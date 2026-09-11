#!/usr/bin/env bash
#
# colcon-build.sh
#
# Build one or more colcon packages (and everything they depend on) with debug
# info, so that libabigail's abidiff has rich DWARF to compare. Intended to run
# inside a ROS 2 container with a binary underlay (ros:<distro> or the ros-abi
# images); missing dependencies are installed via rosdep before the build.
#
# Inputs (environment):
#   PACKAGE     Whitespace-separated colcon package name(s) to build (required),
#               e.g. "rclcpp" or "rclcpp rclcpp_action rclcpp_lifecycle". All
#               names are passed to a single --packages-up-to, so colcon builds
#               the union of their dependency closures exactly once.
#   WORKSPACE   Colcon workspace root (default: current directory).
#   ROS_DISTRO  ROS distro, used for rosdep and to locate the system setup
#               file (default: rolling; ROS containers already export it).
#   UNDERLAY_SETUP
#               setup.bash of the underlay to source before building. Defaults
#               to $ROS_ABI_UNDERLAY, which the ros-abi:<distro>-source images
#               set to their prebuilt source workspace. When unset or missing,
#               the usual /opt/ros/<distro>/setup.bash candidates are probed
#               instead. Ignored when SOURCE_STRATEGY=scratch.
#
#   UPSTREAM_DIR
#               Directory (relative to WORKSPACE) holding the manifest
#               repositories imported by sync-upstream.py (default: src/upstream).
#   REBUILD_PATHS
#               Whitespace-separated directories under UPSTREAM_DIR whose
#               packages changed since the underlay was built (output of
#               sync-upstream.py).
#   SOURCE_STRATEGY
#               incremental (default) | scratch. See below.
#   PACKAGES_SKIP_REGEX
#               colcon --packages-skip-regex applied to the build. When the
#               variable is unset, incremental source builds default to
#               DEFAULT_SOURCE_SKIP_REGEX below, which keeps the DDS vendors
#               on the underlay copy even when their repositories moved (a
#               Fast DDS rebuild would dominate the run for no ABI benefit).
#               Set it to an empty string to disable that default.
#   ROSDEP_SKIP_KEYS
#               rosdep --skip-keys; defaults to $ROS_ABI_ROSDEP_SKIP_KEYS, which
#               the source images set to the keys their distro's documentation
#               skips (fastcdr, the RTI Connext key, urdfdom_headers).
#
# Package selection. Every package in the workspace that lies in the targets'
# dependency closure is a candidate; dependencies not present in the workspace
# come from the sourced underlay. When UPSTREAM_DIR exists and the strategy is
# incremental, the candidates are further restricted with --packages-above to
#   * packages outside UPSTREAM_DIR (the repository under test, .repos imports,
#     related PR clones),
#   * packages under REBUILD_PATHS (upstream repositories that moved), and
#   * upstream packages the underlay does not provide,
# plus everything that depends on them. Unchanged upstream packages are then
# taken from the underlay instead of being recompiled. With strategy=scratch
# no such filter is applied and the whole closure is built from source.
#
# The CMake arguments (Debug, -g -Og, BUILD_TESTING=OFF) are shared with the
# source-underlay images through scripts/abi-build-flags.sh.
#
set -euo pipefail

# shellcheck source=scripts/abi-build-flags.sh
source "$(dirname "${BASH_SOURCE[0]}")/abi-build-flags.sh"

# Incremental source builds skip these packages by default (see
# PACKAGES_SKIP_REGEX above). Scratch builds compile them like everything else.
DEFAULT_SOURCE_SKIP_REGEX='^(fastrtps|fastcdr|foonathan_memory_vendor|cyclonedds|iceoryx_.*)$'

PACKAGE="${PACKAGE:?PACKAGE is required}"
WORKSPACE="${WORKSPACE:-$PWD}"
UNDERLAY_SETUP="${UNDERLAY_SETUP:-${ROS_ABI_UNDERLAY:-}}"
UPSTREAM_DIR="${UPSTREAM_DIR:-src/upstream}"
REBUILD_PATHS="${REBUILD_PATHS:-}"
SOURCE_STRATEGY="${SOURCE_STRATEGY:-incremental}"
ROSDEP_SKIP_KEYS="${ROSDEP_SKIP_KEYS:-${ROS_ABI_ROSDEP_SKIP_KEYS:-}}"
ROS_DISTRO="${ROS_DISTRO:-rolling}"

