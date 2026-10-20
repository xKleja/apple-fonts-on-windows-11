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
#  7. Clears the font cache so the change applies cleanly on restart
#Requires -RunAsAdministrator
param(
    [string]$FontsDir = (Join-Path $PSScriptRoot '..\fonts'),   # holds SF\, ui\, emoji\ and SHA256SUMS.txt
    [string]$BackupDir,                                          # default %ProgramData%\AppleFontsOnWindows
    [switch]$NoRestorePoint,
    [switch]$SkipEmoji,
    [switch]$SkipUI,
    [switch]$Resume     # continue an interrupted install from its recorded state
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'backup-location.ps1')
. (Join-Path $PSScriptRoot 'checks.ps1')
Assert-SupportedWindows

$Fonts     = "$env:WINDIR\Fonts"
$RegLM     = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$RegCU     = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$UIFiles   = 'segoeuil.ttf','segoeuisl.ttf','segoeui.ttf','seguisb.ttf','segoeuib.ttf','seguibl.ttf',
             'seguili.ttf','seguisli.ttf','segoeuii.ttf','seguisbi.ttf','segoeuiz.ttf','seguibli.ttf','SegUIVar.ttf'
$EmojiFile = 'seguiemj.ttf'
$PSProps   = 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider'

if (-not $BackupDir) { $BackupDir = Get-DefaultBackupDir }
$BackupDir = [IO.Path]::GetFullPath($BackupDir)
$StatePath = Join-Path $BackupDir 'state.json'   # not "$State": PowerShell names are case-insensitive ($state = data)
$newBackupDir = -not (Test-Path -LiteralPath $BackupDir)
# Admin-only folder: always for the default and for a new one. An existing custom folder keeps its
# permissions, so the "Installed apps" uninstaller (which runs elevated) is not placed there.
$protectedBackup = $newBackupDir -or $BackupDir -eq (Get-DefaultBackupDir)
if ($protectedBackup) { Protect-BackupDir $BackupDir }

