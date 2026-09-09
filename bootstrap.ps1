# Builds the package. Installs Miniforge if needed; uploads if ANACONDA_API_TOKEN is set.
$ErrorActionPreference = 'Stop'

$prefix = if ($env:MINIFORGE_PREFIX) { $env:MINIFORGE_PREFIX } else { "$env:USERPROFILE\miniforge3" }
$output = 'build_artifacts'

if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path $prefix)) {
        $installer = Join-Path $env:TEMP 'Miniforge3-Windows-x86_64.exe'

        Write-Host "installing Miniforge into $prefix"
        Invoke-WebRequest -OutFile $installer -Uri `
            'https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Windows-x86_64.exe'
        Start-Process -FilePath $installer -ArgumentList '/S', "/D=$prefix" -Wait
        Remove-Item $installer
    }

    & "$prefix\shell\condabin\conda-hook.ps1"
    conda activate base
}

if (-not (conda list -n base conda-build | Select-String '^conda-build ')) {
    conda install -y -n base -c conda-forge conda-build anaconda-client
}

conda build . -c conda-forge --override-channels --no-anaconda-upload --output-folder $output
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$packages = Get-ChildItem -Path $output -Recurse -Filter *.conda
$packages | ForEach-Object { Write-Host $_.FullName }

if ($env:ANACONDA_API_TOKEN) {
    foreach ($package in $packages) {
        conda run -n base --no-capture-output `
            anaconda org upload --skip-existing $package.FullName
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}
