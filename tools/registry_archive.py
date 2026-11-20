"""The archive as a registry of student files, school rules and inspection dossiers
(2026-11-20, revised 2026-11-21; docs/OFFICE_ARCHIVE_ART.md).

Nothing in the room is named. The files outgrow the room and pass the top of the wall,
each bundle with a blank photo; a rule gate recedes into the west wall clause by clause
(1, 1.1, 1.1.1, ...) with light at its seam, watched by an empty uniform on a stand while
one student waits on a stool. Students wait on a bench with the same number, an
inspection desk stands taller than the wall with nobody at it while its oversized stamp
keeps stamping and a lens hangs over the room, report cards and uniforms dry on a line,
and one continuous form unrolls from the files across the floor to the door.

Additive set dressing: no exit, spawn, inspection or route moves. The few colliders
added (bench, the uniform stand, the student's stool, the inspection desk) keep the
footprints of the first version, against the west and north walls, away from the door,
the index desk and the reading stance.
"""
from __future__ import annotations

import math
import random

from build_school_rooms import label
from build_teaching_block import child_path, vec3
from dream_figures import PEOPLE, figure, motion_material, part
from dressing_geometry import Batch, prism

REGISTRY = {
    "file_buff": (196, 170, 120), "file_grey": (146, 138, 122), "file_green": (106, 120, 94),
    "file_rose": (170, 118, 104), "file_string": (214, 198, 160), "dossier_dark": (92, 78, 64),
    "bench": (98, 72, 54), "bench_dark": (66, 50, 40), "photo": (176, 178, 180), "photo_dark": (118, 120, 124),
    "gate_frame": (70, 52, 44), "gate_1": (58, 46, 44), "gate_2": (40, 32, 32), "gate_3": (22, 18, 20),
    "shirt": (226, 220, 204), "shirt_blue": (156, 176, 196), "line": (60, 56, 52), "plaque": (196, 160, 92),
    "armband": (186, 48, 44), "greenbar": (204, 222, 196), "glass": (196, 216, 222),
    "tab_pink": (238, 152, 166), "tab_mint": (124, 204, 182), "tab_lemon": (242, 211, 82),
    "tab_cobalt": (42, 80, 172), "bag_navy": (44, 54, 80), "bag_red": (150, 62, 56),
}
WALL_W = -4.305          # inner face of the west wall
GATE_Z = -1.7
# The four map cases along the north wall (see build_school_annexes.archive).
CASES = [(-3.66 + .98 * i, 1.68 + (i % 2) * .28) for i in range(4)]
FILE_TONES = ("file_buff", "file_grey", "file_green", "file_rose", "dossier_dark", "file_buff")
INSPECTION_TONES = ("file_rose", "dossier_dark", "file_rose", "file_grey")
TABS = ("tab_pink", "tab_mint", "tab_lemon", "tab_cobalt")
STUDENT = {"coat": "uniform", "legs": "trouser", "hair": "hair"}


def _stack(batch, rng, x, z, bottom, top, *, width=(.34, .42), depth=(.28, .36), lean=.012,
           tones=FILE_TONES, string="file_string"):
    """Tied bundles, one on another, drifting as they rise; some show a blank photo or a tab."""
    y, dx, dz = bottom, 0.0, 0.0
    while y < top:
        h = rng.uniform(.07, .16)
        w, d = rng.uniform(*width), rng.uniform(*depth)
        yaw = rng.uniform(-8, 8)
        centre = (x + dx, y + h / 2, z + dz + rng.uniform(0, .05))
        batch.box(rng.choice(tones), centre, (w, h, d), (0, yaw, 0))
        batch.box(string, centre, (.014, h + .006, d + .006), (0, yaw, 0))
        if rng.random() < .45:
            batch.box("paper", (centre[0], y + h * rng.uniform(.3, .7), centre[2] + .02),
                      (w * .86, .006, d * 1.12), (0, yaw + rng.uniform(-9, 9), 0))
        roll = rng.random()
        if roll < .22 and h > .1:
            # A student file: a passport photo with no face, clipped to the front.
            front = math.radians(yaw)
            off = (-w * .25, d / 2 + .003)
            px = centre[0] + off[0] * math.cos(front) + off[1] * math.sin(front)
            pz = centre[2] - off[0] * math.sin(front) + off[1] * math.cos(front)
            batch.box("photo", (px, centre[1], pz), (.055, min(.07, h * .7), .004), (0, yaw, 0))
        elif roll < .5:
            batch.box(rng.choice(TABS), (centre[0] + w / 2 * rng.choice((-1, 1)), centre[1], centre[2]),
                      (.05, .028, .07), (0, yaw, 0))
        dx += rng.uniform(-lean, lean)
        dz += rng.uniform(-lean, lean * .6)
        y += h