Start-Transcript -Path (Join-Path $BackupDir "install-$(Get-Date -Format yyyyMMdd-HHmmss).log") -ErrorAction SilentlyContinue | Out-Null
try {

# Run a system tool with a time limit: a hang becomes a clear error instead of a stuck install.
function Invoke-Tool([string]$Exe, [string]$Arguments, [int]$TimeoutSec = 60, [switch]$AllowFail) {
    "  > $Exe $Arguments"
    $p = Start-Process $Exe -ArgumentList $Arguments -NoNewWindow -PassThru `
        -RedirectStandardOutput "$BackupDir\tool-out.txt" -RedirectStandardError "$BackupDir\tool-err.txt"
    $null = $p.Handle   # keep the process handle, otherwise .NET cannot report ExitCode afterwards
    if (-not $p.WaitForExit($TimeoutSec * 1000)) { $p.Kill(); throw "$Exe timed out after $TimeoutSec s ($Arguments)" }
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        if ($AllowFail) { "  (exit code $($p.ExitCode), ignored)" }
        else { throw "$Exe failed with code $($p.ExitCode): $(Get-Content "$BackupDir\tool-err.txt" -Raw)" }
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
    foreach ($rel in $Expected.Keys) {
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
function Save-State {
    $tmp = "$StatePath.tmp"
    [IO.File]::WriteAllText($tmp, ($state | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    # [NullString]::Value: a real null (plain $null becomes "" for a string argument and Replace rejects it)
    if (Test-Path -LiteralPath $StatePath) { [IO.File]::Replace($tmp, $StatePath, [NullString]::Value) }
    else { Move-Item -LiteralPath $tmp -Destination $StatePath }
}

# --- 1. integrity -----------------------------------------------------------------------
$Here = (Resolve-Path -LiteralPath $FontsDir).Path
foreach ($need in 'SHA256SUMS.txt', 'SF', 'emoji', 'ui\SHA256SUMS.txt') {
    if (-not (Test-Path (Join-Path $Here $need))) { throw "Missing $need in $Here. Run install.ps1 (it downloads the fonts) or see fonts\README.md." }
}
$sums   = Read-Sums $Here
$uiSums = Read-Sums (Join-Path $Here 'ui')
Test-Sums $Here $sums
Test-Sums (Join-Path $Here 'ui') $uiSums
'Checksums OK'

# --- 2. state: fresh install or resume ------------------------------------------------------
if (Test-Path -LiteralPath $StatePath) {
    if (-not $Resume) { throw "Already installed (found $StatePath). Run uninstall.ps1 first, or -Resume to finish an interrupted install." }
    try { $old = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json }
    catch { throw "state.json is unreadable ($($_.Exception.Message)). Restore with the HKLM-Fonts-*.reg export in $BackupDir." }
    Assert-SafeState $old
    if ($old.Complete) { throw "Nothing to resume: the install recorded in $StatePath is complete. Run status.ps1 to check it." }
    # Options chosen at the original install carry over unless given again now.
    if (-not $PSBoundParameters.ContainsKey('SkipUI'))    { $SkipUI    = [switch][bool]$old.Options.SkipUI }
    if (-not $PSBoundParameters.ContainsKey('SkipEmoji')) { $SkipEmoji = [switch][bool]$old.Options.SkipEmoji }
    $installed = if ($old.Installed -is [datetime]) { $old.Installed.ToString('s') } else { [string]$old.Installed }
    $state = [ordered]@{
        Installed = $installed; Complete = $false
        Options   = [ordered]@{ SkipUI = [bool]$SkipUI; SkipEmoji = [bool]$SkipEmoji }
        # @(): a function's output is unrolled, so 0 or 1 items would not stay a list (5.1 then
        # saves an empty list as {} and += on a single item fails)
        SFFonts   = @(Get-Items $old.SFFonts); UI = @(Get-Items $old.UI); HKCU = @(Get-Items $old.HKCU); EmojiReg = $old.EmojiReg
    }
    "Resuming: $($state.SFFonts.Count) SF fonts, $($state.UI.Count) UI fonts, emoji=$([bool]$state.EmojiReg) already recorded"
} else {
    $state = $null
}

# --- 3. pre-flight: every conflict is found here, before anything changes ------------------
$pendingOps = @((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
$sfNames = @($sums.Keys | Where-Object { $_ -like 'SF\*' } | ForEach-Object { Split-Path $_ -Leaf })
$blocked = $pendingOps | Where-Object { $_ -match '\\Fonts\\(SFUI-|' + (($sfNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')' }
if ($blocked) { throw 'A previous uninstall is still waiting to delete font files at the next restart. Restart Windows first, then install.' }

Add-Type -AssemblyName PresentationCore
$en       = [Globalization.CultureInfo]'en-US'
$entries  = @(Get-FontEntries)
$recorded = @{}; if ($state) { foreach ($s in $state.SFFonts) { $recorded[$s.File] = $s } }
$sfPlan   = @()
foreach ($rel in @($sums.Keys | Where-Object { $_ -like 'SF\*' })) {
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
    if (-not $recorded.ContainsKey($leaf)) {
        $existing = $entries | Where-Object { $_.Name -eq $name }
        if ($existing -and $existing.Value -ine $leaf) {
            throw "The font name '$name' is already registered to $($existing.Value). Uninstall that font first. Nothing was changed."
        }
        if (Test-Path -LiteralPath $dest) {
            if ((Get-FileHash -LiteralPath $dest).Hash -ne $item.Hash) { throw "C:\Windows\Fonts already has a different $leaf. Uninstall that font first. Nothing was changed." }
            # The identical Apple file is already there (installed by something else): never take
            # ownership of the file. If it is also registered, leave it entirely alone; if not, only
            # the registry entry is ours (uninstall removes the entry and keeps the file).
            if ($existing) { $item.Skip = $true } else { $item.KeepFile = $true }
        }
    }
    $sfPlan += $item
}

$uiPlan = @()
if (-not $SkipUI) {
    foreach ($file in $UIFiles) {
        $rec = if ($state) { @($state.UI | Where-Object { $_.Original -ieq $file }) } else { @() }
        if ($rec) { foreach ($r in $rec) { $uiPlan += [pscustomobject]@{ File = $file; Registry = $r.Registry; Original = $r.Original; Recorded = $true } }; continue }
        $hits = @($entries | Where-Object { $_.Value -ieq $file })
        if (-not $hits) { throw "Windows' registration for $file is missing or was changed (another font tool?). Undo that tool's change first. Nothing was changed." }
        foreach ($h in $hits) { $uiPlan += [pscustomobject]@{ File = $file; Registry = $h.Name; Original = $h.Value; Recorded = $false } }
    }
}
$emojiPlan = $null
if (-not $SkipEmoji -and -not ($state -and $state.EmojiReg)) {
    $hit = @($entries | Where-Object { $_.Value -ieq $EmojiFile })
    if ($hit.Count -ne 1) { throw "Expected one registry entry for $EmojiFile, found $($hit.Count). Nothing was changed." }
    $emojiPlan = $hit[0]
}
# A font substitution set by another tool takes priority over the registrations changed here.
$subst = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes' -ErrorAction SilentlyContinue
$substNames = if ($subst) { @($subst.PSObject.Properties | Where-Object { $_.Name -notin $PSProps -and $_.Name -match '^Segoe UI( Variable.*| Emoji)?(,\d+)?$' } | ForEach-Object Name) } else { @() }
if ($substNames) { "Note: FontSubstitutes redirects $($substNames -join ', ') to another font (set by another tool); some apps keep showing that font until it is removed." }
'Pre-flight OK'

# --- 4. safety nets (fresh install only) ------------------------------------------------------
$stamp = Get-Date -Format yyyyMMdd-HHmmss
if (-not $state) {
    if (-not $NoRestorePoint) {
        $job = Start-Job { Checkpoint-Computer -Description 'Before macOS fonts' -RestorePointType MODIFY_SETTINGS -WarningAction Stop }
        if (Wait-Job $job -Timeout 180) {
            try { Receive-Job $job -ErrorAction Stop | Out-Null; 'Restore point created' }
            catch { "Restore point not created: $($_.Exception.Message)" }
        } else { 'Restore point not created: timed out after 180 s' }
        Remove-Job $job -Force
    }
    Invoke-Tool reg.exe "export `"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`" `"$BackupDir\HKLM-Fonts-$stamp.reg`" /y"
    if (-not (Test-Path "$BackupDir\HKLM-Fonts-$stamp.reg")) { throw 'Could not export the font registry; nothing was changed.' }
    # The per-user key may not exist: that is fine.
    Invoke-Tool reg.exe "export `"HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`" `"$BackupDir\HKCU-Fonts-$stamp.reg`" /y" -AllowFail
    $state = [ordered]@{
        Installed = (Get-Date).ToString('s'); Complete = $false
        Options   = [ordered]@{ SkipUI = [bool]$SkipUI; SkipEmoji = [bool]$SkipEmoji }
        SFFonts   = @(); UI = @(); HKCU = @(); EmojiReg = $null
    }
    Save-State
}

# --- 5. Apple SF / New York families ----------------------------------------------------
$alreadyThere = 0
foreach ($p in $sfPlan) {
    if ($p.Skip) { $alreadyThere++; continue }
    if (-not $recorded.ContainsKey($p.Leaf)) {
        $state.SFFonts += [ordered]@{ File = $p.Leaf; Registry = $p.Name; KeepFile = $p.KeepFile }
        Save-State   # recorded first: an interruption from here on is undone by uninstall.ps1
    }
    if (-not (Test-Path -LiteralPath $p.Dest) -or (Get-FileHash -LiteralPath $p.Dest).Hash -ne $p.Hash) { Copy-Verified $p.Src $p.Dest $p.Hash }
    New-ItemProperty -Path $RegLM -Name $p.Name -Value $p.Leaf -PropertyType String -Force | Out-Null
}
"Installed $(@($state.SFFonts).Count) SF / New York fonts" + $(if ($alreadyThere) { " ($alreadyThere identical ones were already installed and are left as they are)" })

# --- 6. UI fonts: repoint Segoe UI + Segoe UI Variable registrations --------------------
if (-not $SkipUI) {
    foreach ($p in $uiPlan) {
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
    # A per-user copy of the same family would win over the system one: unregister it (file kept).
    if (Test-Path $RegCU) {
        $cu = (Get-ItemProperty $RegCU).PSObject.Properties | Where-Object {
            $_.Name -notin $PSProps -and
            $_.Name -match '^Segoe UI( Variable( (Text|Display|Small))?)?( (Light|Semilight|Semibold|Bold|Black|Italic))* \(TrueType\)$' }
        foreach ($e in $cu) {
            $state.HKCU += [ordered]@{ Registry = $e.Name; Value = [string]$e.Value }
            Save-State
            Remove-ItemProperty -Path $RegCU -Name $e.Name
        }
    }
    "UI fonts: $(@($state.UI).Count) Segoe registrations point at SF; $(@($state.HKCU).Count) per-user override(s) unregistered"
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
    'Emoji: "Segoe UI Emoji" points at Apple Color Emoji'
    if (Test-Path $RegCU) {
        $cuEmoji = (Get-ItemProperty $RegCU).PSObject.Properties | Where-Object { $_.Name -eq 'Segoe UI Emoji (TrueType)' }
        foreach ($e in $cuEmoji) {
            $state.HKCU += [ordered]@{ Registry = $e.Name; Value = [string]$e.Value }
            Save-State
            Remove-ItemProperty -Path $RegCU -Name $e.Name
        }
    }
}

# --- 8. "Installed apps" entry: uninstall from Settings, even after this folder is deleted ------
# The uninstaller is copied into the admin-only backup folder, because Settings runs it elevated.
if ($protectedBackup) {
    $state.UninstallEntry = $true
    Save-State
    $appDir = Join-Path $BackupDir 'uninstaller'
    New-Item -ItemType Directory -Force (Join-Path $appDir 'scripts') | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\uninstall.ps1') -Destination $appDir -Force
    foreach ($f in 'restore-macos-fonts.ps1', 'backup-location.ps1') {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f) -Destination (Join-Path $appDir 'scripts') -Force
    }
    $release = (Get-Content -LiteralPath (Join-Path $Here 'release.txt') -TotalCount 1 -ErrorAction SilentlyContinue)
    $kb = [int]((Get-ChildItem -LiteralPath $Here -Recurse -File -Include *.ttf, *.otf | Measure-Object Length -Sum).Sum / 1KB)
    New-Item $UninstallKey -Force | Out-Null
    $values = [ordered]@{
        DisplayName     = 'Apple fonts on Windows 11 (community project)'
        DisplayVersion  = "$release".Trim().TrimStart('v')
        Publisher       = 'apple-fonts-on-windows-11 contributors'
        URLInfoAbout    = 'https://github.com/xKleja/apple-fonts-on-windows-11'
        DisplayIcon     = "$env:WINDIR\System32\fontview.exe"
        InstallDate     = Get-Date -Format yyyyMMdd
        InstallLocation = $BackupDir
        UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$appDir\uninstall.ps1`" -BackupDir `"$BackupDir`""
    }
    foreach ($k in $values.Keys) { New-ItemProperty -Path $UninstallKey -Name $k -Value $values[$k] -PropertyType String -Force | Out-Null }
    foreach ($k in 'NoModify', 'NoRepair') { New-ItemProperty -Path $UninstallKey -Name $k -Value 1 -PropertyType DWord -Force | Out-Null }
    New-ItemProperty -Path $UninstallKey -Name EstimatedSize -Value $kb -PropertyType DWord -Force | Out-Null
    'Added to Settings > Apps > Installed apps ("Apple fonts on Windows 11"), where it can be uninstalled'
} else {
    "Not added to Installed apps (custom -BackupDir $BackupDir): uninstall with uninstall.ps1 -BackupDir"
}

# --- 9. state + font cache --------------------------------------------------------------
$state.Complete = $true
Save-State
'Font cache: stopping the service'
$svc = Start-Job { Stop-Service FontCache -Force -ErrorAction SilentlyContinue }
if (-not (Wait-Job $svc -Timeout 60)) { 'Font cache service did not stop in 60 s; the cache will rebuild at restart anyway' }
Remove-Job $svc -Force
Remove-Item "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache\*FontCache*" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:WINDIR\System32\FNTCACHE.DAT" -Force -ErrorAction SilentlyContinue
'Font cache cleared'
'DONE. Restart Windows now.'

} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
