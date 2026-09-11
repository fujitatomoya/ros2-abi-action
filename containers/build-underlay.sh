#!/usr/bin/env bash
#
# build-underlay.sh
#
# "Build the code in the workspace" step of containers/source.Dockerfile: a
# colcon build of everything under <workspace>/src with the same CMake flags
# the action uses for the packages under test (scripts/abi-build-flags.sh),
# followed by containers/finalize-source-image.sh (verification, missing.txt,
# cleanup).
#
# DEVIATION from the documented `colcon build --symlink-install --mixin release`:
#   * Debug -g -Og and BUILD_TESTING=OFF (see abi-build-flags.sh);
#   * no --symlink-install, since src/ is removed by the finalize step;
#   * --continue-on-error: one broken upstream package must not sink the
#     nightly image; colcon-build.sh rebuilds any package the underlay lacks,
#     and the missing ones are listed in missing.txt for diagnosis;
#   * --parallel-workers (PARALLEL_WORKERS, default 2) bounds peak memory on
#     4-vCPU hosted runners; raise it for local builds.
# Nothing is sourced before the build, as the documentation requires.
#
# Also exercised by the source-toolchain job in ci.yml on every base image
# with a one-package workspace.
#
# Usage: build-underlay.sh [workspace-root]   (default: /opt/ros2_ws)
# Environment: PARALLEL_WORKERS (default 2)
set -euo pipefail

ws="${1:-/opt/ros2_ws}"
workers="${PARALLEL_WORKERS:-2}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The image mirrors the repository layout under /opt/ros-abi, so the flags
# file is always one directory up in scripts/.
# shellcheck source=scripts/abi-build-flags.sh
source "$here/../scripts/abi-build-flags.sh"

cd "$ws"
colcon build \
    --base-paths src \
    --continue-on-error \
    --parallel-workers "$workers" \
    --event-handlers console_cohesion+ \
    --cmake-args "${ABI_CMAKE_ARGS[@]}" \
  || echo "WARNING: some packages failed to build; see missing.txt in $ws"

bash "$here/finalize-source-image.sh" "$ws"
