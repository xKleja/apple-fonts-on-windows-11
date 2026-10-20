# What the install and uninstall windows show: numbered steps, ticks, progress bars and timers.
# Dot-sourced by install.ps1, uninstall.ps1, install-macos-fonts.ps1 and restore-macos-fonts.ps1.
# Everything here is display only. Write-Host text also lands in the transcript logs.

if (-not (Get-Variable UiTotal -Scope Script -ErrorAction SilentlyContinue)) { $script:UiTotal = 7 }
# A real tick in Windows Terminal; the classic console's font lacks it. Windows Terminal is the default
# terminal from Windows 11 22H2 unless "Windows Console Host" was chosen (WT_SESSION is not set when
# Windows hands a double-clicked script to it).
$script:UiTick = '+'
try {
    $delegation = (Get-ItemProperty 'HKCU:\Console\%%Startup' -ErrorAction SilentlyContinue).DelegationConsole
    $conhost = '{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}'
    $toFile = [Console]::IsOutputRedirected   # text going to a file or pipe: keep it plain
    if (-not $toFile -and ($env:WT_SESSION -or ([Environment]::OSVersion.Version.Build -ge 22621 -and $delegation -ne $conhost))) { $script:UiTick = [string][char]0x2713 }
} catch { }

function Write-Header([string]$Title, [string]$Subtitle) {
    Write-Host ''
    Write-Host $Title -ForegroundColor White
    if ($Subtitle) { Write-Host $Subtitle -ForegroundColor Gray }
}
function Write-Step([int]$Number, [string]$Text) {
    Write-Host ''
    Write-Host "[$Number/$script:UiTotal] $Text" -ForegroundColor Cyan
}
function Write-Ok([string]$Text)     { Write-Host "      $script:UiTick $Text" -ForegroundColor Green }
function Write-Info([string]$Text)   { Write-Host "      $Text" -ForegroundColor Gray }
function Write-Detail([string]$Text) { Write-Host "      $Text" -ForegroundColor DarkGray }
function Write-Warn([string]$Text)   { Write-Host "      ! $Text" -ForegroundColor Yellow }

# A counted progress bar ("12 of 169 files").
function Show-Progress([string]$Activity, [int]$Done, [int]$Total, [string]$Unit = 'files', [int]$Id = 0) {
    $pct = if ($Total -gt 0) { [Math]::Min(100, [int](100 * $Done / $Total)) } else { 0 }
    Write-Progress -Id $Id -Activity $Activity -Status "$Done of $Total $Unit" -PercentComplete $pct
}
function Hide-Progress([int]$Id = 0) { Write-Progress -Id $Id -Activity 'Done' -Completed }

# Wait for a background job, showing how long it has been running (for steps Windows gives no
# progress for: the restore point, stopping the font cache). $true when it finished in time.
function Wait-WithTimer($Job, [string]$Activity, [string]$Status, [int]$TimeoutSec) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        Write-Progress -Activity $Activity -Status ('{0} ({1} s)' -f $Status, [int]$sw.Elapsed.TotalSeconds)
        if (Wait-Job $Job -Timeout 1) { Hide-Progress; return $true }
    }
    Hide-Progress
    $false
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { '{0:N1} GB' -f ($Bytes / 1GB) } else { '{0:N0} MB' -f ($Bytes / 1MB) }
}
