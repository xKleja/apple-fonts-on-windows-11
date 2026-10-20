# Renders original Segoe UI vs the Apple-based replacement, side by side, without installing anything.
param([string]$Built, [string]$OutPng)
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
$faces = @(
    @{ File = 'segoeuil.ttf';  W = 300; L = 'Light' },    @{ File = 'segoeuisl.ttf'; W = 350; L = 'Semilight' },
    @{ File = 'segoeui.ttf';   W = 400; L = 'Regular' },   @{ File = 'seguisb.ttf';   W = 600; L = 'Semibold' },
    @{ File = 'segoeuib.ttf';  W = 700; L = 'Bold' },     @{ File = 'seguibl.ttf';   W = 900; L = 'Black' },
    @{ File = 'segoeuii.ttf';  W = 400; L = 'Regular'; I = $true }, @{ File = 'segoeuiz.ttf'; W = 700; L = 'Bold'; I = $true }
)
$en = 'Settings  File Explorer  The quick brown fox 0123'
$ar = 'الإعدادات مستكشف الملفات مرحبًا بالعالم ٠١٢٣'
$dpi = 1.5; $rowH = 40; $colW = 760
$faces = @($faces | Where-Object { Test-Path (Join-Path $Built $_.File) })
$dv = New-Object Windows.Media.DrawingVisual
$dc = $dv.RenderOpen()
$dc.DrawRectangle([Windows.Media.Brushes]::White, $null, [Windows.Rect]::new(0, 0, 2 * $colW + 160, ($faces.Count * 2 + 2) * $rowH))
$label = [Windows.Media.Typeface]::new('Segoe UI')
function Text($s, $tf, $size, $x, $y, $rtl = $false) {
    $ft = [Windows.Media.FormattedText]::new($s, [Globalization.CultureInfo]::InvariantCulture,
        $(if ($rtl) { 'RightToLeft' } else { 'LeftToRight' }), $tf, $size, [Windows.Media.Brushes]::Black, $dpi)
    if ($rtl) { $x = $x + $colW - 20 }
    $dc.DrawText($ft, [Windows.Point]::new($x, $y))
}
Text 'Original Segoe UI' $label 16 160 8
Text 'Apple (SF Pro + SF Arabic) as Segoe UI' $label 16 (160 + $colW) 8
$y = $rowH
foreach ($f in $faces) {
    $style = if ($f.I) { [Windows.FontStyles]::Italic } else { [Windows.FontStyles]::Normal }
    $weight = [Windows.FontWeight]::FromOpenTypeWeight($f.W)
    $orig = [Windows.Media.FontFamily]::new([Uri]"file:///$($env:WINDIR -replace '\\','/')/Fonts/$($f.File)", "./#Segoe UI")
    $new  = [Windows.Media.FontFamily]::new([Uri]"file:///$($Built -replace '\\','/')/$($f.File)", "./#Segoe UI")
    $tfo = [Windows.Media.Typeface]::new($orig, $style, $weight, [Windows.FontStretches]::Normal)
    $tfn = [Windows.Media.Typeface]::new($new,  $style, $weight, [Windows.FontStretches]::Normal)
    Text "$($f.L)$(if ($f.I) {' Italic'})" $label 12 8 ($y + 6)
    Text $en $tfo 20 160 $y;          Text $en $tfn 20 (160 + $colW) $y
    Text $ar $tfo 20 160 ($y + $rowH) $true; Text $ar $tfn 20 (160 + $colW) ($y + $rowH) $true
    $y += 2 * $rowH
}
$dc.Close()
$w = [int]((2 * $colW + 160) * $dpi); $h = [int](($faces.Count * 2 + 2) * $rowH * $dpi)
$bmp = [Windows.Media.Imaging.RenderTargetBitmap]::new($w, $h, 96 * $dpi, 96 * $dpi, [Windows.Media.PixelFormats]::Pbgra32)
$bmp.Render($dv)
$enc = [Windows.Media.Imaging.PngBitmapEncoder]::new()
$enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
$fs = [IO.File]::Create($OutPng); $enc.Save($fs); $fs.Close()
"saved $OutPng"
