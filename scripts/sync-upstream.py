#!/usr/bin/env python3
"""
sync-upstream.py

Populate the colcon workspace with the upstream ROS 2 sources a PR must be
built against, and work out which of them have to be rebuilt.

Source mode (MODE=source) imports the distro manifest (ros2.repos) into DEST,
minus the repository under test, and then:

  * incremental strategy: compares the branch head of every repository
    (`git ls-remote`) against the snapshot the ros-abi:<distro>-source image
    was built from. Repositories that moved are reported in `rebuild-paths`;
    colcon-build.sh turns those into `--packages-above`, so only the changed
    packages, everything downstream of them inside the target closure, and
    the targets themselves are compiled. Unchanged packages come prebuilt from
    the image's underlay.
  * scratch strategy: no snapshot is consulted, everything in the closure is
    built from source (rebuild-paths is left empty and colcon-build.sh applies
    no filter).

Related pull requests (RELATED_PRS, e.g. "ros2/rcl#1234 ros2/rmw#567") are
checked out at refs/pull/N/merge (falling back to refs/pull/N/head when the
merge ref does not exist). A repository that is in the manifest is switched to
that ref in place and always counted as changed; one that is not is cloned into
RELATED_DEST. This works in binary mode too, so downstream packages can build
against an unmerged dependency PR.

Repositories that would duplicate a package already present elsewhere in the
workspace (the repository under test when the check runs in a fork, or a repo
pinned via a .repos file) are removed after import, since colcon refuses
duplicate package names.

Inputs (environment):
  MODE           source | binary (default: source).
  STRATEGY       incremental | scratch (default: incremental; source mode only).
  REPOS_URL      Manifest URL. Default: $ROS_ABI_REPOS_URL, else derived from
                 $ROS_DISTRO as https://raw.githubusercontent.com/ros2/ros2/<distro>/ros2.repos
  REPOS_FILE     Local manifest path; takes precedence over REPOS_URL (tests).
  SNAPSHOT       Snapshot from the image. Default: $ROS_ABI_SNAPSHOT, else
                 /opt/ros2_ws/snapshot.repos. Missing snapshot in incremental
                 mode -> warning and every repository is treated as changed.
  EXCLUDE_REPO   "owner/name" of the repository under test (required).
  WORKSPACE_SRC  Workspace src directory used for duplicate detection
                 (default: parent of DEST).
  DEST           Import directory for manifest repositories (required in
                 source mode), e.g. ws/src/upstream.
  RELATED_PRS    Whitespace-separated "owner/repo#N" references (optional).
  RELATED_DEST   Clone directory for related PRs not in the manifest
                 (default: <WORKSPACE_SRC>/related).
  RELATED_URL_BASE
                 Prefix turning "owner/repo" into a clone URL
                 (default: https://github.com/).
  WORKERS        Parallel git ls-remote workers (default: 16).

Outputs ($GITHUB_OUTPUT when set):
  changed        Number of manifest repositories that moved (or were related).
  rebuild-paths  Space-separated directories whose packages must be rebuilt.
  related        Space-separated "owner/repo#N@sha" that were applied.
"""
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

import yaml

SHA_RE = re.compile(r"^[0-9a-f]{40}$")
PR_REF_RE = re.compile(r"^([\w.-]+/[\w.-]+)#(\d+)$")


def log(msg):
    print(msg, flush=True)


def warn(msg):
    print(f"::warning::{msg}", flush=True)


def fail(msg):
    print(f"::error::{msg}", file=sys.stderr, flush=True)
    sys.exit(1)


def run(cmd, **kw):
    log("+ " + " ".join(cmd))
    return subprocess.run(cmd, check=True, **kw)


# --------------------------------------------------------------------------- #
# Manifest / snapshot handling
# --------------------------------------------------------------------------- #
def load_manifest():
    path = os.environ.get("REPOS_FILE", "")
    if path:
        with open(path, encoding="utf-8") as f:
            return yaml.safe_load(f), path
    url = os.environ.get("REPOS_URL") or os.environ.get("ROS_ABI_REPOS_URL")
    if not url:
        distro = os.environ.get("ROS_DISTRO", "")
        if not distro:
            fail("REPOS_URL is not set and ROS_DISTRO is empty; cannot locate ros2.repos.")
        url = f"https://raw.githubusercontent.com/ros2/ros2/{distro}/ros2.repos"
    try:
        with urllib.request.urlopen(url, timeout=60) as resp:
            return yaml.safe_load(resp.read().decode("utf-8")), url
    except Exception as exc:  # noqa: BLE001 - surface any fetch failure
        fail(f"Failed to fetch manifest {url}: {exc}")


def load_snapshot():
    path = os.environ.get("SNAPSHOT") or os.environ.get("ROS_ABI_SNAPSHOT") or "/opt/ros2_ws/snapshot.repos"
    if not os.path.isfile(path):
        return None, path
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    return data.get("repositories", {}) or {}, path


