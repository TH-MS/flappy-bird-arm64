#!/usr/bin/env python3
"""Build Android launcher icons from tools/icon_source.png (the original Flappy Bird icon).
usage: make_icons.py <source.png> <outdir>
Writes main.png (192x192) and adaptive_fg.png / adaptive_bg.png (432x432)."""
import sys, os
from PIL import Image, ImageFilter
src, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
ic = Image.open(src).convert("RGBA")
ic.resize((192, 192), Image.LANCZOS).save(os.path.join(outdir, "main.png"))
# adaptive icon: foreground = icon filling the ~72dp visible window; background = blurred icon (no hard seam)
bg = ic.resize((432, 432), Image.LANCZOS).filter(ImageFilter.GaussianBlur(24))
bg.putalpha(255)
bg.save(os.path.join(outdir, "adaptive_bg.png"))
fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
fg.alpha_composite(ic.resize((320, 320), Image.LANCZOS), (56, 56))
fg.save(os.path.join(outdir, "adaptive_fg.png"))
print("icons written to", outdir)
