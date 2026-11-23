"""Ground and floor tile sheets in the flat vector style: a flat fill, a few inked details, a rounded inked edge.
Dual-grid 6x3 sheets at 64 px a tile (the layout in ../placeholder/README.md). Writes to build/ground/;
--install writes over the sheets in ../placeholder/.
usage: python ground.py [--install]      (needs Pillow, numpy)"""
import math
import os
import random
import sys
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build", "ground")
PLACE = os.path.join(HERE, "..", "placeholder")
TILE = 64                # sheet pixels a tile (EcsTownGrid.ART)
SS = 4                   # supersampling
T = TILE * SS
INK = (30, 26, 24)
ROUND = 7 * SS           # corner rounding of an edge
RIM = 1.6 * SS           # edge ink width
BAND = 4 * SS            # darker band inside the edge
MARGIN = 6 * SS          # details stay this far from a tile's border, so any tile sits by any other

# Dual-grid layout, same as WoodFloor.png: atlas (x, y) -> filled quadrants (TL, TR, BL, BR).
DUAL = {
    (0, 0): "0001", (1, 0): "0011", (2, 0): "0010", (3, 0): "1110", (4, 0): "1101", (5, 0): "1001",
    (0, 1): "0101", (1, 1): "1111", (2, 1): "1010", (3, 1): "1011", (4, 1): "0111", (5, 1): "0110",
    (0, 2): "0100", (1, 2): "1100", (2, 2): "1000", (3, 2): "1111", (4, 2): "1111", (5, 2): "1111",
}


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3])


def quad_mask(bits):
    """The filled quadrants, rounded: blur and threshold on a canvas padded by repeating the border, so a straight
    edge stays on the tile's midline and only corners round."""
    pad = ROUND * 2
    m = np.zeros((T, T), np.uint8)
    h = T // 2
    for q, (y, x) in enumerate(((0, 0), (0, 1), (1, 0), (1, 1))):
        if bits[q] == "1":
            m[y * h:(y + 1) * h, x * h:(x + 1) * h] = 255
    m = np.pad(m, pad, mode="edge")
    im = Image.fromarray(m).filter(ImageFilter.GaussianBlur(ROUND * 0.6))
    a = np.array(im)[pad:-pad, pad:-pad]
    return (a >= 128).astype(np.float32)


def erode(mask, r):
    im = Image.fromarray((mask * 255).astype(np.uint8))
    im = im.filter(ImageFilter.MinFilter(int(r) * 2 + 1))
    return np.array(im).astype(np.float32) / 255


class Kind:
    """One ground: a base colour, an edge style and a detail painter."""
    def __init__(self, base, details, edge="ink", band=0.86, rim=INK, rim_alpha=0.75):
        self.base, self.details, self.edge, self.band, self.rim, self.rim_alpha = base, details, edge, band, rim, rim_alpha


# ------------------------------------------------------------------ detail painters (draw on a T x T RGBA layer)

def pts(rng, n, margin=MARGIN):
    return [(rng.uniform(margin, T - margin), rng.uniform(margin, T - margin)) for _ in range(n)]


def tufts(colour, n=4, light=None):
    def paint(d, rng):
        for x, y in pts(rng, n):
            s = rng.uniform(0.8, 1.2) * SS
            for a in (-35, 0, 35):
                r = math.radians(a + rng.uniform(-8, 8))
                d.line([(x, y), (x + math.sin(r) * 6 * s, y - math.cos(r) * 7 * s)], fill=colour + (200,), width=int(1.6 * SS))
        if light:
            for x, y in pts(rng, 2):
                r = rng.uniform(5, 9) * SS
                d.ellipse([x - r, y - r * 0.7, x + r, y + r * 0.7], fill=light + (90,))
    return paint


def pebbles(colour, n=3, cracks=0):
    def paint(d, rng):
        for x, y in pts(rng, n):
            w, h = rng.uniform(2.2, 4) * SS, rng.uniform(1.6, 3) * SS
            d.ellipse([x - w - 1.2 * SS, y - h - 1.2 * SS, x + w + 1.2 * SS, y + h + 1.2 * SS], fill=INK + (190,))
            d.ellipse([x - w, y - h, x + w, y + h], fill=colour + (255,))
            d.ellipse([x - w * 0.7 - SS, y - h * 0.7 - SS, x + w * 0.3, y + h * 0.1], fill=shade(colour, 1.15) + (255,))
        for x, y in pts(rng, cracks):
            a = rng.uniform(0, math.pi)
            p = [(x, y)]
            for _ in range(3):
                a += rng.uniform(-0.7, 0.7)
                p.append((p[-1][0] + math.cos(a) * 5 * SS, p[-1][1] + math.sin(a) * 5 * SS))
            d.line(p, fill=INK + (90,), width=int(1.0 * SS))
    return paint


