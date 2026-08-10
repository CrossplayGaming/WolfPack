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
REM they need to match the host, and the running host locks the pk3.
REM Packaged builds ship without the compiler: nothing to rebuild.
if exist build.py python build.py || (echo Build failed & pause & exit /b 1)
set /p NUM="  How many players total (2-8)? "
powershell -ExecutionPolicy Bypass -File tools\mp_launch.ps1 -Mode host -Players %NUM%
exit /b 0
:local
if exist build.py python build.py || (echo Build failed & pause & exit /b 1)
choice /c CD /n /m "  (C)o-op lobby or (D)eathmatch arena? "
if errorlevel 2 goto localdm
powershell -ExecutionPolicy Bypass -File tools\mp_launch.ps1 -Mode local
exit /b 0
:localdm
echo.
echo   Which arena?
echo     1 - Kesselring      four corner halls around a pillared keep
echo     2 - Kanalstrasse    a street with uneven side rooms
echo     3 - Zwillingshalle  twin halls, two unequal links
echo     4 - Der Kaefig      nine cells, every one doored on all sides
echo     5 - Sankt Kreuz     a pillared nave with side aisles
echo     6 - Hans's Level    the arena that shipped before these
echo.
set "PICK="
set /p PICK="  Arena (1-6, Enter = 1): "
REM plain if/else, not choice+errorlevel: errorlevel means "N or above",
REM and the descending-test dance it needs is exactly the sort of thing
REM that works here and misfires on someone else's machine
set "ARENA=DM1"
if "%PICK%"=="2" set "ARENA=DM2"
if "%PICK%"=="3" set "ARENA=DM3"
if "%PICK%"=="4" set "ARENA=DM4"
if "%PICK%"=="5" set "ARENA=DM5"
if "%PICK%"=="6" set "ARENA=MAP09"
echo   Arena: %ARENA%
powershell -ExecutionPolicy Bypass -File tools\mp_launch.ps1 -Mode local -Deathmatch -Arena %ARENA%
exit /b 0

:join
set /p CODE="  Invite code (Enter = use clipboard): "
powershell -ExecutionPolicy Bypass -File tools\mp_launch.ps1 -Mode join -Code "%CODE%"
exit /b 0
