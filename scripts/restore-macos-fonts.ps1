# Undoes install-macos-fonts.ps1 exactly, using the state it recorded. Run elevated (normally via
# the repo's uninstall.ps1), then restart.
#
# Every recorded item is undone independently: one failure does not stop the rest. state.json is
# only retired when everything succeeded, so a re-run can finish the job.
#Requires -RunAsAdministrator
param([string]$BackupDir)   # default %ProgramData%\AppleFontsOnWindows
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'backup-location.ps1')
if (-not $BackupDir) { $BackupDir = Get-DefaultBackupDir }
$BackupDir = [IO.Path]::GetFullPath($BackupDir)
$Fonts     = "$env:WINDIR\Fonts"
$RegLM     = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$RegCU     = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$StatePath = Join-Path $BackupDir 'state.json'   # not "$State": PowerShell names are case-insensitive ($state = data)
if (-not (Test-Path -LiteralPath $StatePath)) { throw "No install state at $StatePath; nothing to restore. (Pass -BackupDir if the install used a different folder.)" }
try { $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json }
catch { throw "state.json is unreadable ($($_.Exception.Message)). Restore with the HKLM-Fonts-*.reg export in $BackupDir." }
Assert-SafeState $state

Start-Transcript -Path (Join-Path $BackupDir "restore-$(Get-Date -Format yyyyMMdd-HHmmss).log") -ErrorAction SilentlyContinue | Out-Null
try {

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

# UI registrations back to the original Segoe files
foreach ($u in Get-Items $state.UI) {
    Step "UI $($u.Registry)" {
        Set-ItemProperty -Path $RegLM -Name $u.Registry -Value $u.Original
        Remove-FontFile (Join-Path $Fonts $u.New)
    }
}
$hkcu = @(Get-Items $state.HKCU)
if ($hkcu) {
    if (-not (Test-Path $RegCU)) { New-Item $RegCU -Force | Out-Null }
    foreach ($c in $hkcu) {
        Step "per-user $($c.Registry)" { New-ItemProperty -Path $RegCU -Name $c.Registry -Value $c.Value -PropertyType String -Force | Out-Null }
    }
}
"UI: $(@(Get-Items $state.UI).Count) Segoe registrations restored, $($hkcu.Count) per-user entries re-registered"

# Emoji registration back to seguiemj.ttf
if ($state.EmojiReg) {
    Step 'emoji' {
        Set-ItemProperty -Path $RegLM -Name $state.EmojiReg.Registry -Value $state.EmojiReg.Original
        Remove-FontFile (Join-Path $Fonts $state.EmojiReg.New)
    }
    'Emoji: "Segoe UI Emoji" points at the original seguiemj.ttf again'
}

# SF / New York families
foreach ($s in Get-Items $state.SFFonts) {
    Step "SF $($s.File)" {
        Remove-ItemProperty -Path $RegLM -Name $s.Registry -ErrorAction SilentlyContinue
        if (-not $s.KeepFile) { Remove-FontFile (Join-Path $Fonts $s.File) }   # KeepFile: the file was there before the install
    }
}
"Removed $(@(Get-Items $state.SFFonts).Count) SF / New York fonts"

# Files still in use: delete them at next restart
if ($leftover) {
    Add-Type -Namespace W -Name K -MemberDefinition '[DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool MoveFileEx(string a, string b, int f);'
    # [NullString]::Value: a real null target (plain $null would become "" and fail)
    foreach ($p in $leftover) { [void][W.K]::MoveFileEx($p, [NullString]::Value, 4) }   # MOVEFILE_DELAY_UNTIL_REBOOT
    "$($leftover.Count) font files in use will be deleted at restart (install again only after restarting)"
}

'Font cache: stopping the service'
$svc = Start-Job { Stop-Service FontCache -Force -ErrorAction SilentlyContinue }
if (-not (Wait-Job $svc -Timeout 60)) { 'Font cache service did not stop in 60 s; the cache will rebuild at restart anyway' }
Remove-Job $svc -Force
Remove-Item "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache\*FontCache*" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:WINDIR\System32\FNTCACHE.DAT" -Force -ErrorAction SilentlyContinue

if ($failed) {
    "`nSome steps failed (state.json kept, so running uninstall again retries them):"
    $failed | ForEach-Object { "  $_" }
    throw "$($failed.Count) restore step(s) failed."
}
Rename-Item -LiteralPath $StatePath "state.restored-$(Get-Date -Format yyyyMMdd-HHmmss).json"
'DONE. Restart Windows now.'

} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
