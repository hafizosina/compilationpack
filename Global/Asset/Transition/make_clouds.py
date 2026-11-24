"""Module 13's level transition clouds: big flat-vector cloud masses, lit from the top-left, rimmed in a
blue-grey ink. usage: python make_clouds.py   (needs Inkscape on PATH)"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import flatvec  # noqa: E402
from flatvec import Svg, oval, render_many  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
flatvec.INK = '#5d6b82'
WHITE = (0.95, 0.96, 0.99)
COUNT = 4
PX = 1024


def cloud(seed):
    """One cloud: a broad flat base of lobes with taller puffs on top, read as one mass."""
    rng = random.Random(seed)
    s = Svg(128)
    lobes = []
    lobes.append(oval(64, 80, 54, 13))
    for k in range(5):
        x = 26 + k * 19 + rng.uniform(-3, 3)
        r = rng.uniform(10, 15) * (1.25 if k in (1, 2, 3) else 1.0)
        lobes.append(oval(x, 74 - r * 0.6 + rng.uniform(-2, 2), r, r * rng.uniform(0.85, 1.0)))
    s.shadow(oval(64, 84, 56, 14), offset=(4, 6), blur=3, opacity=0.18)
    s.cluster(lobes, WHITE, outline=1.6, inner=0, dark=0.86)
    return s


def main():
    pairs = []
    for k in range(COUNT):
        svg = os.path.join(HERE, f"cloud_{k}.svg")
        cloud(k + 11).write(svg)
        pairs.append((svg, os.path.join(HERE, f"cloud_{k}.png")))
    render_many(pairs, PX)
    for svg, _ in pairs:
        os.remove(svg)
    print("\n".join(p for _, p in pairs))


if __name__ == "__main__":
    main()
