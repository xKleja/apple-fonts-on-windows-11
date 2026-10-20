# Installs Apple's fonts on Windows 11 and makes Windows use them for its UI and emoji.
# Normally started by the repo's install.ps1. Run elevated. Undo with uninstall.ps1. Restart afterwards.
#
#  1. Verifies every font against the SHA256SUMS files tracked in git
#  2. Pre-flight: finds every conflict before anything changes (existing files, registry names,
#     a previous uninstall still waiting for a restart)
#  3. Safety nets: restore point, registry exports, state.json (records each change *before* it is made)
#  4. Installs the Apple SF / New York families (new fonts only, nothing overwritten)
#  5. UI: copies SF-based "Segoe UI" / "Segoe UI Variable" as new files (SFUI-*.ttf) and points
#     Windows' existing Segoe UI registrations at them. Original Segoe files are not modified.
#  6. Emoji: Apple Color Emoji as SFUI-seguiemj.ttf; the "Segoe UI Emoji" registration points at it
#  7. Adds the Settings > Apps > Installed apps entry
#  8. Clears the font cache so the change applies cleanly on restart
# The window shows these as steps 4-7 of install.ps1's seven (scripts\ui.ps1).
#Requires -RunAsAdministrator
param(
    [string]$FontsDir = (Join-Path $PSScriptRoot '..\fonts'),   # holds SF\, ui\, emoji\ and SHA256SUMS.txt
    [string]$BackupDir,                                          # default %ProgramData%\AppleFontsOnWindows
    [string]$UserSid,   # the signed-in user whose per-user font overrides are handled (install.ps1 passes it;
                        # differs from the elevated account when an administrator's password was typed at UAC)
    [switch]$NoRestorePoint,
    [switch]$SkipEmoji,
    [switch]$SkipUI,
    [switch]$Resume     # continue an interrupted install from its recorded state
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'backup-location.ps1')
. (Join-Path $PSScriptRoot 'checks.ps1')
. (Join-Path $PSScriptRoot 'ui.ps1')
Assert-SupportedWindows

$Fonts     = "$env:WINDIR\Fonts"
$RegLM     = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$PSProps   = 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider'
$Version   = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\VERSION') -TotalCount 1 -ErrorAction SilentlyContinue)

$defaultBackup = -not $BackupDir
$BackupDir = if ($defaultBackup) { Get-DefaultBackupDir } else { Resolve-UserPath $BackupDir }
$StatePath = Join-Path $BackupDir 'state.json'   # not "$State": PowerShell names are case-insensitive ($state = data)
# Only administrators may change this folder: the elevated scripts trust state.json and the uninstaller in it.
$protectNotes = @(Protect-BackupDir $BackupDir -Custom:(-not $defaultBackup))

$LogPath = Join-Path $BackupDir "install-$(Get-Date -Format yyyyMMdd-HHmmss).log"
Start-Transcript -LiteralPath $LogPath -ErrorAction SilentlyContinue | Out-Null
try {
Write-Detail "apple-fonts-on-windows-11 $Version; Windows $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion) build $([Environment]::OSVersion.Version.Build); run by $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Step 4 'Safety checks before any change'
foreach ($n in $protectNotes) { Write-Warn ($n -replace '^Note: ', '') }

# Run a system tool with a time limit: a hang becomes a clear error instead of a stuck install.
# Output is read through pipes (no temp files, so no path in the backup folder can be redirected).
function Invoke-Tool([string]$Exe, [string]$Arguments, [int]$TimeoutSec = 60, [switch]$AllowFail) {
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe, $Arguments
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) { $p.Kill(); throw "$Exe timed out after $TimeoutSec s ($Arguments)" }
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        if ($AllowFail) { "  (exit code $($p.ExitCode), ignored)" }
        else { throw "$Exe failed with code $($p.ExitCode): $($err.Result)$($out.Result)" }
    }
}

# Items of a recorded list; @($null) would otherwise yield one $null item.
function Get-Items($list) { @($list | Where-Object { $_ }) }

