#!/usr/bin/env bash
#
# Smoke test of the source-image toolchain: containers/build-underlay.sh (and
# through it containers/finalize-source-image.sh) on a one-file plain CMake
# package, exactly as containers/source.Dockerfile runs them, and
# containers/install-rosdeps.sh on a manifest that depends on a ROS package
# outside the workspace. ci.yml executes this on every base image of the
# source images after containers/install-ros-apt-source.sh and ros-dev-tools,
# so toolchain drift on a new Ubuntu release (Python, EmPy, colcon, coreutils,
# the ros-<distro>-* archive) is caught in minutes instead of in the nightly
# image build. Requires colcon and a C compiler; the rosdep case additionally
# needs rosdep, root (apt) and ROS_DISTRO, and is skipped otherwise.
# shellcheck source=test/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT"

command -v colcon >/dev/null || { echo "ERROR: colcon is required for this test." >&2; exit 1; }
echo "colcon: $(colcon --log-base /dev/null version-check 2>/dev/null | head -1 || true)"
python3 --version
# Ubuntu 26.04 ships the Rust uutils coreutils; record which one we got.
sort --version | head -1

WS="$TEST_TMP/ws"
mkdir -p "$WS/src"
cp -r test/fixtures/cmake-smoke-pkg "$WS/src/"

begin "build-underlay.sh builds and finalizes a one-package workspace"
expect_success env PARALLEL_WORKERS=2 bash containers/build-underlay.sh "$WS"
assert_contains "$OUT" "Packages not built: 0"
assert_contains "$OUT" "Source underlay finalized in $WS"
assert_file "$WS/install/setup.bash"
assert_file "$WS/install/abi_smoke/lib/libabi_smoke.so"
assert_missing "$WS/src"
assert_missing "$WS/build"
assert_missing "$WS/log"
assert_eq "$(cat "$WS/missing.txt")" ""
ok

begin "the underlay is sourceable the way colcon-build.sh does it"
# abi_smoke is a plain CMake package, so only colcon's own variables are set
# (AMENT_PREFIX_PATH is exported by ament packages only).
# shellcheck disable=SC2016  # $0 is expanded by the inner bash, on purpose
expect_success bash -c 'set +u; source "$0/install/setup.bash"; set -u
  echo "COLCON_PREFIX_PATH=$COLCON_PREFIX_PATH"
  echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}"
  [[ "$COLCON_PREFIX_PATH" == "$0/install"* ]]
  [[ "${LD_LIBRARY_PATH:-}" == *abi_smoke/lib* ]]' "$WS"
ok

begin "finalize lists packages the build did not produce"
WS2="$TEST_TMP/ws2"
mkdir -p "$WS2/src/ghost" "$WS2/install"
cp -r test/fixtures/cmake-smoke-pkg "$WS2/src/"
# A second, complete manifest (colcon ignores package.xml files that lack the
# mandatory elements) for a package the "build" never installed.
sed 's|<name>abi_smoke</name>|<name>ghost</name>|' \
  test/fixtures/cmake-smoke-pkg/package.xml > "$WS2/src/ghost/package.xml"
touch "$WS2/install/setup.bash"
mkdir -p "$WS2/install/abi_smoke"
expect_success bash containers/finalize-source-image.sh "$WS2"
assert_contains "$OUT" "Packages not built: 1"
assert_contains "$OUT" "  missing: ghost"
assert_eq "$(cat "$WS2/missing.txt")" "ghost"
ok

begin "finalize fails loudly without install/setup.bash"
WS3="$TEST_TMP/ws3"
mkdir -p "$WS3/src" "$WS3/install"
expect_failure bash containers/finalize-source-image.sh "$WS3"
assert_contains "$OUT" "colcon did not generate install/setup.bash"
ok

begin "install-rosdeps.sh skips a key that resolves to a ros-<distro>-* binary"
if command -v rosdep >/dev/null && [[ "$EUID" -eq 0 && -n "${ROS_DISTRO:-}" ]]; then
  # xacro is released in every distro but not part of ros2.repos: the key
  # must be skipped (on a freshly supported Ubuntu release the package does
  # not even exist), and the step must still succeed.
  WS4="$TEST_TMP/ws4"
  mkdir -p "$WS4/src"
  cp -r test/fixtures/rosdep-smoke-pkg "$WS4/src/"
  expect_success env ROSDEP_SKIP_KEYS='fastcdr urdfdom_headers' \
    bash containers/install-rosdeps.sh "$WS4"
  assert_contains "$OUT" "  skipped: xacro"
  assert_contains "$OUT" "#All required rosdeps installed successfully"
  assert_eq "$(cat "$WS4/skipped-rosdeps.txt")" "xacro"
  if dpkg -s "ros-$ROS_DISTRO-xacro" >/dev/null 2>&1; then
    fail "ros-$ROS_DISTRO-xacro was installed into a source-only environment"
  fi
  ok
else
  echo "skip [$CASE]: needs rosdep, root and ROS_DISTRO"
fi
