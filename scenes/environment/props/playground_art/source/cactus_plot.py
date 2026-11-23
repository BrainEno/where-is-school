#!/usr/bin/env python3
"""The cactus plot in the schoolyard (round 20): `playground_art/cactus_plot.tscn`.

    python3 scenes/environment/props/playground_art/source/cactus_plot.py

The owner asked for the second of their two reference images to be rebuilt in the yard,
surreal and exact: on a plain concrete floor, out in the open, a square of bare soil let
into the paving as if a slab had been lifted out, a giant ribbed saguaro growing in it, and
beside it a little girl skipping with a rope. In the picture she is seen from behind and a
little to one side: fair hair in a bun, a white long-sleeved dress gathered at the waist,
white tights and white shoes, the rope's loop down at her feet and one knee lifted.

The yard stays in its blue dusk (the owner's choice, round 20). These two are lit as if it
were still broad day: their shader (`shaders/cactus_glow.gdshader`) adds a key light of its
own from the upper left, so the saguaro and the girl are the brightest things in the frame,
the way the house in Magritte's *Empire of Light* stands lit under a daytime sky.

What it writes, and nothing else:

* `cactus_plot.tscn`: the plot's root (instanced by `tools/build_outdoor_locations.py` at
  `CACTUS_PLOT`), the soil (`Plot`), the saguaro (`Saguaro`, a solid in the camera-occluder
  group so it fades when it stands between the camera and the player; its box is pinned in
  `tests/playground_art_slice_test.gd`) and the girl (`Girl`), whose single looping clip
  (`Motion`) hops her and turns the rope round her. No script, actor or interactable.
* `cactus_plot_view.tscn`: the same, for the yard seen from the teaching block's windows
  (`tools/build_teaching_block.py`), where the view carries no physics: no solid, no fade.
* `meshes/cactus_plot/*.tres`: the sculpted, vertex-painted meshes (text ArrayMesh).
* `materials/cactus_glow.tres`, `materials/girl_glow.tres`, `materials/cactus_soil.tres`.

The concrete skin round the plot (`earth_yard.tscn`, `tools/build_yard_earth.py`) has the
plot's 3 x 3 m square cut out of it, so the soil sits a few centimetres below the paving
inside a clean edge. Pure Python and deterministic, like the other yard generators.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ART = HERE.parent
ROOT = HERE.parents[4]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(HERE))

from stable_meshes import PaintMesh, catmull, ellipsoid, mix, rgb, sweep  # noqa: E402
from stable_animals import Cone, Ell, Field, surface  # noqa: E402
from stable_workers import ik  # noqa: E402
from site_mesh import _frames, fbm, noise, rand, smoothstep  # noqa: E402

RES = "res://scenes/environment/props/playground_art"
MESH_DIR = "meshes/cactus_plot"
SCENE = ART / "cactus_plot.tscn"
# The same plot for the yard seen from the teaching block's windows: no solid, no fade.
VIEW_SCENE = ART / "cactus_plot_view.tscn"

PLOT_HALF = 1.5            # the square of soil, 3 x 3 m, centred on the scene origin
PAVING = 0.05              # the concrete skin's top (tools/build_yard_earth.py)
SAGUARO_AT = (-0.3, 0.0, -0.25)
SAGUARO_HEIGHT = 4.4
SAGUARO_BOX = (0.7, SAGUARO_HEIGHT, 0.7)
# She stands on the paving off the plot's south-east corner, facing it, so the yard's
# camera (from the south-east) sees her from behind with the saguaro beyond her.
GIRL_AT = (1.25, PAVING, 2.2)
GIRL_YAW = -160.0
GIRL_BOX = (0.8, 1.3, 1.0)  # x across her, z the sweep of the rope in front and behind
SKIP_PERIOD = 0.84
HOP = 0.075

# --- palette (sRGB) -------------------------------------------------------------------------
SAG_RIDGE = (204, 206, 104)
SAG_FLANK = (150, 164, 70)
SAG_VALLEY = (78, 98, 46)
SAG_OLD = (150, 134, 96)      # the corky grey-brown at the foot of an old saguaro
SAG_CROWN = (214, 210, 120)
AREOLE = (226, 214, 168)
SPINE = (236, 226, 186)
SOIL = (124, 86, 58)
SOIL_DARK = (86, 58, 40)
SOIL_DRY = (158, 120, 86)
GRAVEL = ((176, 160, 138), (132, 118, 104), (196, 178, 150), (104, 92, 84))
CUT_EDGE = (78, 80, 90)
DRESS = (244, 242, 236)
DRESS_SHADE = (214, 214, 214)
SMOCK = (196, 196, 200)
TIGHTS = (238, 236, 232)
SHOE = (248, 246, 240)
SOLE = (196, 190, 180)
SKIN = (238, 200, 176)
SKIN_DEEP = (214, 168, 146)
HAIR = (232, 202, 128)
HAIR_DEEP = (190, 152, 86)
HAIR_LIGHT = (248, 228, 164)
ROPE = (238, 228, 204)
HANDLE = (214, 176, 120)


def _add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def _sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def _scale(a, s):
    return tuple(x * s for x in a)


def _len(a):
    return math.sqrt(sum(x * x for x in a))


def _unit(a):
    n = _len(a)
    return tuple(x / n for x in a)


def _dot(a, b):
    return sum(x * y for x, y in zip(a, b))


# --- the saguaro ---------------------------------------------------------------------------


def rib(theta, ribs, depth):
    """Radius factor of a ribbed stem: broad rounded ribs, narrow creases between them."""
    g = 0.5 + 0.5 * math.cos(ribs * theta)
    return 1.0 - depth * (1.0 - g) ** 2.2, g


def _stem_colour(g, height_frac, y, seed, theta, crest_row):
    c = mix(SAG_VALLEY, SAG_FLANK, smoothstep(0.0, 0.55, g))
    c = mix(c, SAG_RIDGE, smoothstep(0.6, 1.0, g))
    # Long vertical streaks of an old stem, and a wash of new growth toward the crown.
    streak = noise(theta * 9.0 + seed, y * 0.9, seed)
    c = mix(c, _scale(c, 0.86), smoothstep(0.1, 0.7, streak) * 0.5)
    c = mix(c, SAG_CROWN, smoothstep(0.82, 1.0, height_frac) * 0.6)
    if g > 0.985 and crest_row:
        c = AREOLE  # felted areoles strung down every crest
    return c


def stem(path, radius, ribs, depth, seed, *, base_old=0.0, sides_per_rib=6, dome=0.36):
    """A ribbed stem along `path` (points), radius(s) for s in 0..1 of its length; the end is
    a rounded crown where the ribs close up. Returns the mesh and the crest lines (for spines)."""
    pts = catmull(path, 8)
    tangents, frames = _frames(pts)
    lengths = [0.0]
    for a, b in zip(pts, pts[1:]):
        lengths.append(lengths[-1] + _len(_sub(b, a)))
    total = lengths[-1]
    # Resample at an even step so rows are square-ish; then extend into the crown.
    step = 0.08
    rows_s = [i * step for i in range(int(total / step) + 1)]
    sides = ribs * sides_per_rib
    rows, colors, centers = [], [], []
    crests = [[] for _ in range(ribs)]

    def at(s):
        for i in range(len(lengths) - 1):
            if lengths[i + 1] >= s:
                t = (s - lengths[i]) / max(lengths[i + 1] - lengths[i], 1e-9)
                p = _add(pts[i], _scale(_sub(pts[i + 1], pts[i]), t))
                u = _unit(_add(_scale(frames[i][0], 1 - t), _scale(frames[i + 1][0], t)))
                tan = _unit(_add(_scale(tangents[i], 1 - t), _scale(tangents[i + 1], t)))
                v = _unit((tan[1] * u[2] - tan[2] * u[1], tan[2] * u[0] - tan[0] * u[2], tan[0] * u[1] - tan[1] * u[0]))
                return p, u, v, tan
        return pts[-1], frames[-1][0], frames[-1][1], tangents[-1]

    stations = [(s, 0.0) for s in rows_s]
    # The crown: rows on the end hemisphere, the ribs flattening into it.
    end_s = rows_s[-1]
    for k in range(1, 7):
        a = (math.pi / 2) * k / 7
        stations.append((end_s, a))
    for r_index, (s, crown) in enumerate(stations):
        p, u, v, tan = at(s)
        frac = s / total
        r0 = radius(min(1.0, frac))
        lift = 0.0
        if crown > 0:
            lift = math.sin(crown) * r0 * dome / 0.36 * 0.9
            r0 = r0 * math.cos(crown)
        centre = _add(p, _scale(tan, lift))
        ridge_depth = depth * (1.0 - smoothstep(0.35, 1.2, crown))
        row, crow = [], []
        crest_row = r_index % 2 == 0
        for k in range(sides):
            th = math.tau * k / sides
            f, g = rib(th, ribs, ridge_depth)
            rr = r0 * f * (1.0 + 0.012 * noise(th * 3 + seed, s * 2.0, seed))
            d = _add(_scale(u, math.cos(th)), _scale(v, math.sin(th)))
            q = _add(centre, _scale(d, max(rr, 0.004)))
            row.append(q)
            col = _stem_colour(g, frac if crown == 0 else 1.0, s, seed, th, crest_row and crown < 1.2)
            if base_old and s < base_old:
                col = mix(col, SAG_OLD, smoothstep(base_old, 0.0, s) * 0.85)
            crow.append(rgb(col))
            if k % sides_per_rib == 0 and crown < 1.0 and s > 0.08:
                crests[k // sides_per_rib].append((q, d, tan))
        rows.append(row)
        colors.append(crow)
        centers.append(centre)
    m = PaintMesh().grid(rows, wrap=True, centers=centers, colors=colors)
    tip = _add(centers[-1], _scale(at(end_s)[3], 0.004))
    last = rows[-1]
    m.mark()
    for k in range(sides):
        tri = [tip, last[k], last[(k + 1) % sides]]
        m.polygon(tri, _scale(at(end_s)[3], 1.0), rgb(SAG_CROWN))
    return m, crests


def spines(crests, every, seed):
    """Pale spine clusters on the areoles: two short needles each, one-sided, fanned."""
    m = PaintMesh()
    for line in crests:
        for i, (q, out, tan) in enumerate(line):
            if i % every:
                continue
            side = _unit((out[1] * tan[2] - out[2] * tan[1], out[2] * tan[0] - out[0] * tan[2],
                          out[0] * tan[1] - out[1] * tan[0]))
            base = _add(q, _scale(out, 0.004))
            for j, (a, b) in enumerate(((-0.7, 0.9), (0.7, 0.4))):
                jitter = rand(i * 7 + j, seed) - 0.5
                tip = _add(base, _add(_scale(out, 0.034 + 0.01 * jitter),
                                      _add(_scale(side, 0.018 * a), _scale(tan, 0.016 * (b - 0.6) + 0.006 * jitter))))
                w = _scale(tan if j == 0 else side, 0.0035)
                tri = [_sub(base, w), _add(base, w), tip]
                colour = rgb(mix(SPINE, AREOLE, rand(i + j * 13, seed + 1)))
                m.mark()
                m.polygon(tri, _add(out, _scale(side, 0.3)), colour)
    return m


def saguaro():
    """The trunk and two arms, local to the trunk's foot; returns (stems, spines)."""
    h = SAGUARO_HEIGHT

    def trunk_radius(f):
        y = f * h
        r = 0.335 - 0.03 * smoothstep(0.0, 0.5, y) + 0.04 * smoothstep(0.6, 1.8, y) - 0.035 * smoothstep(2.4, 4.0, y)
        return r

    trunk_path = [(0.0, -0.06, 0.0), (0.01, 1.0, 0.0), (0.03, 2.2, -0.01), (0.035, 3.2, -0.02), (0.025, h - 0.32, -0.02)]
    trunk, crests = stem(trunk_path, trunk_radius, 16, 0.13, 3, base_old=0.55, sides_per_rib=5)
    body = PaintMesh().add(trunk)
    needle = PaintMesh().add(spines(crests, 2, 5))
    # Two arms the way old saguaros grow them: out, then elbowing up. One reaches to the
    # south-west and one to the north-east, so from the yard's camera they open to either
    # side of the trunk like the candelabra in the reference.
    for name, start_y, (dx, dz), reach, rise, r, seed in (
        ("west", 1.72, (-0.72, 0.69), 0.78, 1.45, 0.205, 11),
        ("east", 2.42, (0.74, -0.67), 0.66, 1.05, 0.185, 17),
    ):
        path = [
            (0.0, start_y, 0.0),
            (dx * 0.3, start_y + 0.02, dz * 0.3),
            (dx * (reach - 0.14), start_y + 0.12, dz * (reach - 0.14)),
            (dx * reach, start_y + 0.42, dz * reach),
            (dx * (reach + 0.02), start_y + rise * 0.75, dz * (reach + 0.02)),
            (dx * (reach - 0.01), start_y + rise, dz * (reach - 0.01)),
        ]

        def arm_radius(f, r=r):
            return r * (0.86 + 0.14 * smoothstep(0.0, 0.25, f) - 0.06 * smoothstep(0.6, 1.0, f))
        arm, arm_crests = stem(path, arm_radius, 13, 0.14, seed, sides_per_rib=4, dome=0.3)
        body.add(arm)
        needle.add(spines(arm_crests, 2, seed + 2))
    return body, needle


