"""The stable yard's ground after round 19 (docs/EXAM_DREAM_ART.md): trodden, uneven earth.

The owner asked for the yard and lane to read as the same soil as the playground outside,
not a flat brown plane: ground that rises and dips underfoot, straw blown across it, a
few droppings where the horses happened to stand, and some flies. This module is pure
geometry, in `StableYard`-local metres (the yard node sits 4 m west of the annex origin):

* `height(x, z)` is the relief above the unchanged, flat walking slab: a few centimetres of
  lumps and hollows from layered value noise, the same order as the playground's soil
  (`tools/build_yard_earth.py`). It eases down to a near-flat floor wherever something
  stands on the ground (the grain mat, the women, the coop, the bales, the hens) and to the
  old 4 mm plane inside the dream house and at the lane's mouth, so nothing floats or
  sinks and the connector's flat earth meets it without a step.
* `earth()` is that relief as one smooth mesh over the yard and the lane. The existing
  vertex colours are retained in the mesh; `stable_earth.gdshader` now uses the original
  playground soil pigment directly, without multiplying it by those colours. No collider.
* `straw()` scatters loose straw: thin drifts against the walls, a few tufts kicked out
  across the yard and single strands everywhere, each lying on the relief.
* `DUNG` is six droppings at irregular spots and sizes; `SWARMS` puts a handful of flies
  over three of them.
"""
from __future__ import annotations

import math

from stable_meshes import PaintMesh, mix, rgb
from stable_props import STRAW, STRAW_DARK, STRAW_PALE, strand
from site_mesh import euler, fbm, rand, smoothstep

LANE_X, LANE_Z = (-40.2, -20.75), (14.68, 18.45)
YARD_X, YARD_Z = (-40.2, -26.95), (4.6, LANE_Z[0])
HOUSE_X, HOUSE_Z = (-40.2, -33.2), (4.6, 10.4)
FLOOR = .004
STEP = .2

# (x0, x1, z0, z1, amplitude kept) - rectangles where things stand. Soft by EASE metres.
SETTLED = (
    (-32.75, -29.65, 11.65, 13.75, .15),   # the grain mat
    (-33.75, -32.45, 11.6, 13.3, .2),      # the seated woman, her stool, basket and sack
    (-28.95, -28.25, 12.55, 13.25, .25),   # the raker's feet
    (-29.8, -27.4, 5.3, 7.1, .1),          # the coop
    (-33.35, -32.15, 4.6, 10.4, .35),      # the swept strip along the stall fronts
    (-40.0, -38.9, 16.95, 18.3, .15),      # the stacked bales
    (-33.0, -30.5, 4.6, 6.4, .2),          # the manure bay
)
HENS = ((-29.7, 7.9), (-28.5, 8.1), (-30.3, 9.3))
EASE = .45


def _inside(x, z, x0, x1, z0, z1):
    """1 inside the rectangle, easing to 0 over EASE outside it."""
    dx = max(x0 - x, 0.0, x - x1)
    dz = max(z0 - z, 0.0, z - z1)
    return 1.0 - smoothstep(0.0, EASE, math.hypot(dx, dz))


def keep(x, z):
    """How much of the free relief survives here (0 = the flat floor, 1 = open ground)."""
    k = 1.0
    if HOUSE_X[0] <= x <= HOUSE_X[1] - .05 and HOUSE_Z[0] <= z <= HOUSE_Z[1]:
        return 0.0
    for x0, x1, z0, z1, amount in SETTLED:
        k = min(k, 1.0 - (1.0 - amount) * _inside(x, z, x0, x1, z0, z1))
    for hx, hz in HENS:
        k = min(k, .2 + .8 * smoothstep(.12, .45, math.hypot(x - hx, z - hz)))
    # The lane's mouth meets the connector's flat earth.
    k = min(k, smoothstep(LANE_X[1] + .1, LANE_X[1] - 1.6, x))
    return k


def relief(x, z):
    """Free relief before settling: broad swells, smaller lumps and trodden hollows."""
    swell = fbm(x * .42 + 3.1, z * .42 - 1.7, 61, 3)
    lump = fbm(x * 1.7, z * 1.7, 67, 2)
    # Hollows trodden where people and horses walk: a soft trough down the lane and
    # from the lane to the stall fronts, broken up so it does not read as a rut.
    lane_path = math.exp(-((z - 16.4 - .5 * math.sin(x * .37)) / .9) ** 2) if z > LANE_Z[0] - .3 else 0.0
    stall_path = math.exp(-((x + 31.8 + .4 * math.sin(z * .5)) / .8) ** 2) if z < LANE_Z[0] + .6 else 0.0
    trodden = max(lane_path, stall_path) * (.6 + .4 * fbm(x * .9, z * .9, 71, 2))
    return .04 + .04 * swell + .016 * lump - .025 * trodden


def height(x, z):
    k = keep(x, z)
    return FLOOR + (max(relief(x, z), FLOOR) - FLOOR) * k


def _shade(x, z, h):
    """Retained vertex colours: hollows and damp ground darker, crowns paler."""
    dip = smoothstep(.05, .0, h)
    damp = smoothstep(.2, .65, fbm(x * .3 - 5, z * .3 + 2, 73, 3))
    # The ground nearest the stalls and the heap stays darker and damper.
    near = max(math.exp(-((x + 32.6) / 1.4) ** 2) * (1.0 if z < 11.5 else 0.0), math.exp(-(math.hypot(x + 31.75, z - 5.4) / 1.6) ** 2))
    v = 1.0 - .1 * dip - .1 * damp - .1 * near + .06 * smoothstep(.05, .09, h)
    return (v, v * .985, v * .97)


