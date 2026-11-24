"""flatvec - flat vector game-asset drawing: Python builds SVG, Inkscape renders PNG.

Style (RimWorld-like): flat fills, one even dark ink outline, flat shading done as a lighter copy of the shape shifted
toward the light and clipped to the shape (leaves a darker crescent on the far side), optional thin ink detail lines
clipped inside. No gradients, no texture noise.

Use as a library (copy next to your script or add this folder to sys.path):

    from flatvec import Svg, smooth_path, poly, star, oval, squircle, leaf, taper, radial_points, width_profile, render, sheet
    svg = Svg(size=128)                                   # drawing units: 0..128 square canvas
    body = smooth_path(radial_points(64, 64, lambda a: 30 + 4 * math.cos(2 * a)))
    svg.shape(body, (0.62, 0.72, 0.86))                   # base colour as 0..1 rgb
    svg.write('out/body.svg'); render('out/body.svg', 'out/body.png', 256)

Requirements: Inkscape 1.x on PATH (CLI), Pillow (only for sheet()).
"""
import math
import os
import subprocess

INK = '#1e1a18'
LIGHT = (-1.0, -1.0)            # light from the top-left: the lit copy shifts up-left


# ------------------------------------------------------------------ colour

def hexc(c, k=1.0):
    """0..1 rgb (or '#rrggbb') scaled by k -> '#rrggbb'."""
    if isinstance(c, str):
        c = tuple(int(c[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return '#' + ''.join(f'{max(0, min(255, int(round(255 * v * k)))):02x}' for v in c)


# ------------------------------------------------------------------ geometry -> SVG path data

def smooth_path(pts, closed=True):
    """Catmull-Rom curve through the points, written exactly as cubic Beziers. The main way to draw organic shapes:
    place a handful of points, get a smooth outline."""
    n = len(pts)
    P = (lambda i: pts[i % n]) if closed else (lambda i: pts[max(0, min(n - 1, i))])
    d = [f'M{pts[0][0]:.2f},{pts[0][1]:.2f}']
    for i in range(n if closed else n - 1):
        p0, p1, p2, p3 = P(i - 1), P(i), P(i + 1), P(i + 2)
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d.append(f'C{c1[0]:.2f},{c1[1]:.2f} {c2[0]:.2f},{c2[1]:.2f} {p2[0]:.2f},{p2[1]:.2f}')
    return ' '.join(d) + (' Z' if closed else '')


def poly(pts, closed=True):
    """Straight-edged path (crates, planks, crystals, roofs, star tips). smooth_path rounds every corner; use this
    when corners must stay sharp."""
    d = 'M' + ' L'.join(f'{x:.2f},{y:.2f}' for x, y in pts)
    return d + (' Z' if closed else '')


def star(cx, cy, r_out, r_in, n, rot=0.0, sharp=True):
    """Star / spiky ring (pine tier, fire burst, spark, thistle). sharp=False gives a soft, wavy flower edge instead
    (smooth_path through alternating radii never makes points)."""
    pts = []
    for i in range(2 * n):
        a = math.radians(rot) + math.pi * i / n
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.sin(a), cy - r * math.cos(a)))
    return poly(pts) if sharp else smooth_path(pts)


def radial_points(cx, cy, radius_fn, n=36, start=0.0):
    """Points round (cx, cy); radius_fn(angle) gives the radius (angle 0 = up, clockwise, radians).
    Great for blobs, squircles, lobed crowns: radius_fn = lambda a: r * (1 + 0.15 * cos(5 * a))."""
    out = []
    for i in range(n):
        a = start + 2 * math.pi * i / n
        r = radius_fn(a)
        out.append((cx + r * math.sin(a), cy - r * math.cos(a)))
    return out


def squircle(x, y, w, h, k=4.0, angle=0.0, n=40):
    """Rounded rectangle-ish blob (superellipse): k=2 is an ellipse, 4 a soft box, 8+ nearly square. Good for torsos,
    heads, cushions, crates with soft corners."""
    a = math.radians(angle)
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s_ = math.cos(t), math.sin(t)
        px = w * math.copysign(abs(c) ** (2 / k), c)
        py = h * math.copysign(abs(s_) ** (2 / k), s_)
        pts.append((x + px * math.cos(a) - py * math.sin(a), y + px * math.sin(a) + py * math.cos(a)))
    return smooth_path(pts)


def oval(x, y, w, h, angle=0.0, n=24):
    """Ellipse (half-sizes w, h) turned `angle` degrees, as a smooth path."""
    a = math.radians(angle)
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        px, py = w * math.cos(t), h * math.sin(t)
        pts.append((x + px * math.cos(a) - py * math.sin(a), y + px * math.sin(a) + py * math.cos(a)))
    return smooth_path(pts)


def leaf(x, y, length, width, angle):
    """Leaf / ear / petal / blade from (x, y) pointing at `angle` degrees: 0 = up (toward the top of the canvas),
    90 = right, 180 = down, -90 = left. Mirrored pairs: use side * a for parts pointing up-and-out and
    180 - side * a for parts pointing down-and-out (side = -1 left, +1 right); e.g. ears laid back over the shoulders
    of an animal facing up are leaf(x + side*dx, y, L, w, 180 - side*20)."""
    a = math.radians(angle)
    ux, uy = math.sin(a), -math.cos(a)
    nx, ny = -uy, ux
    return smooth_path([(x - nx * width, y - ny * width),
                        (x + ux * length * 0.55 - nx * width * 0.9, y + uy * length * 0.55 - ny * width * 0.9),
                        (x + ux * length, y + uy * length),
                        (x + ux * length * 0.55 + nx * width * 0.9, y + uy * length * 0.55 + ny * width * 0.9),
                        (x + nx * width, y + ny * width)])


def _catmull(pts, per=8):
    out = []
    n = len(pts)
    for i in range(n - 1):
        p0, p1, p2, p3 = pts[max(0, i - 1)], pts[i], pts[i + 1], pts[min(n - 1, i + 2)]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in (0, 1)))
    out.append(tuple(pts[-1]))
    return out