def file_mountain(b, parent):
    """Student files piled on the map cases until they pass the top of the wall."""
    rng = random.Random(1914)
    batch = Batch()
    for i, (x, top) in enumerate(CASES):
        for k, offset in enumerate((-.22, .22)):
            _stack(batch, rng, x + offset, -3.02, top, rng.uniform(3.3, 4.4) - .3 * (k == i % 2))
    for x, z, height in ((-.42, -2.36, 1.32), (-.85, -2.42, .82), (-3.62, 2.98, .66), (-2.3, 3.08, .48)):
        _stack(batch, rng, x, z, 0, height, lean=.02)
    # Inspection dossiers by the inspection desk: red-banded, heavier, leaning more.
    for x, z, height in ((4.0, -1.25, 1.06), (3.95, -.62, .58), (4.05, -.02, .3)):
        _stack(batch, rng, x, z, 0, height, lean=.03, tones=INSPECTION_TONES, string="armband")
    # A library ladder leans into the stacks; nobody could climb it to the top.
    base, rise, lean = (-2.2, 0, -2.25), 3.4, -.45
    pitch = math.degrees(math.atan2(lean, rise))
    length = math.hypot(rise, lean)
    for side in (-.2, .2):
        batch.box("wood", (base[0] + side, rise / 2, base[2] + lean / 2), (.05, length, .05), (pitch, 0, 0))
    for k in range(1, 11):
        t = k / 11
        batch.box("wood_light", (base[0], rise * t, base[2] + lean * t), (.4, .03, .035))
    batch.emit(b, "Files", parent, shadow=True)


def _offset(path, d):
    """The polyline moved sideways by d (mitred at each corner)."""
    out = []
    for i, (x, z) in enumerate(path):
        nx = nz = 0.0
        for a, c in ((path[max(i - 1, 0)], path[i]), (path[i], path[min(i + 1, len(path) - 1)])):
            length = math.hypot(c[0] - a[0], c[1] - a[1])
            if length > 1e-6:
                nx += -(c[1] - a[1]) / length
                nz += (c[0] - a[0]) / length
        n = math.hypot(nx, nz) or 1
        out.append((x + nx / n * d, z + nz / n * d))
    return out


def _resample(path, step):
    points = [path[0]]
    for (x0, z0), (x1, z1) in zip(path, path[1:]):
        n = max(1, round(math.hypot(x1 - x0, z1 - z0) / step))
        points += [(x0 + (x1 - x0) * k / n, z0 + (z1 - z0) * k / n) for k in range(1, n + 1)]
    return points


def continuous_form(b, parent):
    """The permanent record: one fan-fold printout unrolling from the files to the door."""
    path = _resample(((-.62, -2.1), (-.78, -1.2), (-1.7, -.35), (-1.55, .75), (-.4, 1.55), (.9, 2.05),
                      (1.75, 2.7), (2.18, 3.28)), .16)
    batch = Batch()
    y = .024
    for k, seg in enumerate(zip(path, path[1:])):
        batch.strip("greenbar" if k % 4 < 2 else "white", list(seg), .32, y)
    for side in (-.13, .13):
        for x, z in _offset(path, side):
            batch.chip("edge", (x, z), .011, 6, 0, y + .001)
    # Fold creases every so often, and the roll it came from, still feeding.
    for k in range(3, len(path) - 1, 6):
        (x0, z0), (x1, z1) = path[k], path[k + 1]
        yaw = math.degrees(math.atan2(x1 - x0, z1 - z0))
        batch.box("file_grey", (x0, y + .001, z0), (.3, .002, .006), (0, yaw, 0))
    batch.emit(b, "ContinuousForm", parent)
    b.round("FormRoll", parent, (-.62, .17, -2.1), .15, .4, "white", rot=(0, 0, 90), sides=14)
    b.round("FormCore", parent, (-.62, .17, -2.1), .04, .42, "edge", rot=(0, 0, 90), sides=8)


