@echo off
rem Double-click to undo the install (Windows goes back to its own fonts). Same as running uninstall.ps1.
title Apple fonts on Windows 11 - uninstall
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
if errorlevel 1 (echo. & pause)
