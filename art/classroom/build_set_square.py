#!/usr/bin/env python3
"""Build the classroom set square in metre-scale, hand-shaped facets.

The wrapper's origin stays on the reading surface; +Z faces the class. The
broken end, notably the notch on the long ruled edge, is not painted on.
"""
from __future__ import annotations

import argparse
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
GAP = 0.014


def slope_z(x):
    return BACK + (x - LEFT) * (FRONT - BACK) / (TIP - LEFT)


def slope_x(z):
    return LEFT + (z - BACK) * (TIP - LEFT) / (FRONT - BACK)


# (x, z) from the straight leg to the hypotenuse, following the splintered grain.
SPLIT = [(0.121, FRONT), (0.112, 0.190), (0.134, 0.173), (0.145, 0.157),
         (0.121, 0.142), (0.127, 0.129), (0.103, 0.115), (0.110, 0.099),
         (0.096, slope_z(0.096))]


def plank(rows, split_side):
    """Close the board and its detached end separately; expose the raw end grain."""
    wood, cut = Facets(), Facets()
    for (z0, l0, r0), (z1, l1, r1) in zip(rows, rows[1:]):
        centre = ((l0 + r0 + l1 + r1) / 4, THICKNESS / 2, (z0 + z1) / 2)
        outline = list(dict.fromkeys(((l0, z0), (r0, z0), (r1, z1), (l1, z1))))
        face_up(wood, [(x, THICKNESS, z) for x, z in outline])
        face_out(wood, [(x, 0.0, z) for x, z in outline], centre)
        for side, (a, b) in enumerate(((l0, l1), (r0, r1))):
            # Only the right edge of the large piece is split; beyond the last
            # splinter that edge is the clean hypotenuse again.
            raw = side == split_side and z1 >= SPLIT[-1][1]
            face_out(cut if raw else wood, [(a, 0, z0), (a, THICKNESS, z0),
                     (b, THICKNESS, z1), (b, 0, z1)], centre)
    z, left, right = rows[0]
    face_out(wood, [(left, 0, z), (left, THICKNESS, z), (right, THICKNESS, z),
             (right, 0, z)], (0, THICKNESS / 2, z - 0.01))
    return wood, cut


def tape(front_x, rear_x, width, lift):
    """A ribbon passes over both edges onto the underside. Its two shoulders
    are rounded in section. The upper pass sits over part of the lower one.
    """
    def edge(offset):
        xf, xr = front_x + offset, rear_x + offset
        # Follow the displaced tip's hypotenuse too, leaving no wood poking out
        # through the tape on the rear edge of the part of the wrap that joins it.
        rear = slope_z(xr - min(max(xr - SPLIT[-1][0], 0.0), GAP))
        bottom, top = -lift, THICKNESS + lift
        return [(xf, top, FRONT + lift * 0.55), (xf, THICKNESS, FRONT + lift),
                (xf, 0, FRONT + lift), (xf - 0.003, bottom, FRONT + lift * 0.55),
                (xr - 0.003, bottom, rear - lift * 0.55), (xr, 0, rear - lift),
                (xr, THICKNESS, rear - lift), (xr - 0.004, top, rear - lift * 0.55)]

    offsets = [-width / 2, width / 2]
    for x in (SPLIT[-1][0], SPLIT[-1][0] + GAP):
        if -width / 2 < x - rear_x < width / 2:
            offsets.append(x - rear_x)
    edges = [edge(offset) for offset in sorted(offsets)]
    mesh = Facets()
    for a, b in zip(edges, edges[1:]):
        for i in range(len(a)):
            j = (i + 1) % len(a)
            centre = ((a[i][0] + b[i][0]) / 2, THICKNESS / 2,
                      (FRONT + slope_z(rear_x)) / 2)
            # Split each quad: the ribbon twists slightly across the taper.
            face_out(mesh, [a[i], a[j], b[j]], centre)
            face_out(mesh, [a[i], b[j], b[i]], centre)
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

    main, main_cut = plank([(z, LEFT, x) for x, z in SPLIT] + [(BACK, LEFT, LEFT)], 1)
    tip_rows = [(z, x + GAP, slope_x(z) + GAP) for x, z in SPLIT[:-1]]
    x, z = SPLIT[-1]
    tip, tip_cut = plank(tip_rows + [(z, x + GAP, x + GAP)], 0)
    b.detail("Board", ".", (0, 0, 0), main, "varnish", shadow=True)
    b.detail("BrokenTip", ".", (0, 0, 0), tip, "varnish", shadow=True)
    painted("ExposedGrain", main_cut, (107, 73, 46), shadow=True)
    painted("TipGrain", tip_cut, (107, 73, 46), shadow=True)
    # Two continuous passes wrap around the wood; the upper pass sits over the
    # edge of the lower one and is seen from both sides at the exposed lap.
    b.detail("TapeRepair", ".", (0, 0, 0), tape(0.048, 0.079, 0.054, 0.002), "tape")
    painted("TapeOverlap", tape(0.082, 0.106, 0.044, 0.004), (191, 150, 79))

    marks = Batch()
    # Worn handhold in the varnish and a few lengthwise broken grain strokes.
    for pigment, y, outline in (
        ("grip", THICKNESS + 0.0005, [(-0.227, 0.123), (-0.201, 0.098),
            (-0.122, 0.106), (-0.067, 0.130), (-0.098, 0.154), (-0.207, 0.160)]),
        ("worn_lacquer", THICKNESS + 0.001, [(-0.211, 0.127), (-0.165, 0.111),
            (-0.093, 0.130), (-0.142, 0.148), (-0.203, 0.150)]),
    ):
        face_up(marks._mesh(pigment), [(x, y, z) for x, z in outline])
    for x, z, length in [(-0.237, 0.088, 0.143), (-0.232, 0.043, 0.152),
                         (-0.216, -0.018, 0.138), (-0.239, -0.079, 0.071),
                         (-0.176, 0.174, 0.112), (-0.099, 0.065, 0.097),
                         (0.164, 0.171, 0.023)]:
        marks.strip("grain", [(x, z), (x + length * 0.57, z + 0.002), (x + length, z - 0.001)],
                    0.0028, THICKNESS + 0.0005)
    for i in range(25):
        x = -0.246 + i * 0.020
        if 0.019 < x < 0.149:  # tape and exposed join interrupt the scale
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
