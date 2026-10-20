# Windows Sandbox: functional test of the install / uninstall scripts, no restarts needed.
# Started by start-rehearsal.ps1 -Mode Scripts. Runs the project the way a user would, from a copy in an
# awkward folder (spaces, #, %, [], parentheses, Arabic letters) with default settings, and checks
# registry, files, state.json and the Installed apps entry after every step:
#   location guard -> a standard user pre-creates the backup folder -> Install.cmd -> what a standard
#   user can do (Status.cmd, read the uninstaller, not write the backups) -> guards (already installed /
#   nothing to resume) -> uninstall -> simulated crash mid-install + -Resume + uninstall (crash after UI
#   entry 1 and 5) -> install with a per-user Segoe override, delete the project folder, uninstall through
#   the Installed apps entry alone (override put back)
# Standard-user steps run through "runas /trustlevel:0x20000" (the same account, without admin rights).
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
$Parent = Join-Path ([Environment]::GetFolderPath('Desktop')) "My fonts #1 [x] ($arabic) 50%"
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

# Run PowerShell code as a standard user (this account with a non-admin token). Returns the exit code
# ($LASTEXITCODE after the code, 99 if it threw) and logs the output.
function Run-AsStandardUser([string]$Command) {
    $dir = 'C:\Users\Public\aftest'; [void][IO.Directory]::CreateDirectory($dir)
    $outFile = "$dir\out.txt"; $doneFile = "$dir\done.txt"
    Remove-Item -LiteralPath $outFile, $doneFile -ErrorAction SilentlyContinue
    $wrapped = "`$global:LASTEXITCODE = 0; try { & { $Command } *>&1 | Out-File -LiteralPath '$outFile' -Encoding utf8; `$c = `$LASTEXITCODE } " +
               "catch { `$_ | Out-File -LiteralPath '$outFile' -Append -Encoding utf8; `$c = 99 }; Set-Content -LiteralPath '$doneFile' `$c"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapped))
    runas.exe /trustlevel:0x20000 "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc" | Out-Null
    for ($t = 0; $t -lt 120 -and -not (Test-Path -LiteralPath $doneFile); $t++) { Start-Sleep 1 }
    if (-not (Test-Path -LiteralPath $doneFile)) { Log '    | (no result from the standard-user process)'; return -1 }
    Get-Content -LiteralPath $outFile -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Log "    | $_" }
    $script:lastStdOut = (Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
    [int](Get-Content -LiteralPath $doneFile -TotalCount 1)
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
    $users = @((Get-Acl -LiteralPath $Backup).Access | Where-Object { $_.IdentityReference -match 'Users$' -and $_.FileSystemRights -match 'Write|Modify|FullControl|Delete|ChangePermissions|TakeOwnership' })
    Check ($users.Count -eq 0) "backup folder: Users may read but not change it ($(($users.FileSystemRights) -join ', '))"
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

    Log '=== 3. fresh install with Install.cmd (default settings)'
    Check (Run-Cmd "`"$App\Install.cmd`" -NoRestorePoint -NoRestartPrompt") 'Install.cmd succeeded'
    Assert-Installed 'after Install.cmd'
    . "$App\scripts\backup-location.ps1"
    Check (Test-AdminOnlyTree $Backup) 'backup folder and everything in it: administrators-only'
    Check (Run "$App\status.ps1") 'status.ps1 (as administrator) reports everything in place (exit 0)'

    Log '=== 4. what a standard user can do'
    $code = Run-AsStandardUser "& '$App\status.ps1'"
    Check ($code -eq 0 -and $script:lastStdOut -match 'Everything is in place') "Status.cmd's script as a standard user: everything in place (exit $code)"
    $code = Run-AsStandardUser "Get-Content -LiteralPath '$Backup\uninstaller\uninstall.ps1' -TotalCount 1 | Out-Null; 'readable'"
    Check ($code -eq 0 -and $script:lastStdOut -match 'readable') 'the Installed apps uninstaller is readable by a standard user'
    $code = Run-AsStandardUser "try { [IO.File]::WriteAllText('$Backup\uninstaller\uninstall.ps1', 'x'); 'WROTE' } catch { 'denied' }"
    Check ($script:lastStdOut -match 'denied') 'a standard user cannot change the uninstaller'
    $code = Run-AsStandardUser "try { [IO.File]::WriteAllText('$Backup\state.json', '{}'); 'WROTE' } catch { 'denied' }"
    Check ($script:lastStdOut -match 'denied') 'a standard user cannot change state.json'

    Log '=== 5. guards'
    Check (-not (Run "$App\install.ps1" $installArgs)) 'second install refused (already installed)'
    Check (-not (Run "$App\install.ps1" ($installArgs + @{ Resume = $true }))) '-Resume on a complete install refused'

    Log '=== 6. uninstall'
    Check (Run "$App\uninstall.ps1" @{ NoRestartPrompt = $true }) 'uninstall succeeded'
    Assert-Restored 'after uninstall'
    $global:LASTEXITCODE = 0; & "$App\status.ps1" *> $null
    Check ($LASTEXITCODE -eq 2) "status.ps1 reports not installed (exit $LASTEXITCODE, expected 2)"
    Check (-not (Run "$App\uninstall.ps1" @{ NoRestartPrompt = $true })) 'a second uninstall says there is nothing to uninstall'

    # Crash right after the Nth UI entry is recorded: state says it is ours, registry not yet changed.
    # 1 = a one-item list in state.json (Windows PowerShell 5.1 does not keep it a list by itself).
    foreach ($n in 1, 5) {
        Log "=== 7. simulated crash after UI entry $n, then -Resume"
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

    Log '=== 8. per-user override; install, delete the project folder, uninstall from the Installed apps entry'
    $regCU = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    $fakeUserFont = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\SegoeUI-VF.ttf"
    if (-not (Test-Path $regCU)) { New-Item $regCU -Force | Out-Null }
    New-ItemProperty -Path $regCU -Name 'Segoe UI Variable (TrueType)' -Value $fakeUserFont -PropertyType String -Force | Out-Null
    Check (Run "$App\install.ps1" $installArgs) 'install succeeded'
    Assert-Installed 'before deleting the project folder'
    Check ($null -eq (Get-ItemProperty $regCU).'Segoe UI Variable (TrueType)') 'per-user Segoe UI Variable override unregistered'
    Check (@((State).HKCU).Count -eq 1 -and (State).UserSid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) 'override and user SID recorded'
    Remove-Item -LiteralPath $Parent -Recurse -Force
    Check (-not (Test-Path -LiteralPath $Parent)) 'project folder deleted'
    $us = (Get-ItemProperty $AppKey).UninstallString
    Check (Run-Cmd "$us -NoRestartPrompt") 'Installed apps uninstall succeeded'
    Assert-Restored 'after uninstall from Installed apps'
    Check ((Get-ItemProperty $regCU).'Segoe UI Variable (TrueType)' -eq $fakeUserFont) 'per-user override put back'
    Remove-ItemProperty -Path $regCU -Name 'Segoe UI Variable (TrueType)'

    # Last: in Windows Sandbox, a folder re-created where one was just moved aside cannot reuse names
    # renamed away inside it (real NTFS can), so this runs once, after the other scenarios.
    Log '=== 9. a standard user prepares the backup folder before the install'
    cmd /c "rd /s /q `"$Backup`""
    robocopy $Src $App /E /XD .git sandbox-results /NFL /NDL /NJH /NJS /NP | Out-Null
    $code = Run-AsStandardUser "New-Item -ItemType Directory -Force '$Backup\uninstaller' | Out-Null; 'created'"
    Check ($code -eq 0 -and (Test-Path -LiteralPath "$Backup\uninstaller")) "standard user created $Backup\uninstaller (exit $code)"
    Check (Run-Cmd "`"$App\Install.cmd`" -NoRestorePoint -NoRestartPrompt") 'Install.cmd succeeded'
    Assert-Installed 'after Install.cmd over a prepared folder'
    Check ($null -ne (Get-ChildItem -LiteralPath $env:ProgramData -Filter 'AppleFontsOnWindows.untrusted-*' -Directory)) 'the prepared folder was moved aside'
    Check (Test-AdminOnlyTree $Backup) 'the new backup folder and everything in it: administrators-only'
    Check (Run "$App\uninstall.ps1" @{ NoRestartPrompt = $true }) 'uninstall succeeded'
    Assert-Restored 'after uninstall'
} catch {
    $script:fails++
    Log "UNEXPECTED: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)"
}
Log $(if ($script:fails) { "SCRIPT TEST FAILED ($script:fails failed checks)" } else { 'SCRIPT TEST PASSED' })
