"""Diagnose Arabic shaping: built Segoe UI replacement vs Apple's untouched SF Arabic instance.

Shapes a sample sentence with both and prints every glyph whose name, outline ink or advance differs.
Usage: diag_arabic.py <built ui dir> <Apple SF dir>      (e.g. fonts/ui fonts/SF)
"""
import os
import sys
import tempfile

import uharfbuzz as hb
from fontTools.pens.areaPen import AreaPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

if len(sys.argv) != 3:
    sys.exit(__doc__)
AR = f"{sys.argv[2]}/SF Multilingual Extensions/SF Arabic/SF-Arabic.ttf"
TEXT = "الإعدادات مستكشف الملفات مرحبًا بالعالم"
BUILD = sys.argv[1]


def run(path):
    f = hb.Font(hb.Face(hb.Blob.from_file_path(path)))
    b = hb.Buffer()
    b.add_str(TEXT)
    b.guess_segment_properties()
    hb.shape(f, b, {})
    return [i.codepoint for i in b.glyph_infos], [p.x_advance for p in b.glyph_positions]


def area(gs, n):
    p = AreaPen(gs)
    gs[n].draw(p)
    return abs(p.value)


for w, fn in ((300, "segoeuil.ttf"), (400, "segoeui.ttf"), (700, "segoeuib.ttf")):
    raw = instancer.instantiateVariableFont(TTFont(AR), {"wght": w, "opsz": 17})
    raw_path = os.path.join(tempfile.gettempdir(), "sf-arabic-instance.ttf")
    raw.save(raw_path)
    built = TTFont(f"{BUILD}/{fn}")
    (r, radv), (bt, badv) = run(raw_path), run(f"{BUILD}/{fn}")
    ro, bo = raw.getGlyphOrder(), built.getGlyphOrder()
    rg, bg = raw.getGlyphSet(), built.getGlyphSet()
    rn, bn = [ro[i] for i in r], [bo[i] for i in bt]
    same = [n.split("#")[0] for n in bn] == rn
    print(f"== {fn}: same glyph sequence as Apple: {same}  ({len(rn)} vs {len(bn)} glyphs)")
    for a, b, ra_, ba_ in zip(rn, bn, radv, badv):
        ra, ba = area(rg, a), area(bg, b)
        if (ra > 50 and ba < 0.5 * ra) or a != b.split("#")[0] or ra_ != ba_:
            print(f"   apple {a:24} ink {ra:9.0f} adv {ra_:5}   built {b:26} ink {ba:9.0f} adv {ba_:5}")
