# humble.Dockerfile
#
# Self-contained ABI image for ROS 2 Humble.
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
FROM docker.io/library/ros:humble

RUN apt-get update && apt-get install -y --no-install-recommends \
      abigail-tools \
      ccache \
      python3-colcon-common-extensions \
    && rm -rf /var/lib/apt/lists/*
