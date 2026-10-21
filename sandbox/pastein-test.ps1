# Windows Sandbox (with networking): functional test of the paste-in install, get.ps1.
# Started by start-rehearsal.ps1 -Mode PasteIn. Runs the README's paste-in lines the way a user would and
# checks the downloaded copy, the install, and the output after every step:
#   A. pasted into Windows PowerShell, with a profile folder named with spaces, parentheses and &
#   B. pasted again: reuses the copy, reports "Already installed"; then Uninstall.cmd from the copy
#   C. the Command Prompt / Win+R line, over a damaged earlier copy (set aside, not deleted); uninstall
#   D. pasted into PowerShell 7 (portable, downloaded for the test); uninstall
#   E. a download that fails: clear message, nothing changed, nothing left behind
# Without -Release it tests ..\get.ps1 from this checkout, pointed at the latest published release (its
# own release does not exist yet). With -Release it runs the real line: irm .../releases/latest/... | iex
# Writes C:\results\pastein-test.log and ends with "PASTE-IN TEST PASSED" or "PASTE-IN TEST FAILED".
param([switch]$Release)
$ErrorActionPreference = 'Stop'
$Src   = 'C:\src'
$Out   = 'C:\results'
$Log   = "$Out\pastein-test.log"
$RegLM = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$Url   = 'https://github.com/xKleja/apple-fonts-on-windows-11/releases/latest/download/get.ps1'
New-Item -ItemType Directory -Force $Out | Out-Null
$script:fails = 0

function Log($m) { "$(Get-Date -Format HH:mm:ss) $m" | Tee-Object -FilePath $Log -Append | Out-Null }
function Check([bool]$ok, [string]$what) { if ($ok) { Log "  PASS $what" } else { $script:fails++; Log "  FAIL $what" } }
function Segoe { (Get-ItemProperty $RegLM).'Segoe UI (TrueType)' }

# Run a line through cmd.exe exactly as typed in Command Prompt, stdin empty (no prompts), 20 minutes
# at most. Returns the output as one string and logs it; the exit code goes to $script:lastExit.
function Run-Line([string]$line) {
    $nul = "$env:TEMP\empty.txt"; Set-Content $nul '' -NoNewline
    $p = Start-Process "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/d /c `"$line`"" -PassThru -NoNewWindow `
        -RedirectStandardInput $nul -RedirectStandardOutput "$env:TEMP\line-out.txt" -RedirectStandardError "$env:TEMP\line-err.txt"
    $null = $p.Handle   # without it, ExitCode stays empty on Windows PowerShell
    if (-not $p.WaitForExit(1200000)) { $p.Kill(); Log '    | (timed out after 20 minutes)' }
    $script:lastExit = $p.ExitCode
    $text = (Get-Content "$env:TEMP\line-out.txt", "$env:TEMP\line-err.txt" -ErrorAction SilentlyContinue) -join "`n"
    $text -split "`n" | ForEach-Object { Log "    | $_" }
    $text
}

function Copy-Dir([string]$localAppData, [string]$tag) {
    Join-Path $localAppData "AppleFontsOnWindows\apple-fonts-on-windows-11-$($tag.Substring(1))"
}

function Assert-PastedInstall([string]$text, [string]$dir, [string]$label) {
    Log "== verify: $label"
    Check ($text -match 'Apple fonts on Windows 11') 'loader header shown'
    Check (Test-Path -LiteralPath (Join-Path $dir 'Install.cmd')) "copy unpacked to $dir"
    Check ((Segoe) -eq 'SFUI-segoeui.ttf') "Segoe UI -> SFUI-segoeui.ttf ($(Segoe))"
    Check ($text -match 'Check it any time with Status\.cmd') 'loader reports success with where to check and undo'
    Check ($text -notmatch 'CANNOT INSTALL') 'no CANNOT INSTALL'
    Check (-not (Get-ChildItem -LiteralPath (Split-Path $dir) -Filter 'download-*' -ErrorAction SilentlyContinue)) 'no download-* folder left behind'
    $null = Run-Line "`"$dir\Status.cmd`""
    Check ($script:lastExit -eq 0) "Status.cmd from the copy: all in place (exit $script:lastExit)"
}

function Uninstall-From([string]$dir) {
    Log "== uninstall with $dir\Uninstall.cmd"
    $null = Run-Line "`"$dir\Uninstall.cmd`""
    Check ((Segoe) -eq 'segoeui.ttf') "Segoe UI back to segoeui.ttf ($(Segoe))"
}

