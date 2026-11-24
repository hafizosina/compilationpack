"""Module 10's ground textures: one large seamless texture per terrain, 512 px = 8 cells of the map that draws it.
Level 1 (1 m a cell, 8 m a texture, at EcsTownGrid.ART = 64 px a cell) is close-up ground; level 2 (8 m a cell,
64 m a texture) an aerial view; level 3 (64 m a cell, 512 m a texture) a map view. Levels 2 and 3 go to l2/ and l3/, pulled to level 1's
mean colour so a level change doesn't jump. The terrain shader shows each where its cells lie.
usage: python make_ground.py [--level 1|2|3] [key ...]      (needs Pillow, numpy)"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
N = 512


def field(scale, seed, power=2.0):
    """Seamless noise in -1..1: white noise filtered in frequency space, so it repeats exactly at N."""
    rng = np.random.default_rng(seed)
    f = np.fft.fftfreq(N)
    r = np.sqrt(f[None, :] ** 2 + f[:, None] ** 2) * N / scale
    spec = np.fft.fft2(rng.normal(size=(N, N))) * np.exp(-r ** power)
    out = np.real(np.fft.ifft2(spec))
    out -= out.mean()
    return out / (np.abs(out).max() + 1e-9)


def mix(a, b, t):
    t = np.clip(t, 0, 1)[..., None]
    return np.array(a, float) * (1 - t) + np.array(b, float) * t


def wrap_draw(img, draw_fn, x, y, reach):
    """Draws a feature at (x, y) and its copies across the edges it comes near, so the texture stays seamless."""
    for dx in (-N, 0, N):
        for dy in (-N, 0, N):
            if -reach <= x + dx <= N + reach and -reach <= y + dy <= N + reach:
                draw_fn(x + dx, y + dy)


def soft_layer(paint, blur):
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    paint(ImageDraw.Draw(layer))
    if blur:
        big = Image.new("RGBA", (N * 3, N * 3))
        for i in range(3):
            for j in range(3):
                big.paste(layer, (i * N, j * N))
        layer = big.filter(ImageFilter.GaussianBlur(blur)).crop((N, N, 2 * N, 2 * N))
    return layer


def over(base, layer):
    im = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    im.alpha_composite(layer)
    return np.array(im)[..., :3].astype(float)


def specks(rng, n, colours, r0, r1, alpha=(120, 200)):
    def paint(d):
        for _ in range(n):
            x, y, r = rng.uniform(0, N), rng.uniform(0, N), rng.uniform(r0, r1)
            c = rng.choice(colours) + (rng.randint(*alpha),)
            wrap_draw(None, lambda X, Y: d.ellipse([X - r, Y - r * 0.8, X + r, Y + r * 0.8], fill=c), x, y, r + 1)
    return paint


def blades(rng, n, colours, length):
    def paint(d):
        for _ in range(n):
            x, y = rng.uniform(0, N), rng.uniform(0, N)
            a = math.radians(rng.uniform(-35, 35))
            ln = rng.uniform(*length)
            c = rng.choice(colours) + (rng.randint(110, 190),)
            wrap_draw(None, lambda X, Y: d.line([(X, Y), (X + math.sin(a) * ln, Y - math.cos(a) * ln)], fill=c, width=2), x, y, ln + 2)
    return paint


def pebbles(rng, n, colour, r0, r1):
    def paint(d):
        for _ in range(n):
            x, y, r = rng.uniform(0, N), rng.uniform(0, N), rng.uniform(r0, r1)
            k = rng.uniform(0.9, 1.1)
            def one(X, Y):
                d.ellipse([X - r + 1.5, Y - r * 0.75 + 2, X + r + 1.5, Y + r * 0.75 + 2], fill=(0, 0, 0, 55))
                d.ellipse([X - r, Y - r * 0.75, X + r, Y + r * 0.75], fill=tuple(int(v * k) for v in colour) + (255,))
                d.ellipse([X - r * 0.7, Y - r * 0.6, X + r * 0.2, Y + r * 0.05], fill=tuple(min(255, int(v * k * 1.15)) for v in colour) + (200,))
            wrap_draw(None, one, x, y, r + 3)
    return paint


def cracks(rng, n, colour, alpha=90):
    def paint(d):
        for _ in range(n):
            x, y = rng.uniform(0, N), rng.uniform(0, N)
            a = rng.uniform(0, math.tau)
            pts = [(x, y)]
            for _ in range(rng.randint(3, 7)):
                a += rng.uniform(-0.8, 0.8)
                pts.append((pts[-1][0] + math.cos(a) * rng.uniform(6, 14), pts[-1][1] + math.sin(a) * rng.uniform(6, 14)))
            for dx in (-N, 0, N):
                for dy in (-N, 0, N):
                    d.line([(px + dx, py + dy) for px, py in pts], fill=colour + (alpha,), width=2)
    return paint


def grass(seed):
    rng = random.Random(seed)
    low, mid, fine = field(3, seed), field(10, seed + 1), field(60, seed + 2)
    base = mix((92, 128, 56), (112, 148, 64), low * 0.5 + 0.5)
    base = mix(base, (124, 112, 70), np.clip(mid - 0.45, 0, 1) * 1.6)          # bare soil showing through
    base *= (1 + fine[..., None] * 0.06)
    base = over(base, soft_layer(blades(rng, 2600, [(72, 104, 44), (66, 96, 40), (138, 170, 82)], (5, 10)), 0.6))
    base = over(base, soft_layer(specks(rng, 300, [(110, 92, 58), (96, 82, 54)], 1.0, 2.2), 0.5))
    return base


def forest(seed):
    rng = random.Random(seed)
    low, mid, fine = field(4, seed), field(12, seed + 1), field(60, seed + 2)
    base = mix((64, 88, 42), (84, 98, 48), low * 0.5 + 0.5)
    base = mix(base, (92, 74, 46), np.clip(mid - 0.2, 0, 1) * 1.2)
    base *= (1 + fine[..., None] * 0.07)
    base = over(base, soft_layer(specks(rng, 1400, [(118, 92, 50), (134, 104, 54), (92, 70, 40), (150, 120, 60)], 1.5, 3.5, (150, 230)), 0.4))
    base = over(base, soft_layer(blades(rng, 1200, [(52, 76, 34), (96, 126, 58)], (4, 8)), 0.6))
    return base


def dirt(seed):
    rng = random.Random(seed)
    low, mid, fine = field(3, seed), field(14, seed + 1), field(80, seed + 2)
    base = mix((128, 98, 66), (150, 116, 78), low * 0.5 + 0.5)
    base *= (1 + mid[..., None] * 0.08 + fine[..., None] * 0.07)
    base = over(base, soft_layer(specks(rng, 900, [(104, 80, 54), (170, 136, 96)], 0.8, 1.8), 0.4))
    base = over(base, soft_layer(pebbles(rng, 70, (150, 136, 116), 2.5, 5.0), 0.5))
    base = over(base, soft_layer(cracks(rng, 10, (84, 62, 40), 60), 0.7))
    return base


def sand(seed):
    rng = random.Random(seed)
    low, mid, fine = field(3, seed), field(10, seed + 1), field(90, seed + 2)
    y = np.arange(N)[:, None] * np.ones((1, N))
    x = np.ones((N, 1)) * np.arange(N)[None, :]
    ripple = np.sin((y + mid * 30) * math.tau / (N / 32))                         # 32 ripples a texture: seamless
    base = mix((212, 190, 138), (228, 208, 156), low * 0.5 + 0.5)
    base *= (1 + ripple[..., None] * 0.025 + fine[..., None] * 0.05)
    base = over(base, soft_layer(specks(rng, 1300, [(180, 156, 108), (240, 226, 186), (160, 140, 100)], 0.6, 1.4), 0.3))
    return base


def water(seed):
    rng = random.Random(seed)
    low, mid, fine = field(3, seed), field(8, seed + 1), field(30, seed + 2)
    base = mix((44, 96, 132), (60, 116, 150), low * 0.5 + 0.5)
    base *= (1 + mid[..., None] * 0.05)
    glint = np.clip(np.abs(fine) < 0.06, 0, 1) * np.clip(mid + 0.3, 0, 1)        # thin wandering light lines
    base = mix(base, (120, 172, 196), np.array(Image.fromarray((glint * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))) / 255 * 0.45)
    return base


def rock(seed):
    rng = random.Random(seed)
    low, mid, fine = field(3, seed), field(16, seed + 1), field(70, seed + 2)
    base = mix((118, 114, 106), (140, 136, 126), low * 0.5 + 0.5)
    base *= (1 + mid[..., None] * 0.07 + fine[..., None] * 0.06)
    base = over(base, soft_layer(cracks(rng, 40, (70, 66, 60), 110), 0.6))
    base = over(base, soft_layer(cracks(rng, 30, (176, 172, 162), 60), 0.6))
    base = over(base, soft_layer(specks(rng, 500, [(96, 92, 86), (164, 160, 150)], 0.8, 1.8), 0.4))
    return base


GROUNDS = {"grass": grass, "dirt": dirt, "sand": sand, "water": water, "rock": rock, "forest": forest}


# Levels 2 and 3: flat-vector shapes with hard edges, drawn at SS times size and scaled down for clean edges.
SS = 2


def bands(t, colours, edges):
    """Hard tonal patches: each pixel takes the colour of the band its value falls in."""
    return np.array(colours, float)[np.digitize(t, edges)]


def shade(colour, k):
    return tuple(int(np.clip(v * k, 0, 255)) for v in colour)


def vec_layer(paint):
    """A layer painted at SS times size, every shape wrapped round the edges, scaled down to N."""
    layer = Image.new("RGBA", (N * SS, N * SS), (0, 0, 0, 0))
    paint(Pen(ImageDraw.Draw(layer)))
    return layer.resize((N, N), Image.LANCZOS)


class Pen:
    """Draws in N-px coordinates on an SS-scaled canvas, repeating each shape across the edges it nears."""

    def __init__(self, d):
        self.d = d

    def _each(self, pts, reach):
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        for dx in (-N, 0, N):
            for dy in (-N, 0, N):
                if max(xs) + dx >= -reach and min(xs) + dx <= N + reach and max(ys) + dy >= -reach and min(ys) + dy <= N + reach:
                    yield [((x + dx) * SS, (y + dy) * SS) for x, y in pts]

    def poly(self, pts, fill, outline=None, width=1.0):
        for q in self._each(pts, 2):
            self.d.polygon(q, fill=fill)
            if outline:
                self.d.line(q + [q[0]], fill=outline, width=max(1, round(width * SS)), joint="curve")

    def line(self, pts, fill, width):
        for q in self._each(pts, width + 2):
            self.d.line(q, fill=fill, width=max(1, round(width * SS)), joint="curve")

    def dot(self, x, y, r, fill):
        self.poly(blob_pts(x, y, r, None, 10), fill)


def blob_pts(x, y, r, rng, n=12, rough=0.22, squash=1.0):
    """An irregular round polygon."""
    out = []
    a0 = rng.uniform(0, math.tau) if rng else 0.0
    for k in range(n):
        a = a0 + k * math.tau / n
        rr = r * (1 + (rng.uniform(-rough, rough) if rng else 0.0))
        out.append((x + math.cos(a) * rr, y + math.sin(a) * rr * squash))
    return out


def shift(pts, dx, dy, k=1.0):
    cx, cy = sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
    return [(cx + (px - cx) * k + dx, cy + (py - cy) * k + dy) for px, py in pts]


def hillshade(h, strength):
    """Light from the top-left on a seamless height field, -1..1."""
    gx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    gy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    return np.clip(-(gx + gy) * strength, -1, 1)


def crown(pen, rng, x, y, r, colour, ink):
    """A flat-shaded crown: shadow down-right, dark body, lighter copies up-left, thin ink edge."""
    pts = blob_pts(x, y, r, rng, 11, 0.18)
    pen.poly(shift(pts, r * 0.35, r * 0.4), (14, 22, 10, 110))
    pen.poly(pts, shade(colour, 0.82) + (255,), ink, 0.8)
    pen.poly(shift(pts, -r * 0.16, -r * 0.18, 0.72), colour + (255,))
    pen.poly(shift(pts, -r * 0.3, -r * 0.34, 0.36), shade(colour, 1.16) + (220,))


def boulder(pen, rng, x, y, r, colour, ink):
    """A faceted boulder: a lit top-left facet over a darker body, its shadow down-right."""
    pts = blob_pts(x, y, r, rng, rng.randint(6, 8), 0.25, 0.8)
    pen.poly(shift(pts, r * 0.3, r * 0.35), (20, 18, 16, 90))
    pen.poly(pts, shade(colour, 0.8) + (255,), ink, 0.7)
    top = [p for p in pts if (p[0] - x) + (p[1] - y) < r * 0.2] or pts[:3]
    centre = (x - r * 0.12, y - r * 0.12)
    pen.poly([centre] + top, colour + (255,))
    pen.poly(shift([centre] + top, -r * 0.06, -r * 0.06, 0.55), shade(colour, 1.14) + (200,))


def scatter(rng, n, gap):
    """Up to n points no closer than gap, measured round the wrap."""
    pts = []
    for _ in range(n * 6):
        if len(pts) >= n:
            break
        x, y = rng.uniform(0, N), rng.uniform(0, N)
        if all(min(abs(x - px), N - abs(x - px)) ** 2 + min(abs(y - py), N - abs(y - py)) ** 2 >= gap * gap for px, py in pts):
            pts.append((x, y))
    return pts


def wander(rng, steps, step, turn):
    """A wandering polyline from a random point."""
    a, pts = rng.uniform(0, math.tau), [(rng.uniform(0, N), rng.uniform(0, N))]
    for _ in range(steps):
        a += rng.uniform(-turn, turn)
        s = rng.uniform(*step)
        pts.append((pts[-1][0] + math.cos(a) * s, pts[-1][1] + math.sin(a) * s))
    return pts


def flecks(rng, n, colours, r0, r1, alpha=190):
    return lambda p: [p.dot(rng.uniform(0, N), rng.uniform(0, N), rng.uniform(r0, r1), rng.choice(colours) + (alpha,)) for _ in range(n)]


def grid_xy():
    return np.ones((N, 1)) * np.arange(N)[None, :], np.arange(N)[:, None] * np.ones((1, N))


def grass2(seed):
    rng = random.Random(seed)
    low, mid, fine = field(3, seed), field(9, seed + 1), field(40, seed + 2)
    base = bands(low * 0.6 + mid * 0.35 + fine * 0.08, [(84, 118, 50), (96, 130, 56), (106, 140, 62), (118, 150, 68)], [-0.35, 0.0, 0.35])
    base[mid + fine * 0.15 > 0.55] = (128, 132, 72)                                 # dry, thin patches
    def paint(p):
        for x, y in scatter(rng, 70, 18):                                          # darker clumps of tall grass
            q = blob_pts(x, y, rng.uniform(6, 14), rng, 9, 0.35, 0.8)
            p.poly(q, (72, 104, 44, 210))
            p.poly(shift(q, -1.5, -1.5, 0.6), (84, 118, 50, 200))
        for x, y in scatter(rng, 90, 14):                                          # bushes
            crown(p, rng, x, y, rng.uniform(3.0, 5.5), (70, 106, 44), (30, 40, 20, 160))
        flecks(rng, 900, [(70, 100, 42), (140, 168, 84), (150, 132, 80)], 0.6, 1.2, 170)(p)
    return over(base, vec_layer(paint))


def forest2(seed):
    rng = random.Random(seed)
    low, mid = field(3, seed), field(10, seed + 1)
    base = bands(low * 0.7 + mid * 0.3, [(34, 46, 24), (44, 58, 30)], [0.0])        # floor in the gaps
    greens = [(62, 98, 44), (72, 108, 46), (82, 112, 48), (66, 92, 40), (92, 118, 52)]
    def paint(p):
        for x, y in sorted(scatter(rng, 260, 15), key=lambda q: q[0] + q[1]):
            g = greens[int((low[int(y) % N, int(x) % N] * 0.5 + 0.5) * 2.99 + rng.random() * 2) % len(greens)]
            crown(p, rng, x, y, rng.uniform(12, 20), g, (22, 30, 16, 190))
    return over(base, vec_layer(paint))


def rock2(seed):
    rng = random.Random(seed)
    h = field(5, seed) + field(16, seed + 1) * 0.3
    t = h * 0.5 + hillshade(field(6, seed + 2), 25) * 0.5
    base = bands(t, [(104, 100, 92), (120, 116, 107), (134, 130, 120), (150, 146, 136)], [-0.3, 0.05, 0.4])
    def paint(p):
        for _ in range(60):                                                        # cracks between the slabs
            p.line(wander(rng, rng.randint(3, 6), (8, 18), 0.7), (78, 74, 68, 150), 1.0)
        for x, y in sorted(scatter(rng, 170, 13), key=lambda q: q[0] + q[1]):
            boulder(p, rng, x, y, rng.uniform(4, 11), rng.choice([(138, 134, 124), (126, 122, 114), (148, 142, 130)]), (40, 36, 32, 170))
        flecks(rng, 500, [(150, 146, 136), (104, 100, 92)], 0.8, 1.8, 200)(p)
    return over(base, vec_layer(paint))


def sand2(seed):
    rng = random.Random(seed)
    low, mid, fine = field(3, seed), field(10, seed + 1), field(50, seed + 2)
    base = bands(low * 0.7 + mid * 0.3, [(206, 182, 128), (216, 194, 140), (226, 206, 154)], [-0.25, 0.25])
    x, y = grid_xy()
    ripple = np.sin((y + x / 4 + mid * 40) * math.tau / (N / 24))                  # 24 ripples a texture, seamless
    base[(ripple > 0.82) & (fine > -0.4)] *= 0.92
    base[ripple < -0.9] *= 1.04
    def paint(p):
        for xx, yy in scatter(rng, 40, 30):                                        # damp, darker patches
            p.poly(blob_pts(xx, yy, rng.uniform(8, 20), rng, 10, 0.3, 0.7), (194, 168, 116, 120))
        flecks(rng, 240, [(176, 152, 104), (236, 224, 184), (150, 132, 96)], 0.6, 1.6)(p)
        for xx, yy in scatter(rng, 18, 40):                                        # grass tufts
            for _ in range(rng.randint(2, 4)):
                p.dot(xx + rng.uniform(-5, 5), yy + rng.uniform(-5, 5), rng.uniform(1.5, 3), (120, 134, 70, 220))
    return over(base, vec_layer(paint))


def dirt2(seed):
    rng = random.Random(seed)
    low, mid, fine = field(3, seed), field(12, seed + 1), field(50, seed + 2)
    base = bands(low * 0.6 + mid * 0.4, [(124, 94, 62), (136, 104, 70), (150, 116, 78)], [-0.2, 0.3])
    base[mid + fine * 0.2 > 0.45] = (158, 126, 88)                                  # trodden, packed patches
    def paint(p):
        for _ in range(22):                                                        # ruts and foot tracks
            pts = wander(rng, rng.randint(5, 10), (12, 12), 0.35)
            p.line(pts, (108, 80, 52, 140), rng.uniform(1.2, 2.2))
            p.line(shift(pts, -1.2, -1.2), (166, 134, 96, 90), 0.8)
        for x, y in scatter(rng, 120, 9):
            boulder(p, rng, x, y, rng.uniform(1.4, 3.2), (150, 136, 116), (60, 46, 32, 140))
        for x, y in scatter(rng, 40, 20):                                          # weed tufts
            for _ in range(rng.randint(2, 5)):
                p.dot(x + rng.uniform(-4, 4), y + rng.uniform(-4, 4), rng.uniform(1.2, 2.4), rng.choice([(98, 120, 56), (112, 128, 62)]) + (220,))
        flecks(rng, 700, [(104, 80, 54), (170, 136, 96)], 0.5, 1.2, 170)(p)
    return over(base, vec_layer(paint))


def water2(seed):
    rng = random.Random(seed)
    low, mid, fine = field(2, seed), field(6, seed + 1), field(24, seed + 2)
    x, y = grid_xy()
    sheen = np.sin((x + y + mid * 70) * math.tau / (N / 3))                        # broad diagonal sheen, seamless
    base = bands(low * 0.55 + sheen * 0.45, [(42, 92, 128), (50, 104, 140), (60, 116, 150), (74, 130, 162)], [-0.4, 0.05, 0.5])
    base[(np.abs(fine + mid * 0.3) < 0.022) & (sheen > 0.45)] = (118, 168, 194)
    def paint(p):
        for _ in range(70):                                                        # short ripple strokes
            xx, yy, ln = rng.uniform(0, N), rng.uniform(0, N), rng.uniform(5, 12)
            p.line([(xx, yy), (xx + ln, yy - ln * 0.15)], (112, 160, 188, 130), 0.9)
    return over(base, vec_layer(paint))


def grass3(seed):
    rng = random.Random(seed)
    low, mid, fine = field(2, seed), field(6, seed + 1), field(30, seed + 2)
    base = bands(low * 0.55 + mid * 0.35 + fine * 0.1, [(82, 116, 48), (94, 128, 54), (104, 138, 60), (116, 146, 66)], [-0.3, 0.05, 0.4])
    base[mid + fine * 0.2 > 0.6] = (126, 132, 72)
    return over(base, vec_layer(flecks(rng, 700, [(66, 98, 40), (74, 108, 44)], 1.0, 2.2, 200)))


def forest3(seed):
    rng = random.Random(seed)
    low, mid = field(2, seed), field(7, seed + 1)
    base = bands(low * 0.6 + mid * 0.4, [(36, 50, 26), (46, 62, 32)], [0.0])
    greens = [(60, 94, 42), (70, 104, 46), (80, 110, 48), (64, 88, 40)]
    def paint(p):
        for x, y in sorted(scatter(rng, 2600, 4.6), key=lambda q: q[0] + q[1]):
            g = greens[int((low[int(y) % N, int(x) % N] * 0.5 + 0.5) * 1.99 + rng.random() * 2) % len(greens)]
            r = rng.uniform(3.2, 5.2)
            q = blob_pts(x, y, r, rng, 8, 0.2)
            p.poly(shift(q, r * 0.35, r * 0.4), (14, 22, 10, 90))
            p.poly(q, shade(g, 0.84) + (255,))
            p.poly(shift(q, -r * 0.2, -r * 0.22, 0.6), shade(g, 1.08) + (255,))
    return over(base, vec_layer(paint))


def rock3(seed):
    rng = random.Random(seed)
    ridge = field(3, seed) + field(9, seed + 3) * 0.35
    h = (1 - np.abs(ridge)) ** 2 + field(10, seed + 1) * 0.15                     # ridged height: sharp crests
    base = bands(hillshade(h, 40) * 0.75 + h * 0.25, [(96, 92, 85), (112, 108, 100), (128, 124, 115), (142, 138, 128), (160, 156, 146)],
                 [-0.45, -0.12, 0.15, 0.45])
    base[np.abs(ridge) < 0.025] = (172, 168, 158)
    return over(base, vec_layer(flecks(rng, 600, [(88, 84, 78)], 0.8, 1.6, 170)))


def sand3(seed):
    rng = random.Random(seed)
    h = field(3, seed) + field(9, seed + 1) * 0.3
    base = bands(hillshade(h, 30) * 0.6 + h * 0.4, [(204, 180, 126), (214, 192, 138), (224, 204, 152), (234, 216, 166)], [-0.35, 0.0, 0.35])
    return over(base, vec_layer(flecks(rng, 500, [(176, 152, 104), (120, 134, 70)], 0.7, 1.4, 170)))


def dirt3(seed):
    rng = random.Random(seed)
    low, mid, fine = field(2, seed), field(7, seed + 1), field(30, seed + 2)
    base = bands(low * 0.55 + mid * 0.35 + fine * 0.1, [(122, 92, 60), (134, 102, 68), (146, 112, 76), (158, 124, 86)], [-0.3, 0.05, 0.4])
    base[mid + fine * 0.2 > 0.65] = (124, 114, 66)                                  # weedy patches
    return over(base, vec_layer(flecks(rng, 900, [(104, 80, 54), (168, 140, 104)], 0.6, 1.4, 180)))


def water3(seed):
    low, mid, fine = field(2, seed), field(5, seed + 1), field(18, seed + 2)
    base = bands(low * 0.7 + mid * 0.3, [(44, 96, 132), (52, 106, 142), (60, 114, 148)], [-0.25, 0.3])
    base[(np.abs(fine) < 0.02) & (mid > 0.25)] = (96, 148, 178)
    return base


LEVELS = {
    1: GROUNDS,
    2: {"grass": grass2, "dirt": dirt2, "sand": sand2, "water": water2, "rock": rock2, "forest": forest2},
    3: {"grass": grass3, "dirt": dirt3, "sand": sand3, "water": water3, "rock": rock3, "forest": forest3},
}
# How far levels 2 and 3 are pulled to level 1's mean colour: forest half, its canopy is greener than its floor.
PULL = {"forest": 0.5}


def main():
    args = sys.argv[1:]
    level = 1
    if "--level" in args:
        k = args.index("--level")
        level = int(args[k + 1])
        del args[k:k + 2]
    keys = args or list(GROUNDS)
    out = HERE if level == 1 else os.path.join(HERE, "l%d" % level)
    os.makedirs(out, exist_ok=True)
    for i, key in enumerate(GROUNDS):
        if key in keys:
            px = LEVELS[level][key](100 + i + 10 * (level - 1))
            if level != 1:
                target = np.array(Image.open(os.path.join(HERE, key + ".png")).convert("RGB"), float).reshape(-1, 3).mean(0)
                px = px + (target - px.reshape(-1, 3).mean(0)) * PULL.get(key, 1.0)
            Image.fromarray(np.clip(px, 0, 255).astype(np.uint8), "RGB").save(os.path.join(out, key + ".png"))
            print(level, key)


if __name__ == "__main__":
    main()
