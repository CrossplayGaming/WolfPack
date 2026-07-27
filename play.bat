@echo off
REM Launch the current WolfDoom build (rebuilds the IPK3 first, ~1s).
REM Pass extra args through, e.g.:  play.bat +map MAP03
cd /d "%~dp0"

if not exist "build\assets\PLAYPAL" (
    echo First run: extracting assets from your game data...
    python tools\extract_levels.py || goto :fail
    python tools\extract_vswap.py || goto :fail
    python tools\extract_audio.py || goto :fail
    python tools\convert_udmf.py || goto :fail
    python tools\make_assets.py || goto :fail
)

python build.py || goto :fail
REM freelook is forced off at launch: Wolf has no vertical aim, and a
REM value archived in the config otherwise overrides the DEFCVARS default.
start "" "engine\uzdoom.exe" -iwad "dist\wolf.ipk3" -config "dist\playtest.ini" +set freelook 0 %*
exit /b 0

:fail
echo.
echo Build failed - see output above.
pause
exit /b 1
