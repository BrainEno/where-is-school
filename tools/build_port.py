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
from build_container_yard import (CH, COLOURS, CW, L20, L40, RUBBER, RUST, Scene, colour, truck, v3)
from site_mesh import box, cylinder, fbm, noise, rand, smoothstep, tube

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
SHIP_OUTLINE = ((SHIP_X0, SHIP_SIDE), (62.0, SHIP_SIDE), (70.0, -11.4), (76.0, -17.2), (70.0, -23.0),
                (62.0, SHIP_FAR), (SHIP_X0, SHIP_FAR))
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


def crane_mesh():
    """A ship-to-shore crane, local x along the quay, origin between its four feet."""
    m = sm.PaintMesh()

    def paint_steel(c):
        return lambda p, n: (*sm.mix(c, RUST, 0.22 * fbm(p[0] * 0.5 + p[2] * 0.3, p[1] * 0.4, 171)), 1.0)

    orange = paint_steel(CRANE)
    for sx in (-1, 1):
        for z in (RAIL_SEA, RAIL_LAND):
            x = sx * CRANE_HALF
            m.add(box((3.0, 1.0, 1.3), (x, 0.62, z), bevel=0.05), (0.3, 0.3, 0.32, 1.0))
            for wx in (-1.0, 0.0, 1.0):
                m.add(cylinder(0.3, 0.2, 10, axis="z", center=(x + wx, 0.3, z)), (0.2, 0.2, 0.22, 1.0))
            m.add(box((1.0, 28.6, 1.0), (x, 15.4, z)), orange)
        m.add(box((1.0, 1.4, RAIL_LAND - RAIL_SEA), (sx * CRANE_HALF, 14.0, (RAIL_SEA + RAIL_LAND) / 2)), orange)
        m.add(tube([(sx * CRANE_HALF, 1.6, RAIL_LAND), (sx * CRANE_HALF, 13.4, RAIL_SEA)], 0.22, 6), orange)
        m.add(tube([(sx * CRANE_HALF, 14.6, RAIL_SEA), (sx * CRANE_HALF, 29.4, RAIL_LAND)], 0.22, 6), orange)
    for z in (RAIL_SEA, RAIL_LAND):
        m.add(box((2 * CRANE_HALF + 1.0, 1.6, 1.2), (0, 30.2, z)), orange)
        m.add(tube([(-CRANE_HALF, 16.0, z), (CRANE_HALF, 29.0, z)], 0.2, 6), orange)
    # The boom out over the ship, the backreach over the quay, its truss and its stays.
    boom_y = 31.8
    m.add(box((2.6, 2.0, 66.0), (0, boom_y, -13.0)), orange)
    z = -45.0
    k = 0
    while z < 19.0:
        for sx in (-1, 1):
            m.add(tube([(sx * 1.35, boom_y - 1.0, z), (sx * 1.35, boom_y + 1.0, z + 3.0)] if k % 2 == 0 else
                       [(sx * 1.35, boom_y + 1.0, z), (sx * 1.35, boom_y - 1.0, z + 3.0)], 0.09, 4), orange)
        z += 3.0
        k += 1
    apex = (0.0, 46.0, 0.6)
    for sx in (-1, 1):
        m.add(tube([(sx * 1.3, boom_y + 1.0, -2.0), apex], 0.3, 6), orange)
        m.add(tube([(sx * 1.3, boom_y + 1.0, 3.2), apex], 0.3, 6), orange)
    for zz in (-22.0, -40.0, 12.0, 18.0):
        m.add(tube([apex, (0.0, boom_y + 1.0, zz)], 0.08, 4), (0.3, 0.3, 0.3, 1.0))
    m.add(box((5.0, 4.0, 7.0), (0, boom_y + 3.0, 12.5), bevel=0.05), paint_steel(WHITE))
    # The trolley, the driver's cab under it, the ropes and the spreader.
    tz = HANG[2]
    m.add(box((3.2, 1.4, 3.6), (0, boom_y - 1.7, tz)), paint_steel(WHITE))
    m.add(box((2.0, 2.3, 2.4), (0.6, boom_y - 3.6, tz - 2.6)), paint_steel(WHITE))
    m.add(box((2.04, 0.9, 2.0), (0.6, boom_y - 3.2, tz - 2.6)), (*GLASS, 1.0))
    top = HANG[1] + CH + 0.35
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.add(tube([(sx * 1.2, boom_y - 2.4, tz + sz * 1.0), (sx * 2.4, top, tz + sz * 0.6)], 0.035, 4),
                  (0.25, 0.25, 0.26, 1.0))
    m.add(box((L20, 0.32, CW), (0, top - 0.16, tz)), paint_steel(YELLOW))
    m.add(box((1.2, 0.5, 1.6), (0, top + 0.2, tz)), paint_steel(YELLOW))
    return m


