# shellcheck shell=bash
#
# lib.sh
#
# Shared helpers for the test/test-*.sh scripts. Source it, do not execute it.
# Every test script is self-contained and runs locally as well as in ci.yml:
#
#   bash test/test-resolve.sh
#
# A script exits non-zero at the first failing assertion, printing the case
# name and what was expected; on success it prints one "ok" line per case.
set -euo pipefail

# shellcheck disable=SC2034  # used by the sourcing test scripts
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

# Never append to a real $GITHUB_OUTPUT by accident when running inside a
# workflow step; cases that inspect outputs pass their own file explicitly.
unset GITHUB_OUTPUT

CASE=""
OUT=""
RC=0

begin() { CASE="$1"; echo "--- $CASE"; }
ok()    { echo "ok   [$CASE]"; }
fail()  { echo "FAIL [$CASE]: $*" >&2; exit 1; }

# run <cmd...>: run a command without aborting on failure; its combined
# stdout/stderr lands in $OUT (and is echoed, indented) and its exit code in $RC.
run() {
  set +e
  OUT="$("$@" 2>&1)"
  RC=$?
  set -e
  if [[ -n "$OUT" ]]; then
    printf '%s\n' "$OUT" | sed 's/^/    /'
  fi
}
expect_success() { run "$@"; [[ "$RC" -eq 0 ]] || fail "exit code $RC from: $*"; }
expect_failure() { run "$@"; [[ "$RC" -ne 0 ]] || fail "expected a failure from: $*"; }

assert_eq()           { [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"; }
assert_contains()     { [[ "$1" == *"$2"* ]] || fail "output does not contain '$2'"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] || fail "output unexpectedly contains '$2'"; }
assert_match()        { [[ "$1" =~ $2 ]] || fail "'$1' does not match /$2/"; }
assert_file()         { [[ -f "$1" ]] || fail "expected file '$1'"; }
assert_missing()      { [[ ! -e "$1" ]] || fail "expected '$1' not to exist"; }

# output_value <github-output-file> <key>: last value written for <key>.
output_value() { sed -n "s/^$2=//p" "$1" | tail -n 1; }