def taper(pts, w0, w1=0.15):
    """Closed outline of a stroke through pts (tail, trunk, branch, vine, tentacle): half-width w0 at the start
    tapering to w0 * w1 at the end. Draw it with Svg.shape so it gets outline and shading."""
    dense = _catmull([tuple(p) for p in pts])
    n = len(dense)
    right, left = [], []
    for i, p in enumerate(dense):
        q = (dense[min(n - 1, i + 1)][0] - dense[max(0, i - 1)][0], dense[min(n - 1, i + 1)][1] - dense[max(0, i - 1)][1])
        L = math.hypot(*q) or 1
        nrm = (q[1] / L, -q[0] / L)
        w = w0 * (1 - (1 - w1) * i / max(1, n - 1))
        right.append((p[0] + nrm[0] * w, p[1] + nrm[1] * w))
        left.append((p[0] - nrm[0] * w, p[1] - nrm[1] * w))
    out = right + list(reversed(left))
    return smooth_path(out[::2] if len(out) > 40 else out)


def width_profile(x0, y0, length, profile, bend=0.0, n=60):
    """A body seen from above along a spine (animal, fish, vehicle, boat): profile = [(t, half-width as a fraction of
    length)], t = 0 front .. 1 back, spine from (x0, y0) going down the canvas; bend curves it sideways.
    Returns outline points (feed to smooth_path). Wide-narrow-wide profiles give shoulders / waist / hips."""
    ts, ws = zip(*profile)

    def hw(t):
        for i in range(len(ts) - 1):
            if ts[i] <= t <= ts[i + 1]:
                f = (t - ts[i]) / ((ts[i + 1] - ts[i]) or 1)
                return (ws[i] + (ws[i + 1] - ws[i]) * f) * length
        return ws[-1] * length

    def centre(t):
        return x0 + bend * length * math.sin(math.pi * t), y0 + t * length
    right, left = [], []
    for i in range(n):
        t = i / (n - 1)
        x, y = centre(t)
        (xa, ya), (xb, yb) = centre(max(0, t - 0.01)), centre(min(1, t + 0.01))
        L = math.hypot(xb - xa, yb - ya) or 1
        nx, ny = (yb - ya) / L, -(xb - xa) / L
        w = hw(t)
        right.append((x - nx * w, y - ny * w))
        left.append((x + nx * w, y + ny * w))
    pts = right + list(reversed(left))
    return [pts[0]] + [p for i, p in enumerate(pts[1:], 1) if math.dist(p, pts[i - 1]) > 0.6]


# ------------------------------------------------------------------ the drawing

