"""Wall sheets in RimWorld's art style, seen straight from above: a post at a wall's end, corner or join, beams to the
walls beside it; material texture, soft bevel lit from the top-left, a dark edge of the material's own colour, a
faint shadow. 16 join shapes in the side layout of module 10's walls, 64 px a cell.
usage: python make_walls.py [key ...] [--preview]      (needs Pillow, numpy)"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
CELL = 64
SS = 4
T = CELL * SS
# Wall side layout, as module 10's WoodWall.png: atlas (x, y) -> joined sides (R, B, L, T).
SIDES = {
    (0, 0): "RB", (1, 0): "RL", (2, 0): "BL", (3, 0): "R", (4, 0): "RBL", (5, 0): "B",
    (0, 1): "BT", (1, 1): "", (2, 1): "BT", (3, 1): "RBT", (4, 1): "RBLT", (5, 1): "BLT",
    (0, 2): "RT", (1, 2): "RL", (2, 2): "LT", (3, 2): "T", (4, 2): "RLT", (5, 2): "L",
}


def field(scale_x, scale_y, seed):
    """Noise in -1..1 repeating every T, stretched by axis (grain)."""
    rng = np.random.default_rng(seed)
    fx = np.fft.fftfreq(T)[None, :] * T / scale_x
    fy = np.fft.fftfreq(T)[:, None] * T / scale_y
    out = np.real(np.fft.ifft2(np.fft.fft2(rng.normal(size=(T, T))) * np.exp(-(fx ** 2 + fy ** 2))))
    out -= out.mean()
    return out / (np.abs(out).max() + 1e-9)


def blur(a, r):
    pad = int(r * 3) + 2
    p = np.pad(a, pad, mode="edge")
    im = Image.fromarray((np.clip(p, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r))
    return np.array(im)[pad:-pad, pad:-pad].astype(np.float32) / 255


def erode(a, r):
    pad = int(r) + 1
    p = np.pad((a * 255).astype(np.uint8), pad, mode="edge")
    im = Image.fromarray(p).filter(ImageFilter.MinFilter(int(r) * 2 + 1))
    return np.array(im)[pad:-pad, pad:-pad].astype(np.float32) / 255


def shift(a, dy, dx):
    """`a` moved by (dy, dx) pixels, the border repeated (no wrap: a beam runs on past the tile's edge)."""
    pad = max(abs(dy), abs(dx))
    p = np.pad(a, pad, mode="edge")
    return p[pad - dy:pad - dy + T, pad - dx:pad - dx + T]


def box(x0, y0, x1, y1, r=0.0):
    """A rounded rectangle mask (pixels of the T x T tile)."""
    y, x = np.mgrid[0:T, 0:T] + 0.5
    dx = np.maximum(np.maximum(x0 + r - x, x - (x1 - r)), 0)
    dy = np.maximum(np.maximum(y0 + r - y, y - (y1 - r)), 0)
    inside = (x >= x0) & (x <= x1) & (y >= y0) & (y <= y1)
    return (inside & (dx * dx + dy * dy <= r * r + 1e-6)).astype(np.float32)


class Material:
    """How a wall of one material looks: beam and post half-widths (in cells), colour, its textures, and its post
    `round` (a bamboo culm) or square with corners rounded by `corner` of its half-width."""
    def __init__(self, key, colour, beam, post, beam_tex, post_tex, edge=0.42, post_colour=None, round=False, corner=0.18):
        self.key, self.colour, self.beam, self.post = key, np.array(colour, np.float32), beam, post
        self.beam_tex, self.post_tex, self.edge = beam_tex, post_tex, edge
        self.post_colour = np.array(post_colour or colour, np.float32)
        self.round, self.corner = round, corner


# ------------------------------------------------------------------ textures: T x T arrays of brightness factors, grain along x

def planks(seed, boards=2, half=0.19):
    """Boards along the beam, a dark seam between them, long grain; repeats every tile along x."""
    g = field(T / 1.0, 3.0 * SS, seed) * 0.10 + field(T / 4.0, 1.2 * SS, seed + 1) * 0.06
    y = np.arange(T)[:, None] + 0.5
    width = 2 * half * T / boards
    out = 1.0 + g
    top = T / 2 - half * T
    for k in range(1, boards):
        seam = top + k * width
        out = out * (1 - 0.35 * np.exp(-((y - seam) / (0.9 * SS)) ** 2))
    for k in range(boards):                       # each board a touch lighter or darker
        y0, y1 = top + k * width, top + (k + 1) * width
        out = np.where((y >= y0) & (y < y1), out * (0.96 + 0.08 * ((seed + k * 7) % 3) / 2), out)
    return out


def end_grain(seed):
    """A post's top: growth rings round its middle, a few checks (cracks)."""
    y, x = np.mgrid[0:T, 0:T] + 0.5
    r = np.hypot(x - T / 2, y - T / 2) / SS
    wob = field(T / 6.0, T / 6.0, seed) * 1.4
    rings = 1.0 + 0.07 * np.sin((r + wob) * 1.6)
    a = np.arctan2(y - T / 2, x - T / 2)
    check = np.exp(-((a - 0.6) / 0.05) ** 2) * (r > 3) * (r < 13) * 0.25
    return rings - check


def weave(seed, half):
    """Woven bamboo (gedek): flat strips crossing over and under on the diagonal, a darker shadow at each crossing."""
    y, x = np.mgrid[0:T, 0:T] + 0.5
    p = T / 8                                                   # 8 strips a tile: repeats along x
    u, v = (x + y) / p, (x - y) / p
    over = (np.floor(u) + np.floor(v)) % 2 == 0
    fu, fv = u - np.floor(u), v - np.floor(v)
    strip = np.where(over, np.minimum(fu, 1 - fu), np.minimum(fv, 1 - fv))
    out = np.where(over, 1.06, 0.92) * (0.82 + 0.18 * np.clip(strip * 6, 0, 1))
    return out * (1 + field(T / 3.0, T / 3.0, seed) * 0.05)


def culm(seed):
    """A bamboo post cut across, seen from above: the wall of the culm, the hollow dark inside."""
    y, x = np.mgrid[0:T, 0:T] + 0.5
    r = np.hypot(x - T / 2, y - T / 2) / T
    out = 1.0 + 0.06 * np.cos(r * 90)
    return np.where(r < 0.17, 0.42 + r * 1.2, out)


def bricks(seed, half, course=None, length=None):
    """Bricks seen on the wall's top: courses along the beam, joints staggered row to row, light mortar,
    each brick a little lighter or darker."""
    y, x = np.mgrid[0:T, 0:T] + 0.5
    rows = 3
    course = course or (2 * half * T / rows)
    length = length or T / 4
    top = T / 2 - half * T
    row = np.floor((y - top) / course)
    xs = x + (row % 2) * length / 2
    col = np.floor(xs / length)
    fy = (y - top) / course - row
    fx = xs / length - col
    mortar = (np.minimum(fy, 1 - fy) * course < 0.9 * SS) | (np.minimum(fx, 1 - fx) * length < 0.9 * SS)
    tint = 0.9 + 0.2 * ((np.sin(row * 12.9898 + col * 78.233) * 43758.5453) % 1.0)
    out = tint * (1 + field(T / 6.0, T / 6.0, seed) * 0.05)
    return np.where(mortar, 1.18, out)


def blocks(seed, half):
    """Cut stone: two courses of long blocks along the beam, fine joints, speckled grey."""
    out = bricks(seed, half, course=half * T, length=T / 2)
    rng = np.random.default_rng(seed)
    speck = rng.random((T, T)) < 0.012
    return np.where(speck, out * 0.85, out) * (1 + field(T / 10.0, T / 10.0, seed + 3) * 0.05)


def pillar(seed, kind):
    """A post's top: bricks in a pillar (two by two) or one stone with a chiselled border."""
    y, x = np.mgrid[0:T, 0:T] + 0.5
    c = T / 2
    if kind == "brick":
        out = 1 + field(T / 6.0, T / 6.0, seed) * 0.05
        joint = (np.abs(x - c) < 0.9 * SS) | (np.abs(y - c) < 0.9 * SS)
        quad = (x > c) * 1 + (y > c) * 2
        out = out * (0.92 + 0.06 * (quad % 3))
        return np.where(joint, 1.16, out)
    d = np.maximum(np.abs(x - c), np.abs(y - c)) / T
    border = (d > 0.26) & (d < 0.285)
    return np.where(border, 0.82, 1.0) * (1 + field(T / 8.0, T / 8.0, seed) * 0.06)


MATERIALS = {
    "wood": Material("wood", (136, 96, 60), 0.19, 0.37, lambda s: planks(s), lambda s: end_grain(s),
                     post_colour=(122, 84, 52)),
    "bamboo": Material("bamboo", (196, 170, 104), 0.15, 0.30, lambda s: weave(s, 0.15), lambda s: culm(s),
                       post_colour=(150, 160, 84), round=True, edge=0.45),
    "brick": Material("brick", (170, 82, 56), 0.23, 0.38, lambda s: bricks(s, 0.23), lambda s: pillar(s, "brick"),
                      post_colour=(160, 76, 52), corner=0.08, edge=0.40),
    "stone": Material("stone", (128, 128, 122), 0.25, 0.40, lambda s: blocks(s, 0.25), lambda s: pillar(s, "stone"),
                      post_colour=(120, 120, 114), corner=0.10, edge=0.42),
}


def tile(mat, sides, seed):
    c, b, p = T / 2, mat.beam * T, mat.post * T
    beams_h = np.zeros((T, T), np.float32)
    beams_v = np.zeros((T, T), np.float32)
    if "R" in sides:
        beams_h = np.maximum(beams_h, box(c, c - b, T + 8, c + b))
    if "L" in sides:
        beams_h = np.maximum(beams_h, box(-8, c - b, c, c + b))
    if "B" in sides:
        beams_v = np.maximum(beams_v, box(c - b, c, c + b, T + 8))
    if "T" in sides:
        beams_v = np.maximum(beams_v, box(c - b, -8, c + b, c))
    straight = sides in ("RL", "BT")
    if straight:
        post = np.zeros((T, T), np.float32)
    elif mat.round:
        y, x = np.mgrid[0:T, 0:T] + 0.5
        post = (np.hypot(x - c, y - c) <= p).astype(np.float32)
    else:
        post = box(c - p, c - p, c + p, c + p, mat.corner * p)
    beams = np.maximum(beams_h, beams_v) * (1 - post)
    shape = np.maximum(beams, post)

    tex_h = mat.beam_tex(1)                                     # one texture a direction: joints meet across tiles
    tex_v = mat.beam_tex(1).T
    shade = np.where(beams_v > beams_h, tex_v, tex_h)
    base = np.where(post[..., None] > 0, mat.post_colour * mat.post_tex(seed + 9)[..., None], mat.colour * shade[..., None])

    def lit(mask):
        """Bevel: brighter toward the top-left edge, darker toward the bottom-right."""
        s = blur(mask, 2.2 * SS)
        k = int(1.5 * SS)
        e = shift(s, k, k) - shift(s, -k, -k)
        return 1.0 - 0.9 * e

    light = np.where(post > 0, lit(post), lit(np.maximum(beams_h, beams_v)))
    col = base * light[..., None]
    edge = 1.6 * SS
    # The beam runs on under the post: its edge only where it shows, so the post's one edge marks the join.
    whole = np.maximum(beams_h, beams_v)
    ring = (whole > 0) & ~(erode(whole, edge) > 0) & (post == 0)
    col[ring] = col[ring] * mat.edge
    ring = (post > 0) & ~(erode(post, edge) > 0)
    col[ring] = col[ring] * mat.edge
    shadow = blur(shift(shape, 3 * SS, 2 * SS), 2.0 * SS) * 0.35 * (1 - shape)

    out = np.zeros((T, T, 4), np.float32)
    out[..., :3] = col * shape[..., None]
    out[..., 3] = np.maximum(shape, shadow) * 255
    out[..., :3] = np.where(shape[..., None] > 0, out[..., :3], 0)
    im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    return im.resize((CELL, CELL), Image.LANCZOS)


def sheet(mat):
    img = Image.new("RGBA", (CELL * 6, CELL * 3), (0, 0, 0, 0))
    for (x, y), sides in SIDES.items():
        img.alpha_composite(tile(mat, sides, 11 + x * 3 + y * 17), (x * CELL, y * CELL))
    return img


def main():
    keys = [a for a in sys.argv[1:] if not a.startswith("--")] or list(MATERIALS)
    for key in keys:
        sheet(MATERIALS[key]).save(os.path.join(HERE, f"wall_{key}.png"))
        print(f"wall_{key}.png")


if __name__ == "__main__":
    main()
