# Consumer project for the package smoke test -- this does NOT build libzip.
#
# It builds test_libzip.cpp against the *installed* conda package via the CMake
# config files that the package ships (lib/cmake/libzip/), which is how other
# conda recipes consume libzip.  Driven by the test section of meta.yaml.

cmake_minimum_required(VERSION 3.16)

project(libzip_conda_smoke_test CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(libzip CONFIG REQUIRED)

message(STATUS "found libzip ${libzip_VERSION}")

add_executable(test_libzip test_libzip.cpp)
target_link_libraries(test_libzip PRIVATE libzip::zip)

enable_testing()
add_test(NAME smoke COMMAND test_libzip)
