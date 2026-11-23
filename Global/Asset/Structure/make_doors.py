"""Door sheets in the walls' style (make_walls.py: hard bevel per part, no outline, the darker palette): a leaf across the gap between the two posts beside
it, seen from above. 4 tiles of 96 px (1.5 cells at 64 px a cell): horizontal closed, vertical closed, horizontal
open, vertical open; open is the closed leaf see-through.
usage: python make_doors.py [key ...]      (needs Pillow, numpy)"""
import os
import sys

import numpy as np
from PIL import Image

from make_walls import DARKEN, SS, blur, erode

HERE = os.path.dirname(os.path.abspath(__file__))
CELL = 64
TILE = 96                       # px: 1.5 cells
D = TILE * SS                   # canvas side
C = D / 2
U = CELL * SS                   # one cell in canvas units
OPEN = 0.30                     # alpha of an open leaf
TUCK = 0.05                     # cells a leaf reaches under each post beside it


def field(scale_x, scale_y, seed):
    """Noise in -1..1 repeating every D, stretched by axis."""
    rng = np.random.default_rng(seed)
    fx = np.fft.fftfreq(D)[None, :] * D / scale_x
    fy = np.fft.fftfreq(D)[:, None] * D / scale_y
    out = np.real(np.fft.ifft2(np.fft.fft2(rng.normal(size=(D, D))) * np.exp(-(fx ** 2 + fy ** 2))))
    out -= out.mean()
    return out / (np.abs(out).max() + 1e-9)


def rect(x0, y0, x1, y1):
    y, x = np.mgrid[0:D, 0:D] + 0.5
    return ((x >= x0) & (x <= x1) & (y >= y0) & (y <= y1)).astype(np.float32)


def disc(cx, cy, r):
    y, x = np.mgrid[0:D, 0:D] + 0.5
    return (np.hypot(x - cx, y - cy) <= r).astype(np.float32)


def grain(seed):
    return 1 + field(D / 1.0, 2.5 * SS, seed) * 0.10 + field(D / 4.0, 1.0 * SS, seed + 1) * 0.05


def leaf_bamboo(half):
    """Three bamboo poles lying along the door, each its own part, lashed at both ends, a node ring every third of a
    cell; smoked darker than the bamboo wall so the door reads in it."""
    y, x = np.mgrid[0:D, 0:D] + 0.5
    m = rect(C - LENGTH * U / 2, C - half * U, C + LENGTH * U / 2, C + half * U)
    w = 2 * half * U / 3
    v = (y - (C - half * U)) / w
    fv = v - np.floor(v)
    round_ = 0.80 + 0.30 * np.sin(np.clip(fv, 0, 1) * np.pi)           # each pole rounded across
    node = np.abs(((x - C) / (U / 3) + 0.5) % 1 - 0.5) * (U / 3) < 0.9 * SS
    seam = (np.minimum(fv, 1 - fv) * w < 0.7 * SS) & (m > 0)
    parts = []
    for k in range(3):
        pole = m * (np.floor(v) == k) * ~seam
        colour = np.array((92, 72, 42), np.float32) * DARKEN * (round_ * grain(5 + k) * (0.92 + 0.08 * k))[..., None]
        colour[node] *= 0.74
        parts.append((pole, colour))
    for sx in (-0.5, 0.5):
        lash = rect(C + sx * U - 1.6 * SS, C - half * U, C + sx * U + 1.6 * SS, C + half * U)
        parts.append((lash, np.zeros((D, D, 3), np.float32) + np.array((58, 42, 26), np.float32) * DARKEN))
    return parts


def leaf_wood(half):
    """A plank door: short boards across it, each its own part, stained darker than the wood wall, two iron straps
    along it."""
    y, x = np.mgrid[0:D, 0:D] + 0.5
    parts = []
    n = 5
    step = LENGTH * U / n
    for k in range(n):
        x0 = C - LENGTH * U / 2 + k * step
        board = rect(x0 + 0.35 * SS, C - half * U, x0 + step - 0.35 * SS, C + half * U)
        parts.append((board, np.array((96, 60, 36), np.float32) * DARKEN * (grain(3 + k) * (0.92 + 0.04 * (k % 3)))[..., None]))
    for sy in (-0.45, 0.45):
        strap = rect(C - LENGTH * U / 2, C + sy * half * U - 1.6 * SS, C + LENGTH * U / 2, C + sy * half * U + 1.6 * SS)
        parts.append((strap, np.zeros((D, D, 3), np.float32) + np.array((58, 54, 50), np.float32)))
    return parts


