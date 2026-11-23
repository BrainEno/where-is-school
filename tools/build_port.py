#!/usr/bin/env python3
"""The port (港口): `scenes/locations/port/`.

The truck in the container yard carries a box to the dock (docs/NARRATIVE_BIBLE.md, the
essay's 码头 and 大海); climbing into it brings you here. In docs/MAP_PLAN.md this is the
edge of the world, where the water is the sky laid flat.

* A concrete quay with the sea past its edge toward -z and -x, where the game camera looks,
  and a narrow pier running out into it. Its end is the edge of the world: nothing past it
  but water.
* The water (`sky_water.gdshader`) is lit by nothing: it is the evening sky it would mirror,
  with clouds drifting across it and a slow, broad swell that makes the whole reflection
  tremble.
* A ship-to-shore crane on rails, its boom out over a feeder ship moored alongside, a box
  hanging from the spreader; boxes on the quay waiting to ship; bollards and mooring lines.
* The same truck as in the yard, parked by the stacks, its box open at the tail: the way
  back.

Gameplay is art-first: you arrive by the truck, walk the quay and the pier, and three looks
(the sea from the pier end, the crane, the ship) have lines that are the owner's to write
and are still placeholders. The quay edge is closed by invisible walls; nothing here goes
in the water.

The boxes, the truck and the floodlight masts are the container yard's own meshes
(build_container_yard.py), referenced, not copied. The rest are text ArrayMeshes under
`meshes/`.

    python3 tools/build_port.py           # write the scene and its meshes
    python3 tools/build_port.py --check   # fail if they are not what this writes
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import stable_meshes as sm  # also puts the site mesh kit on the path
from build_container_yard import (CH, COLOURS, CW, L20, L40, RUBBER, RUST, Scene, colour, corrugation, truck, v3)
from site_mesh import box, cylinder, euler, fbm, noise, rand, smoothstep, tube

ROOT = Path(__file__).resolve().parent.parent
REL = "scenes/locations/port"
RES = f"res://{REL}"
SCENE = ROOT / REL / "port.tscn"
MESH_DIR = ROOT / REL / "meshes"
ART = "res://scenes/environment/props/playground_art"
YARD = "res://scenes/locations/container_yard/meshes"

# The quay: land from X_MIN to X_MAX and from the edge Z_EDGE back to the fence at Z_MAX.
X_MIN, X_MAX, Z_EDGE, Z_MAX = -24.0, 22.0, -8.0, 18.0
QUAY_FOOT = -2.6
# Past the fences the land runs on, flat and empty, so the sea is only toward the camera.
FAR_EAST, FAR_BACK = 90.0, 70.0
WATER_Y = -1.8
# The pier: a narrow deck from the quay edge out to the end of the world.
PIER_X, PIER_W, PIER_END = -15.0, 3.2, -26.0
# The crane: legs either side of CRANE_X, on the seaward and the landward rail.
CRANE_X, CRANE_HALF, RAIL_SEA, RAIL_LAND = 14.0, 5.5, -6.2, 3.8
HANG = (CRANE_X, 5.0, -8.7)  # the hanging box: centre of its floor
# The ship: moored along the quay east of the open water.
SHIP_SIDE, SHIP_FAR, SHIP_X0, DECK_Y = -9.4, -25.0, 2.0, 3.4
# The truck: its box's tail (the open doors) at TRUCK_TAIL_X.
TRUCK_TAIL_X, TRUCK_Z = 17.4, 15.2
SPAWN = (TRUCK_TAIL_X + 1.6, 0.0, TRUCK_Z)
# Boxes waiting to ship: rows along x, slots 6.5 m apart, as in the yard.
SLOTS = (-19.5, -13.0, -6.5, 0.0)
WAITING = (
    (6.0, ((0, 1, ("blue", "red")), (2, 2, ("red", "blue", "blue")), (3, 3, ("orange",)))),
    (10.6, ((0, 0, ("red_dark",)), (1, 2, ("blue_deep", "red")))),
)
BOLLARDS = (-22.0, -19.0, -11.0, -7.0, -2.0, 3.0, 8.0, 13.0, 18.0, 21.0)
MOORINGS = ((3.0, 7.5), (8.0, 4.0), (18.0, 13.5), (21.0, 25.0))  # bollard x, where it reaches the ship

CONCRETE = (0.78, 0.77, 0.74)
COPE = (0.84, 0.82, 0.76)
WET = (0.24, 0.26, 0.24)
WEED = (0.2, 0.26, 0.17)
IRON = (0.17, 0.18, 0.2)
ROPE = (0.86, 0.82, 0.7)
YELLOW = (0.88, 0.7, 0.26)
CRANE = (0.86, 0.48, 0.27)
HULL = (0.17, 0.21, 0.3)
ANTIFOUL = (0.5, 0.2, 0.15)
WHITE = (0.88, 0.87, 0.82)
GLASS = (0.1, 0.12, 0.17)
CARGO = ((0.188, 0.361, 0.573), (0.62, 0.18, 0.14), (0.47, 0.17, 0.15), (0.78, 0.78, 0.76), (0.24, 0.42, 0.33),
         (0.14, 0.27, 0.47), (0.88, 0.45, 0.1))


# --- the quay -----------------------------------------------------------------------------


def deck_mesh():
    """The quay's top and the pier's, at y = 0, with stains; the texture gives the grain."""
    m = sm.PaintMesh()

    def patch(x0, x1, z0, z1, nx, nz, seed):
        rows, cols = [], []
        for j in range(nz + 1):
            z = z0 + (z1 - z0) * j / nz
            row, crow = [], []
            for i in range(nx + 1):
                x = x0 + (x1 - x0) * i / nx
                row.append((x, 0.0, z))
                c = sm.mix(CONCRETE, (0.46, 0.45, 0.44), 0.55 * fbm(x * 0.16, z * 0.16, seed))
                rust = fbm(x * 0.5 + 3, z * 0.5, seed + 2)
                if rust > 0.62:
                    c = sm.mix(c, RUST, (rust - 0.62) * 1.6)
                crow.append((*c, 1.0))
            rows.append(row)
            cols.append(crow)
        m.grid(rows, outward=(0, 1, 0), colors=cols)

    patch(X_MIN, X_MAX, Z_EDGE, Z_MAX, 40, 23, 121)
    patch(PIER_X - PIER_W / 2, PIER_X + PIER_W / 2, PIER_END, Z_EDGE, 3, 16, 123)
    return m


def faces_mesh():
    """The quay's and the pier's sides down into the water: a pale cope, grey concrete, a
    dark wet band with weed at the waterline; rubber fenders on the face toward the ship."""
    m = sm.PaintMesh()
    ys = (QUAY_FOOT, WATER_Y, WATER_Y + 0.3, WATER_Y + 0.75, -0.16, 0.0)

    def side(a, b, outward, seed):
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        steps = max(2, int(ln / 1.8))
        rows = [[(a[0] + (b[0] - a[0]) * k / steps, y, a[1] + (b[1] - a[1]) * k / steps) for k in range(steps + 1)]
                for y in ys]
        m.mark()
        m.grid(rows, outward=outward, flat=True)

        def paint(p, _n):
            x, y, z = p
            if y > -0.17:
                return (*sm.mix(COPE, CONCRETE, 0.4 * fbm(x * 0.7, z * 0.7, seed)), 1.0)
            c = sm.mix(CONCRETE, (0.5, 0.5, 0.5), 0.6 * fbm(x * 0.4 + z * 0.4, y * 0.6, seed))
            streak = fbm(x * 1.3 + z * 1.3 + seed, y * 0.2, seed + 1)
            if streak > 0.58:
                c = sm.mix(c, RUST, min(0.6, (streak - 0.58) * 2.2))
            wet = 1.0 - smoothstep(WATER_Y + 0.1, WATER_Y + 0.8, y)
            c = sm.mix(c, WET, 0.85 * wet)
            if y < WATER_Y + 0.35:
                c = sm.mix(c, WEED, 0.6 * noise(x * 1.7 + z * 1.7, y * 3.0, seed + 3))
            return (*c, 1.0)
        m.paint(paint)

    west, east = PIER_X - PIER_W / 2, PIER_X + PIER_W / 2
    side((X_MIN, Z_EDGE), (west, Z_EDGE), (0, 0, -1), 131)
    side((east, Z_EDGE), (X_MAX, Z_EDGE), (0, 0, -1), 132)
    side((X_MIN, Z_EDGE), (X_MIN, Z_MAX), (-1, 0, 0), 133)
    side((X_MAX, Z_EDGE), (FAR_EAST, Z_EDGE), (0, 0, -1), 134)
    side((west, Z_EDGE), (west, PIER_END), (-1, 0, 0), 135)
    side((east, Z_EDGE), (east, PIER_END), (1, 0, 0), 136)
    side((west, PIER_END), (east, PIER_END), (0, 0, -1), 137)
    # A low kerb along every edge, set in from it, its paint worn.
    k = 0.13
    kerbs = (
        (((X_MIN + west) / 2, Z_EDGE + k), (west - X_MIN, 0.24)),
        (((east + X_MAX) / 2, Z_EDGE + k), (X_MAX - east, 0.24)),
        ((X_MIN + k, (Z_EDGE + Z_MAX) / 2), (0.24, Z_MAX - Z_EDGE)),
        ((west + k, (PIER_END + Z_EDGE) / 2), (0.24, Z_EDGE - PIER_END)),
        ((east - k, (PIER_END + Z_EDGE) / 2), (0.24, Z_EDGE - PIER_END)),
        ((PIER_X, PIER_END + k), (PIER_W, 0.24)),
    )
    for (cx, cz), (sx, sz) in kerbs:
        m.add(box((sx, 0.14, sz), (cx, 0.07, cz), bevel=0.03))
        m.paint(lambda p, n: (*sm.mix(YELLOW, COPE, 0.7 * smoothstep(0.4, 0.75, fbm(p[0] * 0.8, p[2] * 0.8, 141))),
                              1.0))
    # Fenders on the face the ship lies along, and on the pier's sides.
    x = X_MIN + 3.0
    while x < X_MAX - 1.0:
        if abs(x - PIER_X) > PIER_W:
            m.add(box((0.9, 1.25, 0.32), (x, -1.0, Z_EDGE - 0.16), bevel=0.06), (*RUBBER, 1.0))
        x += 5.5
    for z in (-12.0, -17.0, -22.0):
        for sx in (-1, 1):
            m.add(box((0.3, 1.1, 0.8), (PIER_X + sx * (PIER_W / 2 + 0.15), -1.0, z)), (*RUBBER, 1.0))
    return m


def markings():
    """Paint on the deck: a yellow edge line, slab joints, lane lines, a hatched keep-clear."""
    m = sm.PaintMesh()
    y = 0.006

    def strip(x0, z0, x1, z1, w, c):
        dx, dz = x1 - x0, z1 - z0
        ln = math.hypot(dx, dz)
        nx, nz = -dz / ln * w / 2, dx / ln * w / 2
        m.mark()
        m.polygon([(x0 + nx, y, z0 + nz), (x1 + nx, y, z1 + nz), (x1 - nx, y, z1 - nz), (x0 - nx, y, z0 - nz)],
                  (0, 1, 0))
        m.paint(lambda p, n: (*sm.mix(c, CONCRETE, 0.7 * smoothstep(0.45, 0.8, fbm(p[0] * 0.9, p[2] * 0.9, 151))),
                              1.0))

    west, east = PIER_X - PIER_W / 2, PIER_X + PIER_W / 2
    strip(X_MIN + 0.6, Z_EDGE + 0.55, west - 0.4, Z_EDGE + 0.55, 0.22, YELLOW)
    strip(east + 0.4, Z_EDGE + 0.55, X_MAX - 0.4, Z_EDGE + 0.55, 0.22, YELLOW)
    for sx in (-1, 1):
        strip(PIER_X + sx * (PIER_W / 2 - 0.45), Z_EDGE + 0.3, PIER_X + sx * (PIER_W / 2 - 0.45), PIER_END + 0.6,
              0.16, YELLOW)
    joint = (0.36, 0.35, 0.34)
    x = X_MIN + 5.0
    while x < X_MAX:
        strip(x, Z_EDGE + 0.9, x, 2.2, 0.05, joint)
        x += 5.0
    for z in (-3.0, 2.2):
        strip(X_MIN + 0.5, z, X_MAX - 0.5, z, 0.05, joint)
    for z in (-12.0, -17.0, -22.0):
        strip(west + 0.2, z, east - 0.2, z, 0.05, joint)
    strip(X_MIN + 0.8, 8.3, 4.6, 8.3, 0.12, COPE)
    strip(X_MIN + 0.8, 12.9, X_MAX - 1.0, 12.9, 0.12, COPE)
    # Keep clear where the pier leaves the quay.
    for i in range(7):
        strip(west + 0.1 + i * 0.5, Z_EDGE + 2.6, west + 0.6 + i * 0.5, Z_EDGE + 1.2, 0.14, YELLOW)
    return m


def iron_mesh():
    """Crane rails, bollards along the edge and on the pier, and the mooring lines."""
    m = sm.PaintMesh()
    for z in (RAIL_SEA, RAIL_LAND):
        m.add(box((X_MAX - X_MIN - 0.4, 0.012, 0.6), ((X_MIN + X_MAX) / 2, 0.003, z)), (0.4, 0.39, 0.38, 1.0))
        m.add(box((X_MAX - X_MIN - 0.4, 0.05, 0.12), ((X_MIN + X_MAX) / 2, 0.025, z)), (0.5, 0.48, 0.46, 1.0))
    spots = [(x, Z_EDGE + 0.5) for x in BOLLARDS]
    spots += [(PIER_X + sx * (PIER_W / 2 - 0.5), z) for sx in (-1, 1) for z in (-14.5, PIER_END + 0.6)]
    for x, z in spots:
        m.add(cylinder(0.2, 0.5, 12, center=(x, 0.25, z)),
              lambda p, n: (*sm.mix(IRON, RUST, 0.5 * noise(p[0] * 9, p[1] * 9, 161)), 1.0))
        m.add(cylinder(0.29, 0.08, 12, center=(x, 0.54, z)), (*IRON, 1.0))
        m.add(cylinder(0.26, 0.06, 12, center=(x, 0.03, z)), (*IRON, 1.0))
    # Lines from the bollards up to the ship's side, sagging a little.
    for bx, sx in MOORINGS:
        a = (bx, 0.42, Z_EDGE + 0.5)
        b = (sx, DECK_Y + 0.6, SHIP_SIDE - 0.3)
        path = []
        for k in range(9):
            t = k / 8
            path.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t - 0.9 * 4 * t * (1 - t),
                         a[2] + (b[2] - a[2]) * t))
        m.add(tube(path, 0.045, 5), (*ROPE, 1.0))
    return m


def lifebuoy_mesh():
    """A ring buoy on a post at the end of the pier."""
    m = sm.PaintMesh()
    m.add(box((0.1, 1.4, 0.1), (0, 0.7, 0)), (*WHITE, 1.0))
    ring = [(0.3 * math.cos(a * math.tau / 16), 1.0 + 0.3 * math.sin(a * math.tau / 16), 0.08) for a in range(16)]
    m.add(tube(ring, 0.075, 8, closed=True),
          lambda p, n: (*((0.92, 0.42, 0.16) if (math.atan2(p[1] - 1.0, p[0]) % (math.pi / 2)) < math.pi / 4
                          else WHITE), 1.0))
    return m


# --- the crane ----------------------------------------------------------------------------


def _hazard(m, centre, size, axis_up=True, bands=6):
    """Yellow and black bands round a leg's foot."""
    x, y, z = centre
    sx, sy, sz = size
    h = sy / bands
    for k in range(bands):
        col = (0.9, 0.72, 0.16, 1.0) if k % 2 == 0 else (0.08, 0.08, 0.09, 1.0)
        m.add(box((sx + 0.04, h, sz + 0.04), (x, y - sy / 2 + h * (k + 0.5), z)), col)


