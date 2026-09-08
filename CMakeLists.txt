# Consumer project for the package smoke test -- this does NOT build libzip.
#
# It builds test_libzip.c against the *installed* conda package via the CMake
# config files that the package ships (lib/cmake/libzip/), which is how other
# conda recipes consume libzip.  Run from run_test.sh / run_test.bat.

cmake_minimum_required(VERSION 3.16)

project(libzip_conda_smoke_test C)

find_package(libzip CONFIG REQUIRED)

message(STATUS "found libzip ${libzip_VERSION}")

add_executable(test_libzip test_libzip.c)
target_link_libraries(test_libzip PRIVATE libzip::zip)

enable_testing()
add_test(NAME smoke COMMAND test_libzip)
