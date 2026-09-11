#!/usr/bin/env bash
#
# distro-args.sh
#
# The per-distro values of the ros-abi:<distro>-source images, taken from the
# official "Ubuntu (source)" installation page of each distro:
#
#   https://docs.ros.org/en/<distro>/Installation/Alternatives/Ubuntu-Development-Setup.html
#
#   BASE_IMAGE        the distro's Tier 1 Ubuntu release
#   DEV_TOOLS         the documented "Install development tools" package set
#                     (ros-dev-tools itself is always installed and omitted here)
#   ROSDEP_SKIP_KEYS  the documented `rosdep install --skip-keys` list
#
# Printed as KEY=value lines, one per line, which is exactly the build-args
# format of docker/build-push-action (build-images.yml) and what
# containers/build-image.sh turns into --build-arg flags for local builds.
# This file is the only place these values live; containers/source.Dockerfile
# consumes them as ARGs. The source-toolchain job in ci.yml repeats the
# distro -> BASE_IMAGE pairs in its matrix because a job's container image
# cannot be computed by a step.
#
# Usage: distro-args.sh <distro>      print the build args
#        distro-args.sh --list        print the supported distros
set -euo pipefail

KNOWN_DISTROS=(humble jazzy kilted lyrical rolling)

if [[ "${1:-}" == "--list" ]]; then
  printf '%s\n' "${KNOWN_DISTROS[@]}"
  exit 0
fi

distro="${1:?usage: $0 <distro> | --list}"

# Tool sets shared by several distros.
DEV_TOOLS_HUMBLE="python3-flake8-docstrings python3-pip python3-pytest-cov \
python3-flake8-blind-except python3-flake8-builtins python3-flake8-class-newline \
python3-flake8-comprehensions python3-flake8-deprecated python3-flake8-import-order \
python3-flake8-quotes python3-pytest-repeat python3-pytest-rerunfailures"
DEV_TOOLS_JAZZY="python3-flake8-blind-except python3-flake8-class-newline \
python3-flake8-deprecated python3-mypy python3-pip python3-pytest python3-pytest-cov \
python3-pytest-mock python3-pytest-repeat python3-pytest-rerunfailures \
python3-pytest-runner python3-pytest-timeout"
DEV_TOOLS_KILTED="python3-mypy python3-pip python3-pytest python3-pytest-cov \
python3-pytest-mock python3-pytest-repeat python3-pytest-rerunfailures \
python3-pytest-runner python3-pytest-timeout"

case "$distro" in
  humble)
    base=docker.io/library/ubuntu:jammy
    tools="$DEV_TOOLS_HUMBLE"
    skip="fastcdr rti-connext-dds-6.0.1 urdfdom_headers"
    ;;
  jazzy)
    base=docker.io/library/ubuntu:noble
    tools="$DEV_TOOLS_JAZZY"
    skip="fastcdr rti-connext-dds-6.0.1 urdfdom_headers"
    ;;
  kilted)
    base=docker.io/library/ubuntu:noble
    tools="$DEV_TOOLS_KILTED"
    skip="fastcdr rti-connext-dds-7.3.0 urdfdom_headers"
    ;;
  lyrical)
    base=docker.io/library/ubuntu:26.04
    tools="$DEV_TOOLS_KILTED"
    skip="fastcdr rti-connext-dds-7.7.0 urdfdom_headers"
    ;;
  rolling)
    base=docker.io/library/ubuntu:26.04
    tools="$DEV_TOOLS_KILTED"
    skip="fastcdr rti-connext-dds-7.7.0 urdfdom_headers"
    ;;
  *)
    echo "ERROR: unknown distro '$distro'. Supported: ${KNOWN_DISTROS[*]}" >&2
    exit 1
    ;;
esac

echo "DISTRO=$distro"
echo "BASE_IMAGE=$base"
echo "DEV_TOOLS=$tools"
echo "ROSDEP_SKIP_KEYS=$skip"
