cmake_minimum_required(VERSION 3.8)
project(toy_ros_pkg)

find_package(ament_cmake REQUIRED)

# Build with debug info so abidiff has DWARF to compare.
add_compile_options(-g -Og)

add_library(toy_ros_pkg SHARED src/counter.cpp)
target_include_directories(toy_ros_pkg PUBLIC
  "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
  "$<INSTALL_INTERFACE:include>")
target_compile_features(toy_ros_pkg PUBLIC cxx_std_17)

install(
  DIRECTORY include/
  DESTINATION include)
install(
  TARGETS toy_ros_pkg
  EXPORT export_toy_ros_pkg
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
  RUNTIME DESTINATION bin)

ament_package()
