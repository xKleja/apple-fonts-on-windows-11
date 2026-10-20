# Render the same text with real GDI (CreateDIBSection, like a window surface) in three smoothing
# modes, for several fonts loaded privately. Used to diagnose marks that vanish in classic apps.
param([string[]]$Fonts, [string[]]$Faces, [string]$Text, [int]$Px, [int]$Weight, [string]$OutPng)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class G {
  [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern int AddFontResourceEx(string f, uint fl, IntPtr r);
  [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr CreateFontW(int h,int w,int e,int o,int wt,uint i,uint u,uint s,uint cs,uint op,uint cp,uint q,uint pf,string face);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr h);
  [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr h, IntPtr o);
  [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
  [DllImport("gdi32.dll")] public static extern int SetBkMode(IntPtr h, int m);
  [DllImport("gdi32.dll")] public static extern bool PatBlt(IntPtr h, int x, int y, int w, int hh, uint rop);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int DrawTextW(IntPtr h, string s, int n, ref RECT r, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] public struct BMIH { public int size, w, h; public short planes, bits; public int comp, img, xp, yp, used, imp; }
  [DllImport("gdi32.dll")] public static extern IntPtr CreateDIBSection(IntPtr dc, ref BMIH bi, uint usage, out IntPtr bits, IntPtr sec, uint off);
}
"@
foreach ($f in $Fonts) { [void][G]::AddFontResourceEx($f, 0x10, [IntPtr]::Zero) }
$modes = @(@{ N = 'ClearType'; Q = 5 }, @{ N = 'Antialiased'; Q = 4 }, @{ N = 'No smoothing'; Q = 3 })
$rowH = $Px * 2; $W = 1100; $H = $rowH * $modes.Count * $Faces.Count + 10
$dc = [G]::CreateCompatibleDC([IntPtr]::Zero)
$bi = New-Object G+BMIH; $bi.size = 40; $bi.w = $W; $bi.h = -$H; $bi.planes = 1; $bi.bits = 32
$bits = [IntPtr]::Zero; $dib = [G]::CreateDIBSection($dc, [ref]$bi, 0, [ref]$bits, [IntPtr]::Zero, 0)
[void][G]::SelectObject($dc, $dib); [void][G]::PatBlt($dc, 0, 0, $W, $H, 0x00FF0062)   # WHITENESS
[void][G]::SetBkMode($dc, 1)
$y = 5
foreach ($face in $Faces) {
    foreach ($m in $modes) {
        $lbl = [G]::CreateFontW(-13,0,0,0,400,0,0,0,1,0,0,5,0,'Segoe UI'); $o = [G]::SelectObject($dc, $lbl)
        $r = New-Object G+RECT; $r.l = 5; $r.t = $y + 6; $r.r = 320; $r.b = $y + $rowH
        [void][G]::DrawTextW($dc, "$face / $($m.N)", -1, [ref]$r, 0x20); [void][G]::SelectObject($dc, $o); [void][G]::DeleteObject($lbl)
        $hf = [G]::CreateFontW(-$Px,0,0,0,$Weight,0,0,0,1,0,0,$m.Q,0,$face); $o = [G]::SelectObject($dc, $hf)
        $r = New-Object G+RECT; $r.l = 330; $r.t = $y; $r.r = $W - 10; $r.b = $y + $rowH
        [void][G]::DrawTextW($dc, $Text, -1, [ref]$r, 0x20 -bor 0x2 -bor 0x20000)
        [void][G]::SelectObject($dc, $o); [void][G]::DeleteObject($hf)
        $y += $rowH
    }
}
$img = [Drawing.Image]::FromHbitmap($dib); $img.Save($OutPng); $img.Dispose()
"saved $OutPng"
