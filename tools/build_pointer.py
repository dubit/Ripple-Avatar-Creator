"""Build the onboarding pointer: a big pointing-hand cursor, finger down.

Usage: python tools/build_pointer.py <msr.ttf> [out.png]

<msr.ttf> is Material Symbols Rounded instanced as in build_icons.py. The
glyph is pan_tool_alt (the "link" hand cursor), turned to point down, white
with a dark outline so it reads on any floor or outfit. Writes 256px
(default assets/ui/pointer.png); upload it with mcp upload_image and put the
id in SkinAssets.pointer.
"""

import sys

from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFilter, ImageFont

CELL = 256
SUPERSAMPLE = 4
OUTLINE = 0.06  # of the cell
GLYPH = "pan_tool_alt"


def main() -> None:
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else "assets/ui/pointer.png"
    codepoints = {name: cp for cp, name in TTFont(src).getBestCmap().items()}

    big = CELL * SUPERSAMPLE
    inner = int(big * (1 - 2 * OUTLINE))  # glyph size, leaving room for the outline
    font = ImageFont.truetype(src, inner)
    fill = Image.new("L", (big, big), 0)
    pad = (big - inner) // 2
    ImageDraw.Draw(fill).text((pad, pad + inner), chr(codepoints[GLYPH]), font=font, fill=255, anchor="ls")
    fill = fill.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    fill = fill.rotate(180)

    outline = fill
    for _ in range(4):  # grow by OUTLINE in four steps (big MaxFilters are slow)
        outline = outline.filter(ImageFilter.MaxFilter(int(big * OUTLINE / 2) | 1))

    image = Image.new("RGBA", (big, big), (26, 26, 26, 0))
    image.putalpha(outline)
    white = Image.new("RGBA", (big, big), (255, 255, 255, 255))
    image.paste(white, (0, 0), fill)
    image.resize((CELL, CELL), Image.LANCZOS).save(out)
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
