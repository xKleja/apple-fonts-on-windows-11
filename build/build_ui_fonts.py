"""Build Apple-based replacements for the Windows UI fonts.

Segoe UI (12 static faces)  <- SF Pro (Text optical size) + SF Arabic/Hebrew/Armenian/Georgian
Segoe UI Variable           <- SF Pro variable (wght + opsz), mapped onto Segoe's axis/instance layout

Each output keeps Segoe's exact name table, weight/style bits and vertical metrics, so
Windows matches every requested face (no faux bold) and layouts keep their line heights.

Usage: build_ui_fonts.py <apple fonts dir> <segoe dir> <out dir> [--no-hint]
"""
import os
import sys
import tempfile

from fontTools import subset
from fontTools.merge import Merger
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

APPLE, SEGOE, OUT = sys.argv[1:4]
HINT = "--no-hint" not in sys.argv
os.makedirs(OUT, exist_ok=True)

SF_PRO = f"{APPLE}/SF Pro/SF-Pro.ttf"
SF_PRO_IT = f"{APPLE}/SF Pro/SF-Pro-Italic.ttf"
EXT = f"{APPLE}/SF Multilingual Extensions"
SCRIPTS = [f"{EXT}/SF Arabic/SF-Arabic.ttf", f"{EXT}/SF Hebrew/SF-Hebrew.ttf",
           f"{EXT}/SF Armenian/SF-Armenian.ttf", f"{EXT}/SF Georgian/SF-Georgian.ttf"]
TEXT_OPSZ = 17  # SF Pro "Text" optical size: what macOS uses for UI-sized text

# Segoe UI file -> (weight, italic)
STATIC = {
    "segoeuil.ttf": (300, False), "segoeuisl.ttf": (350, False), "segoeui.ttf": (400, False),
    "seguisb.ttf": (600, False), "segoeuib.ttf": (700, False), "seguibl.ttf": (900, False),
    "seguili.ttf": (300, True), "seguisli.ttf": (350, True), "segoeuii.ttf": (400, True),
    "seguisbi.ttf": (600, True), "segoeuiz.ttf": (700, True), "seguibli.ttf": (900, True),
}
# Apple-only / variation tables that make no sense in the output
DROP_STATIC = ["trak", "morx", "feat", "MERG", "meta", "STAT", "DSIG", "MVAR"]
DROP_VAR = ["trak", "morx", "feat", "MERG", "meta", "DSIG", "MVAR"]


def log(*a):
    print(*a, flush=True)


def drop(font, tags):
    for t in tags:
        if t in font:
            del font[t]


def strip_feature_name_refs(font):
    """Stylistic-set names point into Apple's name table, which we replace."""
    for tag in ("GSUB", "GPOS"):
        if tag in font and font[tag].table.FeatureList:
            for rec in font[tag].table.FeatureList.FeatureRecord:
                rec.Feature.FeatureParams = None


def is_gap_char(c):
    """Characters that must never fall through to another font (or become squares)."""
    return (0x20 <= c <= 0x17F or 0x2010 <= c <= 0x2027 or 0x20A0 <= c <= 0x20CF  # Latin, punctuation, currency
            or 0x600 <= c <= 0x6FF or 0x1C90 <= c <= 0x1CBF)                   # Arabic, Georgian Mtavruli


def gap_fill(font, seg):
    """Copy Segoe's own glyph for the few everyday characters SF Pro does not have."""
    from fontTools.pens.recordingPen import DecomposingRecordingPen
    from fontTools.pens.ttGlyphPen import TTGlyphPen
    seg_cmap, cmap = seg.getBestCmap(), font.getBestCmap()
    want = sorted(c for c in seg_cmap if c not in cmap and is_gap_char(c))
    if not want:
        return 0
    gs, glyf, hmtx = seg.getGlyphSet(), font["glyf"], font["hmtx"]
    order = list(font.getGlyphOrder())
    names = {}
    for c in want:
        src = seg_cmap[c]
        name = names.get(src)
        if name is None:
            name = f"segoe.{src}"
            rec = DecomposingRecordingPen(gs)
            gs[src].draw(rec)
            pen = TTGlyphPen(None)
            rec.replay(pen)
            g = pen.glyph()
            order.append(name)
            font.setGlyphOrder(order)
            glyf.glyphOrder = order
            glyf[name] = g
            g.recalcBounds(glyf)
            hmtx[name] = (gs[src].width, getattr(g, "xMin", 0) if g.numberOfContours else 0)
            if "gvar" in font:
                font["gvar"].variations[name] = []
            names[src] = name
        for t in font["cmap"].tables:
            if t.isUnicode() and (c <= 0xFFFF or t.format in (12, 13)):
                t.cmap[c] = name
    if "HVAR" in font:  # its glyph-indexed width map does not cover the new glyphs; optional table
        del font["HVAR"]
    return len(want)


