r"""Validate the Apple-based Segoe UI / Segoe UI Variable replacements against the originals.

Usage: validate_ui_fonts.py <built dir> <original Segoe dir> <Apple SF dir>
  original Segoe dir: C:\Windows\Fonts, or a copy of the original Segoe files
                      (the originals are never modified by the install, only repointed away from)
Windows only: reads the installed fonts from the registry to check fallback coverage.
Exit code 0 only if every hard check passes.
"""
import collections
import os
import subprocess
import sys

if os.name != "nt" or len(sys.argv) != 4:
    sys.exit(__doc__)

import winreg  # noqa: E402  (Windows only, checked above)

import uharfbuzz as hb  # noqa: E402
from fontTools import unicodedata as ud  # noqa: E402
from fontTools.ttLib import TTCollection, TTFont  # noqa: E402
from fontTools.varLib import instancer  # noqa: E402

BUILT, WINFONTS, APPLE = sys.argv[1:4]
SYSFONTS = os.path.join(os.environ["WINDIR"], "Fonts")   # where registry font file names resolve
SF_PRO, SF_PRO_IT = f"{APPLE}/SF Pro/SF-Pro.ttf", f"{APPLE}/SF Pro/SF-Pro-Italic.ttf"
EXT = f"{APPLE}/SF Multilingual Extensions"
SCRIPTS = [f"{EXT}/SF Arabic/SF-Arabic.ttf", f"{EXT}/SF Hebrew/SF-Hebrew.ttf",
           f"{EXT}/SF Armenian/SF-Armenian.ttf", f"{EXT}/SF Georgian/SF-Georgian.ttf"]
WEIGHTS = {"segoeuil.ttf": (300, False), "segoeuisl.ttf": (350, False), "segoeui.ttf": (400, False),
           "seguisb.ttf": (600, False), "segoeuib.ttf": (700, False), "seguibl.ttf": (900, False),
           "seguili.ttf": (300, True), "seguisli.ttf": (350, True), "segoeuii.ttf": (400, True),
           "seguisbi.ttf": (600, True), "segoeuiz.ttf": (700, True), "seguibli.ttf": (900, True),
           "SegUIVar.ttf": (400, False)}


def apple_instance(path, coords):
    f = TTFont(path)
    lim = {a.axisTag: coords.get(a.axisTag, a.defaultValue) for a in f["fvar"].axes}
    return instancer.instantiateVariableFont(f, lim)


def points(gs, name):
    from fontTools.pens.recordingPen import DecomposingRecordingPen
    r = DecomposingRecordingPen(gs)
    gs[name].draw(r)
    return [p for _, v in r.value for p in v]


def fidelity(fn, new):
    """Every glyph taken from Apple must have exactly Apple's points (each within 2/2048 em: rounding only)."""
    w, it = WEIGHTS[fn]
    c = {"wdth": 100, "opsz": 17, "YAXS": 400, "wght": w}
    base = apple_instance(SF_PRO_IT if it else SF_PRO, c)
    scripts = [apple_instance(p, {"wght": min(w, 900), "opsz": 17}) for p in SCRIPTS] if fn != "SegUIVar.ttf" else []
    gs = new.getGlyphSet()   # default instance for the variable font = SF Pro Text Regular
    bad, compared, worst = [], 0, 0
    for name in new.getGlyphOrder():
        if name.startswith("segoe."):
            continue                      # gap-filled from Segoe on purpose
        src_name, dup = name.split("#")[0], "#" in name
        srcs = (scripts if dup else [base] + scripts)
        src = next((s for s in srcs if src_name in s.getGlyphOrder()), None)
        if src is None:
            continue
        a, b = points(src.getGlyphSet(), src_name), points(gs, name)
        compared += 1
        if len(a) != len(b):
            bad.append(f"{name} (points {len(a)} vs {len(b)})")
            continue
        d = max([max(abs(x1 - x2), abs(y1 - y2)) for (x1, y1), (x2, y2) in zip(a, b)] or [0])
        worst = max(worst, d)
        if d > 2:
            bad.append(f"{name} (moved {d} units)")
    check(not bad, f"{fn}: {compared} glyph outlines identical to Apple's (largest point shift {worst}/2048 em); "
                   f"damaged: {bad[:6]}")
