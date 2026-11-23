#!/usr/bin/env python3
"""The yard's tyres, its covered junk and its razor-wire fence (round 21): `playground_art/meshes/yard_junk/*.tres`.

    python3 scenes/environment/props/playground_art/source/yard_junk.py [--check]

The owner found the tyre stack and the two cubes beside it too coarse: the tyres were
plain tori, the cubes bare blocks. This writes three vertex-painted text meshes that the
art pass (`build_playground_art.py`) hangs where the graybox had them:

* `truck_tyre.tres`: a truck tyre laid flat, about 1 m across - a tread of staggered
  blocks between two ribs, rounded shoulders, a sidewall with its moulded ring and bead,
  and in its hole a pressed-steel wheel whose yellow paint is mostly worn off (the
  inspection text: 轮毂刷过一层黄色油漆，大部分已经被磨掉了). Four stack against the shed
  wall, one lies flat on the ground.
* `covered_junk_west.tres`: on the lower shed footing, a pair of crates and a bucket under
  an old olive army blanket, its hem dragging on the concrete.
* `covered_junk_east.tres`: on the higher footing, crates and a board under a faded blue
  tarpaulin, tied with a cord and weighted with two bricks.

* `razor_coil.tres`, `razor_coil_short.tres`: concertina razor wire (prison wire), a 3 m
  and a 1.5 m length of overlapping clipped loops of barbed tape, coil axis along +Z.
* `wire_post.tres`: a steel fence post with its arm cranked outward (toward -X) to carry
  the top coil. With the chain-link these close the yard's open edges (round 21: the
  owner could walk off the west side), on bodies of their own in `build_outdoor_locations`.

The footings themselves stay: their concrete base still shows under the hem, so the
ping-pong ball is still caught between the base and the ground with the gap on one side
only (the texts). Both piles stand within a few centimetres of their footing's box, and
carry no collision (the footings' colliders are unchanged). Pure Python, deterministic.
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ART = HERE.parent
ROOT = HERE.parents[4]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(HERE))

from stable_meshes import PaintMesh, mix, rgb  # noqa: E402
from stable_animals import Ell, Field, surface  # noqa: E402
from site_mesh import box, euler, fbm as _fbm, noise as _noise, smoothstep  # noqa: E402


def fbm(x, y, seed, octaves=4):
    """`site_mesh.fbm` remapped from about -1..1 to 0..1."""
    return .5 + .5 * _fbm(x, y, seed, octaves)


def noise(x, y, seed=0):
    """`site_mesh.noise` remapped from about -1..1 to 0..1."""
    return .5 + .5 * _noise(x, y, seed)

MESH_DIR = ART / "meshes" / "yard_junk"

RUBBER = (38, 38, 40)
RUBBER_WORN = (58, 57, 56)
DUST = (104, 100, 94)
STEEL = (78, 76, 72)
RUST = (112, 70, 44)
YELLOW = (196, 156, 42)
BLANKET = (86, 92, 58)
BLANKET_DARK = (58, 62, 40)
TARP = (70, 104, 140)
TARP_FADED = (122, 146, 162)
CORD = (172, 158, 120)
BRICK = (142, 74, 52)
CONCRETE = (126, 126, 122)


def _c(t):
    return rgb(t)


def _scale(c, f):
    return tuple(min(255, max(0, round(v * f))) for v in c)


# --- the tyre ------------------------------------------------------------------------------

TYRE_R = 0.5        # outer radius
BEAD_R = 0.285      # where the tyre meets the wheel
HALF_W = 0.115      # half the section width (the stack's pitch is 2 * HALF_W + 0.01)
SIDES = 128         # round the tyre
BLOCKS = 32         # tread blocks round the tyre, per row


def _tyre_profile():
    """(radius, height, part) round the section, from the bottom bead to the top bead."""
    pts = []
    # bottom sidewall from bead outwards, the shoulder, the tread, the top shoulder and wall
    for i in range(9):
        t = i / 8
        r = BEAD_R + (TYRE_R - 0.035 - BEAD_R) * t
        bulge = 0.018 * math.sin(math.pi * t)
        pts.append((r, -HALF_W + 0.02 * (1 - t) ** 2 - bulge, "wall"))
    for i in range(1, 6):
        a = -math.pi / 2 + (math.pi / 2) * i / 6
        pts.append((TYRE_R - 0.035 + 0.035 * math.cos(a), -HALF_W + 0.035 + 0.035 * math.sin(a), "shoulder"))
    for i in range(13):
        y = -HALF_W + 0.035 + (2 * (HALF_W - 0.035)) * i / 12
        pts.append((TYRE_R, y, "tread"))
    for i in range(1, 6):
        a = (math.pi / 2) * i / 6
        pts.append((TYRE_R - 0.035 + 0.035 * math.cos(a), HALF_W - 0.035 + 0.035 * math.sin(a), "shoulder"))
    for i in range(9):
        t = 1 - i / 8
        r = BEAD_R + (TYRE_R - 0.035 - BEAD_R) * t
        bulge = 0.018 * math.sin(math.pi * t)
        pts.append((r, HALF_W - 0.02 * (1 - t) ** 2 + bulge, "wall"))
    return pts


def _groove(angle, y):
    """Depth (m) of the tread pattern at this angle and height across the tread."""
    u = angle * BLOCKS / math.tau
    ay = abs(y)
    depth = 0.0
    if ay < 0.012:
        depth = 0.012  # the centre groove
    else:
        row = 0.5 if y > 0 else 0.0  # the two rows are staggered by half a block
        f = (u + row + 0.35 * (ay - 0.012) / 0.07) % 1.0
        if f < 0.22:
            depth = 0.011  # the slanted groove between blocks
    return depth


def truck_tyre() -> PaintMesh:
    profile = _tyre_profile()
    rows, colours = [], []
    for k in range(SIDES):
        a = math.tau * k / SIDES
        ca, sa = math.cos(a), math.sin(a)
        row, col = [], []
        for r, y, part in profile:
            depth = 0.0
            if part == "tread" and abs(y) < HALF_W - 0.03:
                depth = _groove(a, y)
            elif part == "wall" and abs(r - 0.43) < 0.004:
                depth = 0.002  # the moulded ring on the sidewall
            rr = r - depth
            x, z = rr * ca, rr * sa
            row.append((x, y, z))
            n = fbm(x * 9 + 3, z * 9 + y * 5, 41, 3)
            c = mix(RUBBER, RUBBER_WORN, smoothstep(.45, .85, n) * .35)
            if depth > 0.006:
                c = _scale(RUBBER, .72)
            elif part == "tread":
                c = mix(c, RUBBER_WORN, .45)  # the worn running surface
            if y > HALF_W - 0.04 and part != "tread":
                c = mix(c, DUST, .32 * smoothstep(.35, .8, noise(x * 14, z * 14, 43)))  # dust on top
            if part == "wall" and abs(r - BEAD_R) < 0.012:
                c = _scale(c, .8)
            col.append(_c(c))
        rows.append(row)
        colours.append(col)
    m = PaintMesh()
    rows = [list(r) for r in zip(*rows)]
    colours = [list(c) for c in zip(*colours)]
    m.grid(rows, wrap=True, centers=[(0, y, 0) for _, y, _ in profile], colors=colours)
    _wheel(m)
    return m


def _wheel(m: PaintMesh) -> None:
    """The pressed-steel wheel in the hole: rim, dished disc, eight hand holes, hub."""
    # Section of the wheel (radius, height) from the rim lip down the disc to the hub.
    section = [(BEAD_R + 0.008, 0.07), (BEAD_R - 0.004, 0.07), (BEAD_R - 0.01, 0.05),
               (BEAD_R - 0.012, -0.04), (BEAD_R - 0.04, -0.045), (0.2, -0.02), (0.16, 0.01),
               (0.1, 0.02), (0.075, 0.03), (0.06, 0.03), (0.045, 0.034), (0.0, 0.036)]
    sides = 96
    rows, colours = [], []
    for k in range(sides):
        a = math.tau * k / sides
        ca, sa = math.cos(a), math.sin(a)
        row, col = [], []
        for r, y in section:
            x, z = r * ca, r * sa
            row.append((x, y, z))
            # Hand holes in the disc, painted as dark ovals; paint worn to steel and rust.
            hole = False
            if 0.11 < r < 0.2:
                h = (a * 8 / math.tau) % 1.0
                hole = abs(h - 0.5) < 0.12 and abs(r - 0.15) < 0.03
            # Mostly worn off: the yellow survives in the dish's hollows and round the holes.
            wear = smoothstep(.3, .52, fbm(x * 18 + 7, z * 18 - y * 6, 47, 3))
            if 0.125 < r < 0.185:
                wear *= .7
            c = mix(YELLOW, STEEL, wear)
            c = mix(c, RUST, .6 * smoothstep(.45, .8, noise(x * 30, z * 30, 49)))
            if r > BEAD_R - 0.006:
                c = mix(c, STEEL, .5)  # the rim lip: chipped by tyre irons
            if hole:
                c = (22, 22, 22)
            elif r < 0.07:
                c = mix(STEEL, RUST, .4)  # the hub and its nuts
            col.append(_c(c))
        rows.append(row)
        colours.append(col)
    rows = [list(r) for r in zip(*rows)]
    colours = [list(c) for c in zip(*colours)]
    m.grid(rows, wrap=True, outward=(0, 1, 0), colors=colours)


# --- the covered junk --------------------------------------------------------------------


class RBox:
    """A rounded box, turned by `yaw` degrees about Y."""

    def __init__(self, c, half, r=0.02, yaw=0.0, k=0.06):
        self.c, self.half, self.r, self.k = c, half, r, k
        a = math.radians(yaw)
        self.sa, self.ca = math.sin(a), math.cos(a)
        reach = math.hypot(half[0], half[2]) + r + k
        self.lo = (c[0] - reach, c[1] - half[1] - r - k, c[2] - reach)
        self.hi = (c[0] + reach, c[1] + half[1] + r + k, c[2] + reach)

    def d(self, x, y, z):
        dx, dy, dz = x - self.c[0], y - self.c[1], z - self.c[2]
        lx = dx * self.ca - dz * self.sa
        lz = dx * self.sa + dz * self.ca
        qx, qy, qz = abs(lx) - self.half[0], abs(dy) - self.half[1], abs(lz) - self.half[2]
        out = math.sqrt(max(qx, 0) ** 2 + max(qy, 0) ** 2 + max(qz, 0) ** 2)
        return out + min(max(qx, qy, qz), 0.0) - self.r


class Drape(Field):
    """Smooth-blended objects under one cloth that falls over the footing's box to just above
    the ground, leaving a strip of the concrete base showing. The field is offset by the
    cloth's thickness, flared at the hem, and creased."""

    HEM = 0.075  # the cloth stops this far above the ground: the base shows below it

    def __init__(self, prims, half, lip, seed, thickness=0.012, creases=0.012):
        super().__init__(prims, floor=None)
        mid = (lip + self.HEM) / 2
        self.box = RBox((0, mid, 0), (half - 0.05, (lip - self.HEM) / 2, half - 0.05), r=0.08, k=0.2)
        self.prims = prims + [self.box]
        self.seed, self.t, self.creases, self.lip = seed, thickness, creases, lip

    def __call__(self, x, y, z):
        d = super().__call__(x, y, z) - self.t
        side = smoothstep(self.lip + 0.05, 0.12, y)
        d -= 0.03 * smoothstep(0.3, self.HEM, y)  # the hem flares out
        # Hanging folds down the sides, round the pile; loose creases over the top.
        a = math.atan2(z, x)
        hang = math.sin(a * 13 + 2.5 * noise(a * 2, 0.5, self.seed + 2)) * 0.016 * side
        fold = math.sin((x * 1.7 + z * 2.3) * 9 + 3 * fbm(x * 2, z * 2, self.seed, 2))
        fold += .6 * math.sin((x * 2.9 - z * 1.3) * 13 + 2 * noise(x * 3, z * 3, self.seed + 1))
        d += hang + self.creases * fold * 0.5 * (1 - .6 * side)
        # An uneven hem: lifted here, touching the concrete there.
        hem = self.HEM + 0.05 * smoothstep(.35, .8, noise(a * 2.2 + 4, 1.5, self.seed + 3))
        return max(d, hem - y)


