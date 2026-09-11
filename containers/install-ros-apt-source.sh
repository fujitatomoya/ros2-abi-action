#!/usr/bin/env bash
#
# install-ros-apt-source.sh
#
# The first two steps of the official ROS 2 "Ubuntu (source)" installation
# page, shared by every place this repository needs them so they cannot drift:
#
#   1. Set locale               (en_US.UTF-8)
#   2. Enable required repos    (Universe + the ros2-apt-source package)
#
# Used by containers/source.Dockerfile (baked into the images), by the
# source-toolchain smoke test in ci.yml (same steps on every base image, in
# minutes instead of hours) and by the sync-upstream test job in ci.yml, which
# needs the ROS apt repository for python3-vcstool.
#
# Usage:
#   install-ros-apt-source.sh                 install (must run as root)
#   install-ros-apt-source.sh --version-only  print the resolved ros2-apt-source
#                                             version and exit; no root needed
#
# Environment:
#   ROS_APT_SOURCE_VERSION  Release tag of ros-infrastructure/ros-apt-source to
#                           install. When empty, the latest release is looked
#                           up through the GitHub API.
#   GH_TOKEN / GITHUB_TOKEN Optional token for that lookup. Anonymous API calls
#                           are rate limited per IP, which makes them unreliable
#                           from shared hosted runners; build-images.yml and
#                           ci.yml therefore always provide the job token.
#
# apt lists are left in place so a caller can install further packages without
# another apt-get update; Dockerfile RUN steps remove them afterwards.
set -euo pipefail

ROS_APT_SOURCE_VERSION="${ROS_APT_SOURCE_VERSION:-}"

resolve_version() {
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  local auth=()
  if [[ -n "$token" ]]; then
    auth=(-H "Authorization: Bearer $token")
  fi
  curl -fsSL "${auth[@]}" \
    https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1
}

if [[ "${1:-}" == "--version-only" ]]; then
  version="${ROS_APT_SOURCE_VERSION:-$(resolve_version)}"
  if [[ -z "$version" ]]; then
    echo "ERROR: could not resolve the latest ros2-apt-source release." >&2
    exit 1
  fi
  echo "$version"
  exit 0
fi

if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: $0 installs packages and must run as root (try: sudo -E $0)." >&2
  exit 1
fi

# ---- Set locale --------------------------------------------------------------
apt-get update
apt-get install -y locales software-properties-common curl ca-certificates
locale-gen en_US en_US.UTF-8
update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

# ---- Enable required repositories (Universe + ros2-apt-source) ---------------
add-apt-repository -y universe
version="${ROS_APT_SOURCE_VERSION:-$(resolve_version)}"
if [[ -z "$version" ]]; then
  echo "ERROR: could not resolve the latest ros2-apt-source release." >&2
  exit 1
fi
# shellcheck disable=SC1091
codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME}}")"
deb="/tmp/ros2-apt-source.deb"
curl -fsSL -o "$deb" \
  "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${version}/ros2-apt-source_${version}.${codename}_all.deb"
dpkg -i "$deb"
rm -f "$deb"
apt-get update
echo "ros2-apt-source ${version} installed for Ubuntu ${codename}."