def crane_mesh():
    """A ship-to-shore crane, local x along the quay, origin between its four feet: box
    girder legs with their sill and portal beams and cross bracing, a ladder up one leg, the
    boom with its walkways and lattice, the A-frame and stays, the machinery house, the
    trolley with the driver's cab, the spreader."""
    m = sm.PaintMesh()

    def paint_steel(c, amount=0.22):
        return lambda p, n: (*sm.mix(c, RUST, amount * fbm(p[0] * 0.5 + p[2] * 0.3, p[1] * 0.4, 171)), 1.0)

    orange = paint_steel(CRANE)
    shade = paint_steel(tuple(v * 0.78 for v in CRANE))
    grey = (0.3, 0.3, 0.32, 1.0)
    dark = (0.2, 0.2, 0.22, 1.0)
    rail = (0.9, 0.86, 0.78)
    top_y = 30.2
    for sx in (-1, 1):
        x = sx * CRANE_HALF
        for z in (RAIL_SEA, RAIL_LAND):
            # The bogie: a beam on two wheel sets, a buffer at each end.
            m.add(box((3.0, 0.8, 1.3), (x, 0.82, z)), dark)
            m.add(box((1.6, 0.6, 1.1), (x, 1.5, z)), grey)
            for wx in (-1.0, -0.35, 0.35, 1.0):
                m.add(cylinder(0.3, 0.24, 12, axis="z", center=(x + wx, 0.3, z)), (0.16, 0.16, 0.17, 1.0))
            for bx in (-1, 1):
                m.add(box((0.25, 0.35, 0.5), (x + bx * 1.6, 0.8, z)), (0.9, 0.72, 0.16, 1.0))
            # The leg: a box girder with flanges standing proud at its corners.
            m.add(box((0.94, top_y - 2.0, 0.94), (x, 1.8 + (top_y - 2.0) / 2, z)), orange)
            for fx in (-0.47, 0.47):
                for fz in (-0.47, 0.47):
                    m.add(box((0.08, top_y - 2.4, 0.08), (x + fx, 2.0 + (top_y - 2.4) / 2, z + fz)), shade)
            _hazard(m, (x, 2.9, z), (0.96, 1.8, 0.96))
        # The sill beam low between the seaward and landward legs, the portal beam high,
        # and a K-brace between them.
        mz = (RAIL_SEA + RAIL_LAND) / 2
        span = RAIL_LAND - RAIL_SEA
        m.add(box((1.0, 1.4, span), (x, 14.0, mz)), orange)
        m.add(box((1.04, 0.1, span - 1.0), (x, 14.72, mz)), shade)
        m.add(tube([(x, 1.9, RAIL_LAND - 0.4), (x, 13.4, RAIL_SEA + 0.4)], 0.24, 6), orange)
        m.add(tube([(x, 14.6, RAIL_SEA + 0.4), (x, 29.4, RAIL_LAND - 0.4)], 0.24, 6), orange)
        m.add(tube([(x, 14.6, RAIL_LAND - 0.4), (x, 22.0, mz)], 0.18, 6), orange)
    for z in (RAIL_SEA, RAIL_LAND):
        m.add(box((2 * CRANE_HALF + 1.0, 1.6, 1.2), (0, top_y, z)), orange)
        m.add(box((2 * CRANE_HALF + 1.04, 0.12, 1.24), (0, top_y - 0.6, z)), shade)
        m.add(tube([(-CRANE_HALF + 0.4, 16.0, z), (CRANE_HALF - 0.4, 29.2, z)], 0.2, 6), orange)
        m.add(tube([(CRANE_HALF - 0.4, 16.0, z), (-CRANE_HALF + 0.4, 29.2, z)], 0.14, 6), orange)
        # The number board on the portal beam, toward the quay.
        if z == RAIL_LAND:
            m.add(box((3.4, 1.0, 0.04), (0, top_y, z + 0.62)), (*WHITE, 1.0))
            for k in range(2):
                m.add(box((0.5, 0.7, 0.03), (-0.45 + k * 0.9, top_y, z + 0.65)), (0.1, 0.1, 0.12, 1.0))
    # A caged ladder up the landward east leg, with rest platforms.
    lx, lz = CRANE_HALF + 0.9, RAIL_LAND
    for sz in (-0.25, 0.25):
        m.add(box((0.05, top_y - 3.0, 0.05), (lx, 2.0 + (top_y - 3.0) / 2, lz + sz)), (0.75, 0.75, 0.72, 1.0))
    y = 2.6
    while y < top_y - 1.0:
        m.add(box((0.03, 0.03, 0.5), (lx, y, lz)), (0.75, 0.75, 0.72, 1.0))
        y += 0.6
    y = 4.5
    while y < top_y - 1.5:
        ring = [(lx + 0.35 * math.cos(a * math.tau / 10), y, lz + 0.38 * math.sin(a * math.tau / 10))
                for a in range(10)]
        m.add(tube(ring, 0.025, 4, closed=True), (0.75, 0.75, 0.72, 1.0))
        y += 1.6
    for py in (10.0, 20.0):
        m.add(box((1.2, 0.08, 1.4), (lx - 0.1, py, lz)), grey)
        _railing(m, [(lx + 0.5, py, lz - 0.7), (lx + 0.5, py, lz + 0.7)], 1.0, 0.7, rail)
    # The boom out over the ship and the backreach over the quay: a box girder with a
    # lattice along each side and a walkway with handrails outside it.
    boom_y = 31.8
    m.add(box((2.6, 2.0, 66.0), (0, boom_y, -13.0)), orange)
    m.add(box((2.64, 0.14, 66.0), (0, boom_y - 0.9, -13.0)), shade)
    z = -45.0
    k = 0
    while z < 19.0:
        for sx in (-1, 1):
            m.add(tube([(sx * 1.35, boom_y - 1.0, z), (sx * 1.35, boom_y + 1.0, z + 3.0)] if k % 2 == 0 else
                       [(sx * 1.35, boom_y + 1.0, z), (sx * 1.35, boom_y - 1.0, z + 3.0)], 0.09, 4), orange)
            m.add(box((0.1, 2.0, 0.12), (sx * 1.37, boom_y, z)), shade)
        z += 3.0
        k += 1
    for sx in (-1, 1):
        m.add(box((0.9, 0.06, 64.0), (sx * 1.85, boom_y - 1.0, -13.0)), (0.36, 0.36, 0.38, 1.0))
        _railing(m, [(sx * 2.25, boom_y - 1.0, -44.5), (sx * 2.25, boom_y - 1.0, 18.5)], 1.0, 2.0, rail)
    # The boom tip and its lights.
    m.add(box((3.0, 2.6, 0.6), (0, boom_y, -46.1)), orange)
    for sx in (-1, 1):
        m.add(box((0.3, 0.3, 0.3), (sx * 1.2, boom_y + 1.45, -46.1)), (0.9, 0.2, 0.12, 1.0))
    # The A-frame, its ties and its stays.
    apex = (0.0, 46.0, 0.6)
    for sx in (-1, 1):
        m.add(tube([(sx * 1.3, boom_y + 1.0, -2.0), apex], 0.32, 8), orange)
        m.add(tube([(sx * 1.3, boom_y + 1.0, 3.2), apex], 0.32, 8), orange)
    for t in (0.35, 0.65):
        ya = boom_y + 1.0 + (apex[1] - boom_y - 1.0) * t
        w = 1.3 * (1 - t)
        m.add(tube([(-w, ya, -2.0 + 2.6 * t), (w, ya, -2.0 + 2.6 * t)], 0.12, 6), orange)
        m.add(tube([(-w, ya, 3.2 - 2.6 * t), (w, ya, 3.2 - 2.6 * t)], 0.12, 6), orange)
    m.add(box((1.4, 0.8, 1.4), (apex[0], apex[1] + 0.2, apex[2])), orange)
    m.add(cylinder(0.18, 0.3, 8, center=(apex[0], apex[1] + 0.75, apex[2])), (0.95, 0.15, 0.1, 1.0))
    for zz in (-22.0, -40.0, 12.0, 18.0):
        for sx in (-0.4, 0.4):
            m.add(tube([(sx, apex[1], apex[2]), (sx * 2.5, boom_y + 1.0, zz)], 0.07, 4), (0.3, 0.3, 0.3, 1.0))
    # The machinery house on the backreach: panelled, louvred, a door to the walkway.
    mh = paint_steel(WHITE, 0.3)
    m.add(box((5.0, 4.0, 7.0), (0, boom_y + 3.0, 12.5)), mh)
    m.add(box((5.4, 0.2, 7.4), (0, boom_y + 5.1, 12.5)), (0.7, 0.7, 0.68, 1.0))
    for sx in (-1, 1):
        for k in range(6):
            m.add(box((0.04, 4.0, 0.06), (sx * 2.52, boom_y + 3.0, 9.4 + k * 1.25)), (0.7, 0.7, 0.68, 1.0))
        for k in range(5):
            m.add(box((0.04, 0.12, 1.6), (sx * 2.53, boom_y + 2.0 + k * 0.28, 11.0)), dark)
        m.add(box((0.05, 2.0, 0.9), (sx * 2.53, boom_y + 2.0, 14.6)), (0.5, 0.55, 0.6, 1.0))
    # The trolley, the driver's cab under it with glass all round and in its floor, the
    # ropes and the spreader.
    tz = HANG[2]
    m.add(box((3.2, 1.4, 3.6), (0, boom_y - 1.7, tz)), paint_steel(WHITE))
    for sx in (-1, 1):
        for dz in (-1.3, 1.3):
            m.add(cylinder(0.3, 0.2, 10, axis="x", center=(sx * 1.45, boom_y - 1.05, tz + dz)), dark)
    cab = paint_steel(WHITE)
    cx, cy, cz = 0.6, boom_y - 3.6, tz - 2.6
    m.add(box((0.4, 1.2, 0.4), (cx, boom_y - 2.6, cz + 0.6)), grey)
    m.add(box((2.0, 0.5, 2.4), (cx, cy + 0.9, cz)), cab)
    m.add(box((2.0, 0.4, 2.4), (cx, cy - 0.95, cz)), cab)
    for sx in (-1, 1):
        m.add(box((0.12, 1.5, 0.12), (cx + sx * 0.94, cy, cz - 1.14)), cab)
        m.add(box((0.12, 1.5, 0.12), (cx + sx * 0.94, cy, cz + 1.14)), cab)
    m.add(box((1.8, 1.4, 0.03), (cx, cy, cz - 1.2)), (*GLASS, 1.0))
    m.add(box((1.8, 1.4, 0.03), (cx, cy, cz + 1.2)), (*GLASS, 1.0))
    for sx in (-1, 1):
        m.add(box((0.03, 1.4, 2.2), (cx + sx * 1.0, cy, cz)), (*GLASS, 1.0))
    top = HANG[1] + CH + 0.35
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.add(tube([(sx * 1.2, boom_y - 2.4, tz + sz * 1.0), (sx * 2.4, top, tz + sz * 0.6)], 0.035, 4),
                  (0.25, 0.25, 0.26, 1.0))
    m.add(box((L20, 0.32, CW), (0, top - 0.16, tz)), paint_steel(YELLOW))
    for sx in (-1, 1):
        m.add(box((0.3, 0.5, CW + 0.1), (sx * (L20 / 2 - 0.15), top - 0.3, tz)), paint_steel(YELLOW))
    m.add(box((1.2, 0.5, 1.6), (0, top + 0.2, tz)), paint_steel(YELLOW))
    m.add(cylinder(0.35, 0.4, 10, axis="x", center=(0, top + 0.65, tz)), dark)
    # The festoon cable along the boom, in loops from the trolley back to the tip.
    k = 0
    z = -40.0
    while z < tz - 2.0:
        m.add(tube([(1.0, boom_y - 1.2, z), (1.0, boom_y - 1.8, z + 1.2), (1.0, boom_y - 1.2, z + 2.4)], 0.05, 4),
              dark)
        z += 2.4
        k += 1
    return m


