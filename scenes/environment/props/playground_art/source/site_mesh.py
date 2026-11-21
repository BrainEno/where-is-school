"""Indexed, smooth-or-flat triangle meshes written as Godot text ArrayMeshes.

The construction site and the tower interior are authored here instead of in the
binary scenery bake, so they rebuild without the engine. Every primitive orients its
own triangles: Godot treats clockwise faces as front faces, and the outward side of
each part is decided from a reference point (or axis), not from the order in which a
loop happened to be written. Vertex colours carry wetness, grime and rust on the
textured site materials (`vertex_color_use_as_albedo`).
"""

from __future__ import annotations

import base64
import math
import struct

WHITE = (1.0, 1.0, 1.0)
MAX_VERTICES = 65535


# --- small vector helpers -------------------------------------------------------------


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def length(a):
    return math.sqrt(dot(a, a))


def norm(a):
    n = length(a)
    return (0.0, 1.0, 0.0) if n < 1e-12 else (a[0] / n, a[1] / n, a[2] / n)


def lerp(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


# --- rotations (right-handed, the same axes as Godot's Basis) -------------------------


def rot_x(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return ((1, 0, 0), (0, c, -s), (0, s, c))


def rot_y(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return ((c, 0, s), (0, 1, 0), (-s, 0, c))


def rot_z(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return ((c, -s, 0), (s, c, 0), (0, 0, 1))


def matmul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def apply(m, v):
    return tuple(m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2] for i in range(3))


def euler(rot):
    """Godot's rotation_degrees order (YXZ): yaw, then pitch, then roll."""
    x, y, z = rot
    return matmul(matmul(rot_y(y), rot_x(x)), rot_z(z))


IDENTITY = ((1, 0, 0), (0, 1, 0), (0, 0, 1))


# --- deterministic value noise --------------------------------------------------------


def _hash(ix, iy, seed):
    h = (ix * 374761393 + iy * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def noise(x, y, seed=0):
    """Smooth value noise in [-1, 1]."""
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    ux, uy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = _hash(ix, iy, seed)
    b = _hash(ix + 1, iy, seed)
    c = _hash(ix, iy + 1, seed)
    d = _hash(ix + 1, iy + 1, seed)
    return (a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy) * 2 - 1


def fbm(x, y, seed=0, octaves=4):
    total, amp, freq, norm_ = 0.0, 1.0, 1.0, 0.0
    for o in range(octaves):
        total += noise(x * freq, y * freq, seed + o * 31) * amp
        norm_ += amp
        amp *= 0.5
        freq *= 2.03
    return total / norm_


def rand(i, seed=0):
    """A repeatable number in [0, 1) for the i-th scattered thing."""
    return _hash(i, 7919, seed)


# --- the mesh -------------------------------------------------------------------------


class Mesh:
    def __init__(self):
        self.points: list[tuple] = []
        self.normals: list[tuple] = []
        self.colors: list[tuple] = []
        self.indices: list[int] = []

    # Raw access -----------------------------------------------------------------

    def _vertex(self, p, n, c=WHITE):
        self.points.append(tuple(float(v) for v in p))
        self.normals.append(n)
        self.colors.append(c)
        return len(self.points) - 1

    def triangles(self) -> int:
        return len(self.indices) // 3

    # Grids ----------------------------------------------------------------------

    def grid(self, rows, *, wrap=False, centers=None, outward=None, colors=None, flat=False, inward=False):
        """Triangulate between consecutive rows of points (all rows the same length).

        `centers` (one point per row) or `outward` (a direction) says which side is
        the outside; the whole patch is flipped as one if most of it faces the other
        way. `inward=True` makes the inside the front (a room seen from within).
        `colors` matches `rows`. Smooth patches share vertices; flat ones do not.
        """
        cols = len(rows[0])
        span = cols if wrap else cols - 1
        quads = []
        for r in range(len(rows) - 1):
            for k in range(span):
                k1 = (k + 1) % cols
                quads.append(((r, k), (r, k1), (r + 1, k1), (r + 1, k)))

        def pt(rc):
            return rows[rc[0]][rc[1]]

        # Decide orientation from the area-weighted vote of every quad.
        vote = 0.0
        for q in quads:
            a, b, c, d = (pt(v) for v in q)
            n = cross(sub(c, a), sub(b, a))
            centroid = mul(add(add(a, b), add(c, d)), 0.25)
            if centers is not None:
                ref = centers[q[0][0]] if centers[q[0][0]] is not None else centers[q[2][0]]
                vote += dot(n, sub(centroid, ref))
            elif outward is not None:
                vote += dot(n, outward)
        flip = (vote < 0) != inward

        def col(rc):
            return colors[rc[0]][rc[1]] if colors is not None else WHITE

        if flat:
            for q in quads:
                pts = [pt(v) for v in q]
                cs = [col(v) for v in q]
                if flip:
                    pts, cs = pts[::-1], cs[::-1]
                self._flat_fan(pts, cs)
            return self

        base = len(self.points)
        index = {}
        accum = {}
        for r, row in enumerate(rows):
            for k, p in enumerate(row):
                index[(r, k)] = base + len(index)
                self._vertex(p, (0, 1, 0), col((r, k)))
                accum[(r, k)] = [0.0, 0.0, 0.0]
        for q in quads:
            for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                if flip:
                    tri = (tri[0], tri[2], tri[1])
                a, b, c = (pt(v) for v in tri)
                n = cross(sub(c, a), sub(b, a))
                if length(n) < 1e-14:
                    continue
                for v in tri:
                    acc = accum[v]
                    acc[0] += n[0]
                    acc[1] += n[1]
                    acc[2] += n[2]
                self.indices.extend(index[v] for v in tri)
        for key, acc in accum.items():
            self.normals[index[key]] = norm(acc)
        return self

    def _flat_triangle(self, tri, cols=(WHITE, WHITE, WHITE)):
        a, b, c = tri
        n = cross(sub(c, a), sub(b, a))
        if length(n) < 1e-14:
            return
        n = norm(n)
        first = len(self.points)
        for p, cc in zip(tri, cols):
            self._vertex(p, n, cc)
        self.indices.extend((first, first + 1, first + 2))

    def _flat_fan(self, pts, cols):
        """A flat convex polygon (already wound) sharing its corners between triangles."""
        n = (0.0, 0.0, 0.0)
        for i in range(1, len(pts) - 1):
            n = add(n, cross(sub(pts[i + 1], pts[0]), sub(pts[i], pts[0])))
        if length(n) < 1e-14:
            return
        n = norm(n)
        first = len(self.points)
        for p, cc in zip(pts, cols):
            self._vertex(p, n, cc)
        for i in range(1, len(pts) - 1):
            a, b = sub(pts[i], pts[0]), sub(pts[i + 1], pts[0])
            if length(cross(a, b)) < 1e-14:
                continue
            self.indices.extend((first, first + i, first + i + 1))

    def polygon(self, points, outward, color=WHITE):
        """A flat convex polygon facing `outward`."""
        n = (0.0, 0.0, 0.0)
        for i in range(1, len(points) - 1):
            n = add(n, cross(sub(points[i + 1], points[0]), sub(points[i], points[0])))
        if dot(n, outward) < 0:
            points = list(reversed(points))
        self._flat_fan(list(points), [color] * len(points))
        return self

    # Composition ----------------------------------------------------------------

    def merge(self, other: "Mesh", rotation=IDENTITY, offset=(0, 0, 0), scale=(1, 1, 1), tint=None):
        base = len(self.points)
        inv = (1 / scale[0], 1 / scale[1], 1 / scale[2])
        mirrored = scale[0] * scale[1] * scale[2] < 0
        for p, n, c in zip(other.points, other.normals, other.colors):
            sp = (p[0] * scale[0], p[1] * scale[1], p[2] * scale[2])
            sn = norm((n[0] * inv[0], n[1] * inv[1], n[2] * inv[2]))
            cc = c if tint is None else (c[0] * tint[0], c[1] * tint[1], c[2] * tint[2])
            self._vertex(add(apply(rotation, sp), offset), apply(rotation, sn), cc)
        tris = other.indices
        for i in range(0, len(tris), 3):
            a, b, c = tris[i] + base, tris[i + 1] + base, tris[i + 2] + base
            self.indices.extend((a, c, b) if mirrored else (a, b, c))
        return self

    def recolor(self, fn):
        """fn(point, normal, color) -> color, for grime that depends on world height."""
        self.colors = [fn(p, n, c) for p, n, c in zip(self.points, self.normals, self.colors)]
        return self

    def bounds(self):
        lo = tuple(min(p[i] for p in self.points) for i in range(3))
        hi = tuple(max(p[i] for p in self.points) for i in range(3))
        return lo, hi

    # Output ---------------------------------------------------------------------

    def surface(self) -> str:
        if len(self.points) > MAX_VERTICES:
            raise ValueError(f"mesh has {len(self.points)} vertices; split it")
        colors = b""
        if any(c != WHITE for c in self.colors):
            colors = b"".join(
                struct.pack("<4B", *(max(0, min(255, round(v * 255))) for v in c), 255) for c in self.colors
            )
        return _surface(self.points, self.normals, self.indices, colors)


def _surface(points, normals, indices, colors=b""):
    # The same ArrayMesh v2 layout as tools/fixture_geometry.py: float32 positions,
    # octahedral normal + tangent, an optional RGBA8 colour stream and uint16 indices.
    count = len(points)
    assert 3 <= count < 65536
    attributes = f'"attribute_data": {_packed(colors)},\n' if colors else ""
    flags = (1 << 35) | 1 | 2 | 4 | (8 if colors else 0) | (1 << 12)
    origin = tuple(min(axis) for axis in zip(*points))
    size = tuple(max(axis) - lo for axis, lo in zip(zip(*points), origin))
    vertex = b"".join(struct.pack("<3f", *p) for p in points)
    for x, y, z in normals:
        tangent = (-z, 0, x) if abs(y) < 0.95 else (y, -x, 0)
        vertex += _oct16((x, y, z)) + _oct16(tangent, tangent=True)
    index = struct.pack(f"<{len(indices)}H", *indices)
    return (
        "[{\n"
        f'"aabb": AABB({", ".join(f"{v:.5f}" for v in (*origin, *size))}),\n'
        f'"format": {flags},\n'
        f"{attributes}"
        f'"index_count": {len(indices)},\n'
        f'"index_data": {_packed(index)},\n'
        '"primitive": 3,\n'
        f'"vertex_count": {count},\n'
        f'"vertex_data": {_packed(vertex)}\n'
        "}]"
    )


def _packed(data):
    return f'PackedByteArray("{base64.b64encode(data).decode("ascii")}")'


def _oct16(normal, *, tangent=False):
    x, y, z = (c / sum(map(abs, normal)) for c in normal)
    if z < 0:
        x, y = math.copysign(1 - abs(y), x), math.copysign(1 - abs(x), y)
    u, v = (max(0, min(1, c * 0.5 + 0.5)) for c in (x, y))
    if tangent:  # +1 handedness in the high half of V, matching Godot's tangent encoding.
        v = max(v, 1 / 32767) * 0.5 + 0.5
        if u == 0 and v == 1:
            u = 1
    return struct.pack("<2H", int(u * 65535), int(v * 65535))


# --- primitives -----------------------------------------------------------------------


def ring_points(cx, cy, cz, rx, rz, sides, phase=0.0, y=None):
    return [(cx + rx * math.cos(phase + i * math.tau / sides), cy if y is None else y,
             cz + rz * math.sin(phase + i * math.tau / sides)) for i in range(sides)]


def box(size, center=(0, 0, 0), bevel=0.0, color=WHITE):
    """A flat-shaded box, optionally with chamfered edges (bevel in metres)."""
    sx, sy, sz = (s / 2 for s in size)
    b = min(bevel, sx * 0.45, sy * 0.45, sz * 0.45)
    m = Mesh()
    if b <= 0:
        corners = [(-sx, -sz), (sx, -sz), (sx, sz), (-sx, sz)]
        rows = [[(x, -sy, z) for x, z in corners], [(x, sy, z) for x, z in corners]]
        m.grid(rows, wrap=True, centers=[(0, -sy, 0), (0, sy, 0)], flat=True)
        m.polygon(rows[0], (0, -1, 0), color)
        m.polygon(rows[1], (0, 1, 0), color)
    else:
        def section(inset):
            ix, iz = sx - inset, sz - inset
            c = b - inset if inset < b else 0.0
            return [(-ix + c, -iz), (ix - c, -iz), (ix, -iz + c), (ix, iz - c),
                    (ix - c, iz), (-ix + c, iz), (-ix, iz - c), (-ix, -iz + c)]
        levels = [(-sy, b), (-sy + b, 0.0), (sy - b, 0.0), (sy, b)]
        rows = [[(x, y, z) for x, z in section(inset)] for y, inset in levels]
        m.grid(rows, wrap=True, centers=[(0, y, 0) for y, _ in levels], flat=True)
        m.polygon(rows[0], (0, -1, 0), color)
        m.polygon(rows[-1], (0, 1, 0), color)
    if color != WHITE:
        m.colors = [color] * len(m.points)
    out = Mesh()
    return out.merge(m, offset=center)


def cylinder(radius, height, sides=16, *, top=None, caps=True, smooth=True, bevel=0.0, center=(0, 0, 0),
             axis="y", color=WHITE):
    """A cylinder or frustum standing on `axis` and centred on `center`."""
    rt = radius if top is None else top
    h = height / 2
    if bevel > 0:
        b = min(bevel, h * 0.45, min(radius, rt) * 0.45)
        levels = [(-h, radius - b), (-h + b, radius), (h - b, rt), (h, rt - b)]
    else:
        levels = [(-h, radius), (h, rt)]
    rows = [ring_points(0, y, 0, r, r, sides) for y, r in levels]
    m = Mesh()
    if smooth and bevel <= 0:
        m.grid(rows, wrap=True, centers=[(0, y, 0) for y, _ in levels])
    else:
        m.grid(rows, wrap=True, centers=[(0, y, 0) for y, _ in levels], flat=not smooth)
    if caps:
        m.polygon(rows[0], (0, -1, 0))
        m.polygon(rows[-1], (0, 1, 0))
    if color != WHITE:
        m.colors = [color] * len(m.points)
    rotation = {"y": IDENTITY, "x": rot_z(-90), "z": rot_x(90)}[axis]
    return Mesh().merge(m, rotation, center)


def _frames(path):
    """Parallel-transport frames along a polyline."""
    tangents = []
    for i in range(len(path)):
        a = path[max(0, i - 1)]
        b = path[min(len(path) - 1, i + 1)]
        tangents.append(norm(sub(b, a)))
    t0 = tangents[0]
    seed = (0, 1, 0) if abs(t0[1]) < 0.9 else (1, 0, 0)
    u = norm(cross(t0, seed))
    frames = []
    for t in tangents:
        u = norm(sub(u, mul(t, dot(u, t))))
        v = cross(t, u)
        frames.append((u, v))
    return tangents, frames


def tube(path, radius, sides=10, *, closed=False, caps=True, color=WHITE, section=None):
    """A tube along `path`. `radius` may be a number or one radius per point.

    `section` (a list of (u, v) points in the tube's frame) replaces the circle, for
    box sections that follow a curve.
    """
    if closed:
        path = list(path)
    tangents, frames = _frames(path + ([path[0], path[1]] if closed else []))
    if closed:
        frames = frames[:len(path)]
        tangents = tangents[:len(path)]
    if isinstance(radius, tuple) and section is not None and all(isinstance(r, (int, float)) for r in radius):
        radius = [radius] * len(path)  # one (half-width, half-height) for the whole run
    radii = radius if isinstance(radius, (list, tuple)) else [radius] * len(path)
    shape = section or [(math.cos(i * math.tau / sides), math.sin(i * math.tau / sides)) for i in range(sides)]
    rows = []
    for p, (u, v), r in zip(path, frames, radii):
        rx, ry = (r if isinstance(r, (int, float)) else r[0]), (r if isinstance(r, (int, float)) else r[1])
        rows.append([add(p, add(mul(u, a * rx), mul(v, b * ry))) for a, b in shape])
    m = Mesh()
    if closed:
        rows.append(rows[0])
        centers = list(path) + [path[0]]
    else:
        centers = list(path)
    m.grid(rows, wrap=True, centers=centers, flat=section is not None)
    if caps and not closed:
        m.polygon(rows[0], mul(tangents[0], -1))
        m.polygon(rows[-1], tangents[-1])
    if color != WHITE:
        m.colors = [color] * len(m.points)
    return m


def arc(center, radius, start_deg, end_deg, steps, plane="xy"):
    pts = []
    for i in range(steps + 1):
        a = math.radians(start_deg + (end_deg - start_deg) * i / steps)
        c, s = math.cos(a) * radius, math.sin(a) * radius
        if plane == "xy":
            pts.append((center[0] + c, center[1] + s, center[2]))
        elif plane == "xz":
            pts.append((center[0] + c, center[1], center[2] + s))
        else:
            pts.append((center[0], center[1] + s, center[2] + c))
    return pts


def extrude(outline, depth, *, axis="z", center=0.0, color=WHITE, smooth_sides=False):
    """Extrude a 2-D outline (list of (a, b), any winding, convex or not for the sides)
    along `axis`. Caps are fan-triangulated, so concave outlines need `fan_center`
    inside the visible area (fine for the gear, bucket and counterweight shapes here)."""
    h = depth / 2

    def to3(a, b, w):
        return {"z": (a, b, w), "x": (w, a, b), "y": (a, w, b)}[axis]

    front = [to3(a, b, center + h) for a, b in outline]
    back = [to3(a, b, center - h) for a, b in outline]
    cx = sum(a for a, _ in outline) / len(outline)
    cy = sum(b for _, b in outline) / len(outline)
    m = Mesh()
    m.grid([back, front], wrap=True, centers=[to3(cx, cy, center - h), to3(cx, cy, center + h)],
           flat=not smooth_sides)
    axis_dir = {"z": (0, 0, 1), "x": (1, 0, 0), "y": (0, 1, 0)}[axis]
    for ring, sign in ((front, 1), (back, -1)):
        c3 = to3(cx, cy, center + sign * h)
        for i in range(len(ring)):
            tri = (c3, ring[i], ring[(i + 1) % len(ring)])
            n = cross(sub(tri[2], tri[0]), sub(tri[1], tri[0]))
            if dot(n, axis_dir) * sign < 0:
                tri = (tri[0], tri[2], tri[1])
            m._flat_triangle(tri)
    if color != WHITE:
        m.colors = [color] * len(m.points)
    return m


def rock(radius, seed, *, squash=0.6, detail=1, color=WHITE):
    """A small faceted stone or clod (subdivided octahedron with noise)."""
    verts = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
    faces = [(0, 2, 4), (4, 2, 1), (1, 2, 5), (5, 2, 0), (0, 4, 3), (4, 1, 3), (1, 5, 3), (5, 0, 3)]
    for _ in range(detail):
        cache = {}
        new_faces = []

        def mid(i, j):
            key = (min(i, j), max(i, j))
            if key not in cache:
                cache[key] = len(verts)
                verts.append(norm(mul(add(verts[i], verts[j]), 0.5)))
            return cache[key]

        for a, b, c in faces:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            new_faces += [(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)]
        faces = new_faces
    pts = []
    for i, v in enumerate(verts):
        k = 1 + 0.28 * noise(v[0] * 2.1 + seed, v[2] * 2.1 + v[1], seed)
        pts.append((v[0] * radius * k, v[1] * radius * k * squash, v[2] * radius * k))
    m = Mesh()
    for a, b, c in faces:
        tri = (pts[a], pts[b], pts[c])
        n = cross(sub(tri[2], tri[0]), sub(tri[1], tri[0]))
        centroid = mul(add(add(tri[0], tri[1]), tri[2]), 1 / 3)
        if dot(n, centroid) < 0:
            tri = (tri[0], tri[2], tri[1])
        m._flat_triangle(tri, (color, color, color))
    return m


def signed_volume(m: Mesh) -> float:
    """Positive for a closed mesh whose fronts face out (Godot's clockwise winding)."""
    total = 0.0
    p, idx = m.points, m.indices
    for i in range(0, len(idx), 3):
        a, b, c = p[idx[i]], p[idx[i + 1]], p[idx[i + 2]]
        total -= dot(a, cross(b, c))
    return total / 6.0
