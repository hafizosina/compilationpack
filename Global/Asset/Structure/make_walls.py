"""Wall sheets in RimWorld's art style, seen straight from above: a post at a wall's end, corner or join, beams to the
walls beside it; material texture, a hard bevel on each piece (plank, brick, block, pole) lit from the top-left, no
outline, a faint shadow. 16 join shapes in the side layout of module 10's walls, 64 px a cell.
usage: python make_walls.py [key ...] [--outline]      (needs Pillow, numpy)"""
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


DARKEN = 0.82                   # walls a little darker than their materials' plain colours, to stand off floors


class Material:
    """How a wall of one material looks: beam and post half-widths (in cells), colour, its textures, and its post
    `round` (a bamboo culm) or square with corners rounded by `corner` of its half-width."""
    def __init__(self, key, colour, beam, post, beam_tex, post_tex, edge=1.0, post_colour=None, round=False, corner=0.18,
                 joints=None, post_joints=None, mortar=None, rough=0.0, open_joints=False):
        # edge darkens the outline (1 = none, the look chosen); every colour is taken DARKEN times
        self.key, self.colour, self.beam, self.post = key, np.array(colour, np.float32) * DARKEN, beam, post
        self.beam_tex, self.post_tex, self.edge = beam_tex, post_tex, edge
        self.post_colour = np.array(post_colour or colour, np.float32) * DARKEN
        self.round, self.corner = round, corner
        # joints(): the seams or mortar on a beam running across (a T x T bool mask), post_joints() on a post; mortar is
        # their colour (None: the piece's own, darkened); rough roughens the outline, as if cut by hand
        self.joints, self.post_joints, self.rough = joints, post_joints, rough
        self.open_joints = open_joints                          # the joints are gaps, the ground showing through
        self.mortar = None if mortar is None else tuple(v * DARKEN for v in mortar)


# ------------------------------------------------------------------ textures: T x T arrays of brightness factors, grain along x

# Where each row of boards along a wood beam ends, as fractions of a tile: staggered row to row, repeating every tile.
BOARD_CUTS = ((0.12, 0.58), (0.36, 0.86))


def boards_of(half=0.19):
    """A wood beam running across: two rows of boards, each board's id, and its joints (the seam between the rows
    and the boards' butt ends)."""
    y, x = np.mgrid[0:T, 0:T] + 0.5
    top = T / 2 - half * T
    row = np.clip(np.floor((y - top) / (half * T)), 0, 1).astype(int)
    ids = np.zeros((T, T), np.int32)
    ends = np.zeros((T, T), bool)
    for r, cuts in enumerate(BOARD_CUTS):
        cut_px = np.array(cuts) * T
        k = np.searchsorted(cut_px, x[row == r], side="right") % len(cuts)
        ids[row == r] = r * 10 + k
        d = np.min(np.abs((x[..., None] - cut_px + T / 2) % T - T / 2), axis=-1)
        ends |= (row == r) & (d < 0.7 * SS)
    seam = np.abs(y - T / 2) < 0.7 * SS
    return ids, seam | ends, row, x, cut_px


def planks(seed, boards=2, half=0.19):
    """Boards along the beam, short and staggered, each its own shade, grain along it."""
    ids, joints, row, x, _ = boards_of(half)
    g = field(T / 1.0, 3.0 * SS, seed) * 0.10 + field(T / 4.0, 1.2 * SS, seed + 1) * 0.06
    tint = 0.90 + 0.16 * ((np.sin(ids * 12.9898 + 3.1) * 43758.5453) % 1.0)
    out = (1.0 + g) * tint
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
    return np.where(r < 0.08, 0.42 + r * 2.4, out)


# Where each row of bamboo poles along a wall ends, as fractions of a tile: staggered row to row, repeating every tile.
POLE_CUTS = ((0.20, 0.74), (0.47, 0.99))