def rule_gate(b, parent):
    """The school rules as a gate: clause inside clause, stepping into darkness, light at the seam."""
    g = child_path(parent, "RuleGate")
    b.node("RuleGate", parent, position=vec3((WALL_W, 0, GATE_Z)))
    # (width, height, sill, protrusion, frame, opening backing)
    levels = ((1.16, 3.15, 0, .18, "gate_frame", "gate_1"), (.90, 2.50, .10, .12, "gate_frame", "gate_2"),
              (.68, 2.00, .18, .08, "gate_1", "gate_3"), (.46, 1.60, .24, .05, "gate_2", "gate_3"))
    batch = Batch()
    for i, (w, h, sill, out, frame, back) in enumerate(levels):
        for side in (-1, 1):
            batch.box(frame, (out / 2, sill + h / 2, side * (w / 2 - .05)), (out, h, .1))
        batch.box(frame, (out / 2, sill + h - .05, 0), (out, .1, w))
        batch.box(back, (.004 + .004 * i, sill + h / 2, 0), (.008, h - .1, w - .1))
        if i:
            # A step up into each smaller frame, deepest at the room.
            batch.box("gate_frame", ((.62 - .14 * i) / 2, sill / 2, 0), (.62 - .14 * i, sill, w + .04))
        # Each frame is a sub-clause of the one around it.
        label(b, f"Clause{i}", g, (out + .004, sill + h - .05, 0), ".".join("1" * (i + 1)),
              .0016 - .00025 * i, (0, 90, 0), (214, 186, 132))
    w, h, sill = .46, 1.60, .24
    batch.box("gate_3", (.034, sill + (h - .1) / 2, 0), (.02, h - .14, w - .14))
    batch.emit(b, "Frames", g, shadow=True)
    for name, centre, size in (("SeamFoot", (.05, sill + .012, 0), (.01, .012, w - .1)),
                               ("SeamL", (.05, sill + (h - .1) / 2, -(w - .12) / 2), (.01, h - .16, .01)),
                               ("SeamR", (.05, sill + (h - .1) / 2, (w - .12) / 2), (.01, h - .16, .01)),
                               ("Keyhole", (.05, sill + .72, .1), (.01, .04, .018))):
        b.box(name, g, centre, size, "seam_glow")
    # The light spills over the steps onto the floor, the one warm thing in the room.
    spill = Batch()
    spill.strip("seam_glow", [(.62, 0), (1.9, 0)], .3, .0065)
    spill.strip("seam_glow", [(1.9, 0), (2.5, 0)], .14, .0065)
    for i, (sill, depth) in enumerate(((.10, .48), (.18, .34), (.24, .20))):
        spill.strip("seam_glow", [(depth - .1, 0), (depth + .001, 0)], .2, sill + .002)
    spill.emit(b, "Spill", g)
    b.detail("Pediment", g, (.09, 3.15, 0), prism(((-.72, 0), (.72, 0), (0, .38)), .18), "gate_frame",
             rot=(0, 90, 0), shadow=True)
    label(b, "Section", g, (.012, 2.84, 0), "§", .0042, (0, 90, 0), (214, 186, 132))
    # Beside it, a blank student card in a brass frame: a photo with no face, lines with no name.
    b.box("Card", g, (.008, 1.45, -.8), (.01, .24, .4), "plaque")
    b.box("CardFace", g, (.014, 1.45, -.8), (.004, .2, .36), "paper")
    b.box("CardPhoto", g, (.018, 1.45, -.91), (.004, .15, .11), "photo")
    b.box("CardHead", g, (.021, 1.47, -.91), (.003, .05, .045), "photo_dark")
    b.box("CardShoulders", g, (.021, 1.405, -.91), (.003, .04, .085), "photo_dark")
    for k, y in enumerate((1.5, 1.45, 1.4)):
        b.box(f"CardLine{k}", g, (.018, y, -.74), (.004, .01, .17 - .04 * (k == 2)), "line")

    # The guard is a uniform on a stand: jacket, armband and whistle, nobody inside.
    q = b.shell("UniformStand", parent, (-3.72, 0, -.9), (0, 90, 0))
    b.shape("Body", q, (0, .95, 0), (.6, 1.9, .6))
    for name, centre, size, pigment in (
        ("Foot", (0, .02, 0), (.46, .04, .46), "bench_dark"),
        ("Pole", (0, .86, 0), (.04, 1.68, .04), "bench_dark"),
        ("Hanger", (0, 1.5, 0), (.5, .03, .04), "wood_light"),
        ("Hook", (0, 1.73, 0), (.02, .1, .02), "brass"),
        ("Jacket", (0, 1.2, 0), (.46, .6, .25), "uniform"),
        ("Collar", (0, 1.49, .03), (.3, .07, .2), "uniform"),
        ("Neck", (0, 1.5, .03), (.15, .075, .12), "gate_3"),
        ("Placket", (0, 1.2, .127), (.04, .56, .006), "sleeve_white"),
        ("SleeveL", (-.27, 1.14, 0), (.1, .58, .12), "uniform"),
        ("SleeveR", (.27, 1.14, 0), (.1, .58, .12), "uniform"),
        ("Armband", (-.27, 1.28, 0), (.112, .1, .132), "armband"),
        ("Trousers", (0, .62, 0), (.36, .36, .14), "trouser"),
    ):
        b.box(name, q, centre, size, pigment, shadow=size[1] > .1)
    for k, (x, y) in enumerate(((-.06, 1.42), (.06, 1.42), (.09, 1.28))):
        b.box(f"Lanyard{k}", q, (x * .7, y - .05, .13), (.012, .12, .006), "armband", rot=(0, 0, 20 - 20 * k))
    b.box("Whistle", q, (.07, 1.22, .14), (.05, .025, .03), "brass")

    # One student waits before the gate on a stool, nodding off, satchel at the feet.
    seat = (-3.1, 0, -2.3)
    yaw = math.degrees(math.atan2(WALL_W - seat[0], GATE_Z - seat[2]))
    stool = b.shell("WaitingStool", parent, seat, (0, yaw, 0))
    b.shape("Body", stool, (0, .55, .1), (.62, 1.1, .78))
    b.box("Seat", stool, (0, .42, -.02), (.36, .04, .36), "bench", shadow=True)
    for k in range(3):
        a = math.tau * k / 3 + .5
        b.box(f"Leg{k}", stool, (.13 * math.cos(a), .2, -.02 + .13 * math.sin(a)), (.035, .4, .035), "bench_dark")
    figure(b, stool, "Student", (0, 0, 0), 0, {**STUDENT, "droop": True}, body="nod", phase=.31)
    b.box("Satchel", stool, (.28, .14, .3), (.12, .28, .3), "bag_navy", shadow=True)
    b.box("SatchelFlap", stool, (.28, .23, .3), (.13, .1, .31), "bag_red")


