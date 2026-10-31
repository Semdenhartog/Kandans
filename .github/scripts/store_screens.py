#!/usr/bin/env python3
"""Maakt Play Store-schermafbeeldingen (1080 x 1920, staand 9:16) van de schermtest-plaatjes.

Elk plaatje krijgt een donker-gouden achtergrond, een korte kop en de app in een telefoonframe.
Daarnaast (met --kaal) de oude, kale versie: het bovenste stuk van het scherm in 9:16.

Gebruik: store_screens.py <map met plaatjes> <uitvoermap>
"""
import pathlib
import sys

from PIL import Image

# Volgorde = volgorde in de Play Store.
CHOSEN = [
    ("60_donker_vandaag", "1_beste_moment", "Loop op het beste moment", "Weer, wind en buien: Kadans kiest wanneer je gaat."),
    ("11_opnemen_bezig", "2_run_opnemen", "Lopen met stem en kaart", "Tempo, rondes en je record als ghost-loper."),
    ("62_donker_run_detail", "3_je_run", "Alles over je run", "Kaart, tussentijden, hartslag en terugblik."),
    ("15_na_je_run", "4_na_je_run", "Medailles en records", "Elke run telt. Ook die in de regen."),
    ("63_donker_routes", "5_routes", "Routes met wind mee", "Tekenen, laten maken of als vorm op de kaart."),
    ("66_donker_coach", "6_coach", "Een coach die je runs kent", "Vraag alles over je training."),
]
FONTS = pathlib.Path(__file__).resolve().parents[2] / "assets" / "fonts"
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


def framed(src: pathlib.Path, dst: pathlib.Path, title: str, sub: str) -> None:
    """Donker-goud vlak met kop en de app in een telefoon die onderaan uit beeld loopt."""
    from PIL import ImageDraw, ImageFilter, ImageFont

    W, H = SIZE
    bg = Image.new("RGB", SIZE, BACKGROUND)
    # Verloop van warm donker naar zwart, met een zachte gouden gloed bovenin.
    top, bottom = (34, 26, 16), (9, 9, 11)
    d = ImageDraw.Draw(bg)
    for y in range(H):
        f = y / H
        d.line([(0, y), (W, y)], fill=tuple(round(top[i] * (1 - f) + bottom[i] * f) for i in range(3)))
    glow = Image.new("L", SIZE, 0)
    ImageDraw.Draw(glow).ellipse((W * 0.1, -380, W * 0.9, 520), fill=120)
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    bg = Image.composite(Image.new("RGB", SIZE, (253, 160, 60)), bg, glow.point(lambda v: v * 0.35))

    d = ImageDraw.Draw(bg)
    head = ImageFont.truetype(str(FONTS / "Saira-ExtraBold.ttf"), 78)
    body = ImageFont.truetype(str(FONTS / "DMSans-Medium.ttf"), 38)
    small = ImageFont.truetype(str(FONTS / "Saira-Bold.ttf"), 30)

    def center(text, font, y, fill):
        w = d.textlength(text, font=font)
        d.text(((W - w) / 2, y), text, font=font, fill=fill)

    center("KADANS", small, 96, (253, 160, 60))
    center(title, head, 150, (246, 236, 214))
    center(sub, body, 262, (196, 186, 166))

    # Telefoon: rand met afgeronde hoeken, scherm erin, schaduw eronder.
    pw, top_y, border, radius = 780, 380, 18, 70
    sw = pw - 2 * border
    shot = Image.open(src).convert("RGB")
    scale = sw / shot.width
    shot = shot.resize((sw, round(shot.height * scale)), Image.LANCZOS)
    sh = H - top_y + 40
    shot = shot.crop((0, 0, sw, min(shot.height, sh)))
    if shot.height < sh:
        pad = Image.new("RGB", (sw, sh), BACKGROUND)
        pad.paste(shot, (0, 0))
        shot = pad
    x0 = (W - pw) // 2
    shadow = Image.new("L", SIZE, 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x0 - 10, top_y + 20, x0 + pw + 10, H + 200), radius, fill=190)
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    bg = Image.composite(Image.new("RGB", SIZE, (0, 0, 0)), bg, shadow)
    d = ImageDraw.Draw(bg)
    d.rounded_rectangle((x0, top_y, x0 + pw, H + 200), radius, fill=(26, 24, 22), outline=(120, 96, 60), width=3)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw, sh + 200), radius - border, fill=255)
    bg.paste(shot, (x0 + border, top_y + border), mask)
    # Camera-gaatje.
    d.ellipse((W / 2 - 11, top_y + border + 14, W / 2 + 11, top_y + border + 36), fill=(12, 12, 12))
    bg.save(dst, "PNG", optimize=True)


def main() -> int:
    src_dir, out_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    kaal = "--kaal" in sys.argv
    out_dir.mkdir(parents=True, exist_ok=True)
    made = 0
    for name, out, title, sub in CHOSEN:
        src = src_dir / f"{name}.png"
        if not src.exists():
            print(f"Ontbreekt: {src.name}")
            continue
        if kaal:
            to_store(src, out_dir / f"{out}.png")
        else:
            framed(src, out_dir / f"{out}.png", title, sub)
        made += 1
    print(f"{made} Play Store-schermafbeeldingen gemaakt in {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
