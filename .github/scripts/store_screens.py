#!/usr/bin/env python3
"""Maakt Play Store-schermafbeeldingen (1080 x 1920, staand 9:16) van de schermtest-plaatjes.

Google eist dat de lange kant hooguit 2x de korte kant is; de schermtest-plaatjes zijn langer.
We nemen het bovenste stuk in 9:16 (daar staat het belangrijkste) en vullen korte plaatjes aan
met de achtergrondkleur van de app.

Gebruik: store_screens.py <map met plaatjes> <uitvoermap>
"""
import pathlib
import sys

from PIL import Image

# Volgorde = volgorde in de Play Store.
CHOSEN = [
    ("01_vandaag", "1_beste_moment"),
    ("11_opnemen_bezig", "2_run_opnemen"),
    ("03_run_detail", "3_je_run"),
    ("15_na_je_run", "4_na_je_run"),
    ("04_routes", "5_routes"),
    ("05_coach", "6_coach"),
]
SIZE = (1080, 1920)
BACKGROUND = (9, 9, 11)  # RwColors.background (#09090B)


def to_store(src: pathlib.Path, dst: pathlib.Path) -> None:
    im = Image.open(src).convert("RGB")
    w, h = im.size
    target_h = round(w * SIZE[1] / SIZE[0])
    if h >= target_h:
        im = im.crop((0, 0, w, target_h))
    else:
        canvas = Image.new("RGB", (w, target_h), BACKGROUND)
        canvas.paste(im, (0, 0))
        im = canvas
    im.resize(SIZE, Image.LANCZOS).save(dst, "PNG", optimize=True)


def main() -> int:
    src_dir, out_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    made = 0
    for name, out in CHOSEN:
        src = src_dir / f"{name}.png"
        if not src.exists():
            print(f"Ontbreekt: {src.name}")
            continue
        to_store(src, out_dir / f"{out}.png")
        made += 1
    print(f"{made} Play Store-schermafbeeldingen gemaakt in {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
