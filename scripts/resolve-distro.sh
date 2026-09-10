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
#                   Default: ghcr.io/fujitatomoya/ros-abi
#   BUILD_MODE      "binary" (default): build against the released ros-<distro>
#                   Debian packages, image <prefix>:<distro>.
#                   "source": build against a source-built core underlay,
#                   image <prefix>:<distro>-source (for ROS 2 core repos).
#   SOURCE_STRATEGY "incremental" (default): rebuild only what moved since the
#                   source image was built, on top of its prebuilt underlay.
#                   "scratch": ignore the prebuilt underlay and build the whole
#                   closure from source. Both use <prefix>:<distro>-source,
#                   which carries the system dependencies of all of ros2.repos.
#
# Outputs (written to $GITHUB_OUTPUT when set, always echoed):
#   distro          Resolved distro name.
#   build-mode      Resolved build mode (binary | source).
#   source-strategy Resolved strategy (incremental | scratch).
#   image           Fully-qualified container image.
#
set -euo pipefail

# Single source of truth for the distro -> container map. The image is always
# "<IMAGE_PREFIX>:<distro>" (binary) or "<IMAGE_PREFIX>:<distro>-source";
# only the supported distro set is enumerated here.
KNOWN_DISTROS=(humble jazzy kilted lyrical rolling)

INPUT_DISTRO="${INPUT_DISTRO:-auto}"
IMAGE_PREFIX="${IMAGE_PREFIX:-ghcr.io/fujitatomoya/ros-abi}"
BUILD_MODE="${BUILD_MODE:-binary}"
BUILD_MODE="${BUILD_MODE,,}"

case "$BUILD_MODE" in
  binary|source) ;;
  *)
    echo "::error::Unsupported build-mode '$BUILD_MODE'. Supported: binary, source." >&2
    exit 1
    ;;
esac

SOURCE_STRATEGY="${SOURCE_STRATEGY:-incremental}"
SOURCE_STRATEGY="${SOURCE_STRATEGY,,}"
case "$SOURCE_STRATEGY" in
  incremental|scratch) ;;
  *)
    echo "::error::Unsupported source-strategy '$SOURCE_STRATEGY'. Supported: incremental, scratch." >&2
    exit 1
    ;;
esac

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
# Source builds always use the source image: it is the only one whose system
# dependencies cover the whole manifest, and it carries no binary ROS install
# that could leak into the build. The scratch strategy merely ignores its
# prebuilt underlay (see colcon-build.sh).
if [[ "$BUILD_MODE" == "source" ]]; then
  image="${image}-source"
fi

echo "Resolved distro: $distro"
echo "Resolved mode:   $BUILD_MODE"
echo "Resolved strategy: $SOURCE_STRATEGY"
echo "Resolved image:  $image"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "distro=$distro"
    echo "build-mode=$BUILD_MODE"
    echo "source-strategy=$SOURCE_STRATEGY"
    echo "image=$image"
  } >> "$GITHUB_OUTPUT"
fi