def ripples(colour, n=3):
    def paint(d, rng):
        for x, y in pts(rng, n, MARGIN + 4 * SS):
            w = rng.uniform(5, 9) * SS
            d.arc([x - w, y - w * 0.45, x + w, y + w * 0.45], 200, 340, fill=colour + (170,), width=int(1.5 * SS))
    return paint


def specks(colour, n=10, arcs=0, arc_colour=None):
    def paint(d, rng):
        for x, y in pts(rng, n):
            r = rng.uniform(0.6, 1.1) * SS
            d.ellipse([x - r, y - r, x + r, y + r], fill=colour + (160,))
        for x, y in pts(rng, arcs, MARGIN + 4 * SS):
            w = rng.uniform(6, 10) * SS
            d.arc([x - w, y - w * 0.4, x + w, y + w * 0.4], 200, 340, fill=arc_colour + (120,), width=int(1.2 * SS))
    return paint


def slabs(colour):
    def paint(d, rng):
        for x, y in pts(rng, 2, MARGIN + 6 * SS):
            r = rng.uniform(6, 9) * SS
            k = rng.randint(5, 7)
            a0 = rng.uniform(0, 6.28)
            p = [(x + math.cos(a0 + i * 6.28 / k) * r * rng.uniform(0.75, 1.0), y + math.sin(a0 + i * 6.28 / k) * r * rng.uniform(0.75, 1.0)) for i in range(k)]
            d.polygon(p, fill=shade(colour, 1.08) + (255,), outline=INK + (110,), width=int(1.1 * SS))
        pebbles(shade(colour, 0.9), 0, 2)(d, rng)
    return paint


def litter(colour, leaf):
    def paint(d, rng):
        tufts(colour, 2)(d, rng)
        for x, y in pts(rng, 4):
            a = rng.uniform(0, math.pi)
            dx, dy = math.cos(a) * 3.5 * SS, math.sin(a) * 3.5 * SS
            d.line([(x - dx, y - dy), (x + dx, y + dy)], fill=leaf + (230,), width=int(2.6 * SS))
    return paint


def planks(colour):
    def paint(d, rng):
        for y in range(0, T, 16 * SS):
            d.line([(0, y), (T, y)], fill=INK + (120,), width=int(1.1 * SS))
            x = (rng.randint(1, 3) * 16 * SS) % T
            d.line([(x, y), (x, y + 16 * SS)], fill=INK + (100,), width=int(1.0 * SS))
            for _ in range(2):
                gx = rng.uniform(4, 60) * SS
                d.line([(gx, y + 7 * SS), (gx + 7 * SS, y + 7 * SS)], fill=shade(colour, 0.85) + (180,), width=int(1.0 * SS))
    return paint


def flags(colour):
    def paint(d, rng):
        for row in range(2):
            for col in range(2):
                off = (row % 2) * 16 * SS
                x0, y0 = (col * 32 * SS + off) % T, row * 32 * SS
                for dx in (0, -T):
                    d.rounded_rectangle([x0 + dx + 1.5 * SS, y0 + 1.5 * SS, x0 + dx + 30.5 * SS, y0 + 30.5 * SS], radius=4 * SS,
                                        fill=shade(colour, rng.uniform(0.95, 1.08)) + (255,), outline=INK + (130,), width=int(1.1 * SS))
    return paint


def cobbles(colour):
    def paint(d, rng):
        for row in range(4):
            for col in range(4):
                x0 = col * 16 * SS + (row % 2) * 8 * SS
                y0 = row * 16 * SS
                for dx in (0, -T):
                    d.rounded_rectangle([x0 + dx + 1.2 * SS, y0 + 1.2 * SS, x0 + dx + 14.8 * SS, y0 + 14.8 * SS], radius=5 * SS,
                                        fill=shade(colour, rng.uniform(0.92, 1.1)) + (255,), outline=INK + (120,), width=int(1.0 * SS))
    return paint


def weave(colour, stripe):
    def paint(d, rng):
        for y in (10 * SS, T - 10 * SS):
            d.line([(0, y), (T, y)], fill=stripe + (255,), width=int(3 * SS))
        for x in range(4 * SS, T, 8 * SS):
            d.line([(x, 0), (x, T)], fill=shade(colour, 0.88) + (150,), width=int(1.0 * SS))
    return paint


