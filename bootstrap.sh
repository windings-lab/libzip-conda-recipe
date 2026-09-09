#!/usr/bin/env bash
# Builds the package. Bootstraps conda if needed; uploads if ANACONDA_API_TOKEN is set.
set -euo pipefail

tools_arg="${CONDA_TOOLS_PREFIX:-${HOME}/.conda-tools}"
mkdir -p "${tools_arg}"
TOOLS="$(cd "${tools_arg}" && pwd)"
if command -v cygpath > /dev/null; then
    TOOLS="$(cygpath -m "${TOOLS}")"
fi
readonly TOOLS
readonly OUTPUT="build_artifacts"

case "${TOOLS}/" in
    "$(pwd)"/*)
        echo "CONDA_TOOLS_PREFIX must be outside the recipe directory:" >&2
        echo "conda-bld would land inside it and the test files would recurse" >&2
        exit 1
        ;;
esac

export CONDA_PKGS_DIRS="${CONDA_PKGS_DIRS:-${TOOLS}/pkgs}"

can_build() {
    command -v conda > /dev/null &&
        conda list -n base conda-build 2> /dev/null | grep -q '^conda-build '
}

add_conda_to_path() {
    for dir in "$1/bin" "$1/Scripts"; do
        if [ -x "${dir}/conda" ] || [ -x "${dir}/conda.exe" ]; then
            export PATH="${dir}:${PATH}"
            return 0
        fi
    done
    return 1
}

if ! can_build; then
    for candidate in "${CONDA:-}" "${TOOLS}/env"; do
        [ -n "${candidate}" ] || continue
        outer_path="${PATH}"
        if add_conda_to_path "${candidate}" && can_build; then
            break
        fi
        export PATH="${outer_path}"
    done
fi

if ! can_build; then
    case "$(uname -s)" in
        Linux) platform=linux; member=bin/micromamba ;;
        Darwin) platform=osx; member=bin/micromamba ;;
        MINGW* | MSYS* | CYGWIN*) platform=win; member=Library/bin/micromamba.exe ;;
        *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
    esac
    case "$(uname -m)" in
        x86_64) arch=64 ;;
        aarch64 | arm64) arch=aarch64 ;;
        *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
    esac

    echo "bootstrapping conda-build into ${TOOLS}"
    curl -fsSL "https://micro.mamba.pm/api/micromamba/${platform}-${arch}/latest" |
        tar -xj -C "${TOOLS}" "${member}"

    MAMBA_ROOT_PREFIX="${TOOLS}" "${TOOLS}/${member}" create -y \
        -p "${TOOLS}/env" -c conda-forge --override-channels \
        conda conda-build anaconda-client

    add_conda_to_path "${TOOLS}/env"
fi

if [ -n "${ANACONDA_API_TOKEN:-}" ] &&
    ! conda run -n base anaconda --help > /dev/null 2>&1; then
    echo "ANACONDA_API_TOKEN is set but this conda has no anaconda-client" >&2
    exit 1
fi

conda build . \
    -c conda-forge --override-channels \
    --no-anaconda-upload \
    --output-folder "${OUTPUT}"

find "${OUTPUT}" -name '*.conda' -print

if [ -n "${ANACONDA_API_TOKEN:-}" ]; then
    find "${OUTPUT}" -name '*.conda' -exec \
        conda run -n base --no-capture-output anaconda org upload --skip-existing {} +
fi
