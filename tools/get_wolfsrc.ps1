# Download id Software's GPL Wolfenstein 3D source release into
# reference/wolfsrc - the build's behavior spec and data source (the
# palette and the audio/graphics name tables are parsed from it).
# Official repo: https://github.com/id-Software/wolf3d (GPL).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root "reference\wolfsrc"
Write-Host "  Downloading the id Software GPL source release..."
$tmp = Join-Path $env:TEMP "wolf3d-src.zip"
Invoke-WebRequest "https://github.com/id-Software/wolf3d/archive/refs/heads/master.zip" -OutFile $tmp
$stage = Join-Path $env:TEMP "wolf3d-src-stage"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
Expand-Archive -Path $tmp -DestinationPath $stage
Remove-Item $tmp
$inner = Get-ChildItem $stage -Directory | Select-Object -First 1
New-Item -ItemType Directory -Force (Split-Path -Parent $dest) | Out-Null
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Move-Item $inner.FullName $dest
Remove-Item $stage -Recurse -Force
if (Test-Path (Join-Path $dest "WOLFSRC\OBJ\GAMEPAL.OBJ")) {
    Write-Host "  Source release ready."
    exit 0
}
Write-Host "  Something went wrong - WOLFSRC\OBJ\GAMEPAL.OBJ still missing."
exit 1