def waiting_bench(b, parent):
    """A bench of students with their files, satchels on hooks, the same number for everyone."""
    bench = b.shell("WaitingBench", parent, (-4.07, 0, 1.4))
    b.shape("Body", bench, (0, .45, 0), (.46, .9, 3.1))
    b.box("Seat", bench, (.02, .42, 0), (.42, .05, 3.1), "bench", shadow=True)
    b.box("Rail", bench, (.2, .36, 0), (.04, .1, 3.08), "bench_dark")
    b.box("Back", bench, (-.2, .74, 0), (.04, .32, 3.1), "bench", shadow=True)
    for k, z in enumerate((-1.45, -.5, .5, 1.45)):
        b.box(f"Leg{k}", bench, (0, .2, z), (.36, .4, .05), "bench_dark", shadow=True)
    hairs = ("hair", "hair", "hair_grey", "hair")
    bags = ("bag_navy", "bag_red", "tab_cobalt", "bag_navy")
    for k, z in enumerate((.2, .95, 1.75, 2.55)):
        nods = k in (1, 3)
        p = figure(b, parent, f"Student{k}", (-4.1, 0, z), 90, {**STUDENT, "hair": hairs[k], "droop": True},
                   pose="sit", body="nod" if nods else None, phase=.17 * k)
        if nods:
            b.box(f"Papers{k}", bench, (.06, .452, z - 1.4 + .27), (.22, .008, .3), "paper", rot=(0, 12 * k, 0))
        else:
            b.box("File", p, (0, 1.08, .45), (.26, .2, .012), "file_buff", rot=(-24, 0, 0))
            b.box("FilePhoto", p, (-.07, 1.1, .452), (.05, .06, .004), "photo", rot=(-24, 0, 0))
        b.box(f"Hook{k}", parent, (-4.27, 1.93, z), (.06, .025, .025), "brass")
        b.box(f"Bag{k}", parent, (-4.23, 1.7, z), (.12, .34, .28), bags[k], shadow=True)
        b.box(f"BagFlap{k}", parent, (-4.165, 1.79, z), (.01, .14, .26), "bag_red" if k % 2 == 0 else "tab_mint")
        b.box(f"Strap{k}", parent, (-4.24, 1.89, z), (.02, .08, .04), "bench_dark")
        b.box(f"NumberCard{k}", parent, (WALL_W + .006, 1.36, z), (.01, .12, .16), "paper")
        label(b, f"Number{k}", parent, (WALL_W + .013, 1.36, z), "17", .0019, (0, 90, 0), (40, 49, 66))
    figure(b, parent, "Latecomer", (-2.95, 0, 2.95), 180, {**STUDENT, "droop": True},
           pose="bowed", body="nod", phase=.6)
    # The rules, pinned up in layers: forms over forms, ticked and crossed, none legible.
    b.box("NoticeBoard", parent, (WALL_W + .006, 2.4, 1.4), (.012, .5, 2.5), "ink")
    rng = random.Random(1983)
    pins = Batch()
    for k in range(13):
        z, y = rng.uniform(.3, 2.5), rng.uniform(2.24, 2.56)
        tilt = rng.uniform(-9, 9)
        x = WALL_W + .014 + .001 * k
        pins.box("paper" if k % 3 else "cream", (x, y, z), (.002, .2, .15), (tilt, 0, 0))
        for r in range(3):
            pins.box("line", (x + .002, y + .05 - .04 * r, z + .02), (.002, .008, .08), (tilt, 0, 0))
        mark = "armband" if k % 4 else "tab_cobalt"
        pins.box(mark, (x + .003, y - .07, z - .045), (.002, .012, .03), (tilt - 40, 0, 0))
        pins.box(mark, (x + .003, y - .06, z - .02), (.002, .012, .05), (tilt + 50, 0, 0))
        pins.box("red", (x + .004, y + .085, z), (.006, .018, .018))
    pins.emit(b, "Notices", parent)
    # One bare bulb on a long flex over the bench; no fitting, no ceiling.
    b.box("Flex", parent, (-3.4, 3.1, 1.3), (.008, 1.5, .008), "line")
    b.round("Bulb", parent, (-3.4, 2.32, 1.3), .045, .09, "seam_glow", sides=10)
    b.node("BulbLight", parent, "OmniLight3D", position=vec3((-3.4, 2.24, 1.3)),
           light_color="Color(1, 0.86, 0.6, 1)", light_energy=.38, omni_range=3.4)


