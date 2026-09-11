# binary.Dockerfile
#
# Self-contained ABI image for a ROS 2 distro: ros-abi:<distro>.
#
# Based on the official ros:<distro> image (binary underlay at /opt/ros plus
# colcon/rosdep/vcstool/build-essential) so a single colcon package can be
# built from source, with rosdep filling in any missing package dependencies
# at CI time. abigail-tools and ccache are added on top so the image can also
# run abidiff directly.
#
# These images are published to GHCR by .github/workflows/build-images.yml and
# are the action's default distro->container map (GHCR pulls are not rate
# limited from GitHub-hosted runners, unlike anonymous Docker Hub pulls).
#
# Build: containers/build-image.sh <distro>
#   or:  docker build -f containers/binary.Dockerfile --build-arg DISTRO=<distro> .
ARG DISTRO=rolling
FROM docker.io/library/ros:${DISTRO}

# python3-colcon-common-extensions is already part of ros:<distro>; keeping it
# here makes the image independent of that base's package list.
RUN apt-get update && apt-get install -y --no-install-recommends \
      abigail-tools \
      ccache \
      python3-colcon-common-extensions \
    && rm -rf /var/lib/apt/lists/*
