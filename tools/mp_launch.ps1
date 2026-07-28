# WolfDoom multiplayer launcher core. Called by multiplayer.bat.
# Host: tries UPnP port mapping, copies the invite code, launches -host.
# Join: takes a code (or reads the clipboard), launches -join.
param([string]$Mode, [int]$Players = 2, [string]$Code = "",
      [switch]$Deathmatch)

$ErrorActionPreference = "SilentlyContinue"
$root = Split-Path -Parent $PSScriptRoot
$port = 5029

if ($Mode -eq "host") {
    # try to open the port automatically (UPnP; most home routers)
    $upnp = $false
    try {
        $nat = New-Object -ComObject HNetCfg.NATUPnP
        $col = $nat.StaticPortMappingCollection
        if ($null -ne $col) {
            $ip = (Get-NetIPAddress -AddressFamily IPv4 |
                Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
                Select-Object -First 1).IPAddress
            $col.Add($port, "UDP", $port, $ip, $true, "WolfDoom") | Out-Null
            $upnp = $true
        }
    } catch {}

    $pub = ""
    try { $pub = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5) } catch {}
    $lan = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
        Select-Object -First 1).IPAddress

    $code = if ($pub) { $pub } else { $lan }
    Set-Clipboard -Value $code
    Write-Host ""
    Write-Host "  INVITE CODE (already copied to your clipboard):  $code"
    Write-Host "  Send it to your friends. Same-house players can use: $lan"
    if (-not $upnp -and $pub) {
        Write-Host ""
        Write-Host "  NOTE: your router did not accept automatic setup (UPnP)."
        Write-Host "  Internet friends may fail to connect. Easiest fix: both"
        Write-Host "  install Tailscale (free), then share the code it gives you."
    }
    Write-Host ""
    Write-Host "  Waiting for $Players players total..."
    $modeargs = if ($Deathmatch) { @("-deathmatch", "-nomonsters", "+map", "MAP09") } else { @("+map", "LOBBY") }
    & "$root\engine\uzdoom.exe" -host $Players @modeargs -iwad "$root\dist\wolf.ipk3" -config "$root\dist\playtest.ini" +set wolf_dbg_arm 0
}
elseif ($Mode -eq "join") {
    if (-not $Code) {
        try { $Code = ([string](Get-Clipboard -Raw)).Trim() } catch {}
    }
    # a code must look like an address; anything else re-prompts
    while (-not ($Code -match "^[A-Za-z0-9\.\-:]+$") -or $Code.Length -lt 2) {
        Write-Host ""
        Write-Host "  No usable invite code on the clipboard."
        $Code = (Read-Host "  Type the code (or 'localhost' to join a host on THIS pc)").Trim()
    }
    Write-Host "  Joining $Code ..."
    & "$root\engine\uzdoom.exe" -join $Code -iwad "$root\dist\wolf.ipk3" -config "$root\dist\join.ini" +set wolf_dbg_arm 0
}
