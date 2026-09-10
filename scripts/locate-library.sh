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
#   SEARCH_DIR  Whitespace-separated directories to search recursively
#               (default: ./install). The build job passes the install prefixes
#               of the packages under test (install/<package> ...), so that
#               dependencies rebuilt from source in the same workspace are not
#               diffed by accident. Directories that do not exist are skipped
#               with a warning; at least one must exist.
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

# Word splitting is intentional: SEARCH_DIR is a list of directories.
# shellcheck disable=SC2206
search_dirs=($SEARCH_DIR)
existing=()
for d in "${search_dirs[@]}"; do
  if [[ -d "$d" ]]; then
    existing+=("$d")
  else
    echo "::warning::Search directory '$d' does not exist; skipping." >&2
  fi
done
if [[ "${#existing[@]}" -eq 0 ]]; then
  echo "::error::None of the search directories exist: $SEARCH_DIR" >&2
  exit 1
fi

# Collect matches. -name accepts shell globs, so SONAME may contain '*'.
# LC_ALL=C keeps the order byte-wise and therefore locale-independent, so the
# diff matrix is stable across runners.
mapfile -t matches < <(find "${existing[@]}" -type f -name "$SONAME" 2>/dev/null | LC_ALL=C sort -u)

if [[ "${#matches[@]}" -eq 0 ]]; then
  echo "::error::No library matching '$SONAME' found under '$SEARCH_DIR'." >&2
  exit 1
fi

if [[ "$MODE" == "json" ]]; then
  # Emit a JSON array of unique basenames for use as a GitHub Actions matrix.
  mapfile -t names < <(for m in "${matches[@]}"; do basename "$m"; done | LC_ALL=C sort -u)
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