# --- the plot -------------------------------------------------------------------------------


def plot():
    """Bare soil in a clean-cut square, a little below the paving, with a scatter of gravel."""
    n = 50
    step = 2 * PLOT_HALF / n
    sx, sz = SAGUARO_AT[0], SAGUARO_AT[2]
    rows, colors = [], []
    for j in range(n + 1):
        z = -PLOT_HALF + j * step
        row, crow = [], []
        for i in range(n + 1):
            x = -PLOT_HALF + i * step
            edge = PLOT_HALF - max(abs(x), abs(z))
            f = fbm(x * 2.2, z * 2.2, 41, 4)
            grit = noise(x * 19, z * 19, 43)
            mound = 0.035 * math.exp(-((x - sx) ** 2 + (z - sz) ** 2) / 0.35)
            y = 0.016 + 0.008 * f + 0.004 * grit + mound - 0.006 * smoothstep(0.12, 0.0, edge)
            y = min(y, PAVING - 0.012)
            c = mix(SOIL, SOIL_DARK, smoothstep(-0.25, 0.45, f) * 0.6)
            c = mix(c, SOIL_DRY, smoothstep(0.25, 0.7, noise(x * 3.1 + 5, z * 3.1, 47)) * 0.55)
            # Where the soil has been raked up round the trunk it is darker and damper.
            c = mix(c, SOIL_DARK, smoothstep(0.9, 0.2, math.hypot(x - sx, z - sz)) * 0.5)
            speck = rand(i * 131 + j * 977, 49)
            if speck > 0.94:
                c = mix(c, GRAVEL[int(speck * 97) % 4], 0.8)
            c = mix(c, _scale(c, 0.62), smoothstep(0.16, 0.0, edge))  # in the lip's shadow
            row.append((x, y, z))
            crow.append(rgb(c))
        rows.append(row)
        colors.append(crow)
    m = PaintMesh().grid(rows, outward=(0, 1, 0), colors=colors)
    # The cut faces of the paving: four inner walls from the soil up to the slab's top.
    h = PLOT_HALF
    for a, b, inward in (((-h, -h), (h, -h), (0, 0, 1)), ((h, -h), (h, h), (-1, 0, 0)),
                         ((h, h), (-h, h), (0, 0, -1)), ((-h, h), (-h, -h), (1, 0, 0))):
        m.mark()
        m.polygon([(a[0], 0.0, a[1]), (b[0], 0.0, b[1]), (b[0], PAVING, b[1]), (a[0], PAVING, a[1])],
                  inward, rgb(CUT_EDGE))
    # Gravel: a few hundred small stones lying on the soil.
    for k in range(100):
        x = (rand(k, 61) * 2 - 1) * (h - 0.06)
        z = (rand(k, 62) * 2 - 1) * (h - 0.06)
        if math.hypot(x - sx, z - sz) < 0.42:
            continue
        r = 0.012 + 0.03 * rand(k, 63) ** 2
        y = 0.016 + 0.008 * fbm(x * 2.2, z * 2.2, 41, 4) + r * 0.25
        stone = ellipsoid((x, y, z), (r, r * 0.55, r * (0.7 + 0.5 * rand(k, 64))), rings=3, sides=5,
                          wobble=0.18, seed=k)
        colour = GRAVEL[k % 4]
        m.add(stone, lambda p, nn, c=colour: rgb(_scale(c, 0.8 + 0.25 * max(0.0, nn[1]))))
    return m


