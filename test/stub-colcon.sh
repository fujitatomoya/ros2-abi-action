#!/usr/bin/env bash
#
# Stand-in for colcon used by test/test-colcon-build.sh on machines without a
# ROS installation.
#
#   colcon list [--names-only | --paths-only] --base-paths <dir>...
#               [--packages-up-to <name>...]
#       prints the <name> (or the directory) of every package.xml below the
#       given base paths. --packages-up-to is accepted and ignored: the stub
#       knows no dependencies, so the "closure" is every package it finds.
#   colcon <anything else>
#       records its arguments, one per line, in $COLCON_ARGS_OUT.
set -euo pipefail

if [[ "${1:-}" == "list" ]]; then
  shift
  mode=names
  paths=()
  option=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --names-only) mode=names ;;
      --paths-only) mode=paths ;;
      --base-paths|--packages-up-to) option="$1" ;;
      --*) option="" ;;
      *) if [[ "$option" == "--base-paths" ]]; then paths+=("$1"); fi ;;
    esac
    shift
  done
  [[ "${#paths[@]}" -eq 0 ]] && exit 0
  if [[ "$mode" == "paths" ]]; then
    find "${paths[@]}" -name package.xml -printf '%h\n'
  else
    find "${paths[@]}" -name package.xml -exec \
      sed -n 's:.*<name>\(.*\)</name>.*:\1:p' {} +
  fi
  exit 0
fi

printf '%s\n' "$@" > "${COLCON_ARGS_OUT:?COLCON_ARGS_OUT must be set}"
