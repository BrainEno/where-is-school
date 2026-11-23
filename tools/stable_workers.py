"""Two village women at work in the stable yard behind 01, round 19 (docs/EXAM_DREAM_ART.md).

The owner found the two yard figures coarse and could not tell what they were doing:
they were the exam crowd's student bodies, tinted, one holding a box for a rake. Round 19
sculpts them as what they are, with the signed-distance kit of `stable_animals.py`: two
old women in padded jackets, aprons and head cloths, black cloth shoes with white soles,
weathered hands and faces. Each does one job that reads from across the yard:

* the **raker** stands at the edge of the grain mat, bent from the hip, and draws a long
  wooden grain rake back and forth through the grain (`rake_keys()` keeps the head of the
  rake on the ground while her arms and back swing);
* the **sifter** sits on a low stool at the other edge with a round bamboo sieve over her
  knees and shakes it, beside a basket of grain and a sack.

Every figure is the same five pieces the dressing test knows (`Feet`, `Body/Coat`,
`Body/Head`, `Body/ArmL`, `Body/ArmR`), vertex-painted with an ambient-occlusion estimate
and lit by `stable_coat.gdshader`; their tool is its own node. A native `AnimationPlayer`
moves only visual pivots: no script, actor or collider. Pure Python and deterministic.
"""
from __future__ import annotations

import math

from stable_animals import Cone, Ell, Field, surface
from stable_meshes import PaintMesh, mix, rgb, sweep as _sweep
from site_mesh import box, cylinder, fbm, noise, smoothstep  # noqa: E402

SKIN = (176, 126, 96)
SKIN_DEEP = (132, 88, 66)
LIP = (138, 82, 70)
EYE = (34, 28, 26)
SHOE = (34, 31, 30)
SOLE = (214, 208, 194)
BAMBOO = (196, 168, 112)
BAMBOO_DEEP = (150, 120, 74)
WOOD = (150, 116, 80)
WOOD_DEEP = (104, 78, 54)
GRAIN = (222, 178, 88)
GRAIN_DEEP = (184, 138, 62)
HEMP = (176, 156, 116)

LOOKS = {
    # A navy padded jacket with grey sleeve covers, a faded red head cloth, a brown apron.
    "raker": dict(jacket=(56, 70, 102), sleeve=(122, 128, 132), trousers=(50, 50, 56), apron=(122, 96, 72),
                  cloth=(158, 62, 54), cloth_band=(122, 44, 40), hair=(120, 116, 112), seed=11),
    # A maroon-brown jacket, a blue apron and the white towel of a field worker's head.
    "sifter": dict(jacket=(116, 76, 64), sleeve=(104, 120, 138), trousers=(58, 62, 72), apron=(70, 98, 128),
                   cloth=(226, 220, 204), cloth_band=(92, 120, 160), hair=(96, 92, 90), seed=23),
}

HIP_STAND = .80
HIP_SIT = .36
RAKE_LEAN = 26.0
SIT_LEAN = 16.0
SHOULDER = (.165, .405, -.012)  # body-local, x mirrored
NECK = (0.0, .485, .012)
UPPER_ARM, FOREARM = .265, .235


def sweep(path, r, sides=8, per=1):
    """A round rod of one radius along `path`."""
    return _sweep(path, [r] * len(path), sides=sides, per=per)


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


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _rx(p, deg):
    """Rotate about X the way Godot's rotation_degrees.x does (+ tips +Y toward +Z)."""
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    x, y, z = p
    return (x, y * c - z * s, y * s + z * c)


