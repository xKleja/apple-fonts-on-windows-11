@echo off
rem Double-click to install: Apple fonts for the Windows 11 interface and emoji, plus the SF / New York fonts.
rem Same as running install.ps1 in PowerShell. Extra options are passed on, e.g.  Install.cmd -SkipEmoji
title Apple fonts on Windows 11 - install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
if errorlevel 1 (echo. & pause)
