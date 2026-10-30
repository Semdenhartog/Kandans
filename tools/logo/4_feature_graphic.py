"""Maakt de Play Store-feature graphic (1024x500) uit de gouden K van de Kickstarter-afbeelding.

Draaien vanuit de repo-root: python3 tools/logo/4_feature_graphic.py
Uitvoer: docs/merk/play-store-feature-graphic-1024x500.png
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 1024, 500
BRON = "docs/merk/kickstarter/projectafbeelding-1920x1080.png"
UIT = "docs/merk/play-store-feature-graphic-1024x500.png"
GOUD = (222, 196, 158)
ZACHT = (190, 172, 146)

bron = Image.open(BRON).convert("RGB")
schaal = 0.78 * H / bron.height
k = bron.resize((round(bron.width * schaal), round(bron.height * schaal)), Image.LANCZOS)

# Achtergrond: kleur van de rand van de bron, met de K links (midden van de K op x≈270).
rand = bron.getpixel((5, bron.height // 2))
doek = Image.new("RGB", (W, H), rand)
k_midden = round(960 * schaal)
links = 255 - k_midden
boven = (H - k.height) // 2
# Zachte overgang aan de rechterkant van de K-afbeelding.
masker = Image.new("L", k.size, 255)
d = ImageDraw.Draw(masker)
for y in range(60):  # ook boven en onder zacht laten overlopen
    v = round(255 * y / 60)
    d.line([(0, y), (k.width, y)], fill=v)
    d.line([(0, k.height - 1 - y), (k.width, k.height - 1 - y)], fill=v)
fade = 160
for x in range(fade):
    d.line([(k.width - fade + x, 0), (k.width - fade + x, k.height)], fill=255 - round(255 * x / fade))
doek.paste(k, (links, boven), masker)

teken = ImageDraw.Draw(doek)
saira = ImageFont.truetype("assets/fonts/Saira-Bold.ttf", 84)
dm = ImageFont.truetype("assets/fonts/DMSans-Medium.ttf", 30)
x = 500
naam = "KADANS"
# Ruime letterafstand zoals in het logo.
cx = x
for letter in naam:
    teken.text((cx, 170), letter, font=saira, fill=GOUD)
    cx += saira.getlength(letter) + 12
teken.text((x + 4, 292), "Loop op het beste moment", font=dm, fill=ZACHT)
doek.save(UIT, optimize=True)
assert cx < W - 40, f"naam past niet: {cx}"
print(UIT, doek.size, "naam eindigt op", round(cx))
