# After the engine exits: a pending in-game multiplayer request rides
# an F15 key binding (instant from ui; cvar sets die in paused menus).
$root = Split-Path -Parent $PSScriptRoot
$ini = Join-Path $root "dist\playtest.ini"
if (-not (Test-Path $ini)) { exit 0 }
$line = Select-String -Path $ini -Pattern '^F15=wolf_mp_marker (.+)$'
if (-not $line) { exit 0 }
$req = $line.Matches[0].Groups[1].Value.Trim()
(Get-Content $ini) | Where-Object { $_ -notmatch '^F15=' } | Set-Content $ini
if (-not $req) { exit 0 }
$parts = $req -split ' '
$mpl = Join-Path $root "tools\mp_launch.ps1"
switch ($parts[0]) {
    "host"   { & $mpl -Mode host -Players ([int]$parts[1]) }
    "hostdm" { & $mpl -Mode host -Players ([int]$parts[1]) -Deathmatch }
    "join"   { & $mpl -Mode join }
}
