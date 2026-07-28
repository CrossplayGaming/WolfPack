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
    if ($Deathmatch) {
        # rulesets: engine-native, serverinfo - the host's values
        # replicate to every joiner. 0 disables either limit.
        $fl = Read-Host "  First to how many frags wins? (Enter = 10, 0 = no limit)"
        if ($fl -notmatch "^[0-9]+$") { $fl = 10 }
        $tl = Read-Host "  Time limit in minutes? (Enter = none)"
        if ($tl -notmatch "^[0-9]+$") { $tl = 0 }
        Write-Host "  Rules: $(if ([int]$fl) { "first to $fl frags" } else { "no frag limit" })$(if ([int]$tl) { ", $tl minute cap" })"
    }
    $modeargs = if ($Deathmatch) { @("-deathmatch", "-nomonsters", "+set", "sv_spawnfarthest", "1", "+set", "sv_samelevel", "1", "+set", "fraglimit", "$fl", "+set", "timelimit", "$tl", "+map", "MAP09") } else { @("+map", "LOBBY") }
    & "$root\engine\uzdoom.exe" -host $Players @modeargs -iwad "$root\dist\wolf.ipk3" -config "$root\dist\playtest.ini" +set wolf_dbg_arm 0 +set show_obituaries 0 +set i_pauseinbackground 0
}
elseif ($Mode -eq "local") {
    # Two windows on THIS pc, side by side, for solo multiplayer testing.
    # Throwaway configs (copied fresh from playtest.ini each run) so the
    # forced windowed-mode cvars never leak into the real config; the
    # joiner window keeps sound effects but drops music so audio does
    # not double up. Host launches first and gets a moment to bind the
    # port before the joiner connects to localhost.
    Copy-Item "$root\dist\playtest.ini" "$root\dist\local_host.ini" -Force
    Copy-Item "$root\dist\playtest.ini" "$root\dist\local_join.ini" -Force
    $w = 1720; $h = 968; $y = 300
    $vidH = @("+set","vid_fullscreen","0","+set","win_w","$w","+set","win_h","$h","+set","win_x","60","+set","win_y","$y")
    $vidJ = @("+set","vid_fullscreen","0","+set","win_w","$w","+set","win_h","$h","+set","win_x","2040","+set","win_y","$y")
    if ($Deathmatch) {
        # rulesets: engine-native, serverinfo - the host's values
        # replicate to every joiner. 0 disables either limit.
        $fl = Read-Host "  First to how many frags wins? (Enter = 10, 0 = no limit)"
        if ($fl -notmatch "^[0-9]+$") { $fl = 10 }
        $tl = Read-Host "  Time limit in minutes? (Enter = none)"
        if ($tl -notmatch "^[0-9]+$") { $tl = 0 }
        Write-Host "  Rules: $(if ([int]$fl) { "first to $fl frags" } else { "no frag limit" })$(if ([int]$tl) { ", $tl minute cap" })"
    }
    $modeargs = if ($Deathmatch) { @("-deathmatch", "-nomonsters", "+set", "sv_spawnfarthest", "1", "+set", "sv_samelevel", "1", "+set", "fraglimit", "$fl", "+set", "timelimit", "$tl", "+map", "MAP09") } else { @("+map", "LOBBY") }
    Write-Host ""
    Write-Host "  Launching host window (left)..."
    Start-Process -FilePath "$root\engine\uzdoom.exe" -ArgumentList (@("-host","2") + $modeargs + @("-iwad","$root\dist\wolf.ipk3","-config","$root\dist\local_host.ini","+set","wolf_dbg_arm","0","+set","show_obituaries","0","+set","i_pauseinbackground","0","+set","vid_activeinbackground","1","+set","i_soundinbackground","1") + $vidH)
    Start-Sleep -Seconds 4
    Write-Host "  Launching joiner window (right)..."
    & "$root\engine\uzdoom.exe" -join localhost -iwad "$root\dist\wolf.ipk3" -config "$root\dist\local_join.ini" +set wolf_dbg_arm 0 +set show_obituaries 0 +set snd_musicvolume 0 +set wolf_skin 1 +set i_pauseinbackground 0 +set vid_activeinbackground 1 +set i_soundinbackground 1 @vidJ
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
    & "$root\engine\uzdoom.exe" -join $Code -iwad "$root\dist\wolf.ipk3" -config "$root\dist\join.ini" +set wolf_dbg_arm 0 +set show_obituaries 0 +set i_pauseinbackground 0
}
