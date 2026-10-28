import numpy as np
from PIL import Image, ImageFilter, ImageDraw
src = Image.open('src/origineel.png').convert('RGB')
W = src.width
cx, cy = 626, 621            # midden van de tegel
tile = (48, 40, 1204, 1202)  # gemeten rand van de tegel
# 1. K en KADANS 8% groter (rond het midden van de tegel), de tegel zelf blijft gelijk.
f = 1.08
big = src.resize((round(W * f), round(W * f)), Image.LANCZOS)
ox, oy = round(cx * f - cx), round(cy * f - cy)
scaled = big.crop((ox, oy, ox + W, oy + W))
mask = Image.new('L', (W, W), 0)
ImageDraw.Draw(mask).rectangle((170, 260, 1085, 985), fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(35))
logo = Image.composite(scaled, src, mask)
logo.save('logo_8procent.png')
# 2. App-icoon: tegel sluit aan op de vorm van het icoon.
size = 1024
view = size * 72 / 108                 # zichtbaar deel van de laag
tw = tile[2] - tile[0]
s = 0.985 * view / tw                  # tegel = 98,5% van het zichtbare icoon
img = logo.resize((round(W * s), round(W * s)), Image.LANCZOS)
outside = (5, 5, 4)
fg = Image.new('RGB', (size, size), outside)
fg.paste(img, (round(size / 2 - cx * s), round(size / 2 - cy * s)))
fg.save('voorgrond.png')
Image.new('RGB', (size, size), outside).save('achtergrond.png')
# los icoon (oude launchers): vierkant rond de tegel
half = max(tile[2] - cx, cx - tile[0], tile[3] - cy, cy - tile[1]) + 6
logo.crop((cx - half, cy - half, cx + half, cy + half)).resize((size, size), Image.LANCZOS).save('icoon.png')
print('schaal', round(s, 4))