def inspection_desk(b, parent):
    """An inspection desk taller than the wall. Nobody sits at it; its stamp keeps stamping."""
    d = b.shell("InspectionDesk", parent, (3.62, 0, -2.62))
    b.shape("Body", d, (0, 1.3, 0), (1.28, 2.6, 1.36))
    for name, centre, size, pigment in (
        ("Plinth", (0, .225, 0), (1.36, .45, 1.40), "bench_dark"),
        ("Step", (-.3, .11, .84), (.5, .22, .3), "bench"),
        ("Front", (0, 1.525, .64), (1.28, 2.15, .08), "wood"),
        ("SideL", (-.61, 1.525, .2), (.06, 2.15, .9), "wood"),
        ("SideR", (.61, 1.525, .2), (.06, 2.15, .9), "wood"),
    ):
        b.box(name, d, centre, size, pigment, shadow=True)
    for k in range(3):
        b.box(f"Panel{k}", d, (-.4 + .4 * k, 1.42, .69), (.32, 1.55, .02), "wood_light")
    b.box("Top", d, (0, 2.66, .38), (1.42, .06, .66), "wood_light", rot=(-12, 0, 0), shadow=True)
    b.box("Register", d, (-.2, 2.73, .46), (.64, .09, .52), "navy", rot=(-12, 0, 0), shadow=True)
    # A checklist hangs over the front: rows of boxes, almost all ticked in red, one never.
    sheet = Batch()
    sheet.box("ledger", (-.15, 2.2, .7), (.52, 1.0, .006))
    for r in range(9):
        y = 2.6 - r * .1
        sheet.box("ink", (-.36, y, .705), (.05, .05, .004))
        sheet.box("paper", (-.36, y, .708), (.036, .036, .002))
        sheet.box("line", (-.1, y, .706), (.32 - .06 * (r % 3), .01, .002))
        if r != 6:
            sheet.box("armband", (-.37, y - .008, .711), (.012, .03, .002), (0, 0, 40))
            sheet.box("armband", (-.35, y + .004, .711), (.012, .05, .002), (0, 0, -35))
    sheet.emit(b, "Checklist", d)
    # The stamp is as big as a head and works by itself on its pad.
    b.box("Pad", d, (.36, 2.75, .36), (.36, .03, .3), "red", rot=(-12, 0, 0))
    stamp = motion_material(b, "armband", "stamp", phase=0.0)
    grip = motion_material(b, "bench_dark", "stamp", phase=0.0)
    knob = motion_material(b, "brass", "stamp", phase=0.0)
    part(b, "StampFoot", d, (.36, 2.86, .32), (.3, .07, .24), stamp, shadow=True)
    part(b, "StampBlock", d, (.36, 2.95, .32), (.22, .1, .17), grip, shadow=True)
    part(b, "StampGrip", d, (.36, 3.12, .32), (.07, .24, .07), grip)
    part(b, "StampKnob", d, (.36, 3.28, .32), (.15, .09, .15), knob, shadow=True)
    b.round("LampFoot", d, (-.56, 2.72, .1), .07, .03, "brass", sides=12)
    b.round("LampStem", d, (-.56, 2.86, .1), .012, .28, "brass", sides=8)
    b.round("LampShade", d, (-.56, 2.99, .16), .1, .09, "teal", top=.05, sides=12, rot=(30, 0, 0))
    b.box("Nameplate", d, (0, 2.0, .685), (.78, .16, .01), "plaque")
    b.box("NameplateBlank", d, (0, 2.0, .691), (.66, .08, .004), "bench_dark")
    # The tall stool behind it, empty.
    seat = 2.16
    for k, (x, z) in enumerate(((-.17, -.4), (.17, -.4), (-.17, -.06), (.17, -.06))):
        b.box(f"StoolLeg{k}", d, (x, (.45 + seat) / 2, z), (.04, seat - .45, .04), "bench_dark")
    b.box("StoolSeat", d, (0, seat + .02, -.23), (.44, .05, .44), "bench")
    for k, y in enumerate((.9, 1.5)):
        b.box(f"StoolRung{k}", d, (0, y, -.23), (.38, .03, .03), "bench_dark")
    # A magnifying lens on a long jointed arm, leaning out over the room toward the door.
    arm = Batch()
    joints = ((.58, 2.7, -.2), (.7, 3.55, -.05), (.25, 3.85, .75))
    for (x0, y0, z0), (x1, y1, z1) in zip(joints, joints[1:]):
        length = math.dist((x0, y0, z0), (x1, y1, z1))
        dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
        yaw = math.degrees(math.atan2(dx, dz))
        pitch = math.degrees(math.atan2(math.hypot(dx, dz), dy))
        arm.box("brass", ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (.035, length, .035), (pitch, yaw, 0))
    arm.emit(b, "LensArm", d)
    for k, centre in enumerate(joints):
        b.box(f"Joint{k}", d, centre, (.07, .07, .07), "bench_dark")
    lens = (.15, 3.7, 1.0)
    b.round("LensRim", d, lens, .34, .04, "brass", rot=(55, -20, 0), sides=24, shadow=True)
    b.round("Lens", d, lens, .3, .05, "glass", rot=(55, -20, 0), sides=24)
    # The clerk's ladder, leaning on the side panel.
    for side in (-.18, .18):
        b.box(f"LadderRail{side > 0:d}", d, (-.755, 1.25, .3 + side), (.045, 2.51, .045), "wood_light",
              rot=(0, 0, -4.3))
    for k in range(1, 8):
        b.box(f"LadderRung{k}", d, (-.85 + .19 * k / 8.3, .31 * k, .3), (.045, .03, .36), "wood_light")