# --- the ship -----------------------------------------------------------------------------

SHIP_MID = (SHIP_SIDE + SHIP_FAR) / 2
SHIP_HALF = (SHIP_SIDE - SHIP_FAR) / 2
KEEL_Y = -3.4
FOCSLE_X, FOCSLE_UP = 61.0, 2.4  # where the raised forecastle starts, and how much higher
HOUSE_X0, HOUSE_X1 = 3.0, 11.4  # the accommodation block, stern to front


def ship_top(x):
    """The height of the hull's top edge (the deck at the side) at `x`."""
    sheer = 0.5 * smoothstep(40.0, 77.0, x) ** 1.6
    return DECK_Y + sheer + FOCSLE_UP * smoothstep(FOCSLE_X, FOCSLE_X + 1.2, x)


def ship_half(x, y):
    """Half the hull's breadth at `x` and height `y`: a raked, flared bow, a full midbody,
    the bilge turning in near the keel and the stern drawn in a little under the water."""
    top = ship_top(x)
    tip = 70.8 + 6.2 * smoothstep(KEEL_Y, top, y) ** 0.8
    if x >= tip:
        return 0.0
    f = 1.0
    if x > 52.0:
        u = (x - 52.0) / (tip - 52.0)
        f = max(0.0, 1.0 - u ** 2.2) ** 0.62
    if x < 9.0:
        f *= 1.0 - 0.16 * (1.0 - (x - SHIP_X0) / (9.0 - SHIP_X0)) * (1.0 - smoothstep(WATER_Y, DECK_Y, y))
    f *= 0.7 + 0.3 * smoothstep(KEEL_Y, KEEL_Y + 1.4, y) ** 0.6
    return SHIP_HALF * f


