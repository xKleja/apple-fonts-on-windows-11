# Worker for render_all_glyphs.py: draws every glyph index with GDI (3 sizes) and WPF,
# writes the glyph indices that produced no ink.
param([string]$JobsJson, [string]$OutJson)
Add-Type -AssemblyName PresentationCore
Add-Type @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class GdiInk {
  [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] static extern int AddFontResourceEx(string f, uint fl, IntPtr r);
  [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] static extern bool RemoveFontResourceEx(string f, uint fl, IntPtr r);
  [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateFontW(int h,int w,int e,int o,int wt,uint i,uint u,uint s,uint cs,uint op,uint cp,uint q,uint pf,string face);
  [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr h);
  [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr h, IntPtr o);
  [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr o);
  [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] struct GM { public uint bx, by; public int ox, oy; public short cx, cy; }
  [StructLayout(LayoutKind.Sequential)] struct MAT2 { public int m11, m12, m21, m22; }
  [DllImport("gdi32.dll")] static extern uint GetGlyphOutlineW(IntPtr h, uint ch, uint fmt, out GM gm, uint cb, byte[] buf, ref MAT2 m);
  [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] static extern int GetTextFaceW(IntPtr h, int c, System.Text.StringBuilder s);
  const uint GGO_GRAY8_BITMAP = 6, GGO_GLYPH_INDEX = 0x80;
  public static List<int> Blank(string file, string face, int glyphs, int px, out string gotFace) {
    var res = new List<int>();
    AddFontResourceEx(file, 0x10, IntPtr.Zero);
    IntPtr dc = CreateCompatibleDC(IntPtr.Zero);
    IntPtr hf = CreateFontW(-px,0,0,0,400,0,0,0,1,0,0,4,0,face);
    SelectObject(dc, hf);
    var sb = new System.Text.StringBuilder(64); GetTextFaceW(dc, 64, sb); gotFace = sb.ToString();
    var m = new MAT2 { m11 = 0x10000, m22 = 0x10000 };
    for (int g = 0; g < glyphs; g++) {
      GM gm; uint size = GetGlyphOutlineW(dc, (uint)g, GGO_GRAY8_BITMAP | GGO_GLYPH_INDEX, out gm, 0, null, ref m);
      bool ink = false;
      if (size != 0 && size != 0xFFFFFFFF) {
        var buf = new byte[size];
        GetGlyphOutlineW(dc, (uint)g, GGO_GRAY8_BITMAP | GGO_GLYPH_INDEX, out gm, size, buf, ref m);
        foreach (var b in buf) if (b != 0) { ink = true; break; }
      }
      if (!ink) res.Add(g);
    }
    DeleteObject(hf); DeleteDC(dc);
    RemoveFontResourceEx(file, 0x10, IntPtr.Zero);
    return res;
  }
}
"@
$jobs = Get-Content $JobsJson -Raw | ConvertFrom-Json
$out = @{}
foreach ($j in $jobs) {
    $r = [ordered]@{}
    foreach ($px in 12, 16, 20) {
        $face = ''
        $r["GDI ${px}px"] = [GdiInk]::Blank($j.file, $j.family, $j.glyphs, $px, [ref]$face).ToArray()
        if ($face -ne $j.family) { throw "GDI used '$face' instead of '$($j.family)' for $($j.name)" }
    }
    $gt = [Windows.Media.GlyphTypeface]::new([Uri]$j.file)
    $wpf = New-Object System.Collections.Generic.List[int]
    for ($g = 0; $g -lt $gt.GlyphCount; $g++) {
        $geo = $gt.GetGlyphOutline([uint16]$g, 64, 64)
        if ($geo.IsEmpty() -or $geo.GetArea() -le 0) { $wpf.Add($g) }
    }
    $r['WPF outline'] = $wpf.ToArray()
    $out[$j.family] = $r
    Write-Host "rendered $($j.name)"
}
$out | ConvertTo-Json -Depth 4 -Compress | Set-Content $OutJson
