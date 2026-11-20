"""The archive as the court offices of Kafka's *The Trial* (2026-11-20; docs/OFFICE_ARCHIVE_ART.md).

An attic-like registry where the files outgrow the room: dossier stacks rise past
the top of the wall, petitioners wait on a bench under their hats, all holding the
same number. A magistrate stamps from a desk set absurdly high, laundry hangs from
his desk to the far wall, and paper drifts against every footing. On the west wall a
nested gate that was "made only for you" glows at its seams behind its doorkeeper.

Additive set dressing: no exit, spawn, inspection or route moves. The few
colliders added (bench, gatekeeper, the country man's stool, the high desk) stand
against the west and north walls, away from the door, the index desk and the
reading stance.
"""
from __future__ import annotations

import math
import random

from build_school_rooms import label
from build_teaching_block import child_path, vec3
from dream_figures import PEOPLE, figure, motion_material, part
from dressing_geometry import Batch, prism

TRIAL = {
    "file_buff": (196, 170, 120), "file_grey": (146, 138, 122), "file_green": (106, 120, 94),
    "file_rose": (170, 118, 104), "file_string": (214, 198, 160), "dossier_dark": (92, 78, 64),
    "bench": (98, 72, 54), "bench_dark": (66, 50, 40), "fur": (96, 72, 52), "fur_light": (138, 108, 78),
    "beard": (26, 24, 26), "hat": (38, 36, 40), "law_frame": (70, 52, 44), "law_1": (58, 46, 44),
    "law_2": (40, 32, 32), "law_3": (22, 18, 20), "shirt": (226, 220, 204), "shirt_blue": (156, 176, 196),
    "dress_red": (168, 72, 70), "line": (60, 56, 52), "plaque": (196, 160, 92),
}
WALL_W = -4.305          # inner face of the west wall
GATE_Z = -1.7
# The four map cases along the north wall (see build_school_annexes.archive).
CASES = [(-3.66 + .98 * i, 1.68 + (i % 2) * .28) for i in range(4)]
FILE_TONES = ("file_buff", "file_grey", "file_green", "file_rose", "dossier_dark", "file_buff")


def _stack(batch, rng, x, z, bottom, top, *, width=(.34, .42), depth=(.28, .36), lean=.012):
    """Tied bundles, one on another, drifting as they rise."""
    y, dx, dz = bottom, 0.0, 0.0
    while y < top:
        h = rng.uniform(.07, .16)
        w, d = rng.uniform(*width), rng.uniform(*depth)
        yaw = rng.uniform(-8, 8)
        centre = (x + dx, y + h / 2, z + dz + rng.uniform(0, .05))
        batch.box(rng.choice(FILE_TONES), centre, (w, h, d), (0, yaw, 0))
        batch.box("file_string", centre, (.014, h + .006, d + .006), (0, yaw, 0))
        if rng.random() < .45:
            batch.box("paper", (centre[0], y + h * rng.uniform(.3, .7), centre[2] + .02),
                      (w * .86, .006, d * 1.12), (0, yaw + rng.uniform(-9, 9), 0))
        dx += rng.uniform(-lean, lean)
        dz += rng.uniform(-lean, lean * .6)
        y += h


def dossier_mountain(b, parent):
    """Files piled on the map cases until they pass the top of the wall."""
    rng = random.Random(1914)
    batch = Batch()
    for i, (x, top) in enumerate(CASES):
        for k, offset in enumerate((-.22, .22)):
            _stack(batch, rng, x + offset, -3.02, top, rng.uniform(3.3, 4.4) - .3 * (k == i % 2))
    for x, z, height in ((-.42, -2.36, 1.32), (-.85, -2.42, .82), (-3.62, 2.98, .66), (-2.3, 3.08, .48),
                         (4.0, -1.25, .86), (3.95, -.62, .4)):
        _stack(batch, rng, x, z, 0, height, lean=.02)
    # A library ladder leans into the stacks; nobody could climb it to the top.
    base, rise, lean = (-2.2, 0, -2.25), 3.4, -.45
    pitch = math.degrees(math.atan2(lean, rise))
    length = math.hypot(rise, lean)
    for side in (-.2, .2):
        batch.box("wood", (base[0] + side, rise / 2, base[2] + lean / 2), (.05, length, .05), (pitch, 0, 0))
    for k in range(1, 11):
        t = k / 11
        batch.box("wood_light", (base[0], rise * t, base[2] + lean * t), (.4, .03, .035))
    batch.emit(b, "Dossiers", parent, shadow=True)