def _ship_stations():
    xs = [SHIP_X0 + k * 1.5 for k in range(int((52.0 - SHIP_X0) / 1.5) + 1)]
    x = xs[-1]
    while x < 77.0:
        x = min(77.0, x + 0.7)
        xs.append(x)
    for extra in (FOCSLE_X, FOCSLE_X + 0.6, FOCSLE_X + 1.2):
        if all(abs(extra - v) > 0.05 for v in xs):
            xs.append(extra)
    return sorted(xs)


def _hull_strip(m, xs, y0, y1, levels, paint, side):
    """One band of plating between heights y0 and y1 (y1 may be a function of x), on one
    side (+1 the quay side, -1 the far side): a smooth grid, so its colour stays crisp at
    the band's edges."""
    rows, centers = [], []
    for x in xs:
        top = y1(x) if callable(y1) else y1
        bot = y0(x) if callable(y0) else y0
        row = []
        for k in range(levels + 1):
            y = bot + (top - bot) * k / levels
            row.append((x, y, SHIP_MID + side * ship_half(x, y)))
        rows.append(row)
        centers.append((x, (bot + top) / 2, SHIP_MID))
    m.mark()
    m.grid(rows, centers=centers)
    m.paint(paint)


def _cargo_box(m, length, x, y, z, base, seed, face=0):
    """A box on the hatches: its body, dark end frames, a lighter roof, and, on the side
    `face` (+1 or -1 along z) that the quay sees, the corrugated sheet."""
    def body(p, _n):
        c = sm.mix(base, RUST, 0.32 * fbm(p[0] * 0.8 + seed, p[1] * 1.3 + p[2] * 0.4, seed))
        return (*sm.mix(c, (0.1, 0.1, 0.1), 0.25 * (1.0 - smoothstep(y, y + 0.8, p[1]))), 1.0)
    m.add(box((length - 0.14, CH - 0.05, CW - 0.08), (x, y + CH / 2, z)), body)
    frame = tuple(v * 0.6 for v in base)
    for sx in (-1, 1):
        m.add(box((0.16, CH - 0.02, CW - 0.05), (x + sx * (length / 2 - 0.12), y + CH / 2, z)), (*frame, 1.0))
    m.add(box((length - 0.3, 0.03, CW - 0.2), (x, y + CH - 0.03, z)),
          (*sm.mix(base, (0.86, 0.86, 0.88), 0.45), 1.0))
    if face:
        prof = corrugation(x - length / 2 + 0.2, x + length / 2 - 0.2)
        zs = z + face * (CW / 2 - 0.05)
        rows = [[(u, yy, zs + face * off) for u, off in prof] for yy in (y + 0.14, y + CH - 0.12)]
        m.mark()
        m.grid(rows, outward=(0, 0, face), flat=True)
        m.paint(body)


def _railing(m, path, height=1.0, step=1.6, colour=WHITE):
    """Stanchions along a polyline and two rails along their tops."""
    c = (*colour, 1.0)
    total = sum(math.dist(path[i], path[i + 1]) for i in range(len(path) - 1))
    n = max(1, int(total / step))
    pts = []
    for k in range(n + 1):
        d = total * k / n
        for i in range(len(path) - 1):
            seg = math.dist(path[i], path[i + 1])
            if d <= seg or i == len(path) - 2:
                t = min(1.0, d / seg) if seg else 0.0
                pts.append(tuple(path[i][j] + (path[i + 1][j] - path[i][j]) * t for j in range(3)))
                break
            d -= seg
    for p in pts:
        m.add(box((0.05, height, 0.05), (p[0], p[1] + height / 2, p[2])), c)
    for h in (height * 0.5, height):
        m.add(tube([(p[0], p[1] + h, p[2]) for p in path], 0.025, 4), c)