def drying_line(b, parent):
    """Report cards and uniforms pegged out to dry, from the west wall to the inspection desk."""
    start, end, sag = (WALL_W, 2.62), (2.98, 2.6), .22
    z = -2.42
    batch = Batch()

    def at(t):
        return (start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t - sag * 4 * t * (1 - t))

    for k in range(10):
        (x0, y0), (x1, y1) = at(k / 10), at((k + 1) / 10)
        batch.box("line", ((x0 + x1) / 2, (y0 + y1) / 2, z), (math.hypot(x1 - x0, y1 - y0), .008, .008),
                  (0, 0, math.degrees(math.atan2(y1 - y0, x1 - x0))))
    for t, kind in ((.09, "shirt"), (.19, "card"), (.28, "jacket"), (.39, "card"), (.5, "timetable"),
                    (.61, "file"), (.71, "shirt_blue"), (.82, "card"), (.9, "file")):
        x, y = at(t)
        batch.box("wood_light", (x, y - .01, z), (.022, .06, .026))
        if kind == "file":
            batch.box("file_buff", (x, y - .14, z + .006), (.32, .26, .01), (0, 0, 4))
            batch.box("photo", (x - .09, y - .13, z + .013), (.06, .075, .004), (0, 0, 4))
            batch.box("paper", (x + .01, y - .17, z + .014), (.27, .22, .004), (0, 0, -3))
        elif kind == "card":
            # A report card: a grid of grades with nothing written in.
            batch.box("cream", (x, y - .2, z), (.3, .38, .008), (0, 0, -2))
            for r in range(5):
                batch.box("line", (x, y - .07 - .065 * r, z + .006), (.26, .008, .002))
            batch.box("line", (x + .05, y - .2, z + .006), (.008, .3, .002))
            batch.box("armband", (x + .1, y - .2 - .065 * (round(t * 10) % 3), z + .007), (.04, .03, .002))
        elif kind == "timetable":
            batch.box("white", (x, y - .38, z), (.95, .74, .01), (0, 0, 1))
            for c in range(1, 6):
                batch.box("line", (x - .475 + c * .158, y - .38, z + .007), (.008, .7, .002))
            for r in range(1, 8):
                batch.box("line", (x, y - .01 - r * .092, z + .007), (.92, .008, .002))
            for c, r, pigment in ((1, 2, "tab_pink"), (3, 4, "tab_mint"), (4, 1, "tab_lemon"), (2, 6, "tab_cobalt")):
                batch.box(pigment, (x - .475 + (c + .5) * .158, y - .01 - (r + .5) * .092, z + .008),
                          (.14, .075, .002))
        else:
            colour = {"jacket": "uniform"}.get(kind, kind)
            batch.box(colour, (x, y - .3, z), (.44, .54, .012))
            for side in (-1, 1):
                batch.box(colour, (x + side * .27, y - .17, z), (.16, .27, .012), (0, 0, side * 28))
            if kind == "jacket":
                batch.box("armband", (x - .31, y - .2, z + .008), (.1, .06, .004), (0, 0, -28))
    batch.emit(b, "DryingLine", parent)


