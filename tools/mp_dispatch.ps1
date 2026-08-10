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
# the in-game menu appends "spear" when the session is Spear of
# Destiny, so the relaunch comes back up in the same game
$iwad = if ($req -match '(?i)spear') { "spear.ipk3" } else { "wolf.ipk3" }
$mpl = Join-Path $root "tools\mp_launch.ps1"
switch ($parts[0]) {
    "host"   { & $mpl -Mode host -Players ([int]$parts[1]) -Iwad $iwad -Quiet }
    "hostdm" {
        $fl = 10; $tl = 0; $arena = "DM1"
        if ($parts.Count -gt 2) {
            foreach ($p in $parts[2..($parts.Count - 1)]) {
                if ($p -match '^f([0-9]+)$') { $fl = [int]$Matches[1] }
                if ($p -match '^t([0-9]+)$') { $tl = [int]$Matches[1] }
                # arena rides as m<MAP>; the menu writes the map name
                if ($p -match '^m([A-Za-z0-9]+)$') { $arena = $Matches[1] }
            }
        }
        & $mpl -Mode host -Players ([int]$parts[1]) -Deathmatch -FragLimit $fl -TimeLimit $tl -Arena $arena -Iwad $iwad -Quiet
    }
    "join"   { & $mpl -Mode join -Iwad $iwad -Quiet }
}
