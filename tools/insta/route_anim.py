#!/usr/bin/env python3
"""Route-animaties voor Instagram (9:16, 1080x1920, 30 fps) - strak, donker, goud.

A) route_teken.mp4  (9 s): gouden lijn tekent de echte route "Rondje bos", gloed + vonken,
   tellers lopen mee, finish-flits, dan "Jouw rondje. Beter moment." + knop STUUR WEER.
   Tijdens de eindkaart loopt er een lichtpunt over de lijn (de gloed-variant).
B) route_gloed.mp4  (6 s, naadloze loop): route met twee kometen en een rustige ademgloed.

Gebruik (vanuit de repo-root):  python3 tools/insta/route_anim.py [teken|gloed|beide] [uitmap]
Alleen PIL + numpy + ffmpeg. Route = _bosPoly uit test_screens/screens_test.dart (Amsterdamse Bos).
Cijfers (afstand uit de route, tijd = voorbeeld op 5:45/km) zijn een voorbeeld.
"""
import math, re, subprocess, sys, os, wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

F = 'assets/fonts/'
W, H, FPS = 1080, 1920, 30
GOLD = np.array([217, 191, 146], float)
HOT = np.array([255, 243, 214], float)
AMB = np.array([228, 160, 70], float)
INK = (26, 20, 16)
CREAM = (241, 233, 220)
GOLDI = (217, 191, 146)
rng = np.random.default_rng(11)


def font(n, s):
    return ImageFont.truetype(F + n, s)


# ---------- route ----------
def decode(s):
    pts, i, lat, lon = [], 0, 0, 0
    while i < len(s):
        for k in (0, 1):
            res = shift = 0
            while True:
                b = ord(s[i]) - 63
                i += 1
                res |= (b & 31) << shift
                shift += 5
                if b < 32:
                    break
            d = ~(res >> 1) if res & 1 else res >> 1
            if k == 0:
                lat += d
            else:
                lon += d
        pts.append((lat / 1e5, lon / 1e5))
    return pts


def haversine_m(pts):
    t = 0.0
    for (a, b), (c, d) in zip(pts[:-1], pts[1:]):
        p1, p2 = math.radians(a), math.radians(c)
        dl = math.radians(d - b)
        h = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
        t += 2 * 6371000 * math.asin(math.sqrt(h))
    return t


def load_route(box):
    src = open('test_screens/screens_test.dart', encoding='utf8').read()
    poly = re.search(r"_bosPoly = '([^']+)'", src).group(1).replace('\\\\', '\\')
    pts = decode(poly)
    meters = haversine_m(pts)
    lat0 = sum(p[0] for p in pts) / len(pts)
    xy = np.array([[p[1] * math.cos(math.radians(lat0)), -p[0]] for p in pts])
    xy -= xy.min(0)
    x0, y0, x1, y1 = box
    sc = min((x1 - x0) / xy[:, 0].max(), (y1 - y0) / xy[:, 1].max())
    xy *= sc
    xy[:, 0] += x0 + ((x1 - x0) - xy[:, 0].max()) / 2
    xy[:, 1] += y0 + ((y1 - y0) - xy[:, 1].max()) / 2

    def resample(a):
        seg = np.hypot(*np.diff(a, axis=0).T)
        cum = np.r_[0, np.cumsum(seg)]
        s = np.arange(0, cum[-1], 1.0)
        return np.c_[np.interp(s, cum, a[:, 0]), np.interp(s, cum, a[:, 1])]

    d = resample(xy)
    k = np.exp(-0.5 * (np.arange(-45, 46) / 14.0) ** 2)
    k /= k.sum()
    sm = np.c_[np.convolve(np.pad(d[:, 0], 45, mode='edge'), k, 'valid'),
               np.convolve(np.pad(d[:, 1], 45, mode='edge'), k, 'valid')]
    return resample(sm), meters


