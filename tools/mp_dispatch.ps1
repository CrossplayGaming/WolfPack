# After the engine exits: a pending in-game multiplayer request rides
# an F15 key binding (instant from ui; cvar sets die in paused menus).
# In-game requests run QUIET: no terminal prompts, GUI dialogs only.
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
    "host"   { & $mpl -Mode host -Players ([int]$parts[1]) -Quiet }
    "hostdm" {
        $fl = 10; $tl = 0
        if ($parts.Count -gt 2) {
            foreach ($p in $parts[2..($parts.Count - 1)]) {
                if ($p -match '^f([0-9]+)$') { $fl = [int]$Matches[1] }
                if ($p -match '^t([0-9]+)$') { $tl = [int]$Matches[1] }
            }
        }
        & $mpl -Mode host -Players ([int]$parts[1]) -Deathmatch -FragLimit $fl -TimeLimit $tl -Quiet
    }
    "join"   { & $mpl -Mode join -Quiet }
}
