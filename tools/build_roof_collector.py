#!/usr/bin/env python3
"""Sculpt the yard resident as a painted, jointed native scene (no imported textures).

Round 21: the owner found the container's resident too coarse (eight-sided lofts, block
hands). He is now sculpted like the stable workers of round 19, with the signed-distance
kit of `stable_animals.py`: overlapping ellipsoids and tapered limbs blended by a smooth
minimum, cut where a socket or a fold goes in, turned into one closed mesh per joint by
surface nets, with normals from the field and an ambient-occlusion estimate painted into
the vertex colour. He is the same man: a middle-aged scavenger in a patched olive work
jacket open on a teal shirt, darned blue-grey trousers and old leather work boots, his
dark hair going silver at the temples, a few days of stubble.

The rig is unchanged (`roof_collector_pose.gd` moves these joints): Hip > Trunk > Head,
Trunk > ArmL/ArmR > Elbow, Hip > ThighL/ThighR > Shin > Boot, each piece modelled in its
joint's own space in the rest pose, front toward -Z. One RGBA8-painted surface per piece,
so sleeves, face and repairs add no material passes. Pure Python and deterministic.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

from stable_meshes import mix, rgb  # noqa: F401 - imported first: it puts the kit on the path
from stable_animals import Cone, Ell, Field, surface
from site_mesh import fbm, noise, smoothstep

OUTPUT = Path(__file__).resolve().parents[1] / "scenes/environment/characters/roof_collector.tscn"
MOTION = "res://scenes/environment/characters/roof_collector_pose.gd"
MESH_DIR = OUTPUT.parent / "roof_collector_meshes"
MESH_RES = "res://scenes/environment/characters/roof_collector_meshes"

OLIVE = (108, 118, 78)
MOSS = (79, 93, 68)
TWILL = (136, 133, 91)
YOKE = (172, 125, 64)
SHIRT = (55, 75, 79)
ZIP = (204, 184, 134)
PANTS = (75, 82, 93)
DARN = (123, 124, 117)
LEATHER = (63, 47, 42)
SOLE = (39, 42, 45)
SKIN = (179, 127, 102)
CHEEK = (203, 145, 116)
HAIR = (66, 61, 58)
SILVER = (152, 143, 126)
LIPS = (113, 70, 61)
SKIN_DEEP = (140, 94, 74)
STUBBLE = (118, 96, 86)
EYE = (36, 30, 28)
WHITE = (196, 186, 172)
LACE = (150, 128, 92)
STITCH = (176, 160, 118)

# Joint offsets (parent space), the rig `roof_collector_pose.gd` was written against.
HIP = (0, .872, 0)
HEAD_AT = (0, .548, -.016)
ARM_AT = {-1: (-.217, .434, .01), 1: (.217, .421, .01)}
ELBOW_AT = .234
THIGH_AT = (.103, 0, .012)
KNEE_AT = .445
ANKLE_AT = .345


def vec3(v):
    return "Vector3(%s)" % ", ".join(f"{c:.4g}" for c in v)


# --- the kit: cuts and folds on top of the smooth union ------------------------------------


class Sculpt(Field):
    """A `Field` with smooth cuts (sockets, the gap between parts) and a surface relief."""

    def __init__(self, prims, cuts=(), relief=None, floor=None):
        super().__init__(prims, floor)
        self.cuts = list(cuts)
        self.relief = relief

    def __call__(self, x, y, z):
        d = super().__call__(x, y, z)
        for c in self.cuts:
            lo, hi = c.lo, c.hi
            if lo[0] < x < hi[0] and lo[1] < y < hi[1] and lo[2] < z < hi[2]:
                e = -c.d(x, y, z)
                k = c.k
                h = k - abs(d - e)
                d = max(d, e) + (h * h * .25 / k if h > 0 else 0.0)
        if self.relief is not None and d < .02:
            d += self.relief(x, y, z)
        return d


def _shade(colour_fn, alpha=1.0):
    """colour(p, n) -> sRGB bytes, darkened in the field's creases."""
    def paint(p, n, ao):
        c = colour_fn(p, n)
        k = .56 + .44 * ao
        return rgb(tuple(max(0.0, min(255.0, v * k)) for v in c), alpha)
    return paint