# --- the girl -------------------------------------------------------------------------------
# Figure-local: ground at y = 0, +Z the way she faces, +X her left. About 1.22 m tall.

SHOULDER = (0.118, 0.925, -0.012)
HAND = (0.232, 0.668, 0.095)
UPPER, LOWER = 0.19, 0.17
ROPE_AXIS = (0.0, HAND[1] - 0.075, HAND[2])   # through the bottoms of both handles


def _cloth(base, p, seed, amount=0.08):
    f = fbm(p[0] * 14 + seed, p[1] * 14 + p[2] * 9, seed, 3)
    return mix(base, DRESS_SHADE, smoothstep(-0.2, 0.7, f) * amount * 4)


def _ao(colour_fn, low=0.62):
    def paint(p, n, ao):
        c = colour_fn(p, n)
        k = low + (1.0 - low) * ao
        return rgb(tuple(min(255.0, v * k) for v in c))
    return paint


def legs():
    """White tights and white shoes: standing on the right foot, the left knee lifted."""
    stand = (-0.056, 0.64, 0.0), (-0.06, 0.34, 0.014), (-0.062, 0.078, -0.004)
    lift = (0.056, 0.64, 0.0), (0.066, 0.49, 0.15), (0.068, 0.255, 0.075)
    prims = []
    for hip, knee, ankle in (stand, lift):
        prims += [Cone(hip, knee, 0.05, 0.038, k=0.02), Cone(knee, ankle, 0.037, 0.028, k=0.02)]
    prims.append(Ell((0, 0.64, 0), (0.09, 0.05, 0.065), k=0.03))
    shoes = [Ell((-0.062, 0.038, 0.03), (0.038, 0.038, 0.082), k=0.02),
             Ell((0.068, 0.225, 0.108), (0.036, 0.036, 0.078), pitch=-48.0, k=0.02)]
    prims += shoes
    field = Field(prims, floor=0.0)

    def colour(p, n):
        x, y, z = p
        in_shoe = (y < 0.085 and x < 0) or (x > 0 and y < 0.27 and z > 0.06)
        if in_shoe:
            c = SHOE
            low = y < 0.012 if x < 0 else _dot(_sub(p, (0.068, 0.225, 0.108)), (0, 0.743, -0.669)) < -0.028
            if low:
                c = SOLE
            if abs(y - (0.072 if x < 0 else 0.27)) < 0.006:
                c = _scale(SHOE, 0.86)  # the strap of a Mary Jane
            return c
        return mix(TIGHTS, _scale(TIGHTS, 0.9), smoothstep(0.0, 0.6, noise(x * 40, y * 30, 3)) * 0.4)
    return surface(field, 0.0135, _ao(colour))


