# humble-source.Dockerfile
#
# Source-built ROS 2 Humble underlay for ABI checks of core repositories
# (ros-abi:humble-source).
#
# Why a source image
# ------------------
# The binary images (<distro>.Dockerfile) build the package under test against
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
# for this distro, in the documented order:
#
#   https://docs.ros.org/en/humble/Installation/Alternatives/Ubuntu-Development-Setup.html
#
# Distro-specific values from that page:
#   Tier 1 platform  : Ubuntu Jammy (22.04)
#   rosdep skip keys : fastcdr rti-connext-dds-6.0.1 urdfdom_headers
#
# Deviations from the page are marked "DEVIATION" and explained in place.
# Sibling files exist per distro because the platform, the development tool
# list and the rosdep skip keys differ between distros.
FROM docker.io/library/ubuntu:jammy

# Non-interactive apt; LANG per the "Set locale" step; ROS_DISTRO for rosdep
# and the action scripts (a plain Ubuntu image does not define it).
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    ROS_DISTRO=humble

# ---- Set locale --------------------------------------------------------------
RUN apt-get update && apt-get install -y locales \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ---- Enable required repositories (Universe + ros2-apt-source) ---------------
RUN apt-get update && apt-get install -y software-properties-common curl ca-certificates \
    && add-apt-repository -y universe \
    && ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F'"' '{print $4}') \
    && curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb" \
    && dpkg -i /tmp/ros2-apt-source.deb \
    && rm -f /tmp/ros2-apt-source.deb \
    && rm -rf /var/lib/apt/lists/*

# ---- Install development tools and ROS tools ---------------------------------
# Common packages, then the "Ubuntu 22.04 LTS and later" set, as documented.
RUN apt-get update && apt-get install -y \
      python3-flake8-docstrings \
      python3-pip \
      python3-pytest-cov \
      ros-dev-tools \
    && apt-get install -y \
      python3-flake8-blind-except \
      python3-flake8-builtins \
      python3-flake8-class-newline \
      python3-flake8-comprehensions \
      python3-flake8-deprecated \
      python3-flake8-import-order \
      python3-flake8-quotes \
      python3-pytest-repeat \
      python3-pytest-rerunfailures \
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
    && curl -fsSL https://raw.githubusercontent.com/ros2/ros2/humble/ros2.repos -o ros2.repos \
    && vcs import --input ros2.repos --shallow --retry 3 src \
    && vcs export --exact src > snapshot.repos

# ---- Install dependencies using rosdep ---------------------------------------
RUN apt-get update \
    && rosdep init \
    && rosdep update \
    && rosdep install --from-paths src --ignore-src -y \
         --skip-keys "fastcdr rti-connext-dds-6.0.1 urdfdom_headers" \
    && rm -rf /var/lib/apt/lists/*

# Parallel colcon workers. 2 bounds peak memory on 4-vCPU hosted runners; raise
# it for local builds: docker build --build-arg PARALLEL_WORKERS=8 ...
ARG PARALLEL_WORKERS=2

# ---- Build the code in the workspace -----------------------------------------
# DEVIATION from `colcon build --symlink-install --mixin release`:
#   * Debug with -g -Og instead of release: abidiff needs full DWARF, and this
#     matches what scripts/colcon-build.sh uses for the packages under test;
#   * BUILD_TESTING=OFF: tests are irrelevant to the ABI and dominate build time;
#   * no --symlink-install, since src/ is removed below;
#   * --continue-on-error: one broken upstream package must not sink the nightly
#     image; colcon-build.sh rebuilds any package the underlay lacks, and the
#     missing ones are listed in missing.txt for diagnosis;
#   * --parallel-workers (PARALLEL_WORKERS, default 2) bounds peak memory on
#     4-vCPU hosted runners.
# Nothing is sourced before this step, as the documentation requires.
RUN colcon build \
      --base-paths src \
      --continue-on-error \
      --parallel-workers "${PARALLEL_WORKERS}" \
      --event-handlers console_cohesion+ \
      --cmake-args \
        -DCMAKE_BUILD_TYPE=Debug \
        -DBUILD_TESTING=OFF \
        -DCMAKE_C_FLAGS="-g -Og" \
        -DCMAKE_CXX_FLAGS="-g -Og" \
    || echo "WARNING: some packages failed to build; see missing.txt in the image" \
    && test -f install/setup.bash \
    && colcon list --base-paths src --names-only | sort > packages.txt \
    && ls install | sort > built.txt \
    && comm -23 packages.txt built.txt > missing.txt \
    && echo "Packages not built: $(wc -l < missing.txt)" \
    && rm -rf build log src packages.txt built.txt

# Consumed by scripts/colcon-build.sh and scripts/sync-upstream.py. GitHub
# container jobs expose image ENV to every step.
ENV ROS_ABI_UNDERLAY=/opt/ros2_ws/install/setup.bash \
    ROS_ABI_SNAPSHOT=/opt/ros2_ws/snapshot.repos \
    ROS_ABI_REPOS_URL=https://raw.githubusercontent.com/ros2/ros2/humble/ros2.repos \
    ROS_ABI_ROSDEP_SKIP_KEYS="fastcdr rti-connext-dds-6.0.1 urdfdom_headers"