def _scale(c, s):
    return tuple(v * s for v in c)


def _cloth(base, p, seed, amount=.16):
    """Worn cloth: a soft mottle plus a fine weave."""
    f = fbm(p[0] * 9 + seed, p[1] * 9 + p[2] * 7, seed, 3)
    c = mix(base, _scale(base, .74), smoothstep(-.3, .6, f) * amount * 3)
    w = noise(p[0] * 160 + p[2] * 90, p[1] * 160, seed + 5)
    return _scale(c, .97 + .06 * w)


def _skin(p, seed):
    f = fbm(p[0] * 38, p[1] * 38 + p[2] * 22, seed, 2)
    return mix(SKIN, SKIN_DEEP, smoothstep(-.3, .7, f) * .32)


def _fold_band(y, centre, width):
    return max(0.0, 1.0 - abs(y - centre) / width)


# --- the trunk: an open work jacket over a teal shirt -------------------------------------


def jacket():
    """Trunk-local: origin at the hip joint, +Y up the spine, front toward -Z."""
    prims = [
        Ell((0, .01, .008), (.176, .11, .12)),
        Ell((0, .15, -.004), (.168, .13, .118)),
        Ell((0, .315, -.006), (.19, .13, .122)),
        Ell((0, .42, .006), (.2, .078, .104), k=.05),
        Ell((-.198, .425, .01), (.074, .07, .076), k=.05),
        Ell((.198, .418, .01), (.074, .07, .076), k=.05),
        # The jacket's skirt, hanging a little proud of the hips.
        Ell((0, -.07, .008), (.197, .07, .142), k=.05),
        # The neck rising out of the collar (the head piece carries it on up).
        Cone((0, .46, .004), (0, .575, -.012), .06, .052, k=.03),
        # Collar: two thick flaps standing round the neck, and the lapels lying on the chest.
        Ell((-.064, .49, .018), (.042, .036, .07), k=.025),
        Ell((.064, .49, .018), (.042, .036, .07), k=.025),
    ]
    cuts = [
        # The open front: a shallow V where the shirt shows under the collar.
        Cone((0, .5, -.16), (0, .3, -.15), .05, .012, k=.02),
    ]

    def relief(x, y, z):
        # Soft drag folds: horizontal at the small of the back, diagonal under the arms.
        r = 0.0
        if z > .06:
            r += .0025 * math.sin(y * 70) * _fold_band(y, .17, .09)
        if abs(x) > .13:
            r += .002 * math.sin((y - abs(x) * .8) * 80) * _fold_band(y, .27, .07)
        return r

    field = Sculpt(prims, cuts, relief)
    seed = 31

    def colour(p, n):
        x, y, z = p
        ax = abs(x)
        if y > .49 and ax < .056 and z < .03 and -.06 < z:
            return _skin(p, seed)  # the throat above the shirt
        front = z < -.07
        v_open = front and .3 < y < .5 and ax < (y - .3) * .36 + .008
        if v_open:
            c = _cloth(SHIRT, p, seed, .1)
            if y > .455 and ax > .018:
                c = _scale(c, .82)  # the shirt's own collar points
            return c
        c = _cloth(OLIVE, p, seed)
        if y > .455 and ax > .03:
            c = _cloth(MOSS, p, seed, .1)  # the collar, a darker, newer cloth
        if front and .3 < y < .5 and abs(ax - ((y - .3) * .36 + .008)) < .012:
            c = _scale(c, .8)  # lapel edge
        if front and ax < .006 and -.13 < y <= .3:
            c = ZIP
            if ax > .003:
                c = _scale(ZIP, .72)
        # Pockets, painted: the outline, the flap's seam, and a brass button.
        for px, py, w in ((.092, .31, .046), (.11, .03, .052)):
            if front and (abs(abs(ax - px) - w) < .0035 and py - .045 < y < py + .035):
                c = _scale(c, .74)
            if front and abs(ax - px) < w and abs(y - (py - .045)) < .0035:
                c = _scale(c, .74)
            if front and abs(ax - px) < w and abs(y - (py + .03)) < .004:
                c = _scale(c, .66)
            if front and abs(ax - px) < .0065 and abs(y - (py + .022)) < .0065:
                c = (150, 124, 70)
        # Repairs: a yoke-coloured patch over the right chest pocket, a darn at the left hip.
        if front and .045 < x < .14 and .24 < y < .3:
            c = _cloth(YOKE, p, seed, .1)
            if abs(y - .245) < .003 or abs(y - .295) < .003 or abs(x - .05) < .003 or abs(x - .135) < .003:
                c = STITCH
        if x < -.13 and .07 < y < .2 and z < -.02:
            c = _cloth(DARN, p, seed, .2)
        if z > .06 and abs(x) < .1 and .2 < y < .24:
            c = _cloth(TWILL, p, seed, .1)  # a twill patch across the back
        # Seams: shoulders, back yoke, side seams, and the skirt's hem band.
        if abs(y - (.452 - .2 * max(0.0, ax - .12))) < .004 and ax > .08:
            c = _scale(c, .78)
        if z > .05 and abs(y - .4) < .004:
            c = _scale(c, .8)
        if abs(ax - .17) < .004 and abs(z) < .03 and y < .36:
            c = _scale(c, .82)
        if y < -.105:
            c = _scale(c, .78)
        if y < .0 and z > .0:
            c = _scale(c, .9)
        return c
    return surface(field, .021, _shade(colour))