UI_FILES = ["segoeuil.ttf", "segoeuisl.ttf", "segoeui.ttf", "seguisb.ttf", "segoeuib.ttf", "seguibl.ttf",
            "seguili.ttf", "seguisli.ttf", "segoeuii.ttf", "seguisbi.ttf", "segoeuiz.ttf", "seguibli.ttf",
            "SegUIVar.ttf"]
SAMPLES = {
    "English": "The quick brown fox jumps over the lazy dog. Settings, File Explorer & Notepad 0123456789",
    "Arabic": "مرحبًا بالعالم! الإعدادات، مستكشف الملفات والمفكرة ٠١٢٣٤٥٦٧٨٩ لا إله",
    "Hebrew": "שלום עולם, הגדרות",
    "Greek/Cyrillic": "Καλημέρα κόσμε Привет мир",
}
fails, notes = [], []


def check(ok, msg):
    (notes if ok else fails).append(("PASS " if ok else "FAIL ") + msg)


def hbfont(path, var=None):
    f = hb.Font(hb.Face(hb.Blob.from_file_path(path)))
    if var:
        f.set_variations(var)
    return f


def shape(font, text):
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf, {})
    return buf.glyph_infos, buf.glyph_positions


# --- every other installed font's coverage (what Windows can fall back to) -------------
def installed_fonts():
    out = {}
    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts") as k:
        i = 0
        while True:
            try:
                name, val, _ = winreg.EnumValue(k, i)
            except OSError:
                break
            i += 1
            path = val if os.path.isabs(val) else os.path.join(SYSFONTS, val)
            out[name] = path
    return out


# The fonts under test must not count as their own fallback: skip the Segoe originals and,
# when the install is active, the SFUI-* builds the registry now points at.
skip = {f.lower() for f in UI_FILES} | {"seguiemj.ttf"}
skip |= {"sfui-" + f for f in skip}
fallback_cov = set()
gdi_link_cov = set()
with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink") as k:
    link_files = {line.split(",")[0].lower() for line in winreg.QueryValueEx(k, "Segoe UI")[0]}
unreadable = []
for path in installed_fonts().values():
    base = os.path.basename(path).lower()
    if base in skip or not os.path.exists(path):
        continue
    try:
        fonts = TTCollection(path, lazy=True).fonts if path.lower().endswith(".ttc") else [TTFont(path, lazy=True)]
        for f in fonts:
            cm = set(f.getBestCmap() or {})
            fallback_cov |= cm
            if base in link_files:
                gdi_link_cov |= cm
    except Exception:  # noqa: BLE001  (a broken third-party font must not stop the run)
        unreadable.append(path)
if unreadable:
    notes.append(f"INFO {len(unreadable)} installed font(s) unreadable, not counted as fallback: {unreadable[:5]}")