def poles_along(half):
    """A wall of old bamboo poles laid along it, two side by side, a wall running across: each pixel's pole, its
    place across the pole (0..1), and the joints (the seams between rows and the poles' cut ends)."""
    y, x = np.mgrid[0:T, 0:T] + 0.5
    rows = len(POLE_CUTS)
    top = T / 2 - half * T
    width = 2 * half * T / rows
    row = np.clip(np.floor((y - top) / width), 0, rows - 1).astype(int)
    across = (y - top) / width - row
    ids = np.zeros((T, T), np.int32)
    ends = np.zeros((T, T), bool)
    for r, cuts in enumerate(POLE_CUTS):
        cut_px = np.array(cuts) * T
        sel = row == r
        k = np.searchsorted(cut_px, x[sel], side="right") % len(cuts)
        ids[sel] = r * 10 + k
        d = np.min(np.abs((x[..., None] - cut_px + T / 2) % T - T / 2), axis=-1)
        ends |= sel & (d < 0.7 * SS)
    seams = (np.minimum(across, 1 - across) * width < 0.6 * SS) & (y > top + 1) & (y < T - top - 1)
    return ids, across, seams | ends, x


def old_poles(seed, half):
    """Old bamboo poles along the wall: each round across (lit down its middle), weathered grey-tan and a little
    lighter or darker than the next, node rings along it."""
    ids, across, joints, x = poles_along(half)
    tint = 0.84 + 0.26 * ((np.sin(ids * 12.9898 + 5.0) * 43758.5453) % 1.0)
    out = (0.80 + 0.30 * np.sin(np.clip(across, 0, 1) * np.pi)) * tint * (1 + field(2.0 * SS, T / 10.0, seed) * 0.05)
    offset = ((np.sin(ids * 78.233 + 1.0) * 43758.5453) % 1.0) * T
    node = np.abs(((x + offset) % (T / 2)) - T / 4) < 0.6 * SS           # a node every half cell, shifted pole to pole
    return np.where(node, out * 0.72, out)


def brick_grid(half, course=None, length=None, joint=0.9):
    """Courses along a beam running across, joints staggered row to row: each pixel's (row, column) and the mortar."""
    y, x = np.mgrid[0:T, 0:T] + 0.5
    course = course or (2 * half * T / 3)
    length = length or T / 4
    top = T / 2 - half * T
    row = np.floor((y - top) / course)
    xs = x + (row % 2) * length / 2
    col = np.floor(xs / length)
    fy = (y - top) / course - row
    fx = xs / length - col
    mortar = (np.minimum(fy, 1 - fy) * course < joint * SS) | (np.minimum(fx, 1 - fx) * length < joint * SS)
    return row, col, mortar


def bricks(seed, half, course=None, length=None):
    """Bricks seen on the wall's top, each a little lighter or darker (the mortar is drawn from the joints)."""
    row, col, mortar = brick_grid(half, course, length)
    tint = 0.88 + 0.24 * ((np.sin(row * 12.9898 + col * 78.233) * 43758.5453) % 1.0)
    return tint * (1 + field(T / 6.0, T / 6.0, seed) * 0.05)


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
        quad = (x > c) * 1 + (y > c) * 2
        return out * (0.90 + 0.07 * (quad % 3))
    d = np.maximum(np.abs(x - c), np.abs(y - c)) / T
    border = (d > 0.26) & (d < 0.285)
    return np.where(border, 0.82, 1.0) * (1 + field(T / 8.0, T / 8.0, seed) * 0.06)


def plank_seam(half):
    y = np.arange(T)[:, None] + np.zeros((1, T)) + 0.5
    return np.abs(y - T / 2) < 0.8 * SS


def cross_joint():
    y, x = np.mgrid[0:T, 0:T] + 0.5
    return (np.abs(x - T / 2) < 0.9 * SS) | (np.abs(y - T / 2) < 0.9 * SS)


MATERIALS = {
    "wood": Material("wood", (136, 96, 60), 0.19, 0.37, lambda s: planks(s), lambda s: end_grain(s),
                     post_colour=(122, 84, 52), joints=lambda: boards_of(0.19)[1], rough=0.02),
    "bamboo": Material("bamboo", (150, 130, 88), 0.19, 0.37, lambda s: old_poles(s, 0.19), lambda s: culm(s),
                       post_colour=(138, 118, 80), round=True, joints=lambda: poles_along(0.19)[2]),
    "brick": Material("brick", (170, 82, 56), 0.23, 0.38, lambda s: bricks(s, 0.23), lambda s: pillar(s, "brick"),
                      post_colour=(160, 76, 52), corner=0.08, joints=lambda: brick_grid(0.23)[2],
                      post_joints=cross_joint, mortar=(132, 104, 82), rough=0.05),
    "stone": Material("stone", (128, 128, 122), 0.25, 0.40, lambda s: blocks(s, 0.25), lambda s: pillar(s, "stone"),
                      post_colour=(120, 120, 114), corner=0.10, joints=lambda: brick_grid(0.25, 0.25 * T, T / 2)[2],
                      mortar=(92, 90, 84), rough=0.08),
}