def ship_mesh():
    """A feeder ship's hull: lofted, with a raked bow and a raised forecastle, its decks,
    the gear on the forecastle and rails along the sides. The boxes on the hatches and the
    house at the stern are their own meshes (ship_cargo_mesh, ship_house_mesh), so none of
    the three is past the release's warning size for a model."""
    m = sm.PaintMesh()
    xs = _ship_stations()
    wl = WATER_Y + 0.25

    def plating(p, _n):
        x, y, z = p
        c = sm.mix(HULL, (0.1, 0.12, 0.17), 0.45 * fbm(x * 0.2, y * 0.5 + z * 0.2, 181))
        streak = fbm(x * 1.1 + z * 1.1, y * 0.15, 183)
        if streak > 0.55:
            c = sm.mix(c, RUST, min(0.75, (streak - 0.55) * 2.6))
        # Scrapes where the fenders and the tugs have rubbed.
        if abs(y - 0.4) < 0.9 and noise(x * 0.9, y * 2.0, 189) > 0.72:
            c = sm.mix(c, (0.5, 0.42, 0.36), 0.5)
        return (*c, 1.0)

    def antifoul(p, _n):
        c = sm.mix(ANTIFOUL, (0.3, 0.14, 0.12), 0.4 * fbm(p[0] * 0.4, p[1] * 0.8, 185))
        return (*sm.mix(c, WEED, 0.5 * (1.0 - smoothstep(wl - 0.5, wl, p[1]))), 1.0)

    def sheer_strake(p, _n):
        return (*sm.mix(WHITE, RUST, 0.35 * fbm(p[0] * 0.7, p[1] * 3.0, 187)), 1.0)

    for side in (-1, 1):
        _hull_strip(m, xs, KEEL_Y, wl, 3, antifoul, side)
        _hull_strip(m, xs, wl, wl + 0.16, 1, lambda p, n: (0.08, 0.08, 0.09, 1.0), side)
        _hull_strip(m, xs, wl + 0.16, lambda x: ship_top(x) - 0.42, 5, plating, side)
        _hull_strip(m, xs, lambda x: ship_top(x) - 0.42, ship_top, 1, sheer_strake, side)
    # The keel, closed flat, and the transom across the stern.
    m.polygon([(xs[0], KEEL_Y, SHIP_MID - ship_half(xs[0], KEEL_Y)), (xs[-1], KEEL_Y, SHIP_MID),
               (xs[0], KEEL_Y, SHIP_MID + ship_half(xs[0], KEEL_Y))], (0, -1, 0), (*ANTIFOUL, 1.0))
    # The transom across the stern, in the same bands as the sides.
    top0 = ship_top(SHIP_X0)
    for y0, y1, paint in ((KEEL_Y, wl, antifoul), (wl, wl + 0.16, lambda p, n: (0.08, 0.08, 0.09, 1.0)),
                          (wl + 0.16, top0 - 0.42, plating), (top0 - 0.42, top0, sheer_strake)):
        levels = max(1, int((y1 - y0) / 0.8))
        rows = []
        for k in range(levels + 1):
            y = y0 + (y1 - y0) * k / levels
            hb = ship_half(SHIP_X0, y)
            rows.append([(SHIP_X0, y, SHIP_MID - hb + 2 * hb * j / 6)
                         for j in range(7)])
        m.mark()
        m.grid(rows, outward=(-1, 0, 0))
        m.paint(paint)
    # A white deck line and a dark rubbing strake along the quay side.
    for y_of, rad, col in ((lambda x: ship_top(x) - 0.9, 0.05, WHITE), (lambda x: 0.9, 0.09, (0.08, 0.08, 0.09))):
        path = [(x, y_of(x), SHIP_MID + ship_half(x, y_of(x)) + 0.02) for x in xs if x < 74.0
                and ship_half(x, y_of(x)) > 0.3]
        m.add(tube(path, rad, 4), (*col, 1.0))
    # Draft marks at the stern, midships and the bow: white ticks every two decimetres.
    for mx in (5.0, 38.0, 69.0):
        for k in range(12):
            y = WATER_Y + 0.1 + k * 0.2
            z = SHIP_MID + ship_half(mx, y) + 0.015
            w = 0.36 if k % 5 == 0 else 0.16
            m.add(box((w, 0.07, 0.02), (mx, y, z)), (*WHITE, 1.0))

    # The decks: the main deck from the stern to the forecastle, the forecastle above it.
    deck = lambda p, n: (*sm.mix((0.3, 0.35, 0.32), RUST, 0.45 * fbm(p[0] * 0.3, p[2] * 0.3, 185)), 1.0)
    main = [x for x in xs if x <= FOCSLE_X + 0.6]
    rows = [[(x, DECK_Y - 0.02, SHIP_MID - ship_half(x, DECK_Y) + 0.02),
             (x, DECK_Y - 0.02, SHIP_MID + ship_half(x, DECK_Y) - 0.02)] for x in main]
    m.mark()
    m.grid(rows, outward=(0, 1, 0), flat=True)
    m.paint(deck)
    fwd = [x for x in xs if x >= FOCSLE_X + 1.2]
    rows = [[(x, ship_top(x) - 0.02, SHIP_MID - ship_half(x, ship_top(x)) + 0.02),
             (x, ship_top(x) - 0.02, SHIP_MID + ship_half(x, ship_top(x)) - 0.02)] for x in fwd]
    m.mark()
    m.grid(rows, outward=(0, 1, 0), flat=True)
    m.paint(lambda p, n: (*sm.mix((0.55, 0.22, 0.18), RUST, 0.4 * fbm(p[0] * 0.5, p[2] * 0.5, 186)), 1.0))
    hb = ship_half(FOCSLE_X + 0.9, DECK_Y)
    m.add(box((0.2, FOCSLE_UP + 0.3, 2 * hb - 0.2), (FOCSLE_X + 0.9, DECK_Y + FOCSLE_UP / 2, SHIP_MID)),
          lambda p, n: (*sm.mix(WHITE, RUST, 0.3 * fbm(p[1] * 0.8, p[2] * 0.6, 188)), 1.0))
    # On the forecastle: a windlass, mooring winches and bitts, the foremast.
    fy = ship_top(66.0)
    for sz in (-1, 1):
        m.add(cylinder(0.55, 1.1, 14, axis="z", center=(66.0, fy + 0.7, SHIP_MID + sz * 1.6)), (*IRON, 1.0))
        m.add(cylinder(0.75, 0.12, 14, axis="z", center=(66.0, fy + 0.7, SHIP_MID + sz * 2.2)), (*ANTIFOUL, 1.0))
        m.add(box((1.6, 0.6, 0.8), (66.0, fy + 0.3, SHIP_MID + sz * 0.9)), (0.3, 0.35, 0.32, 1.0))
        for bx in (63.0, 70.0):
            for dz in (0.0, 0.7):
                m.add(cylinder(0.16, 0.6, 10, center=(bx + dz, ship_top(bx) + 0.3, SHIP_MID + sz * 3.4)), (*IRON, 1.0))
    m.add(cylinder(0.16, 9.0, 8, center=(69.0, fy + 4.5, SHIP_MID)), (*WHITE, 1.0))
    m.add(box((0.12, 0.12, 3.0), (69.0, fy + 7.2, SHIP_MID)), (*WHITE, 1.0))
    m.add(box((0.25, 0.25, 0.25), (69.0, fy + 9.1, SHIP_MID)), (0.95, 0.85, 0.6, 1.0))

    # Rails along both sides of the main deck and round the forecastle.
    for side in (-1, 1):
        rx = [x for x in xs if 12.0 <= x <= FOCSLE_X]
        _railing(m, [(x, DECK_Y, SHIP_MID + side * (ship_half(x, DECK_Y) - 0.08)) for x in rx])
        fx = [x for x in xs if FOCSLE_X + 1.2 <= x <= 76.0]
        _railing(m, [(x, ship_top(x), SHIP_MID + side * max(0.05, ship_half(x, ship_top(x)) - 0.08)) for x in fx])
    # Fairleads where the mooring lines come aboard.
    for _bx, sx in MOORINGS:
        m.add(box((0.5, 0.3, 0.2), (sx, ship_top(sx) + 0.15, SHIP_SIDE - 0.1)), (*IRON, 1.0))

    return m


