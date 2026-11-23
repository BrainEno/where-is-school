"""Shaped dressing for the stable yard behind 01, round 18 (docs/EXAM_DREAM_ART.md).

The owner found the yard too dirty, too crowded and a little cheap. The boxes that stood in
for a hen house, hay, quilts, grain and the stall doors become modelled pieces with
boards, twine, folds and raked ridges, painted per vertex with grain and wear and lit by
`assets/shaders/school/stable_coat.gdshader`. Pure Python, written by `dream_stable.py`
as text ArrayMeshes beside the animals.
"""
from __future__ import annotations

import math

from stable_meshes import PaintMesh, mix, rgb, sweep  # also puts the site mesh kit on the path
from site_mesh import box, cylinder, euler, fbm, noise, rand, smoothstep  # noqa: E402

TIMBER = (156, 128, 98)
TIMBER_DARK = (116, 92, 70)
TIMBER_GREY = (168, 158, 142)
TIN = (128, 122, 116)
RUST = (138, 90, 58)
WIRE = (118, 118, 112)
IRON = (54, 52, 50)
STRAW = (206, 176, 100)
STRAW_PALE = (226, 204, 140)
STRAW_DARK = (160, 126, 70)
TWINE = (190, 150, 80)
GRAIN = (222, 176, 84)
GRAIN_DEEP = (188, 140, 60)
TARP = (52, 84, 140)


def _wood(base, seed, along=1):
    """Board colour: long grain streaks, knots, a weathered top edge."""
    def paint(p, n, *_):
        x, y, z = p
        u = (y, x, z)[along]
        streak = fbm(u * 3 + seed, (x + z) * 40 + seed, seed, 3)
        c = mix(base, TIMBER_DARK, smoothstep(-.1, .5, streak) * .45)
        c = mix(c, TIMBER_GREY, smoothstep(.2, .7, fbm(x * 6 + 3, y * 6 + z * 6, seed + 5, 2)) * .4)
        if n[1] < -.5:
            c = mix(c, TIMBER_DARK, .4)
        return rgb(c)
    return paint


def board(m, size, center, seed, base=TIMBER, along=1, bevel=.006):
    tone = mix(base, TIMBER_GREY, rand(seed, 3) * .35)
    m.add(box(size, center, bevel), _wood(tone, seed, along))


def _flat_board(m, size, center, seed, base=TIMBER, along=1):
    board(m, size, center, seed, base, along, bevel=0)


# --- the hen house ----------------------------------------------------------------------
# Origin on the ground at the centre of the old coop's footprint (2.2 x 1.6 m); +Z faces the
# yard. The house stands on legs at the west end, the wire run fills the rest.

