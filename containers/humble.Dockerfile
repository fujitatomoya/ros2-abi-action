# humble.Dockerfile
#
# Self-contained ABI image for ROS 2 Humble.
#
# Based on the full ROS 2 development image (all rosdep dependencies already
# installed) so a single colcon package can be built from source without
# resolving the whole dependency tree on every CI run. libabigail-tools and
# ccache are added on top so the image can also run abidiff directly.
#
# The action's default distro->container map points at the upstream ros2dev
# images; this Dockerfile is the recipe for the optional slimmer, abidiff-ready
# images published by .github/workflows/build-images.yml.
FROM docker.io/tomoyafujita/ros2dev:humble

RUN apt-get update && apt-get install -y --no-install-recommends \
      abigail-tools \
      ccache \
      python3-colcon-common-extensions \
    && rm -rf /var/lib/apt/lists/*
