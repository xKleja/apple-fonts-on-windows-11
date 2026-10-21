<#
.SYNOPSIS
    One-step install: Apple fonts as the Windows 11 UI font, Apple Color Emoji, and all SF / New York fonts.

.DESCRIPTION
    Steps as shown in the window (1-3 as the signed-in user, 4-7 in the administrator window):
    1. Checks that this is Windows 11, that this folder is usable, and which fonts are already here.
    2. Downloads the font zips from this repo's GitHub Release over HTTPS (the release named in
       fonts\release.txt, which matches the checksums in this copy), verifies them, and unpacks the
       listed fonts into fonts\. Skipped when fonts\ already holds every font with the right checksum.
    3. Asks for administrator rights (UAC).
    4-7. scripts\install-macos-fonts.ps1: safety checks, safety nets, install, finish.
    Then a summary, and an offer to restart Windows (needed for the change to show everywhere).

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
# Started from a PowerShell 7 window, Windows PowerShell inherits its module path and then cannot load
# its own modules (Get-FileHash, Expand-Archive, Get-Acl ... "not recognized"): use its own folders.
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $env:PSModulePath = (@([Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') -split ';') +
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules') | Where-Object { $_ }) -join ';'
}
$Repo     = 'xKleja/apple-fonts-on-windows-11'
$FontsDir = Join-Path $PSScriptRoot 'fonts'
$Assets   = 'fonts-sf.zip', 'fonts-ui.zip', 'fonts-emoji.zip'
$Interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
$PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$Started  = Get-Date

function Pause-IfElevated {
    if ($Elevated -and $Interactive) { [void](Read-Host "`nPress Enter to close") }
}
function Stop-WithMessage([string]$Message, [string]$Color = 'Red') {
    Write-Progress -Activity 'Done' -Completed
    Write-Host "`n$Message" -ForegroundColor $Color
    Pause-IfElevated
    exit 1
}

# --- 1. this PC and this folder ------------------------------------------------------------------
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Stop-WithMessage 'CANNOT INSTALL: Windows is blocking scripts on this PC (Smart App Control, S mode or an App Control policy). Nothing was changed.'
}
try {
    $checks = Join-Path $PSScriptRoot 'scripts\checks.ps1'
    if (-not (Test-Path -LiteralPath $checks)) { throw 'Files are missing next to install.ps1. If you opened the ZIP without extracting it: right-click the ZIP, choose "Extract All", and run Install.cmd from the extracted folder.' }
    . $checks
    . (Join-Path $PSScriptRoot 'scripts\ui.ps1')
    $Version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -TotalCount 1).Trim()
    if (-not $Elevated) {
        Write-Header "Apple fonts on Windows 11  $Version" 'Makes Windows use Apple''s fonts for its interface and emoji. Nothing on Windows changes before step 5.'
        Write-Step 1 'Checking this PC and the fonts folder'
    }
    if (-not $DownloadOnly) { Assert-SupportedWindows }
    $locationNotes = @(Test-RepoLocation $PSScriptRoot)
} catch {
    Stop-WithMessage "CANNOT INSTALL: $($_.Exception.Message)"
}
if (-not $Tag) { $Tag = (Get-Content -LiteralPath (Join-Path $FontsDir 'release.txt') -TotalCount 1).Trim() }
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

# How many of the fonts listed in the checksum files are in $Root with the right checksum.
function Get-ReadyCount([string]$Root, [string]$Activity) {
    $ok = 0; $i = 0
    foreach ($e in $Expected) {
        if ($i++ % 8 -eq 0) { Show-Progress $Activity $i $Expected.Count }
        $fontFile = Join-Path $Root $e.Rel
        if ((Test-Path -LiteralPath $fontFile) -and (Get-FileHash -LiteralPath $fontFile -Algorithm SHA256).Hash -eq $e.Hash) { $ok++ }
    }
    Hide-Progress
    $ok
}

