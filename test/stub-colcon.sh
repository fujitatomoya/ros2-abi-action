#!/usr/bin/env bash
#
# Stand-in for colcon used by the ci.yml unit tests of scripts/colcon-build.sh
# on runners without a ROS installation.
#
#   colcon list --names-only --base-paths <dir>...
#       prints the <name> of every package.xml below the given directories.
#   colcon <anything else>
#       records its arguments, one per line, in $COLCON_ARGS_OUT.
set -euo pipefail

if [[ "${1:-}" == "list" ]]; then
  shift
  paths=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --names-only|--base-paths) ;;
      *) paths+=("$1") ;;
    esac
    shift
  done
  [[ "${#paths[@]}" -eq 0 ]] && exit 0
  find "${paths[@]}" -name package.xml -exec \
    sed -n 's:.*<name>\(.*\)</name>.*:\1:p' {} +
  exit 0
fi

printf '%s\n' "$@" > "${COLCON_ARGS_OUT:?COLCON_ARGS_OUT must be set}"
