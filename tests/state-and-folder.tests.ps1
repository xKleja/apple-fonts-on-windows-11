# Unit tests for scripts/backup-location.ps1 (no admin rights, changes nothing outside %TEMP%).
# Runs in CI on Windows PowerShell 5.1 and PowerShell 7:  powershell -File tests\state-and-folder.tests.ps1
# Exit code 0 = all passed.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\backup-location.ps1')
$script:fails = 0
function Check([bool]$ok, [string]$what) { if ($ok) { "PASS $what" } else { $script:fails++; "FAIL $what" } }
function Accepted($state) { try { Assert-SafeState $state; $true } catch { $false } }
function New-State([scriptblock]$Change) {
    $s = [pscustomobject]@{
        Complete = $true; UserSid = 'S-1-5-21-1111111111-2222222222-3333333333-1001'
        SFFonts  = @([pscustomobject]@{ File = 'SF-Pro.ttf'; Registry = 'SF Pro (TrueType)'; KeepFile = $false },
                     [pscustomobject]@{ File = 'NewYorkExtraLarge-Black.otf'; Registry = 'New York Extra Large Black (OpenType)'; KeepFile = $false })
        UI       = @([pscustomobject]@{ Registry = 'Segoe UI Semilight Italic (TrueType)'; Original = 'seguisli.ttf'; New = 'SFUI-seguisli.ttf' },
                     [pscustomobject]@{ Registry = 'Segoe UI Variable (TrueType)'; Original = 'SegUIVar.ttf'; New = 'SFUI-SegUIVar.ttf' })
        HKCU     = @([pscustomobject]@{ Registry = 'Segoe UI Variable (TrueType)'; Value = 'C:\Users\Ana Maria\AppData\Local\Microsoft\Windows\Fonts\SegUIVar.ttf' })
        EmojiReg = [pscustomobject]@{ Registry = 'Segoe UI Emoji (TrueType)'; Original = 'seguiemj.ttf'; New = 'SFUI-seguiemj.ttf' }
    }
    if ($Change) { & $Change $s }
    $s | ConvertTo-Json -Depth 5 | ConvertFrom-Json   # as read back from state.json
}

'== Assert-SafeState'
Check (Accepted (New-State)) 'a state as the install writes it is accepted'
Check (Accepted (New-State { param($s) $s.UI = @(); $s.HKCU = @(); $s.EmojiReg = $null; $s.UserSid = $null })) 'SF-only state without user SID (older installs) is accepted'
Check (-not (Accepted (New-State { param($s) $s.SFFonts[0].File = 'arial.ttf' }))) 'SF entry for a Windows font is rejected'
Check (-not (Accepted (New-State { param($s) $s.SFFonts[0].File = '..\..\System32\x.ttf' }))) 'SF entry with a path is rejected'
Check (-not (Accepted (New-State { param($s) $s.UI[0].Registry = 'Segoe Fluent Icons (TrueType)' }))) 'UI entry for an icon font is rejected'
Check (-not (Accepted (New-State { param($s) $s.UI[0].Original = 'calibri.ttf'; $s.UI[0].New = 'SFUI-calibri.ttf' }))) 'UI entry for a non-Segoe file is rejected'
Check (-not (Accepted (New-State { param($s) $s.UI[0].New = 'SFUI-segoeui.ttf' }))) 'UI entry with a mismatched new file is rejected'
Check (-not (Accepted (New-State { param($s) $s.EmojiReg.Registry = 'Segoe UI Symbol (TrueType)' }))) 'emoji entry for another family is rejected'
Check (-not (Accepted (New-State { param($s) $s.EmojiReg.Original = 'calibri.ttf' }))) 'emoji entry for another file is rejected'
Check (-not (Accepted (New-State { param($s) $s.HKCU[0].Value = '\\server\share\evil.ttf' }))) 'per-user value on a network path is rejected'
Check (-not (Accepted (New-State { param($s) $s.HKCU[0].Registry = 'Arial (TrueType)' }))) 'per-user entry for another family is rejected'
Check (-not (Accepted (New-State { param($s) $s.UserSid = 'S-1-5-18' }))) 'SYSTEM as the user SID is rejected'

'== Test-AdminOnlyItem / Test-AdminOnlyTree'
$tmp = Join-Path ([IO.Path]::GetTempPath()) "aftest-$PID"
[void][IO.Directory]::CreateDirectory($tmp)
try {
    # A folder in the user's temp: owned by and writable for this (non-admin or admin) user.
    $me = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($me.User, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-545'), 'Modify', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
    Set-Acl -LiteralPath $tmp -AclObject $acl
    Check (-not (Test-AdminOnlyItem $tmp)) 'a folder that Users can modify is not trusted'
    Check (-not (Test-AdminOnlyTree $tmp)) '...nor is its tree'
    if ($isAdmin) {
        Protect-BackupDir $tmp -Custom:$false 2>$null | Out-Null   # untrusted default-style folder: moved aside, recreated
        Check (Test-AdminOnlyTree $tmp) 'Protect-BackupDir leaves an administrators-only folder'
        $users = (Get-Acl -LiteralPath $tmp).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq 'S-1-5-32-545' }
        Check ($users -and -not ([int]$users.FileSystemRights -band $WriteMask)) 'Users can read it but not write'
    } else { 'SKIP Protect-BackupDir checks (not running as administrator)' }
} finally {
    foreach ($d in @($tmp) + @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Filter "aftest-$PID.untrusted-*" -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)) {
        if (Test-Path -LiteralPath $d) { cmd /c "rd /s /q `"$d`"" | Out-Null }
    }
}

if ($script:fails) { "$($script:fails) FAILED"; exit 1 }
'ALL PASSED'
