# After the engine exits: if the in-game menu left a multiplayer
# request in the config, clear it and hand off to mp_launch.ps1.
$root = Split-Path -Parent $PSScriptRoot
$ini = Join-Path $root "dist\playtest.ini"
if (-not (Test-Path $ini)) { exit 0 }
$line = Select-String -Path $ini -Pattern '^wolf_mp_request=(.+)$'
if (-not $line) { exit 0 }
$req = $line.Matches[0].Groups[1].Value.Trim()
(Get-Content $ini) | Where-Object { $_ -notmatch '^wolf_mp_request=' } |
    Set-Content $ini
if (-not $req) { exit 0 }
$parts = $req -split ' '
switch ($parts[0]) {
    "host"   { & "$root	ools\mp_launch.ps1" -Mode host -Players ([int]$parts[1]) }
    "hostdm" { & "$root	ools\mp_launch.ps1" -Mode host -Players ([int]$parts[1]) -Deathmatch }
    "join"   { & "$root	ools\mp_launch.ps1" -Mode join }
}