# --- the ship -----------------------------------------------------------------------------


def _outline_dense(step=2.0):
    pts = []
    n = len(SHIP_OUTLINE)
    for i in range(n):
        a, b = SHIP_OUTLINE[i], SHIP_OUTLINE[(i + 1) % n]
        k = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / step))
        for j in range(k):
            t = j / k
            pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return pts


def ship_mesh():
    """A feeder ship: hull, deck, the house and funnel at the stern, boxes on the hatches."""
    m = sm.PaintMesh()
    outline = _outline_dense()
    cx = sum(p[0] for p in outline) / len(outline)
    cz = sum(p[1] for p in outline) / len(outline)
    ys = (-3.4, WATER_Y - 0.1, WATER_Y + 0.35, 1.2, DECK_Y - 0.45, DECK_Y)
    m.mark()
    m.grid([[(x, y, z) for x, z in outline] for y in ys], wrap=True, centers=[(cx, y, cz) for y in ys], flat=True)

    def hull(p, _n):
        x, y, z = p
        if y < WATER_Y + 0.2:
            return (*ANTIFOUL, 1.0)
        if y > DECK_Y - 0.5:
            return (*WHITE, 1.0)
        c = sm.mix(HULL, (0.1, 0.12, 0.17), 0.4 * fbm(x * 0.2, y * 0.5 + z * 0.2, 181))
        streak = fbm(x * 1.1 + z * 1.1, y * 0.15, 183)
        if streak > 0.57:
            c = sm.mix(c, RUST, min(0.7, (streak - 0.57) * 2.4))
        return (*c, 1.0)
    m.paint(hull)
    m.mark()
    m.polygon([(x, DECK_Y, z) for x, z in SHIP_OUTLINE], (0, 1, 0))
    m.paint(lambda p, n: (*sm.mix((0.3, 0.35, 0.32), RUST, 0.4 * fbm(p[0] * 0.3, p[2] * 0.3, 185)), 1.0))
    mid_z = (SHIP_SIDE + SHIP_FAR) / 2
    # The house: five decks of cabins, the bridge across the top, the funnel behind.
    house = lambda p, n: (*sm.mix(WHITE, RUST, 0.25 * fbm(p[0] * 0.6, p[1] * 0.4 + p[2] * 0.3, 187)), 1.0)
    m.add(box((7.0, 12.6, 12.4), (7.5, DECK_Y + 6.3, mid_z)), house)
    for level in range(4):
        y = DECK_Y + 2.0 + level * 2.6
        m.add(box((0.04, 0.8, 10.6), (11.03, y, mid_z)), (*GLASS, 1.0))
        m.add(box((5.6, 0.8, 0.04), (7.5, y, mid_z + 6.22)), (*GLASS, 1.0))
    m.add(box((6.0, 2.3, 16.2), (8.0, DECK_Y + 13.75, mid_z)), house)
    m.add(box((0.04, 1.0, 15.6), (11.02, DECK_Y + 14.0, mid_z)), (*GLASS, 1.0))
    m.add(box((3.0, 5.4, 3.6), (4.0, DECK_Y + 15.0, mid_z)), house)
    m.add(box((3.04, 1.2, 3.64), (4.0, DECK_Y + 16.4, mid_z)), (*CRANE, 1.0))
    m.add(box((3.06, 0.6, 3.66), (4.0, DECK_Y + 17.5, mid_z)), (0.12, 0.12, 0.13, 1.0))
    m.add(cylinder(0.14, 9.0, 8, center=(68.0, DECK_Y + 4.5, mid_z)), (*WHITE, 1.0))
    # The cargo: hatch covers, boxes on them in tiers of nought to three.
    rows = [SHIP_SIDE - 1.55 - k * 2.5 for k in range(6)]
    for b in range(7):
        bx = 14.6 + b * 6.4
        m.add(box((L20 + 0.3, 0.4, SHIP_SIDE - SHIP_FAR - 1.0), (bx, DECK_Y + 0.2, mid_z)), (0.26, 0.32, 0.28, 1.0))
        for r, z in enumerate(rows):
            tiers = int(rand(b * 11 + r, 191) * 3.6)
            for t in range(tiers):
                base = CARGO[int(rand(b * 31 + r * 7 + t, 193) * (len(CARGO) - 0.5))]
                seed = b * 13 + r * 5 + t
                m.add(box((L20 - 0.12, CH - 0.03, CW - 0.06), (bx, DECK_Y + 0.4 + t * CH + CH / 2, z)),
                      lambda p, n, base=base, seed=seed: (*sm.mix(base, RUST, 0.3 * fbm(p[0] * 0.8, p[1] + p[2],
                                                                                       seed)), 1.0))
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
           outline_paths='PackedStringArray("../../Ship/Hull")')
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
