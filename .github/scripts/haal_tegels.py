"""Haalt PDOK-kaarttegels (grijs + luchtfoto) op rond de Amsterdamse voorbeeldroutes van de schermtests.

Alleen voor screens.yml: zo tonen kaarten in de schermafbeeldingen echte straten.
De tegels komen niet in de repo (test_screens/tegels staat in .gitignore).
"""
import math
import os
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

UIT = sys.argv[1] if len(sys.argv) > 1 else 'test_screens/tegels'
GRIJS = 'https://service.pdok.nl/brt/achtergrondkaart/wmts/v2_0/grijs/EPSG:3857/{z}/{x}/{y}.png'
FOTO = 'https://service.pdok.nl/hwh/luchtfotorgb/wmts/v1_0/Actueel_orthoHR/EPSG:3857/{z}/{x}/{y}.jpeg'

# (zuid, west, noord, oost): Amsterdamse Bos, Vondelpark, Amstel (met wat marge).
GEBIEDEN = [
    (52.300, 4.822, 52.340, 4.890),
    (52.350, 4.850, 52.370, 4.892),
    (52.288, 4.885, 52.362, 4.935),
]


def tegel(lat, lon, z):
    n = 2 ** z
    x = int((lon + 180) / 360 * n)
    y = int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)
    return x, y


def taken():
    seen = set()
    for z in range(11, 18):
        for i, (s, w, n_, e) in enumerate(GEBIEDEN):
            if z == 17 and i != 1:  # heel dichtbij alleen het (kleine) Vondelpark
                continue
            x0, y0 = tegel(n_, w, z)
            x1, y1 = tegel(s, e, z)
            for x in range(x0, x1 + 1):
                for y in range(y0, y1 + 1):
                    for soort in ('grijs', 'foto'):
                        if soort == 'foto' and z > 16:
                            continue
                        k = (soort, z, x, y)
                        if k not in seen:
                            seen.add(k)
                            yield k


def haal(k):
    soort, z, x, y = k
    pad = os.path.join(UIT, soort, str(z), str(x), f"{y}.{'png' if soort == 'grijs' else 'jpg'}")
    if os.path.exists(pad):
        return 0
    url = (GRIJS if soort == 'grijs' else FOTO).format(z=z, x=x, y=y)
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Kadans-schermtest (github.com/Semdenhartog/Kandans)'})
        data = urllib.request.urlopen(req, timeout=20).read()
    except Exception as ex:  # noqa: BLE001
        print('mislukt', url, ex)
        return 0
    os.makedirs(os.path.dirname(pad), exist_ok=True)
    with open(pad, 'wb') as f:
        f.write(data)
    return 1


if __name__ == '__main__':
    lijst = list(taken())
    with ThreadPoolExecutor(8) as ex:
        n = sum(ex.map(haal, lijst))
    print(f'{n} van {len(lijst)} tegels opgehaald')
