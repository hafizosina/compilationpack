"""Module 10's ground textures: one large seamless texture per terrain, soft and mottled with fine detail, at
EcsTownGrid.ART = 64 px a cell (512 px = 8 cells). The terrain shader shows each where its cells lie.
usage: python make_ground.py [key ...]      (needs Pillow, numpy)"""
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


def main():
    keys = sys.argv[1:] or list(GROUNDS)
    for i, key in enumerate(GROUNDS):
        if key in keys:
            img = Image.fromarray(np.clip(GROUNDS[key](100 + i), 0, 255).astype(np.uint8), "RGB")
            img.save(os.path.join(HERE, key + ".png"))
            print(key)


if __name__ == "__main__":
    main()
