"""Build the white-fill HUD icon PNGs from the Material Symbols Rounded font.

Usage: python tools/build_icons.py <MaterialSymbolsRounded.(ttf|woff2)> [out_dir]

Writes one 128px PNG per icon to out_dir (default assets/ui/icons). Upload
new ones via Studio's Asset Manager and add their IMAGE asset IDs to
Source/ReplicatedFirst/views/SkinAssets.luau.

Needs: pip install fonttools brotli pillow

Each glyph fills its 128px image the way CSS `font-size: N` fills an N-px
box, so an Icon sized N design px matches the design.
"""

import os
import sys

from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ICONS = (
    "apparel storefront checkroom arrow_back chevron_left chevron_right expand_less close "
    "search shopping_basket add_shopping_cart remove_shopping_cart toll person_add cloud_upload restart_alt "
    "undo remove delete delete_sweep star visibility bookmark_add add_circle edit "
    "add_business lock link ios_share content_copy check check_circle landscape "
    "flight "
    "accessibility_new directions_walk directions_run sports_gymnastics paragliding stairs pool emoji_people"
).split()

CELL = 128
SUPERSAMPLE = 8


def main() -> None:
    src = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "assets/ui/icons"
    os.makedirs(out_dir, exist_ok=True)

    font_file = TTFont(src)
    font_file.flavor = None  # woff2 -> plain sfnt so Pillow/FreeType can read it
    ttf_path = os.path.join(out_dir, ".tmp.ttf")
    font_file.save(ttf_path)
    codepoints = {name: cp for cp, name in font_file.getBestCmap().items()}

    missing = [name for name in ICONS if name not in codepoints]
    if missing:
        sys.exit(f"Font is missing glyphs: {missing}")

    big = CELL * SUPERSAMPLE
    font = ImageFont.truetype(ttf_path, big)  # font size == em box == image

    for name in ICONS:
        mask = Image.new("L", (big, big), 0)
        # Material Symbols glyphs sit on a 0..em box above the baseline.
        ImageDraw.Draw(mask).text((0, big), chr(codepoints[name]), font=font, fill=255, anchor="ls")
        # Close hairline seams where the font's overlapping contours meet.
        mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
        mask = mask.resize((CELL, CELL), Image.LANCZOS)
        glyph = Image.new("RGBA", (CELL, CELL), (255, 255, 255, 0))
        glyph.putalpha(mask)
        glyph.save(os.path.join(out_dir, f"{name}.png"))

    del font
    os.remove(ttf_path)
    print(f"Wrote {len(ICONS)} icons to {out_dir}")


if __name__ == "__main__":
    main()
