# WolfDoom multiplayer launcher core. Called by multiplayer.bat.
# Host: tries UPnP port mapping, copies the invite code, launches -host.
# Join: takes a code (or reads the clipboard), launches -join.
param([string]$Mode, [int]$Players = 2, [string]$Code = "",
      [switch]$Deathmatch, [int]$FragLimit = -1, [int]$TimeLimit = -1,
      [switch]$Quiet)

function New-WolfButton([string]$text, [int]$x, [int]$y, [int]$w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, 40)
    $b.FlatStyle = "Flat"
    $b.BackColor = [System.Drawing.Color]::FromArgb(113, 0, 0)
    $b.ForeColor = [System.Drawing.Color]::FromArgb(255, 247, 0)
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(182, 174, 0)
    $b.FlatAppearance.BorderSize = 2
    $b.Font = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)
    return $b
}

function New-WolfLabel([string]$text, [int]$y, [int]$size, $color, [System.Windows.Forms.Form]$form) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Font = New-Object System.Drawing.Font("Consolas", $size, [System.Drawing.FontStyle]::Bold)
    $l.ForeColor = $color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.AutoSize = $false
    $l.TextAlign = "MiddleCenter"
    $l.Location = New-Object System.Drawing.Point(0, $y)
    $l.Size = New-Object System.Drawing.Size($form.ClientSize.Width, [int]($size * 2.2))
    return $l
}

function Show-WolfDialog([string]$header, [string]$code, [string[]]$lines, [string]$warn, [string]$okText) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $gold = [System.Drawing.Color]::FromArgb(255, 247, 0)
    $grey = [System.Drawing.Color]::FromArgb(195, 195, 195)
    $red  = [System.Drawing.Color]::FromArgb(216, 80, 80)
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "WOLFDOOM"
    $f.FormBorderStyle = "FixedDialog"
    $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.StartPosition = "CenterScreen"
    $f.TopMost = $true
    $f.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $h = 250 + $(if ($warn) { 60 } else { 0 }) + $(if ($code) { 60 } else { 0 })
    $f.ClientSize = New-Object System.Drawing.Size(640, $h)
    $y = 18
    $f.Controls.Add((New-WolfLabel $header $y 16 $gold $f)); $y += 46
    if ($code) {
        $f.Controls.Add((New-WolfLabel $code $y 26 $gold $f)); $y += 70
    }
    foreach ($ln in $lines) {
        $f.Controls.Add((New-WolfLabel $ln $y 10 $grey $f)); $y += 28
    }
    if ($warn) {
        $wl = New-WolfLabel $warn $y 9 $red $f
        $wl.Size = New-Object System.Drawing.Size($f.ClientSize.Width, 56)
        $f.Controls.Add($wl); $y += 60
    }
    $by = $f.ClientSize.Height - 58
    if ($code) {
        $bc = New-WolfButton "COPY CODE AGAIN" 60 $by 240
        $script:wolfCode = $code
        $bc.Add_Click({
            Set-Clipboard -Value $script:wolfCode
            $this.Text = "COPIED!"
        })
        $f.Controls.Add($bc)
        $bg = New-WolfButton $okText 340 $by 240
    } else {
        $bg = New-WolfButton $okText 200 $by 240
    }
    $bg.Add_Click({ $f.Close() }.GetNewClosure())
    $f.Controls.Add($bg)
    $f.AcceptButton = $bg
    $f.ShowDialog() | Out-Null
}

