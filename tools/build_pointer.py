"""Build the onboarding pointer: a white 3D hand, finger up, shaded in our oranges.

Usage: python tools/build_pointer.py <emoji_u1f446.png> [out.png]

The source is Google's Noto Emoji 3D "backhand index pointing up" (Apache
2.0): github.com/googlefonts/noto-emoji, 3D/png/512/emoji_u1f446.png. Its
shading is gradient-mapped onto our palette, dark to light: borderOrange,
accent, accentSoft, then near-white, so the hand reads white with brand
colour in the shadows. Writes assets/ui/pointer.png by default; upload it
with mcp upload_image and put the id in SkinAssets.pointer.
"""

import sys

from PIL import Image, ImageFilter

# (lightness 0..1, colour), dark to light.
RAMP = [
    (0.0, (106, 42, 0)),  # borderOrange
    (0.18, (230, 110, 20)),  # accent, a little darker
    (0.42, (255, 176, 107)),  # accentSoft
    (0.68, (255, 228, 204)),
    (0.9, (255, 250, 245)),
    (1.0, (255, 255, 255)),
]


def ramp(t: float) -> tuple:
    for (a, ca), (b, cb) in zip(RAMP, RAMP[1:]):
        if t <= b:
            k = (t - a) / (b - a)
            return tuple(round(ca[i] + (cb[i] - ca[i]) * k) for i in range(3))
    return RAMP[-1][1]


def lightness(r: int, g: int, b: int) -> float:
    return 0.299 * r + 0.587 * g + 0.114 * b


def main() -> None:
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else "assets/ui/pointer.png"
    image = Image.open(src).convert("RGBA")
    image = image.crop(image.getchannel("A").getbbox())
    px = image.load()
    w, h = image.size
    # Shade from a slightly softened copy: the source's fine grain would
    # otherwise speckle across the colour steps.
    soft = image.filter(ImageFilter.GaussianBlur(1.5)).load()

    # By area, not raw lightness: t is the share of the hand darker than this
    # pixel, so each step of RAMP covers that share of the hand (its shading
    # is mostly light; raw lightness would leave the colours a thin rim).
    values = sorted(round(lightness(*soft[x, y][:3])) for y in range(h) for x in range(w) if px[x, y][3] > 200)
    below = {}
    for index, value in enumerate(values):
        below.setdefault(value, index)
    share = [0.0] * 256
    last = 0.0
    for value in range(256):
        if value in below:
            last = below[value] / len(values)
        share[value] = last
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = ramp(share[round(lightness(*soft[x, y][:3]))]) + (a,)
    image.save(out)
    print(f"Wrote {out} ({w}x{h})")


if __name__ == "__main__":
    main()
