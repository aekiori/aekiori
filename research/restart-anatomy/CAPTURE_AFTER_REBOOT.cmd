@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\capture-post-reboot.ps1" %*
set "RA_EXIT=%ERRORLEVEL%"
echo.
if not "%RA_EXIT%"=="0" echo Capture exited with code %RA_EXIT%.
pause
exit /b %RA_EXIT%
