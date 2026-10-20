# Windows Sandbox: functional test of the install / restore scripts, no restarts needed.
# Started by start-rehearsal.ps1 -Mode Scripts. Checks registry, files and state.json after every step:
#   fresh install -> guards (already installed / nothing to resume) -> restore ->
#   simulated crash mid-install -> -Resume -> restore
# Writes C:\results\script-test.log and ends with "SCRIPT TEST PASSED" or "SCRIPT TEST FAILED".
$ErrorActionPreference = 'Stop'
$Src    = 'C:\src'
$Out    = 'C:\results'
$Backup = 'C:\FontBackup'
$Fonts  = "$env:WINDIR\Fonts"
$RegLM  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$Log    = "$Out\script-test.log"
New-Item -ItemType Directory -Force $Out | Out-Null
$script:fails = 0

function Log($m) { "$(Get-Date -Format HH:mm:ss) $m" | Tee-Object -FilePath $Log -Append | Out-Null }
function Check([bool]$ok, [string]$what) { if ($ok) { Log "  PASS $what" } else { $script:fails++; Log "  FAIL $what" } }
function Reg { Get-ItemProperty $RegLM }
function State { Get-Content "$Backup\state.json" -Raw | ConvertFrom-Json }
function Run([string]$script, [hashtable]$params) {
    try { & "$Src\scripts\$script" @params *>&1 | ForEach-Object { Log "    | $_" }; $true }
    catch { Log "    | THROWN: $($_.Exception.Message)"; $false }
}

$seg = [ordered]@{ 'Segoe UI (TrueType)' = 'segoeui.ttf'; 'Segoe UI Bold (TrueType)' = 'segoeuib.ttf'
                   'Segoe UI Variable (TrueType)' = 'SegUIVar.ttf'; 'Segoe UI Emoji (TrueType)' = 'seguiemj.ttf' }
$before = Reg
$installArgs = @{ FontsDir = "$Src\fonts"; BackupDir = $Backup; NoRestorePoint = $true }

function Assert-Installed([string]$label) {
    Log "== verify: $label"
    $r = Reg; $s = State
    foreach ($k in $seg.Keys) { Check ($r.$k -eq "SFUI-$($seg[$k])") "$k -> SFUI-$($seg[$k])" }
    Check (Test-Path "$Fonts\SFUI-segoeui.ttf") 'SFUI-segoeui.ttf exists'
    Check ($r.'SF Pro Regular (TrueType)' -eq 'SF-Pro.ttf') 'SF Pro registered'
    Check ($s.Complete -eq $true) 'state.Complete'
    Check (@($s.UI).Count -eq 13) "state.UI has 13 entries ($(@($s.UI).Count))"
    Check ([bool]$s.EmojiReg) 'state.EmojiReg recorded'
    $users = @((Get-Acl $Backup).Access | Where-Object { $_.IdentityReference -match 'Users$' })
    Check ($users.Count -eq 0) "backup folder has no Users access ($(($users.IdentityReference) -join ', '))"
    foreach ($u in $s.UI) { Check ($u.Original -notlike 'SFUI-*') "UI original recorded for $($u.Registry)" }
}

function Assert-Restored([string]$label) {
    Log "== verify: $label"
    $r = Reg
    foreach ($k in $seg.Keys) { Check ($r.$k -eq $before.$k) "$k back to $($before.$k)" }
    Check (($r.'SF Pro Regular (TrueType)') -eq ($before.'SF Pro Regular (TrueType)')) 'SF Pro registration back to how it was'
    Check (-not (Test-Path "$Backup\state.json")) 'state.json retired'
    Check ($null -ne (Get-ChildItem "$Backup\state.restored-*.json" -ErrorAction SilentlyContinue)) 'state.restored-*.json kept'
}

try {
    Log '=== 1. fresh install'
    Check (Run 'install-macos-fonts.ps1' $installArgs) 'install succeeded'
    Assert-Installed 'after fresh install'

    Log '=== 2. guards'
    Check (-not (Run 'install-macos-fonts.ps1' $installArgs)) 'second install refused (already installed)'
    Check (-not (Run 'install-macos-fonts.ps1' ($installArgs + @{ Resume = $true }))) '-Resume on a complete install refused'

    Log '=== 3. restore'
    Check (Run 'restore-macos-fonts.ps1' @{ BackupDir = $Backup }) 'restore succeeded'
    Assert-Restored 'after restore'
    Get-ChildItem "$Backup\state.restored-*.json" | Remove-Item -Force

    # Crash right after the Nth UI entry is recorded: state says it is ours, registry not yet changed.
    # 1 = a one-item list in state.json (Windows PowerShell 5.1 does not keep it a list by itself).
    foreach ($n in 1, 5) {
        Log "=== 4. simulated crash after UI entry $n, then -Resume"
        $env:APPLEFONTS_TEST_CRASH_AFTER_UI = "$n"
        Check (-not (Run 'install-macos-fonts.ps1' $installArgs)) 'install interrupted by the simulated crash'
        Remove-Item Env:\APPLEFONTS_TEST_CRASH_AFTER_UI
        $s = State
        Check ($s.Complete -eq $false) 'state marks the install incomplete'
        Check (@($s.UI).Count -eq $n) "$n UI entries recorded before the crash ($(@($s.UI).Count))"
        Check (Run 'install-macos-fonts.ps1' ($installArgs + @{ Resume = $true })) '-Resume finished the install'
        Assert-Installed "after resume (crash at $n)"

        Log "=== 5. restore after the resumed install (crash at $n)"
        Check (Run 'restore-macos-fonts.ps1' @{ BackupDir = $Backup }) 'restore succeeded'
        Assert-Restored "after restore (crash at $n)"
        Get-ChildItem "$Backup\state.restored-*.json" | Remove-Item -Force
    }
} catch {
    $script:fails++
    Log "UNEXPECTED: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)"
}
Log $(if ($script:fails) { "SCRIPT TEST FAILED ($script:fails failed checks)" } else { 'SCRIPT TEST PASSED' })