def thatch(colour):
    def paint(d, rng):
        for y in range(0, T, 8 * SS):
            d.line([(0, y), (T, y)], fill=shade(colour, 0.78) + (200,), width=int(1.4 * SS))
            for _ in range(9):
                x = rng.uniform(0, T)
                d.line([(x, y + 1 * SS), (x + rng.uniform(-1, 1) * SS, y + 7 * SS)], fill=shade(colour, 1.15) + (150,), width=int(0.9 * SS))
    return paint


GRASS = (104, 146, 62)
KINDS = {
    "terrain_grass": Kind(GRASS, tufts(shade(GRASS, 0.72), 4, shade(GRASS, 1.10))),
    "terrain_dirt": Kind((150, 116, 76), pebbles((126, 100, 72), 2, 1)),
    "terrain_sand": Kind((222, 200, 146), specks((180, 156, 104), 9, 1, (250, 236, 196)), band=0.93),
    "terrain_water": Kind((62, 124, 164), ripples((150, 196, 220), 3), edge="shore", band=0.80),
    "terrain_rock": Kind((140, 136, 126), slabs((140, 136, 126))),
    "terrain_forest": Kind((72, 110, 46), litter(shade((72, 110, 46), 0.70), (120, 96, 52))),
    "floor_wood": Kind((168, 124, 78), planks((168, 124, 78)), edge="hard"),
    "floor_stone": Kind((150, 146, 138), flags((150, 146, 138)), edge="hard"),
    "floor_road": Kind((128, 118, 104), cobbles((128, 118, 104)), edge="hard"),
    "floor_rug": Kind((158, 50, 44), weave((158, 50, 44), (210, 170, 70)), edge="hard"),
    "floor_dirt_path": Kind((164, 130, 88), pebbles((140, 112, 80), 2, 1), band=0.90),
    "roof": Kind((196, 160, 92), thatch((196, 160, 92)), edge="hard"),
}
# Floors whose detail is a pattern tiled across the whole tile (planks, flagstones): drawn edge to edge, not kept off the border.
PATTERNED = {"floor_wood", "floor_stone", "floor_road", "floor_rug", "roof"}


def tile(kind, name, bits, seed):
    mask = quad_mask(bits)
    inner = erode(mask, BAND)
    deep = erode(mask, RIM + 2 * SS) if name not in PATTERNED else mask
    rng = random.Random(seed)
    out = np.zeros((T, T, 4), np.float32)
    base = np.array(kind.base, np.float32)
    band_col = np.array(shade(kind.base, kind.band), np.float32)
    col = np.where(inner[..., None] > 0, base, band_col)
    out[..., :3] = col
    out[..., 3] = 255
    det = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    kind.details(ImageDraw.Draw(det), rng)
    d = np.array(det).astype(np.float32)
    a = d[..., 3:4] / 255 * deep[..., None]
    out[..., :3] = out[..., :3] * (1 - a) + d[..., :3] * a
    if kind.edge == "shore":                 # a pale wet line inside the bank, then ink
        foam = (erode(mask, RIM + 1.5 * SS) > 0) & ~(erode(mask, RIM + 3.5 * SS) > 0)
        out[foam, :3] = out[foam, :3] * 0.4 + np.array((200, 228, 236)) * 0.6
    rim = (mask > 0) & ~(erode(mask, RIM) > 0)
    full = bits == "1111"
    if not full:
        out[rim, :3] = out[rim, :3] * (1 - kind.rim_alpha) + np.array(kind.rim) * kind.rim_alpha
    out[..., 3] = mask * 255
    im = Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGBA")
    return im.resize((TILE, TILE), Image.LANCZOS)


def sheet(name):
    kind = KINDS[name]
    img = Image.new("RGBA", (TILE * 6, TILE * 3), (0, 0, 0, 0))
    for (x, y), bits in DUAL.items():
        img.alpha_composite(tile(kind, name, bits, zlib.crc32(f"{name}{x},{y}".encode())), (x * TILE, y * TILE))
    return img


def main():
    install = "--install" in sys.argv
    os.makedirs(BUILD, exist_ok=True)
    for name in KINDS:
        img = sheet(name)
        img.save(os.path.join(BUILD, name + ".png"))
        if install:
            img.save(os.path.join(PLACE, name + ".png"))
    print(BUILD)


if __name__ == "__main__":
    main()
