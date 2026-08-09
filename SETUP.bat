@echo off
REM ============================================================
REM  WOLFPACK SETUP - the compiler. Run this first.
REM  Turns this folder + the UZDoom engine + YOUR Wolfenstein 3D
REM  game data into a playable WolfPack build.
REM ============================================================
cd /d "%~dp0"
echo.
echo   === WOLFPACK SETUP ===
echo.

where python >nul 2>nul
if errorlevel 1 (
    echo   Python 3 is required. Install it from python.org
    echo   ^(check "Add python to PATH" during install^), then rerun.
    pause
    exit /b 1
)
python -c "import PIL" >nul 2>nul || pip install pillow
python -c "import pefile" >nul 2>nul || pip install pefile
python -c "import numpy" >nul 2>nul || pip install numpy
python -c "import soundfile" >nul 2>nul || pip install soundfile
python -c "import pyopl" >nul 2>nul || pip install pyopl

if exist engine\uzdoom.exe goto :haveengine
echo   The UZDoom engine is not in engine\ yet.
choice /c YN /n /m "  Download the latest official release now? (Y/N) "
if errorlevel 2 (
    echo   Get it from github.com/UZDoom/UZDoom/releases and extract
    echo   it into engine\ so engine\uzdoom.exe exists, then rerun.
    pause
    exit /b 1
)
powershell -ExecutionPolicy Bypass -File tools\get_engine.ps1 || (pause & exit /b 1)
:haveengine

if exist reference\wolfsrc\WOLFSRC\OBJ\GAMEPAL.OBJ goto :havesrc
echo   The build also needs id Software's GPL Wolfenstein 3D source
echo   release ^(the palette and data tables come from it^).
choice /c YN /n /m "  Download it from id's official GitHub now? (Y/N) "
if errorlevel 2 (
    echo   Get github.com/id-Software/wolf3d and extract it so that
    echo   reference\wolfsrc\WOLFSRC\ exists, then rerun.
    pause
    exit /b 1
)
powershell -ExecutionPolicy Bypass -File tools\get_wolfsrc.ps1 || (pause & exit /b 1)
:havesrc

if exist gamedata\*.WL6 goto :havedata
echo   NOTE: no WL6 files in gamedata\ - the build will look for a
echo   Steam install of Wolfenstein 3D automatically. If you do not
echo   have it on Steam, read gamedata\README.md first.
echo.
:havedata

echo   Building WolfPack from your game data...
python tools\extract_levels.py || goto :fail
python tools\extract_vswap.py || goto :fail
python tools\extract_audio.py || goto :fail
python tools\extract_vgagraph.py || goto :fail
python tools\extract_text.py || goto :fail
python tools\gen_dmmaps.py || goto :fail
python tools\convert_udmf.py || goto :fail

python tools\gen_flats.py || goto :fail
python tools\import_bj_sheet.py || goto :fail

python tools\import_bj_gun.py || goto :fail
echo   Rendering the AdLib soundtrack ^(one-time, takes a few minutes^)...
python tools\render_adlib.py --music || goto :fail
if exist gamedata\*.SOD python tools\render_adlib.py sod --music
if exist build\audio\sod\music python tools\render_adlib.py sod --music
python build.py || goto :fail

echo.
echo   ============================================
echo   Done! Double-click WolfPack.vbs to play.
echo   Multiplayer lives in the in-game menu.
echo   ============================================
choice /c YN /n /m "  Also build a portable package + installer exe? (Y/N) "
if errorlevel 2 goto :end
python tools\package.py && echo   Packages are in dist\package\
:end
pause
exit /b 0

:fail
echo.
echo   Build failed - see the output above.
pause
exit /b 1
