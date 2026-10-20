# Installs Apple's fonts on Windows 11 and makes Windows use them for its UI and emoji.
# Normally started by the repo's install.ps1. Run elevated. Undo with restore-macos-fonts.ps1. Restart afterwards.
#
#  1. Re-checks every file against SHA256SUMS before touching anything
#  2. Safety nets: restore point, registry exports, original emoji font, state manifest
#  3. Installs the Apple SF / New York families (new fonts only, nothing overwritten)
#  4. UI: copies SF-based "Segoe UI" / "Segoe UI Variable" as new files (SFUI-*.ttf) and points
#     Windows' existing Segoe UI registrations at them. Original Segoe files are not modified.
#  5. Emoji: Apple Color Emoji as SFUI-seguiemj.ttf; the "Segoe UI Emoji" registration points at it
#  6. Clears the font cache so the change applies cleanly on restart
#Requires -RunAsAdministrator
param(
    [string]$FontsDir = (Join-Path $PSScriptRoot '..\fonts'),   # holds SF\, ui\, emoji\ and SHA256SUMS.txt
    [string]$BackupDir,                                          # default: see backup-location.ps1
    [switch]$NoRestorePoint,
    [switch]$SkipEmoji,
    [switch]$SkipUI,
    [switch]$Resume     # continue an interrupted install from its recorded state
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'backup-location.ps1')
if (-not $BackupDir) { $BackupDir = Get-DefaultBackupDir }
$Here     = (Resolve-Path $FontsDir).Path
foreach ($need in 'SHA256SUMS.txt', 'SF', 'emoji', 'ui\SHA256SUMS.txt') {
    if (-not (Test-Path (Join-Path $Here $need))) { throw "Missing $need in $Here. Run install.ps1 (it downloads the fonts) or see fonts\README.md." }
}
$Fonts    = "$env:WINDIR\Fonts"
$RegLM    = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$RegCU    = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$Emoji    = "$Fonts\seguiemj.ttf"
$StatePath = Join-Path $BackupDir 'state.json'   # not "$State": PowerShell names are case-insensitive ($state = data)
$UIFiles  = 'segoeuil.ttf','segoeuisl.ttf','segoeui.ttf','seguisb.ttf','segoeuib.ttf','seguibl.ttf',
            'seguili.ttf','seguisli.ttf','segoeuii.ttf','seguisbi.ttf','segoeuiz.ttf','seguibli.ttf','SegUIVar.ttf'
New-Item -ItemType Directory -Force $BackupDir | Out-Null
Start-Transcript -Path (Join-Path $BackupDir "install-$(Get-Date -Format yyyyMMdd-HHmmss).log") | Out-Null

