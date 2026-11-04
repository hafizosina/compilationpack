"""Generates module 10's placeholder art. Run: python3 make_placeholders.py (needs Pillow, numpy)."""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
CELL = 32
rng = np.random.default_rng(10)

# Dual-grid layout, same as WoodFloor.png: atlas (x, y) -> filled quadrants (TL, TR, BL, BR).
DUAL = {
    (0, 0): "0001", (1, 0): "0011", (2, 0): "0010", (3, 0): "1110", (4, 0): "1101", (5, 0): "1001",
    (0, 1): "0101", (1, 1): "1111", (2, 1): "1010", (3, 1): "1011", (4, 1): "0111", (5, 1): "0110",
    (0, 2): "0100", (1, 2): "1100", (2, 2): "1000", (3, 2): "1111", (4, 2): "1111", (5, 2): "1111",
}
# Wall side layout, same as WoodWall.png: atlas (x, y) -> connected sides (R, B, L, T).
SIDES = {
    (0, 0): "RB", (1, 0): "RL", (2, 0): "BL", (3, 0): "R", (4, 0): "RBL", (5, 0): "B",
    (0, 1): "BT", (1, 1): "", (2, 1): "BT", (3, 1): "RBT", (4, 1): "RBLT", (5, 1): "BLT",
    (0, 2): "RT", (1, 2): "RL", (2, 2): "LT", (3, 2): "T", (4, 2): "RLT", (5, 2): "L",
}


def rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=float)