class Svg:
    """One asset. Drawing units are a size x size square (default 128); y grows downward.
    Shapes stack in call order: draw back to front."""

    def __init__(self, size=128):
        self.size = size
        self.defs, self.body, self.n = [], [], 0

    def uid(self, p='c'):
        self.n += 1
        return f'{p}{self.n}'

    def clip(self, d):
        """Register a clip path from path data; returns its id (for clip= on shape/patch/lines)."""
        cid = self.uid('k')
        self.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
        return cid

    def shape(self, d, colour, outline=2.4, light=None, dark=0.80, lines=(), line_w=1.0, line_opacity=0.85, clip=None):
        """The core primitive. A flat shape: base colour at `dark` brightness, a full-brightness copy shifted toward
        the light and clipped to the shape (the far side keeps a darker crescent), detail lines clipped inside,
        then the ink outline. light = shift in drawing units (default ~2% of the canvas, up-left)."""
        light = light or (LIGHT[0] * self.size * 0.02, LIGHT[1] * self.size * 0.02)
        cid = self.clip(d)
        g = f' clip-path="url(#{clip})"' if clip else ''
        self.body.append(f'<g{g}>')
        self.body.append(f'<path d="{d}" fill="{hexc(colour, dark)}"/>')
        self.body.append(f'<g clip-path="url(#{cid})"><path d="{d}" transform="translate({light[0]:.2f},{light[1]:.2f})" '
                         f'fill="{hexc(colour)}"/></g>')
        for ld in lines:
            self.body.append(f'<path d="{ld}" fill="none" stroke="{INK}" stroke-width="{line_w}" stroke-linecap="round" '
                             f'stroke-linejoin="round" clip-path="url(#{cid})" opacity="{line_opacity}"/>')
        if outline:
            self.body.append(f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="{outline}" stroke-linejoin="round"/>')
        self.body.append('</g>')
        return cid

    def patch(self, d, colour, clip, opacity=1.0):
        """A flat colour patch (spots, saddle, stripe, mask, belly) clipped inside an earlier shape (its clip id).
        Redraw the owner's outline afterwards with outline() so the patch never covers the ink."""
        self.body.append(f'<path d="{d}" fill="{hexc(colour)}" opacity="{opacity}" clip-path="url(#{clip})"/>')

    def lines(self, ds, clip=None, width=0.9, opacity=0.75, colour=INK):
        """Thin open strokes (fur ticks, folds, seams, veins, planks); clipped inside a shape when clip is given."""
        c = f' clip-path="url(#{clip})"' if clip else ''
        for d in ds:
            self.body.append(f'<path d="{d}" fill="none" stroke="{colour}" stroke-width="{width}" stroke-linecap="round" '
                             f'stroke-linejoin="round" opacity="{opacity}"{c}/>')

    def outline(self, d, width=2.4):
        self.body.append(f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="{width}" stroke-linejoin="round"/>')

    def cluster(self, ds, colour, outline=2.4, inner=0.9, light=None, dark=0.80):
        """Several overlapping blobs read as ONE mass (tree crown, bush, cloud, rock pile, smoke): all outlines first,
        then all fills, so ink only runs round the outside; each blob then gets its own lit copy and a thin inner line,
        giving clumps inside one silhouette."""
        light = light or (LIGHT[0] * self.size * 0.02, LIGHT[1] * self.size * 0.02)
        for d in ds:
            self.body.append(f'<path d="{d}" fill="{INK}" stroke="{INK}" stroke-width="{outline * 2}" stroke-linejoin="round"/>')
        for d in ds:
            self.body.append(f'<path d="{d}" fill="{hexc(colour, dark)}"/>')
        for d in ds:
            cid = self.clip(d)
            self.body.append(f'<g clip-path="url(#{cid})"><path d="{d}" transform="translate({light[0]:.2f},{light[1]:.2f})" '
                             f'fill="{hexc(colour)}"/></g>')
            if inner:
                self.body.append(f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="{inner}" opacity="0.55"/>')

    def shadow(self, d, offset=(3, 4), blur=2.5, opacity=0.35):
        """Soft ground shadow (draw it first). Only for things that stand up (trees, buildings); not for flat parts."""
        fid = self.uid('f')
        self.defs.append(f'<filter id="{fid}" x="-30%" y="-30%" width="160%" height="160%">'
                         f'<feGaussianBlur stdDeviation="{blur}"/></filter>')
        self.body.append(f'<path d="{d}" fill="#000" opacity="{opacity}" transform="translate({offset[0]},{offset[1]})" '
                         f'filter="url(#{fid})"/>')

    def raw(self, svg_fragment):
        self.body.append(svg_fragment)

    def write(self, file):
        os.makedirs(os.path.dirname(os.path.abspath(file)), exist_ok=True)
        s = self.size
        with open(file, 'w') as f:
            f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{s}" height="{s}" viewBox="0 0 {s} {s}">'
                    f'<defs>{"".join(self.defs)}</defs>{"".join(self.body)}</svg>')
        return file


# ------------------------------------------------------------------ output

def render(svg_file, png_file, px, background=None):
    """Inkscape CLI: SVG -> PNG at px x px (transparent unless background '#rrggbb')."""
    os.makedirs(os.path.dirname(os.path.abspath(png_file)), exist_ok=True)
    cmd = ['inkscape', svg_file, '--export-type=png', f'--export-filename={png_file}', f'--export-width={px}', f'--export-height={px}']
    cmd += [f'--export-background={background}', '--export-background-opacity=1'] if background else ['--export-background-opacity=0']
    subprocess.run(cmd, check=True, capture_output=True)
    return png_file


def render_many(pairs, px, background=None):
    """Render [(svg, png), ...] in ONE Inkscape process (much faster than calling render() in a loop)."""
    bg = f'export-background:{background};export-background-opacity:1;' if background else 'export-background-opacity:0;'
    script = ';'.join(f'file-open:{s};export-filename:{p};export-width:{px};export-height:{px};{bg}'
                      f'export-do;file-close' for s, p in pairs)
    for _, p in pairs:
        os.makedirs(os.path.dirname(os.path.abspath(p)), exist_ok=True)
    subprocess.run(['inkscape', '--shell'], input=script.replace(';', '\n') + '\nquit\n', text=True, check=True,
                   capture_output=True)


def _font(size):
    from PIL import ImageFont
    for name in ('DejaVuSans-Bold.ttf', 'Arial Bold.ttf', 'arialbd.ttf', 'LiberationSans-Bold.ttf'):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def sheet(items, out, cell=192, cols=6, bg=(70, 62, 52), small=(64, 32), tile=None):
    """Contact sheet for review: each item = (label, png path[, reference image path[, footprint]]).
    Each cell shows the asset big, the reference beside it if given, and downscaled copies at the `small` sizes
    (judge readability at real game size). The background should resemble where the asset sits in the game.
    tile (px): also add a line-up row with every asset at its REAL relative size, footprint = how many game tiles
    across the canvas covers (e.g. a rabbit 1, a pine 3), drawn on a tile grid; use it whenever sizes differ."""
    from PIL import Image, ImageDraw
    font = _font(14)
    extra = sum(small) + 8 * len(small)
    has_ref = any(len(i) > 2 and i[2] for i in items)
    w = cell + extra + (cell if has_ref else 0)
    rows = (len(items) + cols - 1) // cols
    line_h = 0
    if tile:
        feet = [(it[3] if len(it) > 3 else 1) for it in items]
        line_h = int(max(feet) * tile) + 40
    img = Image.new('RGB', (max(cols * (w + 8), int(sum((it[3] if len(it) > 3 else 1) for it in items) * tile + 16 * len(items)) if tile else 0),
                            rows * (cell + 26) + line_h), bg)
    d = ImageDraw.Draw(img)
    for i, it in enumerate(items):
        label, path = it[0], it[1]
        x, y = (i % cols) * (w + 8), (i // cols) * (cell + 26)
        d.text((x + 4, y + 2), label, fill=(255, 235, 160), font=font)
        xx = x
        if len(it) > 2 and it[2]:
            r = Image.open(it[2]).convert('RGBA')
            r.thumbnail((cell, cell))
            img.paste(r, (xx, y + 24), r)
            xx += cell
        a = Image.open(path).convert('RGBA')
        big = a.resize((cell, cell), Image.LANCZOS)
        img.paste(big, (xx, y + 24), big)
        xx += cell + 4
        for s in small:
            t = a.resize((s, s), Image.LANCZOS)
            img.paste(t, (xx, y + 24 + cell - s), t)
            xx += s + 8
    if tile:                                             # line-up at real relative size on a tile grid
        y0 = rows * (cell + 26) + 24
        d.text((4, y0 - 20), f'real relative size (1 tile = {tile}px)', fill=(255, 235, 160), font=font)
        for gx in range(0, img.width, tile):
            d.line([(gx, y0), (gx, img.height)], fill=tuple(int(c * 0.85) for c in bg))
        for gy in range(y0, img.height, tile):
            d.line([(0, gy), (img.width, gy)], fill=tuple(int(c * 0.85) for c in bg))
        xx = 8
        for it in items:
            f = it[3] if len(it) > 3 else 1
            px = max(4, int(f * tile))
            t = Image.open(it[1]).convert('RGBA').resize((px, px), Image.LANCZOS)
            img.paste(t, (xx, y0 + line_h - 40 - px + 8), t)
            xx += px + 16
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    img.save(out)
    return out