def _ao(c, ao):
    return _scale(c, .55 + .45 * ao)


def covered_junk_west() -> PaintMesh:
    """Two crates and a bucket under an army blanket, on a 1.4 m footing 0.4 m high."""
    lip = 0.4  # the footing's top, local origin at its centre on the ground
    under = [
        RBox((-0.24, lip + 0.15, 0.08), (0.34, 0.15, 0.26), r=0.03, yaw=6, k=0.08),
        RBox((0.32, lip + 0.11, -0.12), (0.26, 0.11, 0.3), r=0.03, yaw=-8, k=0.08),
        Ell((0.12, lip + 0.33, 0.18), (0.14, 0.16, 0.14), k=0.06),  # a bucket, upside down
    ]
    field = Drape(under, 0.69, lip, seed=211)

    def paint(p, n, ao):
        x, y, z = p
        w = fbm(x * 6 + 1, z * 6 + y * 4, 213, 3)
        c = mix(BLANKET, BLANKET_DARK, smoothstep(.3, .75, w))
        # The weave's stripe at the hem, and a darned patch.
        if abs(y - 0.11) < 0.012 or abs(y - 0.15) < 0.006:
            c = _scale(c, .86)
        if (x - 0.3) ** 2 + (z + 0.05) ** 2 < 0.012 and y > lip + 0.15:
            c = mix(c, (110, 96, 70), .8)
        c = mix(c, DUST, .25 * smoothstep(.2, .8, n[1]) * smoothstep(.4, .9, noise(x * 9, z * 9, 215)))
        return _c(_ao(c, ao))

    return surface(field, 0.037, paint)


