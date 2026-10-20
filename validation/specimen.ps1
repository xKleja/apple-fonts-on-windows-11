# Full specimen sheets: every Arabic letter in all 4 joining positions, lam-alef, harakat, digits,
# and all Latin letters/accents. Original Segoe UI (left) vs Apple build (right), drawn by
#   - GDI (classic Win32 apps: DrawTextW, hinted, ClearType-style grayscale)
#   - WPF (DirectWrite-style shaping)
# Nothing is installed: Apple fonts are loaded privately from the renamed copies render_all_glyphs.py made.
param([string]$RenderWork, [string]$OutDir)
Add-Type -AssemblyName PresentationCore, WindowsBase, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class GdiSheet {
  [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern int AddFontResourceEx(string f, uint fl, IntPtr r);
  [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateFontW(int h,int w,int e,int o,int wt,uint i,uint u,uint s,uint cs,uint op,uint cp,uint q,uint pf,string face);
  [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr h, IntPtr o);
  [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr o);
  [DllImport("gdi32.dll")] static extern int SetBkMode(IntPtr h, int m);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int DrawTextW(IntPtr h, string s, int n, ref RECT r, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  // Draw one text line with GDI onto a device context at (x,y,w); rtl right-aligns with RTL reading order.
  public static void Line(IntPtr dc, string face, int weight, bool italic, int px, string text, int x, int y, int w, bool rtl) {
    IntPtr f = CreateFontW(-px,0,0,0,weight,(uint)(italic?1:0),0,0,1,0,0,5,0,face);
    IntPtr old = SelectObject(dc, f); SetBkMode(dc, 1);
    var r = new RECT { l = x, t = y, r = x + w, b = y + px * 2 };
    uint flags = 0x20 | 0x100; // DT_SINGLELINE | DT_NOCLIP
    if (rtl) flags |= 0x2 | 0x20000; // DT_RIGHT | DT_RTLREADING
    DrawTextW(dc, text, -1, ref r, flags);
    SelectObject(dc, old); DeleteObject(f);
  }
}
"@
$jobs = Get-Content (Join-Path $RenderWork 'jobs.json') -Raw | ConvertFrom-Json
foreach ($j in $jobs) { [void][GdiSheet]::AddFontResourceEx($j.file, 0x10, [IntPtr]::Zero) }
function AppleFace($file) {
    $fam = ($jobs | Where-Object { $_.name -eq $file }).family
    if (-not $fam) { throw "No render job for $file (run render_all_glyphs.py on the same folder first)" }
    $fam
}

$T = [char]0x640   # tatweel, forces joining forms
$letters = 'ا ب ت ث ج ح خ د ذ ر ز س ش ص ض ط ظ ع غ ف ق ك ل م ن ه و ي ء آ أ ؤ إ ئ ة ى' -split ' '
$arabic = @()
for ($i = 0; $i -lt $letters.Count; $i += 6) {
    $arabic += ($letters[$i..([Math]::Min($i + 5, $letters.Count - 1))] | ForEach-Object { "$_ $_$T $T$_$T $T$_" }) -join '   '
}
$arabic += 'لا لأ لإ لآ ـلا   بَ بُ بِ بً بٌ بٍ بّ بْ   ٠١٢٣٤٥٦٧٨٩ ۰۱۲۳۴۵۶۷۸۹ ، ؛ ؟ ٪'
$arabic += 'الإعدادات مستكشف الملفات والمفكرة مرحبًا بالعالم في نظام ويندوز'
$latin = @(
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789',
    '!"#$%&''()*+,-./:;<=>?@[\]^_`{|}~ ‘’“”–—…•€£¥©®™°±×÷',
    'ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞß àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿ',
    'ĀāĂăĄąĆćĈĉĊċČčĎďĐđĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĦħĨĩĪīĬĭĮįİıĲĳĴĵĶķĸĹĺĻļĽľĿŀŁł',
    'ŃńŅņŇňŉŊŋŌōŎŏŐőŒœŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŦŧŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽžſ'
)
$weights = @(
    @{ L = 'Light';    File = 'segoeuil.ttf'; Seg = 'Segoe UI Light';    W = 300; I = $false },
    @{ L = 'Regular';  File = 'segoeui.ttf';  Seg = 'Segoe UI';          W = 400; I = $false },
    @{ L = 'Semibold'; File = 'seguisb.ttf';  Seg = 'Segoe UI Semibold'; W = 600; I = $false },
    @{ L = 'Bold';     File = 'segoeuib.ttf'; Seg = 'Segoe UI';          W = 700; I = $false },
    @{ L = 'Italic';   File = 'segoeuii.ttf'; Seg = 'Segoe UI';          W = 400; I = $true }
)
New-Item -ItemType Directory -Force $OutDir | Out-Null
$px = 17; $lineH = 34; $colW = 1150; $pad = 20
$lines = @(@{ T = 'ARABIC: every letter isolated / initial / medial / final'; H = 1 }) + ($arabic | ForEach-Object { @{ T = $_; R = 1 } }) +
         @(@{ T = 'LATIN: letters, digits, punctuation, Latin-1, Latin Extended-A'; H = 1 }) + ($latin | ForEach-Object { @{ T = $_ } })

foreach ($w in $weights) {
    # --- GDI sheet
    $h = ($lines.Count + 2) * $lineH + 2 * $pad
    $bmp = New-Object Drawing.Bitmap (2 * $colW + 3 * $pad), $h, ([Drawing.Imaging.PixelFormat]::Format24bppRgb)   # 24-bit: ClearType works (it is disabled on alpha bitmaps)
    $g = [Drawing.Graphics]::FromImage($bmp); $g.Clear([Drawing.Color]::White); $hdc = $g.GetHdc()
    [GdiSheet]::Line($hdc, 'Segoe UI', 600, $false, 15, "GDI (classic apps)  $($w.L): original Segoe UI", $pad, 6, $colW, $false)
    [GdiSheet]::Line($hdc, 'Segoe UI', 600, $false, 15, "Apple build (SF Pro + SF Arabic)", 2 * $pad + $colW, 6, $colW, $false)
    $y = $pad + $lineH
    foreach ($ln in $lines) {
        if ($ln.H) {
            [GdiSheet]::Line($hdc, 'Segoe UI', 600, $false, 13, $ln.T, $pad, $y + 6, $colW, $false)
        } else {
            [GdiSheet]::Line($hdc, $w.Seg, $w.W, $w.I, $px, $ln.T, $pad, $y, $colW, [bool]$ln.R)
            [GdiSheet]::Line($hdc, (AppleFace $w.File), $w.W, $w.I, $px, $ln.T, 2 * $pad + $colW, $y, $colW, [bool]$ln.R)
        }
        $y += $lineH
    }
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save((Join-Path $OutDir "gdi-$($w.L).png")); $bmp.Dispose()

    # --- WPF sheet
    $dv = New-Object Windows.Media.DrawingVisual; $dc = $dv.RenderOpen()
    $dc.DrawRectangle([Windows.Media.Brushes]::White, $null, [Windows.Rect]::new(0, 0, 2 * $colW + 3 * $pad, $h))
    $style = if ($w.I) { [Windows.FontStyles]::Italic } else { [Windows.FontStyles]::Normal }
    $weight = [Windows.FontWeight]::FromOpenTypeWeight($w.W)
    $segFam = [Windows.Media.FontFamily]::new([Uri]"file:///$($env:WINDIR -replace '\\','/')/Fonts/$($w.File)", './#Segoe UI')
    $appFile = ($jobs | Where-Object { $_.name -eq $w.File }).file
    $appFam = [Windows.Media.FontFamily]::new([Uri]"file:///$($appFile -replace '\\','/')", "./#$(AppleFace $w.File)")
    $lbl = [Windows.Media.Typeface]::new('Segoe UI')
    function T($s, $tf, $size, $x, $y, $rtl) {
        $ft = [Windows.Media.FormattedText]::new($s, [Globalization.CultureInfo]::InvariantCulture,
            $(if ($rtl) { 'RightToLeft' } else { 'LeftToRight' }), $tf, $size, [Windows.Media.Brushes]::Black, 1.0)
        if ($rtl) { $x = $x + $colW }
        $dc.DrawText($ft, [Windows.Point]::new($x, $y))
    }
    T "WPF / DirectWrite  $($w.L): original Segoe UI" $lbl 15 $pad 6 $false
    T 'Apple build (SF Pro + SF Arabic)' $lbl 15 (2 * $pad + $colW) 6 $false
    $tfS = [Windows.Media.Typeface]::new($segFam, $style, $weight, [Windows.FontStretches]::Normal)
    $tfA = [Windows.Media.Typeface]::new($appFam, $style, $weight, [Windows.FontStretches]::Normal)
    $y = $pad + $lineH
    foreach ($ln in $lines) {
        if ($ln.H) { T $ln.T $lbl 13 $pad ($y + 6) $false }
        else { T $ln.T $tfS $px $pad $y ([bool]$ln.R); T $ln.T $tfA $px (2 * $pad + $colW) $y ([bool]$ln.R) }
        $y += $lineH
    }
    $dc.Close()
    $rtb = [Windows.Media.Imaging.RenderTargetBitmap]::new(2 * $colW + 3 * $pad, $h, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv)
    $enc = [Windows.Media.Imaging.PngBitmapEncoder]::new(); $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create((Join-Path $OutDir "wpf-$($w.L).png")); $enc.Save($fs); $fs.Close()
    "sheet $($w.L) done"
}
