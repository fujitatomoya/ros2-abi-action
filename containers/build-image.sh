#!/usr/bin/env bash
#
# build-image.sh
#
# Build a ros-abi image locally with the same Dockerfile and build args the
# nightly build-images.yml uses. Run from anywhere; the build context is the
# repository root.
#
# Usage: build-image.sh <distro> [binary|source] [extra docker build args...]
#
#   build-image.sh rolling source --build-arg PARALLEL_WORKERS=8
#   build-image.sh humble               # binary image
#
# The image is tagged ghcr.io/fujitatomoya/ros-abi:<distro>[-source] unless
# IMAGE_PREFIX is set; extra arguments are passed to docker build verbatim
# (add -t to tag differently).
set -euo pipefail

distro="${1:?usage: $0 <distro> [binary|source] [docker build args...]}"
flavor="${2:-binary}"
shift "$(( $# >= 2 ? 2 : 1 ))"
prefix="${IMAGE_PREFIX:-ghcr.io/fujitatomoya/ros-abi}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

args=()
case "$flavor" in
  binary)
    args+=(--build-arg "DISTRO=$distro")
    tag="$prefix:$distro"
    ;;
  source)
    while IFS= read -r line; do
      args+=(--build-arg "$line")
    done < <(bash "$here/distro-args.sh" "$distro")
    tag="$prefix:$distro-source"
    ;;
  *)
    echo "ERROR: flavor must be binary or source, got '$flavor'." >&2
    exit 1
    ;;
esac

set -x
docker build -f "$here/$flavor.Dockerfile" "${args[@]}" -t "$tag" "$@" "$root"
