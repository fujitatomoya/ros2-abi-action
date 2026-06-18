#!/usr/bin/env bash
#
# resolve-distro.sh
#
# Resolve the ROS 2 distribution and the container image that should be used to
# build the package under test.
#
# When INPUT_DISTRO is empty or "auto", the distro is derived from the pull
# request target branch (GITHUB_BASE_REF), which by convention is named after
# the distro in ROS 2 core repositories (rolling, jazzy, humble, ...).
#
# Inputs (environment):
#   INPUT_DISTRO    Explicit distro, or "auto"/"" to derive from the base ref.
#   GITHUB_BASE_REF Pull request target branch (set by GitHub on PR events).
#   IMAGE_PREFIX    Container image repository prefix.
#                   Default: docker.io/tomoyafujita/ros2dev
#
# Outputs (written to $GITHUB_OUTPUT when set, always echoed):
#   distro          Resolved distro name.
#   image           Fully-qualified container image (<prefix>:<distro>).
#
set -euo pipefail

# Single source of truth for the distro -> container map. The image is always
# "<IMAGE_PREFIX>:<distro>"; only the supported distro set is enumerated here.
KNOWN_DISTROS=(humble jazzy kilted lyrical rolling)

INPUT_DISTRO="${INPUT_DISTRO:-auto}"
IMAGE_PREFIX="${IMAGE_PREFIX:-docker.io/tomoyafujita/ros2dev}"

normalize() {
  # Strip a leading refs/heads/ or refs/tags/ and lower-case the result.
  local ref="$1"
  ref="${ref#refs/heads/}"
  ref="${ref#refs/tags/}"
  printf '%s' "${ref,,}"
}

is_known() {
  local candidate="$1"
  local d
  for d in "${KNOWN_DISTROS[@]}"; do
    [[ "$d" == "$candidate" ]] && return 0
  done
  return 1
}

if [[ -n "$INPUT_DISTRO" && "$INPUT_DISTRO" != "auto" ]]; then
  distro="$(normalize "$INPUT_DISTRO")"
else
  if [[ -z "${GITHUB_BASE_REF:-}" ]]; then
    echo "::error::distro=auto but GITHUB_BASE_REF is empty. " \
         "Run on a pull_request event or set 'distro' explicitly." >&2
    exit 1
  fi
  distro="$(normalize "$GITHUB_BASE_REF")"
fi

if ! is_known "$distro"; then
  echo "::error::Unsupported ROS 2 distro '$distro'. " \
       "Supported: ${KNOWN_DISTROS[*]}. " \
       "Set the 'distro' input explicitly if the branch is not named after a distro." >&2
  exit 1
fi

image="${IMAGE_PREFIX}:${distro}"

echo "Resolved distro: $distro"
echo "Resolved image:  $image"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "distro=$distro"
    echo "image=$image"
  } >> "$GITHUB_OUTPUT"
fi
