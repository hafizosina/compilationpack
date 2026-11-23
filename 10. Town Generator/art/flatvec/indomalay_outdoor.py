"""Module 10's Indo-Malay outdoor pieces, flat vector style (as indomalay.py). Writes
../placeholder/indomalay_outdoor.png: a 32 px grid, 8x3, the layout in ../placeholder/README.md.
usage: python indomalay_outdoor.py      (needs Inkscape on PATH, Pillow)"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from flatvec import Svg, poly, oval, squircle, leaf, taper, radial_points, smooth_path, render_many, sheet  # noqa: E402
from indomalay import shape, rect, OUT, WOOD, DARK_WOOD, STONE, BRASS, LEAF, STRAW, CLAY, TILE, DRAW  # noqa: E402
from PIL import Image  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build")
SHEET = os.path.join(HERE, "..", "placeholder", "indomalay_outdoor.png")
SOIL = (0.45, 0.32, 0.20)


def bench(s):
    seat = squircle(128, 64, 110, 22, k=8)
    s.shadow(seat, offset=(6, 7))
    shape(s, seat, WOOD, lines=["M20,64 L236,64"])


def lamp_post(s):
    s.shadow(oval(64, 64, 26, 26), offset=(8, 10))
    shape(s, oval(64, 64, 26, 26), DARK_WOOD)
    shape(s, oval(64, 64, 15, 15), BRASS)
    shape(s, oval(64, 64, 7, 7), (1.0, 0.82, 0.35), outline=2.5)


def garden_bed(s):
    bed = squircle(128, 64, 116, 50, k=8)
    shape(s, bed, SOIL, lines=["M16,48 L240,48", "M16,80 L240,80"])
    for k in range(6):
        x = 36 + k * 37
        for y in (40, 88):
            for a in (-40, 40, 180):
                s.shape(leaf(x, y, 16, 6, a), LEAF, outline=2.5)


def chicken_coop(s):
    roof = poly([(14, 22), (114, 22), (114, 106), (14, 106)])
    s.shadow(roof, offset=(6, 7))
    shape(s, roof, STRAW, lines=[f"M14,{y} L114,{y}" for y in (40, 58, 76, 94)] + ["M64,22 L64,106"])
    shape(s, squircle(96, 112, 16, 12, k=3), (0.96, 0.94, 0.90))          # a hen in front
    shape(s, oval(104, 108, 4, 4), (0.86, 0.25, 0.20), outline=1.5)


def pyre(s):
    base = squircle(128, 128, 110, 110, k=9)
    shape(s, base, STONE, lines=["M18,128 L238,128", "M128,18 L128,238"])
    for k in range(5):                                                     # stacked logs
        y = 72 + k * 26
        s.shape(taper([(48, y), (208, y)], 10, 1.0), WOOD, outline=OUT)
    shape(s, oval(128, 128, 30, 26), (0.95, 0.88, 0.75))                  # shroud on top


def banana_tree(s):
    s.shadow(oval(64, 64, 52, 52), offset=(8, 10))
    for a in range(0, 360, 51):
        s.shape(leaf(64, 64, 58, 16, a), (0.42, 0.66, 0.28), outline=3.5,
                lines=[])
    shape(s, oval(64, 64, 10, 10), (0.36, 0.48, 0.22))


PIECES = [
	("bench", (0, 0), (2, 1), bench), ("lamp_post", (2, 0), (1, 1), lamp_post),
	("garden_bed", (3, 0), (2, 1), garden_bed), ("chicken_coop", (5, 0), (1, 1), chicken_coop),
	("banana_tree", (6, 0), (1, 1), banana_tree), ("pyre", (0, 1), (2, 2), pyre),
]


def main():
	pairs = []
	for name, _, size, draw in PIECES:
		s = Svg(DRAW * max(size))
		draw(s)
		pairs.append((s.write(os.path.join(BUILD, f"{name}.svg")), os.path.join(BUILD, f"{name}.png")))
	for side in (1, 2):
		group = [pair for pair, (_, _, size, _) in zip(pairs, PIECES) if max(size) == side]
		if group:
			render_many(group, TILE * 4 * side)
	atlas = Image.new("RGBA", (TILE * 8, TILE * 3), (0, 0, 0, 0))
	for (name, cell, size, _), (_, png) in zip(PIECES, pairs):
		im = Image.open(png).convert("RGBA").crop((0, 0, TILE * 4 * size[0], TILE * 4 * size[1]))
		atlas.alpha_composite(im.resize((TILE * size[0], TILE * size[1]), Image.LANCZOS), (cell[0] * TILE, cell[1] * TILE))
	atlas.save(SHEET)
	print(sheet([(name, png, None, max(size)) for (name, _, size, _), (_, png) in zip(PIECES, pairs)],
		os.path.join(BUILD, "sheet_outdoor.png"), cols=6, tile=48))


if __name__ == "__main__":
	main()
