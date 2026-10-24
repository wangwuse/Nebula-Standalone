@echo off
rem ============================================================
rem  Nebula on the Ship - FINAL Distribution Helper
rem
rem  What it does:
rem   1. Copies Nebula_Snapshot_26.10.17a.zip
rem   2. Copies NebulaInject.bat
rem   3. Copies NEBULA_README_FULL.txt
rem   4. Creates Nebula_FinalDist.zip containing those 3 files
rem
rem  Usage:
rem    NebulaDist.bat              -> create Nebula_FinalDist.zip
rem    NebulaDist.bat do           -> create Nebula_FinalDist.zip
rem ============================================================
setlocal
set "SRC=C:\NebulaShare\Nebula"
set "OUT=%SRC%\Nebula_FinalDist.zip"
set "TMP=%SRC%\_NebulaDist_tmp

if /i "%~1"=="" goto :DO
if /i "%~1"=="do" goto :DO
if /i "%~1"=="create" goto :DO
echo Unknown arg "!%~1"!
goto :END

:DO
echo [NebulaDist] Creating %OUT% ...
if exist "%TMP%" rmdir /s /q "%TMP%"
mkdir "%TMP%"
copy /y "%SRC%\Nebula_Snapshot_26.10.17a.zip" "%TMP%\Nebula_Snapshot_26.10.17a.zip"
copy /y "%SRC%\NebulaInject.bat" "%TMP%\NebulaInject.bat"
copy /y "%SRC%\NEBULA_README_FULL.txt" "%TMP%\NEBULA_README_FULL.txt"
"C:\Program Files\WinRAR\WinRAR.exe" a -r -tzip "%OUT%" "%TMP%\*"
echo [OK] Created %OUT%
goto :END

:END
endlocal
exit /b 0