# Relative path -> expected SHA-256, from a SHA256SUMS.txt
function Read-Sums([string]$Dir) {
    $map = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $Dir 'SHA256SUMS.txt')) {
        if (-not $line.Trim()) { continue }
        $hash, $rel = $line.Trim() -split '\s+', 2
        $map[($rel.TrimStart('*').TrimStart('.', '/') -replace '/', '\')] = $hash.ToUpperInvariant()
    }
    $map
}

function Test-Sums([string]$Dir, $Expected) {
    $i = 0
    foreach ($rel in $Expected.Keys) {
        if ($i++ % 8 -eq 0) { Show-Progress 'Step 4 of 7: verifying every font again' $i $Expected.Count }
        $path = Join-Path $Dir $rel
        if (-not (Test-Path -LiteralPath $path)) { throw "Missing font: $path. Nothing was changed." }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Expected[$rel]) { throw "Checksum mismatch: $path. Nothing was changed." }
    }
}

# Copy, then check the copy byte-for-byte (catches a full disk or a file swapped mid-install).
function Copy-Verified([string]$From, [string]$To, [string]$Expected) {
    Copy-Item -LiteralPath $From -Destination $To -Force
    if ((Get-FileHash -LiteralPath $To -Algorithm SHA256).Hash -ne $Expected) { throw "Copy of $From to $To is corrupt." }
}

function Get-FontEntries {
    (Get-ItemProperty $RegLM).PSObject.Properties | Where-Object { $_.Name -notin $PSProps }
}

# Saved after every change, so uninstall.ps1 can undo even an interrupted install.
# Written to a temp file first: a power cut mid-write must not leave a corrupt state.json.
# A new temp name every time: re-creating the same name right after it was renamed fails on some
# volumes ("Could not find file", seen in a folder that replaced one moved aside), and it is not guessable.
function Save-State {
    $tmp = "$StatePath.$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($tmp, ($state | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    # [NullString]::Value: a real null (plain $null becomes "" for a string argument and Replace rejects it)
    if (Test-Path -LiteralPath $StatePath) { [IO.File]::Replace($tmp, $StatePath, [NullString]::Value) }
    else { [IO.File]::Move($tmp, $StatePath) }
}

# --- 1. integrity -----------------------------------------------------------------------
$Here = (Resolve-Path -LiteralPath $FontsDir).Path
foreach ($need in 'SHA256SUMS.txt', 'SF', 'emoji', 'ui\SHA256SUMS.txt') {
    if (-not (Test-Path -LiteralPath (Join-Path $Here $need))) { throw "Missing $need in $Here. Run install.ps1 (it downloads the fonts) or see fonts\README.md." }
}
$sums   = Read-Sums $Here
$uiSums = Read-Sums (Join-Path $Here 'ui')
Test-Sums $Here $sums
Test-Sums (Join-Path $Here 'ui') $uiSums
Hide-Progress
Write-Ok "all $($sums.Count + $uiSums.Count) fonts match their checksums"

# --- 2. state: fresh install or resume ------------------------------------------------------
if (Test-Path -LiteralPath $StatePath) {
    try { $old = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json }
    catch { throw "state.json is unreadable ($($_.Exception.Message)). Restore with the HKLM-Fonts-*.reg export in $BackupDir." }
    if (-not $Resume) {
        if ($old.Complete) { throw 'Already installed. To install again, uninstall first (Settings > Apps > Installed apps), restart, then install.' }
        throw 'A previous install did not finish. Run it again with -Resume to finish it, or uninstall to undo it.'
    }
    Assert-SafeState $old
    if ($old.Complete) { throw 'Nothing to resume: the install is complete. Double-click Status.cmd to check it.' }
    # Options chosen at the original install carry over unless given again now.
    if (-not $PSBoundParameters.ContainsKey('SkipUI'))    { $SkipUI    = [switch][bool]$old.Options.SkipUI }
    if (-not $PSBoundParameters.ContainsKey('SkipEmoji')) { $SkipEmoji = [switch][bool]$old.Options.SkipEmoji }
    if ($old.UserSid) { $UserSid = $old.UserSid }   # per-user changes stay with the user they were recorded for
    $installed = if ($old.Installed -is [datetime]) { $old.Installed.ToString('s') } else { [string]$old.Installed }
    $state = [ordered]@{
        Installed = $installed; Complete = $false; Version = $Version; UserSid = $old.UserSid
        Options   = [ordered]@{ SkipUI = [bool]$SkipUI; SkipEmoji = [bool]$SkipEmoji }
        # @(): a function's output is unrolled, so 0 or 1 items would not stay a list (5.1 then
        # saves an empty list as {} and += on a single item fails)
        SFFonts   = @(Get-Items $old.SFFonts); UI = @(Get-Items $old.UI); HKCU = @(Get-Items $old.HKCU); EmojiReg = $old.EmojiReg
    }
    Write-Ok "finishing the earlier install ($($state.SFFonts.Count) SF fonts, $($state.UI.Count) UI fonts, emoji $(if ($state.EmojiReg) { 'yes' } else { 'no' }) recorded so far)"
} else {
    $state = $null
}

