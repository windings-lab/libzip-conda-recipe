#!/usr/bin/env bash
# Builds the package. Installs Miniforge if needed; uploads if ANACONDA_API_TOKEN is set.
set -euo pipefail

readonly PREFIX="${MINIFORGE_PREFIX:-${HOME}/miniforge3}"
readonly OUTPUT="build_artifacts"

if ! command -v conda > /dev/null; then
    if [ ! -d "${PREFIX}" ]; then
        case "$(uname -s)" in
            Linux) os=Linux ;;
            Darwin) os=MacOSX ;;
            *) echo "unsupported OS: $(uname -s); use bootstrap.ps1 on Windows" >&2; exit 1 ;;
        esac
        case "$(uname -m)" in
            x86_64) arch=x86_64 ;;
            aarch64 | arm64) arch=$([ "${os}" = Linux ] && echo aarch64 || echo arm64) ;;
            *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
        esac

        installer="$(mktemp -t miniforge.XXXXXX.sh)"
        trap 'rm -f "${installer}"' EXIT

        echo "installing Miniforge into ${PREFIX}"
        curl -fsSL -o "${installer}" \
            "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-${os}-${arch}.sh"
        bash "${installer}" -b -p "${PREFIX}"
    fi

    # shellcheck disable=SC1091
    . "${PREFIX}/etc/profile.d/conda.sh"
    conda activate base
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
