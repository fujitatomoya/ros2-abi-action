#!/usr/bin/env bash
#
# Unit tests for scripts/sync-upstream.py against local git repositories.
# test/sync-upstream-fixture.sh builds a manifest with repositories that are
# unchanged, moved, new, unreachable, the repo under test, one that duplicates
# a workspace package, and one with a pull-request ref; plus a related-PR
# repository outside the manifest. Requires git, vcs (python3-vcstool) and
# python3-yaml.
# shellcheck source=test/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT"

for tool in git vcs; do
  command -v "$tool" >/dev/null || { echo "ERROR: '$tool' is required for this test." >&2; exit 1; }
done

SYNC=scripts/sync-upstream.py
FX="$TEST_TMP/fx"

begin "fixture repositories, manifest and snapshot"
expect_success bash test/sync-upstream-fixture.sh "$FX"
ok

begin "incremental source sync with related PRs"
out="$TEST_TMP/incremental.out"
expect_success env MODE=source STRATEGY=incremental \
  REPOS_FILE="$FX/manifest.repos" SNAPSHOT="$FX/snapshot.repos" \
  EXCLUDE_REPO=ros2/undertest WORKSPACE_SRC="$FX/ws/src" DEST="$FX/ws/src/upstream" \
  RELATED_PRS='a/related#7 b/outside#3' RELATED_URL_BASE="file://$FX/" \
  GITHUB_OUTPUT="$out" python3 "$SYNC"
D="$FX/ws/src/upstream"
assert_eq "$(output_value "$out" changed)" "3"
assert_eq "$(output_value "$out" rebuild-paths)" "$D/a/fresh $D/a/moved $D/a/related"
# Whole manifest imported (minus repo under test, unreachable, duplicate).
for f in unchanged moved fresh related; do assert_file "$D/a/$f/f"; done
assert_eq "$(cat "$D/a/moved/f")" "two"
for gone in ros2 a/gone a/dup; do assert_missing "$D/$gone"; done
# Related PR in the manifest: merge ref checked out in place.
assert_eq "$(cat "$D/a/related/f")" "pr-merge"
# Related PR outside the manifest: cloned, head ref fallback.
assert_eq "$(cat "$FX/ws/src/related/outside/f")" "pr-head"
assert_match "$(output_value "$out" related)" '^a/related#7@[0-9a-f]{40} b/outside#3@[0-9a-f]{40}$'
ok

begin "scratch strategy imports everything and reports no rebuild paths"
# The unreachable repo makes a scratch import fail, as it should (nothing to
# fall back on). Use the manifest without its 4-line entry.
sed '/^  a\/gone:/,+3d' "$FX/manifest.repos" > "$FX/manifest-reachable.repos"
out="$TEST_TMP/scratch.out"
expect_success env MODE=source STRATEGY=scratch \
  REPOS_FILE="$FX/manifest-reachable.repos" \
  EXCLUDE_REPO=ros2/undertest WORKSPACE_SRC="$FX/ws2/src" DEST="$FX/ws2/src/upstream" \
  GITHUB_OUTPUT="$out" python3 "$SYNC"
assert_eq "$(output_value "$out" rebuild-paths)" ""
assert_file "$FX/ws2/src/upstream/a/unchanged/f"
assert_file "$FX/ws2/src/upstream/a/moved/f"
ok

begin "missing snapshot in incremental mode treats everything as changed"
out="$TEST_TMP/nosnap.out"
expect_success env MODE=source STRATEGY=incremental \
  REPOS_FILE="$FX/manifest-reachable.repos" SNAPSHOT="$FX/does-not-exist.repos" \
  EXCLUDE_REPO=ros2/undertest WORKSPACE_SRC="$FX/ws5/src" DEST="$FX/ws5/src/upstream" \
  GITHUB_OUTPUT="$out" python3 "$SYNC"
assert_contains "$OUT" "::warning::Snapshot"
# unchanged, moved, fresh, related and dup (ws5 holds no checkout of the repo
# under test, so nothing is a duplicate); undertest itself is excluded.
assert_eq "$(output_value "$out" changed)" "5"
assert_file "$FX/ws5/src/upstream/a/dup/f"
ok

begin "binary mode applies related PRs only"
expect_success env MODE=binary EXCLUDE_REPO=ros2/undertest WORKSPACE_SRC="$FX/ws3/src" \
  RELATED_PRS='b/outside#3' RELATED_URL_BASE="file://$FX/" python3 "$SYNC"
assert_eq "$(cat "$FX/ws3/src/related/outside/f")" "pr-head"
assert_missing "$FX/ws3/src/upstream"
ok

begin "related PR pointing at the repo under test is rejected"
expect_failure env MODE=binary EXCLUDE_REPO=ros2/undertest WORKSPACE_SRC="$FX/ws4/src" \
  RELATED_PRS='ros2/undertest#5' python3 "$SYNC"
ok

begin "malformed related PR reference is rejected"
expect_failure env MODE=binary EXCLUDE_REPO=ros2/undertest WORKSPACE_SRC="$FX/ws4/src" \
  RELATED_PRS='not-a-ref' python3 "$SYNC"
ok