def leaf_carved(half):
    """A carved teak double door: two leaves meeting in the middle, a carved border, brass rings by the meeting."""
    out = []
    y, x = np.mgrid[0:D, 0:D] + 0.5
    for side in (-1, 1):
        x0, x1 = (C - LENGTH * U / 2, C - 0.6 * SS) if side < 0 else (C + 0.6 * SS, C + LENGTH * U / 2)
        m = rect(x0, C - half * U, x1, C + half * U)
        colour = np.array((112, 62, 40), np.float32) * DARKEN * grain(7 + side)[..., None]
        inner = rect(x0 + 3.5 * SS, C - half * U + 3.5 * SS, x1 - 3.5 * SS, C + half * U - 3.5 * SS)
        groove = rect(x0 + 3 * SS, C - half * U + 3 * SS, x1 - 3 * SS, C + half * U - 3 * SS) * (1 - inner)
        colour[groove > 0] *= 0.66
        out.append((m, colour))
        ring = disc(C + side * 4.5 * SS, C, 2.6 * SS) * (1 - disc(C + side * 4.5 * SS, C, 1.4 * SS))
        out.append((ring, np.zeros((D, D, 3), np.float32) + np.array((196, 150, 60), np.float32)))
    return out


# key -> (draw, half thickness, post half-width of the wall it goes in, from make_walls.py)
DOORS = {"bamboo": (leaf_bamboo, 0.17, 0.37), "wood": (leaf_wood, 0.17, 0.37), "carved": (leaf_carved, 0.19, 0.38)}
LENGTH = 1.0                    # set per door in sheet(): the gap between the posts either side, plus TUCK each end


def render(parts, vertical, alpha):
    """Each part given the walls' hard bevel in image space (so a vertical door is lit from the top-left too), no
    outline, a faint shadow."""
    if vertical:
        parts = [(m.T, c.transpose(1, 0, 2)) for m, c in parts]
    shape = np.zeros((D, D), np.float32)
    col = np.zeros((D, D, 3), np.float32)
    for m, c in parts:
        cc = c * facets_d(m)[..., None]
        col = np.where(m[..., None] > 0, cc, col)
        shape = np.maximum(shape, m)
    shadow = blur(shift_d(shape, 3 * SS, 2 * SS), 2.0 * SS) * 0.40 * (1 - shape)
    out = np.zeros((D, D, 4), np.float32)
    out[..., :3] = col
    out[..., 3] = np.maximum(shape, shadow) * 255 * alpha
    im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    return im.resize((TILE, TILE), Image.LANCZOS)


def facets_d(mask, width=2.0):
    """make_walls.facets on the door's canvas: a lit band along a part's top-left edges, a dark one bottom-right."""
    s = blur(mask, 1.0 * SS)
    gx = shift_d(s, 0, -1) - shift_d(s, 0, 1)
    gy = shift_d(s, -1, 0) - shift_d(s, 1, 0)
    facing = (gx + gy) / (np.hypot(gx, gy) * 1.4142 + 1e-6)
    band = (mask > 0) & ~(erode(mask, width * SS) > 0)
    out = np.ones(mask.shape, np.float32)
    out[band & (facing > 0.35)] = 1.16
    out[band & (facing < -0.35)] = 0.78
    return out


def shift_d(a, dy, dx):
    pad = max(abs(dy), abs(dx))
    p = np.pad(a, pad, mode="constant")
    return p[pad - dy:pad - dy + D, pad - dx:pad - dx + D]


def sheet(key):
    global LENGTH
    draw, half, post = DOORS[key]
    LENGTH = 2 * (1 - post) + 2 * TUCK
    parts = draw(half)
    img = Image.new("RGBA", (TILE * 4, TILE), (0, 0, 0, 0))
    for k, (vertical, alpha) in enumerate(((False, 1.0), (True, 1.0), (False, OPEN), (True, OPEN))):
        img.alpha_composite(render(parts, vertical, alpha), (k * TILE, 0))
    return img


def main():
    keys = sys.argv[1:] or list(DOORS)
    for key in keys:
        sheet(key).save(os.path.join(HERE, f"door_{key}.png"))
        print(f"door_{key}.png")


if __name__ == "__main__":
    main()
