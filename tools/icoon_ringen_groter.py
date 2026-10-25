"""Kadans-icoon: ringen groter maken in verhouding tot het icoon.

Splitst de voorgrond in vaartlijnen en ringen, schaalt de ringen op (en de
vaartlijnen iets af) en zet ze binnen de veilige cirkel van een Android
adaptive icon (zichtbaar: ~683 px op een laag van 1024 px).
Gebruik: python3 groter.py <map met assets/icon> <uitvoermap>
Let op: werkt op het ORIGINELE icoon (coordinaten hieronder); niet nogmaals draaien op het resultaat.
"""
import sys
from PIL import Image

SRC, OUT = sys.argv[1], sys.argv[2]
RING_SCALE, LINE_SCALE, GAP = 1.15, 0.75, 6
LINES = (204, 366)   # x-bereik vaartlijnen
RINGS = (383, 820)   # x-bereik ringen
Y0, Y1 = 320, 704    # y-bereik van het geheel; ringen vullen dit
RING_CY = (Y0 + Y1) / 2


def relayout(layer: Image.Image) -> Image.Image:
    lines = layer.crop((LINES[0], 0, LINES[1], 1024))
    rings = layer.crop((RINGS[0], Y0, RINGS[1], Y1))
    lw, rw = int(lines.width * LINE_SCALE), int(rings.width * RING_SCALE)
    rh = int(rings.height * RING_SCALE)
    lines = lines.resize((lw, int(1024 * LINE_SCALE)), Image.LANCZOS)
    rings = rings.resize((rw, rh), Image.LANCZOS)
    total = lw + GAP + rw
    x = (1024 - total) // 2
    out = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    ry = int(512 - rh / 2)
    out.alpha_composite(rings, (x + lw + GAP, ry))
    # vaartlijnen houden dezelfde hoogte t.o.v. het ringmidden
    ly = int(512 - RING_CY * LINE_SCALE + (RING_CY - 512) * (RING_SCALE - LINE_SCALE) * 0)
    ly = int(512 + (0 - RING_CY) * LINE_SCALE + (RING_CY - 512) * 0)
    # lijnmidden (y≈546) ligt in het origineel 34 px onder het ringmidden
    line_mid_src = (488 + 605) / 2
    target_mid = 512 + (line_mid_src - RING_CY) * RING_SCALE
    ly = int(target_mid - line_mid_src * LINE_SCALE)
    out.alpha_composite(lines, (x, ly))
    return out


fg = relayout(Image.open(f"{SRC}/foreground.png").convert("RGBA"))
fg.save(f"{OUT}/foreground.png")
mono = relayout(Image.open(f"{SRC}/monochrome.png").convert("RGBA"))
mono.save(f"{OUT}/monochrome.png")

# Oud (niet-adaptief) icoon: achtergrond + voorgrond iets groter, vult het vierkant meer
bg = Image.open(f"{SRC}/background.png").convert("RGBA")
big = fg.resize((1180, 1180), Image.LANCZOS).crop((78, 78, 1102, 1102))
icon = bg.copy()
icon.alpha_composite(big)
icon.convert("RGB").save(f"{OUT}/icon.png")
print("klaar", fg.getbbox())
