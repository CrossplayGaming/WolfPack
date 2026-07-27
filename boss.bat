@echo off
REM Drop straight into a boss fight, fully armed, with the right settings.
REM
REM   boss.bat            -> Hans Grosse   (E1)
REM   boss.bat schabbs    -> Dr. Schabbs   (E2)
REM   boss.bat hitler     -> Hitler        (E3, mech suit then the man)
REM   boss.bat gift       -> Otto Giftmacher (E4)
REM   boss.bat gretel     -> Gretel Grosse (E5)
REM   boss.bat fat        -> General Fettgesicht (E6)
REM
REM Add a skill number to change difficulty, e.g.  boss.bat hitler 4
cd /d "%~dp0"

set MAP=MAP09
if /i "%~1"=="hans"    set MAP=MAP09
if /i "%~1"=="schabbs" set MAP=MAP19
if /i "%~1"=="fake"    set MAP=MAP29
if /i "%~1"=="hitler"  set MAP=MAP29
if /i "%~1"=="gift"    set MAP=MAP39
if /i "%~1"=="gretel"  set MAP=MAP49
if /i "%~1"=="fat"     set MAP=MAP59

set SKILL=3
if not "%~2"=="" set SKILL=%~2

python build.py || goto :fail
echo Launching %MAP% at skill %SKILL% (chaingun, MG, 99 ammo, both keys).
start "" "engine\uzdoom.exe" -iwad "dist\wolf.ipk3" -config "dist\playtest.ini" ^
 +set freelook 0 +set m_forward 0 +set wipetype 0 +set wolf_dbg_arm 1 ^
 -skill %SKILL% +map %MAP%
exit /b 0

:fail
echo.
echo Build failed - see output above.
pause
exit /b 1
