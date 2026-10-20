<#
.SYNOPSIS
    Undo install.ps1: Windows goes back to Segoe UI / Segoe UI Variable / Segoe UI Emoji, and the
    Apple SF / New York fonts are removed. Uses the state recorded by the install, so it only
    reverses what the install actually changed. Also started by Settings > Apps > Installed apps.
.EXAMPLE
    .\uninstall.ps1
.EXAMPLE
    .\uninstall.ps1 -BackupDir D:\FontBackup     # if the install used -BackupDir
#>
[CmdletBinding()]
param(
    [string]$BackupDir,
    [switch]$NoRestartPrompt,
    [switch]$PauseAtEnd,          # keep the window open at the end (the Installed apps entry sets it)
    [switch]$Elevated             # internal: set on the elevated re-launch
)
$ErrorActionPreference = 'Stop'
$Interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected

# Pause before the window closes when nobody would otherwise see the result.
function Pause-ForUser { if (($Elevated -or $PauseAtEnd) -and $Interactive) { [void](Read-Host "`nPress Enter to close") } }
function Stop-WithMessage([string]$Message, [string]$Color = 'Red') {
    Write-Host "`n$Message" -ForegroundColor $Color
    Pause-ForUser
    exit 1
}

if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Stop-WithMessage 'Windows is blocking scripts on this PC (Smart App Control, S mode or an App Control policy), so this cannot run. Nothing was changed.'
}
$BackupDir = if ($BackupDir) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BackupDir) }
             else { Join-Path $env:ProgramData 'AppleFontsOnWindows' }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
# Installs made before 1.2 keep state.json readable by administrators only: when the folder exists
# but its state cannot be seen yet, elevate and let the restore decide.
$stateVisible = try { Test-Path -LiteralPath (Join-Path $BackupDir 'state.json') } catch { $false }
if (-not $stateVisible -and ($isAdmin -or -not (Test-Path -LiteralPath $BackupDir))) {
    Stop-WithMessage "Nothing to uninstall: no install is recorded in $BackupDir. (If the install used -BackupDir, pass the same -BackupDir.)" 'Yellow'
}

if (-not $isAdmin) {
    'Asking for administrator rights (click Yes on the UAC prompt)...'
    $dir = $BackupDir; if ($dir.EndsWith('\')) { $dir += '\' }   # "C:\" must not end in \" on the command line
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated', '-BackupDir', "`"$dir`"")
    if ($NoRestartPrompt) { $argv += '-NoRestartPrompt' }
    try { $p = Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $argv -Wait -PassThru }
    catch { Write-Host "`nAdministrator rights were declined; nothing was changed." -ForegroundColor Yellow; exit 1 }
    exit $p.ExitCode   # the elevated window showed the result and paused
}

try {
    & (Join-Path $PSScriptRoot 'scripts\restore-macos-fonts.ps1') -BackupDir $BackupDir
} catch {
    Write-Host "`nUNINSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Run the uninstall again: it retries only what failed. Details are in the newest restore-*.log in:'
    Write-Host "  $BackupDir"
    Write-Host 'Last resort: System Restore, restore point "Before macOS fonts".'
    Pause-ForUser
    exit 1
}

if (-not $NoRestartPrompt -and $Interactive) {
    $answer = Read-Host "`nRestart Windows now to finish? (y/n)"
    if ($answer -match '^(y|yes)$') {
        shutdown.exe /r /t 30 /c "Restarting to restore the Windows fonts. Save your work. (shutdown /a cancels)"
        'Restarting in 30 seconds. Run "shutdown /a" to cancel.'
    } else { 'Restart later to finish (Start > Power > Restart; "Shut down" is not enough).' }
}
Pause-ForUser
