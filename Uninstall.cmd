@echo off
rem Double-click to undo the install (Windows goes back to its own fonts). Same as running uninstall.ps1.
rem You can also uninstall from Settings > Apps > Installed apps.
title Apple fonts on Windows 11 - uninstall
if not exist "%~dp0uninstall.ps1" goto :missing
rem A PowerShell 7 window passes on its module path, which Windows PowerShell cannot use.
set "PSModulePath="
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
if %errorlevel% neq 0 (echo. & pause)
exit /b %errorlevel%
:missing
echo The other files of this project are missing next to Uninstall.cmd. Extract the whole ZIP first,
echo or uninstall from Settings, Apps, Installed apps.
echo.
pause
exit /b 1
