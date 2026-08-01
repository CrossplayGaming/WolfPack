# HD pack acquisition + conversion (ECWolf RMST by its ModDB author).
# WolfPack ships no HD art: this fetches the user's own copy and
# converts it locally (tools/convert_hdpack.py) into dist/hdtex.pk3 +
# dist/hdsfx.pk3, which the Modernization toggles then load at launch.
#
# ModDB has no stable direct-download URLs, so the flow is:
#   1. If the pack is already on disk (common locations + Downloads),
#      convert it straight away.
#   2. Otherwise open the ModDB page, wait for the user to download,
#      then convert from Downloads.
$root = Split-Path -Parent $PSScriptRoot
$page = "https://www.moddb.com/games/wolfenstein-3d/addons/ecwolf-rmst"

function Find-Pack {
    $spots = @(
        "F:\Retro and Emulation\ECWolf_RMST",
        (Join-Path $env:USERPROFILE "Downloads\ECWolf_RMST"),
        (Join-Path $env:USERPROFILE "Downloads")
    )
    foreach ($s in $spots) {
        if (Test-Path (Join-Path $s "ECWolf_RMST.pk3")) { return $s }
    }
    # a still-zipped download?
    $zip = Get-ChildItem (Join-Path $env:USERPROFILE "Downloads") `
        -Filter "*RMST*.zip" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($zip) {
        $dst = Join-Path $env:USERPROFILE "Downloads\ECWolf_RMST"
        Expand-Archive $zip.FullName $dst -Force
        if (Test-Path (Join-Path $dst "ECWolf_RMST.pk3")) { return $dst }
        $inner = Get-ChildItem $dst -Recurse -Filter "ECWolf_RMST.pk3" |
            Select-Object -First 1
        if ($inner) { return $inner.DirectoryName }
    }
    return $null
}

$src = Find-Pack
if (-not $src) {
    Write-Host "RMST pack not found. Opening its ModDB page - download"
    Write-Host "the addon, then run this script again."
    Start-Process $page
    exit 1
}
Write-Host "Converting RMST pack from: $src"
& python (Join-Path $root "tools\convert_hdpack.py") $src
if ($LASTEXITCODE -eq 0) {
    Write-Host "Done. Enable 'HD Textures' / 'HD Sounds' in the"
    Write-Host "Modernization menu - they apply on the next launch."
}
