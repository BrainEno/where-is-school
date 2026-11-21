"""Offline mesh parts for the school's fitted interiors; no runtime script or importer.

Lofts use clockwise Godot faces with explicit flat normals. Positions and dimensions
remain in metres in the calling builder; only the small generated ArrayMesh is packed.
"""
from __future__ import annotations

import base64
import math
import struct

from build_teaching_block import Build, srgb


class Facets:
    def __init__(self):
        self.points = []
        self.normals = []
        self.indices = []

    def face(self, *points):
        a, b, c = points[:3]
        u = tuple(c[i]-a[i] for i in range(3))
        v = tuple(b[i]-a[i] for i in range(3))
        normal = tuple(u[(i+1)%3]*v[(i+2)%3]-u[(i+2)%3]*v[(i+1)%3] for i in range(3))
        length = math.hypot(*normal)
        if length < 1e-9:
            raise ValueError(f"Degenerate fixture face: {points}")
        first = len(self.points)
        self.points.extend(points)
        self.normals.extend([tuple(n/length for n in normal)]*len(points))
        self.indices.extend(k for j in range(1, len(points)-1) for k in (first, first+j, first+j+1))

    def loft(self, rings):
        for a, b in zip(rings, rings[1:]):
            for i in range(len(a)):
                j = (i+1) % len(a)
                self.face(a[i], a[j], b[j], b[i])
        return self

    def surface(self, colors: bytes = b""):
        # Godot 4 ArrayMesh format v2: POSITION | NORMAL | TANGENT | optional COLOR | INDEX.
        # Positions are float32, normals/tangents octahedral UNORM16, colors RGBA8 in
        # a separate stream, and indices uint16 below 65536 vertices.
        count = len(self.points)
        assert 3 <= count < 65536
        if colors and len(colors) != count * 4:
            raise ValueError("RGBA8 needs four bytes per vertex")
        attributes = f'"attribute_data": {_packed(colors)},\n' if colors else ""
        flags = (1 << 35) | 1 | 2 | 4 | (8 if colors else 0) | (1 << 12)
        origin = tuple(min(axis) for axis in zip(*self.points))
        size = tuple(max(axis)-lo for axis, lo in zip(zip(*self.points), origin))
        vertex = b"".join(struct.pack("<3f", *p) for p in self.points)
        for x, y, z in self.normals:
            tangent = (-z, 0, x) if abs(y) < 0.95 else (y, -x, 0)
            vertex += _oct16((x, y, z)) + _oct16(tangent, tangent=True)
        index = struct.pack(f"<{len(self.indices)}H", *self.indices)
        return (
            '[{\n'
            f'"aabb": AABB({", ".join(f"{v:.7f}" for v in (*origin, *size))}),\n'
            f'"format": {flags},\n'
            f'{attributes}'
            f'"index_count": {len(self.indices)},\n'
            f'"index_data": {_packed(index)},\n'
            '"primitive": 3,\n'
            f'"vertex_count": {count},\n'
            f'"vertex_data": {_packed(vertex)}\n'
            '}]'
        )


def _packed(data):
    return f'PackedByteArray("{base64.b64encode(data).decode("ascii")}")'


def _oct16(normal, *, tangent=False):
    x, y, z = (c / sum(map(abs, normal)) for c in normal)
    if z < 0:
        x, y = math.copysign(1-abs(y), x), math.copysign(1-abs(x), y)
    u, v = (max(0, min(1, c*.5+.5)) for c in (x, y))
    if tangent:  # +1 handedness in the high half of V, matching Godot's tangent encoding.
        v = max(v, 1/32767)*.5+.5
        if u == 0 and v == 1:
            u = 1
    return struct.pack("<2H", int(u*65535), int(v*65535))


def circle(y, rx, rz=None, sides=16):
    return [(rx*math.cos(a), y, (rx if rz is None else rz)*math.sin(a))
            for a in (math.tau*i/sides for i in range(sides))]


def vessel(profile, sides=16):
    """From outer base upward across the lip, then down the hollow. Cap both ends."""
    rings = [circle(y, radius, sides=sides) for y, radius in profile]
    mesh = Facets().loft(rings)
    mesh.face(*reversed(rings[0]))
    mesh.face(*rings[-1])
    return mesh


def rounded_rect(y, width, depth, radius):
    return [(sx*(width/2-radius)+radius*math.cos(a), y, sz*(depth/2-radius)+radius*math.sin(a))
            for i, (sx, sz) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1)))
            for a in (math.pi/2*(i+j/4) for j in range(5))]


