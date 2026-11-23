"""Fence and gate sheets in the walls' style (make_walls.py): a hard bevel on each part lit from the top-left, no outline,
the walls' darker palette, a faint shadow; posts and rails joined to the fences beside them, 16 join shapes in the
walls' side layout, 64 px a cell. A gate is one cell, 2 tiles: across, down.
usage: python make_fences.py [key ...]      (needs Pillow, numpy)"""
import os
import sys

import numpy as np
from PIL import Image

from make_walls import CELL, DARKEN, SIDES, SS, T, blur, box, bricks, erode, facets, field, pillar, shift

HERE = os.path.dirname(os.path.abspath(__file__))
C = T / 2
YX = np.mgrid[0:T, 0:T] + 0.5


def disc(cx, cy, r):
    y, x = YX
    return (np.hypot(x - cx, y - cy) <= r).astype(np.float32)


def arms(sides, half):
    """Bands of half-width `half` (cells) from the middle to each joined side; across and down kept apart."""
    b = half * T
    h = np.zeros((T, T), np.float32)
    v = np.zeros((T, T), np.float32)
    if "R" in sides:
        h = np.maximum(h, box(C, C - b, T + 8, C + b))
    if "L" in sides:
        h = np.maximum(h, box(-8, C - b, C, C + b))
    if "B" in sides:
        v = np.maximum(v, box(C - b, C, C + b, T + 8))
    if "T" in sides:
        v = np.maximum(v, box(C - b, -8, C + b, C))
    return h, v


def along(tex_h, h, v):
    """A texture drawn along x, turned for the arms that run down."""
    return np.where((v > h)[..., None], tex_h.transpose(1, 0, 2), tex_h)


def paint(colour, tex):
    return np.array(colour, np.float32) * DARKEN * tex[..., None]


def render(layers, soft=1.6, shadow=0.40):
    """Layers bottom to top as (mask, rgb, edge): each given the walls' hard bevel (a lit band top-left, a shadowed
    one bottom-right), no outline (`edge` is kept for the layer lists, unused); a faint shadow down-right."""
    shape = np.zeros((T, T), np.float32)
    col = np.zeros((T, T, 3), np.float32)
    for m, c, _edge in layers:
        if not m.any():
            continue
        cc = c * facets(m, 1.6 if soft < 2 else 2.2)[..., None]
        col = np.where(m[..., None] > 0, cc, col)
        shape = np.maximum(shape, m)
    drop = blur(shift(shape, 3 * SS, 2 * SS), 2.0 * SS) * shadow * (1 - shape)
    out = np.zeros((T, T, 4), np.float32)
    out[..., :3] = np.where(shape[..., None] > 0, col, 0)
    out[..., 3] = np.maximum(shape, drop) * 255
    im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    return im.resize((CELL, CELL), Image.LANCZOS)


def turned(layers):
    """The same layers seen down instead of across (lit in image space, so still from the top-left)."""
    return [(m.T, c.transpose(1, 0, 2), e) for m, c, e in layers]


# ------------------------------------------------------------------ textures, along x, repeating every tile

def split_bamboo(half, seed):
    """Two split culms lying side by side along the rail, a seam between, a node every third of a cell."""
    y, x = YX
    b = half * T
    v = (y - (C - b)) / b
    fv = v - np.floor(v)
    out = (0.80 + 0.30 * np.sin(np.clip(fv, 0, 1) * np.pi)) * (1 + field(T, 2.0 * SS, seed) * 0.08)
    out = np.where(np.minimum(fv, 1 - fv) * b < 0.7 * SS, out * 0.62, out)
    node = np.abs(((x / (T / 3)) + 0.5) % 1 - 0.5) * (T / 3) < 0.9 * SS
    return np.where(node, out * 0.78, out)


def screen(seed):
    """A fine woven bamboo screen: narrow strips over and under on the diagonal."""
    y, x = YX
    p = T / 16
    u, v = (x + y) / p, (x - y) / p
    over = (np.floor(u) + np.floor(v)) % 2 == 0
    fu, fv = u - np.floor(u), v - np.floor(v)
    strip = np.where(over, np.minimum(fu, 1 - fu), np.minimum(fv, 1 - fv))
    out = np.where(over, 1.07, 0.90) * (0.84 + 0.16 * np.clip(strip * 6, 0, 1))
    return out * (1 + field(T / 3.0, T / 3.0, seed) * 0.05)


def culm_top(cx, cy, r):
    """A round bamboo post cut across: the culm's wall, its hollow dark."""
    y, x = YX
    d = np.hypot(x - cx, y - cy) / r
    return np.where(d < 0.52, 0.40 + d * 0.5, 1.0 + 0.06 * np.cos(d * 9))


