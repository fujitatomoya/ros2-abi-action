#!/usr/bin/env bash
#
# Create local git repositories, a manifest and a snapshot for testing
# scripts/sync-upstream.py without network access.
#
# Layout under $1:
#   a/unchanged.git   head == snapshot                      -> imported, not rebuilt
#   a/moved.git       advanced after the snapshot           -> imported, rebuilt
#   a/fresh.git       not in the snapshot                   -> imported, rebuilt
#   a/related.git     has refs/pull/7/merge                 -> related PR, rebuilt
#   a/dup.git         provides package "pkg_under_test"     -> dropped (duplicate)
#   a/does-not-exist  referenced by the manifest, missing   -> warning, skipped
#   ros2/undertest    the repository under test (GitHub URL in the manifest)
#   b/outside.git     related PR outside the manifest, refs/pull/3/head only
#   ws/src/pkg        checkout of the repository under test
#   manifest.repos, snapshot.repos
set -euo pipefail

root="${1:?usage: $0 <dir>}"
mkdir -p "$root/a" "$root/b" "$root/ros2" "$root/ws/src"
cd "$root"

export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
# Ignore the developer's git configuration (commit signing, hooks, default
# branch) so the fixture builds the same everywhere.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# make_repo <bare-path> <work-path> [package-name]
make_repo() {
  local bare="$1" work="$2" pkg="${3:-}"
  git init -q --bare "$bare"
  git init -q "$work"
  (
    cd "$work"
    git checkout -q -b rolling
    echo one > f
    if [[ -n "$pkg" ]]; then
      printf '<?xml version="1.0"?>\n<package format="3">\n  <name>%s</name>\n</package>\n' "$pkg" > package.xml
    fi
    git add .
    git commit -qm one
    git remote add origin "$bare"
    git push -q origin rolling
  )
}

make_repo "$root/a/unchanged.git" unchanged-work
make_repo "$root/a/moved.git"     moved-work
make_repo "$root/a/fresh.git"     fresh-work
make_repo "$root/a/related.git"   related-work
make_repo "$root/a/dup.git"       dup-work       pkg_under_test
make_repo "$root/ros2/undertest.git" undertest-work pkg_under_test
make_repo "$root/b/outside.git"   outside-work

snap_unchanged=$(git -C unchanged-work rev-parse HEAD)
snap_moved=$(git -C moved-work rev-parse HEAD)
snap_related=$(git -C related-work rev-parse HEAD)
snap_undertest=$(git -C undertest-work rev-parse HEAD)

# "moved" advances after the snapshot.
( cd moved-work && echo two > f && git commit -qam two && git push -q origin rolling )

# "related" gets a pull request merge ref (what GitHub exposes for open PRs).
( cd related-work && git checkout -q -b pr && echo pr-merge > f && git commit -qam pr \
  && git push -q origin "pr:refs/pull/7/merge" )

# "outside" gets only a head ref, to exercise the merge -> head fallback.
( cd outside-work && git checkout -q -b pr && echo pr-head > f && git commit -qam pr \
  && git push -q origin "pr:refs/pull/3/head" )

# The repository under test as the workflow checks it out.
cp -r undertest-work ws/src/pkg

cat > manifest.repos <<EOF
repositories:
  a/unchanged:
    type: git
    url: $root/a/unchanged.git
    version: rolling
  a/moved:
    type: git
    url: $root/a/moved.git
    version: rolling
  a/fresh:
    type: git
    url: $root/a/fresh.git
    version: rolling
  a/related:
    type: git
    url: $root/a/related.git
    version: rolling
  a/dup:
    type: git
    url: $root/a/dup.git
    version: rolling
  a/gone:
    type: git
    url: $root/a/does-not-exist.git
    version: rolling
  ros2/undertest:
    type: git
    url: https://github.com/ros2/undertest.git
    version: rolling
EOF

cat > snapshot.repos <<EOF
repositories:
  a/unchanged:
    type: git
    url: x
    version: $snap_unchanged
  a/moved:
    type: git
    url: x
    version: $snap_moved
  a/related:
    type: git
    url: x
    version: $snap_related
  ros2/undertest:
    type: git
    url: x
    version: $snap_undertest
EOF

echo "Fixture created under $root"