def law_gate(b, parent):
    """Before the Law: frames nested into darkness, stepped up into the wall, light at the seam."""
    g = child_path(parent, "LawGate")
    b.node("LawGate", parent, position=vec3((WALL_W, 0, GATE_Z)))
    # (width, height, sill, protrusion, frame, opening backing)
    levels = ((1.16, 3.15, 0, .18, "law_frame", "law_1"), (.90, 2.50, .10, .12, "law_frame", "law_2"),
              (.68, 2.00, .18, .08, "law_1", "law_3"), (.46, 1.60, .24, .05, "law_2", "law_3"))
    batch = Batch()
    for i, (w, h, sill, out, frame, back) in enumerate(levels):
        for side in (-1, 1):
            batch.box(frame, (out / 2, sill + h / 2, side * (w / 2 - .05)), (out, h, .1))
        batch.box(frame, (out / 2, sill + h - .05, 0), (out, .1, w))
        batch.box(back, (.004 + .004 * i, sill + h / 2, 0), (.008, h - .1, w - .1))
        if i:
            # A step up into each smaller frame, deepest at the room.
            batch.box("law_frame", ((.62 - .14 * i) / 2, sill / 2, 0), (.62 - .14 * i, sill, w + .04))
    w, h, sill = .46, 1.60, .24
    batch.box("law_3", (.034, sill + (h - .1) / 2, 0), (.02, h - .14, w - .14))
    batch.emit(b, "Frames", g, shadow=True)
    # The radiance "that streams inextinguishably from the door of the Law".
    for name, centre, size in (("SeamFoot", (.05, sill + .012, 0), (.01, .012, w - .1)),
                               ("SeamL", (.05, sill + (h - .1) / 2, -(w - .12) / 2), (.01, h - .16, .01)),
                               ("SeamR", (.05, sill + (h - .1) / 2, (w - .12) / 2), (.01, h - .16, .01)),
                               ("Keyhole", (.05, sill + .72, .1), (.01, .04, .018))):
        b.box(name, g, centre, size, "law_glow")
    # ...and spills over the steps onto the floor, the one warm thing in the room.
    spill = Batch()
    spill.strip("law_glow", [(.62, 0), (1.9, 0)], .3, .0065)
    spill.strip("law_glow", [(1.9, 0), (2.5, 0)], .14, .0065)
    for i, (sill, depth) in enumerate(((.10, .48), (.18, .34), (.24, .20))):
        spill.strip("law_glow", [(depth - .1, 0), (depth + .001, 0)], .2, sill + .002)
    spill.emit(b, "Spill", g)
    b.detail("Pediment", g, (.09, 3.15, 0), prism(((-.72, 0), (.72, 0), (0, .38)), .18), "law_frame",
             rot=(0, 90, 0), shadow=True)
    label(b, "Inscription", g, (.012, 2.84, 0), "法  LAW", .0034, (0, 90, 0), (214, 186, 132))
    b.box("Plaque", g, (.008, 1.45, -.78), (.01, .17, .38), "plaque")
    label(b, "PlaqueText", g, (.016, 1.48, -.78), "此门只为你而设", .0011, (0, 90, 0), (52, 40, 32))
    label(b, "PlaqueEnglish", g, (.016, 1.41, -.78), "THIS GATE WAS MADE ONLY FOR YOU", .00072, (0, 90, 0), (52, 40, 32))

    # The doorkeeper in his fur coat and Tatar beard, and the man from the country on his stool.
    keeper = figure(b, parent, "Doorkeeper", (-3.72, 0, -.9), 90,
                    {"coat": "fur", "hair": "beard", "legs": "bench_dark"}, shadow=True)
    for name, centre, size, pigment in (("Skirt", (0, .55, 0), (.5, .62, .32), "fur"),
                                        ("Collar", (0, 1.44, 0), (.54, .15, .34), "fur_light"),
                                        ("Beard", (0, 1.37, .125), (.07, .36, .03), "beard"),
                                        ("Nose", (0, 1.63, .14), (.05, .07, .08), "skin_dim"),
                                        ("Hat", (0, 1.82, 0), (.27, .15, .27), "fur_light")):
        b.box(name, keeper, centre, size, pigment, shadow=size[1] > .1)
    rng = random.Random(7)
    for k in range(7):
        # The fleas in his collar, whom the man in the end asks for help.
        b.box(f"Flea{k}", keeper, (rng.uniform(-.25, .25), 1.52, rng.uniform(-.16, .17)), (.014, .008, .014), "beard")
    q = b.shell("KeeperStop", parent, (-3.72, 0, -.9))
    b.shape("Body", q, (0, .95, 0), (.6, 1.9, .6))
    man = (-3.1, 0, -2.3)
    yaw = math.degrees(math.atan2(WALL_W - man[0], GATE_Z - man[2]))
    stool = b.shell("CountryStool", parent, man, (0, yaw, 0))
    b.shape("Body", stool, (0, .55, .1), (.62, 1.1, .78))
    b.box("Seat", stool, (0, .42, -.02), (.36, .04, .36), "bench", shadow=True)
    for k in range(3):
        a = math.tau * k / 3 + .5
        b.box(f"Leg{k}", stool, (.13 * math.cos(a), .2, -.02 + .13 * math.sin(a)), (.035, .4, .035), "bench_dark")
    figure(b, stool, "CountryMan", (0, 0, 0), 0, {"coat": "coat_olive", "hair": "hair_grey", "droop": True},
           body="nod", phase=.31)


