"""Fence and gate sheets in the walls' style (make_walls.py): a hard bevel on each part lit from the top-left, no outline,
the walls' darker palette, a faint shadow; posts and rails joined to the fences beside them, 16 join shapes in the
walls' side layout, 64 px a cell. A gate is one cell, 6 tiles (GATE_TILES): across and down, posts on both
sides or on one, for a gate two cells wide.
usage: python make_fences.py [key ...]      (needs Pillow, numpy)"""
import os
import sys

import numpy as np
from PIL import Image

from make_walls import CELL, DARKEN, SIDES, SS, T, blocks, blur, boards_of, box, brick_grid, bricks, erode, facets, field, pillar, planks, shift

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


# ------------------------------------------------------------------ standard sizes, in cells (walls: beam 0.19, post 0.37)

FENCE = 0.10                    # half-width of a fence's body
POST = 0.15                     # half-width of a fence's post or pillar
RAIL = 0.035                    # half-width of a thin rail
STAKE = 0.065                   # radius of a stake's top
GATE_AT = 0.17                  # a gate's posts, in from the cell's edges

WOOD = (136, 96, 60)
STONE = (128, 128, 122)
STICK = (122, 98, 68)
BRICK = (170, 82, 56)
LEAF = (76, 116, 54)


def split(mask, joints):
    """A part cut into pieces by its joints: the pieces (each bevelled on its own) and the joints between."""
    return mask * ~joints, mask * joints


def square(cx, cy, half):
    return box(cx - half * T, cy - half * T, cx + half * T, cy + half * T, 0.12 * half * T)


def stubs(half, to, left=True, right=True):
    """The fence's body running in from the edges of a gate's cell to its posts, `to` in from the edges; only on the
    sides where the fence meets the gate."""
    m = np.zeros((T, T), np.float32)
    if left:
        m = np.maximum(m, box(-8, C - half * T, to * T, C + half * T))
    if right:
        m = np.maximum(m, box((1 - to) * T, C - half * T, T + 8, C + half * T))
    return m


def ends(left, right):
    """A gate's posts: the centres on the sides where the fence meets it, and the leaf's reach (to the cell's edge
    where it runs on into the next cell of the same gate)."""
    lo = GATE_AT * T if left else -8
    hi = (1 - GATE_AT) * T if right else T + 8
    at = ([GATE_AT * T] if left else []) + ([(1 - GATE_AT) * T] if right else [])
    return lo, hi, at


def union(masks):
    out = np.zeros((T, T), np.float32)
    for m in masks:
        out = np.maximum(out, m)
    return out


def tiers(cx, cy, top, colours, knob=True):
    """A candi-like pillar from above: square tiers stepping in from half-width `top`, bricks on the lowest, a small
    round knob (ratna) crowning it."""
    layers = []
    n = len(colours)
    for k, colour in enumerate(colours):
        tex = pillar(9 + k, "brick") if k == 0 else 1 + field(T / 8.0, T / 8.0, 20 + k) * 0.05
        layers.append((square(cx, cy, top * (1 - 0.6 * k / n)), paint(colour, tex), 1.0))
    if knob:
        layers.append((disc(cx, cy, top * 0.22 * T), paint((196, 104, 72), np.ones((T, T))), 1.0))
    return layers


# ------------------------------------------------------------------ fences: layers for one join shape

def bamboo_rail(sides):
    """Split-bamboo rails on round bamboo posts, a post in every cell."""
    h, v = arms(sides, FENCE * 0.8)
    rail = np.maximum(h, v)
    tex = along(paint((204, 182, 116), split_bamboo(FENCE * 0.8, 3)), h, v)
    r = POST * T
    return [(rail, tex, 1.0), (disc(C, C, r), paint((166, 160, 90), culm_top(C, C, r)), 1.0)]


def plank(sides):
    """Teak boards between square posts: two rows of short boards, staggered, as the wood wall's."""
    h, v = arms(sides, FENCE)
    rail = np.maximum(h, v)
    joints_h = boards_of(FENCE)[1]
    joints = np.where(v > h, joints_h.T, joints_h) & (rail > 0)
    pieces, gaps = split(rail, joints)
    layers = [(pieces, along(paint(WOOD, planks(1, half=FENCE)), h, v), 1.0), (gaps, paint(WOOD, np.full((T, T), 0.55)), 1.0)]
    if sides not in ("RL", "BT"):
        layers.append((square(C, C, POST), paint((122, 84, 52), np.ones((T, T))), 1.0))
    return layers


