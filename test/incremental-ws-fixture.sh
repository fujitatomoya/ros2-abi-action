#!/usr/bin/env bash
#
# Build a tiny colcon workspace layout for testing the incremental package
# selection in scripts/colcon-build.sh (used together with test/stub-colcon.sh).
#
#   $1/ws/src/pkg/target          repository under test (package "target")
#   $1/ws/src/upstream/x/depx     upstream repo that moved       (REBUILD_PATHS)
#   $1/ws/src/upstream/y/depy     upstream repo, unchanged, in the underlay
#   $1/ws/src/upstream/z/depz     upstream repo, unchanged, NOT in the underlay
#   $1/prefix                     fake ament prefix providing only "depy"
#   $1/prefix-colcon              fake colcon prefix (isolated layout) providing
#                                 only "depz", as a plain CMake package would
set -euo pipefail

root="${1:?usage: $0 <dir>}"
mkdir -p "$root/ws/src/pkg/target" \
         "$root/ws/src/upstream/x/depx" \
         "$root/ws/src/upstream/y/depy" \
         "$root/ws/src/upstream/z/depz" \
         "$root/prefix/share/ament_index/resource_index/packages" \
         "$root/prefix-colcon/depz"

for p in target depx depy depz; do
  dir="$(find "$root/ws/src" -type d -name "$p")"
  printf '<?xml version="1.0"?>\n<package format="3">\n  <name>%s</name>\n</package>\n' "$p" \
    > "$dir/package.xml"
done

touch "$root/prefix/share/ament_index/resource_index/packages/depy"
echo "Fixture workspace created under $root"