# --- the head ------------------------------------------------------------------------------


def head():
    """Head-local: origin at the base of the neck, front toward -Z."""
    prims = [
        Cone((0, -.01, .006), (0, .095, -.004), .052, .047, k=.025),
        Ell((0, .19, .012), (.081, .098, .097)),
        Ell((0, .122, -.03), (.066, .07, .07), k=.05),
        Ell((0, .078, -.072), (.03, .022, .026), k=.035),
        Ell((-.044, .148, -.068), (.027, .02, .024), k=.03),
        Ell((.044, .148, -.068), (.027, .02, .024), k=.03),
        Ell((0, .19, -.083), (.062, .016, .02), k=.025),
        Cone((0, .184, -.094), (0, .143, -.117), .011, .0155, k=.012),
        Ell((-.013, .139, -.105), (.0105, .0085, .009), k=.008),
        Ell((.013, .139, -.105), (.0105, .0085, .009), k=.008),
        Ell((0, .1, -.098), (.024, .009, .012), k=.012),
        Ell((-.083, .158, .01), (.012, .028, .019), k=.012),
        Ell((.083, .158, .01), (.012, .028, .019), k=.012),
        # Hair: the mass, a swept-up fringe heavier on his left, and the back of it.
        Ell((0, .205, .018), (.087, .088, .099), k=.02),
        Ell((-.026, .268, -.05), (.056, .022, .046), pitch=-14, k=.03),
        Ell((.03, .27, -.03), (.05, .02, .05), k=.03),
        Ell((0, .17, .066), (.074, .07, .044), k=.03),
    ]
    cuts = [
        Ell((-.031, .162, -.096), (.019, .011, .012), k=.01),
        Ell((.031, .162, -.096), (.019, .011, .012), k=.01),
        # A line between the lips.
        Ell((0, .1, -.112), (.021, .0022, .01), k=.004),
    ]
    field = Sculpt(prims, cuts)
    seed = 41

    def hair_weight(x, y, z):
        """0 skin .. 1 hair, soft at the hairline so it doesn't stair-step."""
        ax = abs(x)
        line = .232 - .05 * smoothstep(-.06, .04, z)  # the hairline rises toward the face
        side = smoothstep(.066, .08, ax) * smoothstep(-.05, -.02, z)
        line = line + (.168 - .04 * smoothstep(-.03, .06, z) - line) * side  # sideburns
        line = line + (.115 - line) * smoothstep(.03, .06, z)  # the back of the head
        w = smoothstep(line - .006, line + .006, y)
        # The ear stays skin.
        if ax > .074 and .128 < y < .19 and abs(z - .01) < .028:
            w *= smoothstep(.074, .1, ax) * 0.0
        return w

    def colour(p, n):
        x, y, z = p
        ax = abs(x)
        h = fbm(x * 70 + z * 30, y * 140, seed, 2)
        hair = mix(HAIR, _scale(HAIR, .72), smoothstep(-.4, .6, h))
        grey = .55 * smoothstep(.062, .09, ax) * smoothstep(.235, .185, y) * smoothstep(-.06, .0, z)
        grey += .25 * smoothstep(.5, .95, noise(x * 230, y * 230 + z * 90, seed))
        hair = mix(hair, SILVER, min(1.0, grey))
        hw = hair_weight(x, y, z)
        if hw > .98:
            return hair
        c = _skin(p, seed)
        if z < -.035:
            # Ruddy cheeks and nose, and a few days of stubble on jaw, chin and lip.
            c = mix(c, CHEEK, .32 * smoothstep(.07, .02, abs(ax - .048)) * smoothstep(.04, .0, abs(y - .145)))
            c = mix(c, CHEEK, .25 * smoothstep(.02, .0, ax) * smoothstep(.03, .0, abs(y - .15)))
            st = smoothstep(.142, .112, y) * smoothstep(.052, .07, y)
            st = max(st, smoothstep(.016, .006, abs(y - .113)) * smoothstep(.03, .012, ax))  # the lip
            st *= .62 + .38 * noise(x * 420, y * 420, seed + 3)
            c = mix(c, STUBBLE, min(1.0, st * .85))
            lx, ly = x / .021, (y - .1) / .0052
            if lx * lx + ly * ly < 1.0:
                c = mix(c, LIPS, .85 if y < .1 else .7)
            for ex in (-.031, .031):
                dx, dy = x - ex, y - .162
                if dx * dx / .00021 + dy * dy / .00004 < 1.0:
                    c = EYE if dx * dx + dy * dy < .000042 else WHITE
                    break
                if abs(dy - .0085) < .0028 and abs(dx) < .019:
                    c = _scale(c, .66)  # the upper lid's crease
                if abs(dy - .021) < .0042 and abs(dx + .002 * (1 if ex > 0 else -1)) < .019:
                    c = mix(HAIR, SILVER, .25)  # brows
            if abs(ax - .036) < .0035 and .104 < y < .132:
                c = _scale(c, .86)  # nose-to-mouth folds
            if .205 < y < .225 and ax < .045 and abs((y - .205) % .009 - .0045) < .0012:
                c = _scale(c, .9)  # forehead lines
        return mix(c, hair, hw)
    return surface(field, .0085, _shade(colour))