def leaves(seed, fine=False):
    """Leaf masses: clumps lighter on top, hollows darker, small bright leaves."""
    clump = field(T / (22.0 if fine else 12.0), T / (22.0 if fine else 12.0), seed)
    small = field(T / 60.0, T / 60.0, seed + 1)
    out = 0.92 + 0.22 * clump + 0.10 * small
    return np.where(small > 0.55, out * 1.18, out)


def coping(seed):
    return 1 + field(T / 8.0, T / 8.0, seed) * 0.06


# ------------------------------------------------------------------ fences: layers for one join shape

def bamboo_rail(sides):
    h, v = arms(sides, 0.085)
    rail = np.maximum(h, v)
    tex = along(paint((204, 182, 116), split_bamboo(0.085, 3)), h, v)
    r = 0.13 * T
    post = disc(C, C, r)
    return [(rail, tex, 0.50), (post, paint((166, 160, 90), culm_top(C, C, r)), 0.48)]


def woven(sides):
    h, v = arms(sides, 0.07)
    panel = np.maximum(h, v)
    tex = along(paint((212, 188, 126), screen(5)), h, v)
    r = 0.11 * T
    post = disc(C, C, r)
    return [(panel, tex, 0.52), (post, paint((156, 150, 84), culm_top(C, C, r)), 0.48)]


def hedge_mask(sides):
    """A clipped-free hedge: round the middle and along each joined arm, its outline lumpy but the same at every
    tile's edge (width and noise repeat every tile), so arms meet their neighbours'."""
    y, x = YX
    n = field(T / 7.0, T / 7.0, 21) * 0.05 * T
    d = np.hypot(x - C, y - C) - 0.27 * T
    for side, (sx, sy) in {"R": (1, 0), "L": (-1, 0), "B": (0, 1), "T": (0, -1)}.items():
        if side not in sides:
            continue
        s = x if sx else y
        across = np.abs(y - C) if sx else np.abs(x - C)
        w = 0.21 * T * (1 + 0.12 * np.sin(2 * np.pi * 3 * s / T + 0.7))
        on = (s - C) * (sx + sy) >= 0
        d = np.minimum(d, np.where(on, across - w, 1e9))
    return (d + n < 0).astype(np.float32)


def flowers(mask, seed, count):
    """A few red hibiscus flowers on the hedge, away from the tile's edges: [(mask, rgb, edge)]."""
    rng = np.random.default_rng(seed)
    inner = erode(mask, 4 * SS)
    petals = np.zeros((T, T), np.float32)
    hearts = np.zeros((T, T), np.float32)
    placed = 0
    for _ in range(40):
        if placed >= count:
            break
        cx, cy = rng.uniform(6 * SS, T - 6 * SS, 2)
        if inner[int(cy), int(cx)] <= 0:
            continue
        petals = np.maximum(petals, disc(cx, cy, 2.2 * SS))
        hearts = np.maximum(hearts, disc(cx, cy, 0.8 * SS))
        placed += 1
    return [(petals, paint((200, 44, 46), np.ones((T, T))), 0.62), (hearts, paint((236, 196, 90), np.ones((T, T))), 1.0)]


