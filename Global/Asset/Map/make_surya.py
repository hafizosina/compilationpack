"""Module 13's map weight: a brass Surya Majapahit sun, eight long rays between eight short, rings at its
middle, flat vector. usage: python make_surya.py   (needs Inkscape on PATH)"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from flatvec import Svg, poly, oval, render  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
BRASS = (0.78, 0.60, 0.24)
DARK = (0.55, 0.40, 0.14)


def ray(angle, inner, outer, width):
    """A ray as a kite: from the ring out to a point, split into a lit and a shaded half."""
    a = math.radians(angle)
    at = lambda r, s: (64 + r * math.sin(a + s), 64 - r * math.cos(a + s))
    half = math.atan2(width, inner)
    base, tip = at(inner, 0), at(outer, 0)
    return poly([base, at(inner + 4, -half), tip]), poly([base, tip, at(inner + 4, half)])


def surya():
    s = Svg(128)
    s.shadow(oval(64, 64, 52, 52), offset=(3, 4), blur=2.5, opacity=0.35)
    for k in range(16):
        long = k % 2 == 0
        lit, shade = ray(k * 22.5, 26, 58 if long else 44, 7 if long else 5)
        s.shape(lit, BRASS, outline=1.2, dark=1.0)
        s.shape(shade, BRASS, outline=1.2, dark=0.72)
    s.shape(oval(64, 64, 28, 28), BRASS, outline=1.6)
    s.shape(oval(64, 64, 21, 21), DARK, outline=1.2, dark=1.0)
    for k in range(8):
        a = math.radians(k * 45)
        s.shape(oval(64 + 15 * math.sin(a), 64 - 15 * math.cos(a), 3.2, 3.2), BRASS, outline=0.9)
    s.shape(oval(64, 64, 9, 9), BRASS, outline=1.2)
    return s


if __name__ == "__main__":
    svg = os.path.join(HERE, "surya.svg")
    surya().write(svg)
    render(svg, os.path.join(HERE, "surya.png"), 512)
    os.remove(svg)
