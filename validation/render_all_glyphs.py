"""Render EVERY glyph of each font with Windows' own engines and flag any that come out blank.

  GDI (classic apps, hinted, grayscale) at 12, 16 and 20 px  -> GetGlyphOutline(GGO_GRAY8_BITMAP)
  WPF / DirectWrite-style outline                            -> GlyphTypeface.GetGlyphOutline area

A glyph "should have ink" when its outline in the font file has contours. Fonts are loaded
privately under a temporary family name, so nothing is installed and the real Segoe UI is untouched.

Usage: render_all_glyphs.py <fonts dir> <work dir> [--reference <dir>] [file ...]
  --reference: also expect ink wherever the same-named glyph has ink in the reference font
               (used for the positive control: a damaged copy must be caught)
"""
import json
import os
import shutil
import subprocess
import sys

from fontTools.pens.areaPen import AreaPen
from fontTools.ttLib import TTFont

POWERSHELL = shutil.which("pwsh") or shutil.which("powershell")
if os.name != "nt" or not POWERSHELL or len(sys.argv) < 3:
    sys.exit(__doc__ + "\nNeeds Windows (GDI/WPF) and PowerShell.")
SRC, WORK = sys.argv[1:3]
rest = sys.argv[3:]
REF = None
if "--reference" in rest:
    i = rest.index("--reference")
    if i + 1 >= len(rest):
        sys.exit("--reference needs a directory")
    REF = rest[i + 1]
    rest = rest[:i] + rest[i + 2:]
FILES = rest or sorted(f for f in os.listdir(SRC) if f.lower().endswith(".ttf"))
os.makedirs(WORK, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))

jobs, inked = [], {}
for i, fn in enumerate(FILES):
    f = TTFont(os.path.join(SRC, fn))
    gs = f.getGlyphSet()
    order = f.getGlyphOrder()
    ink = set()
    for gid, name in enumerate(order):
        p = AreaPen(gs)
        gs[name].draw(p)
        if abs(p.value) > 0:
            ink.add(gid)
    if REF:
        ref = TTFont(os.path.join(REF, fn))
        rgs = ref.getGlyphSet()
        for gid, name in enumerate(order):
            if name in rgs and gid not in ink:
                p = AreaPen(rgs)
                rgs[name].draw(p)
                if abs(p.value) > 0:
                    ink.add(gid)
    inked[fn] = (order, ink)
    family = f"ZZRenderTest{i}"
    for rec in f["name"].names:
        if rec.nameID in (1, 4, 6, 16):
            rec.string = family
    out = os.path.join(WORK, f"{i}-{fn}")
    f.save(out)
    jobs.append({"file": out, "family": family, "name": fn, "glyphs": len(order)})

with open(os.path.join(WORK, "jobs.json"), "w") as fh:
    json.dump(jobs, fh)
subprocess.run([POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", os.path.join(HERE, "render_all_glyphs.ps1"),
                os.path.join(WORK, "jobs.json"), os.path.join(WORK, "blank.json")], check=True)
with open(os.path.join(WORK, "blank.json"), encoding="utf-8-sig") as fh:
    blank = json.load(fh)

total_fail = 0
for job in jobs:
    fn = job["name"]
    order, ink = inked[fn]
    res = blank[job["family"]]
    line = [f"{fn:15} {len(ink):6} inked glyphs"]
    for engine, empties in res.items():
        bad = sorted(set(empties) & ink)
        total_fail += len(bad)
        line.append(f"{engine}: {len(bad)} blank" + (f" {[order[g] for g in bad[:6]]}" if bad else ""))
    print(" | ".join(line))
print(f"\nTOTAL blank glyphs that should have ink: {total_fail}")
sys.exit(1 if total_fail else 0)
