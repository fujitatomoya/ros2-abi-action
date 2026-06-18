#!/usr/bin/env bash
#
# locate-library.sh
#
# Locate one or more shared libraries matching a soname glob under a search
# directory. Used in two places:
#   * the build job, to copy the freshly built library/libraries into an
#     artifact directory;
#   * the collect job, to expand the soname glob into a JSON matrix so the diff
#     job can run once per matched library.
#
# Inputs (environment):
#   SONAME      Library file name or glob, e.g. "librclcpp.so" or "lib*.so" (required).
#   SEARCH_DIR  Directory to search recursively (default: ./install).
#   MODE        "paths" (default) prints matched absolute paths, one per line.
#               "json"  prints a JSON array of basenames (for matrix expansion).
#   COPY_TO     When set (paths mode), matched files are also copied here.
#
# Exits non-zero if no library matches the glob.
#
set -euo pipefail

SONAME="${SONAME:?SONAME is required}"
SEARCH_DIR="${SEARCH_DIR:-./install}"
MODE="${MODE:-paths}"
COPY_TO="${COPY_TO:-}"

if [[ ! -d "$SEARCH_DIR" ]]; then
  echo "::error::Search directory '$SEARCH_DIR' does not exist." >&2
  exit 1
fi

# Collect matches. -name accepts shell globs, so SONAME may contain '*'.
mapfile -t matches < <(find "$SEARCH_DIR" -type f -name "$SONAME" 2>/dev/null | sort -u)

if [[ "${#matches[@]}" -eq 0 ]]; then
  echo "::error::No library matching '$SONAME' found under '$SEARCH_DIR'." >&2
  exit 1
fi

if [[ "$MODE" == "json" ]]; then
  # Emit a JSON array of unique basenames for use as a GitHub Actions matrix.
  mapfile -t names < <(for m in "${matches[@]}"; do basename "$m"; done | sort -u)
  printf '['
  for i in "${!names[@]}"; do
    [[ "$i" -gt 0 ]] && printf ','
    printf '"%s"' "${names[$i]}"
  done
  printf ']\n'
  exit 0
fi

# paths mode
if [[ -n "$COPY_TO" ]]; then
  mkdir -p "$COPY_TO"
fi
for m in "${matches[@]}"; do
  echo "$m"
  if [[ -n "$COPY_TO" ]]; then
    cp -av "$m" "$COPY_TO/"
  fi
done