def covered_junk_east() -> PaintMesh:
    """Crates and a board under a blue tarpaulin, tied and weighted, on a 0.6 m footing."""
    lip = 0.6
    under = [
        RBox((-0.2, lip + 0.18, -0.05), (0.36, 0.18, 0.3), r=0.025, yaw=-4, k=0.06),
        RBox((0.34, lip + 0.12, 0.16), (0.24, 0.12, 0.24), r=0.025, yaw=12, k=0.06),
        RBox((0.05, lip + 0.39, 0.0), (0.52, 0.015, 0.14), r=0.01, yaw=24, k=0.05),  # a board
    ]
    field = Drape(under, 0.69, lip, seed=221, thickness=0.008, creases=0.016)

    def paint(p, n, ao):
        x, y, z = p
        c = mix(TARP, TARP_FADED, smoothstep(.1, .9, n[1]) * .55 + .3 * fbm(x * 4, z * 4, 223, 2))
        # The cord round the pile, over the top and across.
        if abs(z - 0.08 + 0.05 * x) < 0.012 or abs(x + 0.1 - 0.08 * z) < 0.012:
            c = CORD
        # Eyelets along the hem.
        if y < 0.11 and abs(((x + z) * 5) % 1.0 - .5) < .05:
            c = (150, 150, 140)
        c = mix(c, DUST, .2 * smoothstep(.3, .9, noise(x * 7, z * 7, 225)))
        return _c(_ao(c, ao))

    tarp = surface(field, 0.037, paint)
    # Two bricks holding it down: separate solids resting on the top.
    brick = Field([RBox((0, 0.032, 0), (0.11, 0.032, 0.055), r=0.006, k=0.01)])

    def brick_paint(p, n, ao):
        x, y, z = p
        c = mix(BRICK, _scale(BRICK, .7), smoothstep(.3, .8, fbm(x * 30, z * 30 + y * 20, 227, 2)))
        return _c(_ao(c, ao))

    piece = surface(brick, 0.012, brick_paint)
    for (bx, bz, yaw) in ((-0.28, -0.1, 18), (0.36, 0.2, -30)):
        top = _top(field, bx, bz, lip + 0.8)
        a = math.radians(yaw)
        tarp.add(piece, rotation=((math.cos(a), 0, math.sin(a)), (0, 1, 0), (-math.sin(a), 0, math.cos(a))),
                 offset=(bx, top - 0.005, bz))
    return tarp