def bodice():
    """The dress above the waist: a fitted bodice over a smocked band, a round collar."""
    prims = [
        Ell((0, 0.735, 0.0), (0.094, 0.06, 0.074)),
        Ell((0, 0.83, 0.006), (0.104, 0.08, 0.08)),
        Ell((0, 0.915, -0.006), (0.118, 0.048, 0.07)),
        Ell((-0.112, 0.918, -0.008), (0.048, 0.042, 0.05), k=0.03),
        Ell((0.112, 0.918, -0.008), (0.048, 0.042, 0.05), k=0.03),
        Cone((0, 0.94, -0.004), (0, 1.02, 0.004), 0.033, 0.029, k=0.02),
        Ell((0, 0.948, 0.0), (0.072, 0.014, 0.058), k=0.02),
    ]
    field = Field(prims)

    def colour(p, n):
        x, y, z = p
        if y > 0.962:
            return SKIN  # the neck
        c = _cloth(DRESS, p, 5)
        if 0.693 < y < 0.772:
            # Smocking: fine gathered rows across the waist, stitched in a grey thread.
            if abs(((y - 0.693) % 0.0125) - 0.006) < 0.0018:
                c = SMOCK
            elif abs((math.atan2(x, z) * 30 / math.pi) % 1.0 - 0.5) < 0.12:
                c = _scale(c, 0.9)
        if 0.94 < y < 0.962:
            c = _scale(DRESS, 0.94)  # the collar's edge
        return c
    return surface(field, 0.0118, _ao(colour, 0.68))


