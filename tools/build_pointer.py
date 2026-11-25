"""Build the onboarding pointer: a white 3D hand, finger up, with soft coloured
light drifting through its shadows, as a looping flipbook.

Usage: python tools/build_pointer.py <emoji_u1f446.png> [out.png]

The source is Google's Noto Emoji 3D "backhand index pointing up" (Apache
2.0): github.com/googlefonts/noto-emoji, 3D/png/512/emoji_u1f446.png.

Roblox UI can't blend additively or mask one image by another, so the effect
is rendered here: a few blurry coloured balls (our palette) drift on looping
paths; each pixel's shadow takes the blend of the balls near it, and the
hand's light areas stay white. FRAMES frames go in one sheet, COLUMNS
across, in reading order; OnboardingHint cross-fades between them. Upload
the sheet with mcp upload_image and put the id in SkinAssets.pointer (and
the frame layout in OnboardingHint if it changes).

Needs: pip install pillow numpy
"""

import math
import sys

import numpy as np
from PIL import Image, ImageFilter

FRAMES = 20
COLUMNS = 5
FRAME_HEIGHT = 256  # px; 5 x 4 frames of 197 x 256 fit in 1024

# (colour, whole cycles per loop in x and y, phase in x and y, size in hand
# heights). Whole cycles, so the loop is seamless.
BALLS = [
    ((122, 92, 255), (1, 2), (0.0, 0.3), 0.34),  # purple
    ((255, 95, 168), (2, 1), (1.7, 0.9), 0.30),  # pink
    ((255, 138, 26), (1, 1), (3.1, 2.2), 0.38),  # accent orange
    ((242, 201, 76), (1, -2), (4.4, 1.3), 0.28),  # yellow
]
REACH = (0.32, 0.30)  # how far the balls wander from the hand's middle (x, y)
DEPTH = 0.8  # shadow curve: lower = more colour into the mid-tones


def main() -> None:
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else "assets/ui/pointer.png"

    image = Image.open(src).convert("RGBA")
    image = image.crop(image.getchannel("A").getbbox())
    image = image.resize((image.width * FRAME_HEIGHT // image.height, FRAME_HEIGHT), Image.LANCZOS)
    w, h = image.size
    alpha = np.asarray(image)[..., 3].astype(np.float32)

    # How shadowed each pixel is, 0 (lightest) to 1 (darkest), from a softened
    # copy so the source's grain doesn't speckle.
    soft = np.asarray(image.filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32) / 255
    lightness = 0.299 * soft[..., 0] + 0.587 * soft[..., 1] + 0.114 * soft[..., 2]
    solid = alpha > 200
    lo, hi = np.percentile(lightness[solid], 2), np.percentile(lightness[solid], 99)
    shade = (np.clip((hi - lightness) / (hi - lo), 0, 1) ** DEPTH)[..., None]

    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32) / h  # hand heights
    middle = (w / h / 2, 0.55)
    rows = math.ceil(FRAMES / COLUMNS)
    sheet = Image.new("RGBA", (w * COLUMNS, h * rows), (0, 0, 0, 0))
    for frame in range(FRAMES):
        t = frame / FRAMES * 2 * math.pi
        colour = np.zeros((h, w, 3), np.float32)
        weight = np.zeros((h, w), np.float32)
        for rgb, (fx, fy), (px, py), size in BALLS:
            bx = middle[0] + REACH[0] * math.sin(fx * t + px)
            by = middle[1] + REACH[1] * math.sin(fy * t + py)
            ball = np.exp(-((xs - bx) ** 2 + (ys - by) ** 2) / (2 * size**2))
            colour += ball[..., None] * np.array(rgb, np.float32)
            weight += ball
        colour /= np.maximum(weight, 1e-4)[..., None]  # the near balls' blend
        rgb = 255 * (1 - shade) + colour * shade  # white lights, coloured shadows
        pixels = np.dstack([rgb, alpha]).clip(0, 255).astype(np.uint8)
        sheet.paste(Image.fromarray(pixels, "RGBA"), ((frame % COLUMNS) * w, (frame // COLUMNS) * h))
    sheet.save(out)
    print(f"Wrote {out}: {FRAMES} frames of {w}x{h}, {COLUMNS} across ({sheet.width}x{sheet.height})")


if __name__ == "__main__":
    main()
