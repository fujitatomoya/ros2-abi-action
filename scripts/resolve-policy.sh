#!/usr/bin/env bash
#
# resolve-policy.sh
#
# Resolve the ABI policy and the corresponding libabigail "fail-on" severity,
# following REP-0009: the rolling distro allows ABI breaks (advisory only),
# while every released distro must not break ABI (strict).
#
# Inputs (environment):
#   INPUT_POLICY  auto | strict | advisory   (default: auto)
#   DISTRO        Resolved distro name (required when INPUT_POLICY=auto).
#
# Outputs (written to $GITHUB_OUTPUT when set, always echoed):
#   policy        strict | advisory
#   fail-on       Value forwarded to libabigail-action:
#                   strict   -> incompatible  (job fails on ABI break)
#                   advisory -> none          (job never fails; report only)
#
set -euo pipefail

INPUT_POLICY="${INPUT_POLICY:-auto}"
DISTRO="${DISTRO:-}"

resolve_auto() {
  # REP-0009: rolling is the only distro that permits ABI breaks.
  case "$DISTRO" in
    rolling) echo "advisory" ;;
    "")
      echo "::error::policy=auto but DISTRO is empty; cannot resolve policy." >&2
      exit 1
      ;;
    *) echo "strict" ;;
  esac
}

case "$INPUT_POLICY" in
  auto|"") policy="$(resolve_auto)" ;;
  strict)   policy="strict" ;;
  advisory) policy="advisory" ;;
  *)
    echo "::error::Invalid policy '$INPUT_POLICY'. Use auto | strict | advisory." >&2
    exit 1
    ;;
esac

case "$policy" in
  strict)   fail_on="incompatible" ;;
  advisory) fail_on="none" ;;
esac

echo "Resolved policy:  $policy"
echo "Resolved fail-on: $fail_on"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "policy=$policy"
    echo "fail-on=$fail_on"
  } >> "$GITHUB_OUTPUT"
fi