def skirt():
    """A full skirt from the waist to above the knee, falling in soft folds; the front lifted
    by the raised knee."""
    sides, rows_n = 54, 16
    rows, colors, centers = [], [], []
    for j in range(rows_n + 1):
        t = j / rows_n
        row, crow = [], []
        for k in range(sides):
            th = math.tau * k / sides
            sx, sz = math.sin(th), math.cos(th)   # th = 0 is her front (+Z)
            hem = 0.425 + 0.045 * max(0.0, sz) ** 2 + 0.03 * max(0.0, sz * 0.7 + sx * 0.7) ** 3
            y = 0.755 + (hem - 0.755) * t
            flare = 0.098 + (0.205 - 0.098) * smoothstep(0.0, 1.0, t ** 0.8)
            fold = 1.0 + (0.07 * math.sin(9 * th + 0.6) + 0.03 * math.sin(17 * th)) * smoothstep(0.1, 1.0, t)
            knee = 1.0 + 0.16 * smoothstep(0.4, 1.0, t) * max(0.0, sz * 0.8 + sx * 0.6) ** 4
            r = flare * fold * knee
            row.append((sx * r, y, sz * r * 0.92))
            shade = 0.5 + 0.5 * math.sin(9 * th + 0.6)
            c = mix(_scale(DRESS, 0.9), DRESS, shade ** 0.7)
            if t > 0.93:
                c = _scale(c, 0.95)  # the hem's turn
            crow.append(rgb(c))
        rows.append(row)
        colors.append(crow)
        centers.append((0.0, rows[-1][0][1], 0.0))
    m = PaintMesh().grid(rows, wrap=True, centers=centers, colors=colors)
    # The inside of the skirt, a shade darker, for the glimpse under the lifted hem.
    inner = [[(x * 0.985, y, z * 0.985) for x, y, z in row] for row in rows]
    m.grid(inner, wrap=True, centers=centers, colors=[[rgb(_scale(DRESS, 0.8))] * sides for _ in inner], inward=True)
    return m


