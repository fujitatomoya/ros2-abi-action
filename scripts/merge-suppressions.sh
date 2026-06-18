#!/usr/bin/env bash
#
# merge-suppressions.sh
#
# Merge the opinionated default ROS suppression spec shipped with this action
# with an optional per-repository suppression file, producing a single combined
# spec that is forwarded to libabigail's abidiff.
#
# Inputs (environment):
#   DEFAULT_SUPPRESSIONS  Path to the action's default spec (optional).
#   REPO_SUPPRESSIONS     Path to the repo's spec, e.g. .abignore (optional).
#   OUTPUT                Path to write the merged spec (required).
#
# Outputs (written to $GITHUB_OUTPUT when set):
#   suppressions          Path to the merged file, or empty if neither input
#                         existed (so callers can pass nothing through).
#
set -euo pipefail

DEFAULT_SUPPRESSIONS="${DEFAULT_SUPPRESSIONS:-}"
REPO_SUPPRESSIONS="${REPO_SUPPRESSIONS:-}"
OUTPUT="${OUTPUT:?OUTPUT is required}"

have_any=false
: > "$OUTPUT"

if [[ -n "$DEFAULT_SUPPRESSIONS" && -f "$DEFAULT_SUPPRESSIONS" ]]; then
  {
    echo "# ---- ros2-abi-action default suppressions ----"
    cat "$DEFAULT_SUPPRESSIONS"
    echo
  } >> "$OUTPUT"
  have_any=true
  echo "Included default suppressions: $DEFAULT_SUPPRESSIONS"
fi

if [[ -n "$REPO_SUPPRESSIONS" ]]; then
  if [[ -f "$REPO_SUPPRESSIONS" ]]; then
    {
      echo "# ---- repository suppressions ($REPO_SUPPRESSIONS) ----"
      cat "$REPO_SUPPRESSIONS"
      echo
    } >> "$OUTPUT"
    have_any=true
    echo "Included repository suppressions: $REPO_SUPPRESSIONS"
  else
    echo "::warning::Suppressions file '$REPO_SUPPRESSIONS' not found; ignoring."
  fi
fi

result=""
if [[ "$have_any" == true ]]; then
  result="$OUTPUT"
else
  rm -f "$OUTPUT"
  echo "No suppressions provided."
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "suppressions=$result" >> "$GITHUB_OUTPUT"
fi