def roughen(mask, amount, seed):
    """The outline nudged in and out a little, as if cut by hand (repeats every tile, so joins still meet)."""
    if amount <= 0:
        return mask
    n = field(T / 7.0, T / 7.0, seed) * 0.6 + field(T / 18.0, T / 18.0, seed + 1) * 0.4
    return ((blur(mask, 1.2 * SS) + n * amount) > 0.5).astype(np.float32)


def facets(mask, width=2.0):
    """A hard-edged bevel on each piece of `mask`: a lit band along its top-left edges, a dark band along its
    bottom-right, flat between."""
    s = blur(mask, 1.0 * SS)
    gx = shift(s, 0, -1) - shift(s, 0, 1)
    gy = shift(s, -1, 0) - shift(s, 1, 0)
    facing = (gx + gy) / (np.hypot(gx, gy) * 1.4142 + 1e-6)
    band = (mask > 0) & ~(erode(mask, width * SS) > 0)
    out = np.ones(mask.shape, np.float32)
    out[band & (facing > 0.35)] = 1.16
    out[band & (facing < -0.35)] = 0.78
    return out


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

    whole = roughen(np.maximum(beams_h, beams_v), mat.rough, 41)
    post = roughen(post, mat.rough, 43)
    beams_h = whole * (beams_h >= beams_v)
    beams_v = whole * (beams_v > beams_h)
    beams = whole * (1 - post)
    shape = np.maximum(beams, post)

    tex_h = mat.beam_tex(1)                                     # one texture a direction: joints meet across tiles
    tex_v = mat.beam_tex(1).T
    shade = np.where(beams_v > beams_h, tex_v, tex_h)
    base = np.where(post[..., None] > 0, mat.post_colour * mat.post_tex(seed + 9)[..., None], mat.colour * shade[..., None])

    # The pieces between the joints each get a hard bevel: a lit facet top-left, a shadowed one bottom-right.
    joints = np.zeros((T, T), bool)
    if mat.joints is not None:
        jh = mat.joints()
        joints |= np.where(beams_v > beams_h, jh.T, jh) & (beams > 0)
    if mat.post_joints is not None:
        joints |= mat.post_joints() & (post > 0)
    if mat.open_joints:                                         # gaps between poles: nothing drawn there
        gaps = joints & (post == 0)
        whole = whole * ~gaps
        beams = beams * ~gaps
        shape = np.maximum(beams, post)
        joints = joints & ~gaps
    pieces_b = (beams > 0) & ~joints
    pieces_p = (post > 0) & ~joints
    light = np.where(post > 0, facets(pieces_p.astype(np.float32)), facets(whole * ~joints))
    col = base * light[..., None]
    if mat.mortar is not None:
        col[joints] = np.array(mat.mortar, np.float32) * (0.9 + 0.2 * field(T / 8.0, T / 8.0, 47))[joints][..., None]
    else:
        col[joints] *= 0.62
    edge = 1.5 * SS
    # The beam runs on under the post: its edge only where it shows, so the post's one edge marks the join.
    ring = (whole > 0) & ~(erode(whole, edge) > 0) & (post == 0)
    col[ring] = col[ring] * mat.edge
    ring = (post > 0) & ~(erode(post, edge) > 0)
    col[ring] = col[ring] * mat.edge
    shadow = blur(shift(shape, 3 * SS, 2 * SS), 2.0 * SS) * 0.40 * (1 - shape)

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
    if "--outline" in sys.argv:                                 # the dark outline, for comparison
        for mat in MATERIALS.values():
            mat.edge = 0.36
    for key in keys:
        sheet(MATERIALS[key]).save(os.path.join(HERE, f"wall_{key}.png"))
        print(f"wall_{key}.png")


if __name__ == "__main__":
    main()
