#!/usr/bin/env bash
#
# Unit tests for scripts/colcon-build.sh argument handling, with stub colcon,
# rosdep and apt-get commands on PATH so no ROS installation is needed.
#
#   colcon   test/stub-colcon.sh: answers `colcon list`, records other args.
#   rosdep   records the arguments of `rosdep install` in $ROSDEP_ARGS_OUT.
#   apt-get  no-op.
# shellcheck source=test/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT"

BUILD=scripts/colcon-build.sh
STUB="$TEST_TMP/stub-bin"
mkdir -p "$STUB"
cp test/stub-colcon.sh "$STUB/colcon"
cat > "$STUB/rosdep" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "install" && -n "${ROSDEP_ARGS_OUT:-}" ]]; then
  shift
  printf '%s\n' "$@" > "$ROSDEP_ARGS_OUT"
fi
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/apt-get"
chmod +x "$STUB"/*
export PATH="$STUB:$PATH"
export ROS_ABI_ROSDEP_SKIP_KEYS=

# The scripts are run from a fresh workspace-less directory unless a case
# provides WORKSPACE, so UPSTREAM_DIR (src/upstream) does not exist.
export WORKSPACE="$TEST_TMP/nows"
mkdir -p "$WORKSPACE"

# Recorded colcon args as one space-separated line (a trailing space ends the
# last argument, so patterns can anchor on it).
colcon_args() { tr '\n' ' ' < "$1"; }

begin "single package is passed through unchanged"
args="$TEST_TMP/args-single.txt"
expect_success env COLCON_ARGS_OUT="$args" PACKAGE=rclcpp bash "$BUILD"
# --packages-up-to must be followed by exactly the one package and then the next flag.
assert_contains "$(colcon_args "$args")" '--packages-up-to rclcpp --event-handlers '
assert_contains "$(colcon_args "$args")" '--cmake-args -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=OFF -DCMAKE_C_FLAGS=-g -Og -DCMAKE_CXX_FLAGS=-g -Og '
ok

begin "space-separated list expands to multiple --packages-up-to names"
args="$TEST_TMP/args-multi.txt"
# The input deliberately has a double space; an unsplit single argument would
# keep it and fail to match this single-spaced pattern.
expect_success env COLCON_ARGS_OUT="$args" \
  PACKAGE='rclcpp  rclcpp_action rclcpp_components rclcpp_lifecycle' bash "$BUILD"
assert_contains "$(colcon_args "$args")" \
  '--packages-up-to rclcpp rclcpp_action rclcpp_components rclcpp_lifecycle --event-handlers '
ok

begin "whitespace-only package list fails"
expect_failure env COLCON_ARGS_OUT="$TEST_TMP/args-empty.txt" PACKAGE='   ' bash "$BUILD"
ok

begin "ROS_ABI_UNDERLAY is sourced ahead of /opt/ros when present"
underlay="$TEST_TMP/underlay/setup.bash"
mkdir -p "$(dirname "$underlay")"
echo 'export ROS_ABI_TEST_UNDERLAY_SOURCED=1' > "$underlay"
expect_success env COLCON_ARGS_OUT="$TEST_TMP/args-underlay.txt" PACKAGE=rclcpp \
  ROS_ABI_UNDERLAY="$underlay" bash "$BUILD"
assert_contains "$OUT" "Sourced ROS environment: $underlay"
ok

begin "rosdep is restricted to the build closure and gets the skip keys"
expect_success bash test/incremental-ws-fixture.sh "$TEST_TMP/incr"
INCR_WS="$TEST_TMP/incr/ws"
rosdep_args="$TEST_TMP/rosdep-args.txt"
expect_success env COLCON_ARGS_OUT="$TEST_TMP/args-rosdep.txt" ROSDEP_ARGS_OUT="$rosdep_args" \
  WORKSPACE="$INCR_WS" PACKAGE=target ROS_DISTRO=kilted ROSDEP_SKIP_KEYS='fastcdr urdfdom_headers' \
  AMENT_PREFIX_PATH= COLCON_PREFIX_PATH= bash "$BUILD"
recorded="$(colcon_args "$rosdep_args")"
assert_contains "$recorded" '--from-paths '
# The stub knows no dependencies, so the "closure" is every package path.
for p in src/pkg/target src/upstream/x/depx src/upstream/y/depy src/upstream/z/depz; do
  assert_contains "$recorded" " $p "
done
assert_contains "$recorded" ' --ignore-src -y -r --rosdistro kilted --skip-keys fastcdr urdfdom_headers '
ok

begin "incremental source build restricts with --packages-above and skips DDS vendors"
args="$TEST_TMP/args-above.txt"
# target: repo under test; depx: moved upstream; depz: upstream but not in the
# underlay; depy: unchanged and in the underlay -> omitted.
expect_success env COLCON_ARGS_OUT="$args" WORKSPACE="$INCR_WS" PACKAGE=target \
  AMENT_PREFIX_PATH="$TEST_TMP/incr/prefix" COLCON_PREFIX_PATH= \
  REBUILD_PATHS="$INCR_WS/src/upstream/x" bash "$BUILD"
assert_contains "$OUT" "Incremental source build: rebuilding 3 package(s)"
assert_contains "$(colcon_args "$args")" \
  '--packages-up-to target --packages-above depx depz target --packages-skip-regex ^(fastrtps|fastcdr|foonathan_memory_vendor|cyclonedds|iceoryx_.*)$ --event-handlers '
ok

begin "a plain CMake package in the colcon prefix counts as provided by the underlay"
args="$TEST_TMP/args-colcon-prefix.txt"
# prefix-colcon provides depz only (isolated layout: <prefix>/<package>/).
expect_success env COLCON_ARGS_OUT="$args" WORKSPACE="$INCR_WS" PACKAGE=target \
  AMENT_PREFIX_PATH="$TEST_TMP/incr/prefix" COLCON_PREFIX_PATH="$TEST_TMP/incr/prefix-colcon" \
  REBUILD_PATHS="$INCR_WS/src/upstream/x" bash "$BUILD"
assert_contains "$(colcon_args "$args")" '--packages-above depx target --packages-skip-regex '
ok

begin "an explicit empty PACKAGES_SKIP_REGEX disables the default"
args="$TEST_TMP/args-noskip.txt"
expect_success env COLCON_ARGS_OUT="$args" WORKSPACE="$INCR_WS" PACKAGE=target \
  AMENT_PREFIX_PATH="$TEST_TMP/incr/prefix" COLCON_PREFIX_PATH= PACKAGES_SKIP_REGEX= bash "$BUILD"
assert_contains "$(colcon_args "$args")" '--packages-above depx depz target --event-handlers '
ok

begin "scratch strategy ignores the underlay, applies no filter, forwards the skip regex"
args="$TEST_TMP/args-scratch.txt"
expect_success env COLCON_ARGS_OUT="$args" WORKSPACE="$INCR_WS" PACKAGE=target \
  SOURCE_STRATEGY=scratch PACKAGES_SKIP_REGEX='^(fastrtps|fastcdr)$' \
  ROS_ABI_UNDERLAY="$underlay" bash "$BUILD"
# The image underlay must not be sourced in a scratch build.
assert_not_contains "$OUT" "Sourced ROS environment: $underlay"
assert_contains "$OUT" "Scratch source build"
assert_contains "$(colcon_args "$args")" \
  '--packages-up-to target --packages-skip-regex ^(fastrtps|fastcdr)$ --event-handlers '
ok

begin "scratch strategy without an explicit regex skips nothing"
args="$TEST_TMP/args-scratch-default.txt"
expect_success env COLCON_ARGS_OUT="$args" WORKSPACE="$INCR_WS" PACKAGE=target \
  SOURCE_STRATEGY=scratch bash "$BUILD"
assert_contains "$(colcon_args "$args")" '--packages-up-to target --event-handlers '
ok