def sort_layout(font):
    """Script / language / feature records must be sorted by tag (spec; engines binary-search them)."""
    for tag in ("GSUB", "GPOS"):
        if tag not in font:
            continue
        t = font[tag].table
        recs = t.FeatureList.FeatureRecord
        perm = sorted(range(len(recs)), key=lambda i: (recs[i].FeatureTag, i))
        new_index = {old: new for new, old in enumerate(perm)}
        t.FeatureList.FeatureRecord = [recs[i] for i in perm]
        t.ScriptList.ScriptRecord.sort(key=lambda r: r.ScriptTag)
        for sr in t.ScriptList.ScriptRecord:
            sr.Script.LangSysRecord.sort(key=lambda r: r.LangSysTag)
            for ls in [sr.Script.DefaultLangSys] + [r.LangSys for r in sr.Script.LangSysRecord]:
                if ls is None:
                    continue
                ls.FeatureIndex = sorted(new_index[i] for i in ls.FeatureIndex)
                if ls.ReqFeatureIndex != 0xFFFF:
                    ls.ReqFeatureIndex = new_index[ls.ReqFeatureIndex]
        fv = getattr(t, "FeatureVariations", None)
        if fv:
            for rec in fv.FeatureVariationRecord:
                for sub in rec.FeatureTableSubstitution.SubstitutionRecord:
                    sub.FeatureIndex = new_index[sub.FeatureIndex]


def pin(path, coords):
    font = TTFont(path)
    # Pin every axis: requested value if given, otherwise the font's default.
    limits = {a.axisTag: coords.get(a.axisTag, a.defaultValue) for a in font["fvar"].axes}
    return instancer.instantiateVariableFont(font, limits, overlap=instancer.OverlapMode.KEEP_AND_SET_FLAGS,
                                             updateFontNames=False)


def apply_segoe_identity(font, seg, variable=False):
    """Copy Segoe's names, style bits and vertical metrics; recompute coverage bits."""
    font["name"] = seg["name"]
    ver = seg["name"].getDebugName(5)
    font["name"].setName(f"{ver}; SF Pro 22.0d5e4 (Apple)", 5, 3, 1, 0x409)
    o, so = font["OS/2"], seg["OS/2"]
    for k in ("usWeightClass", "usWidthClass", "fsSelection", "usWinAscent", "usWinDescent",
              "sTypoAscender", "sTypoDescender", "sTypoLineGap", "fsType"):
        setattr(o, k, getattr(so, k))
    o.panose = so.panose
    o.recalcUnicodeRanges(font)
    o.recalcCodePageRanges(font)
    o.recalcAvgCharWidth(font)
    for k in ("ascent", "descent", "lineGap"):
        setattr(font["hhea"], k, getattr(seg["hhea"], k))
    font["head"].macStyle = seg["head"].macStyle
    strip_feature_name_refs(font)