def _ry(p, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    x, y, z = p
    return (x * c + z * s, y, -x * s + z * c)


def _shade(colour_fn):
    """Wrap colour(p, n) with the field's occlusion and a soft cloth mottle."""
    def paint(p, n, ao):
        c = colour_fn(p, n)
        k = .58 + .42 * ao
        return rgb(tuple(min(255.0, v * k) for v in c))
    return paint


def _cloth(base, p, seed, amount=.16):
    f = fbm(p[0] * 9 + seed, p[1] * 9 + p[2] * 7, seed, 3)
    return mix(base, _scale(base, .72), smoothstep(-.3, .6, f) * amount * 3)


def ik(shoulder, wrist, upper, lower, pole):
    """Two-bone elbow: the elbow bends toward `pole` (a direction) between the two ends."""
    d = _sub(wrist, shoulder)
    dist = min(_len(d), upper + lower - 1e-4)
    axis = _unit(d)
    a = (upper * upper - lower * lower + dist * dist) / (2 * dist)
    h = math.sqrt(max(0.0, upper * upper - a * a))
    side = _sub(pole, _scale(axis, sum(p * q for p, q in zip(pole, axis))))
    side = _unit(side)
    return _add(_add(shoulder, _scale(axis, a)), _scale(side, h))


# --- legs and shoes ---------------------------------------------------------------------

def _legs_standing(look):
    """Feet apart, the left a stride ahead, knees eased: figure-local, ground at y = 0."""
    prims, shoes = [], []
    for s, fwd, knee_fwd in ((-1, .13, .1), (1, -.08, -.0)):
        hip = (s * .088, HIP_STAND - .02, 0.0)
        knee = (s * .1, .45, knee_fwd)
        ankle = (s * .108, .085, fwd)
        prims += [Cone(hip, knee, .088, .064, k=.03), Cone(knee, ankle, .062, .05, k=.03)]
        shoes.append((s * .108, fwd + .045))
    prims.append(Ell((0, HIP_STAND - .02, 0), (.165, .085, .12)))
    return prims, shoes


def _legs_seated(look):
    """Seated on a low stool: thighs forward, shins down, feet flat in front."""
    prims, shoes = [], []
    for s in (-1, 1):
        hip = (s * .09, HIP_SIT + .02, -.02)
        knee = (s * .12, HIP_SIT + .07, .36)
        ankle = (s * .13, .085, .40)
        prims += [Cone(hip, knee, .09, .066, k=.03), Cone(knee, ankle, .062, .05, k=.03)]
        shoes.append((s * .13, .44))
    prims.append(Ell((0, HIP_SIT + .02, -.02), (.17, .09, .13)))
    return prims, shoes


def feet(look, seated):
    prims, shoes = (_legs_seated if seated else _legs_standing)(look)
    for x, z in shoes:
        prims.append(Ell((x, .042, z), (.046, .042, .112), k=.03))
    field = Field(prims, floor=0.0)
    seed = look["seed"]

    def colour(p, n):
        x, y, z = p
        near_shoe = min(((x - sx) / .06) ** 2 + ((z - sz) / .13) ** 2 for sx, sz in shoes) < 1.0
        if y < .092 and near_shoe:
            if y < .016:
                return SOLE
            return mix(SHOE, (60, 56, 54), .3 * max(0.0, n[1]))
        c = _cloth(look["trousers"], p, seed)
        if y < .13:
            c = _scale(c, .82)  # the turned-up cuff
        return c
    return surface(field, .024, _shade(colour))


# --- the body: a padded jacket and an apron ---------------------------------------------

def torso(look):
    """Body-local: origin at the hip joint, +Y up the spine, +Z forward."""
    prims = [
        Ell((0, .03, 0), (.18, .12, .135)),
        Ell((0, .17, .016), (.176, .13, .132)),
        Ell((0, .31, 0), (.186, .13, .126)),
        Ell((0, .375, -.05), (.152, .095, .095)),
        Ell((-.148, .395, -.012), (.078, .062, .078), k=.05),
        Ell((.148, .395, -.012), (.078, .062, .078), k=.05),
        Ell((0, -.075, .004), (.202, .06, .152), k=.05),
        Cone((0, .43, -.004), (0, .5, .012), .066, .052, k=.03),
        Ell((0, .1, .128), (.15, .18, .028), k=.03),
    ]
    field = Field(prims)
    seed = look["seed"] + 3

    def colour(p, n):
        x, y, z = p
        if z > .1 and -.12 < y < .27 and abs(x) < .158 and n[2] > .2:
            c = _cloth(look["apron"], p, seed, .12)
            if y > .235:
                c = _scale(c, .78)  # the apron's waistband
            return c
        c = _cloth(look["jacket"], p, seed)
        if y > .455:
            c = _scale(c, .74)  # stand collar
        if z > .05 and abs(x - .045) < .007 and y > .2:
            c = _scale(c, .7)  # the side-fastened placket of a padded jacket
        if z > .05 and abs(x - .045) < .016 and y > .2 and abs((y - .23) % .07 - .035) < .007:
            c = (40, 38, 40)  # cloth knot buttons
        if y < -.1:
            c = _scale(c, .82)
        return c
    return surface(field, .022, _shade(colour))


# --- the head: a lined face under a head cloth -------------------------------------------

def head(look):
    """Head-local: origin at the base of the neck."""
    prims = [
        Cone((0, 0, 0), (0, .085, .008), .043, .041, k=.02),
        Ell((0, .152, 0), (.081, .097, .091)),
        Ell((0, .106, .036), (.066, .064, .064), k=.04),
        Ell((0, .128, .099), (.013, .021, .016), k=.012),
        Ell((-.08, .13, .004), (.014, .026, .014), k=.01),
        Ell((.08, .13, .004), (.014, .026, .014), k=.01),
        Ell((0, .172, -.012), (.094, .099, .099), k=.03),
        Ell((0, .118, -.102), (.036, .026, .03), k=.02),
        Cone((0, .113, -.11), (.022, .05, -.128), .021, .011, k=.015),
        Cone((0, .113, -.11), (-.018, .056, -.124), .019, .01, k=.015),
    ]
    field = Field(prims)
    seed = look["seed"] + 7

    def colour(p, n):
        x, y, z = p
        face = z > .045 and .04 < y < .207 and abs(x) < .074
        if face or (y < .088 and z > -.05):
            c = mix(SKIN, SKIN_DEEP, smoothstep(-.2, .7, fbm(x * 40, y * 40 + z * 20, seed, 2)) * .35)
            if face:
                for ex in (-.031, .031):
                    if abs(x - ex) < .011 and abs(y - .151) < .0065:
                        return EYE
                    if abs(x - ex) < .015 and abs(y - .167) < .004:
                        c = mix(c, look["hair"], .6)
                if abs(x) < .021 and abs(y - .085) < .0042:
                    return LIP
                if abs(abs(x) - .036) < .004 and .09 < y < .12:
                    c = _scale(c, .86)  # the folds from nose to mouth
            return c
        c = _cloth(look["cloth"], p, seed, .1)
        if abs(y - (.19 + .2 * z)) < .012:
            c = look["cloth_band"]  # a woven stripe across the cloth
        return c
    return surface(field, .0115, _shade(colour))


# --- arms ---------------------------------------------------------------------------------

def arm(look, shoulder, hand, pole, palm):
    """An arm in arm-local space (origin at the shoulder) reaching to `hand` (body-local).

    `palm` is the direction the fingers point from the wrist (they wrap a pole or a rim).
    Returns the mesh and the elbow and wrist used.
    """
    wrist = _sub(hand, _scale(_unit(palm), .055))
    elbow = ik(shoulder, wrist, UPPER_ARM, FOREARM, pole)
    s, e, w = (_sub(q, shoulder) for q in (shoulder, elbow, wrist))
    tip = _add(w, _scale(_unit(palm), .095))
    thumb_dir = _unit(_cross(palm, pole))
    prims = [
        Cone(s, e, .058, .049, k=.03),
        Cone(e, w, .049, .039, k=.03),
        Cone(_add(w, _scale(_unit(palm), .01)), tip, .03, .021, k=.015),
        Cone(_add(w, _scale(thumb_dir, .02)), _add(_add(w, _scale(thumb_dir, .045)), _scale(_unit(palm), .04)),
             .013, .01, k=.01),
    ]
    field = Field(prims)
    seed = look["seed"] + 13
    axis = _unit(_sub(w, e))

    def colour(p, n):
        along = sum((a - b) * c for a, b, c in zip(p, w, axis))
        if along > .004:
            return mix(SKIN, SKIN_DEEP, .35 + .3 * noise(p[0] * 60, p[1] * 60 + p[2] * 40, seed))
        to_elbow = sum((a - b) * c for a, b, c in zip(p, e, axis))
        if to_elbow > -.01:
            c = _cloth(look["sleeve"], p, seed, .1)
            if along > -.03:
                c = _scale(c, .8)  # elasticated cuff of the sleeve cover
            return c
        return _cloth(look["jacket"], p, seed)
    return surface(field, .017, _shade(colour)), elbow, wrist


# --- the tools --------------------------------------------------------------------------

def _wood(base, seed):
    def paint(p, n):
        c = mix(base, WOOD_DEEP, smoothstep(-.2, .6, fbm(p[0] * 6 + p[2] * 30, p[1] * 30, seed, 2)) * .5)
        return rgb(c)
    return paint


RAKE_BACK = .55


def rake(reach, rest_pitch):
    """A wooden grain rake in rake-local space: origin at the lower hand, the pole along +Z.

    The head is `reach` along the pole; its teeth hang plumb when the node is pitched by
    `rest_pitch` degrees.
    """
    m = PaintMesh()
    m.add(sweep([(0, 0, -RAKE_BACK), (0, 0, reach * .5), (0, 0, reach)], .017, sides=8, per=1), _wood(WOOD, 3))
    down = _rx((0, -1, 0), -rest_pitch)
    across = (1, 0, 0)
    head = (0, 0, reach)
    m.add(box((.5, .055, .045), head, .006), _wood(WOOD_DEEP, 5))
    for i in range(12):
        x = -.225 + i * .041
        c = _add(_add(head, _scale(across, x)), _scale(down, .065))
        tooth = sweep([_add(c, _scale(down, -.04)), _add(c, _scale(down, .045))], .009, sides=5, per=1)
        m.add(tooth, _wood(WOOD, 7 + i))
    for s in (-1, 1):
        m.add(sweep([(0, 0, reach - .3), _add(head, (s * .2, 0, 0))], .009, sides=5, per=1), _wood(WOOD_DEEP, 9))
    return m


def sieve(radius=.29, seed=4):
    """A round bamboo sieve, its woven floor sagging a little under a layer of grain."""
    m = PaintMesh()
    rim = [(radius * math.cos(a * math.tau / 40), .028, radius * math.sin(a * math.tau / 40)) for a in range(41)]
    m.add(cylinder(radius, .06, 40, caps=False, center=(0, .0, 0)),
          lambda p, n: rgb(mix(BAMBOO, BAMBOO_DEEP, .5 + .5 * math.sin(math.atan2(p[2], p[0]) * 40) * .4)))
    m.add(sweep(rim, .013, sides=6, per=1), lambda p, n: rgb(BAMBOO_DEEP))
    rows = []
    for j in range(13):
        r = radius * j / 12
        rows.append([(r * math.cos(a * math.tau / 32), -.026 - .02 * (1 - (j / 12) ** 2),
                      r * math.sin(a * math.tau / 32)) for a in range(33)])
    weave = PaintMesh().grid(rows, outward=(0, 1, 0))
    weave.colors = [rgb(mix(BAMBOO, GRAIN, smoothstep(.75, .3, _len((p[0], p[2])) / radius) * .85))
                    for p in weave.points]
    m.add(weave)
    # A shallow layer of grain on the weave, heaped toward the middle.
    rows = []
    for j in range(9):
        r = radius * .82 * j / 8
        rows.append([(r * math.cos(a * math.tau / 28), -.03 + .03 * (1 - (j / 8) ** 2) + .004 * noise(j * 1.7, a, seed),
                      r * math.sin(a * math.tau / 28)) for a in range(29)])
    pile = PaintMesh().grid(rows, outward=(0, 1, 0))
    pile.colors = [rgb(mix(GRAIN_DEEP, GRAIN, .45 + .55 * noise(p[0] * 50, p[2] * 50, seed + 1))) for p in pile.points]
    m.add(pile)
    return m


def basket(seed=6):
    """A woven bamboo basket of grain, standing on the ground."""
    m = PaintMesh()
    m.add(cylinder(.21, .32, 28, top=.25, caps=False, center=(0, .16, 0)),
          lambda p, n: rgb(mix(BAMBOO, BAMBOO_DEEP, .5 + .5 * math.sin(p[1] * 90) * math.sin(
              math.atan2(p[2], p[0]) * 14) * .5)))
    m.add(cylinder(.21, .02, 28, center=(0, .01, 0)), lambda p, n: rgb(BAMBOO_DEEP))
    top = [(.255 * math.cos(a * math.tau / 28), .32, .255 * math.sin(a * math.tau / 28)) for a in range(29)]
    m.add(sweep(top, .014, sides=6, per=1), lambda p, n: rgb(BAMBOO_DEEP))
    rows = []
    for j in range(7):
        r = .245 * j / 6
        rows.append([(r * math.cos(a * math.tau / 24), .3 + .035 * (1 - (j / 6) ** 2) + .006 * noise(j, a, seed),
                      r * math.sin(a * math.tau / 24)) for a in range(25)])
    g = PaintMesh().grid(rows, outward=(0, 1, 0))
    g.colors = [rgb(mix(GRAIN_DEEP, GRAIN, .5 + .5 * noise(p[0] * 40, p[2] * 40, seed))) for p in g.points]
    m.add(g)
    return m


def sack(seed=8):
    """A hemp sack of grain, slumped, its neck tied off."""
    prims = [Ell((0, .2, 0), (.2, .2, .16)), Ell((0, .1, 0), (.22, .1, .18)), Cone((0, .36, 0), (.01, .46, -.01),
                                                                                  .07, .035, k=.04)]
    field = Field(prims, floor=0.0)

    def colour(p, n):
        c = mix(HEMP, (140, 120, 86), .5 + .5 * math.sin(p[1] * 260) * math.sin(p[0] * 260 + p[2] * 260) * .5)
        if abs(p[1] - .4) < .012:
            c = (120, 92, 60)
        return c
    return surface(field, .03, _shade(colour))


def stool(seed=10):
    """A low wooden stool, 0.27 m: a plank seat on four splayed legs."""
    m = PaintMesh()
    m.add(box((.34, .035, .2), (0, .255, 0), .006), _wood(WOOD, seed))
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.add(sweep([(sx * .12, .24, sz * .055), (sx * .15, .0, sz * .08)], .016, sides=6, per=1),
                  _wood(WOOD_DEEP, seed + 1))
        m.add(box((.025, .025, .17), (sx * .135, .1, 0), .004), _wood(WOOD_DEEP, seed + 2))
    return m


# --- poses --------------------------------------------------------------------------------

def body_local(point, hip, lean):
    """Figure-local point -> body-local (the body pivots at `hip`, pitched by `lean`)."""
    return _rx(_sub(point, hip), -lean)


def figure_point(point, hip, lean):
    return _add(_rx(point, lean), hip)


# The raker's grip, figure-local: the lower (right) hand and the pole's direction.
RAKE_GRIP = (.07, .76, .58)
RAKE_DIR = _unit((0, -.64, .77))
RAKE_HEAD_Y = .1


def raker_pose():
    """Body-local hand targets for both arms, and the rake's reach and rest pitch."""
    hip = (0, HIP_STAND, 0)
    right = RAKE_GRIP
    left = _add(RAKE_GRIP, _scale(RAKE_DIR, -.25))
    reach = (right[1] - RAKE_HEAD_Y) / -RAKE_DIR[1]
    pitch = math.degrees(math.asin(-RAKE_DIR[1]))
    hands = {"R": body_local(right, hip, RAKE_LEAN), "L": body_local(left, hip, RAKE_LEAN)}
    palm = _rx(RAKE_DIR, -RAKE_LEAN)
    return hands, palm, reach, pitch


def sifter_pose():
    hip = (0, HIP_SIT, 0)
    hands = {s: body_local((sx * .27, .6, .5), hip, SIT_LEAN) for s, sx in (("L", -1), ("R", 1))}
    return hands


SIEVE_AT = (0.0, .6, .52)


def worker(kind):
    """{'Feet', 'Coat', 'Head', 'ArmL', 'ArmR'} meshes and the arm pivots (body-local)."""
    look = LOOKS[kind]
    seated = kind == "sifter"
    parts = {"Feet": feet(look, seated), "Coat": torso(look), "Head": head(look)}
    shoulders = {}
    if seated:
        hands = sifter_pose()
    else:
        hands, palm, _, _ = raker_pose()
    for side, s in (("L", -1), ("R", 1)):
        sh = (s * SHOULDER[0], SHOULDER[1], SHOULDER[2])
        if seated:
            # Fingers curl over the rim, toward the sieve's centre.
            target = hands[side]
            p = _unit(_sub(body_local(SIEVE_AT, (0, HIP_SIT, 0), SIT_LEAN), target))
            pole = (s * .8, -.6, -.2)
        else:
            target, p = hands[side], palm
            pole = (s * .9, -.4, -.3)
        mesh, _, _ = arm(look, sh, target, pole, p)
        parts["Arm" + side] = mesh
        shoulders[side] = sh
    return parts, shoulders


def _raker_grip(lean, swing, shift=0.0):
    hands, _, _, _ = raker_pose()
    shoulder = (SHOULDER[0], SHOULDER[1], SHOULDER[2])
    hand = _add(shoulder, _rx(_sub(hands["R"], shoulder), swing))
    return figure_point(hand, (0, HIP_STAND, shift), lean)


RAKE_PERIOD = 3.2
HIP_SHIFT = .045


def rake_keys(frames=8, period=RAKE_PERIOD, lean_swing=9.0):
    """[(time, lean, arm_pitch, hip_shift, grip, rake_pitch)] over one stroke, figure-local.

    She bends further from the hip and moves her weight onto the front foot to push the
    rake out, then straightens and settles back to draw it in. Her arms turn at the shoulder by whatever keeps the pole in both hands while
    the rake's teeth stay on the grain: the hands and the pole turn about parallel axes,
    so the pole stays in the grip, and the head slides out and back along the ground.
    """
    _, _, reach, rest = raker_pose()
    keys = []
    for i in range(frames + 1):
        s = math.sin(math.tau * i / frames)
        lean = RAKE_LEAN + lean_swing * s
        shift = HIP_SHIFT * s

        def miss(w):
            grip = _raker_grip(lean, w, shift)
            return grip[1] - reach * math.sin(math.radians(rest + lean - RAKE_LEAN + w)) - RAKE_HEAD_Y
        lo, hi = -45.0, 45.0
        for _ in range(60):
            mid = (lo + hi) / 2
            if (miss(lo) > 0) == (miss(mid) > 0):
                lo = mid
            else:
                hi = mid
        w = (lo + hi) / 2
        keys.append((period * i / frames, lean, w, shift, _raker_grip(lean, w, shift), rest + lean - RAKE_LEAN + w))
    return keys


SIFT_PERIOD = 1.2


def sift_keys(frames=8, sway=5.0):
    """[(time, arm_yaw, sieve_offset)] for a shake of the sieve, body-local.

    Both arms turn the same few degrees about the vertical at the shoulder; the sieve moves
    by the mean of the two hands, so it stays in her fingers as it swings side to side.
    """
    hands = sifter_pose()
    keys = []
    for i in range(frames + 1):
        a = sway * math.sin(math.tau * i / frames)
        moves = []
        for side, sx in (("L", -1), ("R", 1)):
            sh = (sx * SHOULDER[0], SHOULDER[1], SHOULDER[2])
            rel = _sub(hands[side], sh)
            moves.append(_sub(_ry(rel, a), rel))
        offset = _scale(_add(*moves), .5)
        keys.append((SIFT_PERIOD * i / frames, a, offset))
    return keys
