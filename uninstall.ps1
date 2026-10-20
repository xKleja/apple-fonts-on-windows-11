<#
.SYNOPSIS
    Undo install.ps1: Windows goes back to Segoe UI / Segoe UI Variable / Segoe UI Emoji, and the
    Apple SF / New York fonts are removed. Uses the state recorded by the install, so it only
    reverses what the install actually changed.
.EXAMPLE
    .\uninstall.ps1
#>
[CmdletBinding()]
param(
    [string]$BackupDir,
    [switch]$NoRestartPrompt,
    [switch]$Elevated
)
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    'Asking for administrator rights (click Yes on the UAC prompt)...'
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated')
    if ($BackupDir) { $argv += '-BackupDir', "`"$BackupDir`"" }
    if ($NoRestartPrompt) { $argv += '-NoRestartPrompt' }
    $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $argv -Wait -PassThru
    exit $p.ExitCode
}

$params = @{}
if ($BackupDir) { $params.BackupDir = $BackupDir }
try {
    & (Join-Path $PSScriptRoot 'scripts\restore-macos-fonts.ps1') @params
} catch {
    Write-Host "`nRESTORE FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'See the restore-*.log next to state.json. Last resort: System Restore point "Before macOS fonts".'
    if ($Elevated) { Read-Host 'Press Enter to close' }
    exit 1
}

if (-not $NoRestartPrompt) {
    $answer = Read-Host "`nRestart Windows now to finish? (y/n)"
    if ($answer -match '^(y|yes)$') { Restart-Computer -Force }
    else { 'Restart later to finish.' }
}