# ---------- hulpjes ----------
def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def ease_draw(t):
    # begint rustig, snelt op, remt voor de finish af
    t = min(max(t, 0.0), 1.0)
    return 0.5 - 0.5 * math.cos(math.pi * (0.88 * t + 0.12 * t * t * (3 - 2 * t)))


class Scene:
    def __init__(self, route, pad=190):
        self.r = route
        self.pad = pad
        x0, y0 = route.min(0) - pad
        x1, y1 = route.max(0) + pad
        self.ox, self.oy = int(x0), int(y0)
        self.rw, self.rh = int(x1 - x0), int(y1 - y0)
        self.loc = route - [self.ox, self.oy]
        self.n = len(route)
        self.bg0 = self._bg()
        yy, xx = np.mgrid[0:H, 0:W]
        d = np.hypot((xx - W / 2) / (W * 0.75), (yy - H * 0.47) / (H * 0.62))
        self.vig = np.clip(1.08 - 0.9 * d ** 1.7, 0.18, 1.0).astype(np.float32)[..., None]
        self.ghost = self._mask(self.loc[:], 3)

    def _bg(self):
        im = Image.open('site/foto/heide.jpg').convert('RGB')
        cw = int(im.height * W / H)
        cx = int(im.width * 0.70)
        cx = min(max(cx, cw // 2), im.width - cw // 2)
        im = im.crop((cx - cw // 2, 0, cx + cw // 2, im.height)).resize((int(W * 1.12), int(H * 1.12)), Image.LANCZOS)
        im = im.filter(ImageFilter.GaussianBlur(4))
        a = np.asarray(im).astype(np.float32) / 255
        lum = a.mean(2, keepdims=True)
        a = a * 0.45 + lum * 0.55  # bijna monochroom
        a = a * np.array([0.40, 0.34, 0.27], np.float32) * 1.15 + np.array([0.020, 0.016, 0.012], np.float32)
        return Image.fromarray((np.clip(a, 0, 1) * 255).astype('uint8'))

    def bg(self, t, tot):
        return self.bgz(1.0 + 0.045 * (t / tot))

    def bgz(self, z):
        w, h = int(W * 1.12 / z), int(H * 1.12 / z)
        x, y = (self.bg0.width - w) // 2, (self.bg0.height - h) // 2
        im = self.bg0.crop((x, y, x + w, y + h)).resize((W, H), Image.BILINEAR)
        return np.asarray(im).astype(np.float32)

    def _mask(self, pts, width, ss=2):
        im = Image.new('L', (self.rw * ss, self.rh * ss), 0)
        if len(pts) > 1:
            ImageDraw.Draw(im).line([(float(x * ss), float(y * ss)) for x, y in pts], fill=255,
                                    width=int(width * ss), joint='curve')
        return np.asarray(im.resize((self.rw, self.rh), Image.BOX)).astype(np.float32) / 255

    def blur(self, m, r):
        im = Image.fromarray((np.clip(m, 0, 1) * 255).astype('uint8'))
        if r > 14:
            sm = im.resize((self.rw // 2, self.rh // 2), Image.BILINEAR).filter(ImageFilter.GaussianBlur(r / 2))
            im = sm.resize((self.rw, self.rh), Image.BILINEAR)
        else:
            im = im.filter(ImageFilter.GaussianBlur(r))
        return np.asarray(im).astype(np.float32) / 255

    def glow_rgb(self, core, hot, strength=1.0):
        """core/hot: maskers (0..1). Geeft RGB-bijdrage (additief) incl. gloed."""
        g = (1.15 * self.blur(core, 7) + 0.75 * self.blur(core, 24) + 0.50 * self.blur(core, 64)) * strength
        out = (core[..., None] * GOLD + g[..., None] * AMB * 0.62)
        h = hot
        gh = 1.2 * self.blur(h, 9) + 0.8 * self.blur(h, 30)
        out += h[..., None] * HOT * 1.0 + gh[..., None] * HOT * 0.42 * strength
        return out

def add_region(sc, frame, rgb):
    y0, x0 = max(sc.oy, 0), max(sc.ox, 0)
    ry0, rx0 = y0 - sc.oy, x0 - sc.ox
    h = min(sc.rh - ry0, H - y0)
    w = min(sc.rw - rx0, W - x0)
    frame[y0:y0 + h, x0:x0 + w] += rgb[ry0:ry0 + h, rx0:rx0 + w]


def point_glow(sc, pos, radius, color, amount):
    """Zachte gloed rond een punt (lokale regio-coördinaten)."""
    m = np.zeros((sc.rh, sc.rw), np.float32)
    x, y = pos
    r = int(radius * 2.4)
    xs0, xs1 = max(int(x - r), 0), min(int(x + r), sc.rw)
    ys0, ys1 = max(int(y - r), 0), min(int(y + r), sc.rh)
    if xs1 <= xs0 or ys1 <= ys0:
        return m[..., None] * color
    yy, xx = np.mgrid[ys0:ys1, xs0:xs1]
    d2 = ((xx - x) ** 2 + (yy - y) ** 2) / (radius ** 2)
    m[ys0:ys1, xs0:xs1] = np.exp(-d2) * amount
    return m[..., None] * color


def comet_mask(sc, a, ci, width, bands=9):
    """Lichtkomeet: staart loopt vloeiend uit (hoogste helderheid bij de kop)."""
    out = np.zeros((sc.rh, sc.rw), np.float32)
    if ci - a < 4:
        return out
    edges = np.linspace(a, ci, bands + 1).astype(int)
    for b in range(bands):
        lo, hi_ = edges[b], edges[b + 1]
        k = ((b + 1) / bands) ** 2.2
        out = np.maximum(out, sc._mask(sc.loc[lo:hi_ + 2], width * (0.55 + 0.45 * (b + 1) / bands)) * k)
    return out


def text_layer(w, h, items):
    """items: (x, y, tekst, font, kleur) -> RGBA numpy (alpha 0..1, rgb 0..255)."""
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for x, y, t, f, c in items:
        d.text((x, y), t, font=f, fill=c + (255,))
    a = np.asarray(im).astype(np.float32)
    return a[..., :3], a[..., 3:] / 255


def blit(frame, layer, alpha, dy=0):
    rgb, a = layer
    a = a * alpha
    if dy:
        a = np.roll(a, int(dy), axis=0)
        rgb = np.roll(rgb, int(dy), axis=0)
    frame[:] = frame * (1 - a) + rgb * a


def grain(frame, amt=5.5):
    frame += rng.normal(0, amt, frame.shape[:2]).astype(np.float32)[..., None]


def fmt_km(m):
    return f"{m / 1000:.1f}".replace('.', ',')


def fmt_time(s):
    s = int(s)
    return f"{s // 3600}:{(s % 3600) // 60:02d}:{s % 60:02d}"


class Embers:
    def __init__(self):
        self.p = np.zeros((0, 6), np.float32)  # x,y,vx,vy,life,max

    def emit(self, pos, n, dirv=None):
        if n <= 0:
            return
        a = rng.uniform(0, 2 * np.pi, n)
        sp = rng.uniform(0.4, 2.6, n)
        vx = np.cos(a) * sp
        vy = np.sin(a) * sp - 0.7
        life = rng.uniform(16, 44, n)
        self.p = np.vstack([self.p, np.c_[np.full(n, pos[0]), np.full(n, pos[1]), vx, vy, life, life].astype(np.float32)])

    def step(self):
        if len(self.p) == 0:
            return
        self.p[:, 0] += self.p[:, 2]
        self.p[:, 1] += self.p[:, 3]
        self.p[:, 2:4] *= 0.965
        self.p[:, 4] -= 1
        self.p = self.p[self.p[:, 4] > 0]

    def mask(self, sc):
        im = Image.new('L', (sc.rw, sc.rh), 0)
        d = ImageDraw.Draw(im)
        for x, y, vx, vy, life, mx in self.p:
            v = int(255 * (life / mx) ** 1.2)
            r = 1.0 + 1.4 * (life / mx)
            d.ellipse((x - r, y - r, x + r, y + r), fill=v)
        return np.asarray(im).astype(np.float32) / 255


# ---------- audio ----------
def write_wav(path, sig, sr=44100):
    sig = np.clip(sig, -1, 1)
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(sr)
        st = np.c_[sig[0], sig[1]] if isinstance(sig, tuple) else np.c_[sig, sig]
        w.writeframes((st * 32767).astype('<i2').tobytes())


def audio_teken(dur, sr=44100):
    n = int(dur * sr)
    t = np.arange(n) / sr
    env_in = np.clip(t / 0.8, 0, 1)
    env_out = np.clip((dur - t) / 1.2, 0, 1)
    pad = (np.sin(2 * np.pi * 73.42 * t) * 0.20 + np.sin(2 * np.pi * 110.0 * t) * 0.14
           + np.sin(2 * np.pi * 146.83 * t + 0.5 * np.sin(2 * np.pi * 0.2 * t)) * 0.07) * env_in * env_out
    # riser tijdens het tekenen (0.5 - 5.6 s): ruis met oplopende frequentie + glijtoon
    rs, re_ = 0.5, 5.6
    u = np.clip((t - rs) / (re_ - rs), 0, 1)
    amp = (np.sin(np.pi * np.clip(u, 0, 1)) ** 1.5) * ((t >= rs) & (t <= re_))
    f_sweep = 220 * (4 ** (u ** 1.4))
    ph = 2 * np.pi * np.cumsum(f_sweep) / sr
    sweep = np.sin(ph) * 0.10 * amp + np.sin(ph * 2.0) * 0.03 * amp
    noise = rng.normal(0, 1, n)
    k = 1 - np.exp(-2 * np.pi * (300 + 6000 * u ** 2) / sr)
    lp = np.zeros(n)
    y = 0.0
    for i in range(n):
        y += k[i] * (noise[i] - y)
        lp[i] = y
    shimmer = lp * 0.9 * amp
    sig = pad + sweep + shimmer
    # finish: zachte klok + lage dreun op 5.6 s
    def hit(t0, f0, dec, a, inh=(1, 2.76, 5.4, 8.9)):
        tt = np.clip(t - t0, 0, None)
        s = np.zeros(n)
        for j, m in enumerate(inh):
            s += np.sin(2 * np.pi * f0 * m * tt) * np.exp(-tt * dec * (1 + 0.7 * j)) / (1 + 0.8 * j)
        return s * a * (t >= t0)
    sig += hit(5.6, 659.25, 1.3, 0.16)
    sig += hit(5.6, 55.0, 3.0, 0.5, inh=(1,)) * 1.0
    sig += hit(6.55, 987.77, 2.2, 0.05)
    peak = np.abs(sig).max()
    return sig / peak * 0.72


def audio_loop(dur, sr=44100):
    n = int(dur * sr)
    t = np.arange(n) / sr
    f = lambda c: c / dur  # hele aantallen perioden -> naadloos
    lfo = 0.65 + 0.35 * np.sin(2 * np.pi * t / dur)
    sig = (np.sin(2 * np.pi * f(440) * t) * 0.22 + np.sin(2 * np.pi * f(660) * t) * 0.14 * lfo
           + np.sin(2 * np.pi * f(882) * t) * 0.07 * (1.3 - lfo))
    for k in (0.0, 0.5):  # zachte tik als een komeet aan de start passeert
        tt = (t / dur - k) % 1.0 * dur
        sig += np.sin(2 * np.pi * f(1980) * t) * np.exp(-tt * 9) * 0.05
    return sig / np.abs(sig).max() * 0.5


# ---------- ffmpeg ----------
def open_ffmpeg(out, wav, fps=FPS):
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(fps),
           '-i', '-', '-i', wav, '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '17', '-pix_fmt', 'yuv420p',
           '-profile:v', 'high', '-movflags', '+faststart', '-c:a', 'aac', '-b:a', '192k', '-shortest', out]
    return subprocess.Popen(cmd, stdin=subprocess.PIPE)


STILLS = {int(x) for x in os.environ.get('STILLS', '').split(',') if x}
_CUR = [0]


def push(p, frame):
    if STILLS:
        if _CUR[0] in STILLS:
            Image.fromarray(np.clip(frame, 0, 255).astype('uint8')).save(f'/tmp/route_anim/still_{_CUR[0]:03d}.png')
        _CUR[0] += 1
        return
    p.stdin.write(np.clip(frame, 0, 255).astype('uint8').tobytes())


# ---------- A: tekenen ----------
def render_teken(outdir):
    DUR = 9.0
    NF = int(DUR * FPS)
    route, meters = load_route((100, 520, W - 100, 1330))
    sc = Scene(route)
    n = sc.n
    T_START, T_DRAW, T_FIN = 0.55, 5.55, 5.6
    mono = font('DejaVuSansMono.ttf', 28)
    mono_s = font('DejaVuSansMono.ttf', 24)
    kop = font('Saira-ExtraBold.ttf', 112)
    num = font('Saira-Bold.ttf', 86)
    btn_f = font('DejaVuSansMono.ttf', 34)
    L_head1 = text_layer(W, H, [(86, 262, "Jouw rondje.", kop, CREAM)])
    L_head2 = text_layer(W, H, [(86, 386, "Beter moment.", kop, GOLDI)])
    L_lab = text_layer(W, H, [(90, 206, "01   RONDJE BOS", mono, GOLDI)])
    L_hud = text_layer(W, H, [(90, 1432, "AFSTAND", mono_s, (150, 138, 120)), (600, 1432, "TIJD", mono_s, (150, 138, 120))])
    bw, bh, bx, by = 600, 108, 90, 1440
    btn = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(btn)
    bd.rectangle((bx, by, bx + bw, by + bh), fill=(26, 20, 16, 255), outline=(217, 191, 146, 255), width=2)
    bd.rectangle((bx + bw - bh + 26, by + 26, bx + bw - 26, by + bh - 26), fill=(217, 191, 146, 255))
    bd.text((bx + 38, by + bh / 2 - 22), "STUUR WEER", font=btn_f, fill=(241, 233, 220, 255))
    bd.text((bx, by + bh + 34), "KADANS.APP   NU VOOR ANDROID", font=mono_s, fill=(150, 138, 120, 255))
    ba = np.asarray(btn).astype(np.float32)
    L_btn = (ba[..., :3], ba[..., 3:] / 255)

    wav = os.path.join(outdir, '_a.wav')
    write_wav(wav, audio_teken(DUR))
    out = os.path.join(outdir, 'route_teken.mp4')
    ff = open_ffmpeg(out, wav)
    emb = Embers()
    seconds_total = meters / 1000 * 345  # voorbeeld: 5:45 per km

    for fi in range(NF):
        t = fi / FPS
        frame = sc.bg(t, DUR) * sc.vig
        u = ease_draw((t - T_START) / (T_DRAW - T_START)) if t >= T_START else 0.0
        head = u * (n - 1)
        hi = int(head)
        # hartslag van de hele scène na de finish (flits) + gloed
        fin = t - T_FIN
        flash = math.exp(-fin * 3.2) if fin >= 0 else 0.0
        strength = 1.0 + 0.9 * flash
        # eindfase: kometen over de volledige route
        endphase = smooth((t - 6.2) / 0.8)
        # spookroute
        ghost = sc.ghost * (0.16 * smooth(t / 0.7))
        core = np.zeros_like(ghost)
        hot = np.zeros_like(ghost)
        if hi > 2:
            core = sc._mask(sc.loc[:hi + 1], 6) * (1 - 0.5 * smooth((t - 6.0) / 0.8))
            hl = 150
            a = max(0, hi - hl)
            hot = sc._mask(sc.loc[a:hi + 1], 9)
            # warme verloop: staart van de hot-lijn dooft naar goud
            hot = hot * 0.0 + sc._mask(sc.loc[max(0, hi - 60):hi + 1], 9) * 1.0 + 0.45 * sc._mask(sc.loc[a:max(0, hi - 60) + 1], 8)
        if t >= T_FIN and endphase > 0:
            # komeet loopt over de voltooide lijn
            for off, spd in ((0.0, 0.55), (0.5, 0.55)):
                cp = ((t - T_FIN) * spd * 0.3 + off) % 1.0
                ci = int(cp * (n - 1))
                tail = 220
                a = max(0, ci - tail)
                fadeio = min(1.0, cp / 0.04, (1 - cp) / 0.04)
                hot = np.maximum(hot, comet_mask(sc, a, ci, 9) * 0.95 * fadeio * endphase)
        rgb = sc.glow_rgb(np.clip(core, 0, 1), np.clip(hot, 0, 1), strength=strength)
        rgb += ghost[..., None] * np.array([200, 190, 170], np.float32)
        # kop-gloed + start-ring
        sx, sy = sc.loc[0]
        ignite = smooth((t - 0.1) / 0.35)
        rgb += point_glow(sc, (sx, sy), 22, HOT, 0.9 * ignite * (1 - smooth((t - 1.2) / 1.0) * 0.6))
        if hi > 2 and t < T_FIN + 0.05:
            hx, hy = sc.loc[min(hi, n - 1)]
            rgb += point_glow(sc, (hx, hy), 26, HOT, 1.0) + point_glow(sc, (hx, hy), 80, AMB, 0.45)
            emb.emit((hx, hy), 3)
        emb.step()
        em = emb.mask(sc)
        if em.any():
            rgb += (em[..., None] * HOT * 1.0 + sc.blur(em, 5)[..., None] * AMB * 1.4)
        # finish: schokgolf
        if fin >= 0 and fin < 1.3:
            ex, ey = sc.loc[-1]
            r = 12 + fin * 330
            ring = np.zeros((sc.rh, sc.rw), np.float32)
            im = Image.new('L', (sc.rw, sc.rh), 0)
            ImageDraw.Draw(im).ellipse((ex - r, ey - r, ex + r, ey + r), outline=int(255 * (1 - fin / 1.3) ** 1.5), width=4)
            ring = sc.blur(np.asarray(im).astype(np.float32) / 255, 3)
            rgb += ring[..., None] * HOT * 0.9
        if t >= T_FIN:
            ex, ey = sc.loc[-1]
            rgb += point_glow(sc, (ex, ey), 16, HOT, 0.8 * min(1, 0.4 + flash))
        add_region(sc, frame, rgb)
        # start- en eindmarkering (hairline ring)
        frame_i = Image.fromarray(np.clip(frame, 0, 255).astype('uint8'))
        d = ImageDraw.Draw(frame_i)
        gx, gy = sc.loc[0] + [sc.ox, sc.oy]
        d.ellipse((gx - 12, gy - 12, gx + 12, gy + 12), outline=GOLDI, width=2)
        frame = np.asarray(frame_i).astype(np.float32)
        # HUD
        m_done = meters * (hi / (n - 1))
        d = ImageDraw.Draw(Image.new('L', (1, 1)))
        hud_a = smooth((t - 0.5) / 0.5) * (1 - smooth((t - 6.6) / 0.4))
        if hud_a > 0.01:
            blit(frame, L_hud, hud_a)
            im2 = Image.fromarray(np.clip(frame, 0, 255).astype('uint8'))
            d2 = ImageDraw.Draw(im2)
            c = tuple(int(v * hud_a) for v in CREAM)
            d2.text((90, 1468), fmt_km(m_done) + " km", font=num, fill=c)
            d2.text((600, 1468), fmt_time(seconds_total * hi / (n - 1)), font=num, fill=c)
            frame = np.asarray(im2).astype(np.float32)
        # tekst
        blit(frame, L_lab, smooth((t - 0.15) / 0.5))
        a1 = smooth((t - 0.2) / 0.7)
        blit(frame, L_head1, a1, dy=(1 - a1) * 26)
        if t > 6.3:
            a2 = smooth((t - 6.3) / 0.7)
            blit(frame, L_head2, a2, dy=(1 - a2) * 26)
            a3 = smooth((t - 6.9) / 0.6)
            # HUD vervangen door knop
            fade_hud = 1 - smooth((t - 6.8) / 0.4)
            blit(frame, L_btn, a3, dy=(1 - a3) * 20)
        grain(frame)
        fade = smooth(t / 0.35) * (1 - smooth((t - (DUR - 0.35)) / 0.35))
        frame *= fade
        push(ff, frame)
    if not STILLS:
        ff.stdin.close()
        ff.wait()
    os.remove(wav)
    print('klaar', out)


# ---------- B: gloed-loop ----------
def render_gloed(outdir):
    DUR = 6.0
    NF = int(DUR * FPS)
    route, meters = load_route((90, 470, W - 90, 1450))
    sc = Scene(route, pad=200)
    n = sc.n
    mono = font('DejaVuSansMono.ttf', 28)
    mono_s = font('DejaVuSansMono.ttf', 24)
    kop = font('Saira-ExtraBold.ttf', 96)
    L_lab = text_layer(W, H, [(90, 206, "KADANS", mono, GOLDI), (90, 1700, "KADANS.APP", mono_s, (150, 138, 120))])
    L_head = text_layer(W, H, [(86, 262, "Jouw rondje.", kop, CREAM), (86, 372, "Beter moment.", kop, GOLDI)])
    wav = os.path.join(outdir, '_b.wav')
    write_wav(wav, audio_loop(DUR))
    out = os.path.join(outdir, 'route_gloed.mp4')
    ff = open_ffmpeg(out, wav)
    base = sc._mask(sc.loc, 5)
    for fi in range(NF):
        t = fi / FPS
        ph = t / DUR
        breathe = 0.78 + 0.22 * math.sin(2 * math.pi * ph)
        frame = sc.bgz(1.0 + 0.03 * (0.5 - 0.5 * math.cos(2 * math.pi * ph))) * sc.vig  # zoom ademt mee (loopt rond)
        core = base * (0.42 + 0.12 * breathe)
        hot = np.zeros_like(core)
        pts_glow = np.zeros((sc.rh, sc.rw, 3), np.float32)
        for k, off, tail in ((1, 0.0, 330), (1, 0.5, 330), (2, 0.25, 160)):
            cp = (ph * k + off) % 1.0
            ci = int(cp * (n - 1))
            a = max(0, ci - tail)
            fadeio = min(1.0, cp / 0.05, (1 - cp) / 0.05)
            hot = np.maximum(hot, comet_mask(sc, a, ci, 10) * fadeio)
            hx, hy = sc.loc[min(ci, n - 1)]
            pts_glow += point_glow(sc, (hx, hy), 22, HOT, 0.95 * fadeio) + point_glow(sc, (hx, hy), 70, AMB, 0.42 * fadeio)
        rgb = sc.glow_rgb(np.clip(core + 0.0, 0, 1), np.clip(hot, 0, 1), strength=0.9 * breathe)
        # de hele route krijgt een zachte gouden lijn, kometen lichten hem op
        rgb += pts_glow
        add_region(sc, frame, rgb)
        blit(frame, L_lab, 1.0)
        blit(frame, L_head, 1.0)
        grain(frame)
        push(ff, frame)
    if not STILLS:
        ff.stdin.close()
        ff.wait()
    os.remove(wav)
    print('klaar', out)


if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'beide'
    outdir = sys.argv[2] if len(sys.argv) > 2 else '/tmp/route_anim'
    os.makedirs(outdir, exist_ok=True)
    if what in ('teken', 'beide'):
        render_teken(outdir)
    if what in ('gloed', 'beide'):
        render_gloed(outdir)
