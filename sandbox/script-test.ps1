# Windows Sandbox: functional test of the install / uninstall scripts, no restarts needed.
# Started by start-rehearsal.ps1 -Mode Scripts. Runs the project the way a user would, from a copy in an
# awkward folder (spaces, #, %, parentheses, Arabic letters) with default settings, and checks registry,
# files, state.json and the Installed apps entry after every step:
#   location guard -> Install.cmd -> status -> guards (already installed / nothing to resume) ->
#   uninstall -> simulated crash mid-install + -Resume + uninstall (crash after UI entry 1 and 5) ->
#   install, delete the project folder, uninstall through the Installed apps entry alone
# Writes C:\results\script-test.log and ends with "SCRIPT TEST PASSED" or "SCRIPT TEST FAILED".
$ErrorActionPreference = 'Stop'
$Src    = 'C:\src'
$Out    = 'C:\results'
$Backup = Join-Path $env:ProgramData 'AppleFontsOnWindows'   # the default; tests use no -BackupDir
$Fonts  = "$env:WINDIR\Fonts"
$RegLM  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$AppKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\AppleFontsOnWindows'
$Log    = "$Out\script-test.log"
New-Item -ItemType Directory -Force $Out | Out-Null
$script:fails = 0

# The project copy lives here (Arabic written as char codes: this file stays ASCII)
$arabic = -join ([char[]](0x062A, 0x062C, 0x0631, 0x0628, 0x0629))
$Parent = Join-Path ([Environment]::GetFolderPath('Desktop')) "My fonts #1 ($arabic) 50%"
$App    = Join-Path $Parent 'apple-fonts-on-windows-11-main'

function Log($m) { "$(Get-Date -Format HH:mm:ss) $m" | Tee-Object -FilePath $Log -Append | Out-Null }
function Check([bool]$ok, [string]$what) { if ($ok) { Log "  PASS $what" } else { $script:fails++; Log "  FAIL $what" } }
function Reg { Get-ItemProperty $RegLM }
function State { Get-Content "$Backup\state.json" -Raw | ConvertFrom-Json }

# Run a script; success = no exception and exit code 0. Output goes to the log.
function Run([string]$path, [hashtable]$params = @{}) {
    $global:LASTEXITCODE = 0
    try { & $path @params *>&1 | ForEach-Object { Log "    | $_" }; $LASTEXITCODE -eq 0 }
    catch { Log "    | THROWN: $($_.Exception.Message)"; $false }
}

# Run a command line through cmd.exe exactly as typed (as Explorer or Settings would), stdin empty.
function Run-Cmd([string]$line) {
    $nul = "$env:TEMP\empty.txt"; Set-Content $nul '' -NoNewline
    $p = Start-Process cmd.exe -ArgumentList "/d /c `"$line`"" -Wait -PassThru -NoNewWindow `
        -RedirectStandardInput $nul -RedirectStandardOutput "$env:TEMP\cmd-out.txt" -RedirectStandardError "$env:TEMP\cmd-err.txt"
    Get-Content "$env:TEMP\cmd-out.txt", "$env:TEMP\cmd-err.txt" | ForEach-Object { Log "    | $_" }
    $p.ExitCode -eq 0
}

$seg = [ordered]@{ 'Segoe UI (TrueType)' = 'segoeui.ttf'; 'Segoe UI Bold (TrueType)' = 'segoeuib.ttf'
                   'Segoe UI Variable (TrueType)' = 'SegUIVar.ttf'; 'Segoe UI Emoji (TrueType)' = 'seguiemj.ttf' }
$before = Reg
$installArgs = @{ NoRestorePoint = $true; NoRestartPrompt = $true }

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
    $k = Get-ItemProperty $AppKey -ErrorAction SilentlyContinue
    Check ([bool]$k) 'Installed apps entry exists'
    if ($k) {
        Check ($k.DisplayName -eq 'Apple fonts on Windows 11 (community project)') "Installed apps name: $($k.DisplayName)"
        Check (Test-Path -LiteralPath "$Backup\uninstaller\uninstall.ps1") 'uninstaller copied to the backup folder'
        Check ($k.UninstallString -like "*$Backup\uninstaller\uninstall.ps1*") "UninstallString: $($k.UninstallString)"
    }
}