# Per-user font registrations of the signed-in user (HKEY_USERS\<sid>, not the elevated account's HKCU)
if (-not $UserSid) { $UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
if ($UserSid -notmatch '^S-1-(5-21|12-1)(-\d+)+$') { throw "Invalid -UserSid '$UserSid'." }
if ($state) { $state.UserSid = $UserSid }
$RegUser = Get-UserFontKey $UserSid
if (-not $RegUser) { Write-Warn "the registry of user $UserSid is not loaded; their per-user font settings are not checked" }
if ($UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) { Write-Info "per-user settings: handled for the signed-in user ($UserSid), not the administrator account used at the UAC prompt" }

# --- 3. pre-flight: every conflict is found here, before anything changes ------------------
$pendingOps = @((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
$sfNames = @($sums.Keys | Where-Object { $_ -like 'SF\*' } | ForEach-Object { Split-Path $_ -Leaf })
$blocked = $pendingOps | Where-Object { $_ -match '\\Fonts\\(SFUI-|' + (($sfNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')' }
if ($blocked) { throw 'A previous uninstall is still waiting to delete font files. Restart Windows first (Start > Power > Restart; "Shut down" is not enough), then install.' }

Add-Type -AssemblyName PresentationCore
$en       = [Globalization.CultureInfo]'en-US'
$entries  = @(Get-FontEntries)
$userEntries = if ($RegUser -and (Test-Path -LiteralPath $RegUser)) { @((Get-ItemProperty -LiteralPath $RegUser).PSObject.Properties | Where-Object { $_.Name -notin $PSProps }) } else { @() }
$recorded = @{}; if ($state) { foreach ($s in $state.SFFonts) { $recorded[$s.File] = $s } }
$sfPlan   = @()
$perUserSF = @()
$sfRels = @($sums.Keys | Where-Object { $_ -like 'SF\*' })
$i = 0
foreach ($rel in $sfRels) {
    if ($i++ % 8 -eq 0) { Show-Progress 'Step 4 of 7: looking for conflicts with fonts already on this PC' $i $sfRels.Count }
    $src  = Join-Path $Here $rel
    $leaf = Split-Path $rel -Leaf
    $dest = Join-Path $Fonts $leaf
    $gt   = [Windows.Media.GlyphTypeface]::new([Uri]$src)
    $fam  = $null; $face = $null
    [void]$gt.Win32FamilyNames.TryGetValue($en, [ref]$fam)
    [void]$gt.Win32FaceNames.TryGetValue($en, [ref]$face)
    if (-not $fam) { throw "$leaf has no English family name; refusing to register it." }
    $kind = if ($leaf -like '*.otf') { 'OpenType' } else { 'TrueType' }
    $name = "$fam $face ($kind)".Trim()
    $item = [pscustomobject]@{ Src = $src; Leaf = $leaf; Dest = $dest; Name = $name; Hash = $sums[$rel]; Skip = $false; KeepFile = $false }
    if ($userEntries | Where-Object { $_.Name -eq $name }) { $perUserSF += $name }
    if (-not $recorded.ContainsKey($leaf)) {
        $existing = $entries | Where-Object { $_.Name -eq $name }
        if ($existing -and $existing.Value -ine $leaf) {
            throw "The font name '$name' is already registered to $($existing.Value). Uninstall that font first. Nothing was changed."
        }
        if (Test-Path -LiteralPath $dest) {
            if ((Get-FileHash -LiteralPath $dest).Hash -ne $item.Hash) { throw "$Fonts already has a different $leaf. Uninstall that font first. Nothing was changed." }
            # The identical Apple file is already there (installed by something else): never take
            # ownership of the file. If it is also registered, leave it entirely alone; if not, only
            # the registry entry is ours (uninstall removes the entry and keeps the file).
            if ($existing) { $item.Skip = $true } else { $item.KeepFile = $true }
        }
    }
    $sfPlan += $item
}
Hide-Progress
if ($perUserSF) { Write-Warn "$($perUserSF.Count) SF / New York fonts are also installed for this user only (for example '$($perUserSF[0])'). Apps may list them twice; remove them in Settings > Personalization > Fonts if you like." }

$uiPlan = @()
if (-not $SkipUI) {
    foreach ($file in $UIFiles) {
        $rec = if ($state) { @($state.UI | Where-Object { $_.Original -ieq $file }) } else { @() }
        if ($rec) { foreach ($r in $rec) { $uiPlan += [pscustomobject]@{ File = $file; Registry = $r.Registry; Original = $r.Original; Recorded = $true } }; continue }
        $hits = @($entries | Where-Object { $_.Value -ieq $file })
        if (-not $hits) { throw "Windows' registration for $file is missing or was changed (another font tool?). Undo that tool's change first. Nothing was changed." }
        foreach ($h in $hits) {
            if ($h.Name -notmatch $SegoeUIPattern) { throw "Unexpected registration '$($h.Name)' for $file. Nothing was changed." }
            $uiPlan += [pscustomobject]@{ File = $file; Registry = $h.Name; Original = $h.Value; Recorded = $false }
        }
    }
}
$emojiPlan = $null
if (-not $SkipEmoji -and -not ($state -and $state.EmojiReg)) {
    $hit = @($entries | Where-Object { $_.Value -ieq $EmojiFile })
    if ($hit.Count -ne 1 -or $hit[0].Name -notmatch $EmojiPattern) { throw "Expected one 'Segoe UI Emoji' registration for $EmojiFile, found $($hit.Count) ($($hit.Name -join ', ')). Nothing was changed." }
    $emojiPlan = $hit[0]
}
# A font substitution set by another tool takes priority over the registrations changed here.
$subst = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes' -ErrorAction SilentlyContinue
$substNames = if ($subst) { @($subst.PSObject.Properties | Where-Object { $_.Name -notin $PSProps -and $_.Name -match '^Segoe UI( Variable.*| Emoji)?(,\d+)?$' } | ForEach-Object Name) } else { @() }
if ($substNames) { Write-Warn "FontSubstitutes redirects $($substNames -join ', ') to another font (set by another tool); some apps keep showing that font until it is removed." }
Write-Ok 'no conflicts found - nothing has been changed so far'

# --- 4. safety nets (fresh install only) ------------------------------------------------------
$stamp = Get-Date -Format yyyyMMdd-HHmmss
Write-Step 5 'Safety nets'
if ($state) { Write-Ok 'kept from the earlier install (restore point and registry backups)' }
if (-not $state) {
    if ($NoRestorePoint) { Write-Info 'no restore point (-NoRestorePoint)' }
    else {
        $job = Start-Job { Checkpoint-Computer -Description 'Before macOS fonts' -RestorePointType MODIFY_SETTINGS -WarningAction Stop }
        if (Wait-WithTimer $job 'Step 5 of 7: creating a System Restore point' 'Windows can take up to 3 minutes for this' 180) {
            try { Receive-Job $job -ErrorAction Stop | Out-Null; Write-Ok 'restore point "Before macOS fonts" created' }
            catch { Write-Warn "no restore point: $($_.Exception.Message)" }
        } else { Write-Warn 'no restore point: Windows did not create it within 3 minutes' }
        Remove-Job $job -Force
    }
    Invoke-Tool reg.exe "export `"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`" `"$BackupDir\HKLM-Fonts-$stamp.reg`" /y"
    if (-not (Test-Path -LiteralPath "$BackupDir\HKLM-Fonts-$stamp.reg")) { throw 'Could not export the font registry; nothing was changed.' }
    Write-Ok "font registry backed up to $BackupDir"
    # The per-user key may not exist: that is fine.
    Invoke-Tool reg.exe "export `"HKU\$UserSid\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`" `"$BackupDir\HKCU-Fonts-$stamp.reg`" /y" -AllowFail
    $state = [ordered]@{
        Installed = (Get-Date).ToString('s'); Complete = $false; Version = $Version; UserSid = $UserSid
        Options   = [ordered]@{ SkipUI = [bool]$SkipUI; SkipEmoji = [bool]$SkipEmoji }
        SFFonts   = @(); UI = @(); HKCU = @(); EmojiReg = $null
    }
    Save-State
}

# A per-user copy of a changed family would win over the system one: unregister it (file kept, recorded).
function Remove-UserOverride([string]$Pattern) {
    if (-not $RegUser -or -not (Test-Path -LiteralPath $RegUser)) { return }
    $found = (Get-ItemProperty -LiteralPath $RegUser).PSObject.Properties | Where-Object { $_.Name -notin $PSProps -and $_.Name -match $Pattern }
    foreach ($e in $found) {
        $state.HKCU += [ordered]@{ Registry = $e.Name; Value = [string]$e.Value }
        Save-State
        Remove-ItemProperty -LiteralPath $RegUser -Name $e.Name
    }
}

# --- 5. Apple SF / New York families ----------------------------------------------------
# All recorded first, in one save: an interruption from here on is undone by uninstall.ps1, which skips
# files and entries that were not created yet. (Every planned font is new to this PC: pre-flight made sure.)
$alreadyThere = @($sfPlan | Where-Object Skip).Count
$toRecord = @($sfPlan | Where-Object { -not $_.Skip -and -not $recorded.ContainsKey($_.Leaf) })
foreach ($p in $toRecord) { $state.SFFonts += [ordered]@{ File = $p.Leaf; Registry = $p.Name; KeepFile = $p.KeepFile } }
if ($toRecord) { Save-State }
Write-Step 6 'Installing'
$i = 0
foreach ($p in $sfPlan) {
    if ($i++ % 4 -eq 0) { Show-Progress 'Step 6 of 7: installing the SF / New York fonts' $i $sfPlan.Count }
    if ($p.Skip) { continue }
    if (-not (Test-Path -LiteralPath $p.Dest) -or (Get-FileHash -LiteralPath $p.Dest).Hash -ne $p.Hash) { Copy-Verified $p.Src $p.Dest $p.Hash }
    New-ItemProperty -Path $RegLM -Name $p.Name -Value $p.Leaf -PropertyType String -Force | Out-Null
}
Hide-Progress
Write-Ok ("$(@($state.SFFonts).Count) SF / New York fonts installed" + $(if ($alreadyThere) { " ($alreadyThere identical ones were already there and are left as they are)" }))

# --- 6. UI fonts: repoint Segoe UI + Segoe UI Variable registrations --------------------
if (-not $SkipUI) {
    $i = 0
    foreach ($p in $uiPlan) {
        Show-Progress 'Step 6 of 7: switching the Windows interface fonts' (++$i) $uiPlan.Count 'fonts'
        $new = "SFUI-$($p.File)"
        if (-not $p.Recorded) {
            $state.UI += [ordered]@{ Registry = $p.Registry; Original = $p.Original; New = $new }
            Save-State   # recorded before the registry changes
            # Test hook for sandbox\script-test.ps1 only: simulate a crash right after recording.
            if ($env:APPLEFONTS_TEST_CRASH_AFTER_UI -and @($state.UI).Count -eq [int]$env:APPLEFONTS_TEST_CRASH_AFTER_UI) { throw 'Simulated crash (test hook)' }
        }
        $dest = Join-Path $Fonts $new
        if (-not (Test-Path -LiteralPath $dest) -or (Get-FileHash -LiteralPath $dest).Hash -ne $uiSums[$p.File]) {
            Copy-Verified (Join-Path $Here "ui\$($p.File)") $dest $uiSums[$p.File]
        }
        Set-ItemProperty -Path $RegLM -Name $p.Registry -Value $new
    }
    Remove-UserOverride $SegoeUIPattern
    Hide-Progress
    Write-Ok "Segoe UI and Segoe UI Variable now use SF Pro ($(@($state.UI).Count) fonts)"
    if (@($state.HKCU).Count) { Write-Ok "$(@($state.HKCU).Count) per-user copy of Segoe UI unregistered (put back on uninstall)" }
}

# --- 7. emoji ---------------------------------------------------------------------------
# Same method as the UI fonts: the Apple build goes in as a new file and the "Segoe UI Emoji"
# registration points at it. seguiemj.ttf itself (Windows-protected, always in use) is never touched.
if (-not $SkipEmoji) {
    $new = 'SFUI-seguiemj.ttf'
    if ($emojiPlan) {
        $state.EmojiReg = [ordered]@{ Registry = $emojiPlan.Name; Original = $emojiPlan.Value; New = $new }
        Save-State
    }
    $hash = $sums['emoji\AppleColorEmoji-Windows.ttf']
    $dest = Join-Path $Fonts $new
    if (-not (Test-Path -LiteralPath $dest) -or (Get-FileHash -LiteralPath $dest).Hash -ne $hash) {
        Copy-Verified (Join-Path $Here 'emoji\AppleColorEmoji-Windows.ttf') $dest $hash
    }
    Set-ItemProperty -Path $RegLM -Name $state.EmojiReg.Registry -Value $new
    Write-Ok 'Segoe UI Emoji now uses Apple Color Emoji'
    Remove-UserOverride $EmojiPattern
}

# --- 8. "Installed apps" entry: uninstall from Settings, even after this folder is deleted ------
# Settings starts UninstallString as the signed-in user, unelevated; uninstall.ps1 then asks for
# administrator rights. The copy lives in the backup folder, which only administrators can change.
$state.UninstallEntry = $true
Save-State
$appDir = Join-Path $BackupDir 'uninstaller'
if (Test-Path -LiteralPath $appDir) { Remove-Item -LiteralPath $appDir -Recurse -Force }   # fresh copy, nothing left over
New-Item -ItemType Directory -Force (Join-Path $appDir 'scripts') | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\uninstall.ps1') -Destination $appDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\VERSION') -Destination $appDir
foreach ($f in 'restore-macos-fonts.ps1', 'backup-location.ps1', 'ui.ps1') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f) -Destination (Join-Path $appDir 'scripts')
}
$kb = [int]((Get-ChildItem -LiteralPath $Here -Recurse -File -Include *.ttf, *.otf | Measure-Object Length -Sum).Sum / 1KB)
$powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
New-Item $UninstallKey -Force | Out-Null
$values = [ordered]@{
    DisplayName     = 'Apple fonts on Windows 11 (community project)'
    DisplayVersion  = "$Version"
    Publisher       = 'apple-fonts-on-windows-11 contributors'
    URLInfoAbout    = 'https://github.com/xKleja/apple-fonts-on-windows-11'
    DisplayIcon     = "$env:WINDIR\System32\fontview.exe"
    InstallDate     = Get-Date -Format yyyyMMdd
    InstallLocation = $BackupDir
    UninstallString = "`"$powershell`" -NoProfile -ExecutionPolicy Bypass -File `"$appDir\uninstall.ps1`" -BackupDir `"$BackupDir`" -PauseAtEnd"
}
foreach ($k in $values.Keys) { New-ItemProperty -Path $UninstallKey -Name $k -Value $values[$k] -PropertyType String -Force | Out-Null }
foreach ($k in 'NoModify', 'NoRepair') { New-ItemProperty -Path $UninstallKey -Name $k -Value 1 -PropertyType DWord -Force | Out-Null }
New-ItemProperty -Path $UninstallKey -Name EstimatedSize -Value $kb -PropertyType DWord -Force | Out-Null
Write-Ok 'added to Settings > Apps > Installed apps'

# --- 9. state + font cache --------------------------------------------------------------
$state.Complete = $true
Save-State
Write-Step 7 'Finishing'
$svc = Start-Job { Stop-Service FontCache -Force -ErrorAction SilentlyContinue }
if (-not (Wait-WithTimer $svc 'Step 7 of 7: clearing the font cache' 'stopping the Windows font cache service' 60)) { Write-Info 'the font cache service is slow to stop; Windows rebuilds the cache at restart anyway' }
Remove-Job $svc -Force
Remove-Item "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache\*FontCache*" -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:WINDIR\System32\FNTCACHE.DAT" -Force -ErrorAction SilentlyContinue
Write-Ok 'font cache cleared'

} catch {
    # In the log too (the caller prints the message after the transcript has stopped)
    Hide-Progress
    Write-Detail "error: $($_.Exception.Message)"
    Write-Detail $_.ScriptStackTrace
    throw
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