def arms():
    """Long white sleeves to the wrists, small hands closed on the rope's two handles."""
    m = PaintMesh()
    for s in (-1, 1):
        sh = (s * SHOULDER[0], SHOULDER[1], SHOULDER[2])
        hand = (s * HAND[0], HAND[1], HAND[2])
        wrist = _add(hand, (0.0, 0.032, -0.012))
        elbow = ik(sh, wrist, UPPER, LOWER, (s * 0.25, -0.2, -1.0))
        prims = [
            Cone(sh, elbow, 0.036, 0.03, k=0.02),
            Cone(elbow, wrist, 0.03, 0.026, k=0.02),
            Ell(_add(wrist, (0.0, -0.004, 0.004)), (0.03, 0.022, 0.03), k=0.012),  # the cuff
            Ell(_add(hand, (s * 0.004, 0.0, 0.004)), (0.024, 0.032, 0.026), k=0.015),
        ]
        field = Field(prims)
        axis = _unit(_sub(wrist, elbow))

        def colour(p, n, wrist=wrist, axis=axis):
            along = _dot(_sub(p, wrist), axis)
            if along > 0.008:
                return mix(SKIN, SKIN_DEEP, 0.3 * noise(p[0] * 80, p[1] * 80, 7))
            if along > -0.018:
                return _scale(DRESS, 0.95)
            return _cloth(DRESS, p, 9)
        m.add(surface(field, 0.0098, _ao(colour, 0.66)))
        # The handle in her fist, a turned wooden grip, its end showing below the hand.
        top = _add(hand, (0.0, 0.045, 0.0))
        bottom = _add(hand, (s * 0.01, -0.075, 0.0))
        grip = sweep([top, bottom], [0.0125, 0.011], sides=10, per=1)
        m.add(grip, lambda p, nn: rgb(mix(HANDLE, _scale(HANDLE, 0.75), 0.4 * max(0.0, -nn[1]))))
    return m


def head():
    """A child's head from behind: fair hair drawn back into a bun, a glimpse of cheek."""
    bun = (0.0, 1.19, -0.104)
    prims = [
        Ell((0, 1.112, -0.004), (0.086, 0.096, 0.092)),
        Ell((0, 1.07, 0.03), (0.068, 0.064, 0.064), k=0.04),
        Ell((-0.085, 1.1, 0.002), (0.013, 0.023, 0.014), k=0.01),
        Ell((0.085, 1.1, 0.002), (0.013, 0.023, 0.014), k=0.01),
        Ell((0, 1.132, -0.012), (0.091, 0.098, 0.097), k=0.03),        # the hair's volume
        Ell(bun, (0.054, 0.05, 0.046), pitch=35.0, k=0.022),
        Cone((0, 1.0, 0.0), (0, 1.05, 0.01), 0.03, 0.032, k=0.02),
    ]
    field = Field(prims)

    def colour(p, n):
        x, y, z = p
        face = z > 0.035 and y < 1.152 and abs(x) < 0.074
        ear = abs(abs(x) - 0.085) < 0.016 and abs(y - 1.1) < 0.026 and z > -0.02
        if face or ear or y < 1.03:
            c = mix(SKIN, SKIN_DEEP, 0.25 * smoothstep(-0.2, 0.7, fbm(x * 40, y * 40, 21, 2)))
            if face:
                for ex in (-0.03, 0.03):
                    if abs(x - ex) < 0.009 and abs(y - 1.112) < 0.006:
                        return (60, 52, 50)
                if abs(x) < 0.016 and abs(y - 1.058) < 0.0035:
                    return (200, 120, 116)
            return c
        # Hair: strands drawn from the hairline up and back into the bun, then wound round it.
        to_bun = _sub(p, bun)
        d = _len(to_bun)
        if d < 0.056:
            ang = math.atan2(to_bun[0], to_bun[2]) + d * 40.0
        else:
            ang = math.atan2(x, max(0.02, 1.2 - y)) * 3.0 + z * 4.0
        strand = noise(ang * 9.0, d * 6.0, 23)
        c = mix(HAIR_DEEP, HAIR, smoothstep(0.15, 0.75, strand))
        c = mix(c, HAIR_LIGHT, smoothstep(0.4, 1.0, n[1] * 0.6 + n[0] * -0.3) * 0.6)
        if abs(d - 0.05) < 0.005 and to_bun[2] > 0.012:
            c = _scale(HAIR_DEEP, 0.8)  # the tie where the bun is pinned
        return c
    return surface(field, 0.0092, _ao(colour, 0.7))


def rope():
    """The rope, rope-local: its axis is X, through the handle ends; the loop hangs at -Y."""
    hx = HAND[0] + 0.01
    reach = ROPE_AXIS[1] + 0.012   # from the axis to just under her feet at the top of a hop
    path = []
    for i in range(41):
        u = i / 40
        bow = math.sin(math.pi * u)
        x = (-hx + 2 * hx * u) * (1.0 + 0.35 * bow)
        d = 0.0 + reach * bow ** 0.62
        path.append((x, -d, 0.0))
    m = PaintMesh()
    m.add(sweep(path, [0.0075] * len(path), sides=6, per=1),
          lambda p, nn: rgb(mix(ROPE, _scale(ROPE, 0.82), 0.5 * max(0.0, -nn[1]))))
    return m


