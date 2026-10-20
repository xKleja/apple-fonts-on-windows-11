<#
.SYNOPSIS
    One-step install: Apple fonts as the Windows 11 UI font, Apple Color Emoji, and all SF / New York fonts.

.DESCRIPTION
    1. Downloads the font zips from this repo's GitHub Release over HTTPS (skipped if fonts\ is
       already filled), verifies them, and unpacks them into fonts\.
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
    [string]$Tag = 'latest',      # release to download fonts from, e.g. v1.0.0
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
$Assets   = 'fonts-sf.zip', 'fonts-ui.zip', 'fonts-emoji.zip'
$Interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Pause-IfElevated {
    if ($Elevated -and $Interactive) { [void](Read-Host "`nPress Enter to close") }
}

# Every font listed in the checksum files (tracked in git) is present. Hashes are checked by the installer.
function Test-FontsPresent {
    foreach ($sums in (Join-Path $FontsDir 'SHA256SUMS.txt'), (Join-Path $FontsDir 'ui\SHA256SUMS.txt')) {
        $dir = Split-Path $sums
        foreach ($line in Get-Content -LiteralPath $sums) {
            if (-not $line.Trim()) { continue }
            $rel = (($line.Trim() -split '\s+', 2)[1]).TrimStart('*').TrimStart('.', '/') -replace '/', '\'
            if (-not (Test-Path -LiteralPath (Join-Path $dir $rel))) { return $false }
        }
    }
    $true
}

function Assert-FreeSpace([string]$Path, [double]$GB, [string]$Why) {
    $drive = (Get-Item -LiteralPath $Path).PSDrive
    if ($drive.Free -and $drive.Free -lt $GB * 1GB) {
        throw ("Not enough free space on {0}: ({1:N1} GB free, about {2} GB needed for {3})." -f $drive.Name, ($drive.Free / 1GB), $GB, $Why)
    }
}

# --- 1. fonts (as the normal user) ---------------------------------------------------------
if (-not $Elevated) {
    if (Test-FontsPresent) {
        'Fonts already present in fonts\'
    } else {
        Assert-FreeSpace $PSScriptRoot 2 'the download and unpacked fonts'
        $dl = Join-Path $PSScriptRoot 'downloads'
        New-Item -ItemType Directory -Force $dl | Out-Null
        $base = if ($Tag -eq 'latest') { "https://github.com/$Repo/releases/latest/download" }
                else { "https://github.com/$Repo/releases/download/$Tag" }
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'   # the progress bar makes Invoke-WebRequest very slow on 5.1
        foreach ($name in @($Assets) + 'fonts-zips.sha256') {
            "Downloading $name ($Tag)..."
            try { Invoke-WebRequest -Uri "$base/$name" -OutFile (Join-Path $dl $name) -UseBasicParsing -TimeoutSec 1800 }
            catch { throw "Download of $name failed: $($_.Exception.Message)" }
        }

        foreach ($line in Get-Content (Join-Path $dl 'fonts-zips.sha256')) {
            if (-not $line.Trim()) { continue }
            $hash, $name = $line.Trim() -split '\s+', 2
            $name = $name.TrimStart('*')
            if ((Get-FileHash (Join-Path $dl $name) -Algorithm SHA256).Hash -ne $hash.ToUpperInvariant()) { throw "Download corrupted: $name" }
        }
        'Zips verified'
        foreach ($zip in $Assets) {
            "Unpacking $zip"
            Expand-Archive (Join-Path $dl $zip) -DestinationPath $FontsDir -Force
        }
        if (-not (Test-FontsPresent)) { throw 'Unpacked fonts are incomplete (the release does not match fonts\SHA256SUMS.txt in this checkout; try -Tag with the matching release).' }
        Remove-Item $dl -Recurse -Force
    }

    if ($DownloadOnly) { 'Fonts ready in fonts\. Nothing on Windows was changed (-DownloadOnly).'; exit 0 }

    # --- 2. elevate for the install itself ---------------------------------------------
    if (-not (Test-Admin)) {
        'Asking for administrator rights (click Yes on the UAC prompt)...'
        $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated')
        foreach ($k in $PSBoundParameters.Keys) {
            $v = $PSBoundParameters[$k]
            if ($v -is [switch]) { if ($v) { $argv += "-$k" } continue }
            if ($k -eq 'BackupDir') { $v = [IO.Path]::GetFullPath($v) }   # the elevated window starts elsewhere
            $argv += "-$k", ('"{0}"' -f ([string]$v).TrimEnd('\'))
        }
        try { $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $argv -Wait -PassThru }
        catch { throw 'Administrator rights were declined; nothing was installed.' }
        exit $p.ExitCode
    }
}

# --- 3. install (elevated) ----------------------------------------------------------------
$params = @{ FontsDir = $FontsDir }
if ($BackupDir) { $params.BackupDir = $BackupDir }
foreach ($k in 'SkipEmoji', 'SkipUI', 'NoRestorePoint', 'Resume') { if ($PSBoundParameters.ContainsKey($k)) { $params[$k] = [bool]$PSBoundParameters[$k] } }
try {
    Assert-FreeSpace $env:WINDIR 1.2 'the installed fonts'
    & (Join-Path $PSScriptRoot 'scripts\install-macos-fonts.ps1') @params
} catch {
    Write-Host "`nINSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Everything done so far is recorded: run .\install.ps1 -Resume to finish, or .\uninstall.ps1 to undo.'
    Pause-IfElevated
    exit 1
}

if (-not $NoRestartPrompt -and $Interactive) {
    $answer = Read-Host "`nRestart Windows now so every app picks up the new fonts? (y/n)"
    if ($answer -match '^(y|yes)$') {
        shutdown.exe /r /t 30 /c "Restarting to apply the Apple fonts. Save your work. (shutdown /a cancels)"
        'Restarting in 30 seconds. Run "shutdown /a" to cancel.'
    } else { 'Restart later to finish.' }
}
Pause-IfElevated