# Run a system tool with a time limit: a hang becomes a clear error instead of a stuck install.
function Invoke-Tool([string]$Exe, [string]$Arguments, [int]$TimeoutSec = 60) {
    "  > $Exe $Arguments"
    $p = Start-Process $Exe -ArgumentList $Arguments -NoNewWindow -PassThru `
        -RedirectStandardOutput "$BackupDir\tool-out.txt" -RedirectStandardError "$BackupDir\tool-err.txt"
    $null = $p.Handle   # keep the process handle, otherwise .NET cannot report ExitCode afterwards
    if (-not $p.WaitForExit($TimeoutSec * 1000)) { $p.Kill(); throw "$Exe timed out after $TimeoutSec s ($Arguments)" }
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw "$Exe failed with code $($p.ExitCode): $(Get-Content "$BackupDir\tool-err.txt" -Raw)" }
}

Add-Type -Namespace W -Name K -MemberDefinition '[DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool MoveFileEx(string a, string b, int f);'

function Test-Sums([string]$Dir) {
    foreach ($line in Get-Content (Join-Path $Dir 'SHA256SUMS.txt')) {
        $hash, $rel = $line -split '\s+', 2
        $path = Join-Path $Dir ($rel.TrimStart('*').TrimStart('.', '/') -replace '/', '\')
        if ((Get-FileHash $path -Algorithm SHA256).Hash -ne $hash.ToUpper()) { throw "Checksum mismatch: $path. Nothing was changed." }
    }
}

# --- 1. integrity -----------------------------------------------------------------------
Test-Sums $Here
if (-not $SkipUI) { Test-Sums (Join-Path $Here 'ui') }
'Checksums OK'

# --- 2. safety nets (first run only keeps the true originals) ---------------------------
$stamp = Get-Date -Format yyyyMMdd-HHmmss
# Saved after every change, so restore-macos-fonts.ps1 can undo even an interrupted install.
function Save-State { $state | ConvertTo-Json -Depth 4 | Set-Content $StatePath -Encoding UTF8 }
$resumed = $false
if (Test-Path $StatePath) {
    if (-not $Resume) { throw "Already installed (found $StatePath). Run restore-macos-fonts.ps1 first, or -Resume to finish an interrupted install." }
    $old = Get-Content $StatePath -Raw | ConvertFrom-Json
    if ($old.Complete -and ($old.EmojiReg -or $SkipEmoji)) { throw 'The install already completed; nothing to resume.' }
    $state = [ordered]@{ Installed = $old.Installed; Complete = $false; SFFonts = @($old.SFFonts); UI = @($old.UI)
                         HKCU = @($old.HKCU); Emoji = [bool]$old.Emoji; EmojiAside = $old.EmojiAside; EmojiPending = $old.EmojiPending; EmojiReg = $old.EmojiReg }
    $resumed = $true
    "Resuming: $($state.SFFonts.Count) SF fonts, $($state.UI.Count) UI fonts, emoji=$([bool]$state.EmojiReg) already done"
} else {
    if (-not $NoRestorePoint) {
        try { Checkpoint-Computer -Description 'Before macOS fonts' -RestorePointType MODIFY_SETTINGS -WarningAction Stop; 'Restore point created' }
        catch { "Restore point not created now: $($_.Exception.Message)" }
    }
    # via cmd: a missing per-user key must not abort the install (PowerShell 5.1 turns native stderr into errors)
    cmd /c "reg export `"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`" `"$BackupDir\HKLM-Fonts-$stamp.reg`" /y >nul 2>&1"
    if (-not (Test-Path "$BackupDir\HKLM-Fonts-$stamp.reg")) { throw 'Could not export the font registry; nothing was changed.' }
    cmd /c "reg export `"HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`" `"$BackupDir\HKCU-Fonts-$stamp.reg`" /y >nul 2>&1"
    $state = [ordered]@{ Installed = (Get-Date).ToString('s'); Complete = $false; SFFonts = @(); UI = @(); HKCU = @(); Emoji = $false }
    Save-State
}

# --- 3. Apple SF / New York families ----------------------------------------------------
Add-Type -AssemblyName PresentationCore
$en = [Globalization.CultureInfo]'en-US'
$done = @($state.SFFonts | ForEach-Object { $_.File })
foreach ($f in Get-ChildItem (Join-Path $Here 'SF') -Recurse -File -Include *.ttf, *.otf) {
    if ($done -contains $f.Name) { continue }   # resumed: already installed
    $gt   = [Windows.Media.GlyphTypeface]::new([Uri]$f.FullName)
    $kind = if ($f.Extension -eq '.otf') { 'OpenType' } else { 'TrueType' }
    $name = "$($gt.Win32FamilyNames[$en]) $($gt.Win32FaceNames[$en]) ($kind)".Trim()
    if (Test-Path (Join-Path $Fonts $f.Name)) { throw "Refusing to overwrite existing $($f.Name)" }
    Copy-Item $f.FullName (Join-Path $Fonts $f.Name)
    New-ItemProperty -Path $RegLM -Name $name -Value $f.Name -PropertyType String -Force | Out-Null
    $state.SFFonts += @{ File = $f.Name; Registry = $name }
    Save-State
}
"Installed $($state.SFFonts.Count) SF / New York fonts"

