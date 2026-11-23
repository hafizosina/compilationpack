"""Floor surfaces in RimWorld's style: one large seamless texture per floor (512 px = 8 cells at 64 px a cell), low
contrast, slow light and dark patches, fine grain, irregular pieces each softly bevelled (lit from the top-left).
The floor shader (module 10 art/floor.gdshader) shows them where floors lie. Also the attap roof, a dual-grid sheet.
Beside each floor whose edge is cut by its pieces, a piece map (pieces_<key>.png, see piece_map()).
usage: python make_floors.py [key ...]      (needs Pillow, numpy)"""
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "Structure"))
import make_walls  # noqa: E402

N = 512                         # final size
K = 2                           # drawn at K times, then scaled down
M = N * K
CELL = 64 * K                   # one cell, in drawing pixels
Y, X = np.mgrid[0:M, 0:M] + 0.5


def field(cycles, seed, aspect=1.0):
    """Seamless noise in -1..1 with about `cycles` bumps across the texture (`aspect` stretches it along x)."""
    rng = np.random.default_rng(seed)
    fx = np.fft.fftfreq(M)[None, :] * M / (cycles / aspect)
    fy = np.fft.fftfreq(M)[:, None] * M / cycles
    out = np.real(np.fft.ifft2(np.fft.fft2(rng.normal(size=(M, M))) * np.exp(-(fx ** 2 + fy ** 2))))
    out -= out.mean()
    return out / (np.abs(out).max() + 1e-9)


def patches(seed, amount=0.07):
    """The slow light and dark wash RimWorld's floors have, plus a fine grain."""
    return 1 + field(3, seed) * amount + field(10, seed + 1) * amount * 0.5 + field(90, seed + 2) * 0.03


def voronoi(n, seed, jitter=0.8):
    """Seamless cells from an n x n jittered grid: nearest distance, second distance, the cell's id and centre."""
    rng = np.random.default_rng(seed)
    pts = (np.stack(np.meshgrid(np.arange(n), np.arange(n)), -1).reshape(-1, 2) + 0.5
           + (rng.random((n * n, 2)) - 0.5) * jitter) * (M / n)
    f1 = np.full((M, M), 1e9, np.float32)
    f2 = np.full((M, M), 1e9, np.float32)
    ids = np.zeros((M, M), np.int32)
    cx = np.zeros((M, M), np.float32)
    cy = np.zeros((M, M), np.float32)
    for k, (px, py) in enumerate(pts):
        for ox in (-M, 0, M):
            for oy in (-M, 0, M):
                qx, qy = px + ox, py + oy
                if qx < -M * 0.25 or qx > M * 1.25 or qy < -M * 0.25 or qy > M * 1.25:
                    continue
                d = np.hypot(X - qx, Y - qy)
                closer = d < f1
                f2 = np.where(closer, f1, np.minimum(f2, d))
                ids = np.where(closer, k, ids)
                cx = np.where(closer, qx, cx)
                cy = np.where(closer, qy, cy)
                f1 = np.where(closer, d, f1)
    return f1, f2, ids, cx, cy


def dirt_in_gaps(albedo, gap, seed, joint, creep):
    """Brown earth with fine grit filling the joints (gap under `joint`), and a little of it creeping onto the
    stone's edge (out to `creep`), more in some places than others."""
    soil = np.array((122, 94, 62), np.float32) * (patches(seed, 0.10) * (1 + field(150, seed + 3) * 0.10))[..., None]
    grit = field(200, seed + 4) > 0.5
    soil[grit] *= 1.18
    patchy = np.clip(field(12, seed + 5) * 0.8 + 0.4, 0, 1)
    stain = np.clip(1 - (gap - joint) / (creep - joint), 0, 1) ** 2 * 0.45 * patchy
    out = albedo * (1 - stain[..., None]) + soil * stain[..., None]
    out[gap < joint] = soil[gap < joint]
    return out