def texture(kind, base, seed):
    """A 32x32 RGB fill for one material."""
    r = np.random.default_rng(seed)
    img = np.tile(rgb(base), (CELL, CELL, 1))
    img += r.normal(0, 7, (CELL, CELL, 1))
    y, x = np.mgrid[0:CELL, 0:CELL]
    if kind == "grass":
        blades = r.random((CELL, CELL)) < 0.08
        img[blades] -= 28
        img[r.random((CELL, CELL)) < 0.03] += 30
    elif kind == "dirt":
        img[r.random((CELL, CELL)) < 0.06] -= 30
        img[r.random((CELL, CELL)) < 0.03] += 20
    elif kind == "sand":
        img[r.random((CELL, CELL)) < 0.07] += 22
        img[r.random((CELL, CELL)) < 0.03] -= 18
    elif kind == "water":
        waves = ((y + (x // 6) * 3) % 10 == 0) & (r.random((CELL, CELL)) < 0.7)
        img[waves] += 35
    elif kind == "stone":
        img[(x % 16 == 0) | (y % 16 == 0)] -= 35
        img[(x % 16 == 1) | (y % 16 == 1)] += 12
    elif kind == "road":
        cob = ((x + (y // 8 % 2) * 4) % 8 == 0) | (y % 8 == 0)
        img[cob] -= 30
    elif kind == "planks":
        img[(y % 8 == 0)] -= 40
        img[((x + (y // 8) * 11) % 32 == 0)] -= 30
    elif kind == "rug":
        img[((x + y) % 8 < 2)] -= 22
        img[((x - y) % 8 < 1)] += 18
    elif kind == "roof":
        rows = y % 8 == 0
        img[rows] -= 40
        stagger = (x + (y // 8 % 2) * 8) % 16 == 0
        img[stagger] -= 25
    return np.clip(img, 0, 255)


def dual_sheet(name, kind, base, outline_dark=55):
    sheet = np.zeros((CELL * 3, CELL * 6, 4), dtype=np.uint8)
    for (ax, ay), quads in DUAL.items():
        mask = np.zeros((CELL, CELL))
        h = CELL // 2
        for i, (qy, qx) in enumerate([(0, 0), (0, 1), (1, 0), (1, 1)]):
            if quads[i] == "1":
                mask[qy * h:(qy + 1) * h, qx * h:(qx + 1) * h] = 1.0
        # Round corners: blur with edge padding so tile borders stay straight, then threshold.
        pad = 6
        padded = np.pad(mask, pad, mode="edge")
        blurred = np.array(Image.fromarray((padded * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)))
        shape = blurred[pad:-pad, pad:-pad] >= 128
        # Outline: inside pixels within 2 px of the outside.
        p = np.pad(shape, 2, mode="edge")
        inner = shape.copy()
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                inner &= p[2 + dy:2 + dy + CELL, 2 + dx:2 + dx + CELL]
        fill = texture(kind, base, seed=ax * 7 + ay * 13 + sum(map(ord, name)))
        fill[shape & ~inner] -= outline_dark
        tile = np.zeros((CELL, CELL, 4), dtype=np.uint8)
        tile[..., :3] = np.clip(fill, 0, 255).astype(np.uint8)
        tile[..., 3] = np.where(shape, 255, 0)
        sheet[ay * CELL:(ay + 1) * CELL, ax * CELL:(ax + 1) * CELL] = tile
    Image.fromarray(sheet, "RGBA").save(os.path.join(HERE, name))


def wall_sheet(name, beam, post, edge):
    img = Image.new("RGBA", (CELL * 6, CELL * 3), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for (ax, ay), sides in SIDES.items():
        ox, oy, c = ax * CELL, ay * CELL, CELL // 2
        w = 5
        if "R" in sides: d.rectangle([ox + c, oy + c - w, ox + CELL - 1, oy + c + w], fill=beam, outline=edge)
        if "L" in sides: d.rectangle([ox, oy + c - w, ox + c, oy + c + w], fill=beam, outline=edge)
        if "B" in sides: d.rectangle([ox + c - w, oy + c, ox + c + w, oy + CELL - 1], fill=beam, outline=edge)
        if "T" in sides: d.rectangle([ox + c - w, oy, ox + c + w, oy + c], fill=beam, outline=edge)
        d.rectangle([ox + c - 8, oy + c - 8, ox + c + 7, oy + c + 7], fill=post, outline=edge, width=2)
        d.rectangle([ox + c - 3, oy + c - 3, ox + c + 2, oy + c + 2], outline=edge)
    img.save(os.path.join(HERE, name))


def door_sheet(name):
    """Four 48 px tiles, oversized like WoodenDoor.png: H closed, V closed, H open, V open."""
    T = 48
    img = Image.new("RGBA", (T * 4, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    wood, edge, frame = (139, 94, 52, 255), (60, 38, 20, 255), (90, 90, 90, 255)
    c = T // 2
    # Hinge posts at the cell's edges (cell is the middle 32 px).
    def posts(ox, vertical):
        for s in (-16, 15):
            if vertical: d.rectangle([ox + c - 4, s + c - 3, ox + c + 3, s + c + 3], fill=frame)
            else: d.rectangle([ox + s + c - 3, c - 4, ox + s + c + 3, c + 3], fill=frame)
    d.rectangle([c - 15, c - 3, c + 14, c + 2], fill=wood, outline=edge); posts(0, False)
    d.rectangle([T + c - 3, c - 15, T + c + 2, c + 14], fill=wood, outline=edge); posts(T, True)
    d.rectangle([2 * T + c - 15, c - 3, 2 * T + c - 10, c + 24], fill=wood, outline=edge); posts(2 * T, False)
    d.rectangle([3 * T + c - 3, c - 15, 3 * T + c + 24, c - 10], fill=wood, outline=edge); posts(3 * T, True)
    img.save(os.path.join(HERE, name))


def objects_atlas(name):
    """Furniture and plants on a 32 px grid. Layout in README.md."""
    img = Image.new("RGBA", (CELL * 8, CELL * 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ink = (42, 32, 22, 255)
    wood, dark_wood, cloth = (150, 101, 58, 255), (110, 72, 40, 255), (70, 110, 160, 255)
    def r(cx, cy, w, h, x0, y0, x1, y1, **kw):
        d.rectangle([cx * CELL + x0, cy * CELL + y0, cx * CELL + x1, cy * CELL + y1], outline=ink, **kw)
    def e(cx, cy, x0, y0, x1, y1, **kw):
        d.ellipse([cx * CELL + x0, cy * CELL + y0, cx * CELL + x1, cy * CELL + y1], outline=ink, **kw)
    r(0, 0, 1, 2, 4, 2, 27, 61, fill=dark_wood); r(0, 0, 1, 2, 6, 4, 25, 14, fill=(235, 230, 215, 255)); r(0, 0, 1, 2, 6, 18, 25, 59, fill=cloth)  # bed 1x2
    r(1, 0, 2, 2, 4, 2, 59, 61, fill=dark_wood); r(1, 0, 2, 2, 7, 4, 29, 14, fill=(235, 230, 215, 255)); r(1, 0, 2, 2, 34, 4, 56, 14, fill=(235, 230, 215, 255)); r(1, 0, 2, 2, 6, 18, 57, 59, fill=(150, 60, 60, 255))  # double bed 2x2
    r(3, 0, 1, 1, 4, 4, 27, 27, fill=wood)  # table
    r(4, 0, 2, 1, 3, 5, 60, 26, fill=wood)  # long table 2x1
    r(6, 0, 1, 1, 9, 10, 22, 24, fill=wood); r(6, 0, 1, 1, 9, 6, 22, 10, fill=dark_wood)  # chair
    r(7, 0, 1, 1, 3, 3, 28, 28, fill=(80, 80, 85, 255))  # stove
    for px, py in ((10, 10), (21, 10), (10, 21), (21, 21)): e(7, 0, px - 4, py - 4, px + 4, py + 4, fill=(40, 40, 40, 255))
    r(3, 1, 1, 1, 4, 7, 27, 25, fill=wood); r(3, 1, 1, 1, 4, 13, 27, 16, fill=(185, 138, 50, 255))  # chest
    r(4, 1, 2, 1, 2, 6, 61, 25, fill=dark_wood); d.line([4 * CELL + 10, CELL + 12, 4 * CELL + 24, CELL + 12], fill=(170, 170, 170, 255), width=2); r(4, 1, 2, 1, 40, 10, 50, 20, fill=(150, 150, 150, 255))  # workbench 2x1
    r(6, 1, 1, 1, 3, 3, 28, 12, fill=dark_wood)  # shelf, against a wall
    for k in range(4): r(6, 1, 1, 1, 5 + k * 6, 5, 8 + k * 6, 10, fill=[(160, 60, 60, 255), (60, 120, 60, 255), (60, 80, 150, 255), (190, 170, 80, 255)][k])
    e(7, 1, 5, 5, 26, 26, fill=wood); e(7, 1, 9, 9, 22, 22, fill=dark_wood)  # barrel
    r(0, 2, 2, 2, 4, 10, 59, 53, fill=dark_wood); e(0, 2, 18, 18, 45, 45, fill=(180, 180, 190, 255)); e(0, 2, 28, 28, 35, 35, fill=ink)  # sawmill 2x2
    d.polygon([(2 * CELL + 5, 2 * CELL + 10), (2 * CELL + 27, 2 * CELL + 10), (2 * CELL + 22, 2 * CELL + 18), (2 * CELL + 20, 2 * CELL + 26), (2 * CELL + 11, 2 * CELL + 26), (2 * CELL + 9, 2 * CELL + 18)], fill=(70, 70, 75, 255), outline=ink)  # anvil
    r(3, 2, 1, 1, 2, 2, 29, 29, fill=(110, 80, 50, 255))  # crop
    for px in (8, 16, 24):
        for py in (8, 16, 24): e(3, 2, px - 3, py - 3, px + 3, py + 3, fill=(80, 160, 60, 255))
    e(4, 2, 1, 1, 30, 30, fill=(50, 120, 50, 255)); e(4, 2, 9, 9, 22, 22, fill=(70, 150, 60, 255)); e(4, 2, 13, 13, 18, 18, fill=(100, 70, 40, 255))  # tree
    e(5, 2, 4, 6, 27, 27, fill=(70, 140, 60, 255)); e(5, 2, 10, 10, 15, 15, fill=(170, 40, 60, 255)); e(5, 2, 17, 15, 22, 20, fill=(170, 40, 60, 255))  # bush
    e(6, 2, 4, 4, 27, 27, fill=(130, 130, 135, 255)); e(6, 2, 9, 9, 22, 22, fill=(50, 90, 150, 255))  # well
    r(7, 2, 1, 1, 3, 3, 28, 28, fill=(120, 110, 100, 255)); e(7, 2, 9, 9, 22, 22, fill=(220, 120, 40, 255)); e(7, 2, 13, 13, 18, 18, fill=(250, 210, 80, 255))  # hearth
    img.save(os.path.join(HERE, name))


def attachments_atlas(name):
    """16 px icons, one row: wall lamp, candle, plate, book, mug, banner."""
    S = 16
    img = Image.new("RGBA", (S * 6, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ink = (42, 32, 22, 255)
    d.rectangle([3, 9, 12, 13], fill=(90, 90, 90, 255), outline=ink); d.ellipse([4, 2, 11, 9], fill=(250, 220, 90, 255), outline=ink)  # wall lamp
    d.rectangle([S + 6, 5, S + 9, 13], fill=(235, 230, 210, 255), outline=ink); d.ellipse([S + 6, 1, S + 9, 5], fill=(250, 180, 60, 255))  # candle
    d.ellipse([2 * S + 2, 2, 2 * S + 13, 13], fill=(225, 225, 230, 255), outline=ink); d.ellipse([2 * S + 5, 5, 2 * S + 10, 10], outline=(170, 170, 180, 255))  # plate
    d.rectangle([3 * S + 3, 3, 3 * S + 12, 12], fill=(140, 40, 40, 255), outline=ink); d.line([3 * S + 5, 3, 3 * S + 5, 12], fill=(230, 210, 150, 255))  # book
    d.rectangle([4 * S + 4, 4, 4 * S + 10, 12], fill=(150, 110, 70, 255), outline=ink); d.rectangle([4 * S + 10, 6, 4 * S + 12, 10], outline=ink)  # mug
    d.polygon([(5 * S + 3, 1), (5 * S + 12, 1), (5 * S + 12, 14), (5 * S + 7, 11), (5 * S + 3, 14)], fill=(60, 80, 150, 255), outline=ink)  # banner
    img.save(os.path.join(HERE, name))


dual_sheet("terrain_grass.png", "grass", "#5E8A2E")
dual_sheet("terrain_dirt.png", "dirt", "#7A5A38")
dual_sheet("terrain_sand.png", "sand", "#D8C38A")
dual_sheet("terrain_water.png", "water", "#2F5E93")
dual_sheet("floor_wood.png", "planks", "#9A7650")
dual_sheet("floor_stone.png", "stone", "#8C8A84")
dual_sheet("floor_road.png", "road", "#6E665C")
dual_sheet("floor_rug.png", "rug", "#9E2B25")
dual_sheet("roof.png", "roof", "#8E4A36")
wall_sheet("wall_stone.png", beam=(140, 138, 132, 255), post=(110, 108, 104, 255), edge=(50, 48, 46, 255))
door_sheet("door_states.png")
objects_atlas("objects.png")
attachments_atlas("attachments.png")
print("done")
