#!/usr/bin/env bash
# Builds the package. Bootstraps conda if needed; uploads if ANACONDA_API_TOKEN is set.
set -euo pipefail

readonly TOOLS="${CONDA_TOOLS_PREFIX:-${HOME}/.conda-tools}"
readonly OUTPUT="build_artifacts"

export CONDA_PKGS_DIRS="${CONDA_PKGS_DIRS:-${TOOLS}/pkgs}"

add_conda_to_path() {
    for dir in "$1/bin" "$1/Scripts"; do
        if [ -x "${dir}/conda" ] || [ -x "${dir}/conda.exe" ]; then
            export PATH="${dir}:${PATH}"
            return 0
        fi
    done
    return 1
}

if ! command -v conda > /dev/null; then
    for candidate in "${CONDA:-}" "${TOOLS}/env"; do
        if [ -n "${candidate}" ] && add_conda_to_path "${candidate}"; then
            break
        fi
    done
fi

if ! command -v conda > /dev/null; then
    case "$(uname -s)" in
        Linux) platform=linux ;;
        Darwin) platform=osx ;;
        *) echo "cannot bootstrap on $(uname -s); use bootstrap.ps1 on Windows" >&2; exit 1 ;;
    esac
    case "$(uname -m)" in
        x86_64) arch=64 ;;
        aarch64 | arm64) arch=aarch64 ;;
        *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
    esac

    echo "bootstrapping conda-build into ${TOOLS}"
    mkdir -p "${TOOLS}"
    curl -fsSL "https://micro.mamba.pm/api/micromamba/${platform}-${arch}/latest" |
        tar -xj -C "${TOOLS}" bin/micromamba

    MAMBA_ROOT_PREFIX="${TOOLS}" "${TOOLS}/bin/micromamba" create -y \
        -p "${TOOLS}/env" -c conda-forge --override-channels \
        conda conda-build anaconda-client

    add_conda_to_path "${TOOLS}/env"
fi

conda list -n base conda-build | grep -q '^conda-build ' ||
    conda install -y -n base -c conda-forge conda-build anaconda-client

conda build . \
    -c conda-forge --override-channels \
    --no-anaconda-upload \
    --output-folder "${OUTPUT}"

find "${OUTPUT}" -name '*.conda' -print

if [ -n "${ANACONDA_API_TOKEN:-}" ]; then
    find "${OUTPUT}" -name '*.conda' -exec \
        conda run -n base --no-capture-output anaconda org upload --skip-existing {} +
fi
