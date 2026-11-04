#!/usr/bin/env bash
#
# rosdep-ros-keys.sh
#
# Print the rosdep keys of the packages under the given paths that resolve to
# ros-<distro>-* binary packages, one per line, sorted. Keys satisfied by the
# workspace itself (a package under the paths or in the sourced
# AMENT_PREFIX_PATH, i.e. `rosdep --ignore-src` semantics) are not reported.
#
# A source build (containers/source.Dockerfile, scripts/colcon-build.sh in
# source mode) must not mix binary ROS packages into its workspace: the source
# images deliberately carry no /opt/ros, and on a freshly supported Ubuntu
# release the ros-<distro>-* archive does not even exist yet, so `rosdep
# install` would fail outright on such a key. The callers add the keys printed
# here to `rosdep install --skip-keys`; a package that genuinely needs one of
# them then fails in its own CMake configure step with the package named,
# instead of taking the whole rosdep step down.
#
# Usage: rosdep-ros-keys.sh <path>...     (package.xml trees, as --from-paths)
# Environment: ROS_DISTRO (required)
set -euo pipefail

distro="${ROS_DISTRO:?ROS_DISTRO must be set}"
[[ $# -gt 0 ]] || { echo "usage: $0 <path>..." >&2; exit 2; }

# Captured first so that a failing `rosdep keys` fails this script (a process
# substitution's exit status would go unnoticed under set -e).
keys_output="$(rosdep keys --from-paths "$@" --ignore-src --rosdistro "$distro")"
mapfile -t keys < <(sort -u <<<"$keys_output" | sed '/^$/d')
[[ "${#keys[@]}" -gt 0 ]] || exit 0

# `rosdep resolve` prints, per key, a "#ROSDEP[<key>]" header (only when
# given more than one key), the installer ("#apt", "#pip", ...) and the
# resolved package names on one line. It exits 1 when any key has no rule at
# all; those keys are reported again by `rosdep install` itself, so the exit
# code and stderr are ignored here and only the resolutions are parsed.
{ rosdep resolve --rosdistro "$distro" "${keys[@]}" 2>/dev/null || true; } \
  | awk -v prefix="ros-${distro}-" -v single="${keys[0]}" '
      /^#ROSDEP\[/ { key = substr($0, 9, length($0) - 9); next }
      /^#/ { next }
      {
        if (key == "") key = single
        for (i = 1; i <= NF; i++) if (index($i, prefix) == 1) { print key; break }
      }' \
  | sort -u