# --- arms and hands ------------------------------------------------------------------------


def upper_arm(side, patched):
    """Arm-local: origin at the shoulder joint, hanging down to the elbow."""
    elbow = (side * .035, -ELBOW_AT, .007)
    prims = [
        Ell((side * -.004, -.005, .0), (.068, .062, .07), k=.04),
        Cone((0, -.02, 0), elbow, .061, .051, k=.04),
        Ell((side * .012, -.11, .004), (.062, .08, .063), k=.04),
    ]

    def relief(x, y, z):
        return .0022 * math.sin(y * 95 + z * 30) * _fold_band(y, -.2, .05)

    field = Sculpt(prims, relief=relief)

    def colour(p, n):
        x, y, z = p
        c = _cloth(OLIVE, p, 51 + side)
        if abs(y - (-.008)) < .004 and abs(x) > .03:
            c = _scale(c, .78)
        if y < -.17:
            c = mix(c, _scale(c, .8), _fold_band(y, -.2, .05))
        if patched and z < -.02 and -.2 < y < -.09 and x * side > 0:
            c = _cloth(YOKE, p, 57, .1)
            if abs(y + .2) < .003 or abs(y + .09) < .003:
                c = STITCH
        return c
    return surface(field, .0142, _shade(colour))


def forearm(side):
    """Elbow-local: the sleeve to a rolled cuff, and a working hand, palm to the thigh."""
    s = side
    wrist = (0, -.222, -.01)
    prims = [
        Ell((0, -.005, .004), (.053, .05, .055), k=.03),
        Cone((0, -.01, .002), (0, -.192, -.008), .051, .043, k=.03),
        # The rolled cuff.
        Cone((0, -.178, -.007), (0, -.206, -.009), .048, .047, k=.012),
        # Wrist and palm (flat across X, the palm facing the body).
        Cone((0, -.2, -.009), wrist, .028, .027, k=.02),
        Ell((s * -.003, -.262, -.014), (.0195, .045, .036), k=.022),
    ]
    # Four fingers, eased into a loose curl toward the palm, and the thumb forward.
    for i, fz in enumerate((-.04, -.021, -.002, .016)):
        knuckle = (s * -.002, -.302 + .004 * abs(i - 1.3), fz)
        mid = (s * -.012, -.333 + .006 * abs(i - 1.3), fz - .004)
        tip = (s * -.026, -.351 + .008 * abs(i - 1.3), fz - .006)
        r = .0095 if i < 3 else .0082
        prims.append(Cone(knuckle, mid, r, r * .92, k=.006))
        prims.append(Cone(mid, tip, r * .92, r * .78, k=.006))
    prims.append(Cone((s * -.006, -.238, -.042), (s * -.014, -.272, -.058), .0125, .0105, k=.01))
    prims.append(Cone((s * -.014, -.272, -.058), (s * -.022, -.296, -.06), .0105, .0088, k=.008))
    field = Sculpt(prims)

    def colour(p, n):
        x, y, z = p
        if y < -.205:
            c = _skin(p, 61 + s)
            if y < -.3:
                c = mix(c, CHEEK, .25)
            if abs(x * s + .02) < .02 and -.3 < y < -.24 and z > -.03:
                c = _scale(c, .9)  # the crease of the palm
            # Grime worked into the knuckles and nails.
            if y < -.296 and noise(x * 300, y * 300 + z * 200, 67) > .35:
                c = _scale(c, .82)
            return c
        c = _cloth(OLIVE, p, 63 + s)
        if y < -.176:
            c = _cloth(TWILL, p, 65 + s, .1)  # the cuff, rolled to show the lining
            if abs(y + .192) < .003:
                c = _scale(c, .78)
        if y > -.06:
            c = mix(c, _scale(c, .82), _fold_band(y, -.02, .04))
        return c
    return surface(field, .0077, _shade(colour))


