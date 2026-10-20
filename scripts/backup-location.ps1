# Shared by install-macos-fonts.ps1, restore-macos-fonts.ps1 and status.ps1 (and copied, with the
# restore, into the backup folder for the Installed apps uninstaller): where state, registry exports
# and logs live, how that folder is protected, and what a valid state.json may contain.

$script:DefaultBackupDir = Join-Path $env:ProgramData 'AppleFontsOnWindows'
# Settings > Apps > Installed apps entry (written by the install, removed by the restore)
$script:UninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\AppleFontsOnWindows'

# The only Windows registrations the install changes, and the only files it adds.
$script:UIFiles   = 'segoeuil.ttf', 'segoeuisl.ttf', 'segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf', 'seguibl.ttf',
                    'seguili.ttf', 'seguisli.ttf', 'segoeuii.ttf', 'seguisbi.ttf', 'segoeuiz.ttf', 'seguibli.ttf', 'SegUIVar.ttf'
$script:EmojiFile = 'seguiemj.ttf'
$script:SFFilePattern  = '^(SF-[A-Za-z0-9-]+|NewYork[A-Za-z0-9-]*)\.(ttf|otf)$'   # all 155 Apple files, no Windows font
$script:SegoeUIPattern = '^Segoe UI( Variable( (Text|Display|Small))?)?( (Light|Semilight|Semibold|Bold|Black|Italic))* \(TrueType\)$'
$script:EmojiPattern   = '^Segoe UI Emoji \(TrueType\)$'

function Get-DefaultBackupDir { $script:DefaultBackupDir }

# A path the user typed, resolved against PowerShell's current folder (not .NET's, which 5.1 does not keep in step).
function Resolve-UserPath([string]$Path) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) }

$script:AdminSids = 'S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'   # SYSTEM, Administrators, TrustedInstaller
# Write-type rights (data, append, attributes, delete, permissions, ownership, generic write/all)
$script:WriteMask = 2 -bor 4 -bor 16 -bor 64 -bor 256 -bor 65536 -bor 262144 -bor 524288 -bor 0x40000000 -bor 0x10000000

# True when only administrators can change this file or folder (owner and DACL), and it is no link.
function Test-AdminOnlyItem([string]$Path) {
    try {
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        $acl = Get-Acl -LiteralPath $Path
        $owner = (New-Object Security.Principal.NTAccount $acl.Owner).Translate([Security.Principal.SecurityIdentifier]).Value
        # Elevated admins create files owned by Administrators; with the "object creator" policy, by themselves.
        if ($owner -notin $script:AdminSids -and $owner -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) { return $false }
        foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($r.AccessControlType -eq 'Allow' -and $r.IdentityReference.Value -notin $script:AdminSids -and
                ([int]$r.FileSystemRights -band $script:WriteMask)) { return $false }
        }
        $true
    } catch { $false }   # unreadable = not trusted
}

# True when the folder and everything in it can only be changed by administrators. Links are not followed.
function Test-AdminOnlyTree([string]$Dir) {
    $pending = [Collections.Generic.Stack[string]]::new(); $pending.Push($Dir)
    while ($pending.Count) {
        $d = $pending.Pop()
        if (-not (Test-AdminOnlyItem $d)) { return $false }
        try { $children = @(Get-ChildItem -LiteralPath $d -Force -ErrorAction Stop) } catch { return $false }
        foreach ($c in $children) {
            if ($c.PSIsContainer -and -not ($c.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $pending.Push($c.FullName) }
            elseif (-not (Test-AdminOnlyItem $c.FullName)) { return $false }
        }
    }
    $true
}

# The elevated scripts trust what is in this folder, so only administrators may change it. Everyone may
# read it (status.ps1 and the Installed apps uninstaller run unelevated first).
# An existing folder that a standard user could have prepared (owner, permissions, links) is never
# trusted: the default one is moved aside and recreated, a custom one is refused.
function Protect-BackupDir([string]$Dir, [switch]$Custom) {
    if ((Test-Path -LiteralPath $Dir) -and -not (Test-AdminOnlyTree $Dir)) {
        if ($Custom) { throw "The folder $Dir (or something in it) can be changed by non-administrators, so it cannot hold the install's backups. Use a new folder (it is created for administrators only) or leave out -BackupDir. Nothing was changed." }
        $hasState = try { Test-Path -LiteralPath (Join-Path $Dir 'state.json') } catch { $true }
        if ($hasState) { throw "The permissions of $Dir were changed so that non-administrators can modify it. Uninstall (it still works), then install again. Nothing was changed." }
        $aside = "$Dir.untrusted-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Move-Item -LiteralPath $Dir -Destination $aside
        "Note: $Dir already existed with permissions a standard user could change; moved it to $aside"
    }
    if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Force $Dir | Out-Null }
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)   # no inherited rules
    $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach ($rule in @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {   # SYSTEM, Administrators, Users (read)
        $id = New-Object System.Security.Principal.SecurityIdentifier $rule[0]
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($id, $rule[1], $inherit, 'None', 'Allow')))
    }
    $acl.SetOwner((New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'))
    Set-Acl -LiteralPath $Dir -AclObject $acl
}

# Reject anything in state.json that the install itself would not have written, so a modified
# state.json cannot make the elevated restore or -Resume touch other fonts or registry values.
function Assert-SafeState($state) {
    $reg = '^[^\\/]+ \((TrueType|OpenType)\)$'
    $bad = @()
    foreach ($s in @($state.SFFonts | Where-Object { $_ })) {
        if ($s.File -notmatch $script:SFFilePattern -or $s.Registry -notmatch $reg) { $bad += "SFFonts: $($s.File) / $($s.Registry)" }
    }
    foreach ($u in @($state.UI | Where-Object { $_ })) {
        if ($u.Original -notin $script:UIFiles -or $u.New -ne "SFUI-$($u.Original)" -or $u.Registry -notmatch $script:SegoeUIPattern) { $bad += "UI: $($u.Registry) / $($u.Original)" }
    }
    $hkcuValue = '^([^\\/:*?"<>|]+|[A-Za-z]:\\([^\\/:*?"<>|]+\\)+AppData\\Local\\Microsoft\\Windows\\Fonts\\[^\\/:*?"<>|]+)\.(ttf|otf|ttc)$'
    foreach ($c in @($state.HKCU | Where-Object { $_ })) {
        if (($c.Registry -notmatch $script:SegoeUIPattern -and $c.Registry -notmatch $script:EmojiPattern) -or $c.Value -notmatch $hkcuValue) { $bad += "HKCU: $($c.Registry) / $($c.Value)" }
    }
    if ($state.EmojiReg) {
        $e = $state.EmojiReg
        if ($e.Original -ne $script:EmojiFile -or $e.New -ne "SFUI-$($script:EmojiFile)" -or $e.Registry -notmatch $script:EmojiPattern) { $bad += "EmojiReg: $($e.Registry) / $($e.Original)" }
    }
    if ($state.UserSid -and $state.UserSid -notmatch '^S-1-(5-21|12-1)(-\d+)+$') { $bad += "UserSid: $($state.UserSid)" }
    if ($bad) { throw "state.json contains unexpected entries; refusing to act on it:`n  " + ($bad -join "`n  ") }
}

# The per-user font key of the user the install was started for (see install-macos-fonts.ps1 -UserSid).
# $null when that user's registry hive is not loaded (signed out).
function Get-UserFontKey([string]$Sid) {
    if (-not $Sid) { return 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' }
    if (-not (Test-Path -LiteralPath "Registry::HKEY_USERS\$Sid")) { return $null }
    "Registry::HKEY_USERS\$Sid\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
}
