#!/usr/bin/env python3
"""Draws the app icon (1024x1024) procedurally. Requires Pillow.

    python3 tools/make_icon.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

S = 1024
BG = (243, 226, 192)
INK = (42, 37, 34)
ACCENT = (228, 87, 46)
OUT = Path(__file__).resolve().parent.parent / "Game/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

img = Image.new("RGB", (S, S), BG)
d = ImageDraw.Draw(img)
T = S // 8  # tile size

# Floor with a gap, and one tile tumbling into it.
for x in range(8):
    if x in (4, 5):
        continue
    d.rectangle([x * T, S - 2 * T, (x + 1) * T, S], fill=INK)
tile = Image.new("RGBA", (T, T), INK + (255,))
tile = tile.rotate(18, expand=True, resample=Image.BICUBIC)
img.paste(tile, (int(4.35 * T), int(S - 1.55 * T)), tile)

# Spikes on the right.
for i in range(4):
    x0 = int(6 * T + i * T / 2)
    d.polygon([(x0, S - 2 * T), (x0 + T // 4, S - 2 * T - int(T * 0.55)), (x0 + T // 2, S - 2 * T)], fill=INK)

# The hero mid-jump above the gap.
w, h = int(T * 1.55), int(T * 2.0)
cx, by = int(S * 0.44), int(S * 0.52)
d.rounded_rectangle([cx - w // 2, by - h, cx + w // 2, by], radius=int(w * 0.28), fill=INK)
eye_r, pupil_r = int(w * 0.17), int(w * 0.085)
for side in (-1, 1):
    ex = cx + side * int(w * 0.21) + int(w * 0.06)
    ey = by - int(h * 0.62)
    d.ellipse([ex - eye_r, ey - eye_r, ex + eye_r, ey + eye_r], fill=(255, 255, 255))
    d.ellipse([ex - pupil_r + int(w * 0.05), ey - pupil_r + int(h * 0.03),
               ex + pupil_r + int(w * 0.05), ey + pupil_r + int(h * 0.03)], fill=INK)

# Motion ticks and a warning mark.
for i in range(3):
    y = by - int(h * 0.2) - i * int(T * 0.35)
    d.rounded_rectangle([cx - w // 2 - int(T * 0.9), y, cx - w // 2 - int(T * 0.35), y + int(T * 0.12)],
                        radius=int(T * 0.06), fill=INK)
d.ellipse([int(S * 0.72), int(S * 0.16), int(S * 0.86), int(S * 0.30)], fill=ACCENT)
d.rounded_rectangle([int(S * 0.781), int(S * 0.185), int(S * 0.799), int(S * 0.255)], radius=8, fill=BG)
d.ellipse([int(S * 0.779), int(S * 0.263), int(S * 0.801), int(S * 0.285)], fill=BG)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT)
print(f"wrote {OUT}")
