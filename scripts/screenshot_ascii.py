#!/usr/bin/env python3
"""Prints screenshots as small ASCII thumbnails plus their dominant colors, so a
screenshot can be inspected from a plain text CI log.

    python3 scripts/screenshot_ascii.py screenshots/*.png
"""
import sys
from PIL import Image

RAMP = "@#%*+=-:. "  # dark → light


def describe(path, cols=100):
    im = Image.open(path).convert("RGB")
    if im.height > im.width:  # portrait framebuffer holding a landscape app
        im = im.rotate(90, expand=True)
    small = im.resize((200, max(1, int(200 * im.height / im.width))))
    counts = sorted(small.getcolors(small.width * small.height), reverse=True)
    total = small.width * small.height
    top = ", ".join(f"#{r:02X}{g:02X}{b:02X} {100 * n / total:.0f}%" for n, (r, g, b) in counts[:5])
    rows = max(1, int(cols * im.height / im.width * 0.45))
    gray = im.resize((cols, rows)).convert("L")
    print(f"=== {path}  {im.width}x{im.height}  colors: {top}")
    for y in range(rows):
        print("|" + "".join(RAMP[min(len(RAMP) - 1, gray.getpixel((x, y)) * len(RAMP) // 256)] for x in range(cols)) + "|")


for p in sys.argv[1:]:
    describe(p)
