"""Maakt eigen achtergronden voor Kadans (geen foto's van anderen, dus geen rechten of bronvermelding nodig).
Gebruik: python3 tools/maak_achtergronden.py  → assets/achtergronden/*.jpg (1080×2340, staand)."""
import os
import numpy as np
from PIL import Image, ImageFilter

W, H = 1080, 2340
UIT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'achtergronden')
ZAND, ZAND_D = np.array([237, 230, 218.]), np.array([19, 17, 14.])
GOUD, GOUD_L = np.array([162, 124, 74.]), np.array([217, 191, 146.])
KOFFIE, TAUPE = np.array([122, 90, 52.]), np.array([196, 174, 146.])
GRID = np.mgrid[0:H, 0:W].astype(np.float32)
Y, X = GRID[0] / H, GRID[1] / W


def noise(seed, schaal, w=W, h=H):
    """Zacht ruisveld tussen 0 en 1: som van willekeurige golven (kommagetal, dus geen trapjes in de lijnen)."""
    r = np.random.default_rng(seed)
    f = np.zeros((h, w), np.float32)
    for _ in range(6):
        k = r.uniform(0.35, 1.0) * 600 / schaal
        hoek = r.uniform(0, 6.28)
        f += r.uniform(0.4, 1) * np.sin((X * np.cos(hoek) * W + Y * np.sin(hoek) * H) / 1000 * k * 6.28 + r.uniform(0, 6.28))
    return (f - f.min()) / (f.max() - f.min() + 1e-6)


def glow(cx, cy, rx, ry):
    return np.exp(-(((X - cx) ** 2) / rx + ((Y - cy) ** 2) / ry))


def korrel(img, sterkte=5, seed=3):
    n = np.random.default_rng(seed).normal(0, sterkte, (H, W, 1)).astype(np.float32)
    return img + n


def bewaar(img, naam):
    os.makedirs(UIT, exist_ok=True)
    Image.fromarray(np.clip(korrel(img), 0, 255).astype(np.uint8)).save(os.path.join(UIT, naam + '.jpg'), quality=90)


def aura(donker):
    img = np.zeros((H, W, 3), np.float32) + (ZAND_D if donker else ZAND)
    img += glow(0.9, 0.05, 0.22, 0.12)[..., None] * ((GOUD_L - ZAND_D) * 0.28 if donker else (TAUPE - ZAND) * 0.9)
    img += glow(0.05, 0.95, 0.25, 0.14)[..., None] * ((KOFFIE - ZAND_D) * 0.22 if donker else (TAUPE - ZAND) * 0.7)
    return img


def mist_heuvels(donker):
    """Vier ruggen achter elkaar, steeds lichter en waziger, zoals mist boven de heide."""
    top, bodem = (np.array([42, 34, 26.]), ZAND_D) if donker else (np.array([225, 214, 196.]), np.array([196, 176, 148.]))
    img = np.zeros((H, W, 3), np.float32) + top
    img += Y[..., None] * (bodem - top)
    for i, (basis, amp, seed) in enumerate([(0.46, 0.05, 21), (0.56, 0.06, 22), (0.67, 0.07, 23), (0.80, 0.08, 24)]):
        r = np.random.default_rng(seed)
        golf = sum(r.uniform(0.4, 1) * np.sin(X * r.uniform(1, 2.6) * 6.28 + r.uniform(0, 6.28)) for _ in range(3)) / 2.2
        rug = basis + amp * golf
        masker = np.clip((Y - rug) * 90, 0, 1)[..., None]
        diep = (0.25 + 0.2 * i) if not donker else (0.18 + 0.12 * i)
        kleur = bodem * (1 - diep) + KOFFIE * diep if not donker else ZAND_D + (KOFFIE - ZAND_D) * (0.16 - 0.03 * i)
        img = img * (1 - masker) + kleur * masker
        mist = np.exp(-((Y - rug - 0.02) ** 2) / 0.004)[..., None] * (0.35 if not donker else 0.12)
        img += mist * ((255 - img) if not donker else (GOUD_L - img) * 0.4)
    return img


def glas_vlekken(donker):
    """Grote zachte kleurvlakken: ideaal achter matglas, geeft het glas iets om te breken."""
    img = np.zeros((H, W, 3), np.float32) + (ZAND_D if donker else ZAND)
    for cx, cy, rx, ry, kleur, s in [(0.8, 0.12, 0.10, 0.05, GOUD_L, 0.9), (0.15, 0.40, 0.14, 0.06, KOFFIE, 0.6),
                                      (0.85, 0.68, 0.12, 0.06, GOUD, 0.7), (0.2, 0.92, 0.16, 0.07, TAUPE, 0.8)]:
        g = glow(cx, cy, rx, ry)[..., None]
        img += g * ((kleur - ZAND_D) * s * 0.4 if donker else (kleur - ZAND) * s * 0.75)
    return img


def zonsopkomst(donker):
    """Van vroeg licht boven naar warm zand onder: voor 'Later lopen' en de rondleiding."""
    boven, onder = (np.array([58, 44, 34.]), np.array([19, 17, 14.])) if donker else (np.array([240, 214, 176.]), np.array([237, 230, 218.]))
    img = boven + Y[..., None] * (onder - boven)
    img += glow(0.5, 0.2, 0.25, 0.04)[..., None] * (np.array([255, 196, 120.]) - img) * (0.35 if donker else 0.5)
    return img


def main():
    for donker, s in ((False, 'licht'), (True, 'donker')):
        bewaar(aura(donker), 'aura_' + s)
        bewaar(mist_heuvels(donker), 'mist_heuvels_' + s)
        bewaar(glas_vlekken(donker), 'glas_vlekken_' + s)
        bewaar(zonsopkomst(donker), 'zonsopkomst_' + s)


if __name__ == '__main__':
    main()