def ship_cargo_mesh():
    """The ship's hatches and the boxes on them."""
    m = sm.PaintMesh()
    # Hatch coamings and their covers, boxes on them in tiers of nought to three, a
    # lashing bridge between each pair of bays.
    rows_z = [SHIP_SIDE - 1.55 - k * 2.5 for k in range(6)]
    cover_y = DECK_Y + 1.1
    for b in range(7):
        bx = 14.6 + b * 6.4
        m.add(box((L20 + 0.3, 1.0, SHIP_HALF * 2 - 1.6), (bx, DECK_Y + 0.5, SHIP_MID)), (0.26, 0.32, 0.28, 1.0))
        m.add(box((L20 + 0.5, 0.12, SHIP_HALF * 2 - 1.4), (bx, DECK_Y + 1.04, SHIP_MID)), (0.33, 0.4, 0.35, 1.0))
        for k in range(3):
            m.add(box((0.14, 0.08, SHIP_HALF * 2 - 1.8), (bx - L20 / 2 + 1.0 + k * 2.0, cover_y + 0.04, SHIP_MID)),
                  (0.22, 0.27, 0.24, 1.0))
        for r, z in enumerate(rows_z):
            tiers = int(rand(b * 11 + r, 191) * 3.6)
            for t in range(tiers):
                base = CARGO[int(rand(b * 31 + r * 7 + t, 193) * (len(CARGO) - 0.5))]
                _cargo_box(m, L20, bx, cover_y + 0.08 + t * CH, z, base, b * 13 + r * 5 + t, face=1 if r == 0 else 0)
        if b < 6:
            lx = bx + 3.2
            for z in [SHIP_SIDE - 0.3] + [z - 1.25 for z in rows_z[:-1]] + [SHIP_FAR + 0.3]:
                m.add(box((0.14, 2 * CH, 0.14), (lx, DECK_Y + CH, z)), (*YELLOW, 1.0))
            for level in (CH, 2 * CH):
                m.add(box((0.5, 0.06, SHIP_HALF * 2 - 0.6), (lx, DECK_Y + level, SHIP_MID)), (0.4, 0.4, 0.38, 1.0))
            _railing(m, [(lx, DECK_Y + 2 * CH, SHIP_FAR + 0.4), (lx, DECK_Y + 2 * CH, SHIP_SIDE - 0.4)], 0.9, 2.5,
                     YELLOW)
    return m


def ship_house_mesh():
    """The accommodation at the stern: a poop, four decks of cabins with their windows, the
    bridge with its wings, the mast and radar on top, the funnel, the lifeboat."""
    def house(p, _n):
        c = sm.mix(WHITE, (0.72, 0.72, 0.7), 0.4 * fbm(p[0] * 0.6, p[1] * 0.4 + p[2] * 0.3, 187))
        streak = fbm(p[0] * 1.6 + p[2] * 1.6, p[1] * 0.25, 190)
        if streak > 0.6:
            c = sm.mix(c, RUST, min(0.5, (streak - 0.6) * 2.0))
        return (*c, 1.0)

    m = sm.PaintMesh()
    glass = (*GLASS, 1.0)
    mid = SHIP_MID
    x0, x1 = HOUSE_X0, HOUSE_X1
    half = 6.0
    # The poop: a full-width deck house under everything.
    poop_top = DECK_Y + 2.4
    m.add(box((x1 + 1.6 - SHIP_X0, 2.4, 2 * (SHIP_HALF - 0.4)), ((SHIP_X0 + x1 + 1.6) / 2, DECK_Y + 1.2, mid)), house)
    _railing(m, [(x1 + 1.5, poop_top, mid - SHIP_HALF + 0.5), (x1 + 1.5, poop_top, mid + SHIP_HALF - 0.5),
                 (SHIP_X0 + 0.2, poop_top, mid + SHIP_HALF - 0.5)])
    levels = 4
    step = 2.7
    for level in range(levels):
        y0 = poop_top + level * step
        m.add(box((x1 - x0, step - 0.15, 2 * half), ((x0 + x1) / 2, y0 + (step - 0.15) / 2, mid)), house)
        # The deck above overhangs a little: a plate that reads as a line round the house.
        m.add(box((x1 - x0 + 0.6, 0.15, 2 * half + 0.6), ((x0 + x1) / 2, y0 + step - 0.075, mid)),
              (0.8, 0.79, 0.76, 1.0))
        wy = y0 + 1.35
        # Windows: the front faces the bow (+x), the side faces the quay (+z).
        for k in range(6):
            z = mid - half + 1.1 + k * 1.95
            m.add(box((0.04, 0.8, 1.0), (x1 + 0.02, wy, z)), glass)
        for k in range(4):
            x = x0 + 1.0 + k * 2.0
            if level % 2 == 0 and k == 3:
                m.add(box((0.85, 1.9, 0.04), (x, y0 + 0.95, mid + half + 0.02)), (0.6, 0.62, 0.6, 1.0))
            else:
                m.add(box((1.0, 0.8, 0.04), (x, wy, mid + half + 0.02)), glass)
        _railing(m, [(x1 + 0.28, y0 + step, mid - half - 0.28), (x1 + 0.28, y0 + step, mid + half + 0.28),
                     (x0 - 0.28, y0 + step, mid + half + 0.28)], 0.9, 1.8)
    # The bridge: wider than the house, its wings reaching the ship's sides, a band of
    # glass across the front and round the wing ends; the roof overhangs as a visor.
    by = poop_top + levels * step
    bw = SHIP_HALF - 0.1
    m.add(box((x1 - x0 - 0.6, 2.5, 2 * half), ((x0 + x1) / 2 + 0.3, by + 1.25, mid)), house)
    for sz in (-1, 1):
        m.add(box((3.0, 2.5, bw - half), (x1 - 1.5, by + 1.25, mid + sz * (half + bw) / 2)), house)
        m.add(box((3.2, 0.1, 2.0), (x1 - 1.6, by - 0.4, mid + sz * (bw - 1.0))), (0.8, 0.79, 0.76, 1.0))
        m.add(box((0.15, 0.4, 0.15), (x1 - 1.6, by - 0.2, mid + sz * (bw - 0.3))), (0.8, 0.79, 0.76, 1.0))
        m.add(box((2.4, 1.0, 0.04), (x1 - 1.5, by + 1.55, mid + sz * (bw + 0.02))), glass)
    k = 0
    z = mid - bw + 0.5
    while z < mid + bw - 0.4:
        m.add(box((0.04, 1.1, 0.9), (x1 + 0.02, by + 1.5, z)), glass)
        z += 1.05
        k += 1
    m.add(box((x1 - x0 + 0.4, 0.2, 2 * bw + 0.4), ((x0 + x1) / 2, by + 2.6, mid)), (0.82, 0.81, 0.78, 1.0))
    # On the bridge roof: the mast, its yard, two radar scanners, a whip aerial.
    ry = by + 2.7
    m.add(box((1.0, 0.8, 1.0), (x1 - 3.0, ry + 0.4, mid)), house)
    m.add(cylinder(0.14, 4.6, 8, center=(x1 - 3.0, ry + 2.3, mid)), (*WHITE, 1.0))
    m.add(box((0.1, 0.1, 3.4), (x1 - 3.0, ry + 3.8, mid)), (*WHITE, 1.0))
    m.add(box((0.2, 0.2, 0.2), (x1 - 3.0, ry + 4.7, mid)), (0.95, 0.85, 0.6, 1.0))
    for dz, w in ((-2.2, 2.6), (2.0, 2.0)):
        m.add(cylinder(0.18, 0.6, 8, center=(x1 - 2.0, ry + 0.3, mid + dz)), (*IRON, 1.0))
        m.add(box((0.25, 0.14, w), (x1 - 2.0, ry + 0.66, mid + dz)), (*WHITE, 1.0))
    m.add(cylinder(0.03, 3.0, 4, center=(x0 + 1.0, ry + 1.5, mid + 3.0)), (*IRON, 1.0))
    # The funnel behind the bridge: a rounded casing, a band of the line's colour, a black
    # top and two exhausts.
    fx, fz = x0 + 1.2, mid
    base_y = poop_top + 2 * step
    rows, centers = [], []
    for y in (base_y, by + 3.8, by + 4.6, by + 5.4, by + 6.2):
        rows.append([(fx + 1.5 * math.cos(a * math.tau / 16) ** 1 * 1.0, y,
                      fz + 1.9 * math.sin(a * math.tau / 16)) for a in range(16)])
        centers.append((fx, y, fz))
    for i, (lo, hi) in enumerate(zip(rows, rows[1:])):
        col = ((*WHITE, 1.0), (*CRANE, 1.0), (*WHITE, 1.0), (0.1, 0.1, 0.11, 1.0))[i]
        m.mark()
        m.grid([lo, hi], wrap=True, centers=[centers[i], centers[i + 1]])
        m.paint(lambda p, n, col=col: col)
    m.polygon(rows[-1], (0, 1, 0), (0.05, 0.05, 0.05, 1.0))
    for dz in (-0.5, 0.5):
        m.add(cylinder(0.22, 1.2, 10, center=(fx - 0.3, by + 6.7, fz + dz)), (0.12, 0.12, 0.12, 1.0))
    # The freefall lifeboat on its ramp off the stern, nose down toward the water.
    tilt = euler((0, 0, -32))
    boat = sm.PaintMesh()
    boat.add(sm.ellipsoid((0, 0, 0), (2.6, 0.75, 0.95), rings=8, sides=14), (0.95, 0.42, 0.12, 1.0))
    boat.add(box((2.6, 0.5, 1.1), (0.3, 0.55, 0)), (0.95, 0.5, 0.18, 1.0))
    boat.add(box((0.7, 0.35, 1.12), (-0.8, 0.5, 0)), glass)
    m.add(boat, rotation=tilt, offset=(SHIP_X0 - 0.4, poop_top + 1.0, mid + 2.4))
    for dz in (-0.75, 0.75):
        m.add(box((5.6, 0.18, 0.16), (0, 0, 0)), (0.5, 0.5, 0.52, 1.0), rotation=tilt,
              offset=(SHIP_X0 - 0.2, poop_top + 0.25, mid + 2.4 + dz))
        m.add(box((0.16, 2.8, 0.16), (SHIP_X0 + 1.6, poop_top + 1.4, mid + 2.4 + dz)), (0.5, 0.5, 0.52, 1.0))
    return m