def coop():
    m = PaintMesh()
    hx0, hx1, hz0, hz1 = -1.08, -.12, -.78, .32
    floor, eave, ridge = .42, 1.0, 1.28
    seed = 300
    # Legs, floor, and vertical boards all round.
    for i, (x, z) in enumerate(((hx0 + .05, hz0 + .05), (hx1 - .05, hz0 + .05), (hx0 + .05, hz1 - .05),
                                (hx1 - .05, hz1 - .05))):
        _flat_board(m, (.07, floor, .07), (x, floor / 2, z), seed + i, TIMBER_DARK)
    _flat_board(m, (hx1 - hx0, .04, hz1 - hz0), ((hx0 + hx1) / 2, floor + .02, (hz0 + hz1) / 2), seed + 9, along=0)
    width = .12
    for side, ((lo, hi), fixed, axis) in enumerate((((hx0, hx1), hz1, 0), ((hx0, hx1), hz0, 0),
                                                   ((hz0, hz1), hx0, 2), ((hz0, hz1), hx1, 2))):
        count = int(round((hi - lo) / width))
        for k in range(count):
            u = lo + (k + .5) * (hi - lo) / count
            top = eave
            if axis == 2:
                # Gable ends rise to the ridge.
                mid = (hz0 + hz1) / 2
                top = eave + (ridge - eave) * (1 - abs(u - mid) / ((hz1 - hz0) / 2))
            h = top - floor
            if side == 0 and -.78 < u < -.5:
                h = top - (floor + .36)  # the pop hole
                cy = floor + .36 + h / 2
            else:
                cy = floor + h / 2
            size = ((hi - lo) / count - .008, h, .025) if axis == 0 else (.025, h, (hi - lo) / count - .008)
            centre = (u, cy, fixed) if axis == 0 else (fixed, cy, u)
            _flat_board(m, size, centre, seed + 20 + side * 30 + k)
    # Corner battens and a rail under the eaves.
    for x in (hx0, hx1):
        for z in (hz0, hz1):
            _flat_board(m, (.05, eave - floor, .05), (x, (eave + floor) / 2, z), seed + 90, TIMBER_DARK)
    _flat_board(m, (hx1 - hx0 + .06, .05, .04), ((hx0 + hx1) / 2, eave - .02, hz1 + .02), seed + 91, TIMBER_DARK, along=0)
    # A nesting box on the east wall with its own lid.
    _flat_board(m, (.32, .3, .5), (hx1 + .16, floor + .3, -.25), seed + 92)
    m.add(box((.38, .03, .56), (hx1 + .18, floor + .47, -.25), .006), rgb(TIN))
    # The ramp from the pop hole down into the run, with cleats.
    ramp = PaintMesh()
    _flat_board(ramp, (.22, .02, .7), (0, 0, 0), seed + 93, along=2)
    for k in range(5):
        _flat_board(ramp, (.2, .02, .02), (0, .02, -.28 + k * .14), seed + 94 + k, TIMBER_DARK)
    m.add(ramp, None, rotation=_rx(34), offset=(-.64, floor / 2 + .02, hz1 + .29))
    # Corrugated tin roof, two pitches, overhanging; a dark underside.
    for sgn in (-1, 1):
        rows, under = [], []
        for r in range(9):
            t = r / 8
            z = (hz0 + hz1) / 2 + sgn * t * ((hz1 - hz0) / 2 + .14)
            y = ridge + .03 - t * (ridge - eave + .06)
            row, urow = [], []
            for c in range(41):
                x = hx0 - .14 + c / 40 * (hx1 - hx0 + .28)
                ripple = .012 * math.sin(c * math.pi / 2)
                row.append((x, y + ripple + .012, z))
                urow.append((x, y - .004, z))
            rows.append(row)
            under.append(urow)
        top = PaintMesh().grid(rows, outward=(0, 1, 0))
        top.colors = [rgb(mix(TIN, RUST, smoothstep(.1, .6, fbm(p[0] * 5, p[2] * 5 + sgn, 8, 3)) * .6))
                      for p in top.points]
        m.add(top)
        bottom = PaintMesh().grid(under, outward=(0, -1, 0))
        bottom.colors = [rgb(TIMBER_DARK) for _ in bottom.points]
        m.add(bottom)
    _flat_board(m, (hx1 - hx0 + .3, .05, .05), ((hx0 + hx1) / 2, ridge + .05, (hz0 + hz1) / 2), seed + 99, TIMBER_DARK,
          along=0)
    # The run: a timber frame and wire mesh on three sides and the top.
    rx0, rx1, rz0, rz1, rh = -.12, 1.08, -.78, .78, 1.0
    posts = ((rx1, rz0), (rx1, rz1), (rx0, rz1), ((rx0 + rx1) / 2, rz1), (rx1, 0.0))
    for i, (x, z) in enumerate(posts):
        _flat_board(m, (.06, rh, .06), (x, rh / 2, z), seed + 110 + i, TIMBER_DARK)
    for y in (.04, rh - .03):
        _flat_board(m, (rx1 - rx0, .05, .05), ((rx0 + rx1) / 2, y, rz1), seed + 120, TIMBER_DARK, along=0)
        _flat_board(m, (.05, .05, rz1 - rz0), (rx1, y, (rz0 + rz1) / 2), seed + 121, TIMBER_DARK, along=2)
    _flat_board(m, (rx1 - rx0, .05, .05), ((rx0 + rx1) / 2, rh - .03, rz0), seed + 122, TIMBER_DARK, along=0)
    wire = PaintMesh()
    step = .11
    for k in range(int((rx1 - rx0) / step) + 1):
        x = rx0 + k * step
        wire.add(cylinder(.0035, rh - .06, 4, center=(x, rh / 2, rz1 + .03), smooth=False), rgb(WIRE))
        wire.add(cylinder(.0035, rz1 - rz0, 4, center=(x, rh - .005, (rz0 + rz1) / 2), axis="z", smooth=False),
                 rgb(WIRE))
    for k in range(int((rz1 - rz0) / step) + 1):
        z = rz0 + k * step
        wire.add(cylinder(.0035, rh - .06, 4, center=(rx1 + .03, rh / 2, z), smooth=False), rgb(WIRE))
        wire.add(cylinder(.0035, rx1 - rx0, 4, center=((rx0 + rx1) / 2, rh - .005, z), axis="x", smooth=False),
                 rgb(WIRE))
    for k in range(1, int((rh - .06) / step) + 1):
        y = .04 + k * step
        wire.add(cylinder(.0035, rx1 - rx0, 4, center=((rx0 + rx1) / 2, y, rz1 + .03), axis="x", smooth=False),
                 rgb(WIRE))
        wire.add(cylinder(.0035, rz1 - rz0, 4, center=(rx1 + .03, y, (rz0 + rz1) / 2), axis="z", smooth=False),
                 rgb(WIRE))
    m.add(wire)
    # A little straw on the run floor, a water dish and a feeder.
    m.add(straw_patch(((rx0 + .05, rx1 - .05), (rz0 + .05, rz1 - .05)), 70, 401, .004))
    m.add(cylinder(.13, .05, 18, top=.15, center=(.75, .025, -.45)), rgb((96, 98, 100)))
    m.add(cylinder(.12, .01, 18, center=(.75, .045, -.45)), rgb((86, 104, 112)))
    m.add(cylinder(.09, .3, 14, center=(.25, .15, -.55)), rgb((150, 60, 48)))
    m.add(cylinder(.16, .03, 16, center=(.25, .015, -.55)), rgb((150, 60, 48)))
    return m


