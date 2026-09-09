#!/usr/bin/env bash
# Points meta.yaml at a new upstream version: ./bump.sh 1.11.5
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <version>" >&2
    exit 1
fi

readonly VERSION="$1"
readonly RECIPE="meta.yaml"
readonly URL="https://github.com/nih-at/libzip/releases/download/v${VERSION}/libzip-${VERSION}.tar.xz"

current="$(sed -n 's/^{% set version = "\(.*\)" %}$/\1/p' "${RECIPE}")"
if [ -z "${current}" ]; then
    echo "cannot find the version line in ${RECIPE}" >&2
    exit 1
fi

if [ "${current}" = "${VERSION}" ]; then
    echo "${RECIPE} is already at ${VERSION}; bump build: number instead" >&2
    exit 1
fi

echo "fetching ${URL}"
sha256="$(curl -fsSL "${URL}" | sha256sum | cut -d' ' -f1)"

sed -i \
    -e "s|^{% set version = \".*\" %}$|{% set version = \"${VERSION}\" %}|" \
    -e "s|^  sha256: .*$|  sha256: ${sha256}|" \
    -e "s|^  number: .*$|  number: 0|" \
    "${RECIPE}"

echo "${current} -> ${VERSION}"
echo "sha256: ${sha256}"
git --no-pager diff --stat "${RECIPE}"
