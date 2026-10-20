@echo off
rem Double-click to check that the Apple fonts are still in place (read-only, changes nothing).
title Apple fonts on Windows 11 - status
if not exist "%~dp0status.ps1" goto :missing
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0status.ps1" %*
set "code=%errorlevel%"
echo.
pause
exit /b %code%
:missing
echo The other files of this project are missing next to Status.cmd. Extract the whole ZIP first.
echo.
pause
exit /b 1
