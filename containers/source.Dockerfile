# source.Dockerfile
#
# Source-built ROS 2 underlay for ABI checks of core repositories:
# ros-abi:<distro>-source. One Dockerfile serves every distro; the values that
# differ between distros (Tier 1 Ubuntu release, development tool set, rosdep
# skip keys) come in as build args from containers/distro-args.sh.
#
# Build: containers/build-image.sh <distro> source [--build-arg PARALLEL_WORKERS=8]
#
# Why a source image
# ------------------
# The binary images (binary.Dockerfile) build the package under test against
# the released ros-<distro>-* Debian packages. That is right for downstream
# packages, but ROS 2 core repositories (rclcpp, rcl, rmw, ...) develop against
# the *source* branches of their dependencies, which regularly carry API that
# has not reached the binary archive yet. Building such a PR against binaries
# fails, so core repositories use check.yml's build-mode: source, backed by
# this image.
#
# What the image contains
# -----------------------
#   /opt/ros2_ws/install         every package of the distro's ros2.repos,
#                                built from source with Debug -g -Og
#   /opt/ros2_ws/snapshot.repos  exact commit of every imported repository
#                                (vcs export --exact); diffed by
#                                scripts/sync-upstream.py at CI time
#   /opt/ros2_ws/ros2.repos      the manifest that was imported
#   /opt/ros2_ws/missing.txt     packages the build did not produce, if any
#   /opt/ros-abi/                the scripts below, mirroring the repository
#
# There is deliberately NO binary ROS 2 installation in this image: the
# official instructions require the source build to run in an environment
# where no other ROS 2 installation is sourced.
#
# How the image is used
# ---------------------
# check.yml (build-mode: source) imports the current ros2.repos into the PR
# workspace, works out which repositories moved since snapshot.repos, and
# colcon-build.sh sources ROS_ABI_UNDERLAY and rebuilds only those packages,
# their dependents and the packages under test. With source-strategy: scratch
# the underlay is ignored and the whole closure is compiled from source in the
# same image (its system dependencies are already installed).
#
# Provenance
# ----------
# Every step below follows the official "Ubuntu (source)" installation page
# for the distro, in the documented order:
#
#   https://docs.ros.org/en/<distro>/Installation/Alternatives/Ubuntu-Development-Setup.html
#
# Deviations from the page are marked "DEVIATION" and explained in place (or
# in the script that implements the step).

# ---- Build args (see containers/distro-args.sh) ------------------------------
# The defaults only make a bare `docker build` well-formed; build-image.sh and
# build-images.yml always pass the full, consistent set for a distro.
ARG BASE_IMAGE=docker.io/library/ubuntu:26.04
FROM ${BASE_IMAGE}
ARG DISTRO=rolling
ARG DEV_TOOLS
ARG ROSDEP_SKIP_KEYS
# ROS_APT_SOURCE_VERSION may be passed in (build-images.yml resolves it with an
# authenticated API call); when empty, the documented anonymous lookup is used.
ARG ROS_APT_SOURCE_VERSION=""
# Parallel colcon workers. 2 bounds peak memory on 4-vCPU hosted runners; raise
# it for local builds: build-image.sh <distro> source --build-arg PARALLEL_WORKERS=8
ARG PARALLEL_WORKERS=2

# Non-interactive apt; LANG per the "Set locale" step; ROS_DISTRO for rosdep
# and the action scripts (a plain Ubuntu image does not define it).
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    ROS_DISTRO=${DISTRO}

# The scripts shared with ci.yml, laid out as in the repository so that
# build-underlay.sh finds ../scripts/abi-build-flags.sh.
COPY containers/*.sh /opt/ros-abi/containers/
COPY scripts/abi-build-flags.sh /opt/ros-abi/scripts/

RUN test -n "$ROSDEP_SKIP_KEYS" \
    || { echo "ROSDEP_SKIP_KEYS build arg is required; build with containers/build-image.sh <distro> source"; exit 1; }

# ---- Set locale / Enable required repositories -------------------------------
RUN bash /opt/ros-abi/containers/install-ros-apt-source.sh \
    && rm -rf /var/lib/apt/lists/*

# ---- Install development tools and ROS tools ---------------------------------
# The documented per-distro set (DEV_TOOLS) plus ros-dev-tools. Word splitting
# of DEV_TOOLS is intended.
RUN apt-get update && apt-get install -y ${DEV_TOOLS} ros-dev-tools \
    && rm -rf /var/lib/apt/lists/*

# Action-specific additions (not part of the documented setup): ccache speeds
# up the per-PR builds, abigail-tools lets the image run abidiff directly.
RUN apt-get update && apt-get install -y --no-install-recommends \
      abigail-tools \
      ccache \
    && rm -rf /var/lib/apt/lists/*

# ---- Get ROS 2 code ----------------------------------------------------------
# DEVIATION: the manifest is saved next to the workspace and the clones are
# shallow (sources are deleted at the end; only install/ and the snapshot are
# kept), and --retry guards against transient network errors.
WORKDIR /opt/ros2_ws
RUN mkdir -p src \
    && curl -fsSL "https://raw.githubusercontent.com/ros2/ros2/${DISTRO}/ros2.repos" -o ros2.repos \
    && vcs import --input ros2.repos --shallow --retry 3 src \
    && vcs export --exact src > snapshot.repos

# ---- Install dependencies using rosdep ---------------------------------------
RUN apt-get update \
    && rosdep init \
    && rosdep update \
    && rosdep install --from-paths src --ignore-src -y \
         --skip-keys "${ROSDEP_SKIP_KEYS}" \
    && rm -rf /var/lib/apt/lists/*

# ---- Build the code in the workspace -----------------------------------------
# DEVIATIONs are documented in build-underlay.sh. Nothing is sourced
# beforehand, as the documentation requires.
RUN bash /opt/ros-abi/containers/build-underlay.sh /opt/ros2_ws

# Consumed by scripts/colcon-build.sh and scripts/sync-upstream.py. GitHub
# container jobs expose image ENV to every step.
ENV ROS_ABI_UNDERLAY=/opt/ros2_ws/install/setup.bash \
    ROS_ABI_SNAPSHOT=/opt/ros2_ws/snapshot.repos \
    ROS_ABI_REPOS_URL=https://raw.githubusercontent.com/ros2/ros2/${DISTRO}/ros2.repos \
    ROS_ABI_ROSDEP_SKIP_KEYS="${ROSDEP_SKIP_KEYS}"
