"""Module 13's world map compass rose, flat vector in the map's ink, brass and parchment.
usage: python make_compass.py   (needs Inkscape on PATH)"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from flatvec import Svg, poly, oval, render  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
INK = (0.165, 0.125, 0.086)
BRASS = (0.725, 0.541, 0.196)
PAPER = (0.906, 0.839, 0.675)


def point(angle, length, width):
    """One arm of the rose split down its middle: the lit half and the shaded half."""
    a = math.radians(angle)
    tip = (64 + length * math.sin(a), 64 - length * math.cos(a))
    side = lambda s: (64 + width * math.sin(a + s * math.pi / 2), 64 - width * math.cos(a + s * math.pi / 2))
    return poly([(64, 64), side(-1), tip]), poly([(64, 64), tip, side(1)])


def rose():
    s = Svg(128)
    s.shape(oval(64, 64, 40, 40), PAPER, outline=1.6, dark=0.92)
    s.shape(oval(64, 64, 35, 35), PAPER, outline=0.9, dark=1.0)
    for k in range(8):
        a = k * 45 + 22.5
        left, right = point(a, 30, 3.5)
        s.shape(left, BRASS, outline=0.9, dark=1.0)
        s.shape(right, BRASS, outline=0.9, dark=0.75)
    for k in range(4):
        a = k * 90 + 45
        left, right = point(a, 36, 5.5)
        s.shape(left, PAPER, outline=1.1, dark=1.0)
        s.shape(right, INK, outline=1.1, dark=1.6)
    for k in range(4):
        a = k * 90
        left, right = point(a, 56 if k == 0 else 50, 7.5)
        s.shape(left, PAPER, outline=1.3, dark=1.0)
        s.shape(right, INK, outline=1.3, dark=1.6)
    s.shape(oval(64, 64, 5, 5), BRASS, outline=1.2)
    return s


if __name__ == "__main__":
    svg = os.path.join(HERE, "compass.svg")
    rose().write(svg)
    render(svg, os.path.join(HERE, "compass.png"), 512)
    os.remove(svg)
