<#
.SYNOPSIS
    One-step install: Apple fonts as the Windows 11 UI font, Apple Color Emoji, and all SF / New York fonts.

.DESCRIPTION
    0. Checks that this is Windows 11 and that this folder is somewhere the install can work from.
    1. Downloads the font zips from this repo's GitHub Release over HTTPS (the release named in
       fonts\release.txt, which matches the checksums in this copy), verifies them, and unpacks the
       listed fonts into fonts\. Skipped when fonts\ already holds every font with the right checksum.
    2. Asks for administrator rights (UAC) and runs scripts\install-macos-fonts.ps1, which re-verifies
       every font against the checksums tracked in git, backs up what it changes, and records its state.
    3. Offers to restart Windows (needed for the change to show everywhere).

    Undo with Uninstall.cmd or Settings > Apps > Installed apps. Check the current state with Status.cmd.

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
    [switch]$Elevated,            # internal: set on the elevated re-launch
    [string]$UserSid              # internal: the signed-in user, passed to the elevated re-launch
)
$ErrorActionPreference = 'Stop'
$Repo     = 'xKleja/apple-fonts-on-windows-11'
$FontsDir = Join-Path $PSScriptRoot 'fonts'
$Assets   = 'fonts-sf.zip', 'fonts-ui.zip', 'fonts-emoji.zip'
$Interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
$PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

function Pause-IfElevated {
    if ($Elevated -and $Interactive) { [void](Read-Host "`nPress Enter to close") }
}
function Stop-WithMessage([string]$Message, [string]$Color = 'Red') {
    Write-Host "`n$Message" -ForegroundColor $Color
    Pause-IfElevated
    exit 1
}

# --- 0. this PC and this folder ----------------------------------------------------------------
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Stop-WithMessage 'CANNOT INSTALL: Windows is blocking scripts on this PC (Smart App Control, S mode or an App Control policy). Nothing was changed.'
}
try {
    $checks = Join-Path $PSScriptRoot 'scripts\checks.ps1'
    if (-not (Test-Path -LiteralPath $checks)) { throw 'Files are missing next to install.ps1. If you opened the ZIP without extracting it: right-click the ZIP, choose "Extract All", and run Install.cmd from the extracted folder.' }
    . $checks
    if (-not $DownloadOnly) { Assert-SupportedWindows }
    foreach ($w in Test-RepoLocation $PSScriptRoot) { if (-not $Elevated) { Write-Host "Note: $w" -ForegroundColor Yellow } }
} catch {
    Stop-WithMessage "CANNOT INSTALL: $($_.Exception.Message)"
}
if (-not $Tag) { $Tag = (Get-Content -LiteralPath (Join-Path $FontsDir 'release.txt') -TotalCount 1).Trim() }
$Version  = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -TotalCount 1).Trim()
$StateDir = if ($BackupDir) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BackupDir) }
            else { Join-Path $env:ProgramData 'AppleFontsOnWindows' }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# The checksums tracked in git, read once before anything is downloaded (the zips cannot change them).
