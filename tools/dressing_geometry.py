"""Merged, outward-facing primitive geometry for dense set dressing (2026-11-20).

The archive's dossier stacks and the offices' confetti tops would otherwise be
hundreds of separate `MeshInstance3D` nodes. `Batch` collects rotated boxes and
flat strips per pigment and emits one `ArrayMesh` per pigment instead. Faces are
oriented away from their own centre, so the winding never depends on how a caller
lists the corners.
"""
from __future__ import annotations

import math

from fixture_geometry import Facets


def _sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def _dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def _normal(points):
    """The normal `Facets.face` will assign to these points (its own cross order)."""
    a, b, c = points[:3]
    u, v = _sub(c, a), _sub(b, a)
    return tuple(u[(i + 1) % 3] * v[(i + 2) % 3] - u[(i + 2) % 3] * v[(i + 1) % 3] for i in range(3))


def face_out(mesh, points, centre):
    """Add a convex face whose normal points away from `centre`."""
    middle = tuple(sum(axis) / len(points) for axis in zip(*points))
    if _dot(_normal(points), _sub(middle, centre)) < 0:
        points = points[::-1]
    mesh.face(*points)


def face_up(mesh, points):
    """Add a horizontal convex face that is lit from above."""
    if _normal(points)[1] < 0:
        points = points[::-1]
    mesh.face(*points)


def rotate(offset, rot):
    """Godot's rotation order (YXZ): roll about Z, then pitch about X, then yaw about Y."""
    x, y, z = offset
    rx, ry, rz = (math.radians(a) for a in rot)
    x, y = x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz)
    y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
    x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
    return (x, y, z)


def solid_loft(rings, *, caps=True):
    """Loft closed rings into a convex solid, capping both ends."""
    centre = tuple(sum(axis) / sum(len(r) for r in rings) for axis in zip(*[p for r in rings for p in r]))
    mesh = Facets()
    for a, b in zip(rings, rings[1:]):
        for i in range(len(a)):
            j = (i + 1) % len(a)
            face_out(mesh, [a[i], a[j], b[j], b[i]], centre)
    if caps:
        face_out(mesh, list(rings[0]), centre)
        face_out(mesh, list(rings[-1]), centre)
    return mesh


def prism(outline, depth):
    """Extrude an XY outline (convex, any winding) through Z, centred on z = 0."""
    front = [(x, y, depth / 2) for x, y in outline]
    back = [(x, y, -depth / 2) for x, y in outline]
    return solid_loft([back, front])


class Batch:
    """Rotated boxes and floor strips, merged into one mesh per pigment."""

    def __init__(self):
        self.meshes: dict[str, Facets] = {}

    def _mesh(self, pigment):
        return self.meshes.setdefault(pigment, Facets())

    def box(self, pigment, centre, size, rot=(0, 0, 0)):
        hx, hy, hz = (s / 2 for s in size)
        corners = {}
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    dx, dy, dz = rotate((sx * hx, sy * hy, sz * hz), rot)
                    corners[sx, sy, sz] = (centre[0] + dx, centre[1] + dy, centre[2] + dz)
        mesh = self._mesh(pigment)
        for axis in range(3):
            for sign in (-1, 1):
                quad = []
                for a, b in ((-1, -1), (-1, 1), (1, 1), (1, -1)):
                    key = [0, 0, 0]
                    key[axis] = sign
                    key[(axis + 1) % 3], key[(axis + 2) % 3] = a, b
                    quad.append(corners[tuple(key)])
                face_out(mesh, quad, centre)

    def chip(self, pigment, centre, radius, sides, angle, y):
        """A flat polygon (a triangle, a square, a dot) lying on a surface at height y."""
        points = [(centre[0] + radius * math.cos(angle + math.tau * i / sides), y,
                   centre[1] + radius * math.sin(angle + math.tau * i / sides)) for i in range(sides)]
        face_up(self._mesh(pigment), points)

    def strip(self, pigment, path, width, y):
        """A flat ribbon along an XZ polyline: Memphis squiggles, floor rules."""
        mesh = self._mesh(pigment)
        for (x0, z0), (x1, z1) in zip(path, path[1:]):
            length = math.hypot(x1 - x0, z1 - z0)
            if length < 1e-6:
                continue
            nx, nz = -(z1 - z0) / length * width / 2, (x1 - x0) / length * width / 2
            face_up(mesh, [(x0 + nx, y, z0 + nz), (x1 + nx, y, z1 + nz), (x1 - nx, y, z1 - nz), (x0 - nx, y, z0 - nz)])

    def emit(self, b, name, parent, *, shadow=False):
        for pigment, mesh in sorted(self.meshes.items()):
            if mesh.points:
                b.detail(f"{name}_{pigment}", parent, (0, 0, 0), mesh, pigment, shadow=shadow)
        self.meshes = {}