# --- legs and boots ------------------------------------------------------------------------


def thigh(side, darned):
    """Thigh-local: origin at the hip joint, down to the knee."""
    s = side
    prims = [
        Ell((s * -.016, -.05, .004), (.072, .07, .082), k=.04),
        Cone((s * -.008, -.06, .002), (0, -.445, -.004), .08, .062, k=.04),
        Ell((s * -.004, -.22, -.006), (.084, .13, .084), k=.05),
        Ell((0, -.428, -.03), (.054, .05, .04), k=.03),
    ]

    def relief(x, y, z):
        return .0018 * math.sin(y * 120 + x * 40) * _fold_band(y, -.39, .05)

    field = Sculpt(prims, relief=relief)

    def colour(p, n):
        x, y, z = p
        c = _cloth(PANTS, p, 71 + s)
        if z < -.06 and abs(x) < .006:
            c = _scale(c, .84)  # the pressed crease, long since gone soft
        if abs(x * s - .085) < .005 and abs(z) < .03:
            c = _scale(c, .82)  # outer seam
        if y > -.12 and z < -.03 and abs(x * s - .055) < .004 and y > -.1 + .5 * (x * s - .02):
            c = _scale(c, .7)  # pocket opening
        if darned and z < -.03 and -.31 < y < -.2 and -.04 < x * s < .05:
            c = _cloth(DARN, p, 73, .2)
            if abs(y + .31) < .003 or abs(y + .2) < .003:
                c = STITCH
        if y < -.36:
            c = mix(c, _scale(c, .8), _fold_band(y, -.39, .05))
        return c
    return surface(field, .017, _shade(colour))


