# Emit the +set sv_* args that enforce the archived Modernization
# choices (wolf_mod_* user cvars, [WolfDoom.Player] section). The sv
# tri-states never archive and cvar writes are menu/launch-only, so
# every launcher translates the truth cvars into engine gates here.
# 1 = force-deny (classic), 2 = force-allow (modern).
param([string]$Ini = "", [string]$Game = "wl6")
if (-not $Ini) { $Ini = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "dist\playtest.ini" }
$vals = @{ jump = 0; crouch = 0; freelook = 0 }
if (Test-Path $Ini) {
    foreach ($k in @($vals.Keys)) {
        $m = Select-String -Path $Ini -Pattern ("^wolf_mod_" + $k + "=(.+)$") | Select-Object -First 1
        if ($m -and $m.Matches[0].Groups[1].Value.Trim() -notin @("0", "false")) { $vals[$k] = 1 }
    }
}
$out = @()
foreach ($pair in @(@("jump", "sv_jump"), @("crouch", "sv_crouch"), @("freelook", "sv_freelook"))) {
    $out += "+set"; $out += $pair[1]; $out += $(if ($vals[$pair[0]]) { "2" } else { "1" })
}
# HD pack files: converted locally by tools/convert_hdpack.py from the
# user's own RMST download; toggles apply at launch because the engine
# cannot load wads mid-session. The texture pack is per game - both
# games number their walls and sprites from zero, so Spear's pack would
# paint cobblestone over Wolf3D's doors.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tex = if ($Game -eq "sod") { "dist\hdtex_sod.pk3" } else { "dist\hdtex.pk3" }
foreach ($pack in @(@("hdtex", $tex), @("hdsfx", "dist\hdsfx.pk3"))) {
    $m = Select-String -Path $Ini -Pattern ("^wolf_mod_" + $pack[0] + "=(.+)$") -ErrorAction SilentlyContinue | Select-Object -First 1
    $on = $m -and $m.Matches[0].Groups[1].Value.Trim() -notin @("0", "false")
    if ($on -and (Test-Path (Join-Path $root $pack[1]))) {
        $out += "-file"; $out += (Join-Path $root $pack[1])
    }
}
$out -join " "
