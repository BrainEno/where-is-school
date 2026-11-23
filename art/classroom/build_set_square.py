#!/usr/bin/env python3
"""Build the classroom set square in metre-scale, hand-shaped facets.

The wrapper's origin stays on the reading surface; +Z faces the class. The square
is hollow: the same right triangle is cut out of its middle, leaving a wooden
frame a few centimetres wide. Its long right-angle leg is broken across — two
separate pieces, the far one slid a couple of millimetres — and the break is
bound with crooked turns of browned tape that go round the leg. Nothing about the
break is painted on: the two pieces are separate solids and the tape is a ribbon.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from dressing_geometry import Batch, face_out, face_up
from fixture_geometry import Facets, FixtureBuild

SCENE = ROOT / "scenes/environment/props/set_square.tscn"
MATERIALS = "res://assets/materials/classroom"

LEFT, TIP = -0.275, 0.275
BACK, FRONT = -0.21, 0.21
THICKNESS = 0.028
BORDER = 0.055            # width of the wooden frame round the hole
SLIDE = (0.0038, 0.0013)  # how far the broken-off piece sits from the other

# The right angle sits at C; the long leg runs to B, the short one back to A.
C = (LEFT, FRONT)
B = (TIP, FRONT)
A = (LEFT, BACK)


def _inradius() -> float:
    a, b, c = math.dist(C, A), math.dist(C, B), math.dist(A, B)
    return (a + b - c) * 0.5


R_IN = _inradius()
INCENTRE = (LEFT + R_IN, FRONT - R_IN)
K = 1.0 - BORDER / R_IN
I0, I1, I2 = (tuple(INCENTRE[i] + K * (p[i] - INCENTRE[i]) for i in range(2))
              for p in (C, B, A))
Z_IN = FRONT - BORDER      # the hole's edge on the broken leg

# The break runs across the long leg, from its outer edge to the hole, following
# the splintered grain rather than a straight line.
BREAK = [(0.030, FRONT), (0.039, 0.203), (0.027, 0.197), (0.042, 0.189),
         (0.034, 0.181), (0.049, 0.174), (0.041, 0.166), (0.052, Z_IN)]

# Where the tape is wound, in plan: (x of the near edge, x of the far edge, slant,
# lift off the wood). The turns lap over each other and stop short of the break's
# far side, so the splintered end stays visible.
TURNS = [(-0.034, -0.002, 0.10, 0.0012),
         (-0.014, 0.016, -0.12, 0.0020),
         (0.004, 0.034, 0.07, 0.0028)]


def _normal(points):
    a, b, c = points[:3]
    u = tuple(c[i] - a[i] for i in range(3))
    v = tuple(b[i] - a[i] for i in range(3))
    return tuple(u[(i + 1) % 3] * v[(i + 2) % 3] - u[(i + 2) % 3] * v[(i + 1) % 3]
                 for i in range(3))


def face_down(mesh, points):
    if _normal(points)[1] > 0:
        points = points[::-1]
    mesh.face(*points)


def _inside(p, a, b, c) -> bool:
    def side(u, v, w):
        return (v[0] - u[0]) * (w[1] - u[1]) - (v[1] - u[1]) * (w[0] - u[0])
    d1, d2, d3 = side(a, b, p), side(b, c, p), side(c, a, p)
    return (d1 >= 0 and d2 >= 0 and d3 >= 0) or (d1 <= 0 and d2 <= 0 and d3 <= 0)


def triangulate(poly):
    """Ear clipping for the simple outlines the frame is cut into."""
    count = len(poly)
    order = list(range(count))
    area = sum(poly[i][0] * poly[(i + 1) % count][1]
               - poly[(i + 1) % count][0] * poly[i][1] for i in range(count))
    if area < 0:
        order.reverse()
    triangles = []
    while len(order) > 3:
        ear = None
        for k in range(len(order)):
            i0, i1, i2 = order[k - 1], order[k], order[(k + 1) % len(order)]
            a, b, c = poly[i0], poly[i1], poly[i2]
            if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) <= 1e-12:
                continue
            if any(_inside(poly[j], a, b, c) for j in order if j not in (i0, i1, i2)):
                continue
            ear = k
            break
        if ear is None:
            raise ValueError(f"Cannot triangulate {poly}")
        triangles.append((order[ear - 1], order[ear], order[(ear + 1) % len(order)]))
        order.pop(ear)
    triangles.append(tuple(order))
    return triangles


def solid(mesh, poly, edges, inside, *, top=True, bottom=True):
    """Extrude a closed (x, z) outline between y = 0 and THICKNESS.

    `edges` lists the outline edges that are real surfaces (outer rim, hole wall,
    broken end). A seam shared with the neighbouring piece is left out: the two
    pieces butt against each other there and the wall would only z-fight.
    """
    triangles = triangulate(poly) if (top or bottom) else []
    if top:
        for tri in triangles:
            face_up(mesh, [(poly[i][0], THICKNESS, poly[i][1]) for i in tri])
    if bottom:
        for tri in triangles:
            face_down(mesh, [(poly[i][0], 0.0, poly[i][1]) for i in tri])
    centre = (inside[0], THICKNESS * 0.5, inside[1])
    for i in edges:
        p, q = poly[i], poly[(i + 1) % len(poly)]
        face_out(mesh, [(p[0], 0.0, p[1]), (p[0], THICKNESS, p[1]),
                        (q[0], THICKNESS, q[1]), (q[0], 0.0, q[1])], centre)


def rounded_rect_path(y0, y1, z0, z1, radius, steps=3):
    """A closed loop round a rectangle in the YZ plane, corners rounded."""
    points = []

    def arc(cy, cz, a0, a1):
        for step in range(steps + 1):
            angle = math.radians(a0 + (a1 - a0) * step / steps)
            points.append((cy + radius * math.cos(angle), cz + radius * math.sin(angle)))

    arc(y0 + radius, z1 - radius, 180, 90)
    arc(y1 - radius, z1 - radius, 90, 0)
    arc(y1 - radius, z0 + radius, 0, -90)
    arc(y0 + radius, z0 + radius, -90, -180)
    return points


def tape_edge(x, z, slant, phase=0.0):
    """A tape's cut edge, in plan: slanted across the leg and never quite straight."""
    return x + slant * (z - (Z_IN + FRONT) * 0.5) + 0.0012 * math.sin((z - Z_IN) * 70.0 + phase)


