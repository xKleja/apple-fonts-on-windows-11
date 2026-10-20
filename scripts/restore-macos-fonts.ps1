# Undoes install-macos-fonts.ps1 exactly, using the state it recorded. Run elevated (normally via
# uninstall.ps1, or the Installed apps entry), then restart.
#
# Every recorded item is undone independently: one failure does not stop the rest. state.json is
# only retired when everything succeeded, so a re-run can finish the job.
#Requires -RunAsAdministrator
param([string]$BackupDir)   # default %ProgramData%\AppleFontsOnWindows
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'backup-location.ps1')
$BackupDir = if ($BackupDir) { Resolve-UserPath $BackupDir } else { Get-DefaultBackupDir }
$Fonts     = "$env:WINDIR\Fonts"
$RegLM     = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$StatePath = Join-Path $BackupDir 'state.json'   # not "$State": PowerShell names are case-insensitive ($state = data)
if (-not (Test-Path -LiteralPath $StatePath)) { throw "Nothing to uninstall: no install is recorded in $BackupDir." }

$LogPath = Join-Path $BackupDir "restore-$(Get-Date -Format yyyyMMdd-HHmmss).log"
Start-Transcript -LiteralPath $LogPath -ErrorAction SilentlyContinue | Out-Null
try {

try { $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json }
catch { throw "state.json is unreadable ($($_.Exception.Message)). Restore with the HKLM-Fonts-*.reg export in $BackupDir." }
Assert-SafeState $state
if (-not (Test-AdminOnlyTree $BackupDir)) {
    "Note: $BackupDir can be changed by non-administrators. Only the install's own fonts and registry entries are restored (state.json is checked), but keep install backups in an administrators-only folder."
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

# UI registrations back to the original Segoe files
foreach ($u in Get-Items $state.UI) {
    Step "UI $($u.Registry)" {
        Set-ItemProperty -Path $RegLM -Name $u.Registry -Value $u.Original
        Remove-FontFile (Join-Path $Fonts $u.New)
    }
}
# Per-user registrations go back into the hive of the user they were taken from
$hkcu = @(Get-Items $state.HKCU)
if ($hkcu) {
    $regUser = Get-UserFontKey $state.UserSid
    if (-not $regUser) {
        $failed += "per-user fonts: user $($state.UserSid) is signed out. Sign in as that user, then uninstall again."
    } else {
        if (-not (Test-Path -LiteralPath $regUser)) { New-Item -Path $regUser -Force | Out-Null }
        foreach ($c in $hkcu) {
            Step "per-user $($c.Registry)" { New-ItemProperty -LiteralPath $regUser -Name $c.Registry -Value $c.Value -PropertyType String -Force | Out-Null }
        }
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
        $props = Get-ItemProperty -Path $RegLM
        if ($props.PSObject.Properties.Name -contains $s.Registry) { Remove-ItemProperty -Path $RegLM -Name $s.Registry }
        if (-not $s.KeepFile) { Remove-FontFile (Join-Path $Fonts $s.File) }   # KeepFile: the file was there before the install
    }
}
"Removed $(@(Get-Items $state.SFFonts).Count) SF / New York fonts"

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
    "$($leftover.Count) font files in use will be deleted at the next restart"
}

'Font cache: stopping the service'
$svc = Start-Job { Stop-Service FontCache -Force -ErrorAction SilentlyContinue }
if (-not (Wait-Job $svc -Timeout 60)) { 'Font cache service did not stop in 60 s; the cache will rebuild at restart anyway' }
Remove-Job $svc -Force
Remove-Item "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache\*FontCache*" -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:WINDIR\System32\FNTCACHE.DAT" -Force -ErrorAction SilentlyContinue

if ($failed) {
    "`nSome steps failed (state.json kept, so uninstalling again retries them):"
    $failed | ForEach-Object { "  $_" }
    throw "$($failed.Count) restore step(s) failed."
}
if ($state.UninstallEntry -or (Test-Path $UninstallKey)) {
    if (Test-Path $UninstallKey) { Remove-Item $UninstallKey -Recurse -Force }
    'Removed from Settings > Apps > Installed apps'
}
Rename-Item -LiteralPath $StatePath "state.restored-$(Get-Date -Format yyyyMMdd-HHmmss).json"
"DONE. Log: $LogPath"

} catch {
    "ERROR: $($_.Exception.Message)"
    $_.ScriptStackTrace
    throw
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