def _rx(deg):
    a = math.radians(deg)
    return ((1, 0, 0), (0, math.cos(a), -math.sin(a)), (0, math.sin(a), math.cos(a)))


# --- straw, bales ---------------------------------------------------------------------

def strand(length_, width):
    """One flattened straw along +Z, both faces (as stable_meshes.strand)."""
    h, w = length_ / 2, width / 2
    m = PaintMesh()
    for side in (-1, 1):
        ridge, edge = (0, w * .45, -h), (side * w, 0, -h)
        ridge2, edge2 = (0, w * .45, h), (side * w, 0, h)
        quad = [ridge, ridge2, edge2, edge] if side > 0 else [ridge, edge, edge2, ridge2]
        m.polygon(quad, (side * .4, 1, 0))
        m.polygon(list(reversed(quad)), (-side * .4, -1, 0))
    return m


def straw_patch(area, count, seed, height=.01):
    """A thin, tidy scatter of straw (a swept floor, not a midden)."""
    (x0, x1), (z0, z1) = area
    m = PaintMesh()
    for i in range(count):
        x = x0 + (x1 - x0) * rand(i, seed)
        z = z0 + (z1 - z0) * rand(i, seed + 1)
        y = .004 + height * rand(i, seed + 2)
        c = mix(STRAW, STRAW_PALE, rand(i, seed + 4)) if rand(i, seed + 7) > .25 else STRAW_DARK
        m.add(strand(.08 + .14 * rand(i, seed + 3), .006), rgb(c),
              rotation=euler((rand(i, seed + 6) * 16 - 8, rand(i, seed + 8) * 180, 0)), offset=(x, y, z))
    return m


