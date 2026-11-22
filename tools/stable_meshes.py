"""Shaped meshes for the stink stable behind 01 (docs/EXAM_DREAM_ART.md, round 10).

Pure Python, no engine: `build_dream_annex.py` writes each mesh as its own text
ArrayMesh under `scenes/locations/corridor/stable_meshes/`, because the dream annex
scene is already most of the release's 1 MiB budget for one scene.

Every mesh carries RGBA8 vertex colour. RGB is the painted colour field (sRGB). Alpha
is a motion weight read by `stable_paint.gdshader` / `stable_ink.gdshader` /
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
    IDENTITY, Mesh, _surface, add, apply, cross, cylinder, dot, euler, fbm, lerp, mul, noise, norm, rand,
    rock, smoothstep, sub, tube,
)

STILL = 0.5
WING = 0.0
# The horse frame: +Z forward, +Y up, origin on the ground between the hooves.
NECK_PIVOT = (0.0, 1.30, 0.50)
TAIL_PIVOT = (0.0, 1.36, -0.93)


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


def cut_strip(base, tips, thickness, face, edge):
    """Cut paper: quads from a base polyline out to a jagged tip polyline, with thickness.

    `base` and `tips` are the same length. The two faces get `face`, the cut edge `edge`.
    """
    m = PaintMesh()
    n = len(base)
    # Offset direction: the normal of the strip's own plane (from its first quad).
    plane = norm(cross(sub(base[min(1, n - 1)], base[0]), sub(tips[0], base[0])))
    h = mul(plane, thickness / 2)
    front_b = [add(p, h) for p in base]
    front_t = [add(p, h) for p in tips]
    back_b = [sub(p, h) for p in base]
    back_t = [sub(p, h) for p in tips]
    for i in range(n - 1):
        for quad_pts, out, col in (
            ((front_b[i], front_b[i + 1], front_t[i + 1], front_t[i]), plane, face),
            ((back_b[i], back_b[i + 1], back_t[i + 1], back_t[i]), mul(plane, -1), face),
        ):
            m.mark()
            m.polygon([quad_pts[0], quad_pts[1], quad_pts[2]], out)
            m.polygon([quad_pts[0], quad_pts[2], quad_pts[3]], out)
            m.paint(lambda p, nn, c=col: c)
    # The cut edge all round the tips, and the two ends.
    ring = [*zip(front_t, back_t)]
    for i in range(n - 1):
        (a, b), (c, d) = ring[i], ring[i + 1]
        mid = mul(add(add(a, b), add(c, d)), .25)
        inner = mul(add(base[i], base[i + 1]), .5)
        m.mark()
        m.polygon([a, c, d, b], sub(mid, inner))
        m.paint(lambda p, nn, col=edge: col)
    for i, j in ((0, 1), (n - 1, n - 2)):
        out = sub(base[i], base[j])
        m.mark()
        m.polygon([front_b[i], front_t[i], back_t[i], back_b[i]], out)
        m.paint(lambda p, nn, col=edge: col)
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


# --- the horses -----------------------------------------------------------------------


BAY = {"coat": (128, 74, 44), "shade": (98, 54, 34), "points": (34, 28, 26), "mane": (30, 25, 24),
       "mane_edge": (226, 214, 176), "blaze": (236, 228, 212), "hoof": (54, 46, 40), "muzzle": (70, 46, 36)}
GREY = {"coat": (178, 174, 166), "shade": (128, 126, 122), "points": (92, 88, 86), "mane": (232, 228, 214),
        "mane_edge": (60, 58, 66), "blaze": (206, 204, 198), "hoof": (66, 62, 60), "muzzle": (96, 90, 88)}
EYE = (16, 13, 12)
NOSTRIL = (36, 26, 24)
EAR_IN = (58, 40, 34)

BODY = (
    (-0.99, 1.31, 0.03, 0.03, 0.03),
    (-0.96, 1.31, 0.13, 0.16, 0.16),
    (-0.89, 1.29, 0.22, 0.25, 0.27),
    (-0.77, 1.27, 0.27, 0.30, 0.33),
    (-0.58, 1.25, 0.29, 0.31, 0.36),
    (-0.36, 1.22, 0.28, 0.33, 0.38),
    (-0.10, 1.21, 0.30, 0.35, 0.39),
    (0.16, 1.22, 0.30, 0.36, 0.38),
    (0.38, 1.25, 0.27, 0.37, 0.34),
    (0.55, 1.26, 0.23, 0.33, 0.30),
    (0.68, 1.22, 0.19, 0.27, 0.26),
    (0.76, 1.18, 0.12, 0.18, 0.18),
    (0.80, 1.16, 0.03, 0.04, 0.04),
)
NECK = ((0, 1.24, 0.42), (0, 1.48, 0.64), (0, 1.72, 0.84), (0, 1.90, 0.96), (0, 1.97, 1.0))
NECK_R = ((.16, .27), (.14, .23), (.115, .18), (.10, .14), (.09, .12))
HEAD = ((0, 1.99, 0.96), (0, 1.92, 1.06), (0, 1.80, 1.22), (0, 1.68, 1.36), (0, 1.60, 1.45), (0, 1.585, 1.475))
HEAD_R = ((.085, .12), (.09, .14), (.078, .105), (.068, .082), (.066, .074), (.05, .05))


def _neck_weight(p):
    a = NECK_PIVOT
    b = HEAD[0]
    axis = sub(b, a)
    t = dot(sub(p, a), axis) / dot(axis, axis)
    return smoothstep(0.05, 0.95, t)


def _horse_colour(look, p, part, seed):
    coat, shade = look["coat"], look["shade"]
    x, y, z = p
    c = coat
    if part in ("body", "muscle", "neck", "head"):
        # Painted fields, not gradients: the belly and the inside of the legs a step darker.
        if y < 0.95 + 0.05 * math.sin(z * 7):
            c = shade
        if look is GREY:
            spot = fbm(x * 7 + seed, z * 7 + y * 5, seed + 3, 3)
            if spot > 0.18 and y > 0.9:
                c = mix(coat, (236, 234, 228), 0.65)
            elif spot < -0.32:
                c = shade
    if part == "head":
        if z > 1.36:
            c = look["muzzle"]
        if look is BAY and abs(x) < 0.03 + 0.02 * (z - 1.0) and 1.05 < z < 1.36 and y > 1.68:
            c = look["blaze"]
    if part == "leg":
        c = look["points"] if (look is BAY and y < 0.58) or y < 0.36 else coat
        if look is GREY and y < 0.58:
            c = look["points"]
        if look is BAY and y < 0.2 and x > 0 and z < 0:
            c = look["blaze"]  # one white sock, hind right
    w = STILL
    if part in ("neck", "head", "ear", "mane", "eye"):
        w = STILL + 0.5 * (1.0 if part in ("head", "ear", "eye") else _neck_weight(p))
    return rgb(c, w)


def horse(look, seed=0):
    """About 9k triangles: lofted barrel, neck and head; muscled legs; cut-paper mane and tail."""
    m = PaintMesh()

    def bulge(a, z):
        # The shoulder and the quarters stand out on the sides of the barrel.
        side = abs(math.cos(a)) ** 3 * (1 if math.sin(a) > -0.2 else 0.4)
        return side * (0.07 * math.exp(-((z - 0.42) / 0.12) ** 2) + 0.08 * math.exp(-((z + 0.66) / 0.16) ** 2))

    m.add(loft_z(BODY, sides=34, per=3, bulge=bulge), lambda p, n: _horse_colour(look, p, "body", seed))
    m.add(sweep(NECK, NECK_R, sides=22, per=3), lambda p, n: _horse_colour(look, p, "neck", seed))
    m.add(sweep(HEAD, HEAD_R, sides=20, per=3), lambda p, n: _horse_colour(look, p, "head", seed))
    # Jaw: the round cheek under the head.
    for sx in (-1, 1):
        m.add(ellipsoid((sx * .045, 1.90, 1.06), (.05, .085, .09), 8, 12),
              lambda p, n: _horse_colour(look, p, "head", seed))
    for sx in (-1, 1):
        # Shoulder and thigh masses, then the legs.
        m.add(ellipsoid((sx * .17, 1.14, .46), (.1, .27, .17), 9, 14),
              lambda p, n: _horse_colour(look, p, "muscle", seed))
        m.add(ellipsoid((sx * .17, 1.06, -.64), (.13, .3, .23), 9, 14),
              lambda p, n: _horse_colour(look, p, "muscle", seed))
        x = sx * .15
        fore = ((x, 1.02, .50), (x, .80, .53), (x, .54, .55), (x, .44, .555), (x, .23, .555), (x, .135, .585),
                (x, .085, .61))
        hind = ((x, 1.10, -.62), (x, .86, -.56), (x, .63, -.71), (x, .53, -.755), (x, .26, -.74), (x, .145, -.70),
                (x, .085, -.675))
        for path, radii in ((fore, (.10, .075, .056, .052, .039, .044, .046)),
                            (hind, (.13, .105, .068, .058, .041, .044, .046))):
            m.add(sweep(path, radii, sides=14, per=3), lambda p, n: _horse_colour(look, p, "leg", seed))
            # Knee / hock and fetlock knuckles.
            for k in (3, 5):
                m.add(ellipsoid(path[k], (radii[k] * 1.08, radii[k] * 1.25, radii[k] * 1.12), 6, 10),
                      lambda p, n: _horse_colour(look, p, "leg", seed))
            hx, _, hz = path[-1]
            m.add(cylinder(.058, .085, 16, top=.047, center=(hx, .0425, hz + .01)), rgb(look["hoof"]))
        # Ears, eyes, nostrils.
        ear_base, ear_tip = (sx * .05, 2.02, .985), (sx * .075, 2.17, .955)
        m.add(sweep((ear_base, lerp(ear_base, ear_tip, .5), ear_tip), ((.03, .022), (.026, .018), (.004, .004)),
                    sides=8, per=2), lambda p, n: _horse_colour(look, p, "ear", seed))
        m.add(ellipsoid((sx * .083, 1.895, 1.115), (.016, .022, .026), 6, 10), rgb(EYE, 1.0))
        m.add(ellipsoid((sx * .036, 1.585, 1.462), (.011, .016, .013), 5, 8), rgb(NOSTRIL, 1.0))
    # The mane: one jagged sheet of cut paper along the crest, falling to the off side.
    crest = catmull([(0, 1.62, 0.36), (0, 1.80, 0.62), (0, 1.98, 0.84), (0, 2.08, 0.97)], 6)
    base, tips = [], []
    for i, (x, y, z) in enumerate(crest):
        k = i / (len(crest) - 1)
        reach = (.13 if i % 2 else .24) * (1 - .3 * k)
        base.append((.02, y - .015, z))
        tips.append((.09 + reach * .45, y - .03 - reach * .85, z - .05 - .03 * (i % 3)))
    m.add(cut_strip(base, tips, .018, rgb(look["mane"]), rgb(look["mane_edge"])))
    m.weight(lambda p: STILL + 0.5 * _neck_weight(p))
    # Forelock between the ears.
    fb = [(-.03, 2.03, .99), (0, 2.04, 1.0), (.03, 2.03, .99)]
    ft = [(-.04, 1.9, 1.05), (.0, 1.86, 1.07), (.035, 1.91, 1.05)]
    m.add(cut_strip(fb, ft, .012, rgb(look["mane"]), rgb(look["mane_edge"])))
    m.weight(lambda p: 1.0)
    # The tail: three tasselled sheets of paper fanned round the dock.
    dock = ((0, 1.38, -.95), (0, 1.30, -1.03), (0, 1.18, -1.07))
    m.add(sweep(dock, (.05, .045, .04), sides=10, per=2), rgb(look["mane"]))
    m.weight(_tail_weight)
    for fan in (-28, 0, 28):
        rot = euler((0, fan, 0))
        base, tips = [], []
        steps = 9
        for i in range(steps):
            k = i / (steps - 1)
            y = 1.22 - .62 * k
            zz = -1.08 - .1 * math.sin(k * 2.2)
            half = .035 + .07 * math.sin(k * math.pi * .85)
            jag = (.05 if i % 2 else 0)
            base.append(_rot_about(rot, (-half, y, zz), TAIL_PIVOT))
            tips.append(_rot_about(rot, (half, y - jag, zz - .01), TAIL_PIVOT))
        m.add(cut_strip(base, tips, .012, rgb(look["mane"]), rgb(look["mane_edge"])))
        m.weight(_tail_weight)
    return m


def _rot_about(rotation, p, pivot):
    return add(apply(rotation, sub(p, pivot)), pivot)


def _tail_weight(p):
    drop = max(0.0, min(1.0, (TAIL_PIVOT[1] - p[1] + .04) / 0.78))
    return STILL - 0.5 * smoothstep(0.0, 1.0, drop)


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


def giant_fly():
    """A fly the size of a dog, circling the heap: the same fly, pasted in at the wrong scale."""
    m = PaintMesh()
    thorax = ((0, .30, .08), (0, .33, .0), (0, .31, -.1))
    m.add(sweep(thorax, (.13, .14, .12), sides=18, per=3), rgb(FLY_BODY))
    m.add(ellipsoid((0, .28, -.3), (.14, .12, .24), 10, 18),
          lambda p, n: rgb(FLY_SHEEN if math.sin(p[2] * 40) > 0 else FLY_BODY))
    m.add(ellipsoid((0, .3, .18), (.1, .09, .07), 8, 14), rgb(FLY_BODY))
    for sx in (-1, 1):
        # Compound eyes: big domes chequered into facets.
        m.add(ellipsoid((sx * .07, .32, .21), (.065, .075, .06), 10, 16),
              lambda p, n: rgb(FLY_EYE if (int(p[1] * 90) + int(p[2] * 90) + int(p[0] * 90)) % 2 else
                               mix(FLY_EYE, (232, 120, 70), .5), 1.0))
        # Legs: three a side, kneeled out and down.
        for k, z in enumerate((.06, -.02, -.1)):
            hip = (sx * .08, .25, z)
            knee = (sx * .26, .32, z + (.05 - .05 * k))
            foot = (sx * .32, .0, z + (.12 - .12 * k))
            m.add(sweep((hip, knee, foot), (.016, .013, .006), sides=6, per=3), rgb(FLY_BODY))
        # Wings: cut film with ink veins, marked to flap.
        outline = [(sx * .05, .42, .0), (sx * .42, .5, -.14), (sx * .5, .47, -.38), (sx * .36, .43, -.52),
                   (sx * .12, .42, -.22)]
        m.mark()
        for poly, out in ((outline, (0, 1, 0)), (list(reversed(outline)), (0, -1, 0))):
            for i in range(1, len(poly) - 1):
                m.polygon([poly[0], poly[i], poly[i + 1]], out)
        m.paint(lambda p, n: rgb(FLY_WING if fbm(p[0] * 14, p[2] * 14, 3, 2) > -.25 else (60, 64, 70), WING))
    # Proboscis.
    m.add(sweep(((0, .26, .22), (0, .16, .27), (0, .1, .25)), (.02, .016, .03), sides=8, per=2), rgb((64, 50, 42)))
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


def daze_halo(stars=3):
    """The knocked-out spiral and its orbiting stars, cut from paper, flat in XZ."""
    m = PaintMesh()
    # Spiral strip.
    inner, outer = [], []
    turns, steps = 2.2, 70
    for i in range(steps):
        t = i / (steps - 1)
        a = t * turns * math.tau
        r = .03 + .19 * t
        w = .012 + .01 * t
        inner.append((math.cos(a) * (r - w), 0, math.sin(a) * (r - w)))
        outer.append((math.cos(a) * (r + w), 0, math.sin(a) * (r + w)))
    sp = cut_strip(inner, outer, .01, rgb(MUSTARD), rgb(INK))
    m.add(sp)
    # Stars.
    for k in range(stars):
        pts = []
        for i in range(10):
            a = math.tau * i / 10 + math.pi / 2
            r = .07 if i % 2 == 0 else .03
            pts.append((math.cos(a) * r, math.sin(a) * r))
        star = slab_polygon(pts, .012, rgb(ACID if k % 2 else (246, 236, 120)), rgb(INK))
        a = math.tau * k / stars
        m.add(star, None, rotation=euler((0, -a * 57.3 + 90, 0)), offset=(math.cos(a) * .3, .06 * math.sin(a * 2),
                                                                           math.sin(a) * .3))
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


def stain(seed, radius, colour):
    """A hard-edged painted puddle of smell on the ground (flat, a millimetre thick)."""
    pts = []
    n = 40
    for i in range(n):
        a = math.tau * i / n
        r = radius * (1 + .35 * fbm(math.cos(a) * 1.4 + seed, math.sin(a) * 1.4, seed, 3))
        pts.append((math.cos(a) * r, math.sin(a) * r * .8))
    m = slab_polygon(pts, .002, rgb(colour), rgb(colour))
    return PaintMesh().merge(m, euler((-90, 0, 0)))
