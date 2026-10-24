@echo off
rem ============================================================
rem  Nebula on the Ship - Among Us Mod Injector (Windows Batch)
rem
rem  Usage:
rem    NebulaInject.bat install    - Run NebulaInjector.ps1 -Action Install
rem    NebulaInject.bat uninstall  - Run NebulaInjector.ps1 -Action Uninstall
rem    NebulaInject.bat status     - Run NebulaInjector.ps1 -Action Status
rem    NebulaInject.bat             - Default: install
rem ============================================================
setlocal
set "GAME=C:\Among_92595"
set "INJ=C:\NebulaInjector\NebulaInjector.ps1"

echo ============================================
echo   Nebula on the Ship - Among Us Mod Injector
echo ============================================
echo.

if /i "%~1"=="uninstall" goto :UNINSTALL
if /i "%~1"=="status" goto :STATUS
if /i "%~1"=="" goto :INSTALL
echo Unknown action "!%~1"!
goto :END

:INSTALL
echo [Install] Running NebulaInjector.ps1 -Action Install ...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!INJ!" -Action Install -GamePath "!GAME!"
if errorlevel 1 goto :FAIL
echo [OK] Install finished.
echo.
echo [Status] Post-install check:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!INJ!" -Action Status -GamePath "!GAME!"
goto :END

:UNINSTALL
echo [Uninstall] Running NebulaInjector.ps1 -Action Uninstall ...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!INJ!" -Action Uninstall -GamePath "!GAME!"
if errorlevel 1 goto :FAIL
echo [OK] Uninstall finished.
goto :END

:STATUS
echo [Status] Running NebulaInjector.ps1 -Action Status -GamePath "!GAME!" ...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!INJ!" -Action Status -GamePath "!GAME!"
goto :END

:FAIL
echo.
echo [FAIL] Step failed, see output above.
pause
exit /b 1

:END
endlocal
exit /b 0