def _patch(x0, x1, z0, z1):
    nx = max(1, round((x1 - x0) / STEP))
    nz = max(1, round((z1 - z0) / STEP))
    rows, colours = [], []
    for j in range(nz + 1):
        z = z0 + (z1 - z0) * j / nz
        row, cols = [], []
        for i in range(nx + 1):
            x = x0 + (x1 - x0) * i / nx
            h = height(x, z)
            row.append((x, h, z))
            cols.append(rgb(_shade(x, z, h)))
        rows.append(row)
        colours.append(cols)
    m = PaintMesh().grid(rows, outward=(0, 1, 0), colors=colours)
    return m


def earth():
    """The yard and the lane as one relief mesh (they share the edge at LANE_Z[0])."""
    m = PaintMesh()
    m.add(_patch(*YARD_X, *YARD_Z))
    m.add(_patch(*LANE_X, *LANE_Z))
    return m


# --- straw blown about the yard -------------------------------------------------------------

def _drift(points, count, seed, spread):
    """Straws scattered about a polyline (a drift along a wall) or a point (a tuft)."""
    out = []
    for i in range(count):
        t = rand(i, seed)
        if len(points) == 1:
            cx, cz = points[0]
        else:
            seg = min(int(t * (len(points) - 1)), len(points) - 2)
            u = t * (len(points) - 1) - seg
            (ax, az), (bx, bz) = points[seg], points[seg + 1]
            cx, cz = ax + (bx - ax) * u, az + (bz - az) * u
        r = spread * math.sqrt(rand(i, seed + 1))
        a = rand(i, seed + 2) * math.tau
        out.append((cx + r * math.cos(a), cz + r * math.sin(a * 1.3) * .9))
    return out


def straw(seed=19):
    """Loose straw over the yard and lane: drifts at the walls, tufts, and single strands."""
    spots = []
    # Drifts along the foot of the walls, where the wind leaves it.
    spots += _drift([(-39.9, 15.0), (-39.9, 11.0)], 90, seed, .35)
    spots += _drift([(-38.5, 18.2), (-31.0, 18.25), (-26.0, 18.2)], 110, seed + 10, .3)
    spots += _drift([(-33.0, 4.85), (-27.4, 4.8)], 45, seed + 20, .28)
    # A few tufts dropped from a fork, at no particular place.
    for k, (x, z, n) in enumerate(((-34.6, 9.6, 36), (-30.8, 10.4, 26), (-36.3, 15.6, 30), (-28.6, 15.9, 22),
                                   (-35.2, 13.1, 20), (-31.7, 14.3, 18), (-37.6, 17.1, 28))):
        spots += _drift([(x, z)], n, seed + 30 + k, .32 + .1 * (k % 3))
    # Single strands everywhere, thinning toward the lane's mouth.
    for i in range(260):
        x = LANE_X[0] + .2 + (LANE_X[1] - LANE_X[0] - 1.5) * rand(i, seed + 90) ** 1.3
        z = YARD_Z[0] + .2 + (LANE_Z[1] - YARD_Z[0] - .4) * rand(i, seed + 91)
        if z < LANE_Z[0] and x > YARD_X[1] - .1:
            continue
        spots.append((x, z))
    m = PaintMesh()
    for i, (x, z) in enumerate(spots):
        if not (LANE_X[0] + .05 < x < LANE_X[1] - .3 and YARD_Z[0] + .05 < z < LANE_Z[1] - .05):
            continue
        if z < LANE_Z[0] and x > YARD_X[1] - .05:
            continue
        if keep(x, z) == 0.0:
            continue  # inside the dream house; it has its own bedding
        c = mix(STRAW, STRAW_PALE, rand(i, seed + 4)) if rand(i, seed + 7) > .3 else STRAW_DARK
        c = mix(c, (150, 128, 84), .25 * rand(i, seed + 8))  # trodden, weathered
        length = .09 + .18 * rand(i, seed + 3) ** 1.5
        m.add(strand(length, .009 + .004 * rand(i, seed + 5)), rgb(c),
              rotation=euler((rand(i, seed + 6) * 14 - 7, rand(i, seed + 9) * 360, rand(i, seed + 11) * 10 - 5)),
              offset=(x, height(x, z) + .004 + .006 * rand(i, seed + 2), z))
    return m


# --- droppings and flies ----------------------------------------------------------------

# (x, z, variant, scale, yaw) - where they happened to fall, not a pattern.
DUNG = (
    (-32.48, 7.15, 0, 1.35, 23),
    (-31.15, 9.85, 1, 1.1, 141),
    (-35.3, 14.25, 2, .95, 260),
    (-29.75, 10.95, 1, .8, 77),
    (-38.15, 16.1, 0, 1.2, 312),
    (-30.55, 17.05, 2, 1.0, 199),
)
# (dropping index, fly count, spread) - only some droppings draw flies.
SWARMS = ((0, 7, .16), (1, 5, .12), (4, 6, .15))


def dung_at(i):
    x, z, variant, scale, yaw = DUNG[i]
    return (x, height(x, z) - .006, z), variant, scale, yaw
