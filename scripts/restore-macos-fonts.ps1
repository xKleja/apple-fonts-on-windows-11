# Undoes install-macos-fonts.ps1 exactly, using the state it recorded. Run elevated, then restart.
#Requires -RunAsAdministrator
param([string]$BackupDir)   # default: see backup-location.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'backup-location.ps1')
if (-not $BackupDir) { $BackupDir = Get-DefaultBackupDir }
$Fonts = "$env:WINDIR\Fonts"
$RegLM = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$RegCU = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$Emoji = "$Fonts\seguiemj.ttf"
$StatePath = Join-Path $BackupDir 'state.json'   # not "$State": PowerShell names are case-insensitive ($state = data)
if (-not (Test-Path $StatePath)) { throw "No install state at $StatePath; nothing to restore." }
$state = Get-Content $StatePath -Raw | ConvertFrom-Json
Start-Transcript -Path (Join-Path $BackupDir "restore-$(Get-Date -Format yyyyMMdd-HHmmss).log") | Out-Null
$leftover = @()

# Run a system tool with a time limit: a hang becomes a clear error instead of a stuck restore.
function Invoke-Tool([string]$Exe, [string]$Arguments, [int]$TimeoutSec = 60) {
    "  > $Exe $Arguments"
    $p = Start-Process $Exe -ArgumentList $Arguments -NoNewWindow -PassThru `
        -RedirectStandardOutput "$BackupDir\tool-out.txt" -RedirectStandardError "$BackupDir\tool-err.txt"
    $null = $p.Handle   # keep the process handle, otherwise .NET cannot report ExitCode afterwards
    if (-not $p.WaitForExit($TimeoutSec * 1000)) { $p.Kill(); throw "$Exe timed out after $TimeoutSec s ($Arguments)" }
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw "$Exe failed with code $($p.ExitCode): $(Get-Content "$BackupDir\tool-err.txt" -Raw)" }
}

function Remove-FontFile([string]$Path) {
    try { Remove-Item $Path -Force -ErrorAction Stop }
    catch { $script:leftover += $Path }   # still loaded; harmless once unregistered, removed below at restart
}

# UI registrations back to the original Segoe files
foreach ($u in $state.UI) {
    Set-ItemProperty -Path $RegLM -Name $u.Registry -Value $u.Original
    Remove-FontFile (Join-Path $Fonts $u.New)
}
foreach ($c in $state.HKCU) {
    New-ItemProperty -Path $RegCU -Name $c.Registry -Value $c.Value -PropertyType String -Force | Out-Null
}
"UI: $(@($state.UI).Count) Segoe registrations restored, $(@($state.HKCU).Count) per-user entries re-registered"

# SF / New York families
foreach ($s in $state.SFFonts) {
    Remove-ItemProperty -Path $RegLM -Name $s.Registry -ErrorAction SilentlyContinue
    Remove-FontFile (Join-Path $Fonts $s.File)
}
"Removed $(@($state.SFFonts).Count) SF / New York fonts"

# Emoji
Add-Type -Namespace W -Name K -MemberDefinition '[DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool MoveFileEx(string a, string b, int f);'
$SessionMgr = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'

if ($state.EmojiReg) {
    Set-ItemProperty -Path $RegLM -Name $state.EmojiReg.Registry -Value $state.EmojiReg.Original
    Remove-FontFile (Join-Path $Fonts $state.EmojiReg.New)
    'Emoji: "Segoe UI Emoji" points at the original seguiemj.ttf again'
}

# Older installs swapped seguiemj.ttf itself
if ($state.Emoji) {
    $original = "$BackupDir\seguiemj.ttf.original"
    'Emoji: taking ownership'
    Invoke-Tool takeown.exe "/f `"$Emoji`" /a"
    Invoke-Tool icacls.exe "`"$Emoji`" /grant Administrators:F"
    if ($state.EmojiPending -and (Test-Path $state.EmojiPending)) {
        # Restoring before the restart that would have swapped it: cancel the scheduled swap.
        'Emoji: cancelling the swap scheduled for the next restart'
        $ops = @((Get-ItemProperty $SessionMgr -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
        $keep = @(); for ($i = 0; $i -lt $ops.Count; $i += 2) {
            if ($ops[$i] -notlike "*$(Split-Path $state.EmojiPending -Leaf)") { $keep += $ops[$i], $ops[$i + 1] }
        }
        if ($keep.Count) { Set-ItemProperty $SessionMgr -Name PendingFileRenameOperations -Value ([string[]]$keep) -Type MultiString }
        else { Remove-ItemProperty $SessionMgr -Name PendingFileRenameOperations -ErrorAction SilentlyContinue }
        Remove-Item $state.EmojiPending -Force
    } else {
        'Emoji: swapping the original back'
        $aside = "$Emoji.apple-$(Get-Date -Format yyyyMMddHHmmss)"
        $renamed = $true
        try { Rename-Item $Emoji $aside } catch { $renamed = $false }
        if ($renamed) {
            try { Copy-Item $original $Emoji }
            catch { Rename-Item $aside $Emoji; throw "Copying the original emoji font back failed: $_" }
            Remove-FontFile $aside
        } else {
            # In use: Windows puts the original back early in the next restart.
            $pending = "$Fonts\seguiemj.ttf.segoe-pending"
            Copy-Item $original $pending -Force
            if (-not [W.K]::MoveFileEx($pending, $Emoji, 0x5)) { throw "Could not schedule the original emoji font to return (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
            'Emoji: in use; the original Segoe UI Emoji returns during the next restart'
        }
    }
    # Owner first (needs full control, granted above), then the original access list.
    'Emoji: restoring Windows permissions'
    try {
        Invoke-Tool icacls.exe "`"$Emoji`" /setowner `"NT SERVICE\TrustedInstaller`""
        Invoke-Tool icacls.exe "`"$Fonts`" /restore `"$BackupDir\seguiemj.acl`""
    } catch { "WARNING: could not restore the file's original permissions ($($_.Exception.Message)); harmless." }
    if ($state.EmojiAside -and (Test-Path $state.EmojiAside)) { Remove-FontFile $state.EmojiAside }
    'Original Segoe UI Emoji restored'
}

# Files still in use: delete them at next restart
if ($leftover) {
    # [NullString]::Value: a real null target (plain $null would become "" and fail)
    foreach ($p in $leftover) { [void][W.K]::MoveFileEx($p, [NullString]::Value, 4) }   # MOVEFILE_DELAY_UNTIL_REBOOT
    "$($leftover.Count) font files in use will be deleted at restart"
}

Rename-Item $StatePath "state.restored-$(Get-Date -Format yyyyMMdd-HHmmss).json"
'Font cache: stopping the service'
$svc = Start-Job { Stop-Service FontCache -Force -ErrorAction SilentlyContinue }
if (-not (Wait-Job $svc -Timeout 60)) { 'Font cache service did not stop in 60 s; the cache will rebuild at restart anyway' }
Remove-Job $svc -Force
Remove-Item "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache\*FontCache*" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:WINDIR\System32\FNTCACHE.DAT" -Force -ErrorAction SilentlyContinue
'DONE. Restart Windows now.'
Stop-Transcript | Out-Null