# --- scene ---------------------------------------------------------------------------------


GLOW_SHADER = f"{RES}/shaders/cactus_glow.gdshader"
MATERIALS = {
    # The daylight on the saguaro and the girl. `glow` scales the shader's own key light.
    "cactus_glow": f'''[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="{GLOW_SHADER}" id="1_glow"]

[resource]
resource_name = "cactus_glow"
shader = ExtResource("1_glow")
shader_parameter/glow = 0.95
shader_parameter/roughness = 0.62
shader_parameter/sheen = 0.35
''',
    "girl_glow": f'''[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="{GLOW_SHADER}" id="1_glow"]

[resource]
resource_name = "girl_glow"
shader = ExtResource("1_glow")
shader_parameter/glow = 0.8
shader_parameter/roughness = 0.9
shader_parameter/sheen = 0.25
''',
    # The soil is lit by the dusk like everything else round it.
    "cactus_soil": '''[gd_resource type="StandardMaterial3D" format=3]

[resource]
resource_name = "cactus_soil"
vertex_color_use_as_albedo = true
vertex_color_is_srgb = true
diffuse_mode = 3
specular_mode = 2
roughness = 1.0
''',
}


class Scene:
    def __init__(self):
        self.ext: list[str] = []
        self.subs: list[str] = []
        self.nodes: list[str] = []
        self.files: dict[str, str] = {}
        self._n = 0

    def ext_id(self, kind, path, rid):
        line = f'[ext_resource type="{kind}" path="{path}" id="{rid}"]'
        if line not in self.ext:
            self.ext.append(line)
        return rid

    def mesh(self, name, build):
        file_name = f"{name}.tres"
        mesh = build()
        self.files[file_name] = f'[gd_resource type="ArrayMesh" format=3]\n\n[resource]\nresource_name = "{name}"\n_surfaces = {mesh.surface()}\n'
        return self.ext_id("ArrayMesh", f"{RES}/{MESH_DIR}/{file_name}", f"mesh_{name}")

    def material(self, name):
        kind = "StandardMaterial3D" if name == "cactus_soil" else "ShaderMaterial"
        return self.ext_id(kind, f"{RES}/materials/{name}.tres", f"mat_{name}")

    def sub(self, kind, **props):
        self._n += 1
        rid = f"{kind}_{self._n}"
        body = "".join(f"{k} = {v}\n" for k, v in props.items())
        self.subs.append(f'[sub_resource type="{kind}" id="{rid}"]\n{body}')
        return rid

    def node(self, name, parent, kind=None, *, extra="", **props):
        head = f'[node name="{name}"'
        if kind:
            head += f' type="{kind}"'
        if parent is not None:
            head += f' parent="{parent}"'
        head += extra + "]"
        body = "".join(f"{k} = {v}\n" for k, v in props.items())
        self.nodes.append(head + "\n" + body)

    def text(self):
        steps = 1 + len(self.ext) + len(self.subs)
        return "\n".join([f"[gd_scene load_steps={steps} format=3]", "", *self.ext, "", *self.subs, *self.nodes])


def vec3(v):
    return "Vector3(" + ", ".join(f"{c:.4g}" for c in v) + ")"


def mesh_node(s, name, parent, rid, mat, *, pos=(0, 0, 0), rot=None, shadow=True, aabb=None):
    props = {"position": vec3(pos)}
    if rot:
        props["rotation_degrees"] = vec3(rot)
    props["mesh"] = f'ExtResource("{rid}")'
    props["material_override"] = f'ExtResource("{s.material(mat)}")'
    if not shadow:
        props["cast_shadow"] = 0
    if aabb:
        props["custom_aabb"] = "AABB(" + ", ".join(f"{v:g}" for v in aabb) + ")"
    s.node(name, parent, "MeshInstance3D", **props)


def skip_keys():
    """One skip: the rope turns once; she is up while it passes under her feet."""
    times = [i * SKIP_PERIOD / 12 for i in range(13)]
    hop, turn = [], []
    for t in times:
        phase = t / SKIP_PERIOD
        # Highest at phase 0 (rope under the feet), landed by a third of the turn.
        lift = HOP * max(0.0, math.cos(math.pi * min(phase, 1.0 - phase) * 2.6)) ** 1.5
        hop.append((t, (0.0, lift, 0.0)))
        turn.append((t, (360.0 * phase, 0.0, 0.0)))
    return hop, turn