def shin(side, darned):
    """Shin-local: origin at the knee, the trouser leg falling over the boot top."""
    s = side
    prims = [
        Ell((0, -.005, -.01), (.06, .05, .062), k=.03),
        Cone((0, -.01, 0), (0, -.32, .006), .061, .054, k=.03),
        Ell((0, -.13, .026), (.056, .085, .052), k=.04),
        # The hem, a little wider where it breaks over the boot.
        Cone((0, -.29, .004), (0, -.345, .002), .056, .06, k=.02),
    ]
    field = Sculpt(prims)

    def colour(p, n):
        x, y, z = p
        c = _cloth(PANTS, p, 81 + s)
        if y < -.31:
            c = _scale(c, .8)
            if noise(x * 200, z * 200, 83 + s) > .3:
                c = mix(c, (110, 100, 86), .4)  # the hem frayed and dusty
        if z < -.05 and abs(x) < .006:
            c = _scale(c, .86)
        if abs(x * s - .058) < .004 and abs(z) < .03:
            c = _scale(c, .82)
        if darned and z < -.03 and -.17 < y < -.05 and abs(x) < .045:
            c = _cloth(DARN, p, 85, .2)
            if abs(y + .17) < .003 or abs(y + .05) < .003:
                c = STITCH
        return c
    return surface(field, .0155, _shade(colour))


def boot():
    """Ankle-local: an old leather work boot, the sole at y = -SOLE."""
    sole = -.082
    prims = [
        Cone((0, .085, .004), (0, -.03, .002), .052, .056, k=.03),
        Ell((0, -.042, -.035), (.05, .042, .108), k=.04),
        Ell((0, -.05, -.12), (.046, .033, .046), k=.03),
        Ell((0, -.048, .036), (.046, .036, .042), k=.03),
        # The sole and heel block, standing a little proud of the upper.
        Ell((0, -.075, -.04), (.056, .016, .125), k=.012),
        Ell((0, -.074, .04), (.05, .018, .046), k=.012),
    ]
    field = Sculpt(prims, floor=sole)

    def colour(p, n):
        x, y, z = p
        if y < -.062:
            c = SOLE
            if y > -.068:
                c = (70, 62, 54)  # the welt
            return c
        c = mix(LEATHER, (92, 70, 58), .4 * smoothstep(.2, .9, noise(x * 90, y * 90 + z * 60, 91)))
        if z < -.12 and n[1] > .2:
            c = mix(c, (118, 92, 72), .45)  # scuffed toe cap
        if abs(z + .088) < .004 and y > -.06:
            c = _scale(c, .7)  # the toe cap's seam
        # Lacing: crossed laces up the tongue.
        if z < -.02 and abs(x) < .022 and y > -.03:
            k = (y + .03) % .026
            if abs(abs(x) - k * .7) < .0035:
                return LACE
            if abs(x) > .016 and k < .006:
                return (150, 140, 120)  # eyelets
        if y > .07:
            c = _scale(c, .8)  # the collar of the boot
        return c
    return surface(field, .011, _shade(colour))


# --- the scene -----------------------------------------------------------------------------