def hay_bale(seed):
    """A small square bale, 0.9 x 0.45 x 0.5 m, rounded, with two bands of twine."""
    m = PaintMesh()
    sx, sy, sz = .9, .45, .5

    def straw(p, n, *_):
        x, y, z = p
        streak = noise(x * 6 + seed, (y + z) * 60, seed) * .5 + noise(x * 40, (y - z) * 90, seed + 1) * .5
        c = mix(STRAW, STRAW_PALE, smoothstep(-.2, .6, streak))
        c = mix(c, STRAW_DARK, smoothstep(.3, .8, -streak) * .6)
        if abs(x) > sx / 2 - .02:
            c = mix(c, STRAW_DARK, .25 + .2 * noise(y * 50, z * 50, seed + 2))  # cut ends
        return rgb(c)

    rows, centers = [], []
    for j in range(7):
        t = j / 6
        y = sy * t
        inset = .035 * (1 - math.sin(t * math.pi)) ** 2
        ring = []
        for k in range(24):
            a = math.tau * k / 24
            c, s = math.cos(a), math.sin(a)
            px = math.copysign(abs(c) ** .25, c) * (sx / 2 - inset)
            pz = math.copysign(abs(s) ** .25, s) * (sz / 2 - inset)
            ring.append((px, y, pz))
        rows.append(ring)
        centers.append((0, y, 0))
    body = PaintMesh().grid(rows, wrap=True, centers=centers)
    body.polygon(rows[0], (0, -1, 0))
    body.polygon(rows[-1], (0, 1, 0))
    m.add(body, straw)
    for bx in (-.22, .22):
        loop = [(bx, .01, -sz / 2 - .004), (bx, sy + .004, -sz / 2 - .004), (bx, sy + .004, sz / 2 + .004),
                (bx, .01, sz / 2 + .004)]
        for a, b in zip(loop, loop[1:]):
            m.add(sweep([a, b], (.006, .006), sides=5, per=1), rgb(TWINE))
    # A few loose ends standing proud of the faces.
    for i in range(14):
        face = i % 2 * 2 - 1
        px, py = (rand(i, seed + 9) - .5) * sx * .9, .05 + rand(i, seed + 10) * (sy - .1)
        m.add(strand(.06 + .05 * rand(i, seed + 11), .005), rgb(STRAW_PALE),
              rotation=euler((rand(i, seed + 12) * 40 - 20, 90 * rand(i, seed + 13), 0)),
              offset=(px, py, face * (sz / 2 + .01)))
    return m


# --- quilts on the line -----------------------------------------------------------------

QUILTS = (
    {"base": (176, 52, 60), "motif": (238, 214, 200), "edge": (62, 98, 74), "pattern": "peony"},
    {"base": (40, 116, 118), "motif": (232, 190, 80), "edge": (176, 52, 60), "pattern": "check"},
    {"base": (226, 150, 158), "motif": (70, 118, 78), "edge": (236, 222, 200), "pattern": "leaf"},
)


def quilt(look, width=1.5, drop=1.66, seed=0):
    """A quilt folded over the wire: soft vertical folds, a sag, a printed motif, a border."""
    m = PaintMesh()

    def at(u, v, side):
        x = (u - .5) * width
        sag = .04 * math.sin(u * math.pi)
        fold = .035 * math.sin(u * math.tau * 3.2 + seed) * smoothstep(0, .35, v)
        y = -v * drop - sag + .01 * math.sin(u * 17) * v
        z = fold + side * .012 + .03 * v * math.sin(u * 5 + seed)
        return (x, y, z)

    def colour(u, v):
        x, y = u * width, v * drop
        c = look["base"]
        if look["pattern"] == "check":
            if (int(x / .25) + int(y / .25)) % 2:
                c = mix(c, look["motif"], .85)
        else:
            cx, cy = (x % .5) - .25, (y % .55) - .27
            r = math.hypot(cx, cy)
            petals = .1 + .03 * math.cos(math.atan2(cy, cx) * (5 if look["pattern"] == "peony" else 2))
            if r < petals:
                c = look["motif"]
            if r < .03:
                c = look["edge"]
        if u < .04 or u > .96 or v > .965:
            c = look["edge"]
        shade = .92 + .08 * noise(x * 20, y * 20, seed)
        return rgb(tuple(v_ * shade for v_ in c))

    for side, cols, rws in ((1, 48, 34), (-1, 24, 16)):
        rows = [[at(c / cols, r / rws, side) for c in range(cols + 1)] for r in range(rws + 1)]
        g = PaintMesh().grid(rows, outward=(0, 0, side))
        g.colors = [colour(c / cols, r / rws) for r in range(rws + 1) for c in range(cols + 1)]
        m.add(g)
    # The fold over the wire on top.
    roll = sweep([(-width / 2, 0, 0), (width / 2, 0, 0)], (.022, .022), sides=10, per=1)
    roll.colors = [rgb(look["edge"]) for _ in roll.points]
    m.add(roll)
    # Two wooden pegs.
    for px in (-width / 3, width / 3):
        m.add(box((.025, .08, .03), (px, -.01, 0), .004), rgb(TIMBER))
    return m


