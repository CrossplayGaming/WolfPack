@echo off
REM WolfDoom multiplayer - host or join with zero manual setup.
cd /d "%~dp0"
python build.py || (echo Build failed & pause & exit /b 1)
echo.
echo   === WOLFDOOM MULTIPLAYER ===
echo.
echo   1 - Host a game  (friends join you)
echo   2 - Join a game  (invite code on your clipboard, or type it)
echo.
choice /c 12 /n /m "  Choose: "
if errorlevel 2 goto join
set /p NUM="  How many players total (2-8)? "
powershell -ExecutionPolicy Bypass -File tools\mp_launch.ps1 -Mode host -Players %NUM%
exit /b 0
:join
set /p CODE="  Invite code (Enter = use clipboard): "
powershell -ExecutionPolicy Bypass -File tools\mp_launch.ps1 -Mode join -Code "%CODE%"
exit /b 0