function Show-Msg([string]$text) {

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($text, "WolfDoom Multiplayer") | Out-Null
}

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
    if ($Quiet) {
        $warn = if (-not $upnp -and $pub) { "Router note: automatic port setup (UPnP) failed. If internet friends cannot connect, you can both install Tailscale (free) and share the code it gives you instead." } else { "" }
        Show-WolfDialog "YOUR INVITE CODE" $code @(
            "Already copied to your clipboard - paste it to your friends now.",
            "Same-house players can use: $lan",
            "The game begins when everyone has joined.") $warn "START HOSTING"
    }
    Write-Host ""
    Write-Host "  Waiting for $Players players total..."
    if ($Deathmatch) {
        # rulesets: engine-native, serverinfo - the host's values
        # replicate to every joiner. 0 disables either limit. The menu
        # passes them via the marker; prompts are the terminal path only.
        if ($FragLimit -ge 0) {
            $fl = $FragLimit; $tl = [Math]::Max(0, $TimeLimit)
        } elseif ($Quiet) {
            $fl = 10; $tl = 0
        } else {
            $fl = Read-Host "  First to how many frags wins? (Enter = 10, 0 = no limit)"
            if ($fl -notmatch "^[0-9]+$") { $fl = 10 }
            $tl = Read-Host "  Time limit in minutes? (Enter = none)"
            if ($tl -notmatch "^[0-9]+$") { $tl = 0 }
        }
    }
    $modeargs = if ($Deathmatch) { @("-deathmatch", "-nomonsters", "+set", "sv_spawnfarthest", "1", "+set", "sv_samelevel", "1", "+set", "sv_itemrespawn", "1", "+set", "fraglimit", "$fl", "+set", "timelimit", "$tl", "+map", "MAP09") } else { @("+map", "LOBBY") }
    $svargs = ((& "$root\tools\mod_args.ps1") -split " ")
    & "$root\engine\uzdoom.exe" -host $Players @modeargs @svargs -iwad "$root\dist\wolf.ipk3" -config "$root\dist\playtest.ini" +set wolf_dbg_arm 0 +set show_obituaries 0 +set i_pauseinbackground 0
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
    $modeargs = if ($Deathmatch) { @("-deathmatch", "-nomonsters", "+set", "sv_spawnfarthest", "1", "+set", "sv_samelevel", "1", "+set", "sv_itemrespawn", "1", "+set", "fraglimit", "$fl", "+set", "timelimit", "$tl", "+map", "MAP09") } else { @("+map", "LOBBY") }
    Write-Host ""
    Write-Host "  Launching host window (left)..."
    $svargs = ((& "$root\tools\mod_args.ps1") -split " ")
    Start-Process -FilePath "$root\engine\uzdoom.exe" -ArgumentList (@("-host","2") + $modeargs + $svargs + @("-iwad","$root\dist\wolf.ipk3","-config","$root\dist\local_host.ini","+set","wolf_dbg_arm","0","+set","show_obituaries","0","+set","i_pauseinbackground","0","+set","vid_activeinbackground","1","+set","i_soundinbackground","1") + $vidH)
    Start-Sleep -Seconds 4
    Write-Host "  Launching joiner window (right)..."
    & "$root\engine\uzdoom.exe" -join localhost -iwad "$root\dist\wolf.ipk3" -config "$root\dist\local_join.ini" +set wolf_dbg_arm 0 +set show_obituaries 0 +set snd_musicvolume 0 +set wolf_skin 1 +set color '24 24 d8' +set i_pauseinbackground 0 +set vid_activeinbackground 1 +set i_soundinbackground 1 @vidJ
}
elseif ($Mode -eq "join") {

    if (-not $Code) {
        try { $Code = ([string](Get-Clipboard -Raw)).Trim() } catch {}
    }
    # a code must look like an address; the quiet path explains and
    # exits instead of prompting in a window nobody can see
    if ($Quiet -and (-not ($Code -match "^[A-Za-z0-9\.\-:]+$") -or $Code.Length -lt 2)) {
        Show-WolfDialog "NO INVITE CODE FOUND" "" @(
            "Your clipboard does not contain an invite code.",
            "Ask the host for their code and copy it,",
            "then open the game and choose Multiplayer > Join again.") "" "OK"
        exit 0
    }
    while (-not ($Code -match "^[A-Za-z0-9\.\-:]+$") -or $Code.Length -lt 2) {
        Write-Host ""
        Write-Host "  No usable invite code on the clipboard."
        $Code = (Read-Host "  Type the code (or 'localhost' to join a host on THIS pc)").Trim()
    }
    Write-Host "  Joining $Code ..."
    & "$root\engine\uzdoom.exe" -join $Code -iwad "$root\dist\wolf.ipk3" -config "$root\dist\join.ini" +set wolf_dbg_arm 0 +set show_obituaries 0 +set i_pauseinbackground 0
}
