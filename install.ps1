<#
.SYNOPSIS
    One-step install: Apple fonts as the Windows 11 UI font, Apple Color Emoji, and all SF / New York fonts.

.DESCRIPTION
    0. Checks that this is Windows 11 and that this folder is somewhere the install can work from.
    1. Downloads the font zips from this repo's GitHub Release over HTTPS (the release named in
       fonts\release.txt, which matches the checksums in this copy), verifies them, and unpacks them
       into fonts\. Skipped when fonts\ already holds every font with the right checksum.
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
    [string]$Tag,                 # release to download fonts from; default: fonts\release.txt
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

function Pause-IfElevated {
    if ($Elevated -and $Interactive) { [void](Read-Host "`nPress Enter to close") }
}

# --- 0. this PC and this folder ----------------------------------------------------------------
try {
    $checks = Join-Path $PSScriptRoot 'scripts\checks.ps1'
    if (-not (Test-Path -LiteralPath $checks)) { throw 'Files are missing next to install.ps1. If you opened the ZIP without extracting it: right-click the ZIP, choose "Extract All", and run Install.cmd from the extracted folder.' }
    . $checks
    if (-not $DownloadOnly) { Assert-SupportedWindows }
    foreach ($w in Test-RepoLocation $PSScriptRoot) { if (-not $Elevated) { Write-Host "Note: $w" -ForegroundColor Yellow } }
} catch {
    Write-Host "`nCANNOT INSTALL: $($_.Exception.Message)" -ForegroundColor Red
    Pause-IfElevated
    exit 1
}
if (-not $Tag) { $Tag = (Get-Content -LiteralPath (Join-Path $FontsDir 'release.txt') -TotalCount 1).Trim() }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Every font listed in the checksum files (tracked in git) is present and matches its checksum.
function Test-FontsReady {
    foreach ($sums in (Join-Path $FontsDir 'SHA256SUMS.txt'), (Join-Path $FontsDir 'ui\SHA256SUMS.txt')) {
        $dir = Split-Path $sums
        foreach ($line in Get-Content -LiteralPath $sums) {
            if (-not $line.Trim()) { continue }
            $hash, $rel = $line.Trim() -split '\s+', 2
            $fontFile = Join-Path $dir ($rel.TrimStart('*').TrimStart('.', '/') -replace '/', '\')
            if (-not (Test-Path -LiteralPath $fontFile)) { return $false }
            if ((Get-FileHash -LiteralPath $fontFile -Algorithm SHA256).Hash -ne $hash.ToUpperInvariant()) { return $false }
        }
    }
    $true
}

# Up to 3 attempts per file: a dropped connection should not need a manual re-run.
function Get-Download([string]$Url, [string]$OutFile) {
    for ($i = 1; ; $i++) {
        try { Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 1800; return }
        catch {
            if ($i -ge 3) { throw "Download of $(Split-Path $Url -Leaf) failed: $($_.Exception.Message)" }
            "  attempt $i failed ($($_.Exception.Message)); retrying in $(5 * $i) s"
            Start-Sleep -Seconds (5 * $i)
        }
    }
}

function Assert-FreeSpace([string]$Path, [double]$GB, [string]$Why) {
    $drive = (Get-Item -LiteralPath $Path).PSDrive
    if ($drive.Free -and $drive.Free -lt $GB * 1GB) {
        throw ("Not enough free space on {0}: ({1:N1} GB free, about {2} GB needed for {3})." -f $drive.Name, ($drive.Free / 1GB), $GB, $Why)
    }
}

# --- 1. fonts (as the normal user) ---------------------------------------------------------
if (-not $Elevated) {
    'Checking the fonts in fonts\...'
    try {
        if (Test-FontsReady) {
            'Fonts already present and verified'
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
                Get-Download "$base/$name" (Join-Path $dl $name)
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
            if (-not (Test-FontsReady)) { throw "The fonts from release $Tag do not match the checksums in this copy (fonts\SHA256SUMS.txt). Download this project again and retry." }
            Remove-Item $dl -Recurse -Force
        }
    } catch {
        Write-Host "`nDOWNLOAD FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Nothing on Windows was changed. Check the internet connection and run the install again.'
        exit 1
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
        catch { Write-Host "`nAdministrator rights were declined; nothing was installed." -ForegroundColor Yellow; exit 1 }
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
    Write-Host 'If the install stopped part-way, everything done so far is recorded: run .\install.ps1 -Resume to finish it, or .\uninstall.ps1 to undo it.'
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