# --- 4. UI fonts: repoint Segoe UI + Segoe UI Variable registrations --------------------
if (-not $SkipUI) {
    $lm = (Get-ItemProperty $RegLM).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
    $doneUI = @($state.UI | ForEach-Object { $_.New })
    foreach ($file in $UIFiles) {
        if ($doneUI -contains "SFUI-$file") { continue }   # resumed: already repointed
        $entry = $lm | Where-Object { $_.Value -ieq $file }
        if (-not $entry) { throw "No registry entry found for $file" }
        $new = "SFUI-$file"
        Copy-Item (Join-Path $Here "ui\$file") (Join-Path $Fonts $new) -Force
        Set-ItemProperty -Path $RegLM -Name $entry.Name -Value $new
        $state.UI += @{ Registry = $entry.Name; Original = $entry.Value; New = $new }
        Save-State
    }
    # A per-user copy of the same family would win over the system one: unregister it (file kept).
    if (Test-Path $RegCU) {
        $cu = (Get-ItemProperty $RegCU).PSObject.Properties | Where-Object { $_.Name -match '^Segoe UI( Variable)?( (Light|Semilight|Semibold|Bold|Black|Italic))* \(TrueType\)$' }
        foreach ($e in $cu) {
            $state.HKCU += @{ Registry = $e.Name; Value = $e.Value }
            Save-State
            Remove-ItemProperty -Path $RegCU -Name $e.Name
        }
    }
    "UI fonts: $($state.UI.Count) Segoe registrations now point at SF; $($state.HKCU.Count) per-user override(s) unregistered"
}

# --- 5. emoji ---------------------------------------------------------------------------
# Same method as the UI fonts: the Apple build goes in as a new file and the "Segoe UI Emoji"
# registration points at it. seguiemj.ttf itself (Windows-protected, always in use) is never touched.
if (-not $SkipEmoji -and -not $state.EmojiReg) {
    # An earlier version of this script scheduled a boot-time file swap; Windows refused it. Clean that up.
    if ($state.EmojiPending) {
        $SessionMgr = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
        $ops = @((Get-ItemProperty $SessionMgr -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
        $keep = @(); for ($i = 0; $i + 1 -lt $ops.Count; $i += 2) {
            if ($ops[$i] -notlike '*seguiemj.ttf.apple-pending') { $keep += $ops[$i], $ops[$i + 1] }
        }
        if ($ops.Count -ne $keep.Count) {
            if ($keep.Count) { Set-ItemProperty $SessionMgr -Name PendingFileRenameOperations -Value ([string[]]$keep) -Type MultiString }
            else { Remove-ItemProperty $SessionMgr -Name PendingFileRenameOperations -ErrorAction SilentlyContinue }
        }
        if (Test-Path $state.EmojiPending) { Remove-Item $state.EmojiPending -Force }
        $state.EmojiPending = $null
        $state.Emoji = $false
        Save-State
        'Emoji: removed the old boot-time swap'
    }
    $entry = (Get-ItemProperty $RegLM).PSObject.Properties | Where-Object { $_.Value -ieq 'seguiemj.ttf' }
    if (-not $entry) { throw 'No registry entry found for seguiemj.ttf' }
    Copy-Item (Join-Path $Here 'emoji\AppleColorEmoji-Windows.ttf') "$Fonts\SFUI-seguiemj.ttf" -Force
    Set-ItemProperty -Path $RegLM -Name $entry.Name -Value 'SFUI-seguiemj.ttf'
    $state.EmojiReg = @{ Registry = $entry.Name; Original = $entry.Value; New = 'SFUI-seguiemj.ttf' }
    Save-State
    'Emoji: "Segoe UI Emoji" now points at Apple Color Emoji'
}

# --- 6. state + font cache --------------------------------------------------------------
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
Stop-Transcript | Out-Null