def paper_drifts(b, parent):
    """Forms and carbons drifted against the bench, the gate steps and the inspection desk."""
    rng = random.Random(1925)
    batch = Batch()
    tones = ("paper", "cream", "white", "file_buff", "paper")
    for (x0, x1, z0, z1), count in (((-3.9, -2.9, -.3, 3.2), 34), ((-3.8, -2.6, -2.4, -1.0), 22),
                                    ((2.6, 4.2, -1.9, -.9), 20), ((-4.1, .2, 2.7, 3.3), 26), ((-1.2, .2, -2.6, -2.0), 12)):
        layer = 0
        for _ in range(count):
            layer += 1
            x, z = rng.uniform(x0, x1), rng.uniform(z0, z1)
            batch.box(rng.choice(tones), (x, .004 + .0028 * (layer % 9), z), (.21, .002, .297),
                      (rng.uniform(-4, 4), rng.uniform(0, 180), 0))
        for _ in range(count // 6):
            batch.box("paper", (rng.uniform(x0, x1), .035, rng.uniform(z0, z1)), (.07, .06, .07),
                      (rng.uniform(0, 90), rng.uniform(0, 90), rng.uniform(0, 90)))
    batch.emit(b, "Drifts", parent)


def queue_post(b, parent):
    """A number dispenser by the door. It only ever issues 17."""
    q = child_path(parent, "QueuePost")
    b.node("QueuePost", parent, position=vec3((1.12, 0, 3.2)))
    b.round("Pole", q, (0, .6, 0), .025, 1.2, "edge", sides=8)
    b.round("Foot", q, (0, .015, 0), .16, .03, "edge", sides=12)
    b.box("Dispenser", q, (0, 1.28, 0), (.2, .22, .14), "red", shadow=True)
    b.box("Ticket", q, (0, 1.12, .072), (.07, .12, .004), "paper", rot=(-8, 0, 0))
    label(b, "TicketNumber", q, (0, 1.11, .076), "17", .0012, (-8, 0, 0), (40, 49, 66))
    label(b, "Take", q, (0, 1.3, .072), "取号  TAKE A NUMBER", .0007, ink=(240, 226, 196))


def index_desk(b, desk):
    """A stamp carousel and a spike of slips on the index desk, clear of the ledger."""
    b.box("StampRack", desk, (-.9, .805, -.3), (.44, .03, .13), "wood")
    for k in range(5):
        x = -1.08 + k * .09
        b.box(f"StampFoot{k}", desk, (x, .838, -.3), (.05, .036, .04), "edge")
        b.round(f"StampGrip{k}", desk, (x, .89, -.3), .018, .07, ("ink", "red", "ink", "brass", "ink")[k], sides=8)
    b.round("Spike", desk, (.98, .87, -.36), .004, .16, "brass", sides=6)
    b.round("SpikeFoot", desk, (.98, .8, -.36), .05, .02, "edge", sides=10)
    for k in range(7):
        b.box(f"Spiked{k}", desk, (.98, .815 + .012 * k, -.36), (.11, .002, .08), "paper", rot=(0, 23 * k, 0))


def registry_archive(b):
    b.pigments.update({k: v for k, v in {**PEOPLE, **REGISTRY}.items() if k not in b.pigments})
    b.mat("seam_glow", shading_mode=0, albedo_color="Color(1, 0.93, 0.74, 1)")
    r = "Registry"
    b.node(r, ".")
    file_mountain(b, r)
    continuous_form(b, r)
    rule_gate(b, r)
    waiting_bench(b, r)
    inspection_desk(b, r)
    drying_line(b, r)
    paper_drifts(b, r)
    queue_post(b, r)
