@echo off
REM Open the voxel gallery: every generated model standing beside the
REM original sprite it was derived from. Rebuilds the pack first so it
REM always reflects the current pipeline, then drops straight into the
REM exhibition hall - no menu, no episode select.
REM
REM Pass extra engine args through, e.g.:  gallery.bat +freeze 1
cd /d "%~dp0"

if not exist "dist\wolf.ipk3" (
    echo No build found - run play.bat once to compile the game first.
    goto :fail
)

if exist tools\voxel\gallery.py (
    echo Building the voxel gallery...
    python tools\voxel\gallery.py || goto :fail
)
if not exist "dist\wolfvox_gallery.pk3" (
    echo dist\wolfvox_gallery.pk3 is missing and could not be built.
    goto :fail
)

engine\uzdoom.exe -iwad "dist\wolf.ipk3" -file "dist\wolfvox_gallery.pk3" ^
    +map GALLERY %*
goto :eof

:fail
echo.
pause
exit /b 1
