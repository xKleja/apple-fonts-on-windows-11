<#
.SYNOPSIS
    Read-only health check: which font file Windows actually uses for each UI family right now,
    whether the installed files still match the verified builds, and what the install recorded.
    No admin rights needed. Run it after Windows updates.
    Exit code: 0 = everything in place, 1 = something differs, 2 = not installed.
.EXAMPLE
    .\status.ps1
.EXAMPLE
    .\status.ps1 -BackupDir D:\FontBackup     # if the install used -BackupDir
#>
param([string]$BackupDir)
$ErrorActionPreference = 'Stop'
# Started from a PowerShell 7 window, Windows PowerShell inherits its module path and then cannot load
# its own modules (Get-FileHash, Expand-Archive, Get-Acl ... "not recognized"): use its own folders.
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $env:PSModulePath = (@([Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') -split ';') +
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules') | Where-Object { $_ }) -join ';'
}
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Host 'Windows is blocking scripts on this PC (Smart App Control, S mode or an App Control policy).' -ForegroundColor Red
    exit 1
}
. (Join-Path $PSScriptRoot 'scripts\backup-location.ps1')
$BackupDir = if ($BackupDir) { Resolve-UserPath $BackupDir } else { Get-DefaultBackupDir }
Add-Type -AssemblyName PresentationCore
$en    = [Globalization.CultureInfo]'en-US'
$Fonts = "$env:WINDIR\Fonts"
$ok    = $true

# What was installed decides what is expected (-SkipUI / -SkipEmoji installs are not "broken").
$statePath = Join-Path $BackupDir 'state.json'
$s = $null; $stateError = $null
try {
    if (Test-Path -LiteralPath $statePath) { $s = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
} catch { $stateError = $_.Exception.Message }
$hasUI    = -not $s -or @($s.UI | Where-Object { $_ }).Count -gt 0
$hasEmoji = -not $s -or [bool]$s.EmojiReg

$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$version = "$(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -TotalCount 1 -ErrorAction SilentlyContinue)".Trim()
Write-Host "Apple fonts on Windows 11 $version - status" -ForegroundColor Cyan
$product = if ([int]$cv.CurrentBuild -ge 22000) { $cv.ProductName -replace 'Windows 10', 'Windows 11' } else { $cv.ProductName }   # Windows 11 still says "Windows 10" here
"  Windows: $product $($cv.DisplayVersion), build $($cv.CurrentBuild).$($cv.UBR)"

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
    $path = if ($found) { $gt.FontUri.LocalPath } else { '' }
    $file = if ($found) { (Split-Path $path -Leaf).ToUpperInvariant() } else { '(not found)' }
    $ver = ''
    if ($found) { [void]$gt.VersionStrings.TryGetValue($en, [ref]$ver) }
    # Must be the system copy: a per-user copy of the same file name would hide a reverted system entry.
    $good = $file -eq $expect[$fam] -and (Split-Path $path) -eq $Fonts
    if ($found -and $file -eq $expect[$fam] -and -not $good) { $file = $path }
    if (-not $good) { $ok = $false }
    "{0} {1,-27} -> {2,-20} {3}" -f $(if ($good) { '[OK]  ' } else { '[DIFF]' }), $fam, $file, $ver
}

if ($hasUI) {
    Write-Host "`nInstalled files vs verified builds:" -ForegroundColor Cyan
    $sums = Join-Path $PSScriptRoot 'fonts\ui\SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $sums)) {
        "  fonts\ui\SHA256SUMS.txt is missing from this folder (download the project again)"; $ok = $false
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

$fontsOk = $ok
Write-Host "`nRecorded install:" -ForegroundColor Cyan
"  folder: $BackupDir"
$installed = $true
if ($s) {
    $when = if ($s.Installed -is [datetime]) { $s.Installed.ToString('s') } else { $s.Installed }
    # 1.2.0 on Windows PowerShell saved the version as an object: { "value": "1.2.0", "PSPath": ... }
    $installedVersion = if ($s.Version.value) { $s.Version.value } elseif ($s.Version) { $s.Version } else { 'before 1.2' }
    "  installed $when (version $installedVersion); complete=$($s.Complete); SF fonts=$(@($s.SFFonts | Where-Object { $_ }).Count); UI=$(@($s.UI | Where-Object { $_ }).Count); emoji=$([bool]$s.EmojiReg)"
    "  Installed apps entry: $(if (Test-Path $UninstallKey) { 'yes' } else { 'no' })"
    if (-not $s.Complete) { "  The install did not finish: run Install.cmd again to finish it, or uninstall to undo it."; $ok = $false }
} elseif ($stateError) {
    "  cannot read the install record ($stateError). Installs made before version 1.2 keep it readable by"
    "  administrators only: run this as administrator to see it."
} else {
    "  no install recorded"
    $installed = $false
    $ok = $false
}

Write-Host ''
if ($ok) { Write-Host 'Everything is in place.' -ForegroundColor Green; exit 0 }
if (-not $installed) {
    if ($fontsOk) { Write-Host "The fonts are in place, but no install record was found in $BackupDir. If the install used -BackupDir, pass the same -BackupDir." -ForegroundColor Yellow }
    else { Write-Host 'Not installed (or installed with a different -BackupDir).' -ForegroundColor Yellow }
    exit 2
}
Write-Host 'Something differs (Windows updates can undo part of the change). To fix it: uninstall (Settings > Apps > Installed apps),' -ForegroundColor Yellow
Write-Host 'restart, then double-click Install.cmd and restart again.' -ForegroundColor Yellow
exit 1