$Expected = @()
foreach ($sums in (Join-Path $FontsDir 'SHA256SUMS.txt'), (Join-Path $FontsDir 'ui\SHA256SUMS.txt')) {
    $sub = if ((Split-Path (Split-Path $sums) -Leaf) -eq 'ui') { 'ui\' } else { '' }
    foreach ($line in Get-Content -LiteralPath $sums) {
        if (-not $line.Trim()) { continue }
        $hash, $rel = $line.Trim() -split '\s+', 2
        $Expected += [pscustomobject]@{ Rel = $sub + ($rel.TrimStart('*').TrimStart('.', '/') -replace '/', '\'); Hash = $hash.ToUpperInvariant() }
    }
}

# Every font listed in the checksum files is present in $Root and matches its checksum.
function Test-FontsReady([string]$Root = $FontsDir) {
    foreach ($e in $Expected) {
        $fontFile = Join-Path $Root $e.Rel
        if (-not (Test-Path -LiteralPath $fontFile)) { return $false }
        if ((Get-FileHash -LiteralPath $fontFile -Algorithm SHA256).Hash -ne $e.Hash) { return $false }
    }
    $true
}

# Background Intelligent Transfer (shows progress, resumes) with a plain download as fallback;
# up to 3 attempts, so a dropped connection does not need a manual re-run.
function Get-Download([string]$Url, [string]$OutFile) {
    for ($i = 1; ; $i++) {
        try {
            try { Start-BitsTransfer -Source $Url -Destination $OutFile -DisplayName 'Apple fonts on Windows 11' -ErrorAction Stop }
            catch {
                $ProgressPreference = 'SilentlyContinue'   # the progress bar makes Invoke-WebRequest very slow on 5.1
                Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 1800
            }
            return
        } catch {
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
    "Apple fonts on Windows 11 $Version"
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
            "Downloading the fonts from release $Tag (about 0.7 GB; this can take a few minutes)..."
            Get-Download "$base/fonts-zips.sha256" (Join-Path $dl 'fonts-zips.sha256')
            $zipSums = @{}
            foreach ($line in Get-Content -LiteralPath (Join-Path $dl 'fonts-zips.sha256')) {
                if (-not $line.Trim()) { continue }
                $hash, $name = $line.Trim() -split '\s+', 2
                $zipSums[$name.TrimStart('*')] = $hash.ToUpperInvariant()
            }
            foreach ($zip in $Assets) {
                if (-not $zipSums.ContainsKey($zip)) { throw "Release $Tag has no checksum for $zip." }
                $file = Join-Path $dl $zip
                # A zip already downloaded and verified by an earlier, interrupted run is kept.
                if ((Test-Path -LiteralPath $file) -and (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -eq $zipSums[$zip]) { "  $zip already downloaded"; continue }
                "  $zip"
                Get-Download "$base/$zip" $file
                if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $zipSums[$zip]) { throw "Download of $zip is corrupted (checksum mismatch)." }
            }
            'Zips verified'
            # Unpack into a scratch folder and copy out only the fonts listed in the checksum files,
            # so nothing in a zip can replace files of this project (the checksum files included).
            $unpacked = Join-Path $dl 'unpacked'
            if (Test-Path -LiteralPath $unpacked) { Remove-Item -LiteralPath $unpacked -Recurse -Force }
            foreach ($zip in $Assets) {
                "Unpacking $zip"
                Expand-Archive -LiteralPath (Join-Path $dl $zip) -DestinationPath $unpacked -Force
            }
            if (-not (Test-FontsReady $unpacked)) { throw "The fonts from release $Tag do not match the checksums in this copy (fonts\SHA256SUMS.txt). Download this project again from the latest release and retry." }
            foreach ($e in $Expected) {
                $to = Join-Path $FontsDir $e.Rel
                New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
                Copy-Item -LiteralPath (Join-Path $unpacked $e.Rel) -Destination $to -Force
            }
            if (-not (Test-FontsReady)) { throw 'Copying the fonts into fonts\ failed. Check free space and run the install again.' }
            Remove-Item -LiteralPath $dl -Recurse -Force
        }
    } catch {
        Write-Host "`nCOULD NOT GET THE FONTS: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Message -like 'Download of*') { Write-Host 'Check the internet connection (and any proxy or firewall), then run the install again.' }
        Write-Host 'Nothing on Windows was changed.'
        exit 1
    }

    if ($DownloadOnly) { 'Fonts ready in fonts\. Nothing on Windows was changed (-DownloadOnly).'; exit 0 }

    # Already installed, or a previous run that did not finish? (state.json is readable by everyone.)
    $statePath = Join-Path $StateDir 'state.json'
    $old = try { if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } } catch { $null }
    if ($old -and -not $Resume) {
        if ($old.Complete) {
            Stop-WithMessage "Already installed. Double-click Status.cmd to check it. To install again: uninstall (Settings > Apps > Installed apps), restart, then install." 'Yellow'
        }
        if ($Interactive -and (Read-Host "`nA previous install did not finish. Finish it now? (y/n)") -match '^(y|yes)$') { $Resume = [switch]$true }
        else { Stop-WithMessage 'A previous install did not finish. Run Install.cmd again and answer y to finish it, or uninstall to undo it.' 'Yellow' }
    }

    # --- 2. elevate for the install itself ---------------------------------------------
    if (-not (Test-Admin)) {
        'Asking for administrator rights (click Yes on the UAC prompt)...'
        $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated',
                  '-UserSid', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value, '-Tag', $Tag)
        foreach ($k in 'SkipEmoji', 'SkipUI', 'NoRestorePoint', 'NoRestartPrompt') { if ($PSBoundParameters[$k]) { $argv += "-$k" } }
        if ($Resume) { $argv += '-Resume' }
        if ($BackupDir) {
            $dir = $StateDir; if ($dir.EndsWith('\')) { $dir += '\' }   # "C:\" must not end in \" on the command line
            $argv += '-BackupDir', "`"$dir`""
        }
        try { $p = Start-Process $PowerShellExe -Verb RunAs -ArgumentList $argv -Wait -PassThru }
        catch { Write-Host "`nAdministrator rights were declined; nothing was installed." -ForegroundColor Yellow; exit 1 }
        exit $p.ExitCode   # the elevated window showed the result and paused
    }
}

# --- 3. install (elevated) ----------------------------------------------------------------
$params = @{ FontsDir = $FontsDir }
if ($BackupDir) { $params.BackupDir = $StateDir }
if ($UserSid) { $params.UserSid = $UserSid }
foreach ($k in 'SkipEmoji', 'SkipUI', 'NoRestorePoint') { if ($PSBoundParameters.ContainsKey($k)) { $params[$k] = [bool]$PSBoundParameters[$k] } }
if ($Resume) { $params.Resume = $true }
try {
    Assert-FreeSpace $env:WINDIR 1.2 'the installed fonts'
    & (Join-Path $PSScriptRoot 'scripts\install-macos-fonts.ps1') @params
} catch {
    Write-Host "`nINSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
    $state = try { Get-Content -LiteralPath (Join-Path $StateDir 'state.json') -Raw | ConvertFrom-Json } catch { $null }
    if ($state -and -not $state.Complete) {
        Write-Host 'Everything done so far is recorded: run Install.cmd again to finish it, or uninstall to undo it.'
    }
    $log = Get-ChildItem -LiteralPath $StateDir -Filter 'install-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($log) { Write-Host "Log (attach it to a bug report): $($log.FullName)" }
    Pause-IfElevated
    exit 1
}

if (-not $NoRestartPrompt -and $Interactive) {
    $answer = Read-Host "`nRestart Windows now so every app picks up the new fonts? (y/n)"
    if ($answer -match '^(y|yes)$') {
        shutdown.exe /r /t 30 /c "Restarting to apply the Apple fonts. Save your work. (shutdown /a cancels)"
        'Restarting in 30 seconds. Run "shutdown /a" to cancel.'
    } else { 'Restart later to finish (Start > Power > Restart).' }
}
Pause-IfElevated