try {
    Log "=== paste-in test, $(if ($Release) { 'the published release' } else { 'get.ps1 from this checkout' })"
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $req = [Net.HttpWebRequest]::Create('https://github.com/xKleja/apple-fonts-on-windows-11/releases/latest')
    $req.AllowAutoRedirect = $false; $req.Method = 'HEAD'
    $resp = $req.GetResponse(); $latest = ($resp.Headers['Location'] -split '/')[-1]; $resp.Close()
    Log "latest published release: $latest"

    $loader = "$Out\get-under-test.ps1"
    if ($Release) {
        $text = (New-Object Net.WebClient).DownloadString($Url)
        $tag = [regex]::Match($text, "\`$Tag  = '(v[0-9.]+)'").Groups[1].Value
        Check ($tag -eq $latest) "the latest release's get.ps1 names that release ($tag)"
        $paste = "irm $Url | iex"
    } else {
        $text = Get-Content -LiteralPath "$Src\get.ps1" -Raw
        $own = [regex]::Match($text, "\`$Tag  = '(v[0-9.]+)'").Groups[1].Value
        $tag = $latest
        $text = $text.Replace("`$Tag  = '$own'", "`$Tag  = '$tag'")
        Log "testing get.ps1 for $own, pointed at $tag"
        $paste = "Get-Content -Raw -LiteralPath '$loader' | iex"
    }
    Set-Content -LiteralPath $loader $text -Encoding ASCII
    $before = Segoe
    Check ($before -eq 'segoeui.ttf') "starts with stock Segoe UI ($before)"

    # A. Windows PowerShell, profile folder with spaces, parentheses and &
    $odd = 'C:\Users\Public\Test (A&B) x\AppData\Local'
    New-Item -ItemType Directory -Force -Path $odd | Out-Null
    $realLocal = $env:LOCALAPPDATA
    Log "=== A. pasted into Windows PowerShell, LOCALAPPDATA = $odd"
    $env:LOCALAPPDATA = $odd
    $outA = Run-Line "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command `"$paste`""
    $dirA = Copy-Dir $odd $tag
    Assert-PastedInstall $outA $dirA 'A'

    Log '=== B. pasted again'
    $outB = Run-Line "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command `"$paste`""
    Check ($outB -match 'Using the copy downloaded before') 'reuses the copy'
    Check ($outB -match 'Already installed') 'installer says Already installed'
    Check ($outB -notmatch 'Check it any time') 'no success line after a refusal'
    Check ($outB -match 'The installer''s files are in') 'says where the files are'
    $env:LOCALAPPDATA = $realLocal
    Uninstall-From $dirA

    # C. the Command Prompt / Win+R line over a damaged earlier copy
    $dirC = Copy-Dir $realLocal $tag
    Log "=== C. Command Prompt line, over a damaged copy in $dirC"
    New-Item -ItemType Directory -Force -Path $dirC | Out-Null
    Set-Content -LiteralPath "$dirC\Install.cmd" '@echo damaged'
    Set-Content -LiteralPath "$dirC\VERSION" '0.0.0'
    $outC = Run-Line "powershell -NoProfile -Command `"$paste`""
    Assert-PastedInstall $outC $dirC 'C'
    $aside = @(Get-ChildItem -LiteralPath (Split-Path $dirC) -Directory -Filter "$(Split-Path $dirC -Leaf).old-*")
    Check ($aside.Count -eq 1 -and (Test-Path -LiteralPath "$($aside[0].FullName)\VERSION")) 'damaged copy set aside, not deleted'
    Uninstall-From $dirC

    # D. PowerShell 7 (portable zip from the PowerShell project's releases)
    Log '=== D. pasted into PowerShell 7'
    $pwshZip = "$env:TEMP\pwsh.zip"; $pwshDir = "$env:TEMP\pwsh7"
    try {
        (New-Object Net.WebClient).DownloadFile('https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-x64.zip', $pwshZip)
        Expand-Archive -LiteralPath $pwshZip -DestinationPath $pwshDir -Force
    } catch { Log "  SKIP PowerShell 7 not available: $($_.Exception.Message)" }
    if (Test-Path "$pwshDir\pwsh.exe") {
        $outD = Run-Line "`"$pwshDir\pwsh.exe`" -NoProfile -Command `"`$PSVersionTable.PSVersion.ToString(); $paste`""
        Check ($outD -match '(?m)^7\.') 'ran in PowerShell 7'
        Check ($outD -match 'Using the copy downloaded before') 'reuses the copy from C'
        Assert-PastedInstall $outD $dirC 'D'
        Uninstall-From $dirC
    }

    # E. a download that fails
    Log '=== E. download fails'
    $bad = $text.Replace("`$Tag  = '$tag'", "`$Tag  = 'v0.0.0'")
    Set-Content -LiteralPath "$Out\get-bad.ps1" $bad -Encoding ASCII
    $outE = Run-Line "powershell -NoProfile -Command `"Get-Content -Raw -LiteralPath '$Out\get-bad.ps1' | iex`""
    Check ($outE -match 'CANNOT INSTALL: could not download the installer') 'clear download failure message'
    Check ($outE -match 'Nothing was changed') 'says nothing was changed'
    Check ((Segoe) -eq 'segoeui.ttf') 'Segoe UI untouched'
    Check (-not (Test-Path -LiteralPath (Copy-Dir $realLocal 'v0.0.0'))) 'no copy for the failed version'
    Check (-not (Get-ChildItem -LiteralPath "$realLocal\AppleFontsOnWindows" -Filter 'download-*' -ErrorAction SilentlyContinue)) 'no download-* folder left behind'
} catch {
    $script:fails++
    Log "THROWN: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)"
}
if ($script:fails -eq 0) { Log 'PASTE-IN TEST PASSED' } else { Log "PASTE-IN TEST FAILED ($script:fails failures)" }