def animation(s, parent, tracks):
    props = {"resource_name": '"Skip"', "length": f"{SKIP_PERIOD:g}", "loop_mode": 1}
    for i, ((path, prop), keys) in enumerate(tracks.items()):
        slot = f"tracks/{i}/"
        props[slot + "type"] = '"value"'
        props[slot + "imported"] = "false"
        props[slot + "enabled"] = "true"
        props[slot + "path"] = f'NodePath("{path}:{prop}")'
        props[slot + "interp"] = 1
        props[slot + "loop_wrap"] = "true"
        times = ", ".join(f"{t:.4g}" for t, _ in keys)
        transitions = ", ".join("1" for _ in keys)
        values = ", ".join(vec3(v) for _, v in keys)
        props[slot + "keys"] = (f'{{"times": PackedFloat32Array({times}), "transitions": '
                                f'PackedFloat32Array({transitions}), "update": 0, "values": [{values}]}}')
    anim = s.sub("Animation", **props)
    library = s.sub("AnimationLibrary", _data=f'{{&"Skip": SubResource("{anim}")}}')
    s.node("Motion", parent, "AnimationPlayer", autoplay='"Skip"', libraries=f'{{&"": SubResource("{library}")}}')


def build(view=False):
    s = Scene()
    s.node("CactusPlot", None, "Node3D")
    mesh_node(s, "Plot", ".", s.mesh("cactus_plot_soil", plot), "cactus_soil", shadow=False)

    stems, needles = saguaro()
    sag_pos = (SAGUARO_AT[0], SAGUARO_BOX[1] / 2, SAGUARO_AT[2])
    if view:
        s.node("Saguaro", ".", "Node3D", position=vec3(sag_pos))
    else:
        box = s.sub("BoxShape3D", size=vec3(SAGUARO_BOX))
        s.node("Saguaro", ".", "StaticBody3D", extra=' groups=["camera_occluder"]', position=vec3(sag_pos))
        s.node("CollisionShape3D", "Saguaro", "CollisionShape3D", shape=f'SubResource("{box}")')
    foot = (0.0, -SAGUARO_BOX[1] / 2 + 0.02, 0.0)
    mesh_node(s, "Stem", "Saguaro", s.mesh("saguaro_stem", lambda: stems), "cactus_glow", pos=foot)
    mesh_node(s, "Spines", "Saguaro", s.mesh("saguaro_spines", lambda: needles), "cactus_glow", pos=foot, shadow=False)

    if not view:
        # Round 21: she is solid. A box round her and the sweep of her rope, so the player
        # walks round her instead of through her (pinned in playground_art_slice_test.gd).
        box = s.sub("BoxShape3D", size=vec3(GIRL_BOX))
        s.node("GirlBody", ".", "StaticBody3D",
               position=vec3((GIRL_AT[0], GIRL_AT[1] + GIRL_BOX[1] / 2, GIRL_AT[2])))
        s.node("CollisionShape3D", "GirlBody", "CollisionShape3D", shape=f'SubResource("{box}")')
    s.node("Girl", ".", "Node3D", position=vec3(GIRL_AT), rotation_degrees=vec3((0, GIRL_YAW, 0)))
    s.node("Figure", "Girl", "Node3D")
    fig = "Girl/Figure"
    for name, build_fn in (("Legs", legs), ("Bodice", bodice), ("Skirt", skirt), ("Arms", arms), ("Head", head)):
        mesh_node(s, name, fig, s.mesh(f"girl_{name.lower()}", build_fn), "girl_glow")
    r = ROPE_AXIS[1] + 0.05
    mesh_node(s, "Rope", fig, s.mesh("girl_rope", rope), "girl_glow", pos=ROPE_AXIS,
              aabb=(-0.4, -r, -r, 0.8, 2 * r, 2 * r))
    hop, turn = skip_keys()
    animation(s, "Girl", {("Figure", "position"): hop, ("Figure/Rope", "rotation_degrees"): turn})
    return s


def main():
    s = build()
    out_dir = ART / MESH_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    for stale in out_dir.glob("*.tres"):
        if stale.name not in s.files:
            stale.unlink()
    total = 0
    for name, text in s.files.items():
        (out_dir / name).write_text(text)
        total += len(text)
        print(f"{MESH_DIR}/{name:28s} {len(text) / 1024:8.1f} KiB")
    for name, text in MATERIALS.items():
        (ART / "materials" / f"{name}.tres").write_text(text)
    SCENE.write_text(s.text())
    VIEW_SCENE.write_text(build(view=True).text())
    print(f"wrote {SCENE.relative_to(ROOT)} and {len(s.files)} meshes ({total / 1024:.0f} KiB)")


if __name__ == "__main__":
    main()
