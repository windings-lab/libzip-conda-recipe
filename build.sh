#!/usr/bin/env bash
set -euxo pipefail

mkdir -p build
cd build

# CMAKE_ARGS comes first so the options below override it
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

# CMake drops an optional backend silently when its library is missing
for macro in HAVE_LIBBZ2 HAVE_LIBLZMA HAVE_LIBZSTD HAVE_CRYPTO; do
    if ! grep -q "^#define ${macro}" config.h; then
        echo "ERROR: ${macro} is not set; an optional dependency was not found" >&2
        cat config.h >&2
        exit 1
    fi
done

cmake --build . --parallel "${CPU_COUNT}"
cmake --install .