def basin(width, depth, drop, radius, drain=0.032):
    """Outer skirt, rolled flange, fillet, sloped sump, and a genuinely open drain."""
    rings = [rounded_rect(y, width-d, depth-d, max(0.006, radius-d/2)) for y, d in (
        (-0.006, 0.014), (0.012, 0), (0.018, 0.014), (0.016, 0.074),
        (-0.007, 0.100), (-drop*0.72, 0.18), (-drop*0.94, 0.24),
    )]
    # Orient the drain rays to the perimeter rays; long sides converge without a twist.
    rays = [(x/math.hypot(x, z), z/math.hypot(x, z)) for x, _, z in rings[-1]]
    rings += [[(x*r, y, z*r) for x, z in rays] for y, r in (
        (-drop, drain+0.010), (-drop-0.008, drain), (-drop-0.028, drain),
    )]
    return Facets().loft(rings)


def pipe(profile, radius, sides=12):
    """Sweep a faceted tube in the XY plane. Adjacent bends share the same ring."""
    rings = []
    for i, (x, y) in enumerate(profile):
        before, after = profile[max(i-1, 0)], profile[min(i+1, len(profile)-1)]
        dx, dy = after[0]-before[0], after[1]-before[1]
        length = math.hypot(dx, dy)
        rings.append([(x+r*dy/length, y-r*dx/length, z) for r, _, z in circle(0, radius, sides=sides)])
    mesh = Facets().loft(rings)
    mesh.face(*reversed(rings[0]))
    mesh.face(*rings[-1])
    return mesh


class FixtureBuild(Build):
    def __init__(self, name, pigments=None, materials=None):
        super().__init__(name)
        self.pigments = pigments or {}
        self.materials = materials or {}

    def surface(self, name):
        if name in self.materials:
            return self.bind(f"mat_{name}", self.materials[name], "Material")
        if name in self.pigments and name not in self.local_mats:
            self.mat(name, albedo_color=srgb(self.pigments[name]))
        return super().surface(name)

    def detail(self, name, parent, pos, mesh, mat, rot=None, shadow=False):
        self.flat(name, parent, self.mesh("ArrayMesh", _surfaces=mesh.surface()), mat, pos, rot, shadow)

    def round(self, name, parent, pos, radius, height, mat, *, top=None, sides=16, rot=None, shadow=False):
        self.flat(name, parent, self.mesh("CylinderMesh", top_radius=f"{radius if top is None else top:g}",
                  bottom_radius=f"{radius:g}", height=f"{height:g}", radial_segments=sides, rings=0),
                  mat, pos, rot, shadow)

    def drain(self, name, parent, pos, radius, steel, dark):
        """A seated strainer. The dark cup is below both the rim and the steel bridges."""
        x, y, z = pos
        self.round(name+"Cup", parent, (x, y-0.010, z), radius, 0.014, dark)
        ring = Facets().loft([circle(y, r) for y, r in ((-0.008, radius), (0, radius),
                           (0, radius*0.80), (-0.008, radius*0.80))])
        self.detail(name+"Ring", parent, pos, ring, steel)
        for i, k in enumerate((-0.47, 0, 0.47)):
            self.box(f"{name}Bridge{i}", parent, (x+radius*k, y-0.002, z),
                     (radius*0.19, 0.007, radius*(1.35 if k else 1.68)), steel)

    def tap(self, name, parent, pos, steel, mark, *, rise=0.33, reach=0.28):
        x, y, z = pos
        self.round(name+"Collar", parent, (x, y+0.014, z), 0.048, 0.028, steel)
        sweep = pipe(((0, 0.025), (0, rise-0.060), (0.019, rise-0.019),
                      (0.064, rise), (reach-0.054, rise), (reach-0.015, rise-0.020),
                      (reach, rise-0.058), (reach, rise-0.088)), 0.019)
        self.detail(name+"Spout", parent, pos, sweep, steel, shadow=True)
        self.round(name+"Aerator", parent, (x+reach, y+rise-0.096, z), 0.022, 0.021, steel)
        self.round(name+"Outlet", parent, (x+reach, y+rise-0.107, z), 0.014, 0.003, mark)
        self.round(name+"Valve", parent, (x, y+0.109, z), 0.030, 0.048, steel, rot=(90, 0, 0))
        self.box(name+"Lever", parent, (x+0.043, y+0.109, z+0.025), (0.109, 0.021, 0.030), mark)
