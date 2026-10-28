from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT

GOLD_LIGHT = (245, 233, 210)
GOLD_MID = (226, 200, 142)
GOLD_DEEP = (193, 149, 94)
GOLD_DARK = (156, 103, 55)
BLACK = (15, 15, 15)
DARK = (14, 14, 14)


def rounded_square(draw, box, radius, fill):
    x0, y0, x1, y1 = box
    draw.rounded_rectangle((x0, y0, x1, y1), radius=radius, fill=fill)


def create_badge_icon(path: Path):
    size = 1024
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background dark rounded square
    rounded_square(draw, (40, 40, size - 40, size - 40), 220, BLACK)

    # Subtle sheen
    sheen = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    sheen_draw = ImageDraw.Draw(sheen)
    sheen_draw.rounded_rectangle((70, 60, size - 70, size - 70), radius=190, outline=(255, 255, 255, 28), width=12)
    img = Image.alpha_composite(img, sheen)

    # Stylized K shape - simple geometric ribbon version
    # Main left leg
    poly = [
        (350, 240),
        (470, 240),
        (700, 520),
        (600, 520),
        (430, 350),
        (370, 390),
        (370, 760),
        (250, 760),
        (250, 250),
        (350, 240),
    ]
    draw.polygon(poly, fill=(245, 233, 210, 255))

    # inner cut / highlight to mimic the elegant K profile
    cut = [
        (402, 300),
        (518, 300),
        (630, 420),
        (543, 420),
        (458, 340),
        (402, 300),
    ]
    draw.polygon(cut, fill=BLACK)

    # diagonal right stroke
    draw.polygon([
        (470, 240),
        (630, 240),
        (800, 440),
        (640, 440),
        (470, 240),
    ], fill=(207, 177, 119, 255))

    # accent face
    draw.polygon([
        (485, 310),
        (625, 310),
        (718, 410),
        (580, 410),
        (485, 310),
    ], fill=(245, 233, 210, 200))

    # A subtle dark counter-shape to emulate the ribbon cut
    draw.polygon([
        (560, 350),
        (650, 350),
        (710, 420),
        (620, 420),
        (560, 350),
    ], fill=(15, 15, 15, 220))

    img.save(path)


def create_mark(path: Path, size: int = 512):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # dark rounded square for the mark export
    rounded_square(draw, (20, 20, size - 20, size - 20), 110, BLACK)

    # draw K silhouette
    draw.polygon([
        (190, 90),
        (250, 90),
        (410, 255),
        (330, 255),
        (240, 170),
        (190, 210),
        (190, 420),
        (120, 420),
        (120, 90),
        (190, 90),
    ], fill=(232, 206, 153, 255))
    draw.polygon([
        (250, 90),
        (410, 90),
        (520, 200),
        (360, 200),
        (250, 90),
    ], fill=(201, 172, 110, 255))
    draw.polygon([
        (250, 90),
        (360, 90),
        (500, 230),
        (390, 230),
        (250, 90),
    ], fill=(245, 233, 210, 180))

    # dark slit to create the luxe ribbon cut
    draw.polygon([
        (315, 235),
        (405, 235),
        (470, 300),
        (380, 300),
        (315, 235),
    ], fill=BLACK)

    img.save(path)


def create_wordmark(path: Path, width: int = 1400, height: int = 420):
    img = Image.new('RGBA', (width, height), BLACK)
    draw = ImageDraw.Draw(img)

    # Prefer system font if available; otherwise fallback to default sans.
    font = None
    candidates = [
        '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
        '/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf',
        '/System/Library/Fonts/Supplemental/SFCompactDisplay-Bold.otf',
    ]
    for candidate in candidates:
        try:
            font = ImageFont.truetype(candidate, 150)
            break
        except Exception:
            continue
    if font is None:
        font = ImageFont.load_default()

    text = 'KADANS'
    bbox = draw.textbbox((0, 0), text, font=font)
    w = bbox[2] - bbox[0]
    h = bbox[3] - bbox[1]
    x = (width - w) / 2.0
    y = (height - h) / 2.0 - 10

    # gold gradient via horizontal line sampling
    for xpx in range(width):
        t = xpx / max(1, width - 1)
        r = int(245 + (173 - 245) * t)
        g = int(233 + (116 - 233) * t)
        b = int(210 + (70 - 210) * t)
        draw.line((xpx, 0, xpx, height), fill=(r, g, b, 255))

    # Clear text area by drawing text with a dark fill behind it
    draw.text((x, y), text, font=font, fill=(15, 15, 15, 255), stroke_width=0)
    # Draw the gold text on top with a slightly stylized letter spacing effect
    draw.text((x, y), text, font=font, fill=(236, 214, 174, 255))

    img.save(path)


def create_favicon(path: Path):
    create_mark(path, size=512)


if __name__ == '__main__':
    create_badge_icon(OUT / 'assets' / 'icon' / 'icon.png')
    create_mark(OUT / 'assets' / 'icon' / 'foreground.png', size=1024)
    Image.new('RGBA', (1024, 1024), BLACK).save(OUT / 'assets' / 'icon' / 'background.png')
    create_mark(OUT / 'site' / 'mark.png', size=1024)
    create_wordmark(OUT / 'site' / 'wordmark.png', width=1400, height=420)
    create_wordmark(OUT / 'site' / 'logo.png', width=1600, height=620)
    create_favicon(OUT / 'site' / 'favicon.png')
    # keep existing SVG assets as source-of-truth; these PNGs are generated exports
    print('Generated brand PNG exports in assets/icon and site.')