function Assert-Restored([string]$label) {
    Log "== verify: $label"
    $r = Reg
    foreach ($k in $seg.Keys) { Check ($r.$k -eq $before.$k) "$k back to $($before.$k)" }
    Check (($r.'SF Pro Regular (TrueType)') -eq ($before.'SF Pro Regular (TrueType)')) 'SF Pro registration back to how it was'
    Check (-not (Test-Path "$Backup\state.json")) 'state.json retired'
    Check ($null -ne (Get-ChildItem "$Backup\state.restored-*.json" -ErrorAction SilentlyContinue)) 'state.restored-*.json kept'
    Check (-not (Test-Path $AppKey)) 'Installed apps entry removed'
    Get-ChildItem "$Backup\state.restored-*.json" -ErrorAction SilentlyContinue | Remove-Item -Force
}

try {
    Log "=== 0. copy the project to: $App"
    New-Item -ItemType Directory -Force $App | Out-Null
    robocopy $Src $App /E /XD .git sandbox-results /NFL /NDL /NJH /NJS /NP | Out-Null
    Check ($LASTEXITCODE -lt 8) "copied (robocopy exit $LASTEXITCODE)"

    Log '=== 1. location guard: run from a network path'
    $unc = '\\localhost\' + $App.Substring(0, 1) + '$' + $App.Substring(2)
    if (Test-Path -LiteralPath "$unc\install.ps1") {
        $global:LASTEXITCODE = 0
        $o = & "$unc\install.ps1" -DownloadOnly *>&1 | Out-String
        Log "    | $($o.Trim())"
        Check ($LASTEXITCODE -eq 1 -and $o -match 'network drive') 'refused with a network-drive message'
    } else { Log '  SKIP admin share not available' }

    Log '=== 2. fresh install with Install.cmd (default settings)'
    Check (Run-Cmd "`"$App\Install.cmd`" -NoRestorePoint -NoRestartPrompt") 'Install.cmd succeeded'
    Assert-Installed 'after Install.cmd'
    Check (Run "$App\status.ps1") 'status.ps1 reports everything in place (exit 0)'

    Log '=== 3. guards'
    Check (-not (Run "$App\install.ps1" $installArgs)) 'second install refused (already installed)'
    Check (-not (Run "$App\install.ps1" ($installArgs + @{ Resume = $true }))) '-Resume on a complete install refused'

    Log '=== 4. uninstall'
    Check (Run "$App\uninstall.ps1" @{ NoRestartPrompt = $true }) 'uninstall succeeded'
    Assert-Restored 'after uninstall'
    Check (-not (Run "$App\status.ps1")) 'status.ps1 reports not installed (exit 1)'

    # Crash right after the Nth UI entry is recorded: state says it is ours, registry not yet changed.
    # 1 = a one-item list in state.json (Windows PowerShell 5.1 does not keep it a list by itself).
    foreach ($n in 1, 5) {
        Log "=== 5. simulated crash after UI entry $n, then -Resume"
        $env:APPLEFONTS_TEST_CRASH_AFTER_UI = "$n"
        Check (-not (Run "$App\install.ps1" $installArgs)) 'install interrupted by the simulated crash'
        Remove-Item Env:\APPLEFONTS_TEST_CRASH_AFTER_UI
        $s = State
        Check ($s.Complete -eq $false) 'state marks the install incomplete'
        Check (@($s.UI).Count -eq $n) "$n UI entries recorded before the crash ($(@($s.UI).Count))"
        Check (Run "$App\install.ps1" ($installArgs + @{ Resume = $true })) '-Resume finished the install'
        Assert-Installed "after resume (crash at $n)"
        Check (Run "$App\uninstall.ps1" @{ NoRestartPrompt = $true }) 'uninstall succeeded'
        Assert-Restored "after uninstall (crash at $n)"
    }

    Log '=== 6. install, delete the project folder, uninstall from the Installed apps entry'
    Check (Run "$App\install.ps1" $installArgs) 'install succeeded'
    Assert-Installed 'before deleting the project folder'
    Remove-Item -LiteralPath $Parent -Recurse -Force
    Check (-not (Test-Path -LiteralPath $Parent)) 'project folder deleted'
    $us = (Get-ItemProperty $AppKey).UninstallString
    Check (Run-Cmd "$us -NoRestartPrompt") 'Installed apps uninstall succeeded'
    Assert-Restored 'after uninstall from Installed apps'
} catch {
    $script:fails++
    Log "UNEXPECTED: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)"
}
Log $(if ($script:fails) { "SCRIPT TEST FAILED ($script:fails failed checks)" } else { 'SCRIPT TEST PASSED' })