# One download with a progress bar (size, speed, time left). Background Intelligent Transfer when
# available (resumes after a dropped connection); otherwise a plain download, watched by file size.
function Get-OneDownload([string]$Url, [string]$OutFile, [string]$Label) {
    $barTitle = "Step 2 of 7: downloading $Label"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $bits = $null
    try { $bits = Start-BitsTransfer -Source $Url -Destination $OutFile -Asynchronous -DisplayName 'Apple fonts on Windows 11' -ErrorAction Stop } catch { $bits = $null }
    if ($bits) {
        $transient = $null
        try {
            while ($bits.JobState -in 'Queued', 'Connecting', 'Transferring', 'TransientError') {
                if ($bits.JobState -eq 'TransientError') {
                    if (-not $transient) { $transient = [Diagnostics.Stopwatch]::StartNew() }
                    if ($transient.Elapsed.TotalSeconds -gt 90) { throw "connection lost ($($bits.ErrorDescription.Trim()))" }
                } else { $transient = $null }
                $done = [double]$bits.BytesTransferred; $total = [double]$bits.BytesTotal
                if ($total -gt 0 -and $total -lt 1e15) {
                    $rate = $done / [Math]::Max(1, $sw.Elapsed.TotalSeconds)
                    $left = if ($rate -gt 0) { [int](($total - $done) / $rate) } else { 0 }
                    Write-Progress -Activity $barTitle -Status ('{0} of {1}   {2:N1} MB/s   about {3} s left' -f (Format-Size $done), (Format-Size $total), ($rate / 1MB), $left) -PercentComplete ([int](100 * $done / $total))
                } else { Write-Progress -Activity $barTitle -Status 'connecting...' }
                if ($sw.Elapsed.TotalMinutes -gt 60) { throw 'timed out after 60 minutes' }
                Start-Sleep -Milliseconds 300
            }
            if ($bits.JobState -ne 'Transferred') { throw "$($bits.JobState): $($bits.ErrorDescription)" }
            Complete-BitsTransfer -BitsJob $bits
        } catch {
            Remove-BitsTransfer -BitsJob $bits -ErrorAction SilentlyContinue
            throw
        } finally { Hide-Progress }
        return
    }
    # Plain download in a background job; the file size shows the progress.
    $job = Start-Job -ArgumentList $Url, $OutFile {
        param($u, $o)
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'   # the progress bar makes Invoke-WebRequest very slow on 5.1
        Invoke-WebRequest -Uri $u -OutFile $o -UseBasicParsing -TimeoutSec 1800
    }
    try {
        while (-not (Wait-Job $job -Timeout 1)) {
            $done = if (Test-Path -LiteralPath $OutFile) { [double](Get-Item -LiteralPath $OutFile).Length } else { 0 }
            Write-Progress -Activity $barTitle -Status ('{0} so far   {1:N1} MB/s' -f (Format-Size $done), ($done / 1MB / [Math]::Max(1, $sw.Elapsed.TotalSeconds)))
        }
        Receive-Job $job -ErrorAction Stop | Out-Null
    } finally { Remove-Job $job -Force; Hide-Progress }
}