def petitioners(b, parent):
    """The waiting room of the court offices: a bench, hats on hooks, the same number for everyone."""
    bench = b.shell("PetitionBench", parent, (-4.07, 0, 1.4))
    b.shape("Body", bench, (0, .45, 0), (.46, .9, 3.1))
    b.box("Seat", bench, (.02, .42, 0), (.42, .05, 3.1), "bench", shadow=True)
    b.box("Rail", bench, (.2, .36, 0), (.04, .1, 3.08), "bench_dark")
    b.box("Back", bench, (-.2, .74, 0), (.04, .32, 3.1), "bench", shadow=True)
    for k, z in enumerate((-1.45, -.5, .5, 1.45)):
        b.box(f"Leg{k}", bench, (0, .2, z), (.36, .4, .05), "bench_dark", shadow=True)
    looks = (("coat_grey", "hair_grey"), ("coat_olive", "hair"), ("coat_ink", "hair_grey"), ("coat_rust", "hair"))
    for k, (z, (coat, hair)) in enumerate(zip((.2, .95, 1.75, 2.55), looks)):
        nods = k in (1, 3)
        p = figure(b, parent, f"Petitioner{k}", (-4.1, 0, z), 90, {"coat": coat, "hair": hair, "droop": True},
                   pose="sit", body="nod" if nods else None, phase=.17 * k)
        if nods:
            b.box(f"Papers{k}", bench, (.06, .452, z - 1.4 + .27), (.22, .008, .3), "paper", rot=(0, 12 * k, 0))
        else:
            b.box("Petition", p, (0, 1.08, .45), (.26, .2, .008), "ledger", rot=(-24, 0, 0))
        b.box(f"Hook{k}", parent, (-4.27, 1.93, z), (.06, .025, .025), "brass")
        b.box(f"HatCrown{k}", parent, (-4.2, 1.87, z), (.2, .12, .22), "hat", shadow=True)
        b.box(f"HatBrim{k}", parent, (-4.2, 1.81, z), (.32, .02, .34), "hat")
        b.box(f"NumberCard{k}", parent, (WALL_W + .006, 1.5, z), (.01, .12, .16), "paper")
        label(b, f"Number{k}", parent, (WALL_W + .013, 1.5, z), "17", .0019, (0, 90, 0), (40, 49, 66))
    figure(b, parent, "Latecomer", (-2.95, 0, 2.95), 180, {"coat": "coat_navy", "hair": "hair", "droop": True},
           pose="bowed", body="nod", phase=.6)
    b.box("NoticeBoard", parent, (WALL_W + .006, 2.36, 1.4), (.012, .34, 2.5), "ink")
    label(b, "Notice", parent, (WALL_W + .014, 2.42, 1.4), "候审者请保持安静", .0031, (0, 90, 0), (232, 215, 172))
    label(b, "NoticeEnglish", parent, (WALL_W + .014, 2.27, 1.4), "PETITIONERS WAIT HERE  ·  NO TALKING",
          .0016, (0, 90, 0), (232, 215, 172))
    # One bare bulb on a long flex over the bench; no fitting, no ceiling.
    b.box("Flex", parent, (-3.4, 3.1, 1.3), (.008, 1.5, .008), "line")
    b.round("Bulb", parent, (-3.4, 2.32, 1.3), .045, .09, "law_glow", sides=10)
    b.node("BulbLight", parent, "OmniLight3D", position=vec3((-3.4, 2.24, 1.3)),
           light_color="Color(1, 0.86, 0.6, 1)", light_energy=.38, omni_range=3.4)


