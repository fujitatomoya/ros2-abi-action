#!/usr/bin/env bash
#
# Stand-in for rosdep used by test/test-colcon-build.sh and test/test-rosdep.sh
# on machines without a ROS installation. Driven by environment variables:
#
#   rosdep install <args>
#       records its arguments, one per line, in $ROSDEP_ARGS_OUT (when set)
#       and the AMENT_PREFIX_PATH it saw in $ROSDEP_ENV_OUT (when set).
#   rosdep keys <args>
#       prints the keys in $ROSDEP_STUB_KEYS (space separated), one per line;
#       the --from-paths / --ignore-src arguments are accepted and ignored.
#   rosdep resolve [--rosdistro <d>] <key>...
#       prints the real `rosdep resolve` layout: a "#ROSDEP[<key>]" header
#       per key only when more than one key is given, then "#apt" and the
#       package names. Keys in $ROSDEP_STUB_ROS_KEYS resolve to
#       ros-$ROS_DISTRO-<key> (underscores to dashes), keys in
#       $ROSDEP_STUB_UNKNOWN_KEYS have no rule (an error on stderr and exit
#       code 1 at the end, as rosdep does), every other key to lib<key>-dev.
#   rosdep <anything else>  (init, update, ...)
#       no-op.
set -euo pipefail

command="${1:-}"
shift || true

case "$command" in
  install)
    if [[ -n "${ROSDEP_ARGS_OUT:-}" ]]; then
      printf '%s\n' "$@" > "$ROSDEP_ARGS_OUT"
    fi
    if [[ -n "${ROSDEP_ENV_OUT:-}" ]]; then
      printf '%s\n' "${AMENT_PREFIX_PATH:-}" > "$ROSDEP_ENV_OUT"
    fi
    ;;
  keys)
    for key in ${ROSDEP_STUB_KEYS:-}; do
      echo "$key"
    done
    ;;
  resolve)
    keys=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --rosdistro) shift ;;
        --*) ;;
        *) keys+=("$1") ;;
      esac
      shift
    done
    status=0
    for key in "${keys[@]}"; do
      [[ "${#keys[@]}" -gt 1 ]] && echo "#ROSDEP[$key]"
      if [[ " ${ROSDEP_STUB_UNKNOWN_KEYS:-} " == *" $key "* ]]; then
        echo "ERROR: no rosdep rule for '$key'" >&2
        status=1
      elif [[ " ${ROSDEP_STUB_ROS_KEYS:-} " == *" $key "* ]]; then
        echo "#apt"
        echo "ros-${ROS_DISTRO:?}-${key//_/-}"
      else
        echo "#apt"
        echo "lib${key}-dev"
      fi
    done
    exit "$status"
    ;;
  *)
    ;;
esac
