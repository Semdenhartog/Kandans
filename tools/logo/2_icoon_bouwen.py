import numpy as np, cv2
from PIL import Image, ImageFilter

src = cv2.imread('src/origineel.png')
H, W = src.shape[:2]

# Maskers van K en tekst op de plek in het origineel.
def place(name, x0, y0):
    a = np.array(Image.open(name))[:, :, 3]
    m = np.zeros((H, W), np.uint8)
    # positie: zoek waar de bijgesneden afbeelding in het origineel hoort (zelfde offsets als bij uitsnijden)
    m[y0:y0 + a.shape[0], x0:x0 + a.shape[1]] = a
    return m

def offset(raw, x0, y0):
    a = np.array(Image.open(raw))[:, :, 3]
    ys, xs = np.nonzero(a > 8)
    return x0 + xs.min(), y0 + ys.min()

kx, ky = offset('k_raw.png', 320, 225)
tx, ty = offset('tekst_raw.png', 150, 860)
mask = np.maximum(place('k_raw.png', 320, 225), place('tekst_raw.png', 150, 860))
mask = cv2.dilate((mask > 20).astype(np.uint8) * 255, np.ones((45, 45), np.uint8))
filled = cv2.inpaint(src, mask, 21, cv2.INPAINT_TELEA)
# Ingevulde plek iets donkerder en zachter (leest als schaduw achter de K).
soft = cv2.GaussianBlur(mask.astype(np.float32) / 255, (0, 0), 12)[..., None]
# Korrel van echt marmer (hoogfrequent deel van een schone strook) in de ingevulde plek leggen.
f = src.astype(np.float32)
hp = f - cv2.GaussianBlur(f, (0, 0), 6)
strip = hp[110:860, 110:335]
tile = np.concatenate([strip, strip[:, ::-1]] * 3, 1)
tile = np.concatenate([tile, tile[::-1]], 0)[:H, :W]
pad = np.zeros_like(f); pad[:tile.shape[0], :tile.shape[1]] = tile
pad = np.roll(pad, (0, 0), (0, 1))
filled = (filled.astype(np.float32) + pad * soft * 0.9).clip(0, 255).astype(np.uint8)
c0, c1 = 175, 1080
bg = cv2.cvtColor(filled[c0:c1, c0:c1], cv2.COLOR_BGR2RGB)
bg = Image.fromarray(bg).resize((1024, 1024), Image.LANCZOS)
bg.save('achtergrond.png')
open('posities.txt', 'w').write(f'{kx} {ky} {tx} {ty}\n')
print('K op', kx, ky, 'tekst op', tx, ty)

# Ingevulde plek iets minder warm (de gloed van de K hoort bij de K, niet bij het marmer).
bgn = np.asarray(Image.open('achtergrond.png')).astype(np.float32)
m2 = cv2.resize(soft[c0:c1, c0:c1, 0], (1024, 1024))[..., None]
grey = bgn.mean(2, keepdims=True)
bgn = (bgn * (1 - 0.6 * m2) + grey * (0.6 * m2)) * (1 - 0.5 * m2)
Image.fromarray(bgn.clip(0, 255).astype(np.uint8)).save('achtergrond.png')

K = Image.open('k.png')

def k_layer(width_frac, size=1024, shadow=True, dy=0):
    w = int(size * width_frac)
    k = K.resize((w, round(K.height * w / K.width)), Image.LANCZOS)
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    x = (size - k.width) // 2
    y = (size - k.height) // 2 + dy
    if shadow:
        a = np.array(k)[:, :, 3]
        sh = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        s = Image.fromarray(np.dstack([np.zeros_like(a)] * 3 + [(a * 0.75).astype(np.uint8)]))
        sh.paste(s, (x, y + size // 90), s)
        sh = sh.filter(ImageFilter.GaussianBlur(size / 80))
        layer = Image.alpha_composite(layer, sh)
    layer.alpha_composite(k, (x, y))
    return layer

bg = Image.open('achtergrond.png').convert('RGBA')
fg = k_layer(0.44)
fg.save('voorgrond.png')
icon = Image.alpha_composite(bg, k_layer(0.58)).convert('RGB')
icon.save('icoon.png')
# monochroom: alleen de vorm van de K (Android kleurt hem zelf)
a = np.array(k_layer(0.44, shadow=False))[:, :, 3]
Image.fromarray(np.dstack([np.full_like(a, 255)] * 3 + [a])).save('monochroom.png')
