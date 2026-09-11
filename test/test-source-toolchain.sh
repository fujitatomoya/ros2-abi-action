#!/usr/bin/env bash
#
# Smoke test of the source-image toolchain: containers/build-underlay.sh (and
# through it containers/finalize-source-image.sh) on a one-file plain CMake
# package, exactly as containers/source.Dockerfile runs them. ci.yml executes
# this on every base image of the source images after
# containers/install-ros-apt-source.sh and ros-dev-tools, so toolchain drift on
# a new Ubuntu release (Python, EmPy, colcon, coreutils) is caught in minutes
# instead of in the nightly image build. Requires colcon and a C compiler.
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
