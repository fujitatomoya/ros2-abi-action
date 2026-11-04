#!/usr/bin/env bash
#
# install-rosdeps.sh
#
# "Install dependencies using rosdep" step of containers/source.Dockerfile:
# `rosdep init`, `rosdep update` and `rosdep install --from-paths src
# --ignore-src` with the distro's documented --skip-keys (ROSDEP_SKIP_KEYS,
# from containers/distro-args.sh).
#
# DEVIATION from the documented command: rosdep keys that resolve to
# ros-<distro>-* binary packages are skipped as well. The source images
# deliberately contain no binary ROS 2 installation, and on a freshly
# supported Ubuntu release the ros-<distro>-* archive does not exist at all,
# so such a key -- a package.xml in ros2.repos depending on a ROS package
# outside ros2.repos -- would otherwise fail the whole step and leave the
# nightly image stale (robot_state_publisher's exec_depend on xacro did that
# for a month in October 2026). The skipped keys are printed and recorded in
# <workspace>/skipped-rosdeps.txt, one per line, next to missing.txt; a
# package that genuinely needs one fails in its own CMake configure step with
# the package named, where colcon's --continue-on-error lists it in
# missing.txt.
#
# Also exercised by the source-toolchain job in ci.yml on every base image.
#
# Usage: install-rosdeps.sh [workspace-root]   (default: /opt/ros2_ws)
# Environment: ROS_DISTRO (required), ROSDEP_SKIP_KEYS (documented keys)
set -euo pipefail

ws="${1:-/opt/ros2_ws}"
: "${ROS_DISTRO:?ROS_DISTRO must be set}"
skip_keys="${ROSDEP_SKIP_KEYS:-}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The image mirrors the repository layout under /opt/ros-abi, so the helper
# is always one directory up in scripts/.
ros_keys_script="$here/../scripts/rosdep-ros-keys.sh"

cd "$ws"

apt-get update
# `rosdep init` refuses to run twice; the default sources list is all it writes.
[[ -f /etc/ros/rosdep/sources.list.d/20-default.list ]] || rosdep init
rosdep update --rosdistro "$ROS_DISTRO"

# Keys outside the documented skip list that would pull in ros-<distro>-*
# binaries (see the header). A failure of the helper itself is fatal: a
# silently empty list would reintroduce exactly the failure described above.
ros_keys="$(bash "$ros_keys_script" src)"
grep -vxF -f <(tr ' ' '\n' <<<"$skip_keys" | sed '/^$/d') <<<"$ros_keys" \
  | sed '/^$/d' > skipped-rosdeps.txt || true
if [[ -s skipped-rosdeps.txt ]]; then
  echo "WARNING: skipping rosdep keys that resolve to ros-${ROS_DISTRO}-* binaries" \
       "(the workspace is built from source only; see skipped-rosdeps.txt):"
  sed 's/^/  skipped: /' skipped-rosdeps.txt
fi
# One space-separated word list, as rosdep splits --skip-keys itself.
skip_keys="$(cat <(echo "$skip_keys") skipped-rosdeps.txt | xargs)"

rosdep install --from-paths src --ignore-src -y --rosdistro "$ROS_DISTRO" \
  --skip-keys "$skip_keys"