def stakes(sides, centre=True):
    """Round stake tops along each joined arm, six a cell on the cell grid, and one in the middle."""
    m = disc(C, C, STAKE * 1.15 * T) if centre else np.zeros((T, T), np.float32)
    for k in range(6):
        p = (k + 0.5) * T / 6
        r = STAKE * T * (0.9 + 0.2 * ((k * 37) % 5) / 4)
        if "R" in sides and p > C:
            m = np.maximum(m, disc(p, C, r))
        if "L" in sides and p < C:
            m = np.maximum(m, disc(p, C, r))
        if "B" in sides and p > C:
            m = np.maximum(m, disc(C, p, r))
        if "T" in sides and p < C:
            m = np.maximum(m, disc(C, p, r))
    return m


def stick_tex():
    y, x = YX
    step = T / 6
    rings = 1 + 0.08 * np.cos(np.hypot(x % step - step / 2, y % step - step / 2) * 0.9)
    return paint(STICK, rings * (1 + field(T / 8.0, T / 8.0, 5) * 0.08))


def stick(sides):
    """A stick fence: close-set wooden stakes tied to a thin rail behind them."""
    h, v = arms(sides, RAIL)
    return [(np.maximum(h, v), paint((104, 82, 56), np.ones((T, T))), 1.0), (stakes(sides), stick_tex(), 1.0)]


def stone(sides):
    """A low andesite wall of cut blocks, square block pillars at its ends, corners and joins."""
    h, v = arms(sides, FENCE)
    wall = np.maximum(h, v)
    joints_h = brick_grid(FENCE, FENCE * T, T / 2)[2]
    joints = np.where(v > h, joints_h.T, joints_h) & (wall > 0)
    pieces, gaps = split(wall, joints)
    layers = [(pieces, along(paint(STONE, blocks(3, FENCE)), h, v), 1.0), (gaps, paint((92, 90, 84), np.ones((T, T))), 1.0)]
    if sides not in ("RL", "BT"):
        layers.append((square(C, C, POST), paint((120, 120, 114), pillar(4, "stone")), 1.0))
    return layers


def hedge_mask(sides):
    """A plant fence: round the middle and along each joined arm, its outline lumpy but the same at every tile's edge
    (width and noise repeat every tile), so arms meet their neighbours'."""
    y, x = YX
    n = field(T / 7.0, T / 7.0, 21) * 0.035 * T
    d = np.hypot(x - C, y - C) - FENCE * 1.9 * T
    for side, (sx, sy) in {"R": (1, 0), "L": (-1, 0), "B": (0, 1), "T": (0, -1)}.items():
        if side not in sides:
            continue
        s_ = x if sx else y
        across = np.abs(y - C) if sx else np.abs(x - C)
        w = FENCE * 1.5 * T * (1 + 0.12 * np.sin(2 * np.pi * 3 * s_ / T + 0.7))
        on = (s_ - C) * (sx + sy) >= 0
        d = np.minimum(d, np.where(on, across - w, 1e9))
    return (d + n < 0).astype(np.float32)


def flowers(mask, seed, count):
    """A few red hibiscus flowers on the hedge, away from the tile's edges: [(mask, rgb, edge)]."""
    rng = np.random.default_rng(seed)
    inner = erode(mask, 3 * SS)
    petals = np.zeros((T, T), np.float32)
    hearts = np.zeros((T, T), np.float32)
    placed = 0
    for _ in range(60):
        if placed >= count:
            break
        cx, cy = rng.uniform(6 * SS, T - 6 * SS, 2)
        if inner[int(cy), int(cx)] <= 0:
            continue
        petals = np.maximum(petals, disc(cx, cy, 2.0 * SS))
        hearts = np.maximum(hearts, disc(cx, cy, 0.7 * SS))
        placed += 1
    return [(petals, paint((200, 44, 46), np.ones((T, T))), 1.0), (hearts, paint((236, 196, 90), np.ones((T, T))), 1.0)]


