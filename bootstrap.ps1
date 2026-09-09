# Builds the package. Bootstraps conda if needed; uploads if ANACONDA_API_TOKEN is set.
$ErrorActionPreference = 'Stop'

$tools = if ($env:CONDA_TOOLS_PREFIX) { $env:CONDA_TOOLS_PREFIX } else { "$env:USERPROFILE\.conda-tools" }
$output = 'build_artifacts'

if (-not $env:CONDA_PKGS_DIRS) { $env:CONDA_PKGS_DIRS = "$tools\pkgs" }

function Add-CondaToPath($prefix) {
    foreach ($dir in @("$prefix\Scripts", "$prefix\bin", $prefix)) {
        if (Test-Path "$dir\conda.exe") {
            $env:PATH = "$dir;$env:PATH"
            return $true
        }
    }
    return $false
}

if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
    foreach ($candidate in @($env:CONDA, "$tools\env")) {
        if ($candidate -and (Add-CondaToPath $candidate)) { break }
    }
}

if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
    Write-Host "bootstrapping conda-build into $tools"
    New-Item -ItemType Directory -Force -Path $tools | Out-Null

    $archive = Join-Path $env:TEMP 'micromamba.tar.bz2'
    Invoke-WebRequest -OutFile $archive -Uri 'https://micro.mamba.pm/api/micromamba/win-64/latest'
    tar -xj -C $tools -f $archive
    Remove-Item $archive

    $env:MAMBA_ROOT_PREFIX = $tools
    & "$tools\Library\bin\micromamba.exe" create -y `
        -p "$tools\env" -c conda-forge --override-channels `
        conda conda-build anaconda-client
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    if (-not (Add-CondaToPath "$tools\env")) { throw "conda not found after bootstrap" }
}

if (-not (conda list -n base conda-build | Select-String '^conda-build ')) {
    conda install -y -n base -c conda-forge conda-build anaconda-client
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

conda build . -c conda-forge --override-channels --no-anaconda-upload --output-folder $output
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$packages = Get-ChildItem -Path $output -Recurse -Filter *.conda
$packages | ForEach-Object { Write-Host $_.FullName }

if ($env:ANACONDA_API_TOKEN) {
    foreach ($package in $packages) {
        conda run -n base --no-capture-output anaconda org upload --skip-existing $package.FullName
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}