def _top(field, x, z, start):
    """The height of the surface straight down at x, z."""
    lo, hi = 0.0, start
    for _ in range(30):
        mid = (lo + hi) / 2
        if field(x, mid, z) < 0:
            lo = mid
        else:
            hi = mid
    return lo


# --- the razor-wire fence ------------------------------------------------------------------

GALVANISED = (150, 156, 160)
GALV_DARK = (96, 100, 104)
COIL_R = 0.3          # concertina loop radius
LOOP_STEP = 0.11      # loops along the coil
LOOP_POINTS = 30


def razor_coil(length: float = 3.0, seed: int = 301) -> PaintMesh:
    """Concertina wire along +Z, centred on the origin: loops of flat barbed tape, every
    other one leaning the other way so neighbours cross in the diamonds the clips make."""
    m = PaintMesh()
    loops = int(round(length / LOOP_STEP))
    half_w = 0.011
    for i in range(loops):
        z0 = -length / 2 + (i + 0.5) * length / loops
        lean = math.radians(24 if i % 2 else -24)
        r = COIL_R * (1 + 0.05 * (_noise(i * 0.7, 0.3, seed)))
        ring = []
        for k in range(LOOP_POINTS):
            a = math.tau * k / LOOP_POINTS
            y, x = r * math.sin(a), r * math.cos(a)
            ring.append(((x, y, z0 + math.tan(lean) * y), (math.cos(a), math.sin(a), 0.0)))
        rust = smoothstep(.55, .9, noise(i * 0.31, 0.7, seed + 1))
        colour = rgb(mix(GALVANISED, RUST, rust * .6))
        dark = rgb(mix(GALV_DARK, RUST, rust * .6))
        base = len(m.points)
        for (x, y, z), n in ring:  # the tape: a ribbon facing out from the coil's axis
            m._vertex((x, y, z - half_w), n, colour)
            m._vertex((x, y, z + half_w), n, dark)
        for k in range(LOOP_POINTS):
            k1 = (k + 1) % LOOP_POINTS
            a0, b0, a1, b1 = base + 2 * k, base + 2 * k + 1, base + 2 * k1, base + 2 * k1 + 1
            m.indices += [a0, a1, b1, a0, b1, b0]
        for k in range(0, LOOP_POINTS, 2):  # the barbs: a pair of blades off each edge
            (x, y, z), n = ring[k]
            (x1, y1, z1), _ = ring[(k + 1) % LOOP_POINTS]
            tx, ty = (x1 - x) * 0.35, (y1 - y) * 0.35
            for side in (-1, 1):
                tip = (x + tx, y + ty, z + side * (half_w + 0.03))
                root_a = (x, y, z + side * half_w)
                root_b = (x + 2 * tx, y + 2 * ty, z + side * half_w)
                v = len(m.points)
                for q in (root_a, tip, root_b):
                    m._vertex(q, n, colour)
                m.indices += [v, v + 1, v + 2]
    return m


