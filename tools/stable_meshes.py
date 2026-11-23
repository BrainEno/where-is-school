"""Shaped meshes for the stable yard behind 01 (docs/EXAM_DREAM_ART.md, round 10).

Since round 18 the horses and hens are sculpted in `stable_animals.py` and the yard's
dressing is modelled in `stable_props.py`; this module keeps the dung, the heap, the
straw, the flies, the smell and the ink silhouette, and the kit those modules share.

Pure Python, no engine: `build_dream_annex.py` writes each mesh as its own text
ArrayMesh under `scenes/locations/corridor/stable_meshes/`, because the dream annex
scene is already most of the release's 1 MiB budget for one scene.

Every mesh carries RGBA8 vertex colour. RGB is the painted colour field (sRGB). Alpha
is a motion weight read by `stable_paint.gdshader` / `stable_coat.gdshader` /
`stench_flies.gdshader`, so a whole animal moves without a skeleton or a script:

* 0.5        still;
* 0.5 -> 1   how much of the graze turn about the neck pivot a vertex takes (neck, head,
             mane, ears);
* 0.5 -> 0   how much of the tail swish a vertex takes;
* < 0.1      a fly's wing (it flaps about the body's long axis).
"""
from __future__ import annotations

import math
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scenes/environment/props/playground_art/source"))

from site_mesh import (  # noqa: E402 - the kit lives beside the playground art
    IDENTITY, Mesh, _surface, add, cylinder, euler, fbm, mul, noise, rand, rock, smoothstep, sub, tube,
)

STILL = 0.5
WING = 0.0


def rgb(c, a=STILL):
    """sRGB bytes (or 0..1 floats) and a motion weight as one RGBA tuple."""
    if max(c) > 1.0:
        c = tuple(v / 255.0 for v in c)
    return (c[0], c[1], c[2], a)


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


class PaintMesh(Mesh):
    """`site_mesh.Mesh` whose colours keep their alpha (the motion weight)."""

    def surface(self) -> str:
        if len(self.points) > 65535:
            raise ValueError(f"mesh has {len(self.points)} vertices; split it")
        packed = []
        for c in self.colors:
            a = c[3] if len(c) > 3 else STILL
            packed.append(struct.pack("<4B", *(max(0, min(255, round(v * 255))) for v in (c[0], c[1], c[2], a))))
        return _surface(self.points, self.normals, self.indices, b"".join(packed))

    def paint(self, fn):
        """fn(point, normal) -> RGBA for every vertex added since `mark`."""
        start = getattr(self, "_mark", 0)
        for i in range(start, len(self.points)):
            self.colors[i] = fn(self.points[i], self.normals[i])
        return self

    def weight(self, fn):
        """Keep the painted colour, set the motion weight: fn(point) -> alpha."""
        start = getattr(self, "_mark", 0)
        for i in range(start, len(self.points)):
            c = self.colors[i]
            self.colors[i] = (c[0], c[1], c[2], fn(self.points[i]))
        return self

    def mark(self):
        self._mark = len(self.points)
        return self

    def add(self, other, fn=None, *, rotation=IDENTITY, offset=(0, 0, 0), scale=(1, 1, 1)):
        self.mark()
        self.merge(other, rotation, offset, scale)
        if fn is not None:
            self.paint(fn if callable(fn) else (lambda p, n, c=fn: c))
        return self


# --- curves and lofts ---------------------------------------------------------------------


def catmull(points, per=4):
    """A Catmull-Rom spline through `points` (tuples of any length), `per` steps a span."""
    out = []
    n = len(points)
    for i in range(n - 1):
        p0, p1, p2, p3 = points[max(i - 1, 0)], points[i], points[i + 1], points[min(i + 2, n - 1)]
        for s in range(per):
            t = s / per
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2
                                    + (-a + 3 * b - 3 * c + d) * t3) for a, b, c, d in zip(p0, p1, p2, p3)))
    out.append(tuple(points[-1]))
    return out