# A scratch source build compiles the whole closure itself and must not see
# the image's prebuilt underlay (the source images carry no /opt/ros either,
# so the probe loop below finds nothing and the build runs in a clean
# environment, as the ROS 2 source-build documentation requires).
if [[ "$SOURCE_STRATEGY" == "scratch" ]]; then
  UNDERLAY_SETUP=""
fi

# Split PACKAGE on whitespace (spaces, tabs, newlines) into individual names.
# Word splitting is intentional here; the names never contain glob characters.
# shellcheck disable=SC2206
PACKAGES=($PACKAGE)
if [[ "${#PACKAGES[@]}" -eq 0 ]]; then
  echo "::error::PACKAGE must contain at least one colcon package name." >&2
  exit 1
fi

cd "$WORKSPACE"

# An incremental source build (manifest imported under UPSTREAM_DIR, underlay
# in use) gets the DDS-vendor skip list unless the caller set the variable,
# even to an empty string.
if [[ -z "${PACKAGES_SKIP_REGEX+set}" && -d "$UPSTREAM_DIR" && "$SOURCE_STRATEGY" != "scratch" ]]; then
  PACKAGES_SKIP_REGEX="$DEFAULT_SOURCE_SKIP_REGEX"
fi
SKIP_ARGS=()
if [[ -n "${PACKAGES_SKIP_REGEX:-}" ]]; then
  SKIP_ARGS=(--packages-skip-regex "$PACKAGES_SKIP_REGEX")
fi

# Install any package dependencies that are not already present in the image.
# This runs BEFORE sourcing the underlay: on images without a prebuilt ROS
# install (or with a partial one), rosdep installs the binary underlay into
# /opt/ros/<distro>, which the sourcing step below then picks up. Official
# Docker library images purge /var/lib/apt/lists at build time, so apt-get
# update is required for any apt-backed install to succeed.
if command -v rosdep >/dev/null 2>&1; then
  apt-get update || \
    echo "::warning::apt-get update failed; rosdep install may not resolve packages."
  rosdep update --rosdistro "$ROS_DISTRO" || \
    echo "::warning::rosdep update failed; continuing with the image's cached state."
  # Restrict rosdep to the packages that will actually be built (the targets'
  # dependency closure within the workspace). Unrelated packages that happen
  # to be in the workspace -- other packages of the repository under test, or
  # imported upstream repositories outside the closure -- would otherwise pull
  # in their own system dependencies for nothing. Fall back to the whole src
  # tree if colcon list is unavailable. The skip regex is deliberately NOT
  # applied here: a skipped package must stay in --from-paths so that
  # --ignore-src keeps treating its key as source-provided instead of
  # resolving it to a ros-<distro>-* binary.
  # shellcheck disable=SC2207
  rosdep_paths=($(colcon list --paths-only --base-paths src \
                    --packages-up-to "${PACKAGES[@]}" 2>/dev/null)) || rosdep_paths=()
  if [[ "${#rosdep_paths[@]}" -eq 0 ]]; then
    rosdep_paths=(src)
  fi
  ROSDEP_SKIP_ARGS=()
  if [[ -n "$ROSDEP_SKIP_KEYS" ]]; then
    ROSDEP_SKIP_ARGS=(--skip-keys "$ROSDEP_SKIP_KEYS")
  fi
  # A failure here means missing build dependencies, which the colcon build
  # below cannot recover from, so fail fast at the actual cause. -r still lets
  # rosdep continue past individually unresolvable keys.
  rosdep install --from-paths "${rosdep_paths[@]}" --ignore-src -y -r \
    --rosdistro "$ROS_DISTRO" "${ROSDEP_SKIP_ARGS[@]}"
fi

