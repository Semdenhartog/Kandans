"""Maakt het abstracte beeld voor kadans.fit (hero en voet): golvende banen in espresso en goud,
zacht vervaagd, als looplijnen die door elkaar lopen. Eigen beeld, geen foto's van anderen.
Gebruik: python3 tools/maak_site_beeld.py  → site/beeld-hero.jpg en site/beeld-voet.jpg"""
import numpy as np
from PIL import Image, ImageFilter


def ribbons(w, h, seed, shift=0.0):
    """Een paar grote, zachte vormen met één scherpe lichtrand: rustig, met diepte (als door een lens)."""
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    x /= w
    y /= h
    img = np.zeros((h, w, 3), np.float32) + np.array([24, 19, 14], np.float32)
    glow = np.exp(-(((x - 0.7 - shift) ** 2) / 0.35 + ((y - 0.75) ** 2) / 0.3))
    img += glow[..., None] * np.array([60, 42, 20], np.float32)
    shapes = [  # (midden, amplitude, frequentie, breedte, kleur, sterkte)
        (0.30, 0.22, 0.55, 0.22, (150, 112, 62), 0.75),
        (0.78, 0.18, 0.75, 0.30, (217, 191, 146), 0.55),
        (0.55, 0.28, 0.45, 0.10, (240, 221, 182), 0.45),
    ]
    sharp = np.zeros((h, w), np.float32)
    for mid, amp, f, width, col, strength in shapes:
        ph = rng.uniform(0, 6.28)
        curve = mid + amp * np.sin(x * f * 6.28 + ph) + 0.35 * (x - 0.5 - shift) * (rng.uniform(-1, 1))
        d = y - curve
        band = 1 / (1 + np.exp(-d / (width * 0.18))) * np.exp(-(np.clip(d, 0, None) / width) ** 2)
        img = img * (1 - band[..., None] * strength) + band[..., None] * strength * np.array(col, np.float32) * (0.6 + 0.4 * x[..., None])
        sharp += np.exp(-(d / 0.0025) ** 2) * (0.4 + 0.6 * x)
    soft = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius=w / 70))
    arr = np.asarray(soft, np.float32)
    line = Image.fromarray(np.clip(sharp * 255, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius=1.2))
    arr += (np.asarray(line, np.float32) / 255.0)[..., None] * np.array([120, 100, 70], np.float32)
    # Vignet en lichte korrel.
    vig = 1 - 0.45 * (((x - 0.5) ** 2 + (y - 0.5) ** 2) / 0.5)
    arr *= vig[..., None]
    arr += np.random.default_rng(seed + 1).normal(0, 2.5, (h, w, 1))
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


ribbons(1920, 1200, 7).save('site/beeld-hero.jpg', quality=82, optimize=True, progressive=True)
ribbons(1920, 900, 11, shift=-0.2).save('site/beeld-voet.jpg', quality=80, optimize=True, progressive=True)
print('klaar')