def hedge(sides, seed=0):
    m = hedge_mask(sides)
    return [(m, paint((76, 116, 54), leaves(31)), 0.55)] + flowers(m, 101 + seed, 1 + len(sides) // 2 + seed % 2)


def brick_wall(sides):
    h, v = arms(sides, 0.18)
    wall = np.maximum(h, v)
    tex = along(paint((178, 90, 62), bricks(7, 0.18)), h, v)
    ch, cv = arms(sides, 0.06)
    layers = [(wall, tex, 0.45), (np.maximum(ch, cv), paint((214, 194, 160), coping(8)), 0.72)]
    if sides not in ("RL", "BT"):
        p = 0.22 * T
        q = 0.14 * T
        layers.append((box(C - p, C - p, C + p, C + p, 0.08 * p), paint((168, 82, 56), pillar(9, "brick")), 0.42))
        layers.append((box(C - q, C - q, C + q, C + q, 0.1 * q), paint((218, 198, 164), coping(10)), 0.70))
    return layers


FENCES = {"bamboo_rail": bamboo_rail, "woven": woven, "hedge": hedge, "brick_wall": brick_wall}


# ------------------------------------------------------------------ gates: one cell drawn across, joined at both sides

def gate_bamboo_rail():
    """A swing gate of three lashed poles between two posts, the fence's rails running on to the cell's edges."""
    stub = np.maximum(box(-8, C - 0.085 * T, 0.16 * T, C + 0.085 * T), box(0.84 * T, C - 0.085 * T, T + 8, C + 0.085 * T))
    rail = paint((204, 182, 116), split_bamboo(0.085, 3))
    leaf = box(0.16 * T, C - 0.12 * T, 0.84 * T, C + 0.12 * T)
    poles = paint((222, 200, 136), np.ones((T, T)))
    y, x = YX
    pv = (y - (C - 0.12 * T)) / (0.24 * T / 3)
    fv = pv - np.floor(pv)
    poles *= (0.82 + 0.28 * np.sin(np.clip(fv, 0, 1) * np.pi))[..., None]
    for sx in (0.36, 0.64):
        poles[np.abs(x - sx * T) < 1.4 * SS] = (110, 84, 52)
    r = 0.12 * T
    posts = disc(0.16 * T, C, r) + disc(0.84 * T, C, r)
    post_tex = np.where(x < C, culm_top(0.16 * T, C, r), culm_top(0.84 * T, C, r))
    return [(stub, rail, 0.50), (leaf, poles, 0.46), (np.minimum(posts, 1), paint((166, 160, 90), post_tex), 0.48)]


def gate_woven():
    """A gate of woven nipa leaf in a bamboo frame, between two posts."""
    stub = np.maximum(box(-8, C - 0.07 * T, 0.15 * T, C + 0.07 * T), box(0.85 * T, C - 0.07 * T, T + 8, C + 0.07 * T))
    y, x = YX
    leaf = box(0.15 * T, C - 0.09 * T, 0.85 * T, C + 0.09 * T)
    ribs = 0.9 + 0.14 * np.sin(x / (1.6 * SS)) + field(T / 4.0, 1.5 * SS, 12) * 0.08
    frame = np.maximum(box(0.15 * T, C - 0.11 * T, 0.85 * T, C - 0.075 * T), box(0.15 * T, C + 0.075 * T, 0.85 * T, C + 0.11 * T))
    r = 0.12 * T
    posts = np.minimum(disc(0.15 * T, C, r) + disc(0.85 * T, C, r), 1)
    post_tex = np.where(x < C, culm_top(0.15 * T, C, r), culm_top(0.85 * T, C, r))
    return [(stub, paint((212, 188, 126), screen(5)), 0.52), (leaf, paint((150, 138, 76), ribs), 0.50),
            (frame, paint((206, 184, 118), np.ones((T, T))), 0.55), (posts, paint((156, 150, 84), post_tex), 0.48)]


def gate_hedge():
    """An opening in the hedge framed by two clipped square posts of it; the middle left empty."""
    posts = np.maximum(box(-8, C - 0.25 * T, 0.28 * T, C + 0.25 * T, 0.05 * T), box(0.72 * T, C - 0.25 * T, T + 8, C + 0.25 * T, 0.05 * T))
    return [(posts, paint((86, 128, 60), leaves(33, fine=True)), 0.55)]


def gate_brick():
    """Candi bentar: a split gate, two stepped brick towers either side of an opening in the cell's middle, their
    inner faces sheer."""
    layers = []
    for half, depth, colour, tex, edge in ((0.36, 0.33, (172, 86, 58), bricks(13, 0.36), 0.42),
                                           (0.27, 0.26, (184, 94, 64), pillar(14, "brick"), 0.45),
                                           (0.17, 0.18, (218, 198, 164), coping(15), 0.70)):
        m = np.maximum(box(-8, C - half * T, depth * T, C + half * T), box((1 - depth) * T, C - half * T, T + 8, C + half * T))
        layers.append((m, paint(colour, tex), edge))
    return layers


GATES = {"bamboo_rail": gate_bamboo_rail, "woven": gate_woven, "hedge": gate_hedge, "brick": gate_brick}


def fence_sheet(key):
    img = Image.new("RGBA", (CELL * 6, CELL * 3), (0, 0, 0, 0))
    for (x, y), sides in SIDES.items():
        layers = hedge(sides, x + y * 6) if key == "hedge" else FENCES[key](sides)
        img.alpha_composite(render(layers, soft=2.6 if key == "hedge" else 1.6), (x * CELL, y * CELL))
    return img


def gate_sheet(key):
    layers = GATES[key]()
    soft = 2.6 if key == "hedge" else 1.6
    img = Image.new("RGBA", (CELL * 2, CELL), (0, 0, 0, 0))
    img.alpha_composite(render(layers, soft), (0, 0))
    img.alpha_composite(render(turned(layers), soft), (CELL, 0))
    return img


def main():
    keys = sys.argv[1:] or list(FENCES) + ["gate_" + k for k in GATES]
    for key in keys:
        if key.startswith("gate_"):
            gate_sheet(key[5:]).save(os.path.join(HERE, f"{key}.png"))
            print(f"{key}.png")
        else:
            fence_sheet(key).save(os.path.join(HERE, f"fence_{key}.png"))
            print(f"fence_{key}.png")


if __name__ == "__main__":
    main()
