@echo off
rem Double-click to check that the Apple fonts are still in place (read-only, changes nothing).
title Apple fonts on Windows 11 - status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0status.ps1" %*
echo.
pause