def build_static(fname, weight, italic, tmp):
    seg = TTFont(f"{SEGOE}/{fname}")
    base = pin(SF_PRO_IT if italic else SF_PRO, {"wdth": 100, "opsz": TEXT_OPSZ, "YAXS": 400, "wght": weight})
    drop(base, DROP_STATIC)
    strip_feature_name_refs(base)
    base_cmap = set(base.getBestCmap())
    parts = [os.path.join(tmp, "base.ttf")]
    base.save(parts[0])

    covered = set(base_cmap)
    for i, path in enumerate(SCRIPTS):
        s = pin(path, {"wght": min(weight, 900), "opsz": TEXT_OPSZ})
        drop(s, DROP_STATIC)
        strip_feature_name_refs(s)
        new = sorted(set(s.getBestCmap()) - covered)
        if not new:
            continue
        opts = subset.Options()
        opts.layout_features = ["*"]
        opts.name_IDs = ["*"]
        opts.notdef_outline = True
        opts.glyph_names = True
        sub = subset.Subsetter(opts)
        sub.populate(unicodes=new)
        sub.subset(s)
        covered |= set(new)
        p = os.path.join(tmp, f"script{i}.ttf")
        s.save(p)
        parts.append(p)

    merged = Merger().merge(parts)
    filled = gap_fill(merged, seg)
    sort_layout(merged)
    apply_segoe_identity(merged, seg)
    out = os.path.join(OUT, fname)
    merged.save(out)
    if HINT:
        import ttfautohint
        hinted = out + ".hinted"
        # hint_composites must stay off: it appends a glyph and corrupts GPOS anchors (caught by OTS).
        ttfautohint.ttfautohint(in_file=out, out_file=hinted, no_info=True,
                                default_script="latn", fallback_script="latn",
                                hint_composites=False)
        h, pre = TTFont(hinted), TTFont(out)
        if h.getGlyphOrder() != pre.getGlyphOrder() or any(
                h.reader[t] != pre.reader[t] for t in ("GPOS", "GSUB", "GDEF") if t in pre):
            raise SystemExit(f"{fname}: hinting changed glyph order or layout tables; refusing to continue")
        # ttfautohint may touch vertical metrics; put Segoe's back
        for k in ("usWinAscent", "usWinDescent", "sTypoAscender", "sTypoDescender", "sTypoLineGap"):
            setattr(h["OS/2"], k, getattr(seg["OS/2"], k))
        for k in ("ascent", "descent", "lineGap"):
            setattr(h["hhea"], k, getattr(seg["hhea"], k))
        h.save(out)
        os.remove(hinted)
    log(f"static {fname}: wght {weight}{' italic' if italic else ''}, "
        f"{len(TTFont(out).getBestCmap())} chars ({filled} gap-filled from Segoe)")


def build_variable():
    seg = TTFont(f"{SEGOE}/SegUIVar.ttf")
    vf = instancer.instantiateVariableFont(
        TTFont(SF_PRO), {"wdth": 100, "wght": (300, 400, 700), "opsz": (TEXT_OPSZ, TEXT_OPSZ, 28)},
        updateFontNames=False)
    drop(vf, DROP_VAR)
    seg_axes = {a.axisTag: a for a in seg["fvar"].axes}
    # Present Segoe's user-space axes (opsz 5..10.5..36): Text sizes and below get SF Text,
    # Display sizes get SF Display, matching how macOS switches optical sizes.
    for a in vf["fvar"].axes:
        s = seg_axes[a.axisTag]
        a.minValue, a.defaultValue, a.maxValue = s.minValue, s.defaultValue, s.maxValue
        a.axisNameID = s.axisNameID
    vf["fvar"].instances = seg["fvar"].instances
    vf["STAT"] = seg["STAT"]
    filled = gap_fill(vf, seg)
    sort_layout(vf)
    apply_segoe_identity(vf, seg, variable=True)
    out = os.path.join(OUT, "SegUIVar.ttf")
    vf.save(out)
    log(f"variable SegUIVar.ttf: axes {[(a.axisTag, a.minValue, a.defaultValue, a.maxValue) for a in vf['fvar'].axes]}, "
        f"{len(vf['fvar'].instances)} instances, {filled} gap-filled from Segoe")


if __name__ == "__main__":
    only = [a for a in sys.argv[4:] if not a.startswith("--")]
    build_variable()
    for fname, (w, it) in STATIC.items():
        if only and fname not in only:
            continue
        with tempfile.TemporaryDirectory() as tmp:
            build_static(fname, w, it, tmp)
    log("BUILD DONE")