def wire_post() -> PaintMesh:
    """A 60 mm steel post 2.3 m high with its top cranked outward (-X) at 45 degrees."""
    m = PaintMesh()
    paint = rgb(GALV_DARK)
    m.add(box((0.06, 2.3, 0.06), (0, 1.15, 0), bevel=0.006), lambda p, n: paint)
    arm = 0.62
    m.add(box((0.05, arm, 0.05), (0, arm / 2, 0), bevel=0.005), lambda p, n: paint,
          rotation=euler((0, 0, 45)), offset=(0, 2.28, 0))
    m.add(box((0.1, 0.06, 0.1), (0, 2.31, 0), bevel=0.008), lambda p, n: rgb(GALVANISED))  # the cap
    m.add(box((0.16, 0.05, 0.16), (0, 0.025, 0), bevel=0.01), lambda p, n: rgb(CONCRETE))  # its footing
    return m


MESHES = {
    "truck_tyre": truck_tyre,
    "covered_junk_west": covered_junk_west,
    "covered_junk_east": covered_junk_east,
    "razor_coil": razor_coil,
    "razor_coil_short": lambda: razor_coil(1.5, 303),
    "wire_post": wire_post,
}


def mesh_tres(name: str, mesh: PaintMesh) -> str:
    return f'[gd_resource type="ArrayMesh" format=3]\n\n[resource]\nresource_name = "{name}"\n_surfaces = {mesh.surface()}\n'


def outputs() -> dict[Path, str]:
    return {MESH_DIR / f"{name}.tres": mesh_tres(name, build()) for name, build in MESHES.items()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    files = outputs()
    if args.check:
        stale = [p.name for p, text in files.items() if not p.is_file() or p.read_text() != text]
        if stale:
            parser.error("stale yard junk meshes: " + ", ".join(stale) + "; run yard_junk.py")
    else:
        MESH_DIR.mkdir(parents=True, exist_ok=True)
        for p, text in files.items():
            p.write_text(text)
    for p, text in files.items():
        print(f"{p.relative_to(ROOT)}: {len(text):,} bytes")


if __name__ == "__main__":
    main()