def normalize_repo(url_or_slug):
    """Reduce a git URL or owner/name slug to lower-case 'owner/name' (or path)."""
    s = url_or_slug.strip()
    s = re.sub(r"^(https?://|git@|ssh://git@|file://)", "", s)
    s = re.sub(r"^github\.com[:/]", "", s)
    s = re.sub(r"\.git$", "", s)
    return s.strip("/").lower()


def matches_slug(url, slug):
    """True when a manifest url refers to owner/name `slug` (also for local paths)."""
    n = normalize_repo(url)
    return n == slug or n.endswith("/" + slug)


def resolve_head(name, entry):
    """Return (name, sha or None, error or None) for a manifest entry."""
    url = entry.get("url", "")
    version = str(entry.get("version", "")).strip()
    if not version:
        return name, None, "manifest entry has no version"
    if SHA_RE.match(version):
        return name, version, None
    refs = [f"refs/heads/{version}", f"refs/tags/{version}^{{}}", f"refs/tags/{version}"]
    try:
        out = subprocess.run(
            ["git", "ls-remote", url, *refs],
            check=True, capture_output=True, text=True, timeout=120,
            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
        ).stdout
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        detail = getattr(exc, "stderr", "") or str(exc)
        return name, None, f"git ls-remote failed: {detail.strip()}"
    found = {}
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) == 2:
            found[parts[1]] = parts[0]
    for ref in refs:  # priority: branch, peeled tag, tag object
        if ref in found:
            return name, found[ref], None
    return name, None, f"ref '{version}' not found on {url}"


# --------------------------------------------------------------------------- #
# Workspace helpers
# --------------------------------------------------------------------------- #
def package_names(root, exclude_dir=None):
    """Names of all colcon/ament packages (package.xml) below root."""
    names = set()
    exclude_dir = os.path.realpath(exclude_dir) if exclude_dir else None
    for dirpath, dirnames, filenames in os.walk(root):
        real = os.path.realpath(dirpath)
        if exclude_dir and (real == exclude_dir or real.startswith(exclude_dir + os.sep)):
            dirnames[:] = []
            continue
        dirnames[:] = [d for d in dirnames if d != ".git"]
        if "COLCON_IGNORE" in filenames or "AMENT_IGNORE" in filenames:
            dirnames[:] = []
            continue
        if "package.xml" in filenames:
            try:
                name = ET.parse(os.path.join(dirpath, "package.xml")).getroot().findtext("name")
                if name:
                    names.add(name.strip())
            except ET.ParseError:
                pass
    return names