def superellipse(cx, cy, z, hw, hup, hdn, sides, power=2.4, bulge=None):
    ring = []
    for i in range(sides):
        a = math.tau * i / sides
        c, s = math.cos(a), math.sin(a)
        x = math.copysign(abs(c) ** (2 / power), c) * hw
        y = math.copysign(abs(s) ** (2 / power), s) * (hup if s > 0 else hdn)
        if bulge is not None:
            x *= 1 + bulge(a)
        ring.append((cx + x, cy + y, z))
    return ring


def loft_z(stations, sides=32, per=3, bulge=None, power=2.4):
    """A body lofted along +Z from (z, cy, half width, half height up, half height down)."""
    rows, centers = [], []
    for z, cy, hw, hup, hdn in catmull(stations, per):
        rows.append(superellipse(0.0, cy, z, max(hw, .004), max(hup, .004), max(hdn, .004), sides, power,
                                 None if bulge is None else (lambda a, z=z: bulge(a, z))))
        centers.append((0.0, cy, z))
    m = PaintMesh().grid(rows, wrap=True, centers=centers)
    m.polygon(rows[0], (0, 0, -1))
    m.polygon(rows[-1], (0, 0, 1))
    return m


def sweep(path, radii, sides=16, per=3, caps=True):
    """A smooth tube along a Catmull-Rom path; radii are numbers or (across, along-plane) pairs."""
    pts = catmull(path, per)
    rr = catmull([r if isinstance(r, tuple) else (r, r) for r in radii], per)
    t = tube(pts, [tuple(r) for r in rr], sides=sides, caps=caps)
    return PaintMesh().merge(t)


def ellipsoid(center, radii, rings=10, sides=18, wobble=0.0, seed=0):
    rows, centers = [], []
    cx, cy, cz = center
    rx, ry, rz = radii
    for r in range(1, rings):
        v = math.pi * r / rings
        y = -math.cos(v)
        k = math.sin(v)
        row = []
        for i in range(sides):
            a = math.tau * i / sides
            d = 1 + wobble * noise(a * 1.7 + seed, v * 2.3, seed)
            row.append((cx + rx * k * math.cos(a) * d, cy + ry * y * d, cz + rz * k * math.sin(a) * d))
        rows.append(row)
        centers.append((cx, cy + ry * y, cz))
    m = PaintMesh().grid(rows, wrap=True, centers=centers)
    # Poles as small fans.
    for row, pole, out in ((rows[0], (cx, cy - ry, cz), (0, -1, 0)), (rows[-1], (cx, cy + ry, cz), (0, 1, 0))):
        for i in range(sides):
            tri = [pole, row[i], row[(i + 1) % sides]]
            m.polygon(tri, add(mul(out, 1.0), sub(mul(add(add(tri[0], tri[1]), tri[2]), 1 / 3), center)))
    return m


