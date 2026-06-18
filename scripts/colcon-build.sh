#!/usr/bin/env bash
#
# colcon-build.sh
#
# Build a single colcon package (and everything it depends on) with debug info,
# so that libabigail's abidiff has rich DWARF to compare. Intended to run inside
# a ROS 2 development container that already has the dependencies installed.
#
# Inputs (environment):
#   PACKAGE     Colcon package name to build (required).
#   WORKSPACE   Colcon workspace root (default: current directory).
#   ROS_DISTRO  ROS distro, used to locate the system setup file (optional;
#               most ROS containers already export it).
#
# The build uses CMAKE_BUILD_TYPE=Debug and "-g -Og" so symbols and DWARF are
# present while keeping the build reasonably fast.
#
set -euo pipefail

PACKAGE="${PACKAGE:?PACKAGE is required}"
WORKSPACE="${WORKSPACE:-$PWD}"

cd "$WORKSPACE"

# Source whichever ROS environment is available in the container. The ros2dev
# images expose the underlay either under /opt/ros or a prebuilt setup_ws.
sourced=""
for candidate in \
  "/opt/ros/${ROS_DISTRO:-}/setup.bash" \
  "/root/setup_ws/install/setup.bash" \
  "/root/ros2_ws/install/setup.bash"; do
  if [[ -n "$candidate" && -f "$candidate" ]]; then
    # shellcheck disable=SC1090
    source "$candidate"
    sourced="$candidate"
    echo "Sourced ROS environment: $candidate"
    break
  fi
done
if [[ -z "$sourced" ]]; then
  echo "::warning::No ROS setup.bash found; relying on the container's default environment."
fi

# Install any package dependencies that are not already present in the image.
# Dependencies are pre-installed in the ros2dev images, so failures here are
# non-fatal (they usually mean rosdep metadata is stale, not that a dep is
# missing) and we let the actual colcon build surface real problems.
if command -v rosdep >/dev/null 2>&1; then
  rosdep update --rosdistro "${ROS_DISTRO:-rolling}" || \
    echo "::warning::rosdep update failed; continuing with the image's cached state."
  rosdep install --from-paths src --ignore-src -y -r \
    --rosdistro "${ROS_DISTRO:-rolling}" || \
    echo "::warning::rosdep install reported issues; continuing to colcon build."
fi

# Enable ccache when present to speed up warm builds.
CCACHE_ARGS=()
if command -v ccache >/dev/null 2>&1; then
  export CC="${CC:-/usr/lib/ccache/gcc}"
  export CXX="${CXX:-/usr/lib/ccache/g++}"
  CCACHE_ARGS+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
fi

echo "Building package '$PACKAGE' (with up-to dependencies) in $WORKSPACE"
colcon build \
  --packages-up-to "$PACKAGE" \
  --event-handlers console_direct+ \
  --cmake-args \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_FLAGS="-g -Og" \
    -DCMAKE_CXX_FLAGS="-g -Og" \
    "${CCACHE_ARGS[@]}"

echo "colcon build for '$PACKAGE' completed."