# --- grain drying on a tarp -----------------------------------------------------------

def grain_mat(size, seed):
    """A tarp with turned-up edges and grain raked into soft ridges."""
    w, d = size
    m = PaintMesh()
    nx, nz = int(w / .05) + 1, int(d / .05) + 1
    rows = []
    for i in range(nz):
        z = -d / 2 + i * d / (nz - 1)
        row = []
        for k in range(nx):
            x = -w / 2 + k * w / (nx - 1)
            edge = min(x + w / 2, w / 2 - x, z + d / 2, d / 2 - z)
            body = smoothstep(0, .2, edge)
            ridge = .5 + .5 * math.cos(z / .22 * math.tau + .3 * noise(x * 3, z * 3, seed))
            y = .012 + body * (.022 + .016 * ridge + .006 * noise(x * 14, z * 14, seed + 1))
            row.append((x, y, z))
        rows.append(row)
    g = PaintMesh().grid(rows, outward=(0, 1, 0))
    cols = []
    for row in rows:
        for x, y, z in row:
            t = smoothstep(.02, .05, y)
            cols.append(rgb(mix(GRAIN_DEEP, GRAIN, t + .15 * noise(x * 30, z * 30, seed + 2))))
    g.colors = cols
    m.add(g)
    # The tarp under it, a hand's width bigger, its edge lifted on a few stones.
    tw, td = w + .2, d + .2
    tarp = []
    for i in range(9):
        z = -td / 2 + i * td / 8
        tarp.append([(-tw / 2 + k * tw / 12, .004 + .02 * smoothstep(.06, 0, min(-tw / 2 + k * tw / 12 + tw / 2,
                                                                                tw / 2 - (-tw / 2 + k * tw / 12),
                                                                                z + td / 2, td / 2 - z)),
                      z) for k in range(13)])
    t = PaintMesh().grid(tarp, outward=(0, 1, 0))
    t.colors = [rgb(mix(TARP, (90, 110, 150), .2 * noise(p[0] * 4, p[2] * 4, seed + 3))) for p in t.points]
    m.add(t)
    return m


# --- the stall front --------------------------------------------------------------------

def half_door(width, height=1.2, seed=0):
    """Vertical boards on a Z brace, iron strap hinges and a bolt; centred, thin along X."""
    m = PaintMesh()
    count = max(3, int(round(width / .14)))
    for k in range(count):
        z = -width / 2 + (k + .5) * width / count
        board(m, (.035, height - .02 * (k % 2), width / count - .008), (0, height / 2, z), seed + k)
    for y in (.16, height - .16):
        board(m, (.03, .11, width - .04), (.032, y, 0), seed + 40, TIMBER_DARK, along=2)
    length = math.hypot(width - .12, height - .32)
    a = math.degrees(math.atan2(height - .32, width - .12))
    brace = PaintMesh()
    board(brace, (.03, .1, length), (0, 0, 0), seed + 41, TIMBER_DARK, along=2)
    m.add(brace, None, rotation=_rx(a), offset=(.032, height / 2, 0))
    for y in (.16, height - .16):
        m.add(box((.012, .045, .32), (-.024, y, -width / 2 + .18), .003), rgb(IRON))
    m.add(box((.02, .03, .12), (-.03, height * .55, width / 2 - .1), .004), rgb(IRON))
    # The top rail is worn pale where heads lean over it.
    board(m, (.07, .05, width), (0, height + .02, 0), seed + 50, TIMBER_GREY, along=2)
    return m


def manure_bay():
    """Three low board walls round the heap, so the muck is kept rather than spread."""
    m = PaintMesh()
    w, d, h = 2.3, 1.7, .62
    for k in range(4):
        y = .08 + k * .15
        board(m, (w, .14, .04), (0, y, -d / 2), 700 + k, along=0)
        for sx in (-1, 1):
            board(m, (.04, .14, d), (sx * w / 2, y, 0), 710 + k + sx, along=2)
    for x, z in ((-w / 2, -d / 2), (w / 2, -d / 2), (-w / 2, d / 2), (w / 2, d / 2)):
        board(m, (.08, h + .08, .08), (x, (h + .08) / 2, z), 730, TIMBER_DARK)
    return m

