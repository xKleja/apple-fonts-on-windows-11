<#
.SYNOPSIS
    One-step install: Apple fonts as the Windows 11 UI font, Apple Color Emoji, and all SF / New York fonts.

.DESCRIPTION
    1. Downloads the font zips from this repo's GitHub Release (skipped if fonts\ is already filled),
       verifies them, and unpacks them into fonts\.
    2. Asks for administrator rights (UAC) and runs scripts\install-macos-fonts.ps1, which re-verifies
       every font against the checksums tracked in git, backs up what it changes, and records its state.
    3. Offers to restart Windows (needed for the change to show everywhere).

    Undo with .\uninstall.ps1. Check the current state with .\status.ps1.

.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -SkipEmoji          # UI + SF fonts only
.EXAMPLE
    .\install.ps1 -Resume             # finish an install that was interrupted
.EXAMPLE
    .\install.ps1 -DownloadOnly       # just fetch + verify the fonts into fonts\
#>
[CmdletBinding()]
param(
    [string]$Tag = 'latest',      # release to download fonts from
    [string]$BackupDir,           # default %ProgramData%\AppleFontsOnWindows
    [switch]$SkipEmoji,
    [switch]$SkipUI,
    [switch]$NoRestorePoint,
    [switch]$Resume,
    [switch]$NoRestartPrompt,
    [switch]$DownloadOnly,        # fetch + verify + unpack the fonts, change nothing on Windows
    [switch]$Elevated             # internal: set on the elevated re-launch
)
$ErrorActionPreference = 'Stop'
$Repo     = 'xKleja/apple-fonts-on-windows-11'
$FontsDir = Join-Path $PSScriptRoot 'fonts'
$Assets   = [ordered]@{ 'fonts-sf.zip' = 'SF'; 'fonts-ui.zip' = 'ui'; 'fonts-emoji.zip' = 'emoji' }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-FontsPresent {
    (Get-ChildItem (Join-Path $FontsDir 'SF') -Recurse -File -Include *.ttf, *.otf -ErrorAction SilentlyContinue).Count -ge 155 -and
    (Get-ChildItem (Join-Path $FontsDir 'ui') -File -Filter *.ttf -ErrorAction SilentlyContinue).Count -ge 13 -and
    (Test-Path (Join-Path $FontsDir 'emoji\AppleColorEmoji-Windows.ttf'))
}

# --- 1. fonts (as the normal user, so gh uses your own GitHub sign-in) ------------------
if (-not $Elevated) {
    if (Test-FontsPresent) {
        'Fonts already present in fonts\'
    } else {
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            throw 'GitHub CLI (gh) is needed to download the fonts: winget install GitHub.cli, then gh auth login'
        }
        gh auth status *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Sign in to GitHub first: gh auth login' }
        $dl = Join-Path $PSScriptRoot 'downloads'
        New-Item -ItemType Directory -Force $dl | Out-Null
        "Downloading font zips from $Repo ($Tag)..."
        $tagArg = if ($Tag -eq 'latest') { @() } else { @($Tag) }
        gh release download @tagArg -R $Repo -D $dl --clobber -p 'fonts-*.zip' -p 'fonts-zips.sha256'
        if ($LASTEXITCODE -ne 0) { throw 'Download failed (see the gh message above).' }

        foreach ($line in Get-Content (Join-Path $dl 'fonts-zips.sha256')) {
            $hash, $name = $line -split '\s+', 2
            $name = $name.TrimStart('*')
            if ((Get-FileHash (Join-Path $dl $name) -Algorithm SHA256).Hash -ne $hash.ToUpper()) { throw "Download corrupted: $name" }
        }
        'Zips verified'
        foreach ($zip in $Assets.Keys) {
            "Unpacking $zip"
            Expand-Archive (Join-Path $dl $zip) -DestinationPath $FontsDir -Force
        }
        if (-not (Test-FontsPresent)) { throw 'Unpacked fonts are incomplete.' }
        Remove-Item $dl -Recurse -Force
    }

    if ($DownloadOnly) { 'Fonts ready in fonts\. Nothing on Windows was changed (-DownloadOnly).'; exit 0 }

    # --- 2. elevate for the install itself ---------------------------------------------
    if (-not (Test-Admin)) {
        'Asking for administrator rights (click Yes on the UAC prompt)...'
        $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated')
        foreach ($k in $PSBoundParameters.Keys) {
            $v = $PSBoundParameters[$k]
            if ($v -is [switch]) { if ($v) { $argv += "-$k" } } else { $argv += "-$k", "`"$v`"" }
        }
        $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $argv -Wait -PassThru
        exit $p.ExitCode
    }
}

# --- 3. install (elevated) ----------------------------------------------------------------
$params = @{ FontsDir = $FontsDir }
foreach ($k in 'BackupDir') { if ($PSBoundParameters[$k]) { $params[$k] = $PSBoundParameters[$k] } }
foreach ($k in 'SkipEmoji', 'SkipUI', 'NoRestorePoint', 'Resume') { if ($PSBoundParameters[$k]) { $params[$k] = $true } }
try {
    & (Join-Path $PSScriptRoot 'scripts\install-macos-fonts.ps1') @params
} catch {
    Write-Host "`nINSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Nothing is left half-done that cannot be undone: run .\install.ps1 -Resume to finish, or .\uninstall.ps1 to undo.'
    if ($Elevated) { Read-Host 'Press Enter to close' }
    exit 1
}

if (-not $NoRestartPrompt) {
    $answer = Read-Host "`nRestart Windows now so every app picks up the new fonts? (y/n)"
    if ($answer -match '^(y|yes)$') { Restart-Computer -Force }
    else { 'Restart later to finish.' }
}
