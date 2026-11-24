"""Module 13's level transition clouds: big flat-vector cloud masses, lit from the top-left, rimmed in a
blue-grey ink. usage: python make_clouds.py   (needs Inkscape on PATH)"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import flatvec  # noqa: E402
from flatvec import Svg, oval, render_many, smooth_path  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
flatvec.INK = '#5d6b82'
WHITE = (0.95, 0.96, 0.99)
COUNT = 6
PX = 512


def cloud(seed):
    """One cloud: overlapping puffs on a flat base read as one mass, each puff's shaded crescent showing it,
    small bumps along the top edge, and a shaded belly."""
    rng = random.Random(seed)
    s = Svg(128)
    lobes = [oval(64, 80, 48, 12)]
    puffs = []
    count = rng.choice((4, 5))
    for k in range(count):
        x = 30 + k * (68 / (count - 1)) + rng.uniform(-2, 2)
        r = rng.uniform(12, 15) * (1.3 if 0 < k < count - 1 else 1.0)
        y = 76 - r * 0.7 + rng.uniform(-2, 2)
        lobes.append(oval(x, y, r, r * 0.92))
        puffs.append((x, y, r))
    for x, y, r in puffs:
        for a in rng.sample((-60, -30, 0, 30, 60), 2):
            t = math.radians(a - 90)
            lobes.append(oval(x + r * 0.86 * math.cos(t), y + r * 0.86 * math.sin(t), r * 0.32, r * 0.3))
    s.shadow(oval(64, 84, 50, 12), offset=(3, 5), blur=2.5, opacity=0.16)
    s.cluster(lobes, WHITE, outline=1.4, inner=0, dark=0.8, light=(-2.2, -2.2))
    belly = smooth_path([(20, 84), (42, 88), (64, 89), (86, 88), (108, 84), (100, 91), (64, 93), (28, 91)])
    s.shape(belly, (0.82, 0.86, 0.93), outline=0)
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