def high_desk(b, parent):
    """The examining magistrate's desk: on a plinth, taller than the wall, stamped from above."""
    d = b.shell("HighDesk", parent, (3.62, 0, -2.62))
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
    b.box("Register", d, (-.15, 2.73, .46), (.74, .09, .52), "navy", rot=(-12, 0, 0), shadow=True)
    b.box("Hanging", d, (-.15, 2.28, .695), (.5, .9, .006), "ledger", rot=(0, 0, 3))
    label(b, "Case", d, (-.15, 2.52, .70), "案 K.", .0024, (0, 0, 3), (112, 78, 71))
    b.box("Pad", d, (.3, 2.74, .36), (.13, .02, .1), "red", rot=(-12, 0, 0))
    b.round("Ink", d, (.5, 2.75, .52), .035, .05, "ink", sides=10)
    b.round("LampFoot", d, (.5, 2.72, .18), .07, .03, "brass", sides=12)
    b.round("LampStem", d, (.5, 2.86, .18), .012, .28, "brass", sides=8)
    b.round("LampShade", d, (.5, 2.99, .24), .1, .09, "teal", top=.05, sides=12, rot=(30, 0, 0))
    b.box("Nameplate", d, (0, 2.0, .685), (.78, .16, .01), "plaque")
    label(b, "Title", d, (0, 2.03, .692), "预审法官", .0016, ink=(52, 40, 32))
    label(b, "TitleEnglish", d, (0, 1.97, .692), "EXAMINING MAGISTRATE", .00085, ink=(52, 40, 32))
    seat = 2.16
    for k, (x, z) in enumerate(((-.17, -.4), (.17, -.4), (-.17, -.06), (.17, -.06))):
        b.box(f"StoolLeg{k}", d, (x, (.45 + seat) / 2, z), (.04, seat - .45, .04), "bench_dark")
    b.box("StoolSeat", d, (0, seat + .02, -.23), (.44, .05, .44), "bench")
    for k, y in enumerate((.9, 1.5)):
        b.box(f"StoolRung{k}", d, (0, y, -.23), (.38, .03, .03), "bench_dark")
    official = figure(b, d, "Magistrate", (0, seat - .44, -.23), 0,
                      {"coat": "coat_ink", "hair": "hair_grey", "droop": True}, pose="sit", hand="stamp", phase=.0)
    part(b, "Stamp", official, (.21, 1.05, .42), (.07, .08, .07), motion_material(b, "brass", "stamp", phase=0.0))
    # The clerk's ladder, leaning on the side panel.
    for side in (-.18, .18):
        b.box(f"LadderRail{side > 0:d}", d, (-.755, 1.25, .3 + side), (.045, 2.51, .045), "wood_light",
              rot=(0, 0, -4.3))
    for k in range(1, 8):
        b.box(f"LadderRung{k}", d, (-.85 + .19 * k / 8.3, .31 * k, .3), (.045, .03, .36), "wood_light")


def laundry(b, parent):
    """In the court's attic, washing hangs between the files: a line from the west wall to the high desk."""
    start, end, sag = (WALL_W, 2.62), (2.98, 2.6), .22
    z = -2.42
    batch = Batch()

    def at(t):
        return (start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t - sag * 4 * t * (1 - t))

    for k in range(10):
        (x0, y0), (x1, y1) = at(k / 10), at((k + 1) / 10)
        batch.box("line", ((x0 + x1) / 2, (y0 + y1) / 2, z), (math.hypot(x1 - x0, y1 - y0), .008, .008),
                  (0, 0, math.degrees(math.atan2(y1 - y0, x1 - x0))))
    for t, kind in ((.09, "shirt"), (.19, "file"), (.28, "shirt_blue"), (.39, "dress_red"), (.5, "sheet"),
                    (.61, "file"), (.71, "shirt"), (.82, "file"), (.9, "file")):
        x, y = at(t)
        batch.box("wood_light", (x, y - .01, z), (.022, .06, .026))
        if kind == "file":
            batch.box("file_buff", (x, y - .14, z + .006), (.32, .26, .01), (0, 0, 4))
            batch.box("paper", (x + .01, y - .17, z + .014), (.27, .22, .004), (0, 0, -3))
        elif kind == "sheet":
            batch.box("white", (x, y - .38, z), (.95, .74, .01), (0, 0, 1))
        elif kind == "dress_red":
            batch.box(kind, (x, y - .22, z), (.3, .4, .012))
            batch.box(kind, (x, y - .52, z), (.46, .24, .012))
        else:
            batch.box(kind, (x, y - .3, z), (.44, .54, .012))
            for side in (-1, 1):
                batch.box(kind, (x + side * .27, y - .17, z), (.16, .27, .012), (0, 0, side * 28))
    batch.emit(b, "Laundry", parent)


def paper_drifts(b, parent):
    """Petitions and carbons drifted against the bench, the gate steps and the high desk."""
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


def trial_archive(b):
    b.pigments.update({k: v for k, v in {**PEOPLE, **TRIAL}.items() if k not in b.pigments})
    b.mat("law_glow", shading_mode=0, albedo_color="Color(1, 0.93, 0.74, 1)")
    t = "Trial"
    b.node(t, ".")
    dossier_mountain(b, t)
    law_gate(b, t)
    petitioners(b, t)
    high_desk(b, t)
    laundry(b, t)
    paper_drifts(b, t)
    queue_post(b, t)
