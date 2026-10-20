# Undoes install-macos-fonts.ps1 exactly, using the state it recorded. Run elevated (normally via
# uninstall.ps1, or the Installed apps entry), then restart.
#
# Every recorded item is undone independently: one failure does not stop the rest. state.json is
# only retired when everything succeeded, so a re-run can finish the job.
# The window shows three steps (scripts\ui.ps1): check the record, restore, finish.
#Requires -RunAsAdministrator
param([string]$BackupDir)   # default %ProgramData%\AppleFontsOnWindows
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'backup-location.ps1')
$UiTotal = 3
. (Join-Path $PSScriptRoot 'ui.ps1')
$BackupDir = if ($BackupDir) { Resolve-UserPath $BackupDir } else { Get-DefaultBackupDir }
$Fonts     = "$env:WINDIR\Fonts"
$RegLM     = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$StatePath = Join-Path $BackupDir 'state.json'   # not "$State": PowerShell names are case-insensitive ($state = data)
if (-not (Test-Path -LiteralPath $StatePath)) { throw "Nothing to uninstall: no install is recorded in $BackupDir." }

$LogPath = Join-Path $BackupDir "restore-$(Get-Date -Format yyyyMMdd-HHmmss).log"
Start-Transcript -LiteralPath $LogPath -ErrorAction SilentlyContinue | Out-Null
try {

Write-Step 1 'Checking what the install changed'
try { $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json }
catch { throw "state.json is unreadable ($($_.Exception.Message)). Restore with the HKLM-Fonts-*.reg export in $BackupDir." }
Assert-SafeState $state
$when = if ($state.Installed -is [datetime]) { $state.Installed.ToString('yyyy-MM-dd HH:mm') } else { "$($state.Installed)".Replace('T', ' ') }
Write-Ok "install record from $when checked ($(if ($state.Complete) { 'complete' } else { 'unfinished' }))"
if (-not (Test-AdminOnlyTree $BackupDir)) {
    Write-Warn "$BackupDir can be changed by non-administrators. Only the install's own fonts and registry entries are restored (state.json is checked), but keep install backups in an administrators-only folder."
}

$leftover = @()
$failed   = @()

function Remove-FontFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop }
    catch { $script:leftover += $Path }   # still loaded; harmless once unregistered, removed below at restart
}

# Run one undo step; record a failure and carry on with the rest.
function Step([string]$What, [scriptblock]$Do) {
    try { & $Do } catch { $script:failed += "${What}: $($_.Exception.Message)" }
}

function Get-Items($list) { @($list | Where-Object { $_ }) }

Write-Step 2 "Putting Windows' own fonts back"
$ui = @(Get-Items $state.UI); $hkcu = @(Get-Items $state.HKCU); $sf = @(Get-Items $state.SFFonts)
$total = $ui.Count + $hkcu.Count + $(if ($state.EmojiReg) { 1 } else { 0 }) + $sf.Count
$done = 0
$activity = "Step 2 of 3: restoring Windows' fonts"

# UI registrations back to the original Segoe files
foreach ($u in $ui) {
    Show-Progress $activity (++$done) $total 'changes'
    Step "UI $($u.Registry)" {
        Set-ItemProperty -Path $RegLM -Name $u.Registry -Value $u.Original
        Remove-FontFile (Join-Path $Fonts $u.New)
    }
}
if ($ui) { Write-Ok "Segoe UI and Segoe UI Variable use Windows' own files again ($($ui.Count) fonts)" }
# Per-user registrations go back into the hive of the user they were taken from
if ($hkcu) {
    $regUser = Get-UserFontKey $state.UserSid
    if (-not $regUser) {
        $failed += "per-user fonts: user $($state.UserSid) is signed out. Sign in as that user, then uninstall again."
    } else {
        if (-not (Test-Path -LiteralPath $regUser)) { New-Item -Path $regUser -Force | Out-Null }
        foreach ($c in $hkcu) {
            Show-Progress $activity (++$done) $total 'changes'
            Step "per-user $($c.Registry)" { New-ItemProperty -LiteralPath $regUser -Name $c.Registry -Value $c.Value -PropertyType String -Force | Out-Null }
        }
        Write-Ok "$($hkcu.Count) per-user copy of Segoe UI registered again"
    }
}

# Emoji registration back to seguiemj.ttf
if ($state.EmojiReg) {
    Show-Progress $activity (++$done) $total 'changes'
    Step 'emoji' {
        Set-ItemProperty -Path $RegLM -Name $state.EmojiReg.Registry -Value $state.EmojiReg.Original
        Remove-FontFile (Join-Path $Fonts $state.EmojiReg.New)
    }
    Write-Ok 'Segoe UI Emoji uses Windows'' own emoji again'
}

# SF / New York families
foreach ($s in $sf) {
    if (++$done % 4 -eq 0) { Show-Progress $activity $done $total 'changes' }
    Step "SF $($s.File)" {
        $props = Get-ItemProperty -Path $RegLM
        if ($props.PSObject.Properties.Name -contains $s.Registry) { Remove-ItemProperty -Path $RegLM -Name $s.Registry }
        if (-not $s.KeepFile) { Remove-FontFile (Join-Path $Fonts $s.File) }   # KeepFile: the file was there before the install
    }
}
Hide-Progress
if ($sf) { Write-Ok "$($sf.Count) SF / New York fonts removed" }

# Files still in use: delete them at the next restart
if ($leftover) {
    Step 'delete at restart' {
        Add-Type -Namespace W -Name K -MemberDefinition '[DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool MoveFileEx(string a, string b, int f);'
        foreach ($p in $leftover) {
            # [NullString]::Value: a real null target (plain $null would become "" and fail)
            if (-not [W.K]::MoveFileEx($p, [NullString]::Value, 4)) {   # MOVEFILE_DELAY_UNTIL_REBOOT
                throw "could not schedule $p (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
            }
        }
    }
    Write-Info "$($leftover.Count) font files are in use; Windows deletes them at the next restart"
}

Write-Step 3 'Finishing'
$svc = Start-Job { Stop-Service FontCache -Force -ErrorAction SilentlyContinue }
if (-not (Wait-WithTimer $svc 'Step 3 of 3: clearing the font cache' 'stopping the Windows font cache service' 60)) { Write-Info 'the font cache service is slow to stop; Windows rebuilds the cache at restart anyway' }
Remove-Job $svc -Force
Remove-Item "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache\*FontCache*" -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:WINDIR\System32\FNTCACHE.DAT" -Force -ErrorAction SilentlyContinue
Write-Ok 'font cache cleared'

if ($failed) {
    Write-Host ''
    Write-Host 'Some changes could not be undone yet (uninstalling again retries only these):' -ForegroundColor Yellow
    $failed | ForEach-Object { Write-Warn $_ }
    throw "$($failed.Count) change(s) could not be undone."
}
if ($state.UninstallEntry -or (Test-Path $UninstallKey)) {
    if (Test-Path $UninstallKey) { Remove-Item $UninstallKey -Recurse -Force }
    Write-Ok 'removed from Settings > Apps > Installed apps'
}
Rename-Item -LiteralPath $StatePath "state.restored-$(Get-Date -Format yyyyMMdd-HHmmss).json"
Write-Detail "log: $LogPath"

} catch {
    Hide-Progress
    Write-Detail "error: $($_.Exception.Message)"
    Write-Detail $_.ScriptStackTrace
    throw
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