def tape_turn(x0, x1, slant, lift, phase=0.0, radius=0.007):
    """One turn of tape: a closed ribbon round the leg's section. Its two cut
    edges are slanted in plan, so the wrap reads as done in a hurry."""
    mesh = Facets()
    path = rounded_rect_path(-lift, THICKNESS + lift, Z_IN - lift, FRONT + lift, radius)
    z_mid = (Z_IN + FRONT) * 0.5
    centre = ((x0 + x1) * 0.5, THICKNESS * 0.5, z_mid)
    for i in range(len(path)):
        y0, z0 = path[i]
        y1, z1 = path[(i + 1) % len(path)]
        face_out(mesh, [
            (tape_edge(x0, z0, slant, phase), y0, z0),
            (tape_edge(x1, z0, slant, phase), y0, z0),
            (tape_edge(x1, z1, slant, phase), y1, z1),
            (tape_edge(x0, z1, slant, phase), y1, z1)], centre)
    return mesh


def tape_tab(x0, x1, z0, z1, lift, rise):
    """The loose end of the tape, not pressed down onto the wood."""
    mesh = Facets()
    y = THICKNESS + lift
    face_up(mesh, [(x0, y, z0), (x0, y, z1), (x1, y + rise, z1), (x1, y + rise, z0)])
    return mesh


