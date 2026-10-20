<#
.SYNOPSIS
    Read-only health check: which font file Windows actually uses for each UI family right now,
    whether the installed files still match the verified builds, and what the install recorded.
    No admin rights needed. Run it after Windows feature updates.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\backup-location.ps1')
Add-Type -AssemblyName PresentationCore
$en    = [Globalization.CultureInfo]'en-US'
$Fonts = "$env:WINDIR\Fonts"
$ok    = $true

Write-Host "`nFont each family resolves to (DirectWrite / modern apps):" -ForegroundColor Cyan
$expect = [ordered]@{
    'Segoe UI' = 'SFUI-SEGOEUI.TTF'; 'Segoe UI Semibold' = 'SFUI-SEGUISB.TTF'; 'Segoe UI Light' = 'SFUI-SEGOEUIL.TTF'
    'Segoe UI Variable Text' = 'SFUI-SEGUIVAR.TTF'; 'Segoe UI Variable Display' = 'SFUI-SEGUIVAR.TTF'
    'Segoe UI Variable Small' = 'SFUI-SEGUIVAR.TTF'; 'Segoe UI Emoji' = 'SFUI-SEGUIEMJ.TTF'; 'SF Pro' = 'SF-PRO.TTF'
}
foreach ($fam in $expect.Keys) {
    $gt = $null
    $found = [Windows.Media.Typeface]::new($fam).TryGetGlyphTypeface([ref]$gt)
    $file = if ($found) { (Split-Path $gt.FontUri.LocalPath -Leaf).ToUpper() } else { '(not found)' }
    $good = $file -eq $expect[$fam]
    if (-not $good) { $ok = $false }
    "{0} {1,-27} -> {2,-20} {3}" -f $(if ($good) { '[OK]  ' } else { '[DIFF]' }), $fam, $file, $(if ($found) { $gt.VersionStrings[$en] })
}

Write-Host "`nInstalled files vs verified builds:" -ForegroundColor Cyan
$sums = Join-Path $PSScriptRoot 'fonts\ui\SHA256SUMS.txt'
$bad = 0; $n = 0
foreach ($line in Get-Content $sums) {
    $hash, $name = $line -split '\s+', 2
    $name = $name.TrimStart('*').TrimStart('.', '/')
    $path = Join-Path $Fonts "SFUI-$name"
    $n++
    if (-not (Test-Path $path) -or (Get-FileHash $path).Hash -ne $hash.ToUpper()) { $bad++; "  [DIFF] SFUI-$name" }
}
"  {0}/{1} UI font files match" -f ($n - $bad), $n
if ($bad) { $ok = $false }

Write-Host "`nRecorded install:" -ForegroundColor Cyan
$dir = Get-DefaultBackupDir
$state = Join-Path $dir 'state.json'
if (Test-Path $state) {
    $s = Get-Content $state -Raw | ConvertFrom-Json
    "  state: $state"
    "  installed $($s.Installed); complete=$($s.Complete); SF fonts=$(@($s.SFFonts).Count); UI=$(@($s.UI).Count); emoji=$([bool]$s.EmojiReg)"
} else {
    "  no install recorded (looked in $dir)"
    $ok = $false
}

Write-Host ''
if ($ok) { Write-Host 'Everything is in place.' -ForegroundColor Green }
else { Write-Host 'Something differs. After a Windows update, run .\install.ps1 -Resume (or uninstall + install).' -ForegroundColor Yellow }
