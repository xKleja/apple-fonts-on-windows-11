# Load each font with Windows' own parsers without installing it:
#  - GDI: AddFontResourceEx(FR_PRIVATE), the same font driver used for installed fonts
#  - WPF GlyphTypeface: Windows' managed OpenType loader (names, cmap, glyph outlines)
param([string]$Root)
Add-Type -AssemblyName PresentationCore
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Gdi {
  [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern int AddFontResourceEx(string f, uint fl, IntPtr r);
  [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern bool RemoveFontResourceEx(string f, uint fl, IntPtr r);
}
"@
$FR_PRIVATE = 0x10
$ok = 0; $bad = @()
foreach ($f in Get-ChildItem $Root -Recurse -File -Include *.ttf, *.otf) {
    try {
        $n = [Gdi]::AddFontResourceEx($f.FullName, $FR_PRIVATE, [IntPtr]::Zero)
        if ($n -lt 1) { throw "GDI rejected the font" }
        [void][Gdi]::RemoveFontResourceEx($f.FullName, $FR_PRIVATE, [IntPtr]::Zero)
        $gt = [Windows.Media.GlyphTypeface]::new([Uri]$f.FullName)
        $fam = $gt.Win32FamilyNames[[Globalization.CultureInfo]'en-US']
        if (-not $fam) { throw "no family name" }
        foreach ($cp in 0x41, 0x645, 0x5D0) {   # A, Arabic meem, Hebrew alef
            $gi = 0
            if ($gt.CharacterToGlyphMap.TryGetValue($cp, [ref]$gi)) { [void]$gt.GetGlyphOutline($gi, 32, 32) }
        }
        "{0,-16} OK  family='{1}' face='{2}' glyphs={3}" -f $f.Name, $fam, $gt.Win32FaceNames[[Globalization.CultureInfo]'en-US'], $gt.GlyphCount
        $ok++
    } catch {
        $bad += "$($f.Name): $($_.Exception.Message)"
    }
}
"Windows-loaded OK: $ok   failed: $($bad.Count)"
$bad
