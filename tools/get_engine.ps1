# Download the latest official UZDoom release into engine\.
# Official source: https://github.com/UZDoom/UZDoom/releases
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $root "engine"
Write-Host "  Checking the latest UZDoom release..."
$rel = Invoke-RestMethod "https://api.github.com/repos/UZDoom/UZDoom/releases/latest"
$asset = $rel.assets | Where-Object { $_.name -match "^Windows-UZDoom-.*\.zip$" } | Select-Object -First 1
if (-not $asset) {
    $asset = $rel.assets | Where-Object { $_.name -match "(?i)windows.*\.zip$" } | Select-Object -First 1
}
if (-not $asset) { Write-Host "  No Windows zip in the latest release - download manually from github.com/UZDoom/UZDoom/releases"; exit 1 }
Write-Host "  Downloading $($asset.name) ($([math]::Round($asset.size / 1MB)) MB)..."
$tmp = Join-Path $env:TEMP $asset.name
Invoke-WebRequest $asset.browser_download_url -OutFile $tmp
Write-Host "  Extracting into engine\..."
New-Item -ItemType Directory -Force $engine | Out-Null
Expand-Archive -Path $tmp -DestinationPath $engine -Force
Remove-Item $tmp
# some zips wrap everything in a single folder - flatten it
if (-not (Test-Path (Join-Path $engine "uzdoom.exe"))) {
    $sub = Get-ChildItem $engine -Directory | Where-Object { Test-Path (Join-Path $_.FullName "uzdoom.exe") } | Select-Object -First 1
    if ($sub) {
        Get-ChildItem $sub.FullName | Move-Item -Destination $engine -Force
        Remove-Item $sub.FullName -Recurse -Force
    }
}
if (Test-Path (Join-Path $engine "uzdoom.exe")) {
    Write-Host "  UZDoom ready."
    exit 0
}
Write-Host "  Something went wrong - engine\uzdoom.exe still missing."
exit 1
