cmake_minimum_required(VERSION 3.10)
project(abi_smoke C)

add_library(abi_smoke SHARED src/smoke.c)
install(TARGETS abi_smoke LIBRARY DESTINATION lib)
