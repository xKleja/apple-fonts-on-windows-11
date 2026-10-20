<#
.SYNOPSIS
    Read-only health check: which font file Windows actually uses for each UI family right now,
    whether the installed files still match the verified builds, and what the install recorded.
    No admin rights needed. Run it after Windows feature updates. Exit code 0 = everything in place.
.EXAMPLE
    .\status.ps1
.EXAMPLE
    .\status.ps1 -BackupDir D:\FontBackup     # if the install used -BackupDir
#>
param([string]$BackupDir)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\backup-location.ps1')
if (-not $BackupDir) { $BackupDir = Get-DefaultBackupDir }
Add-Type -AssemblyName PresentationCore
$en    = [Globalization.CultureInfo]'en-US'
$Fonts = "$env:WINDIR\Fonts"
$ok    = $true

# What was installed decides what is expected (-SkipUI / -SkipEmoji installs are not "broken").
$statePath = Join-Path $BackupDir 'state.json'
$s = $null
if (Test-Path -LiteralPath $statePath) {
    try { $s = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $s = $null }
}
$hasUI    = -not $s -or @($s.UI | Where-Object { $_ }).Count -gt 0
$hasEmoji = -not $s -or [bool]$s.EmojiReg

Write-Host "`nFont each family resolves to (DirectWrite / modern apps):" -ForegroundColor Cyan
$expect = [ordered]@{}
if ($hasUI) {
    $expect['Segoe UI'] = 'SFUI-SEGOEUI.TTF'; $expect['Segoe UI Semibold'] = 'SFUI-SEGUISB.TTF'; $expect['Segoe UI Light'] = 'SFUI-SEGOEUIL.TTF'
    $expect['Segoe UI Variable Text'] = 'SFUI-SEGUIVAR.TTF'; $expect['Segoe UI Variable Display'] = 'SFUI-SEGUIVAR.TTF'
    $expect['Segoe UI Variable Small'] = 'SFUI-SEGUIVAR.TTF'
}
if ($hasEmoji) { $expect['Segoe UI Emoji'] = 'SFUI-SEGUIEMJ.TTF' }
$expect['SF Pro'] = 'SF-PRO.TTF'
foreach ($fam in $expect.Keys) {
    $gt = $null
    $found = [Windows.Media.Typeface]::new($fam).TryGetGlyphTypeface([ref]$gt)
    $file = if ($found) { (Split-Path $gt.FontUri.LocalPath -Leaf).ToUpperInvariant() } else { '(not found)' }
    $ver = ''
    if ($found) { [void]$gt.VersionStrings.TryGetValue($en, [ref]$ver) }
    $good = $file -eq $expect[$fam]
    if (-not $good) { $ok = $false }
    "{0} {1,-27} -> {2,-20} {3}" -f $(if ($good) { '[OK]  ' } else { '[DIFF]' }), $fam, $file, $ver
}

if ($hasUI) {
    Write-Host "`nInstalled files vs verified builds:" -ForegroundColor Cyan
    $sums = Join-Path $PSScriptRoot 'fonts\ui\SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $sums)) {
        "  fonts\ui\SHA256SUMS.txt is missing from this checkout"; $ok = $false
    } else {
        $bad = 0; $n = 0
        foreach ($line in Get-Content -LiteralPath $sums) {
            if (-not $line.Trim()) { continue }
            $hash, $name = $line.Trim() -split '\s+', 2
            $name = $name.TrimStart('*').TrimStart('.', '/')
            $path = Join-Path $Fonts "SFUI-$name"
            $n++
            if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path).Hash -ine $hash) { $bad++; "  [DIFF] SFUI-$name" }
        }
        "  {0}/{1} UI font files match" -f ($n - $bad), $n
        if ($bad) { $ok = $false }
    }
}

Write-Host "`nRecorded install:" -ForegroundColor Cyan
if ($s) {
    $when = if ($s.Installed -is [datetime]) { $s.Installed.ToString('s') } else { $s.Installed }
    "  state: $statePath"
    "  installed $when; complete=$($s.Complete); SF fonts=$(@($s.SFFonts | Where-Object { $_ }).Count); UI=$(@($s.UI | Where-Object { $_ }).Count); emoji=$([bool]$s.EmojiReg)"
    if (-not $s.Complete) { "  The install did not finish: run .\install.ps1 -Resume"; $ok = $false }
} else {
    "  no install recorded (looked in $BackupDir; pass -BackupDir if the install used another folder)"
    $ok = $false
}

Write-Host ''
if ($ok) { Write-Host 'Everything is in place.' -ForegroundColor Green }
elseif (-not $s) { Write-Host 'Not installed (or installed with a different -BackupDir).' -ForegroundColor Yellow }
else { Write-Host 'Something differs. After a Windows update: run .\uninstall.ps1, restart, then .\install.ps1 and restart.' -ForegroundColor Yellow }
exit ([int](-not $ok))
