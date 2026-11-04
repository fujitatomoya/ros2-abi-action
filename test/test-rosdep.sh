#!/usr/bin/env bash
#
# Unit tests for scripts/rosdep-ros-keys.sh and containers/install-rosdeps.sh
# with the stub rosdep (test/stub-rosdep.sh) and a no-op apt-get on PATH, so no
# ROS installation is needed. test/test-source-toolchain.sh runs the install
# script against a real rosdep on every base image.
# shellcheck source=test/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT"

KEYS=scripts/rosdep-ros-keys.sh
INSTALL=containers/install-rosdeps.sh
STUB="$TEST_TMP/stub-bin"
mkdir -p "$STUB"
cp test/stub-rosdep.sh "$STUB/rosdep"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/apt-get"
chmod +x "$STUB"/*
export PATH="$STUB:$PATH"
export ROS_DISTRO=rolling

WS="$TEST_TMP/ws"
mkdir -p "$WS/src"

begin "keys resolving to ros-<distro>-* binaries are listed, sorted, once"
expect_success env ROSDEP_STUB_KEYS='xacro libssl-dev robot_state_publisher xacro' \
  ROSDEP_STUB_ROS_KEYS='xacro robot_state_publisher' bash "$KEYS" "$WS/src"
assert_eq "$OUT" $'robot_state_publisher\nxacro'
ok

begin "a single key is parsed without the #ROSDEP header"
expect_success env ROSDEP_STUB_KEYS='xacro' ROSDEP_STUB_ROS_KEYS='xacro' bash "$KEYS" "$WS/src"
assert_eq "$OUT" "xacro"
expect_success env ROSDEP_STUB_KEYS='libssl-dev' ROSDEP_STUB_ROS_KEYS='xacro' bash "$KEYS" "$WS/src"
assert_eq "$OUT" ""
ok

begin "a key without any rule does not hide the others"
# rosdep resolve exits 1 for the unknown key; rosdep install reports it again.
expect_success env ROSDEP_STUB_KEYS='nosuchkey xacro' ROSDEP_STUB_ROS_KEYS='xacro' \
  ROSDEP_STUB_UNKNOWN_KEYS='nosuchkey' bash "$KEYS" "$WS/src"
assert_eq "$OUT" "xacro"
ok

begin "no keys at all prints nothing"
expect_success env ROSDEP_STUB_KEYS= bash "$KEYS" "$WS/src"
assert_eq "$OUT" ""
ok

begin "the helper needs ROS_DISTRO and at least one path"
expect_failure env -u ROS_DISTRO bash "$KEYS" "$WS/src"
expect_failure bash "$KEYS"
ok

begin "install-rosdeps.sh skips the ros-<distro>-* keys on top of the documented ones"
args="$TEST_TMP/install-args.txt"
expect_success env ROSDEP_ARGS_OUT="$args" ROSDEP_SKIP_KEYS='fastcdr urdfdom_headers' \
  ROSDEP_STUB_KEYS='xacro fastcdr libssl-dev' ROSDEP_STUB_ROS_KEYS='xacro fastcdr' \
  bash "$INSTALL" "$WS"
# fastcdr is already in the documented list and is not reported twice.
assert_eq "$(cat "$WS/skipped-rosdeps.txt")" "xacro"
assert_contains "$OUT" "WARNING: skipping rosdep keys that resolve to ros-rolling-* binaries"
assert_contains "$OUT" "  skipped: xacro"
assert_eq "$(tr '\n' ' ' < "$args")" \
  '--from-paths src --ignore-src -y --rosdistro rolling --skip-keys fastcdr urdfdom_headers xacro '
ok

begin "install-rosdeps.sh without such keys records an empty list and warns about nothing"
expect_success env ROSDEP_ARGS_OUT="$args" ROSDEP_SKIP_KEYS='fastcdr' \
  ROSDEP_STUB_KEYS='libssl-dev' bash "$INSTALL" "$WS"
assert_file "$WS/skipped-rosdeps.txt"
assert_eq "$(cat "$WS/skipped-rosdeps.txt")" ""
assert_not_contains "$OUT" "WARNING"
assert_eq "$(tr '\n' ' ' < "$args")" \
  '--from-paths src --ignore-src -y --rosdistro rolling --skip-keys fastcdr '
ok

begin "install-rosdeps.sh fails when the helper fails rather than installing blindly"
# A rosdep that cannot even list keys: the helper exits non-zero.
broken="$TEST_TMP/broken-bin"
mkdir -p "$broken"
# $1 is meant for the generated stub, not for this script, hence the single quotes.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\n[[ "$1" == keys ]] && exit 3\nexit 0\n' > "$broken/rosdep"
chmod +x "$broken/rosdep"
expect_failure env PATH="$broken:$PATH" ROSDEP_ARGS_OUT="$TEST_TMP/never.txt" \
  ROSDEP_SKIP_KEYS='fastcdr' bash "$INSTALL" "$WS"
assert_missing "$TEST_TMP/never.txt"
ok