def pieces():
    """{name: (parent path, offset, mesh key, mesh)} in tree order."""
    out = []
    hip = "Hip"
    trunk = f"{hip}/Trunk"
    out.append(("Hip", ".", HIP, None, None))
    out.append(("Trunk", hip, (0, 0, 0), "Trunk", jacket()))
    out.append(("Head", trunk, HEAD_AT, "Head", head()))
    for tag, side in (("L", -1), ("R", 1)):
        arm = f"{trunk}/Arm{tag}"
        out.append((f"Arm{tag}", trunk, ARM_AT[side], f"Sleeve{tag}", upper_arm(side, side > 0)))
        out.append(("Elbow", arm, (side * .035, -ELBOW_AT, .007), f"Forearm{tag}", forearm(side)))
    for tag, side in (("L", -1), ("R", 1)):
        leg = f"{hip}/Thigh{tag}"
        out.append((f"Thigh{tag}", hip, (side * THIGH_AT[0], THIGH_AT[1], THIGH_AT[2]),
                    f"Trousers{tag}", thigh(side, side < 0)))
        out.append(("Shin", leg, (0, -KNEE_AT, 0), f"Shin{tag}", shin(side, side > 0)))
        out.append(("Boot", f"{leg}/Shin", (0, -ANKLE_AT, 0), "Shoe", None))
    return out


def rest_parts():
    """(mesh, world offset) for every piece in the rest pose (previews)."""
    world = {".": (0, 0, 0)}
    shoe = boot()
    result = []
    for name, parent, at, key, mesh in pieces():
        path = name if parent == "." else f"{parent}/{name}"
        origin = tuple(a + b for a, b in zip(world[parent], at))
        world[path] = origin
        if key == "Shoe":
            mesh = shoe
        if mesh is not None:
            result.append((mesh, origin))
    return result


def _snake(key):
    return "".join(f"_{c.lower()}" if c.isupper() else c for c in key).lstrip("_")


def outputs():
    """{path: text}: the scene, plus one text ArrayMesh per piece under MESH_DIR.

    The meshes live beside the scene, like the stable's animals and the cactus plot, so the
    scene stays a few kilobytes and each mesh is measured on its own.
    """
    files, nodes, refs = {}, [], {}
    shoe = boot()
    for name, parent, at, key, mesh in pieces():
        nodes.append(f'[node name="{name}" type="Node3D" parent="{parent}"]\nposition = {vec3(at)}\n')
        if key is None:
            continue
        path = name if parent == "." else f"{parent}/{name}"
        if key == "Shoe":
            mesh = shoe
        if key not in refs:
            stem = f"collector_{_snake(key)}"
            files[MESH_DIR / f"{stem}.tres"] = (
                f'[gd_resource type="ArrayMesh" format=3]\n\n[resource]\n'
                f'resource_name = "{stem}"\n_surfaces = {mesh.surface()}\n')
            refs[key] = (stem, f"{MESH_RES}/{stem}.tres")
        nodes.append(f'[node name="Pigment" type="MeshInstance3D" parent="{path}"]\n'
                     f'mesh = ExtResource("{refs[key][0]}")\nmaterial_override = SubResource("ClothAndSkin")\n')
    ext = "\n".join(f'[ext_resource type="ArrayMesh" path="{res}" id="{stem}"]' for stem, res in refs.values())
    header = f'''[gd_scene load_steps={len(refs) + 3} format=3]

[ext_resource type="Script" path="{MOTION}" id="pose"]
{ext}

[sub_resource type="StandardMaterial3D" id="ClothAndSkin"]
vertex_color_use_as_albedo = true
vertex_color_is_srgb = true
roughness = 0.94
'''
    root = '[node name="RoofCollector" type="Node3D"]\nscript = ExtResource("pose")\n'
    files[OUTPUT] = "\n".join([header, root, *nodes])
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    files = outputs()
    stale = sorted(set(MESH_DIR.glob("*.tres")) - set(files)) if MESH_DIR.is_dir() else []
    if args.check:
        bad = [f for f, text in files.items() if not f.is_file() or f.read_text() != text]
        if bad or stale:
            parser.error("the collector is stale; run tools/build_roof_collector.py")
    else:
        MESH_DIR.mkdir(parents=True, exist_ok=True)
        for f in stale:
            f.unlink()
        for f, text in files.items():
            f.write_text(text)
    total = sum(len(text) for text in files.values())
    largest = max(len(text) for text in files.values())
    print(f"Sculpted collector: {len(files)} files, {total:,} bytes (largest {largest:,}); no imported images.")


if __name__ == "__main__":
    main()