def checkout_pull_request(repo_dir, number):
    """Check out refs/pull/<n>/merge (or /head) in repo_dir; return the sha."""
    for ref in (f"pull/{number}/merge", f"pull/{number}/head"):
        try:
            run(["git", "-C", repo_dir, "fetch", "--depth", "1", "origin", ref],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            continue
        run(["git", "-C", repo_dir, "checkout", "-q", "FETCH_HEAD"])
        sha = subprocess.run(["git", "-C", repo_dir, "rev-parse", "HEAD"],
                             check=True, capture_output=True, text=True).stdout.strip()
        log(f"  checked out {ref} -> {sha[:10]} in {repo_dir}")
        return sha
    fail(f"Pull request #{number} has neither a merge nor a head ref in {repo_dir}; "
         "does the PR exist and is it open?")


def parse_related():
    refs = []
    for token in os.environ.get("RELATED_PRS", "").split():
        m = PR_REF_RE.match(token)
        if not m:
            fail(f"Invalid related PR reference '{token}'; expected owner/repo#N.")
        slug, number = m.group(1).lower(), int(m.group(2))
        if (slug, number) not in refs:
            refs.append((slug, number))
    return refs


def write_outputs(changed, rebuild_paths, related):
    out = os.environ.get("GITHUB_OUTPUT")
    if not out:
        return
    with open(out, "a", encoding="utf-8") as f:
        f.write(f"changed={changed}\n")
        f.write(f"rebuild-paths={' '.join(rebuild_paths)}\n")
        f.write(f"related={' '.join(related)}\n")


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def main():
    mode = os.environ.get("MODE", "source").lower()
    strategy = os.environ.get("STRATEGY", "incremental").lower()
    if mode not in ("source", "binary"):
        fail(f"MODE must be source or binary, got '{mode}'.")
    if strategy not in ("incremental", "scratch"):
        fail(f"STRATEGY must be incremental or scratch, got '{strategy}'.")

    exclude = os.environ.get("EXCLUDE_REPO", "").strip().lower()
    if not exclude:
        fail("EXCLUDE_REPO (owner/name of the repository under test) is required.")
    dest = os.environ.get("DEST", "").strip()
    if mode == "source" and not dest:
        fail("DEST (import directory) is required in source mode.")
    ws_src = os.environ.get("WORKSPACE_SRC") or (os.path.dirname(os.path.abspath(dest)) if dest else "")
    related_dest = os.environ.get("RELATED_DEST") or os.path.join(ws_src, "related")
    related_base = os.environ.get("RELATED_URL_BASE", "https://github.com/")
    workers = int(os.environ.get("WORKERS", "16"))

    related = parse_related()
    for slug, number in related:
        if slug == exclude:
            fail(f"Related PR {slug}#{number} points at the repository under test itself.")

    rebuild_paths = []
    applied = []
    changed_count = 0

    if mode == "source":
        manifest, manifest_src = load_manifest()
        manifest_repos = {
            n: e for n, e in ((manifest or {}).get("repositories", {}) or {}).items()
            if (e or {}).get("type", "git") == "git"
        }
        log(f"Manifest: {manifest_src} ({len(manifest_repos)} repositories)")

        # Existing workspace packages (repo under test, .repos imports, ...).
        os.makedirs(dest, exist_ok=True)
        present = package_names(ws_src, exclude_dir=dest) if ws_src else set()

        # ---- decide what to import -------------------------------------------
        to_import = {}
        for name, entry in manifest_repos.items():
            if matches_slug(entry.get("url", ""), exclude):
                log(f"  skip   {name} (repository under test, checked out by the workflow)")
                continue
            to_import[name] = entry

        # ---- decide what changed ---------------------------------------------
        changed = set()
        if strategy == "scratch":
            log("Strategy: scratch -> every package in the closure is built from source.")
        else:
            snapshot, snapshot_path = load_snapshot()
            if snapshot is None:
                warn(f"Snapshot {snapshot_path} not found; treating every repository as changed "
                     "(equivalent to a scratch build).")
                changed = set(to_import)
            else:
                log(f"Snapshot: {snapshot_path} ({len(snapshot)} repositories)")
                with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
                    results = list(pool.map(lambda kv: resolve_head(*kv), to_import.items()))
                for name, sha, err in results:
                    if err:
                        # Unreachable: leave it out of the import so vcs does
                        # not fail on it; the underlay copy is used instead.
                        warn(f"{name}: {err}; keeping the underlay version.")
                        to_import.pop(name)
                        continue
                    snap = (snapshot.get(name) or {}).get("version")
                    if snap is None:
                        log(f"  new    {name} @ {sha[:10]} (not in snapshot)")
                        changed.add(name)
                    elif str(snap) != sha:
                        log(f"  moved  {name} {str(snap)[:10]} -> {sha[:10]}")
                        changed.add(name)

        # ---- import ----------------------------------------------------------
        with tempfile.NamedTemporaryFile("w", suffix=".repos", delete=False, encoding="utf-8") as tmp:
            yaml.safe_dump({"repositories": to_import}, tmp, default_flow_style=False)
            import_file = tmp.name
        run(["vcs", "import", "--shallow", "--retry", "3", "--input", import_file, dest],
            stdout=subprocess.DEVNULL)

        # ---- drop imported repos that duplicate packages already present ------
        for name in sorted(to_import):
            repo_dir = os.path.join(dest, name)
            if not os.path.isdir(repo_dir):
                continue
            dup = package_names(repo_dir) & present
            if dup:
                log(f"  drop   {name}: duplicates workspace package(s) {', '.join(sorted(dup))}")
                shutil.rmtree(repo_dir)
                changed.discard(name)
                to_import.pop(name)

        # ---- related PRs whose repository is in the manifest -----------------
        for slug, number in list(related):
            hits = [n for n, e in to_import.items() if matches_slug(e.get("url", ""), slug)]
            if not hits:
                continue
            for name in hits:
                sha = checkout_pull_request(os.path.join(dest, name), number)
                applied.append(f"{slug}#{number}@{sha}")
                changed.add(name)
            related.remove((slug, number))

        for name in sorted(changed):
            rebuild_paths.append(os.path.abspath(os.path.join(dest, name)))
        changed_count = len(changed)
        if strategy == "incremental":
            log(f"{changed_count} of {len(to_import)} repositories need rebuilding.")

    # ---- related PRs outside the manifest (or binary mode) -------------------
    for slug, number in related:
        url = f"{related_base}{slug}.git"
        repo_dir = os.path.join(related_dest, slug.split("/")[1])
        if os.path.exists(repo_dir):
            fail(f"{repo_dir} already exists; cannot clone related PR {slug}#{number}.")
        os.makedirs(related_dest, exist_ok=True)
        log(f"Related PR {slug}#{number} is not in the manifest; cloning {url}")
        run(["git", "clone", "-q", "--depth", "1", url, repo_dir])
        sha = checkout_pull_request(repo_dir, number)
        applied.append(f"{slug}#{number}@{sha}")

    if applied:
        log("Related pull requests applied: " + ", ".join(applied))
    write_outputs(changed_count, rebuild_paths, applied)


if __name__ == "__main__":
    main()
