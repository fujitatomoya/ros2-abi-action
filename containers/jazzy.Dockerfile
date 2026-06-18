# jazzy.Dockerfile
#
# Self-contained ABI image for ROS 2 Jazzy. See humble.Dockerfile for details.
FROM docker.io/tomoyafujita/ros2dev:jazzy

RUN apt-get update && apt-get install -y --no-install-recommends \
      abigail-tools \
      ccache \
      python3-colcon-common-extensions \
    && rm -rf /var/lib/apt/lists/*