def build():
    b = FixtureBuild("SetSquare", materials={
        "varnish": f"{MATERIALS}/varnish_pale.tres",
        "tape": f"{MATERIALS}/tape_browned.tres",
        "ink": f"{MATERIALS}/metal_ink.tres",
        "pigments": f"{MATERIALS}/set_square_pigments.tres",
    })

    def painted(name, mesh, rgb, *, shadow=False):
        # Share a classroom-owned surface. Pigment is per facet, not an embedded
        # material: these details don't get the wood plank's raised ink outline.
        rgba = bytes((*rgb, 255)) * len(mesh.points)
        b.flat(name, ".", b.mesh("ArrayMesh", _surfaces=mesh.surface(rgba)),
               "pigments", (0, 0, 0), shadow=shadow)

    # The frame in three bands, each between an outer edge and the hole's edge.
    hyp = [B, A, I2, I1]      # the long side
    vert = [A, C, I0, I2]     # the short side
    near = [C] + BREAK + [I0]                       # the leg, up to the break
    far = [BREAK[0], B, I1] + BREAK[:0:-1]          # the leg, past the break
    far = [(x + SLIDE[0], z + SLIDE[1]) for x, z in far]

    frame = Facets()
    solid(frame, hyp, (0, 2), (-0.027, 0.014))
    solid(frame, vert, (0, 2), (-0.2475, 0.014))
    solid(frame, near, (0, 1, 2, 3, 4, 5, 6, 7, 8), (-0.10, 0.1825))

    broken = Facets()
    solid(broken, far, (0, 2, 3, 4, 5, 6, 7, 8, 9), (0.18, 0.1825))

    grain = Facets()
    centre_left = (-0.10, THICKNESS * 0.5, 0.1825)
    centre_right = (0.18, THICKNESS * 0.5, 0.1825)
    for p, q in zip(BREAK, BREAK[1:]):
        face_out(grain, [(p[0], 0.0, p[1]), (p[0], THICKNESS, p[1]),
                         (q[0], THICKNESS, q[1]), (q[0], 0.0, q[1])], centre_left)
        face_out(grain, [(p[0] + SLIDE[0], 0.0, p[1] + SLIDE[1]),
                         (p[0] + SLIDE[0], THICKNESS, p[1] + SLIDE[1]),
                         (q[0] + SLIDE[0], THICKNESS, q[1] + SLIDE[1]),
                         (q[0] + SLIDE[0], 0.0, q[1] + SLIDE[1])], centre_right)

    b.detail("Board", ".", (0, 0, 0), frame, "varnish", shadow=True)
    b.detail("BrokenEnd", ".", (0, 0, 0), broken, "varnish", shadow=True)
    painted("ExposedGrain", grain, (107, 73, 46), shadow=True)

    # Three turns, each lapping the last; the end of the roll is left loose on top.
    for name, (x0, x1, slant, lift), phase in zip(
            ("TapeRepair", "TapeRepairLap", "TapeRepairTop"), TURNS, (0.0, 1.7, 3.4)):
        b.detail(name, ".", (0, 0, 0), tape_turn(x0, x1, slant, lift, phase), "tape")
    b.detail("TapeEnd", ".", (0, 0, 0), tape_tab(0.030, 0.058, 0.184, 0.206, 0.0032, 0.004), "tape")
    lap = Facets()
    for index, (x0, x1, slant, lift) in enumerate(TURNS):
        phase = index * 1.7
        for edge in (x0, x1):
            face_up(lap, [(tape_edge(edge, Z_IN, slant, phase), THICKNESS + lift + 0.0004, Z_IN),
                          (tape_edge(edge, FRONT, slant, phase), THICKNESS + lift + 0.0004, FRONT),
                          (tape_edge(edge, FRONT, slant, phase) - 0.0018, THICKNESS + lift + 0.0004, FRONT),
                          (tape_edge(edge, Z_IN, slant, phase) - 0.0018, THICKNESS + lift + 0.0004, Z_IN)])
    painted("TapeOverlap", lap, (176, 136, 71))

    marks = Batch()
    # Worn handhold on the short leg, where the square is held, and the paler
    # lacquer inside it.
    for pigment, y, outline in (
        ("grip", THICKNESS + 0.0005, [(-0.272, 0.196), (-0.240, 0.190), (-0.226, 0.165),
            (-0.228, 0.120), (-0.246, 0.075), (-0.270, 0.060), (-0.273, 0.100),
            (-0.272, 0.150)]),
        ("worn_lacquer", THICKNESS + 0.001, [(-0.268, 0.184), (-0.246, 0.178), (-0.236, 0.158),
            (-0.238, 0.126), (-0.252, 0.092), (-0.266, 0.080), (-0.269, 0.120),
            (-0.268, 0.152)]),
    ):
        face_up(marks._mesh(pigment), [(x, y, z) for x, z in outline])
    # A few lengthwise broken grain strokes, kept inside the frame.
    for x, z, length in [(-0.252, 0.030, 0.052), (-0.250, -0.030, 0.058),
                         (-0.256, -0.086, 0.036), (-0.070, 0.176, 0.070),
                         (-0.010, 0.166, 0.058), (0.120, 0.168, 0.040)]:
        marks.strip("grain", [(x, z), (x + length * 0.57, z + 0.002), (x + length, z - 0.001)],
                    0.0028, THICKNESS + 0.0005)
    # The scale along both legs. It stops where the tape is wound.
    taped = (TURNS[0][0] - 0.004, TURNS[-1][1] + 0.004)
    for i in range(25):
        x = -0.246 + i * 0.020
        if taped[0] < x < taped[1]:
            continue
        marks.strip("ink", [(x, 0.205), (x, 0.177 if i % 5 == 0 else 0.192)],
                    0.0032, THICKNESS + 0.001)
    for i in range(17):
        z = 0.169 - i * 0.020
        marks.strip("ink", [(-0.269, z), (-0.241 if i % 5 == 0 else -0.256, z)],
                    0.0032, THICKNESS + 0.001)
    for pigment, color in (("grain", (189, 148, 103)), ("grip", (231, 208, 166)),
                           ("worn_lacquer", (246, 225, 188))):
        painted(f"Face_{pigment}", marks.meshes.pop(pigment), color)
    marks.emit(b, "Face", ".")
    scene = b.emit()
    header, rest = scene.split("\n\n", 1)
    return header + "\n\n; Rebuild with python3 art/classroom/build_set_square.py\n\n" + rest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify the shipped scene without rewriting it")
    output = build()
    if parser.parse_args().check:
        if SCENE.read_text() != output:
            raise SystemExit("Set square drift; rebuild with art/classroom/build_set_square.py")
    else:
        SCENE.write_text(output)


if __name__ == "__main__":
    main()
