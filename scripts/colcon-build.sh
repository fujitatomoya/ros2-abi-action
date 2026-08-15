#!/usr/bin/env bash
#
# colcon-build.sh
#
# Build a single colcon package (and everything it depends on) with debug info,
# so that libabigail's abidiff has rich DWARF to compare. Intended to run inside
# a ROS 2 container with a binary underlay (ros:<distro> or the ros-abi images);
# missing dependencies are installed via rosdep before the build.
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

# Install any package dependencies that are not already present in the image.
# This runs BEFORE sourcing the underlay: on images without a prebuilt ROS
# install (or with a partial one), rosdep installs the binary underlay into
# /opt/ros/<distro>, which the sourcing step below then picks up. Official
# Docker library images purge /var/lib/apt/lists at build time, so apt-get
# update is required for any apt-backed install to succeed.
if command -v rosdep >/dev/null 2>&1; then
  apt-get update || \
    echo "::warning::apt-get update failed; rosdep install may not resolve packages."
  rosdep update --rosdistro "${ROS_DISTRO:-rolling}" || \
    echo "::warning::rosdep update failed; continuing with the image's cached state."
  # A failure here means missing build dependencies, which the colcon build
  # below cannot recover from, so fail fast at the actual cause. -r still lets
  # rosdep continue past individually unresolvable keys.
  rosdep install --from-paths src --ignore-src -y -r \
    --rosdistro "${ROS_DISTRO:-rolling}"
fi

# Source whichever ROS environment is available in the container: the binary
# underlay under /opt/ros (possibly just installed by rosdep above) or a
# prebuilt source workspace shipped by ros2dev-style images.
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

# Enable ccache when present to speed up warm builds.
CCACHE_ARGS=()
if command -v ccache >/dev/null 2>&1; then
  export CC="${CC:-/usr/lib/ccache/gcc}"
  export CXX="${CXX:-/usr/lib/ccache/g++}"
  CCACHE_ARGS+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
fi

echo "Building package '$PACKAGE' (with up-to dependencies) in $WORKSPACE"
# BUILD_TESTING=OFF: only the shared library matters for the ABI diff, and
# skipping tests avoids requiring every test_depend (ament_lint_*, fixtures).
colcon build \
  --packages-up-to "$PACKAGE" \
  --event-handlers console_direct+ \
  --cmake-args \
    -DCMAKE_BUILD_TYPE=Debug \
    -DBUILD_TESTING=OFF \
    -DCMAKE_C_FLAGS="-g -Og" \
    -DCMAKE_CXX_FLAGS="-g -Og" \
    "${CCACHE_ARGS[@]}"

echo "colcon build for '$PACKAGE' completed."
