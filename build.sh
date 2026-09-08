#!/usr/bin/env bash
# Build script for the libzip conda package (Linux / macOS).
set -euxo pipefail

mkdir -p build
cd build

# ${CMAKE_ARGS} is exported by the conda compiler activation scripts and carries
# the cross-compilation settings (sysroot, CMAKE_FIND_ROOT_PATH, ...).  It has
# to come first so that the options below can still override it.
cmake ${CMAKE_ARGS} \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_PREFIX_PATH="${PREFIX}" \
    -DBUILD_SHARED_LIBS=ON \
    -DENABLE_BZIP2=ON \
    -DENABLE_LZMA=ON \
    -DENABLE_ZSTD=ON \
    -DENABLE_OPENSSL=ON \
    -DENABLE_GNUTLS=OFF \
    -DENABLE_MBEDTLS=OFF \
    -DENABLE_COMMONCRYPTO=OFF \
    -DBUILD_TOOLS=ON \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_DOC=OFF \
    -DBUILD_OSSFUZZ=OFF \
    -DBUILD_REGRESS=OFF \
    ..

# libzip's CMake silently disables an optional backend when it cannot find the
# library, which would produce a package that is missing half of the features
# this recipe advertises.  The generated config.h records what was actually
# enabled, so check it and fail the build rather than ship a crippled package.
# HAVE_CRYPTO comes from OpenSSL here, since every other crypto backend is off.
for macro in HAVE_LIBBZ2 HAVE_LIBLZMA HAVE_LIBZSTD HAVE_CRYPTO; do
    if ! grep -q "^#define ${macro}" config.h; then
        echo "ERROR: ${macro} is not set; an optional dependency was not found" >&2
        cat config.h >&2
        exit 1
    fi
done

cmake --build . --parallel "${CPU_COUNT}"
cmake --install .

# The upstream regression suite (BUILD_REGRESS) is driven by `nihtest`, which is
# not packaged for conda, so it is disabled above.  The `test:` section of
# meta.yaml compiles and runs a consumer program against the installed package
# instead.
