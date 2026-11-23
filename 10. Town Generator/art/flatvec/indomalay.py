"""Module 10's Indo-Malay furniture, flat vector style (thick ink outline, flat lit shading, light from the top-left).
Writes ../placeholder/indomalay.png: a 32 px grid, 8x4, the layout in ../placeholder/README.md, and a review sheet.
usage: python indomalay.py        (needs Inkscape on PATH, Pillow)
Each piece is drawn top-down on 128 units a tile; a piece standing against a wall has its back at the top."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from flatvec import Svg, smooth_path, poly, oval, squircle, leaf, taper, radial_points, render_many, sheet  # noqa: E402
from PIL import Image  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build")
SHEET = os.path.join(HERE, "..", "placeholder", "indomalay.png")
TILE = 32           # game pixels a tile
DRAW = 128          # drawing units a tile
OUT = 5.0           # outline width: thick enough to read at 32 px
FINE = 2.4          # inner detail lines

WOOD, DARK_WOOD, CLAY, DARK_CLAY = (0.62, 0.42, 0.24), (0.42, 0.28, 0.17), (0.72, 0.40, 0.25), (0.48, 0.26, 0.17)
STRAW, RICE, STONE, BRASS = (0.84, 0.72, 0.45), (0.95, 0.93, 0.85), (0.58, 0.57, 0.54), (0.85, 0.66, 0.24)
IRON, CLOTH_RED, CLOTH_BLUE, LEAF = (0.45, 0.46, 0.50), (0.68, 0.22, 0.20), (0.24, 0.36, 0.58), (0.38, 0.62, 0.28)


def rect(x0, y0, x1, y1):
    return poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])


def shape(s, d, colour, lines=(), outline=OUT):
    return s.shape(d, colour, outline=outline, lines=lines, line_w=FINE)


def sleeping_mat(s):
    mat = squircle(64, 128, 50, 116, k=6)
    weave = [f"M16,{y} L112,{y}" for y in range(44, 240, 14)]
    shape(s, mat, STRAW, lines=weave)
    shape(s, squircle(64, 40, 38, 20, k=3), (0.93, 0.88, 0.76))                 # pillow at the back
    shape(s, squircle(64, 170, 46, 58, k=5), CLOTH_BLUE, lines=["M20,150 L108,150", "M20,190 L108,190"])  # cloth


def clay_stove(s):
    body = squircle(64, 64, 52, 48, k=5)
    s.shadow(body, offset=(6, 7))
    shape(s, body, CLAY)
    for x in (40, 88):
        shape(s, oval(x, 62, 18, 18), (0.20, 0.15, 0.12))
        shape(s, oval(x, 62, 10, 10), (0.95, 0.55, 0.20), outline=2)
    shape(s, rect(48, 92, 80, 116), (0.15, 0.11, 0.09))                         # fire mouth at the front


def storage_jar(s):
    s.shadow(oval(64, 66, 44, 44), offset=(6, 7))
    shape(s, oval(64, 66, 44, 44), CLAY)
    shape(s, oval(64, 62, 22, 22), DARK_CLAY)
    shape(s, oval(64, 62, 13, 13), (0.16, 0.12, 0.10), outline=2.5)


def low_table(s):
    top = squircle(128, 64, 116, 44, k=7)
    s.shadow(top, offset=(6, 7))
    shape(s, top, DARK_WOOD, lines=["M14,50 L242,50", "M14,78 L242,78"])
    shape(s, oval(96, 64, 18, 18), RICE)                                        # a bowl and a cup on it
    shape(s, oval(150, 62, 11, 11), CLAY)


def statue(s):
    base = squircle(64, 70, 50, 44, k=6)
    s.shadow(base, offset=(6, 7))
    shape(s, base, STONE, lines=["M18,96 L110,96"])
    shape(s, squircle(64, 66, 34, 22, k=3), (0.66, 0.65, 0.62))                 # seated body, shoulders
    shape(s, oval(64, 52, 16, 17), (0.70, 0.69, 0.66))                          # head
    shape(s, oval(64, 40, 7, 7), (0.70, 0.69, 0.66), outline=3)                 # top knot


def offering_table(s):
    top = squircle(128, 58, 118, 42, k=7)
    s.shadow(top, offset=(6, 7))
    shape(s, top, DARK_WOOD)
    for k, colour in enumerate([(0.95, 0.80, 0.25), (0.90, 0.35, 0.35), RICE, (0.95, 0.80, 0.25)]):
        x = 56 + k * 48
        shape(s, oval(x, 60, 21, 21), LEAF)                                     # banana-leaf tray
        shape(s, oval(x, 60, 11, 11), colour, outline=3)                        # flowers, rice


def pounding_trough(s):
    log = squircle(128, 70, 118, 36, k=4)
    s.shadow(log, offset=(6, 7))
    shape(s, log, WOOD, lines=["M20,58 L236,58", "M20,84 L236,84"])
    for x in (78, 178):
        shape(s, oval(x, 70, 26, 18), (0.30, 0.21, 0.14))
        shape(s, oval(x, 72, 16, 10), RICE, outline=2)
    s.shape(taper([(40, 22), (216, 30)], 7, 1.0), DARK_WOOD, outline=OUT)         # a pestle laid across


def rice_basket(s):
    s.shadow(oval(64, 66, 48, 48), offset=(6, 7))
    weave = [f"M{x},14 L{x},118" for x in range(26, 110, 12)]
    shape(s, oval(64, 66, 48, 48), STRAW, lines=weave)
    shape(s, oval(62, 62, 32, 30), RICE)


def potters_wheel(s):
    shape(s, oval(64, 64, 50, 50), DARK_WOOD, lines=["M14,64 L114,64", "M64,14 L64,114"])
    shape(s, oval(64, 64, 26, 26), CLAY)
    shape(s, oval(64, 64, 11, 11), DARK_CLAY, outline=3)


def loom(s):
    frame = rect(10, 12, 246, 110)
    s.shadow(frame, offset=(6, 7))
    shape(s, frame, WOOD)
    cloth = rect(34, 28, 222, 96)
    cid = shape(s, cloth, CLOTH_RED)
    for k, x in enumerate(range(40, 222, 16)):
        s.patch(rect(x, 28, x + 7, 96), [(0.92, 0.76, 0.30), CLOTH_BLUE][k % 2], cid)
    s.outline(cloth, OUT)
    shape(s, rect(10, 12, 246, 28), DARK_WOOD)                                  # beam at the back


def wine_jar(s):
    s.shadow(oval(64, 66, 40, 46), offset=(6, 7))
    shape(s, oval(64, 66, 40, 46), (0.40, 0.24, 0.16))
    shape(s, oval(64, 60, 18, 18), (0.30, 0.18, 0.12))
    shape(s, oval(64, 58, 11, 11), STRAW, outline=3)                            # stopper


def kiln(s):
    dome = oval(64, 64, 54, 52)
    s.shadow(dome, offset=(6, 7))
    bricks = [f"M10,{y} L118,{y}" for y in (40, 64, 88)]
    shape(s, dome, (0.66, 0.34, 0.24), lines=bricks)
    shape(s, squircle(64, 104, 26, 18, k=3), (0.15, 0.10, 0.08))
    shape(s, oval(64, 106, 12, 8), (0.98, 0.58, 0.18), outline=2)


def salt_boiler(s):
    for x in (34, 222, 128):                                                    # hearth stones under the pan
        shape(s, oval(x, 100, 18, 14), STONE)
    pan = squircle(128, 62, 112, 44, k=8)
    s.shadow(pan, offset=(6, 7))
    shape(s, pan, IRON)
    shape(s, squircle(128, 62, 96, 30, k=8), RICE, lines=["M48,56 L104,70", "M140,52 L204,66"])


def herb_jars(s):
    shelf = rect(8, 10, 120, 34)
    shape(s, shelf, DARK_WOOD)
    for k, colour in enumerate([LEAF, CLAY, (0.55, 0.65, 0.35), STRAW]):
        x = 22 + k * 28
        s.shadow(oval(x, 58, 13, 16), offset=(4, 5))
        shape(s, oval(x, 58, 13, 16), colour)
        shape(s, oval(x, 50, 7, 5), DARK_WOOD, outline=2.5)


def weapon_rack(s):
    shape(s, rect(8, 10, 120, 32), DARK_WOOD)
    for x, lean in ((36, -6), (64, 0), (92, 6)):
        s.shape(taper([(x, 30), (x + lean, 112)], 5, 0.35), (0.80, 0.80, 0.84), outline=OUT * 0.8)
        shape(s, oval(x, 30, 9, 9), BRASS, outline=3)


def strongbox(s):
    box = rect(18, 26, 110, 108)
    s.shadow(box, offset=(6, 7))
    shape(s, box, DARK_WOOD, lines=["M18,52 L110,52"])
    for x in (36, 92):
        shape(s, rect(x - 6, 26, x + 6, 108), BRASS, outline=3)
    shape(s, rect(56, 58, 72, 76), BRASS, outline=3)


def scales(s):
    s.shape(taper([(14, 60), (114, 60)], 5, 1.0), BRASS, outline=OUT * 0.8)
    s.shape(taper([(64, 60), (64, 112)], 5, 1.0), DARK_WOOD, outline=OUT * 0.8)
    for x in (22, 106):
        shape(s, oval(x, 76, 18, 18), BRASS)
    shape(s, oval(64, 112, 22, 10), DARK_WOOD)


def gong(s):
    s.shadow(oval(64, 64, 50, 50), offset=(6, 7))
    shape(s, oval(64, 64, 50, 50), BRASS, lines=[smooth_path(radial_points(64, 64, lambda a: 36, 24))])
    shape(s, oval(64, 64, 16, 16), (0.70, 0.52, 0.18))


def incense_burner(s):
    s.shadow(oval(64, 72, 34, 30), offset=(5, 6))
    shape(s, oval(64, 72, 34, 30), BRASS)
    shape(s, oval(64, 70, 18, 15), (0.30, 0.25, 0.20))
    s.shape(taper([(64, 66), (56, 40), (70, 24), (60, 8)], 5, 0.3), (0.88, 0.88, 0.90), outline=1.5)  # smoke


# name, atlas cell, size in tiles, drawing
PIECES = [
	("sleeping_mat", (0, 0), (1, 2), sleeping_mat), ("clay_stove", (1, 0), (1, 1), clay_stove),
	("storage_jar", (2, 0), (1, 1), storage_jar), ("low_table", (3, 0), (2, 1), low_table),
	("statue", (5, 0), (1, 1), statue), ("offering_table", (6, 0), (2, 1), offering_table),
	("pounding_trough", (1, 1), (2, 1), pounding_trough), ("rice_basket", (3, 1), (1, 1), rice_basket),
	("potters_wheel", (4, 1), (1, 1), potters_wheel), ("loom", (5, 1), (2, 1), loom),
	("wine_jar", (7, 1), (1, 1), wine_jar), ("kiln", (0, 2), (1, 1), kiln),
	("salt_boiler", (1, 2), (2, 1), salt_boiler), ("herb_jars", (3, 2), (1, 1), herb_jars),
	("weapon_rack", (4, 2), (1, 1), weapon_rack), ("strongbox", (5, 2), (1, 1), strongbox),
	("scales", (6, 2), (1, 1), scales), ("gong", (7, 2), (1, 1), gong), ("incense_burner", (0, 3), (1, 1), incense_burner),
]


def main():
	pairs = []
	for name, _, size, draw in PIECES:
		s = Svg(DRAW * max(size))
		draw(s)
		pairs.append((s.write(os.path.join(BUILD, f"{name}.svg")), os.path.join(BUILD, f"{name}.png")))
	# Render at 4x game size, then scale down: crisper than rendering at 32 px.
	big = []
	for (svg, png), (_, _, size, _) in zip(pairs, PIECES):
		big.append((svg, png, size))
	for side in (1, 2):
		group = [(svg, png) for svg, png, size in big if max(size) == side]
		if group:
			render_many(group, TILE * 4 * side)
	atlas = Image.new("RGBA", (TILE * 8, TILE * 4), (0, 0, 0, 0))
	for (name, cell, size, _), (_, png) in zip(PIECES, pairs):
		im = Image.open(png).convert("RGBA").crop((0, 0, TILE * 4 * size[0], TILE * 4 * size[1]))
		im = im.resize((TILE * size[0], TILE * size[1]), Image.LANCZOS)
		atlas.alpha_composite(im, (cell[0] * TILE, cell[1] * TILE))
	atlas.save(SHEET)
	print(sheet([(name, png, None, max(size)) for (name, _, size, _), (_, png) in zip(PIECES, pairs)],
		os.path.join(BUILD, "sheet.png"), cols=5, tile=48))


if __name__ == "__main__":
	main()
