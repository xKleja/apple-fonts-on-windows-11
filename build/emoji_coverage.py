"""Emoji coverage per Unicode Emoji version: Segoe UI Emoji vs Apple (Mac) vs built font.

Usage: emoji_coverage.py <emoji-test.txt> name=path[#index] ...
An emoji counts as supported when HarfBuzz shapes it to a single non-.notdef glyph.
"""
import collections
import re
import sys

import uharfbuzz as hb


def load(spec):
    path, _, idx = spec.partition("#")
    return hb.Font(hb.Face(hb.Blob.from_file_path(path), int(idx or 0)))


def ok(font, s):
    buf = hb.Buffer()
    buf.add_str(s)
    buf.guess_segment_properties()
    hb.shape(font, buf, {})
    g = [i.codepoint for i in buf.glyph_infos]
    return len(g) == 1 and g[0] != 0


items = []
for line in open(sys.argv[1], encoding="utf-8"):
    m = re.match(r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*\S+\s+E(\d+\.\d+)\s+(.*)$", line)
    if m:
        items.append(("".join(chr(int(c, 16)) for c in m.group(1).split()), m.group(2), m.group(3)))

fonts = {}
for arg in sys.argv[2:]:
    name, _, spec = arg.partition("=")
    fonts[name] = load(spec)

tot = collections.Counter()
sup = {k: collections.Counter() for k in fonts}
res = []
for s, v, label in items:
    tot[v] += 1
    r = {k: ok(f, s) for k, f in fonts.items()}
    res.append((s, v, label, r))
    for k in fonts:
        if r[k]:
            sup[k][v] += 1

names = list(fonts)
print("ver    total " + " ".join(f"{n:>10}" for n in names))
for v in sorted(tot, key=float):
    print(f"{v:6} {tot[v]:5} " + " ".join(f"{sup[n][v]:>10}" for n in names))
print("all    " + f"{sum(tot.values()):5} " + " ".join(f"{sum(sup[n].values()):>10}" for n in names))

if len(names) >= 2:
    base = names[0]
    for other in names[1:]:
        miss = [(v, label) for s, v, label, r in res if r[base] and not r[other]]
        print(f"\nIn {base} but missing from {other}: {len(miss)}")
        for v, label in miss[:25]:
            print(f"   E{v} {label}")