# Source whichever ROS environment is available in the container. An explicit
# underlay (ros-abi:<distro>-source images export ROS_ABI_UNDERLAY pointing at
# their source overlay, whose setup chains to /opt/ros/<distro>) takes
# precedence; otherwise probe the binary underlay under /opt/ros (possibly just
# installed by rosdep above) or a prebuilt source workspace shipped by
# ros2dev-style images.
sourced=""
for candidate in \
  "$UNDERLAY_SETUP" \
  "/opt/ros/$ROS_DISTRO/setup.bash" \
  "/root/setup_ws/install/setup.bash" \
  "/root/ros2_ws/install/setup.bash"; do
  if [[ -n "$candidate" && -f "$candidate" ]]; then
    # ROS setup scripts reference variables that may be unset
    # (AMENT_TRACE_SETUP_FILES, COLCON_TRACE, ...), so relax nounset around
    # the source or it aborts under this script's set -u.
    set +u
    # shellcheck disable=SC1090
    source "$candidate"
    set -u
    sourced="$candidate"
    echo "Sourced ROS environment: $candidate"
    break
  fi
done
if [[ -z "$sourced" ]]; then
  echo "::warning::No ROS setup.bash found; relying on the container's default environment."
fi

# Incremental source builds: restrict the build to what actually needs
# recompiling (see the header comment). Everything else in the closure is
# taken from the sourced underlay.
in_underlay() {
  local IFS=: p
  # ament packages register in the ament index of their prefix ...
  for p in ${AMENT_PREFIX_PATH:-}; do
    [[ -f "$p/share/ament_index/resource_index/packages/$1" ]] && return 0
  done
  # ... plain CMake packages only in colcon's own index: a per-package prefix
  # directory (isolated install layout, the default) or a colcon-core marker
  # (merged layout).
  for p in ${COLCON_PREFIX_PATH:-}; do
    [[ -d "$p/$1" || -f "$p/share/colcon-core/packages/$1" ]] && return 0
  done
  return 1
}

ABOVE_ARGS=()
if [[ -d "$UPSTREAM_DIR" && "$SOURCE_STRATEGY" != "scratch" ]]; then
  above_paths=()
  for d in src/*/; do
    d="${d%/}"
    [[ "$(realpath "$d")" == "$(realpath "$UPSTREAM_DIR")" ]] && continue
    above_paths+=("$d")
  done
  for p in $REBUILD_PATHS; do
    [[ -d "$p" ]] && above_paths+=("$p")
  done
  above=()
  if [[ "${#above_paths[@]}" -gt 0 ]]; then
    mapfile -t above < <(colcon list --names-only --base-paths "${above_paths[@]}")
  fi
  # Upstream packages the underlay does not provide have to be built as well,
  # or their dependents would fail to find them.
  mapfile -t upstream_pkgs < <(colcon list --names-only --base-paths "$UPSTREAM_DIR")
  for name in "${upstream_pkgs[@]}"; do
    in_underlay "$name" || above+=("$name")
  done
  if [[ "${#above[@]}" -gt 0 ]]; then
    mapfile -t above < <(printf '%s\n' "${above[@]}" | sort -u)
    ABOVE_ARGS=(--packages-above "${above[@]}")
    echo "Incremental source build: rebuilding ${#above[@]} package(s) and their dependents;" \
         "unchanged upstream packages come from the underlay."
  fi
elif [[ -d "$UPSTREAM_DIR" ]]; then
  echo "Scratch source build: every package in the closure is compiled from source."
fi

# Enable ccache when present to speed up warm builds.
CCACHE_ARGS=()
if command -v ccache >/dev/null 2>&1; then
  export CC="${CC:-/usr/lib/ccache/gcc}"
  export CXX="${CXX:-/usr/lib/ccache/g++}"
  CCACHE_ARGS+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
fi

echo "Building package(s) '${PACKAGES[*]}' (with up-to dependencies) in $WORKSPACE"
colcon build \
  --packages-up-to "${PACKAGES[@]}" \
  "${ABOVE_ARGS[@]}" \
  "${SKIP_ARGS[@]}" \
  --event-handlers console_direct+ \
  --cmake-args "${ABI_CMAKE_ARGS[@]}" "${CCACHE_ARGS[@]}"

echo "colcon build for '${PACKAGES[*]}' completed."