def hedge(sides, seed=0):
    m = hedge_mask(sides)
    return [(m, paint(LEAF, leaves(31)), 1.0)] + flowers(m, 101 + seed, 1 + len(sides) // 2 + seed % 2)


def brick_wall(sides):
    """A candi fence: a low Majapahit brick wall, each brick its own, a brick coping along its top, and at its ends,
    corners and joins a pillar built up in tiers like a candi, crowned with a knob."""
    h, v = arms(sides, FENCE)
    wall = np.maximum(h, v)
    joints_h = brick_grid(FENCE)[2]
    joints = np.where(v > h, joints_h.T, joints_h) & (wall > 0)
    pieces, gaps = split(wall, joints)
    layers = [(pieces, along(paint(BRICK, bricks(7, FENCE)), h, v), 1.0), (gaps, paint((132, 104, 82), np.ones((T, T))), 1.0)]
    ch, cv = arms(sides, FENCE * 0.45)
    layers.append((np.maximum(ch, cv), paint((186, 94, 64), 1 + field(T / 8.0, T / 8.0, 8) * 0.06), 1.0))
    if sides not in ("RL", "BT"):
        layers += tiers(C, C, POST * 1.1, ((160, 76, 52), (178, 88, 60), (190, 98, 66)))
    return layers


FENCES = {"bamboo_rail": bamboo_rail, "plank": plank, "stick": stick, "stone": stone, "hedge": hedge,
          "brick_wall": brick_wall}


# ------------------------------------------------------------------ gates: one cell drawn across, joined at both sides

def gate_bamboo_rail(left=True, right=True):
    """A swing gate of three lashed poles between two round posts, the fence's rails running on to the cell's edges."""
    y, x = YX
    lo, hi, at = ends(left, right)
    half = FENCE * 1.1
    leaf = box(lo, C - half * T, hi, C + half * T)
    pv = (y - (C - half * T)) / (2 * half * T / 3)
    poles = paint((222, 200, 136), 0.82 + 0.28 * np.sin(np.clip(pv - np.floor(pv), 0, 1) * np.pi))
    for sx in (0.38, 0.62):
        poles[np.abs(x - sx * T) < 1.2 * SS] = (110, 84, 52)
    r = POST * T
    posts = union([disc(cx, C, r) for cx in at])
    post_tex = np.where(x < C, culm_top(GATE_AT * T, C, r), culm_top((1 - GATE_AT) * T, C, r))
    return [(stubs(FENCE * 0.8, GATE_AT, left, right), paint((204, 182, 116), split_bamboo(FENCE * 0.8, 3)), 1.0),
            (leaf, poles, 1.0), (posts, paint((166, 160, 90), post_tex), 1.0)]


def gate_plank(left=True, right=True):
    """A gate of upright boards with a Z brace, between two square posts; the fence's boards run on to the edges."""
    y, x = YX
    lo, hi, at = ends(left, right)
    leaf = box(lo, C - FENCE * 0.85 * T, hi, C + FENCE * 0.85 * T)
    width = (1 - 2 * GATE_AT) * T / 5
    board = np.floor((x - GATE_AT * T) / width)
    fx = (x - GATE_AT * T) / width - board
    seams = (np.minimum(fx, 1 - fx) * width < 0.7 * SS) & (leaf > 0)
    brace = (np.abs((y - C) - (x - C) * 0.22) < 1.2 * SS) & (leaf > 0)
    pieces, gaps = split(leaf, seams)
    tint = 0.92 + 0.14 * ((np.sin(board * 12.9898) * 43758.5453) % 1.0)
    posts = union([square(cx, C, POST) for cx in at])
    return [(stubs(FENCE, GATE_AT, left, right), paint(WOOD, planks(1, half=FENCE)), 1.0), (pieces, paint(WOOD, tint * 1.05), 1.0),
            (gaps, paint(WOOD, np.full((T, T), 0.55)), 1.0), (brace.astype(np.float32), paint((112, 78, 48), np.ones((T, T))), 1.0),
            (posts, paint((122, 84, 52), np.ones((T, T))), 1.0)]


def gate_stick(left=True, right=True):
    """A gate of stakes lashed to a frame, a stick brace across it, between two thicker stakes."""
    y, x = YX
    lo, hi, at = ends(left, right)
    frame = box(lo, C - RAIL * 1.8 * T, hi, C + RAIL * 1.8 * T)
    tops = stakes("RL", centre=False) * (frame == 0)
    brace = ((np.abs(y - C - (x - C) * 0.12) < 1.0 * SS) & (frame > 0)).astype(np.float32)
    posts = union([disc(cx, C, STAKE * 1.5 * T) for cx in at])
    return [(stubs(RAIL, GATE_AT, left, right), paint((104, 82, 56), np.ones((T, T))), 1.0), (frame, paint((140, 112, 76), np.ones((T, T))), 1.0),
            (np.maximum(tops, brace), stick_tex(), 1.0), (posts, paint((104, 82, 56), np.ones((T, T))), 1.0)]


def gate_stone(left=True, right=True):
    """An opening in the stone wall between two square block pillars."""
    lo, hi, at = ends(left, right)
    stub = stubs(FENCE, GATE_AT, left, right)
    pieces, gaps = split(stub, brick_grid(FENCE, FENCE * T, T / 2)[2] & (stub > 0))
    pillars = union([square(cx, C, POST * 1.1) for cx in at])
    return [(pieces, paint(STONE, blocks(3, FENCE)), 1.0), (gaps, paint((92, 90, 84), np.ones((T, T))), 1.0),
            (pillars, paint((120, 120, 114), pillar(4, "stone")), 1.0)]


def gate_hedge(left=True, right=True):
    """An opening in the plant fence between two clipped hedge posts, squarer and denser than the hedge, a flower on
    each; the middle left empty."""
    lo, hi, at = ends(left, right)
    posts = union([square(cx, C, POST * 1.3) for cx in at])
    return [(stubs(FENCE * 1.5, GATE_AT, left, right), paint(LEAF, leaves(31)), 1.0), (posts, paint((70, 112, 50), leaves(33, fine=True)), 1.0)] \
        + flowers(posts, 7, len(at))


def gate_brick(left=True, right=True):
    """Candi bentar: a split gate, two tiered candi towers either side of an opening in the cell's middle, the candi
    fence running into them."""
    lo, hi, at = ends(left, right)
    stub = stubs(FENCE, GATE_AT, left, right)
    pieces, gaps = split(stub, brick_grid(FENCE)[2] & (stub > 0))
    layers = [(pieces, paint(BRICK, bricks(7, FENCE)), 1.0), (gaps, paint((132, 104, 82), np.ones((T, T))), 1.0)]
    for cx in at:
        layers += tiers(cx, C, POST * 1.3, ((160, 76, 52), (172, 84, 58), (184, 92, 62), (196, 102, 70)))
    return layers


GATES = {"bamboo_rail": gate_bamboo_rail, "plank": gate_plank, "stick": gate_stick, "stone": gate_stone,
         "hedge": gate_hedge, "brick": gate_brick}


def fence_sheet(key):
    img = Image.new("RGBA", (CELL * 6, CELL * 3), (0, 0, 0, 0))
    for (x, y), sides in SIDES.items():
        layers = hedge(sides, x + y * 6) if key == "hedge" else FENCES[key](sides)
        img.alpha_composite(render(layers, soft=2.6 if key == "hedge" else 1.6), (x * CELL, y * CELL))
    return img


# A gate sheet's 6 tiles: (down, a post on the first side, a post on the second side). The first side is the left
# across, the top down; a side with no post meets another cell of the same gate.
GATE_TILES = ((False, True, True), (True, True, True), (False, False, True), (False, True, False),
              (True, False, True), (True, True, False))


def gate_sheet(key):
    soft = 2.6 if key == "hedge" else 1.6
    img = Image.new("RGBA", (CELL * len(GATE_TILES), CELL), (0, 0, 0, 0))
    for k, (down, first, second) in enumerate(GATE_TILES):
        layers = GATES[key](first, second)
        img.alpha_composite(render(turned(layers) if down else layers, soft), (k * CELL, 0))
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