# --- the scene ----------------------------------------------------------------------------


def waiting():
    """The boxes waiting to ship, as (name, centre, length, colours)."""
    out = []
    for r, (z, row) in enumerate(WAITING):
        for first, last, colours in row:
            x = (SLOTS[first] + SLOTS[last]) / 2
            length = L20 if first == last else L40
            name = f"Row{r}Slot{first}" if first == last else f"Row{r}Slot{first}{last}"
            out.append((name, (x, 0.0, z), length, colours))
    return out


def build() -> Scene:
    s = Scene(RES)
    location = s.res("Script", "res://scripts/world/location_root.gd", "location")
    navigation = s.res("Script", "res://scripts/world/location_navigation.gd", "navigation")
    ambience = s.res("Script", "res://scripts/world/ambience_player.gd", "ambience")
    tone = s.res("AudioStream", "res://assets/audio/room_tone_walkway.wav", "tone")
    exit_scene = s.res("PackedScene", "res://scenes/interaction/location_exit.tscn", "exit")
    look = s.res("PackedScene", "res://scenes/interaction/interactable.tscn", "look")
    water_shader = s.res("Shader", f"{RES}/sky_water.gdshader", "water")
    metal_tile = s.res("Texture2D", f"{ART}/textures/metal_tile.png", "metal_tile")
    ground_tile = s.res("Texture2D", f"{ART}/textures/ground_tile.png", "ground_tile")
    fence = s.res("Material", f"{ART}/materials/fence_panel.tres", "fence")
    boxes = {k: s.res("ArrayMesh", f"{YARD}/{name}.tres", f"yard_{name}")
             for k, name in (((L20, 0), "container20_a"), ((L20, 1), "container20_b"),
                             ((L40, 0), "container40_a"), ((L40, 1), "container40_b"))}
    truck_rig = s.res("ArrayMesh", f"{YARD}/truck.tres", "yard_truck")
    truck_box = s.res("ArrayMesh", f"{YARD}/container40_open.tres", "yard_container40_open")
    mast = s.res("ArrayMesh", f"{YARD}/mast.tres", "yard_mast")

    sky = (0.46, 0.44, 0.54)
    env = s.sub("Environment", "PortEnvironment",
                background_mode="1", background_color=colour(sky),
                ambient_light_source="2", ambient_light_color=colour((0.7, 0.66, 0.76)),
                ambient_light_energy="1.0", tonemap_mode="2", tonemap_exposure="0.7",
                fog_enabled="true", fog_light_color=colour(sky), fog_density="0.007",
                adjustment_enabled="true", adjustment_saturation="1.02", adjustment_contrast="1.04")

    def painted(rid, base, *, texture=None, scale=0.58, world=False, srgb=False):
        # As in the yard: `srgb` when the vertex colour is the whole colour.
        props = {"resource_name": f'"{rid}"', "diffuse_mode": "3", "specular_mode": "2",
                 "vertex_color_use_as_albedo": "true", "albedo_color": colour(base), "roughness": "1.0"}
        if srgb:
            props["vertex_color_is_srgb"] = "true"
        if texture is not None:
            props.update(albedo_texture=texture, uv1_scale=v3((scale, scale, scale)), uv1_triplanar="true")
            if world:
                props["uv1_world_triplanar"] = "true"
        props["texture_filter"] = "3"
        return s.sub("StandardMaterial3D", rid, **props)

    box_mats = {name: painted(f"container_{name}", c, texture=metal_tile) for name, c in COLOURS.items()}
    deck_mat = painted("quay_deck", (0.96, 0.95, 0.95), texture=ground_tile, scale=0.25, world=True)
    face_mat = painted("quay_face", (1, 1, 1), texture=ground_tile, scale=0.3, world=True, srgb=True)
    paint_mat = painted("quay_paint", (1, 1, 1), srgb=True)
    steel_mat = painted("steel", (1, 1, 1), srgb=True)
    crane_mat = painted("crane_steel", (1, 1, 1), texture=metal_tile, scale=0.4, world=True, srgb=True)
    ship_mat = painted("ship", (1, 1, 1), texture=metal_tile, scale=0.35, world=True, srgb=True)
    water_mat = s.sub("ShaderMaterial", "SkyWater", shader=water_shader)

    root = s.node("Port", None, "Node3D", script=location, location_id='&"port"')
    s.node("WorldEnvironment", root, "WorldEnvironment", environment=env)
    s.node("Sun", root, "DirectionalLight3D", rotation_degrees=v3((-40, -150, 0)),
           light_color=colour((1, 0.8, 0.62)), light_energy="0.75", shadow_enabled="true",
           directional_shadow_max_distance="70.0")
    s.node("Navigation", root, "NavigationRegion3D", script=navigation)
    s.node("Ambience", root, "AudioStreamPlayer", stream=tone, volume_db="-30.0", script=ambience,
           target_db="-25.0", pitch_scale="0.7")

    # The sea: one plane, far wider than any view, under the quay as well.
    s.node("Sea", root, "MeshInstance3D", position=v3((0, WATER_Y, -60.0)),
           mesh=s.sub("PlaneMesh", "Plane_sea", size="Vector2(420, 420)"), material_override=water_mat,
           cast_shadow="0")

    # The quay and the pier: slabs to stand on, their sides down into the water.
    s.node("Quay", root, "StaticBody3D", collision_layer="1", collision_mask="0")
    s.node("Land", "Quay", "CollisionShape3D", position=v3(((X_MIN + X_MAX) / 2, -0.15, (Z_EDGE + Z_MAX) / 2)),
           shape=s.sub("BoxShape3D", "Shape_land", size=v3((X_MAX - X_MIN, 0.3, Z_MAX - Z_EDGE))))
    s.node("Pier", "Quay", "CollisionShape3D", position=v3((PIER_X, -0.15, (PIER_END + Z_EDGE) / 2)),
           shape=s.sub("BoxShape3D", "Shape_pier", size=v3((PIER_W, 0.3, Z_EDGE - PIER_END))))
    s.node("Deck", "Quay", "MeshInstance3D", mesh=s.mesh("Deck", deck_mesh()), material_override=deck_mat)
    s.node("Faces", "Quay", "MeshInstance3D", mesh=s.mesh("Faces", faces_mesh()), material_override=face_mat)
    s.node("Markings", "Quay", "MeshInstance3D", mesh=s.mesh("Markings", markings()), material_override=paint_mat,
           cast_shadow="0")
    s.node("Iron", "Quay", "MeshInstance3D", mesh=s.mesh("Iron", iron_mesh()), material_override=steel_mat)
    # The land past the fences: two plain slabs, just under the deck's level.
    for name, (x0, x1, z0, z1) in (("Hinterland", (X_MIN, FAR_EAST, Z_MAX, FAR_BACK)),
                                   ("EastLand", (X_MAX, FAR_EAST, Z_EDGE, Z_MAX))):
        s.node(name, "Quay", "MeshInstance3D", position=v3(((x0 + x1) / 2, -0.01, (z0 + z1) / 2)),
               mesh=s.sub("PlaneMesh", f"Plane_{name}", size=f"Vector2({x1 - x0:g}, {z1 - z0:g})"),
               material_override=deck_mat)
    s.node("Lifebuoy", "Quay", "MeshInstance3D", position=v3((PIER_X + 0.9, 0, PIER_END + 0.45)),
           mesh=s.mesh("Lifebuoy", lifebuoy_mesh()), material_override=steel_mat)

    # Invisible walls along every edge over the water: nothing here goes in.
    west, east = PIER_X - PIER_W / 2, PIER_X + PIER_W / 2
    walls = (
        ("SeaWest", ((X_MIN + west) / 2, Z_EDGE), (west - X_MIN + 0.3, 0.3)),
        ("SeaEast", ((east + X_MAX) / 2, Z_EDGE), (X_MAX - east + 0.3, 0.3)),
        ("WestEdge", (X_MIN, (Z_EDGE + Z_MAX) / 2), (0.3, Z_MAX - Z_EDGE)),
        ("PierWest", (west, (Z_EDGE + PIER_END) / 2), (0.3, Z_EDGE - PIER_END)),
        ("PierEast", (east, (Z_EDGE + PIER_END) / 2), (0.3, Z_EDGE - PIER_END)),
        ("PierEnd", (PIER_X, PIER_END), (PIER_W + 0.3, 0.3)),
    )
    s.node("EdgeWalls", root, "StaticBody3D", collision_layer="1", collision_mask="0")
    for name, (x, z), (sx, sz) in walls:
        s.node(name, "EdgeWalls", "CollisionShape3D", position=v3((x, 0.6, z)),
               shape=s.sub("BoxShape3D", f"Shape_{name}", size=v3((sx, 1.2, sz))))

    # Fences on the land sides.
    s.node("Fences", root, "Node3D")
    for name, pos, size in (("FenceBack", ((X_MIN + X_MAX) / 2, 1.0, Z_MAX), (X_MAX - X_MIN, 2.0, 0.08)),
                            ("FenceEast", (X_MAX, 1.0, (Z_EDGE + 0.6 + Z_MAX) / 2), (0.08, 2.0, Z_MAX - Z_EDGE - 0.6))):
        body = s.node(name, "Fences", "StaticBody3D", position=v3(pos), collision_layer="1", collision_mask="0")
        s.node("CollisionShape3D", body, "CollisionShape3D", shape=s.sub("BoxShape3D", f"Shape_{name}", size=v3(size)))
        s.node("MeshInstance3D", body, "MeshInstance3D", mesh=s.sub("BoxMesh", f"Box_{name}", size=v3(size)),
               material_override=fence)

    # The boxes waiting to ship, stack by stack.
    s.node("Waiting", root, "Node3D")
    for i, (name, centre, length, colours) in enumerate(waiting()):
        body = s.node(name, "Waiting", "StaticBody3D", groups=["camera_occluder"], position=v3(centre),
                      collision_layer="1", collision_mask="0")
        height = CH * len(colours)
        s.node("CollisionShape3D", body, "CollisionShape3D", position=v3((0, height / 2, 0)),
               shape=s.sub("BoxShape3D", f"Shape_{name}", size=v3((length, height, CW))))
        for level, paint in enumerate(colours):
            j = i * 7 + level
            flip = 180.0 if rand(j, 201) > 0.5 else 0.0
            skew = (rand(j, 203) - 0.5) * 0.8 if level else 0.0
            s.node(f"Level{level}", body, "MeshInstance3D", position=v3((0, level * CH, 0)),
                   rotation_degrees=v3((0, flip + skew, 0)), mesh=boxes[(length, int(rand(j, 205) * 2))],
                   material_override=box_mats[paint])

    # The crane: its four legs are what the body meets.
    s.node("Crane", root, "StaticBody3D", groups=["camera_occluder"], position=v3((CRANE_X, 0, 0)),
           collision_layer="1", collision_mask="0")
    leg_bogie = s.sub("BoxShape3D", "Shape_crane_bogie", size=v3((3.0, 1.3, 1.3)))
    leg_column = s.sub("BoxShape3D", "Shape_crane_leg", size=v3((1.0, 28.6, 1.0)))
    for sx in (-1, 1):
        for z in (RAIL_SEA, RAIL_LAND):
            tag = f"{'W' if sx < 0 else 'E'}{'Sea' if z == RAIL_SEA else 'Land'}"
            s.node(f"Bogie{tag}", "Crane", "CollisionShape3D", position=v3((sx * CRANE_HALF, 0.65, z)), shape=leg_bogie)
            s.node(f"Leg{tag}", "Crane", "CollisionShape3D", position=v3((sx * CRANE_HALF, 15.4, z)), shape=leg_column)
    s.node("Frame", "Crane", "MeshInstance3D", mesh=s.mesh("Crane", crane_mesh()), material_override=crane_mat,
           extra_cull_margin="2.0")
    s.node("Hanging", root, "MeshInstance3D", position=v3(HANG), mesh=boxes[(L20, 1)],
           material_override=box_mats["red"])

    # The ship alongside: out over the water, nothing to stand on.
    s.node("Ship", root, "Node3D")
    s.node("Hull", "Ship", "MeshInstance3D", mesh=s.mesh("Ship", ship_mesh()), material_override=ship_mat)
    s.node("Cargo", "Ship", "MeshInstance3D", mesh=s.mesh("ShipCargo", ship_cargo_mesh()), material_override=ship_mat)
    s.node("House", "Ship", "MeshInstance3D", mesh=s.mesh("ShipHouse", ship_house_mesh()), material_override=ship_mat)

    # The truck that brought you, its box open at the tail.
    truck(s, root, (TRUCK_TAIL_X - L40 / 2, 0, TRUCK_Z),
          {"rig_mesh": truck_rig, "rig": steel_mat, "box_mesh": truck_box, "box": box_mats["blue"]})

    # Floodlight masts.
    for i, (x, z) in enumerate(((-8.0, 16.8), (-22.8, 16.6), (-22.8, -6.6), (1.0, -6.9))):
        holder = s.node(f"Mast{i}", root, "Node3D", position=v3((x, 0, z)), rotation_degrees=v3((0, 30 + i * 80, 0)))
        s.node("Pole", holder, "MeshInstance3D", mesh=mast, material_override=steel_mat)
        s.node("Light", holder, "OmniLight3D", position=v3((0, 8.6, 0.6)), light_color=colour((1.0, 0.76, 0.5)),
               light_energy="1.4", omni_range="22.0", omni_attenuation="0.8")

    s.node("SpawnPoints", root, "Node3D")
    s.node("FromContainerYard", "SpawnPoints", "Marker3D", groups=["spawn_point"], position=v3(SPAWN))

    s.node("Interactables", root, "Node3D")
    s.node("BackToContainerYard", "Interactables", instance=exit_scene,
           position=v3((TRUCK_TAIL_X + 0.8, 0.9, TRUCK_Z)), interact_id='&"port_back_to_container_yard"',
           prompt_key='"prompt.port_out"', radius="1.4", outline_paths='PackedStringArray("../../Truck/Box")',
           destination_scene='"res://scenes/locations/container_yard/container_yard.tscn"',
           destination_spawn='&"FromPort"', destination_id='&"container_yard"')
    s.node("SeaLook", "Interactables", instance=look, position=v3((PIER_X, 1.0, PIER_END + 1.0)),
           interact_id='&"port_sea_look"', inspection_id='&"port_sea"', radius="1.6",
           outline_paths='PackedStringArray("../../Quay/Lifebuoy")')
    s.node("CraneLook", "Interactables", instance=look, position=v3((CRANE_X, 1.0, (RAIL_SEA + RAIL_LAND) / 2)),
           interact_id='&"port_crane_look"', inspection_id='&"port_crane"', radius="1.6",
           outline_paths='PackedStringArray("../../Crane/Frame")')
    s.node("ShipLook", "Interactables", instance=look, position=v3((6.0, 1.0, Z_EDGE + 1.0)),
           interact_id='&"port_ship_look"', inspection_id='&"port_ship"', radius="1.6",
           outline_paths='PackedStringArray("../../Ship/Hull", "../../Ship/Cargo", "../../Ship/House")')
    return s


def outputs() -> dict[Path, str]:
    s = build()
    files = {SCENE: s.emit()}
    for name, text in s.files.items():
        files[MESH_DIR / name] = text
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail if the files differ from what this writes")
    args = parser.parse_args()
    files = outputs()
    stale = {p for p in MESH_DIR.glob("*.tres")} - set(files) if MESH_DIR.exists() else set()
    if args.check:
        bad = [p for p, text in files.items() if not p.exists() or p.read_text() != text] + sorted(stale)
        if bad:
            print("port is stale; run python3 tools/build_port.py:")
            for p in bad:
                print("  ", p.relative_to(ROOT))
            return 1
        print(f"port up to date ({len(files)} files)")
        return 0
    MESH_DIR.mkdir(parents=True, exist_ok=True)
    for p in stale:
        p.unlink()
    for p, text in files.items():
        p.write_text(text)
    size = SCENE.stat().st_size
    meshes = sum(p.stat().st_size for p in MESH_DIR.glob("*.tres"))
    print(f"wrote {SCENE.relative_to(ROOT)} ({size:,} bytes) and {len(files) - 1} meshes ({meshes:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
