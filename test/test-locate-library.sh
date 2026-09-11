#!/usr/bin/env bash
#
# Unit tests for scripts/locate-library.sh: only the install prefixes of the
# packages under test are searched, so libraries of dependencies rebuilt in
# the same workspace are not diffed.
# shellcheck source=test/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LOCATE="$REPO_ROOT/scripts/locate-library.sh"
WS="$TEST_TMP/ws"

# A fake isolated install tree: install/<package>/lib/lib<package>.so
for p in rclcpp rclcpp_action rcl; do
  mkdir -p "$WS/install/$p/lib"
  echo "$p" > "$WS/install/$p/lib/lib$p.so"
done
cd "$WS"

begin "explicit SEARCH_DIR: only the listed prefixes are matched"
expect_success env SONAME='lib*.so' MODE=json \
  SEARCH_DIR='install/rclcpp install/rclcpp_action install/does_not_exist' bash "$LOCATE"
assert_contains "$OUT" '["librclcpp.so","librclcpp_action.so"]'
assert_contains "$OUT" "::warning::Search directory 'install/does_not_exist' does not exist"
ok

begin "PACKAGE derives the install prefixes (what the build job passes)"
expect_success env SONAME='lib*.so' MODE=json PACKAGE='rclcpp  rclcpp_action' bash "$LOCATE"
assert_contains "$OUT" '["librclcpp.so","librclcpp_action.so"]'
ok

begin "SEARCH_DIR takes precedence over PACKAGE"
expect_success env SONAME='lib*.so' MODE=json PACKAGE=rclcpp SEARCH_DIR=install/rcl bash "$LOCATE"
assert_contains "$OUT" '["librcl.so"]'
ok

begin "default search dir is the whole install tree"
expect_success env SONAME='lib*.so' MODE=json bash "$LOCATE"
assert_contains "$OUT" '["librcl.so","librclcpp.so","librclcpp_action.so"]'
ok

begin "paths mode prints matches and copies them"
copy="$TEST_TMP/artifacts"
expect_success env SONAME='librclcpp.so' PACKAGE=rclcpp COPY_TO="$copy" bash "$LOCATE"
assert_contains "$OUT" "install/rclcpp/lib/librclcpp.so"
assert_file "$copy/librclcpp.so"
assert_missing "$copy/librcl.so"
ok

begin "no existing search dir fails"
expect_failure env SONAME='lib*.so' SEARCH_DIR='install/nope' bash "$LOCATE"
ok

begin "no matching library fails"
expect_failure env SONAME='libnothing.so' bash "$LOCATE"
ok
