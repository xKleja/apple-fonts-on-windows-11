<#
.SYNOPSIS
    Undo install.ps1: Windows goes back to Segoe UI / Segoe UI Variable / Segoe UI Emoji, and the
    Apple SF / New York fonts are removed. Uses the state recorded by the install, so it only
    reverses what the install actually changed.
.EXAMPLE
    .\uninstall.ps1
.EXAMPLE
    .\uninstall.ps1 -BackupDir D:\FontBackup     # if the install used -BackupDir
#>
[CmdletBinding()]
param(
    [string]$BackupDir,
    [switch]$NoRestartPrompt,
    [switch]$Elevated
)
$ErrorActionPreference = 'Stop'
$Interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected

function Pause-IfElevated {
    if ($Elevated -and $Interactive) { [void](Read-Host "`nPress Enter to close") }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    'Asking for administrator rights (click Yes on the UAC prompt)...'
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated')
    if ($BackupDir) { $argv += '-BackupDir', ('"{0}"' -f [IO.Path]::GetFullPath($BackupDir).TrimEnd('\')) }
    if ($NoRestartPrompt) { $argv += '-NoRestartPrompt' }
    try { $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $argv -Wait -PassThru }
    catch { throw 'Administrator rights were declined; nothing was changed.' }
    exit $p.ExitCode
}

$params = @{}
if ($BackupDir) { $params.BackupDir = $BackupDir }
try {
    & (Join-Path $PSScriptRoot 'scripts\restore-macos-fonts.ps1') @params
} catch {
    Write-Host "`nRESTORE FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'See the restore-*.log next to state.json. Running .\uninstall.ps1 again retries what failed.'
    Write-Host 'Last resort: System Restore point "Before macOS fonts".'
    Pause-IfElevated
    exit 1
}

if (-not $NoRestartPrompt -and $Interactive) {
    $answer = Read-Host "`nRestart Windows now to finish? (y/n)"
    if ($answer -match '^(y|yes)$') {
        shutdown.exe /r /t 30 /c "Restarting to restore the Windows fonts. Save your work. (shutdown /a cancels)"
        'Restarting in 30 seconds. Run "shutdown /a" to cancel.'
    } else { 'Restart later to finish.' }
}
Pause-IfElevated
