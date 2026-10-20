@echo off
rem Double-click to install: Apple fonts for the Windows 11 interface and emoji, plus the SF / New York fonts.
rem Same as running install.ps1 in PowerShell. Extra options are passed on, e.g.  Install.cmd -SkipEmoji
title Apple fonts on Windows 11 - install
if not exist "%~dp0install.ps1" goto :missing
rem A PowerShell 7 window passes on its module path, which Windows PowerShell cannot use.
set "PSModulePath="
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
if %errorlevel% neq 0 (echo. & pause)
exit /b %errorlevel%
:missing
echo The other files of this project are missing next to Install.cmd.
echo If you opened the ZIP without extracting it: right-click the ZIP, choose "Extract All",
echo then double-click Install.cmd in the extracted folder.
echo.
pause
exit /b 1
