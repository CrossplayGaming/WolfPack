@echo off
REM WolfDoom multiplayer - host or join with zero manual setup.
cd /d "%~dp0"
echo.
echo   === WOLFDOOM MULTIPLAYER ===
echo.
echo   1 - Host a game  (friends join you)
echo   2 - Join a game  (invite code on your clipboard, or type it)
echo   3 - Test on this PC (two windows side by side)
echo.
choice /c 123 /n /m "  Choose: "
if errorlevel 3 goto local
if errorlevel 2 goto join
REM host rebuilds (fresh build for the session); joiners must NOT -
REM they need to match the host, and the running host locks the pk3
python build.py || (echo Build failed & pause & exit /b 1)
set /p NUM="  How many players total (2-8)? "
powershell -ExecutionPolicy Bypass -File tools\mp_launch.ps1 -Mode host -Players %NUM%
exit /b 0
:local
python build.py || (echo Build failed & pause & exit /b 1)
choice /c CD /n /m "  (C)o-op lobby or (D)eathmatch arena? "
if errorlevel 2 (
    powershell -ExecutionPolicy Bypass -File tools\mp_launch.ps1 -Mode local -Deathmatch
) else (
    powershell -ExecutionPolicy Bypass -File tools\mp_launch.ps1 -Mode local
)
exit /b 0
:join
set /p CODE="  Invite code (Enter = use clipboard): "
powershell -ExecutionPolicy Bypass -File tools\mp_launch.ps1 -Mode join -Code "%CODE%"
exit /b 0
