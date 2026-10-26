#!/usr/bin/env python3
"""Generate scripts/Atlas.gd from the APK's res/raw/atlas.txt (UV rects -> pixel rects)."""
import sys
src, dst = sys.argv[1], sys.argv[2]
rows = [l.split() for l in open(src) if len(l.split()) == 7]
lines = []
for name, w, h, u, v, uw, vh in sorted(rows, key=lambda r: r[0]):
    x, y = round(float(u) * 1024), round(float(v) * 1024)
    W, H = round(float(uw) * 1024), round(float(vh) * 1024)
    assert (W, H) == (int(w), int(h)), name
    lines.append(f'\t"{name}": Rect2i({x}, {y}, {W}, {H}),')
tpl = open(dst.replace("scripts/Atlas.gd", "tools/Atlas.gd") + ".tpl").read()
open(dst, "w").write(tpl.replace("#@RECTS@", "\n".join(lines)))
print(len(lines), "sprites written to", dst)