def triangulate(poly):
    """Ear clipping for a simple 2-D polygon (any winding). Returns index triples."""
    pts = list(poly)
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
               for i in range(len(pts)))
    idx = list(range(len(pts)))
    if area < 0:
        idx.reverse()

    def inside(p, a, b, c):
        def s(p1, p2, p3):
            return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
        d1, d2, d3 = s(p, a, b), s(p, b, c), s(p, c, a)
        return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))

    out = []
    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = pts[i0], pts[i1], pts[i2]
            if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) <= 1e-12:
                continue
            if any(inside(pts[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            out.append((i0, i1, i2))
            idx.pop(k)
            break
        else:
            break
    if len(idx) == 3:
        out.append(tuple(idx))
    return out


def slab_polygon(outline, depth, face, edge, *, back=None):
    """A flat cut-out in the XY plane, `depth` thick around z = 0; any simple outline."""
    m = PaintMesh()
    h = depth / 2
    tris = triangulate(outline)
    for z, out, col in ((h, (0, 0, 1), face), (-h, (0, 0, -1), face if back is None else back)):
        for a, b, c in tris:
            m.mark()
            m.polygon([(*outline[a], z), (*outline[b], z), (*outline[c], z)], out)
            m.paint(lambda p, n, cc=col: cc)
    sign = 1 if sum(outline[i][0] * outline[(i + 1) % len(outline)][1] - outline[(i + 1) % len(outline)][0]
                    * outline[i][1] for i in range(len(outline))) > 0 else -1
    for i in range(len(outline)):
        a, b = outline[i], outline[(i + 1) % len(outline)]
        # Outward edge normal in 2-D (independent of the centroid for concave outlines).
        ex, ey = b[0] - a[0], b[1] - a[1]
        out = (ey * sign, -ex * sign, 0)
        if abs(ex) + abs(ey) < 1e-9:
            continue
        m.mark()
        m.polygon([(*a, h), (*b, h), (*b, -h), (*a, -h)], out)
        m.paint(lambda p, n, cc=edge: cc)
    return m


# --- dung ----------------------------------------------------------------------------


DUNG_FRESH = (76, 66, 34)
DUNG_WET = (52, 46, 26)
DUNG_OLD = (128, 108, 74)
DUNG_GREEN = (98, 104, 44)
STRAW = (214, 184, 102)
STRAW_PALE = (232, 214, 150)
STRAW_DARK = (164, 128, 66)


def apple(center, size, seed, age, detail=2):
    """One ball of horse dung: a squashed lumpy stone with fibre showing through."""
    seed = int(seed)
    r = rock(size, seed, squash=.78, detail=detail)
    fresh = mix(DUNG_FRESH, DUNG_OLD, age)

    def colour(p, n):
        f = fbm(p[0] * 60 + seed, p[2] * 60 + p[1] * 40, int(seed) + 9, 2)
        c = mix(fresh, DUNG_GREEN, max(0.0, f) * .9)
        if f < -.35:
            c = mix(c, STRAW_DARK, .6)  # undigested straw
        if n[1] < -.3:
            c = mix(c, DUNG_WET, .5)
        return rgb(c)

    m = PaintMesh()
    yaw = rand(int(seed * 7), 11) * 360
    m.add(r, colour, rotation=euler((rand(int(seed * 5), 3) * 30 - 15, yaw, 0)),
          offset=center)
    return m


def dung_pile(seed, scale=1.0, age=0.0):
    """A dropping of 6-14 balls heaped on each other, with a few crushed ones and straw."""
    m = PaintMesh()
    count = 6 + int(rand(seed, 1) * 9)
    placed = []
    for i in range(count):
        r = (.028 + .016 * rand(seed * 31 + i, 2)) * scale
        for attempt in range(12):
            a = rand(seed * 17 + i * 5 + attempt, 3) * math.tau
            d = (.02 + .09 * rand(seed * 13 + i + attempt, 4)) * scale
            x, z = math.cos(a) * d, math.sin(a) * d
            y = r * .72
            for (px, py, pz, pr) in placed:
                gap = math.hypot(x - px, z - pz)
                if gap < (r + pr) * .9:
                    y = max(y, py + math.sqrt(max(0.0, ((r + pr) * .9) ** 2 - gap * gap)) * .8)
            if y < .16 * scale:
                break
        placed.append((x, y, z, r))
        m.add(apple((x, y, z), r, seed * 100 + i, age))
    # Straw caught in it.
    for k in range(5):
        a = rand(seed * 41 + k, 5) * math.tau
        L = .07 + .06 * rand(seed + k, 6)
        cx, cz = math.cos(a) * .06 * scale, math.sin(a) * .06 * scale
        m.add(strand(L, .004), rgb(STRAW_DARK if k % 2 else STRAW),
              rotation=euler((rand(seed + k, 7) * 20, a * 57.3, 0)), offset=(cx, .012, cz))
    return m


def strand(length_, width):
    """One flattened straw along +Z: a creased ribbon, both faces drawn (12 vertices)."""
    h, w = length_ / 2, width / 2
    m = Mesh()
    for side, up in ((-1, 1), (1, 1)):
        ridge, edge = (0, w * .45, -h), (side * w, 0, -h)
        ridge2, edge2 = (0, w * .45, h), (side * w, 0, h)
        quad = [ridge, ridge2, edge2, edge] if side > 0 else [ridge, edge, edge2, ridge2]
        m.polygon(quad, (side * .4, up, 0))
        m.polygon(list(reversed(quad)), (-side * .4, -up, 0))
    return m


def heap(seed=5):
    """The muck heap: a lumpy mound of dung and soiled straw, bristling, with a fork in it."""
    m = PaintMesh()
    rows, centers = [], []
    sides, rings = 40, 14
    R, H = 1.05, .82
    for r in range(rings + 1):
        v = r / rings
        row = []
        for i in range(sides):
            a = math.tau * i / sides
            lump = fbm(math.cos(a) * 2.2 + v * 3, math.sin(a) * 2.2 + v * 2, seed, 4)
            rad = R * (1 - v ** 1.6) * (1 + .16 * lump) + .02
            h = H * (1 - (1 - v) ** 2.1) * (1 + .22 * fbm(a * 1.3, v * 4, seed + 4, 3))
            row.append((math.cos(a) * rad * (1.15 if math.cos(a) > 0 else 1), h, math.sin(a) * rad))
        rows.append(row)
        centers.append((0, max(0.0, H * (1 - (1 - v) ** 2.1) - .3), 0))
    mound = PaintMesh().grid(rows, wrap=True, centers=centers)

    def colour(p, n):
        f = fbm(p[0] * 9, p[2] * 9 + p[1] * 6, seed + 1, 3)
        top = smoothstep(.1, .7, p[1])
        c = mix(DUNG_WET, DUNG_FRESH, smoothstep(.0, .25, p[1]))
        c = mix(c, DUNG_OLD, top * .55)
        if f > .22:
            c = mix(c, STRAW_DARK, .75)
        elif f < -.3:
            c = mix(c, DUNG_GREEN, .6)
        return rgb(c)

    m.add(mound, colour)
    m.polygon(rows[-1], (0, 1, 0))
    # Balls on the surface, straw stuck in at all angles.
    k = 0
    for i in range(70):
        a = rand(i, 21) * math.tau
        v = rand(i, 22) * .85
        ring = rows[int(v * rings)]
        p = ring[int(a / math.tau * sides) % sides]
        if i < 34:
            m.add(apple(add(p, (0, .015, 0)), .03 + .015 * rand(i, 23), 500 + i, rand(i, 24) * .6, detail=1))
        else:
            L = .12 + .16 * rand(i, 25)
            m.add(strand(L, .006), rgb(mix(STRAW, STRAW_PALE, rand(i, 26))),
                  rotation=euler((-25 - 40 * rand(i, 27), a * 57.3 + 90, 0)), offset=add(p, (0, .02, 0)))
            k += 1
    # A pitchfork stuck in at an angle.
    fork = PaintMesh()
    fork.add(sweep(((0, 0, 0), (0, .7, 0), (0, 1.4, 0)), (.016, .016, .016), sides=8, per=1), rgb((150, 112, 70)))
    fork.add(cylinder(.024, .1, 10, center=(0, -.02, 0)), rgb((70, 70, 72)))
    for t in (-1.5, -.5, .5, 1.5):
        fork.add(sweep(((t * .028, -.02, 0), (t * .034, -.14, .01), (t * .036, -.3, .04)), (.006, .005, .002),
                       sides=6, per=2), rgb((86, 88, 92)))
    fork.add(sweep(((-.06, -.03, 0), (0, -.045, 0), (.06, -.03, 0)), (.01, .01, .01), sides=6, per=2),
             rgb((86, 88, 92)))
    m.add(fork, None, rotation=euler((24, 30, -14)), offset=(.38, .62, .12))
    return m


def bedding(area, count, seed, height=.02):
    """Loose straw: `count` strands over area ((x0, x1), (z0, z1)), some heaped, some soiled."""
    (x0, x1), (z0, z1) = area
    m = PaintMesh()
    for i in range(count):
        x = x0 + (x1 - x0) * rand(i, seed)
        z = z0 + (z1 - z0) * rand(i, seed + 1)
        lump = .5 + .5 * fbm(x * 2.5, z * 2.5, seed, 3)
        y = height * lump * 3 + .006 + .02 * rand(i, seed + 2) * lump
        L = .1 + .22 * rand(i, seed + 3)
        tone = rand(i, seed + 4)
        c = mix(STRAW, STRAW_PALE, tone) if tone > .3 else mix(STRAW, STRAW_DARK, .8)
        if fbm(x * 4 + 3, z * 4, seed + 7, 2) < -.38:
            c = mix(c, DUNG_FRESH, .55)  # trodden muck
        m.add(strand(L, .007 + .004 * rand(i, seed + 5)), rgb(c),
              rotation=euler((rand(i, seed + 6) * 24 - 12, rand(i, seed + 8) * 180, rand(i, seed + 9) * 30)),
              offset=(x, y, z))
    return m


# --- flies and their giant --------------------------------------------------------------


FLY_BODY = (26, 28, 24)
FLY_SHEEN = (54, 92, 60)
FLY_EYE = (150, 38, 30)
FLY_WING = (196, 206, 214)


def fly(scale=1.0):
    """A small fly: thorax, abdomen, red eyes and two wings marked for flapping."""
    m = PaintMesh()
    s = scale
    m.add(ellipsoid((0, 0, 0), (.0045 * s, .004 * s, .0055 * s), 5, 8), rgb(FLY_BODY))
    m.add(ellipsoid((0, -.0005 * s, -.0085 * s), (.004 * s, .0035 * s, .0065 * s), 5, 8), rgb(FLY_SHEEN))
    for sx in (-1, 1):
        m.add(ellipsoid((sx * .0026 * s, .0008 * s, .0062 * s), (.0024 * s, .0028 * s, .0022 * s), 4, 6),
              rgb(FLY_EYE))
        wing = [(sx * .002 * s, .0035 * s, .001 * s), (sx * .013 * s, .0045 * s, -.006 * s),
                (sx * .011 * s, .004 * s, -.013 * s), (sx * .003 * s, .0035 * s, -.005 * s)]
        m.mark()
        m.polygon(wing, (0, 1, 0))
        m.polygon(list(reversed(wing)), (0, -1, 0))
        m.paint(lambda p, n: rgb(FLY_WING, WING))
    return m


# --- smell, painted ----------------------------------------------------------------------


ACID = (190, 212, 58)
MUSTARD = (222, 186, 54)
BILE = (128, 150, 62)
PAPER_CORE = (240, 234, 196)
INK = (40, 38, 48)


def stink_cloud(seed, radius=.34, colour=ACID):
    """A soft, uneven three-dimensional wisp rather than a paper silhouette."""
    m = PaintMesh()
    muted = mix(colour, (175, 174, 143), .65)
    for i, (x, y, z, size) in enumerate(((0, 0, 0, 1), (-.48, -.06, .10, .65),
                                         (.42, .13, -.12, .72))):
        puff = ellipsoid((x * radius, y * radius, z * radius),
                         (radius * size, radius * .67 * size, radius * .64 * size),
                         rings=8, sides=12, wobble=.08, seed=seed + i)
        m.add(puff, rgb(muted))
    return m


def horse_silhouette():
    """Side profile of a horse in (z, y), for the ink shadow painted on the stall wall."""
    return [
        (-1.05, 0.55), (-1.0, 1.28), (-0.92, 1.52), (-0.6, 1.58), (-0.1, 1.55), (0.36, 1.62), (0.62, 1.86),
        (0.86, 2.05), (0.96, 2.18), (1.02, 2.06), (1.12, 1.92), (1.46, 1.62), (1.42, 1.52), (1.18, 1.66),
        (0.98, 1.78), (0.74, 1.4), (0.7, 1.08), (0.62, 0.9), (0.6, 0.02), (0.5, 0.02), (0.5, 0.86),
        (0.38, 0.84), (0.42, 0.02), (0.32, 0.02), (0.28, 0.84), (-0.4, 0.86), (-0.62, 0.84), (-0.66, 0.02),
        (-0.76, 0.02), (-0.76, 0.6), (-0.82, 0.02), (-0.92, 0.02), (-0.95, 0.84),
    ]
