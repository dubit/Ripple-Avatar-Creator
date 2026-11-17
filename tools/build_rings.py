"""Draws the recommendation ring's glow images (white, alpha = light; tinted in-game).
ring_glow.png  a bright thin ring with a soft glow either side
ring_fill.png  a soft filled disc (the dwell fill)
Usage: python tools/build_rings.py assets/world"""
import sys, math
import numpy as np
from PIL import Image

out = sys.argv[1]
N = 512
y, x = np.mgrid[0:N, 0:N]
r = np.hypot(x - (N - 1) / 2, y - (N - 1) / 2) / (N / 2)  # 0 centre .. 1 edge

def save(alpha, name):
    a = np.clip(alpha, 0, 1)
    img = np.zeros((N, N, 4), dtype=np.uint8)
    img[..., :3] = 255
    img[..., 3] = (a * 255).round().astype(np.uint8)
    Image.fromarray(img, "RGBA").save(f"{out}/{name}")

R = 0.78  # ring radius (fraction of half-size)
core = np.exp(-((r - R) / 0.022) ** 2)           # the bright line
glow = 0.55 * np.exp(-((r - R) / 0.09) ** 2)     # soft halo either side
inner = 0.10 * np.exp(-((r - R) / 0.30) ** 2) * (r < R)  # faint light inside
save(np.maximum(core, glow + inner), "ring_glow.png")

fill = 0.85 * (1 / (1 + np.exp((r - 0.74) / 0.035)))  # soft-edged disc inside the ring
save(fill, "ring_fill.png")
print("ok")
