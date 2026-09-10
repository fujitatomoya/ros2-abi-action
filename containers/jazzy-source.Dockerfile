# jazzy-source.Dockerfile
#
# Source-built ROS 2 Jazzy underlay for ABI checks of core repositories
# (ros-abi:jazzy-source). See humble-source.Dockerfile for the full design
# notes; this file follows the official "Ubuntu (source)" page for Jazzy:
#
#   https://docs.ros.org/en/jazzy/Installation/Alternatives/Ubuntu-Development-Setup.html
#
# Distro-specific values from that page:
#   Tier 1 platform  : Ubuntu Noble (24.04)
#   rosdep skip keys : fastcdr rti-connext-dds-6.0.1 urdfdom_headers
#
# Deviations from the page are marked "DEVIATION" and explained in place.
FROM docker.io/library/ubuntu:noble

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    ROS_DISTRO=jazzy

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

# ---- Install development tools -----------------------------------------------
RUN apt-get update && apt-get install -y \
      python3-flake8-blind-except \
      python3-flake8-class-newline \
      python3-flake8-deprecated \
      python3-mypy \
      python3-pip \
      python3-pytest \
      python3-pytest-cov \
      python3-pytest-mock \
      python3-pytest-repeat \
      python3-pytest-rerunfailures \
      python3-pytest-runner \
      python3-pytest-timeout \
      ros-dev-tools \
    && rm -rf /var/lib/apt/lists/*

# Action-specific additions (not part of the documented setup).
RUN apt-get update && apt-get install -y --no-install-recommends \
      abigail-tools \
      ccache \
    && rm -rf /var/lib/apt/lists/*

# ---- Get ROS 2 code ----------------------------------------------------------
# DEVIATION: manifest saved locally, shallow clones, --retry (see humble file).
WORKDIR /opt/ros2_ws
RUN mkdir -p src \
    && curl -fsSL https://raw.githubusercontent.com/ros2/ros2/jazzy/ros2.repos -o ros2.repos \
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
# DEVIATION from `colcon build --symlink-install --mixin release`: Debug -g -Og,
# BUILD_TESTING=OFF, no symlink install, --continue-on-error, 2 workers (see
# humble-source.Dockerfile for the reasoning). Nothing is sourced beforehand.
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

ENV ROS_ABI_UNDERLAY=/opt/ros2_ws/install/setup.bash \
    ROS_ABI_SNAPSHOT=/opt/ros2_ws/snapshot.repos \
    ROS_ABI_REPOS_URL=https://raw.githubusercontent.com/ros2/ros2/jazzy/ros2.repos \
    ROS_ABI_ROSDEP_SKIP_KEYS="fastcdr rti-connext-dds-6.0.1 urdfdom_headers"
