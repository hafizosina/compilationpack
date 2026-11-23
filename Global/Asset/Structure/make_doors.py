"""Door sheets in RimWorld's style, as the walls (make_walls.py): a leaf across the gap between the two posts beside
it, seen from above. 4 tiles of 96 px (1.5 cells at 64 px a cell): horizontal closed, vertical closed, horizontal
open, vertical open; open is the closed leaf see-through.
usage: python make_doors.py [key ...]      (needs Pillow, numpy)"""
import os
import sys

import numpy as np
from PIL import Image

from make_walls import SS, blur, erode

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
    """Three bamboo poles lying along the door, lashed at both ends, a node ring every third of a cell."""
    y, x = np.mgrid[0:D, 0:D] + 0.5
    m = rect(C - LENGTH * U / 2, C - half * U, C + LENGTH * U / 2, C + half * U)
    w = 2 * half * U / 3
    v = (y - (C - half * U)) / w
    fv = v - np.floor(v)
    round_ = 0.78 + 0.32 * np.sin(np.clip(fv, 0, 1) * np.pi)           # each pole rounded across
    colour = np.array((180, 156, 94), np.float32) * (round_ * grain(5))[..., None]
    split = np.minimum(fv, 1 - fv) * w < 0.8 * SS
    colour[(split & (m > 0))] *= 0.55
    node = np.abs(((x - C) / (U / 3) + 0.5) % 1 - 0.5) * (U / 3) < 0.9 * SS
    colour[(node & (m > 0))] *= 0.75
    for sx in (-0.5, 0.5):
        lash = rect(C + sx * U - 1.6 * SS, C - half * U, C + sx * U + 1.6 * SS, C + half * U)
        colour[lash > 0] = (110, 84, 52)
    return [(m, colour)]


def leaf_wood(half):
    """A plank door: boards along it, two dark iron straps across."""
    m = rect(C - LENGTH * U / 2, C - half * U, C + LENGTH * U / 2, C + half * U)
    colour = np.array((136, 96, 60), np.float32) * grain(3)[..., None]
    y, x = np.mgrid[0:D, 0:D] + 0.5
    seam = np.exp(-((y - C) / (0.8 * SS)) ** 2) * 0.35
    colour *= (1 - seam)[..., None]
    for sx in (-0.33, 0.33):
        strap = rect(C + sx * U - 2.2 * SS, C - half * U, C + sx * U + 2.2 * SS, C + half * U)
        colour[strap > 0] = (70, 64, 58)
    return [(m, colour)]


def leaf_carved(half):
    """A carved teak double door: two leaves meeting in the middle, a carved border, brass rings by the meeting."""
    out = []
    y, x = np.mgrid[0:D, 0:D] + 0.5
    for side in (-1, 1):
        x0, x1 = (C - LENGTH * U / 2, C - 0.6 * SS) if side < 0 else (C + 0.6 * SS, C + LENGTH * U / 2)
        m = rect(x0, C - half * U, x1, C + half * U)
        colour = np.array((112, 62, 40), np.float32) * grain(7 + side)[..., None]
        inner = rect(x0 + 3.5 * SS, C - half * U + 3.5 * SS, x1 - 3.5 * SS, C + half * U - 3.5 * SS)
        border = m * (1 - inner)
        groove = rect(x0 + 3 * SS, C - half * U + 3 * SS, x1 - 3 * SS, C + half * U - 3 * SS) * (1 - inner)
        colour[border > 0] *= 1.12
        colour[groove > 0] *= 0.62
        ring = disc(C + side * 4.5 * SS, C, 2.6 * SS) * (1 - disc(C + side * 4.5 * SS, C, 1.4 * SS))
        colour[ring > 0] = (196, 150, 60)
        out.append((m, colour))
    return out


# key -> (draw, half thickness, post half-width of the wall it goes in, from make_walls.py)
DOORS = {"bamboo": (leaf_bamboo, 0.17, 0.37), "wood": (leaf_wood, 0.17, 0.37), "carved": (leaf_carved, 0.19, 0.38)}
LENGTH = 1.0                    # set per door in sheet(): the gap between the posts either side, plus TUCK each end


def render(parts, vertical, alpha):
    """Light, edge and shadow each part in image space (so a vertical door is lit from the top-left too)."""
    if vertical:
        parts = [(m.T, c.transpose(1, 0, 2)) for m, c in parts]
    shape = np.zeros((D, D), np.float32)
    col = np.zeros((D, D, 3), np.float32)
    for m, c in parts:
        s = blur(m, 2.0 * SS)
        k = int(1.4 * SS)
        light = 1.0 - 0.9 * (shift_d(s, k, k) - shift_d(s, -k, -k))
        cc = c * light[..., None]
        ring = (m > 0) & ~(erode(m, 1.5 * SS) > 0)
        cc[ring] *= 0.42
        col = np.where(m[..., None] > 0, cc, col)
        shape = np.maximum(shape, m)
    shadow = blur(shift_d(shape, 3 * SS, 2 * SS), 2.0 * SS) * 0.35 * (1 - shape)
    out = np.zeros((D, D, 4), np.float32)
    out[..., :3] = col
    out[..., 3] = np.maximum(shape, shadow) * 255 * alpha
    im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    return im.resize((TILE, TILE), Image.LANCZOS)


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