def tint_of(ids, seed, spread):
    rng = np.random.default_rng(seed)
    return (1 - spread / 2 + rng.random(ids.max() + 1) * spread)[ids]


LIGHT = np.array((-1.0, -1.0, 1.3)) / np.linalg.norm((-1.0, -1.0, 1.3))     # from the top-left, above


def relief(albedo, height, strength=1.0, occlusion=0.3):
    """Lights `albedo` by `height` (in drawing pixels): slopes facing the top-left brighter, the far ones darker,
    and the low parts shadowed by `occlusion`. Gradients wrap, so the texture stays seamless."""
    gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5 * strength
    gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5 * strength
    n = np.stack([-gx, -gy, np.ones_like(gx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    lam = np.clip((n @ LIGHT) / LIGHT[2], 0.25, 1.8)
    low = (height - height.min()) / (np.ptp(height) + 1e-6)
    return albedo * (lam * (1 - occlusion * (1 - low)))[..., None]


def bevel(d, width):
    """0 at an edge, rising smoothly to 1 at `width` in."""
    t = np.clip(d / width, 0, 1)
    return t * t * (3 - 2 * t)


def boards():
    """The planks' layout: four rows a cell, random lengths, joints staggered. Returns each pixel's board id, its
    distance along the board, the board's length, and the board width."""
    rng = np.random.default_rng(11)
    w = CELL / 4
    rows = int(M / w)
    row = np.floor(Y / w).astype(int)
    board = np.zeros((M, M), np.int32)
    fx = np.zeros((M, M), np.float32)
    length = np.zeros((M, M), np.float32)
    for r in range(rows):
        cuts = [rng.uniform(0, M)]
        while True:
            nxt = cuts[-1] + rng.uniform(0.9, 2.8) * CELL
            if nxt >= cuts[0] + M - 0.7 * CELL:
                break
            cuts.append(nxt)
        starts = np.concatenate([np.array(cuts) - cuts[0], [M]])
        sel = row == r
        rel = (X[sel] - cuts[0]) % M
        seg = np.searchsorted(starts, rel, side="right") - 1
        board[sel] = seg + r * 100
        fx[sel] = rel - starts[seg]
        length[sel] = starts[seg + 1] - starts[seg]
    return board, fx, length, w


def teak():
    """Teak planks of random length, four to a cell, joints staggered: each board raised with rounded edges, a
    little uneven, grain along it, a few knots."""
    rng = np.random.default_rng(12)
    board, fx, length, w = boards()
    rows = int(M / w)
    fy = (Y % w)
    grain = field(6, 12, aspect=12) * 0.10 + field(30, 13, aspect=16) * 0.06
    albedo = np.array((150, 104, 62), np.float32) * (tint_of(board, 14, 0.18) * (1 + grain) * patches(15, 0.06))[..., None]
    edge = bevel(np.minimum(fy, w - fy), 2.2 * K) * bevel(np.minimum(fx, length - fx), 2.2 * K)
    height = edge * 4.0 + tint_of(board, 16, 0.6) * edge + grain * 3.0
    for r in range(rows):
        for k in range(40):
            if rng.random() < 0.012:
                kx, ky = k * M / 40 + rng.uniform(0, M / 40), (r + 0.5) * w
                d = np.hypot((X - kx + M / 2) % M - M / 2, (Y - ky) * 1.6)
                m = d < 5 * K
                albedo[m] *= (0.62 + 0.38 * d[m] / (5 * K))[..., None]
                height[m] -= (1 - d[m] / (5 * K)) * 1.2
    return relief(albedo, height, 1.0, 0.45)


def flagstones():
    """Irregular grey andesite flags (crazy paving): each raised from sunken grout with worn edges, tilted a little,
    its face rough, a little lighter or darker than the next."""
    f1, f2, ids, cx, cy = voronoi(14, 21)
    gap = f2 - f1
    rng = np.random.default_rng(26)
    tilt = rng.normal(0, 0.012, (ids.max() + 1, 2))
    face = bevel(gap - 0.03 * CELL, 0.07 * CELL)
    height = face * (6.0 + (X - cx) * tilt[ids, 0] * K + (Y - cy) * tilt[ids, 1] * K) \
        + face * (field(40, 27) * 0.8 + field(140, 28) * 0.4)
    albedo = np.array((150, 148, 140), np.float32) * (tint_of(ids, 22, 0.18) * patches(23, 0.07))[..., None]
    albedo[field(160, 24) > 0.55] *= 0.88
    albedo = dirt_in_gaps(albedo, gap, 25, 0.03 * CELL, 0.09 * CELL)
    return relief(albedo, height, 1.0, 0.45)


def cobbles():
    """River cobbles set in packed earth, worn flat on top and rounded at the rim, the earth a little lower between."""
    f1, f2, ids, cx, cy = voronoi(22, 31, jitter=0.7)
    gap = f2 - f1
    r = f1 / (f1 + np.maximum(gap / 2 - 0.018 * CELL, 1e-3))
    stone = r < 1
    dome = np.clip(1 - r ** 3, 0, 1)                                 # worn: flat on top, rounded only at the rim
    height = np.where(stone, dome * 3.5, 0.0) + field(60, 34) * 0.3
    colour = np.array((140, 134, 124), np.float32) * (tint_of(ids, 33, 0.26) * patches(35, 0.04))[..., None]
    in_from_edge = np.where(stone, (1 - r) * (f1 + np.maximum(gap / 2 - 0.018 * CELL, 1e-3)), 0.0)
    albedo = dirt_in_gaps(colour, in_from_edge, 32, 0.001, 0.05 * CELL)
    return relief(albedo, height, 0.8, 0.18)


def pandan():
    """A pandan mat (anyaman) in a diagonal 2-over-2 twill: flat strips with square ends, each span two strips long,
    dipping only where it goes under the next; fibres along each strip, each strip a shade apart."""
    p = CELL / 7
    u, v = (X + Y) / p, (X - Y) / p
    i, j = np.floor(u), np.floor(v)
    over = ((i + j) % 4) < 2                                          # a strip along u is on top here
    fu, fv = u - i, v - j
    across = np.where(over, fv, fu)
    run = np.where(over, ((i + j) % 4 + fu) / 2, (((i + j) % 4 - 2) + fv) / 2)   # 0..1 along the span on top
    fibre = np.sin(across * math.pi * 11 + field(40, 41) * 2.5)
    height = bevel(np.minimum(across, 1 - across), 0.12) * 1.6 + bevel(np.minimum(run, 1 - run), 0.10) * 1.8 \
        + np.where(over, 0.6, 0.0) + fibre * 0.15
    strip = np.where(over, j, i).astype(np.int32) % 64
    albedo = np.array((180, 166, 108), np.float32) * (tint_of(strip, 43, 0.12) * patches(42, 0.05) * (1 + fibre * 0.03))[..., None]
    return relief(albedo, height, 1.0, 0.45)


def earth():
    """A worn path: packed earth, lighter than the dirt round it, lumpy, faint ruts, small pebbles standing out."""
    rng = np.random.default_rng(51)
    height = field(10, 54) * 2.5 + field(30, 55) * 1.0 + field(90, 56) * 0.4 + field(4, 53, aspect=6) * 2.0
    albedo = np.array((160, 128, 90), np.float32) * patches(52, 0.08)[..., None]
    for _ in range(110):
        x, y, rad = rng.uniform(0, M), rng.uniform(0, M), rng.uniform(1.4, 3.0) * K
        d = np.hypot((X - x + M / 2) % M - M / 2, (Y - y + M / 2) % M - M / 2)
        m = d < rad
        albedo[m] = np.array((150, 140, 124), np.float32) * rng.uniform(0.85, 1.1)
        height[m] += np.sqrt(1 - (d[m] / rad) ** 2) * 3.0
    return relief(albedo, height, 1.0, 0.3)


def poles():
    """The bamboo poles' layout: widths across the texture; returns each pixel's pole, the widths and their edges."""
    rng = np.random.default_rng(61)
    widths = []
    while sum(widths) < M - 0.25 * CELL:
        widths.append(rng.uniform(0.17, 0.25) * CELL)
    widths = np.array(widths) * M / sum(widths)
    edges = np.concatenate([[0], np.cumsum(widths)])
    return np.clip(np.searchsorted(edges, X, side="right") - 1, 0, len(widths) - 1), widths, edges


def bamboo():
    """Whole bamboo poles laid side by side (lantai bambu), running down the texture: each round across, a little
    wider or narrower and a different tan than the next, node rings at uneven heights, long streaks, dark seams."""
    rng = np.random.default_rng(62)
    pole, widths, edges = poles()
    across = (X - edges[pole]) / widths[pole]
    hues = np.array([(204, 172, 108), (190, 152, 92), (212, 184, 120), (176, 136, 80), (198, 170, 110)], np.float32)
    colour = hues[rng.integers(0, len(hues), len(widths))][pole]
    shade = tint_of(pole, 62, 0.14) * (1 + field(3, 63, aspect=1 / 10) * 0.08 + field(40, 64, aspect=1 / 14) * 0.04)
    albedo = colour * shade[..., None]
    height = np.sqrt(np.clip(1 - (2 * across - 1) ** 2, 0, 1)) * 5.0
    for k in range(len(widths)):
        start, step = rng.uniform(0, M), rng.uniform(1.0, 1.5) * CELL
        n = max(1, int(round(M / step)))
        step = M / n                                                    # whole nodes a texture: seamless down
        for m in range(n):
            ny = (start + m * step) % M
            d = np.abs((Y - ny + M / 2) % M - M / 2)
            ring = (pole == k) & (d < 1.6 * K)
            height[ring] += (1 - d[ring] / (1.6 * K)) * 1.2
            albedo[ring & (d < 0.6 * K)] *= 0.72
        if rng.random() < 0.3:                                          # an old brown blotch on some poles
            by, reach = rng.uniform(0, M), rng.uniform(0.3, 0.8) * CELL
            d = np.abs((Y - by + M / 2) % M - M / 2)
            blot = (pole == k) & (d < reach)
            fade = (1 - (d[blot] / reach) ** 2)[..., None]
            albedo[blot] *= 1 - fade * (1 - np.array((0.86, 0.78, 0.70), np.float32))
    return relief(albedo, height, 1.0, 0.55)


SHIFT = 0.12                    # cells a plank or pole end may reach past the cell line or stop short


def piece_map(off_x, off_y, rand, stray):
    """The floor shader's piece map: R, G the offset (in cells, -1..1) from a pixel to the point that decides
    whether its piece is drawn near an edge; B the piece's random reach (0.5 = none); A its chance to lie as a
    stray past the edge (1 = never)."""
    out = np.stack([np.clip(off_x, -1, 1) * 0.5 + 0.5, np.clip(off_y, -1, 1) * 0.5 + 0.5, rand, stray], -1)
    return np.clip(np.round(out * 255), 0, 255).astype(np.uint8)


def stone_pieces(n, seed, jitter):
    """Each stone decides by its own centre, with its own reach and stray chance."""
    f1, f2, ids, cx, cy = voronoi(n, seed, jitter)
    rand = np.random.default_rng(seed + 100).random(ids.max() + 1)
    stray = np.random.default_rng(seed + 200).random(ids.max() + 1)
    return piece_map((cx - X) / CELL, (cy - Y) / CELL, rand[ids], stray[ids])


def plank_pieces():
    """A plank decides by its own middle line, its end shifted along it by its own amount."""
    board, fx, length, w = boards()
    shift = (np.random.default_rng(111).random(board.max() + 1) - 0.5) * 2 * SHIFT
    centre_y = np.floor(Y / w) * w + w / 2
    return piece_map(shift[board], (centre_y - Y) / CELL, np.full(X.shape, 0.5), np.ones(X.shape))


def pole_pieces():
    """A pole decides by its own middle line, its end shifted along it by its own amount."""
    pole, widths, edges = poles()
    shift = (np.random.default_rng(112).random(len(widths)) - 0.5) * 2 * SHIFT
    centre_x = edges[pole] + widths[pole] / 2
    return piece_map((centre_x - X) / CELL, shift[pole], np.full(X.shape, 0.5), np.ones(X.shape))


PIECES = {"stone": lambda: stone_pieces(14, 21, 0.8), "road": lambda: stone_pieces(22, 31, 0.7),
          "wood": plank_pieces, "bamboo": pole_pieces}

SURFACES = {"wood": teak, "stone": flagstones, "road": cobbles, "rug": pandan, "dirt_path": earth, "bamboo": bamboo}


def roof():
    """Attap thatch, a dual-grid sheet (roofs keep the dual grid): rows of palm-leaf shingles, leaf strokes down
    each, the lower edge of a row darker."""
    T, SS = make_walls.T, make_walls.SS
    yy, xx = np.mgrid[0:T, 0:T] + 0.5
    h = T / 5
    fy = (yy % h) / h
    row = np.floor(yy / h)
    stroke = 1 + 0.10 * np.sin((xx + row * 7) * 2 * math.pi / (T / 24)) + make_walls.field(T / 1.0, T / 20.0, 51) * 0.08
    tex = np.array((156, 126, 74), np.float32) * (stroke * (1.08 - 0.40 * fy ** 2.5))[..., None]
    dual = {(0, 0): "0001", (1, 0): "0011", (2, 0): "0010", (3, 0): "1110", (4, 0): "1101", (5, 0): "1001",
            (0, 1): "0101", (1, 1): "1111", (2, 1): "1010", (3, 1): "1011", (4, 1): "0111", (5, 1): "0110",
            (0, 2): "0100", (1, 2): "1100", (2, 2): "1000", (3, 2): "1111", (4, 2): "1111", (5, 2): "1111"}
    img = Image.new("RGBA", (64 * 6, 64 * 3), (0, 0, 0, 0))
    for (ax, ay), bits in dual.items():
        m = np.zeros((T, T), np.float32)
        for q, (qy, qx) in enumerate(((0, 0), (0, 1), (1, 0), (1, 1))):
            if bits[q] == "1":
                m[qy * T // 2:(qy + 1) * T // 2, qx * T // 2:(qx + 1) * T // 2] = 1
        s = make_walls.blur(m, 2.0 * SS)
        k = int(1.4 * SS)
        col = tex * (1.0 - 0.6 * (make_walls.shift(s, k, k) - make_walls.shift(s, -k, -k)))[..., None]
        ring = (m > 0) & ~(make_walls.erode(m, 1.4 * SS) > 0)
        if bits != "1111":
            col[ring] *= 0.45
        out = np.zeros((T, T, 4), np.float32)
        out[..., :3] = col
        out[..., 3] = m * 255
        tile = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA").resize((64, 64), Image.LANCZOS)
        img.alpha_composite(tile, (ax * 64, ay * 64))
    return img


def main():
    keys = sys.argv[1:] or list(SURFACES) + ["roof"]
    for key in keys:
        if key == "roof":
            roof().save(os.path.join(HERE, "roof_thatch.png"))
            print("roof_thatch.png")
            continue
        img = Image.fromarray(np.clip(SURFACES[key](), 0, 255).astype(np.uint8), "RGB").resize((N, N), Image.LANCZOS)
        img.save(os.path.join(HERE, f"surface_{key}.png"))
        print(f"surface_{key}.png")
        if key in PIECES:                                               # exact values: every K-th pixel, no filtering
            Image.fromarray(PIECES[key]()[::K, ::K], "RGBA").save(os.path.join(HERE, f"pieces_{key}.png"))
            print(f"pieces_{key}.png")


if __name__ == "__main__":
    main()