# Up to 3 attempts, so a dropped connection does not need a manual re-run.
function Get-Download([string]$Url, [string]$OutFile, [string]$Label) {
    for ($i = 1; ; $i++) {
        try { Get-OneDownload $Url $OutFile $Label; return }
        catch {
            if ($i -ge 3) { throw "Download of $Label failed: $($_.Exception.Message)" }
            Write-Warn "attempt $i failed ($($_.Exception.Message)); trying again in $(5 * $i) s"
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

# --- 1-3. as the signed-in user ------------------------------------------------------------------
if (-not $Elevated) {
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        Write-Ok "Windows 11 $($cv.DisplayVersion) (build $($cv.CurrentBuild)); this folder is usable"
        foreach ($n in $locationNotes) { Write-Warn $n }
        $ready = Get-ReadyCount $FontsDir 'Step 1 of 7: checking the fonts already in this folder'
        $all = $Expected.Count
        if ($ready -eq $all) { Write-Ok "all $all fonts are already here and verified" }
        else { Write-Info "$ready of $all fonts are here; the rest are downloaded next" }

        Write-Step 2 "Downloading the fonts (about 0.7 GB, release $Tag)"
        if ($ready -eq $all) {
            Write-Ok 'not needed'
        } else {
            Assert-FreeSpace $PSScriptRoot 2 'the download and unpacked fonts'
            $dl = Join-Path $PSScriptRoot 'downloads'
            New-Item -ItemType Directory -Force $dl | Out-Null
            $base = if ($Tag -eq 'latest') { "https://github.com/$Repo/releases/latest/download" }
                    else { "https://github.com/$Repo/releases/download/$Tag" }
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Get-Download "$base/fonts-zips.sha256" (Join-Path $dl 'fonts-zips.sha256') 'the checksum list'
            $zipSums = @{}
            foreach ($line in Get-Content -LiteralPath (Join-Path $dl 'fonts-zips.sha256')) {
                if (-not $line.Trim()) { continue }
                $hash, $name = $line.Trim() -split '\s+', 2
                $zipSums[$name.TrimStart('*')] = $hash.ToUpperInvariant()
            }
            $n = 0
            foreach ($zip in $Assets) {
                $n++
                if (-not $zipSums.ContainsKey($zip)) { throw "Release $Tag has no checksum for $zip." }
                $file = Join-Path $dl $zip
                # A zip already downloaded and verified by an earlier, interrupted run is kept.
                if ((Test-Path -LiteralPath $file) -and (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -eq $zipSums[$zip]) {
                    Write-Ok "$zip ($(Format-Size (Get-Item -LiteralPath $file).Length)) - already downloaded earlier"; continue
                }
                Get-Download "$base/$zip" $file "$zip (file $n of $($Assets.Count))"
                if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $zipSums[$zip]) { throw "Download of $zip is corrupted (checksum mismatch)." }
                Write-Ok "$zip ($(Format-Size (Get-Item -LiteralPath $file).Length)) - checksum OK"
            }
            # Unpack into a scratch folder and copy out only the fonts listed in the checksum files,
            # so nothing in a zip can replace files of this project (the checksum files included).
            $unpacked = Join-Path $dl 'unpacked'
            if (Test-Path -LiteralPath $unpacked) { Remove-Item -LiteralPath $unpacked -Recurse -Force }
            $n = 0
            foreach ($zip in $Assets) {
                Show-Progress 'Step 2 of 7: unpacking' $n $Assets.Count 'zips'; $n++
                $ProgressPreference = 'SilentlyContinue'   # Expand-Archive's own per-file bar would replace ours
                Expand-Archive -LiteralPath (Join-Path $dl $zip) -DestinationPath $unpacked -Force
                $ProgressPreference = 'Continue'
            }
            Hide-Progress
            if ((Get-ReadyCount $unpacked 'Step 2 of 7: verifying the unpacked fonts') -ne $all) { throw "The fonts from release $Tag do not match the checksums in this copy (fonts\SHA256SUMS.txt). Download this project again from the latest release and retry." }
            $i = 0
            foreach ($e in $Expected) {
                if ($i++ % 8 -eq 0) { Show-Progress 'Step 2 of 7: putting the fonts in place' $i $all }
                $to = Join-Path $FontsDir $e.Rel
                New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
                Copy-Item -LiteralPath (Join-Path $unpacked $e.Rel) -Destination $to -Force
            }
            Hide-Progress
            if ((Get-ReadyCount $FontsDir 'Step 2 of 7: checking the fonts in place') -ne $all) { throw 'Copying the fonts into fonts\ failed. Check free space and run the install again.' }
            Remove-Item -LiteralPath $dl -Recurse -Force
            Write-Ok "$all fonts unpacked and verified"
        }
    } catch {
        Write-Progress -Activity 'Done' -Completed
        Write-Host "`nCOULD NOT GET THE FONTS: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Message -like 'Download of*') { Write-Host 'Check the internet connection (and any proxy or firewall), then run the install again. Zips that already arrived are kept.' }
        Write-Host 'Nothing on Windows was changed.'
        exit 1
    }

    if ($DownloadOnly) { Write-Host ''; Write-Host 'Fonts ready in fonts\. Nothing on Windows was changed (-DownloadOnly).' -ForegroundColor Green; exit 0 }

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

    Write-Step 3 'Administrator rights'
    if (-not (Test-Admin)) {
        Write-Info 'Click Yes on the Windows prompt. The install continues in a new window.'
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
    Write-Ok 'already running as administrator'
}

# --- 4-7. as administrator (scripts\install-macos-fonts.ps1) -------------------------------------
if ($Elevated) { Write-Header "Apple fonts on Windows 11  $Version  (administrator)" }
$params = @{ FontsDir = $FontsDir }
if ($BackupDir) { $params.BackupDir = $StateDir }
if ($UserSid) { $params.UserSid = $UserSid }
foreach ($k in 'SkipEmoji', 'SkipUI', 'NoRestorePoint') { if ($PSBoundParameters.ContainsKey($k)) { $params[$k] = [bool]$PSBoundParameters[$k] } }
if ($Resume) { $params.Resume = $true }
try {
    Assert-FreeSpace $env:WINDIR 1.2 'the installed fonts'
    & (Join-Path $PSScriptRoot 'scripts\install-macos-fonts.ps1') @params
} catch {
    Write-Progress -Activity 'Done' -Completed
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

$log = Get-ChildItem -LiteralPath $StateDir -Filter 'install-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
$line = '  ' + ('=' * 64)
Write-Host ''
Write-Host $line -ForegroundColor Green
Write-Host ("   Installed in {0} s. Restart Windows to see the new fonts everywhere." -f [int]((Get-Date) - $Started).TotalSeconds) -ForegroundColor Green
Write-Host '   Check it any time:  Status.cmd' -ForegroundColor Green
Write-Host '   Undo it:            Settings > Apps > Installed apps' -ForegroundColor Green
if ($log) { Write-Host "   Log:                $($log.FullName)" -ForegroundColor DarkGreen }
Write-Host $line -ForegroundColor Green

if (-not $NoRestartPrompt -and $Interactive) {
    $answer = Read-Host "`nRestart now? Save your work first. (y = restart in 30 s, n = later)"
    if ($answer -match '^(y|yes)$') {
        & "$env:SystemRoot\System32\shutdown.exe" /r /t 30 /c "Restarting to apply the Apple fonts. Save your work. (shutdown /a cancels)"
        Write-Host 'Restarting in 30 seconds. Run "shutdown /a" to cancel.'
    } else { Write-Host 'Restart later with Start > Power > Restart.' }
}
Pause-IfElevated
