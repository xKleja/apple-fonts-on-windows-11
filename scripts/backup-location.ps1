# Where install/restore keep their state, registry exports, logs and the original emoji font.
# Dot-sourced by install-macos-fonts.ps1, restore-macos-fonts.ps1 and status.ps1.

$script:DefaultBackupDir = Join-Path $env:ProgramData 'AppleFontsOnWindows'

function Get-DefaultBackupDir { $script:DefaultBackupDir }

# The elevated scripts trust state.json, so its folder must not be writable by standard users.
function Protect-BackupDir([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Force $Dir | Out-Null }
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)   # no inherited rules
    $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach ($sid in 'S-1-5-18', 'S-1-5-32-544') {   # SYSTEM, Administrators
        $id = (New-Object System.Security.Principal.SecurityIdentifier $sid).Translate([System.Security.Principal.NTAccount])
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($id, 'FullControl', $inherit, 'None', 'Allow')))
    }
    $acl.SetOwner((New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'))
    Set-Acl -LiteralPath $Dir -AclObject $acl
}

# Reject anything in state.json that could make the elevated restore touch files or registry
# values outside what the install itself creates.
function Assert-SafeState($state) {
    $file  = '^[A-Za-z0-9 ._()-]+\.(ttf|otf)$'
    $sfui  = '^SFUI-[A-Za-z0-9._-]+\.ttf$'
    $reg   = '^[^\\/]+ \((TrueType|OpenType)\)$'
    $bad = @()
    foreach ($s in @($state.SFFonts | Where-Object { $_ })) { if ($s.File -notmatch $file -or $s.File -like 'SFUI-*' -or $s.Registry -notmatch $reg) { $bad += "SFFonts: $($s.File) / $($s.Registry)" } }
    foreach ($u in @($state.UI | Where-Object { $_ }))      { if ($u.New -notmatch $sfui -or $u.Original -notmatch $file -or $u.Registry -notmatch $reg) { $bad += "UI: $($u.Registry)" } }
    foreach ($c in @($state.HKCU | Where-Object { $_ }))    { if ($c.Registry -notmatch '^Segoe UI[^\\/]* \(TrueType\)$') { $bad += "HKCU: $($c.Registry)" } }
    if ($state.EmojiReg) {
        $e = $state.EmojiReg
        if ($e.New -notmatch $sfui -or $e.Original -notmatch $file -or $e.Registry -notmatch $reg) { $bad += "EmojiReg: $($e.Registry)" }
    }
    if ($bad) { throw "state.json contains unexpected entries; refusing to act on it:`n  " + ($bad -join "`n  ") }
}
