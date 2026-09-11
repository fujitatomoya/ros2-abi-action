# shellcheck shell=bash
#
# abi-build-flags.sh
#
# The single definition of the CMake arguments every colcon build in this
# repository uses, so the packages under test (scripts/colcon-build.sh) and the
# source underlay they are linked against (containers/build-underlay.sh, and
# through it the ros-abi:<distro>-source images) are compiled identically:
#
#   * Debug with -g -Og: abidiff needs full DWARF; -Og keeps the build fast
#     while preserving symbols.
#   * BUILD_TESTING=OFF: tests are irrelevant to the ABI, dominate build time
#     and would require every test_depend (ament_lint_*, fixtures).
#
# Sourced, not executed. Consumers pass "${ABI_CMAKE_ARGS[@]}" after
# `colcon build ... --cmake-args`.
# shellcheck disable=SC2034  # used by the sourcing scripts
ABI_CMAKE_ARGS=(
  -DCMAKE_BUILD_TYPE=Debug
  -DBUILD_TESTING=OFF
  -DCMAKE_C_FLAGS="-g -Og"
  -DCMAKE_CXX_FLAGS="-g -Og"
)
