# Windows Sandbox rehearsal driver. Runs the real install + restore scripts and records evidence.
# Phases (state survives the in-sandbox restarts):
#   0-before    capture baseline           -> install -> restart
#   1-installed capture with Apple fonts   -> restore -> restart
#   2-restored  capture after undo         -> done
$ErrorActionPreference = 'Continue'
$Src     = 'C:\src'          # the repo, mapped read-only by start-rehearsal.ps1
$Out     = 'C:\results'      # mapped back to the host
$Phase   = 'C:\rehearsal-phase.txt'
$Backup  = 'C:\FontBackup'
$Self    = 'C:\src\sandbox\rehearsal.ps1'
New-Item -ItemType Directory -Force $Out | Out-Null

function Log($m) { "$(Get-Date -Format HH:mm:ss) $m" | Tee-Object -FilePath "$Out\rehearsal.log" -Append }

Add-Type -AssemblyName System.Drawing, System.Windows.Forms, PresentationCore
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class U {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
  [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr CreateFontW(int h,int w,int e,int o,int wt,uint i,uint u,uint s,uint cs,uint op,uint cp,uint q,uint pf,string face);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr h);
  [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr h, IntPtr o);
  [DllImport("gdi32.dll")] public static extern uint GetFontData(IntPtr h, uint table, uint off, byte[] buf, uint len);
}
"@
[void][U]::SetProcessDPIAware()

function Key([byte]$vk) { [U]::keybd_event($vk,0,0,[UIntPtr]::Zero); [U]::keybd_event($vk,0,2,[UIntPtr]::Zero) }

function Shot($name) {
    Start-Sleep -Seconds 3
    $b = [Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
    $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size)
    $bmp.Save("$script:dir\$name.png"); $g.Dispose(); $bmp.Dispose()
}

# Which font file / version does Windows actually hand out for each UI face?
function FontReport {
    $rows = @()
    foreach ($fam in 'Segoe UI', 'Segoe UI Variable', 'Segoe UI Variable Text', 'Segoe UI Variable Display', 'Segoe UI Emoji') {
        foreach ($w in 'Normal', 'Bold') {
            $tf = [Windows.Media.Typeface]::new([Windows.Media.FontFamily]::new($fam), [Windows.FontStyles]::Normal,
                  [Windows.FontWeights]::$w, [Windows.FontStretches]::Normal)
            $gt = $null; $ok = $tf.TryGetGlyphTypeface([ref]$gt)
            $rows += [pscustomobject]@{ API = 'DirectWrite/WPF'; Family = $fam; Weight = $w
                File = if ($ok) { Split-Path $gt.FontUri.LocalPath -Leaf } else { '(not found)' }
                Version = if ($ok) { $gt.VersionStrings[[Globalization.CultureInfo]'en-US'] } else { '' } }
        }
    }
    $dc = [U]::CreateCompatibleDC([IntPtr]::Zero)
    foreach ($fam in 'Segoe UI', 'Segoe UI Variable') {
        foreach ($wt in 400, 700) {
            $hf = [U]::CreateFontW(-16,0,0,0,$wt,0,0,0,1,0,0,5,0,$fam); [void][U]::SelectObject($dc, $hf)
            $size = [U]::GetFontData($dc, 0, 0, $null, 0)
            $rows += [pscustomobject]@{ API = 'GDI'; Family = $fam; Weight = $wt; File = "font data $([math]::Round($size/1MB,1)) MB"; Version = '' }
        }
    }
    $rows | Format-Table -AutoSize | Out-String -Width 250 | Set-Content "$script:dir\font-report.txt"
    $rows | Format-Table -AutoSize | Out-String -Width 250 | ForEach-Object { Log $_ }
}

function Capture($phase) {
    $script:dir = Join-Path $Out $phase; New-Item -ItemType Directory -Force $script:dir | Out-Null
    Log "=== capture $phase"
    FontReport
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' | Out-String -Width 250 |
        Select-String 'Segoe UI' | Out-String | Set-Content "$script:dir\registry.txt"

    Shot '01-desktop'
    Key 0x5B; Shot '02-start-menu'; Key 0x1B; Start-Sleep 1
    $p = Start-Process 'ms-settings:' -PassThru; Start-Sleep 6; Shot '03-settings'
    Get-Process SystemSettings -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Process explorer.exe 'C:\Windows'; Start-Sleep 4; Shot '04-explorer'
    (New-Object -ComObject Shell.Application).Windows() | ForEach-Object { $_.Quit() }
    Start-Process control.exe 'sysdm.cpl'; Start-Sleep 4; Shot '05-classic-dialog'
    Get-Process rundll32 -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Process 'msedge.exe' "--no-first-run --inprivate file:///C:/src/sandbox/test-page.html"; Start-Sleep 10; Shot '06-edge-test-page'
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Process notepad.exe 'C:\src\sandbox\sample.txt'; Start-Sleep 4; Shot '07-notepad'
    Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
}

function NextAfterRestart($phase) {
    Set-Content $Phase $phase
    New-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name Rehearsal -Force `
        -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Self" | Out-Null
    Log "restarting into phase $phase"
    shutdown.exe /r /t 3
}

$current = if (Test-Path $Phase) { Get-Content $Phase } else { '0-before' }
# Both the sandbox LogonCommand and RunOnce may start this after a restart: run each phase once.
try { New-Item -ItemType File "C:\rehearsal-lock-$current" -ErrorAction Stop | Out-Null }
catch { exit 0 }
Log "phase: $current"
switch ($current) {
    '0-before' {
        Start-Sleep 20   # let the shell finish starting
        Capture '0-before'
        Log '=== install'
        & "$Src\scripts\install-macos-fonts.ps1" -FontsDir "$Src\fonts" -BackupDir $Backup -NoRestorePoint *>&1 | ForEach-Object { Log $_ }
        NextAfterRestart '1-installed'
    }
    '1-installed' {
        Start-Sleep 20
        Capture '1-installed'
        Log '=== restore'
        & "$Src\scripts\restore-macos-fonts.ps1" -BackupDir $Backup *>&1 | ForEach-Object { Log $_ }
        NextAfterRestart '2-restored'
    }
    '2-restored' {
        Start-Sleep 20
        Capture '2-restored'
        Set-Content $Phase 'done'
        Log '=== REHEARSAL COMPLETE'
    }
}