# --- per-font checks ------------------------------------------------------------------
width_report = []
for fn in UI_FILES:
    new_p, old_p = os.path.join(BUILT, fn), os.path.join(WINFONTS, fn)
    new, old = TTFont(new_p), TTFont(old_p)

    # 1. structure
    r = subprocess.run([sys.executable, "-m", "ots", new_p, os.devnull], capture_output=True, text=True, check=False)
    check(r.returncode == 0, f"{fn}: OpenType Sanitizer {r.stderr.strip()[:120]}")
    try:
        for tag in new.keys():  # noqa: SIM118  (TTFont is not iterable over its tags)
            if tag != "GlyphOrder":
                new[tag]
        check(True, f"{fn}: all tables decompile")
    except Exception as e:
        check(False, f"{fn}: decompile error {e!r}")

    # 1a. outlines are Apple's, untouched
    fidelity(fn, new)

    # 1b. layout tables sorted by tag (engines binary-search scripts/features)
    unsorted = []
    for tag in ("GSUB", "GPOS"):
        if tag in new:
            t = new[tag].table
            lists = {"scripts": [r.ScriptTag for r in t.ScriptList.ScriptRecord],
                     "features": [r.FeatureTag for r in t.FeatureList.FeatureRecord]}
            for sr in t.ScriptList.ScriptRecord:
                lists[f"langs/{sr.ScriptTag}"] = [r.LangSysTag for r in sr.Script.LangSysRecord]
            unsorted += [f"{tag} {k}" for k, v in lists.items() if v != sorted(v)]
    check(not unsorted, f"{fn}: layout tags sorted {unsorted[:4]}")

    # 2. identity: names / style bits / metrics identical to Segoe
    def names(t):
        return {(r.nameID, r.platformID, r.platEncID, r.langID): r.toUnicode() for r in t["name"].names if r.nameID != 5}
    check(names(new) == names(old), f"{fn}: name table identical to Segoe (except version)")
    for k in ("usWeightClass", "fsSelection", "usWinAscent", "usWinDescent", "sTypoAscender", "sTypoDescender", "sTypoLineGap"):
        check(getattr(new["OS/2"], k) == getattr(old["OS/2"], k), f"{fn}: OS/2.{k} = {getattr(new['OS/2'], k)}")
    for k in ("ascent", "descent", "lineGap"):
        check(getattr(new["hhea"], k) == getattr(old["hhea"], k), f"{fn}: hhea.{k}")
    check(new["head"].macStyle == old["head"].macStyle, f"{fn}: macStyle")
    if "fvar" in old:
        def ax(t):
            return [(a.axisTag, a.minValue, a.defaultValue, a.maxValue) for a in sorted(t["fvar"].axes, key=lambda a: a.axisTag)]
        check(ax(new) == ax(old), f"{fn}: variation axes {ax(new)}")
        def inst(t):
            return sorted((tuple(sorted(i.coordinates.items())), i.subfamilyNameID) for i in t["fvar"].instances)
        check(inst(new) == inst(old), f"{fn}: all {len(old['fvar'].instances)} named instances match")

    # 3. coverage: nothing Segoe could draw may become a square
    lost = set(old.getBestCmap()) - set(new.getBestCmap())
    dwrite_sq = sorted(c for c in lost if c not in fallback_cov and not ud.category(chr(c)).startswith(("Z", "C", "M")))
    gdi_sq = sorted(c for c in lost if c not in gdi_link_cov and c not in fallback_cov)
    by_script = collections.Counter(ud.script_name(ud.script(chr(c))) for c in lost)
    check(not dwrite_sq, f"{fn}: {len(lost)} chars moved to fallback fonts, {len(dwrite_sq)} with no fallback "
          f"{[hex(c) for c in dwrite_sq[:10]]}")
    # Everyday English + Arabic must come from the Apple font itself, never from fallback:
    # Basic Latin, Latin-1, Latin Extended-A, general punctuation basics, Euro, Arabic block.
    core = [c for c in old.getBestCmap() if 0x20 <= c <= 0x17F or 0x2010 <= c <= 0x2027 or c == 0x20AC
            or (0x600 <= c <= 0x6FF and not ud.category(chr(c)).startswith("C"))]
    core_lost = [c for c in core if c in lost]
    check(not core_lost, f"{fn}: everyday Latin + Arabic all drawn by the Apple font "
          f"({len(core) - len(core_lost)}/{len(core)}; missing {[hex(c) for c in core_lost[:10]]})")
    check(not gdi_sq, f"{fn}: classic (GDI) apps: {len(gdi_sq)} chars with no linked/fallback font")
    notes.append(f"INFO {fn}: chars handed to fallback by script: {dict(by_script.most_common(8))}")

    # 4. shaping: no missing glyphs, Arabic joins
    var = None
    if "fvar" in new:
        var = {"wght": 400, "opsz": 10.5}
    fnew, fold = hbfont(new_p, var), hbfont(old_p, var)
    for lang, text in SAMPLES.items():
        if fn == "SegUIVar.ttf" and lang in ("Arabic", "Hebrew"):
            continue  # Segoe UI Variable has no Arabic/Hebrew either; Windows falls back to Segoe UI
        infos, pos = shape(fnew, text)
        notdef = sum(1 for i in infos if i.codepoint == 0)
        check(notdef == 0, f"{fn}: {lang} sample shapes with no missing glyphs ({notdef})")
        if lang == "Arabic":
            iso = set(shape(fnew, ch)[0][0].codepoint for ch in "مرحبالعم")
            joined = sum(1 for i in infos if i.codepoint not in iso)
            check(joined > 10, f"{fn}: Arabic letters join (contextual forms used: {joined})")
        w_new = sum(p.x_advance for p in pos)
        w_old = sum(p.x_advance for p in shape(fold, text)[1])
        if lang in ("English", "Arabic") and w_old:
            width_report.append((fn, lang, w_new / w_old))

print("\n".join(notes))
print("\nText width vs Segoe (1.00 = same):")
for fn, lang, r in width_report:
    print(f"  {fn:14} {lang:8} {r:.2f}")
print(f"\n{len(fails)} FAILED checks" if fails else "\nALL HARD CHECKS PASSED")
print("\n".join(fails))
sys.exit(1 if fails else 0)
