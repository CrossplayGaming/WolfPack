@echo off
REM Launch the current WolfDoom build (rebuilds first). Runs the

REM engine in the FOREGROUND: on exit, a pending in-game multiplayer

REM request (wolf_mp_request in the config) restarts into host/join.
REM Pass extra args through, e.g.:  play.bat +map MAP03
cd /d "%~dp0"

REM Packaged builds ship without the compiler: skip build steps
if not exist build.py goto :run
if not exist "reference\wolfsrc\WOLFSRC\OBJ\GAMEPAL.OBJ" (
    echo The id GPL source release is missing - run SETUP.bat first.
    goto :fail
)
if not exist "build\assets\PLAYPAL" (
    echo First run: extracting assets from your game data...
    python tools\extract_levels.py || goto :fail
    python tools\extract_vswap.py || goto :fail
    python tools\extract_audio.py || goto :fail
    python tools\extract_vgagraph.py || goto :fail
    python tools\extract_text.py || goto :fail
    python tools\convert_udmf.py || goto :fail
    python tools\import_bj_sheet.py || goto :fail
    python tools\make_assets.py || goto :fail
)

python build.py || goto :fail
:run
REM No screen wipe (Wolf has none between levels), and mouse is
REM horizontal only: no vertical aim (freelook 0), no mouse-Y move
REM (m_forward 0) -> horizontal turn only, per D-004. Forced at launch
REM because an archived config value overrides the DEFCVARS default.
REM The wolf_dbg_ switches are forced off the same way: even declared
REM nosave, a stale archived value still LOADS if the ini has the line,
REM so one boss.bat session could leak the full arsenal into normal play.
for /f "usebackq delims=" %%m in (`powershell -ExecutionPolicy Bypass -File tools\mod_args.ps1`) do set "MODARGS=%%m"
"engine\uzdoom.exe" -iwad "dist\wolf.ipk3" -config "dist\playtest.ini" %MODARGS% +set m_forward 0 +set wipetype 0 +set wolf_dbg_arm 0 +set wolf_dbg_doortest 0 +set wolf_dbg_alert 0 +set wolf_dbg_forcefire 0 +set wolf_dbg_victory 0 +set wolf_dbg_boss 0 %*

powershell -ExecutionPolicy Bypass -File tools\mp_dispatch.ps1

exit /b 0

:fail
echo.
echo Build failed - see output above.
powershell -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('The game build failed. Run play.bat from a terminal to see the details.','WolfDoom') | Out-Null"
exit /b 1
