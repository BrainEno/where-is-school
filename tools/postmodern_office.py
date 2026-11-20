"""Postmodern office furniture for the school offices (2026-11-20; docs/OFFICE_ARCHIVE_ART.md).

Swivel chairs on five-star bases, Memphis desks with terrazzo tops and mismatched
legs, a Carlton-style totem shelf, a broken-pediment cabinet, fluted column lamps and
a bird kettle. Everything is primitive geometry in hard pastel and primary fields.

A piece is given a collider only where the room it replaces already had one
(`collider=True`), so the navigation, the inspection stances and the camera shots
keep the footprint they were measured against.
"""
from __future__ import annotations

import math
import random

from build_teaching_block import child_path, vec3
from dressing_geometry import Batch, prism, solid_loft
from fixture_geometry import pipe, rounded_rect, vessel

POMO = {
    "pomo_pink": (238, 152, 166), "pomo_mint": (124, 204, 182), "pomo_lemon": (242, 211, 82),
    "pomo_cobalt": (42, 80, 172), "pomo_black": (30, 30, 35), "pomo_white": (240, 234, 222),
    "pomo_red": (218, 66, 52), "pomo_lilac": (182, 156, 210), "pomo_terra": (210, 122, 88),
    "pomo_chrome": (186, 190, 196), "terrazzo": (229, 222, 207), "pomo_grey": (132, 134, 142),
}


def _group(b, parent, name, pos, rot, collider):
    if collider:
        return b.shell(name, parent, pos, rot)
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3(rot))
    return child_path(parent, name)


def confetti(b, name, parent, y, width, depth, pigments, *, count=60, seed=0, size=.022):
    """Terrazzo chips on a top surface: triangles, squares and dots in a few colours."""
    rng = random.Random(seed)
    batch = Batch()
    for _ in range(count):
        batch.chip(rng.choice(pigments), (rng.uniform(-width / 2 + .04, width / 2 - .04),
                   rng.uniform(-depth / 2 + .04, depth / 2 - .04)), size * rng.uniform(.6, 1.5),
                   rng.choice((3, 3, 4, 7)), rng.uniform(0, math.tau), y)
    batch.emit(b, name, parent)


def squiggles(b, name, parent, y, width, depth, pigment, *, count=10, seed=0, line=.016):
    """Bacterio-style black worms over a pale field."""
    rng = random.Random(seed)
    batch = Batch()
    for _ in range(count):
        x, z = rng.uniform(-width / 2 + .12, width / 2 - .12), rng.uniform(-depth / 2 + .1, depth / 2 - .1)
        heading = rng.uniform(0, math.tau)
        path = []
        for k in range(6):
            path.append((x, z))
            heading += (1 if k % 2 else -1) * rng.uniform(.8, 1.4)
            x = max(-width / 2 + .05, min(width / 2 - .05, x + .07 * math.cos(heading)))
            z = max(-depth / 2 + .05, min(depth / 2 - .05, z + .07 * math.sin(heading)))
        batch.strip(pigment, path, line, y)
    batch.emit(b, name, parent)


def swivel_chair(b, parent, name, pos, yaw=0, *, seat="pomo_pink", back="pomo_black", base="pomo_black",
                 accent="pomo_lemon", crest="disc", arms=True, collider=False, rot=None):
    """A gas-lift office chair. The seat faces local +Z, like the rooms' plain chairs."""
    q = _group(b, parent, name, pos, rot or (0, yaw, 0), collider)
    if collider:
        b.shape("SeatStop", q, (0, .37, 0), (.5, .72, .5))
    for i in range(5):
        a = 72 * i + 18
        r = math.radians(a)
        b.box(f"Spoke{i}", q, (.15 * math.sin(r), .075, .15 * math.cos(r)), (.052, .04, .30), base,
              rot=(0, a, 0), shadow=True)
        b.round(f"Caster{i}", q, (.30 * math.sin(r), .032, .30 * math.cos(r)), .032, .045, base,
                rot=(0, a, 90), sides=10)
    b.round("Hub", q, (0, .09, 0), .058, .07, base, sides=12)
    b.round("Shroud", q, (0, .19, 0), .05, .16, base, top=.034, sides=12)
    b.round("Lift", q, (0, .33, 0), .022, .16, "pomo_chrome", sides=10)
    b.box("Mechanism", q, (0, .405, -.01), (.2, .05, .22), base)
    cushion = [rounded_rect(y, w, d, r) for y, w, d, r in (
        (.425, .48, .46, .09), (.448, .53, .51, .12), (.478, .53, .51, .12), (.497, .49, .47, .1))]
    b.detail("Seat", q, (0, 0, 0), solid_loft(cushion), seat, shadow=True)
    b.box("Spine", q, (0, .44, -.24), (.06, .035, .14), "pomo_chrome")
    b.box("Upright", q, (0, .58, -.30), (.05, .30, .035), "pomo_chrome")
    if crest == "disc":
        b.round("Back", q, (0, .87, -.30), .25, .07, back, rot=(90, 0, 0), sides=24, shadow=True)
        b.round("Dot", q, (.07, .91, -.262), .085, .008, accent, rot=(90, 0, 0), sides=16)
    elif crest == "triangle":
        b.detail("Back", q, (0, 0, -.30), prism(((-.27, .62), (.27, .62), (0, 1.16)), .07), back, shadow=True)
        for i in range(3):
            b.box(f"Stripe{i}", q, (0, .69 + .1 * i, -.262), (.36 - .1 * i, .026, .008), accent)
    elif crest == "arch":
        b.box("Back", q, (0, .77, -.30), (.46, .26, .07), back, shadow=True)
        b.round("Crown", q, (0, .90, -.30), .23, .07, back, rot=(90, 0, 0), sides=24, shadow=True)
        b.box("Keystone", q, (0, 1.10, -.262), (.08, .1, .012), accent)
    elif crest == "throne":
        # Rises past the occupant's head and ends in a split pediment with an oculus.
        b.box("Back", q, (0, 1.08, -.31), (.60, 1.12, .10), back, shadow=True)
        b.box("Panel", q, (0, 1.02, -.256), (.44, .78, .012), accent)
        for side in (-1, 1):
            b.box(f"Pilaster{side+1}", q, (side * .26, 1.02, -.25), (.06, .98, .03), "pomo_chrome")
            b.box(f"Pediment{side+1}", q, (side * .19, 1.72, -.31), (.30, .07, .12), back,
                  rot=(0, 0, -side * 24), shadow=True)
        b.round("Oculus", q, (0, 1.74, -.30), .07, .13, accent, rot=(90, 0, 0), sides=16)
    if arms:
        for side in (-1, 1):
            b.detail(f"Arm{side+1}", q, (side * .27, 0, 0),
                     pipe(((-.12, .47), (-.12, .655), (.17, .655), (.17, .50)), .014, 8), "pomo_chrome",
                     rot=(0, 90, 0))
            b.box(f"ArmPad{side+1}", q, (side * .27, .672, .01), (.06, .03, .26), accent)
    return q


def memphis_desk(b, name, pos, width, depth, *, tall=.79, top="terrazzo", yaw=0, parent=".", seed=0,
                 colours=("pomo_cobalt", "pomo_pink", "pomo_lemon"), collider=True, classical=False):
    """A desk whose every leg is a different solid. The top is where items sit, at `tall`."""
    group = _group(b, parent, name, pos, (0, yaw, 0), collider)
    leg, pedestal, panel = colours
    h = tall - .076
    b.box("Top", group, (0, tall - .038, 0), (width, .076, depth), top, shadow=True)
    b.box("Edge", group, (0, tall - .038, depth / 2 + .007), (width, .082, .014), "pomo_black")
    confetti(b, "Terrazzo", group, tall + .0012, width, depth, ("pomo_black", "pomo_red", leg, "pomo_mint"),
             count=int(width * depth * 70), seed=seed)
    if collider:
        b.shape("Body", group, (0, tall / 2, 0), (width, tall, depth))
    if classical:
        # Four fluted columns with gilded capitals, and a frieze on the visitor's side.
        for i, (sx, sz) in enumerate(((-1, -1), (-1, 1), (1, -1), (1, 1))):
            x, z = sx * (width / 2 - .14), sz * (depth / 2 - .13)
            b.round(f"Column{i}", group, (x, h / 2, z), .075, h - .1, panel, sides=12, shadow=True)
            b.box(f"Capital{i}", group, (x, h - .03, z), (.2, .06, .2), "pomo_lemon")
            b.box(f"Base{i}", group, (x, .03, z), (.19, .06, .19), "pomo_black")
            for k in range(6):
                a = math.tau * k / 6
                b.box(f"Flute{i}_{k}", group, (x + .076 * math.cos(a), h / 2, z + .076 * math.sin(a)),
                      (.012, h - .16, .012), pedestal)
        b.box("Frieze", group, (0, h - .07, depth / 2 - .02), (width - .5, .12, .03), pedestal)
        for k in range(int((width - .6) / .3) + 1):
            b.box(f"Triglyph{k}", group, (-(width - .6) / 2 + k * .3, h - .07, depth / 2 - .002),
                  (.07, .1, .012), "pomo_black")
        return group
    # A cobalt drum, a pink drawer ziggurat, one black rod that leans, a lemon lobe.
    b.round("Drum", group, (-width / 2 + .24, h / 2, 0), .13, h, leg, sides=20, shadow=True)
    b.round("DrumCap", group, (-width / 2 + .24, h - .012, 0), .16, .024, "pomo_black", sides=20)
    px = width / 2 - .26
    b.box("Pedestal", group, (px, h / 2, 0), (.40, h, depth * .78), pedestal, shadow=True)
    b.box("Plinth", group, (px, .04, 0), (.46, .08, depth * .84), "pomo_black")
    for k in range(3):
        y = .16 + k * (h - .2) / 3
        b.box(f"Drawer{k}", group, (px, y + .09, depth * .39 + .006), (.34, (h - .32) / 3, .014), panel)
        b.round(f"Knob{k}", group, (px, y + .09, depth * .39 + .03), .022, .03, "pomo_black", rot=(90, 0, 0), sides=8)
    b.box("Rod", group, (0, h / 2, -depth / 2 + .1), (.03, h + .07, .03), "pomo_black", rot=(0, 0, 18))
    b.round("Lobe", group, (-width / 2, tall - .036, depth * .1), depth * .42, .072, panel, sides=24, shadow=True)
    b.box("Modesty", group, (-.05, h - .2, -depth / 2 + .05), (width - .95, .30, .022), panel)
    for k in range(5):
        b.round(f"Spot{k}", group, (-.05 - (width - 1.2) / 2 + k * (width - 1.2) / 4, h - .2, -depth / 2 + .036),
                .03, .008, "pomo_black", rot=(90, 0, 0), sides=10)
    return group


def carlton(b, name, pos, yaw=0, *, parent=".", collider=True):
    """A totem room divider after the 1981 Memphis shelf: splayed arms around a spine."""
    q = _group(b, parent, name, pos, (0, yaw, 0), collider)
    if collider:
        b.shape("Footprint", q, (0, .98, 0), (1.02, 1.96, .40))
    b.box("Base", q, (0, .17, 0), (1.02, .34, .40), "pomo_white", shadow=True)
    squiggles(b, "Bacterio", q, .3415, 1.0, .38, "pomo_black", count=7, seed=3)
    b.box("BaseFace", q, (0, .17, .203), (.98, .30, .006), "pomo_black")
    for k in range(6):
        b.box(f"Worm{k}", q, (-.4 + k * .16, .17 + (.06 if k % 2 else -.06), .207), (.1, .03, .006), "pomo_white",
              rot=(0, 0, 35 if k % 2 else -35))
    for part, centre, size, pigment, roll in (
        ("Spine", (0, 1.13, 0), (.05, 1.58, .30), "pomo_red", 0),
        ("Shelf", (0, .82, 0), (.98, .035, .32), "pomo_lemon", 0),
        ("UpperShelf", (0, 1.36, 0), (.62, .035, .32), "pomo_cobalt", 0),
        ("ArmL", (-.24, 1.08, 0), (.56, .035, .30), "pomo_pink", 42),
        ("ArmR", (.24, 1.08, 0), (.56, .035, .30), "pomo_mint", -42),
        ("WingL", (-.19, 1.60, 0), (.42, .035, .30), "pomo_lemon", -38),
        ("WingR", (.19, 1.60, 0), (.42, .035, .30), "pomo_cobalt", 38),
        ("PostL", (-.475, .58, 0), (.035, .48, .30), "pomo_black", 0),
        ("PostR", (.475, .58, 0), (.035, .48, .30), "pomo_black", 0),
        ("Crest", (0, 1.88, 0), (.14, .16, .30), "pomo_red", 0),
        ("CrestBar", (0, 1.80, 0), (.36, .03, .30), "pomo_black", 0),
    ):
        b.box(part, q, centre, size, pigment, rot=(0, 0, roll) if roll else None, shadow=True)
    for k, (x, w, h, pigment) in enumerate(((-.38, .05, .26, "pomo_cobalt"), (-.32, .06, .23, "pomo_pink"),
                                             (-.25, .04, .28, "pomo_black"), (.3, .07, .21, "pomo_lemon"))):
        b.box(f"Book{k}", q, (x, .84 + h / 2, 0), (w, h, .22), pigment)
    b.detail("Vase", q, (.0, 1.375, 0), vessel(((0, .07), (.002, .072), (.06, .11), (.16, .05), (.2, .06),
             (.2, .052), (.06, .1)), 12), "pomo_mint", shadow=True)
    return q


def pediment_cabinet(b, name, pos, yaw=0, *, width=1.0, height=1.9, body="pomo_pink", trim="pomo_mint",
                     parent=".", collider=True):
    """A cabinet dressed as a skyscraper with a broken pediment and an oculus."""
    q = _group(b, parent, name, pos, (0, yaw, 0), collider)
    shaft = height - .34
    if collider:
        b.shape("Footprint", q, (0, shaft / 2, 0), (width, shaft, .50))
    b.box("Body", q, (0, shaft / 2, 0), (width, shaft, .48), body, shadow=True)
    b.box("Plinth", q, (0, .05, .01), (width + .06, .10, .52), "pomo_black")
    b.box("Cornice", q, (0, shaft + .03, .01), (width + .1, .06, .54), "pomo_lemon", shadow=True)
    for side in (-1, 1):
        x = side * (width / 2 - .06)
        b.box(f"Pilaster{side+1}", q, (x, shaft / 2 + .02, .25), (.08, shaft - .2, .03), trim)
        b.box(f"Capital{side+1}", q, (x, shaft - .07, .26), (.14, .06, .05), "pomo_lemon")
        b.box(f"Door{side+1}", q, (side * (width / 4 - .01), shaft / 2 + .02, .245), (width / 2 - .2, shaft - .4, .02),
              "pomo_white")
        b.round(f"Pull{side+1}", q, (side * .07, shaft / 2, .265), .025, .03, "pomo_black", rot=(90, 0, 0), sides=10)
        # Each half-gable starts at the cornice edge and stops short of the middle.
        x0, x1 = side * (width / 2 + .04), side * .12
        y0 = shaft + .06
        y1 = y0 + abs(x1 - x0) * math.tan(math.radians(26))
        b.box(f"Gable{side+1}", q, ((x0 + x1) / 2, (y0 + y1) / 2 + .03, .01),
              (math.hypot(x1 - x0, y1 - y0), .08, .5), body, rot=(0, 0, -side * 26), shadow=True)
    b.round("Oculus", q, (0, shaft + .2, .2), .085, .04, "pomo_black", rot=(90, 0, 0), sides=20)
    b.round("OculusEye", q, (0, shaft + .2, .222), .05, .012, "pomo_lemon", rot=(90, 0, 0), sides=16)
    return q


def column_lamp(b, name, pos, *, parent=".", shaft="pomo_white", shade="pomo_lemon", capital="pomo_pink",
                light=False):
    """A fluted Doric floor lamp under a cone shade."""
    q = _group(b, parent, name, pos, (0, 0, 0), False)
    b.box("Base", q, (0, .04, 0), (.34, .08, .34), "pomo_black", shadow=True)
    b.round("Shaft", q, (0, .74, 0), .068, 1.32, shaft, sides=16, shadow=True)
    for k in range(8):
        a = math.tau * k / 8
        b.box(f"Flute{k}", q, (.068 * math.cos(a), .74, .068 * math.sin(a)), (.012, 1.26, .012), "pomo_grey")
    b.box("Capital", q, (0, 1.43, 0), (.22, .07, .22), capital)
    b.round("Shade", q, (0, 1.64, 0), .27, .32, shade, top=.07, sides=20, shadow=True)
    if light:
        b.node("Glow", q, "OmniLight3D", position=vec3((0, 1.5, 0)), light_color="Color(1, 0.88, 0.66, 1)",
               light_energy=.32, omni_range=2.6)
    return q


def kettle(b, name, parent, pos, yaw=0):
    """A cone kettle with a red bird on the spout and a blue grip."""
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)))
    q = child_path(parent, name)
    b.detail("Body", q, (0, 0, 0), vessel(((0, .11), (.2, .03), (.21, .022)), 16), "pomo_chrome",
             shadow=True)
    b.round("Knob", q, (0, .225, 0), .018, .03, "pomo_red", sides=8)
    b.detail("Grip", q, (0, 0, 0), pipe(((-.06, .17), (-.02, .245), (.05, .24), (.07, .16)), .009, 8), "pomo_cobalt")
    b.round("Spout", q, (.12, .07, 0), .012, .09, "pomo_chrome", rot=(0, 0, -55), sides=8)
    b.box("Bird", q, (.165, .11, 0), (.04, .025, .018), "pomo_red", rot=(0, 0, 20))
    return q


def memphis_rug(b, name, parent, pos, width, depth, *, field="pomo_white", ink="pomo_black", border="pomo_cobalt",
                seed=0, lift=0.0):
    """A flat rug with a border and black squiggles; it never collides. `lift` tucks it under floor light."""
    b.node(name, parent, position=vec3((pos[0], pos[1] + lift, pos[2])))
    q = child_path(parent, name)
    b.box("Field", q, (0, .004, 0), (width, .006, depth), field)
    batch = Batch()
    for sign in (-1, 1):
        batch.strip(border, [(-width / 2, sign * (depth / 2 - .05)), (width / 2, sign * (depth / 2 - .05))], .1, .0076)
        batch.strip(border, [(sign * (width / 2 - .05), -depth / 2 + .1), (sign * (width / 2 - .05), depth / 2 - .1)],
                    .1, .0076)
    batch.emit(b, "Border", q)
    squiggles(b, "Worms", q, .0078, width - .24, depth - .24, ink, count=int(width * depth * 6), seed=seed, line=.022)
    confetti(b, "Dots", q, .0079, width - .3, depth - .3, ("pomo_pink", "pomo_lemon"), count=int(width * depth * 9),
             seed=seed + 1, size=.03)
    return q


def wall_clock(b, name, parent, pos, rot=(0, 0, 0)):
    """A clock face of primary shapes whose two hands point to the same nothing."""
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3(rot))
    q = child_path(parent, name)
    b.round("Face", q, (0, 0, 0), .22, .03, "pomo_white", rot=(90, 0, 0), sides=24, shadow=True)
    b.round("Rim", q, (0, 0, -.006), .245, .02, "pomo_cobalt", rot=(90, 0, 0), sides=24)
    for k in range(4):
        a = math.tau * k / 4
        b.box(f"Mark{k}", q, (.16 * math.cos(a), .16 * math.sin(a), .018), (.05, .05, .006),
              ("pomo_red", "pomo_lemon", "pomo_mint", "pomo_pink")[k], rot=(0, 0, 45))
    b.box("HandA", q, (0, .06, .024), (.018, .13, .006), "pomo_black")
    b.box("HandB", q, (0, .075, .028), (.012, .16, .006), "pomo_black")
    return q


# ---------------------------------------------------------------------------
# Room dressings. Each is called by its room builder after the original
# furniture with the same node names has been rebuilt here.


def vacant_workroom(b):
    """A borrowed corner: one chair left on its side, the shelves taken away."""
    w = "Postmodern"
    b.node(w, ".")
    swivel_chair(b, w, "Toppled", (-.9, .33, 1.95), 0, seat="pomo_mint", back="pomo_pink", accent="pomo_black",
                 crest="arch", collider=True, rot=(0, 63, 90))
    # Exposed screw line in place of the cabinet; not another array of props.
    b.box("Cleat", w, (-4.284, .59, -.86), (.048, .111, 3.71), "ink")
    for i in range(5):
        b.box(f"Cut{i}", w, (-4.255, .59, -2.28+i*.72), (.014,.032,.034), "putty")
    wall_clock(b, "Clock", w, (-4.27, 1.95, .30), (0, 90, 0))


def principal_suite(b):
    """The principal's office: a classical desk front and displaced proscenium."""
    w = "Postmodern"
    b.node(w, ".")
    column_lamp(b, "LampWest", (-.25, 0, -2.95), parent=w, shade="pomo_mint", capital="pomo_lemon", light=True)
    column_lamp(b, "LampEast", (4.05, 0, -1.95), parent=w, shade="pomo_pink", capital="pomo_lemon")
    # SideCase becomes a small skyscraper: a split gable and an oculus on top.
    crown = child_path(w, "SideCrown")
    b.node("SideCrown", w, position=vec3((3.67, 1.12, -2.97)))
    b.box("Cornice", crown, (0, .03, 0), (1.0, .06, .6), "pomo_lemon", shadow=True)
    for side in (-1, 1):
        b.box(f"Gable{side+1}", crown, (side * .28, .15, 0), (.42, .07, .52), "pomo_pink", rot=(0, 0, -side * 26),
              shadow=True)
    b.round("Oculus", crown, (0, .2, .22), .07, .04, "pomo_black", rot=(90, 0, 0), sides=16)
    wall_clock(b, "Clock", w, (-4.48, 2.2, 1.05), (0, 90, 0))
    # Two freestanding pink columns frame the throne against the false window wall.
    for k, x in enumerate((.5, 2.98)):
        col = child_path(w, f"Column{k}")
        b.node(f"Column{k}", w, position=vec3((x, 0, -3.18)))
        b.box("Base", col, (0, .06, 0), (.4, .12, .32), "pomo_black", shadow=True)
        b.round("Shaft", col, (0, 1.2, 0), .15, 2.16, "pomo_pink", sides=20, shadow=True)
        b.box("Capital", col, (0, 2.32, 0), (.42, .1, .34), "pomo_lemon", shadow=True)
        b.round("Ball", col, (0, 2.5, 0), .1, .2, "pomo_cobalt", top=.02, sides=12)


def staff_office_dressing(b):
    """Working-office ephemera printed at calendar and room scale; no new stops."""
    w = "Postmodern"
    b.node(w, ".")
    # A paper roll interrupts the two painted windows; the shifts continue on
    # the floor, but the order of their columns is different there.
    b.box("CalendarStock", w, (.16,1.457,-2.918), (1.43,2.27,.019), "paper", rot=(0,0,-2))
    b.box("CalendarHeader", w, (.12,2.442,-2.899), (1.47,.217,.016), "stamp", rot=(0,0,-2))
    for i in range(6):
        x = -.342 + i*.194
        b.box(f"CalendarColumn{i}", w, (x,1.36,-2.892), (.016,1.59,.015), "rule", rot=(0,0,-2))
    for i in range(5):
        b.box(f"CalendarRow{i}", w, (.165,1.97-i*.295,-2.889), (1.15,.015,.016), "ledger", rot=(0,0,-2))
    for i, (x, z, depth) in enumerate(((-.83,-.99,2.97),(-.51,-.16,4.64),(.24,-.58,3.83),(.64,.10,2.24))):
        b.box(f"CancelledColumn{i}", w, (x,.006,z), (.071 if i != 1 else .137,.006,depth),
              "stamp" if i == 1 else "paper", rot=(0,-7,0))
    b.box("CancelStroke", w, (-.10,.009,.85), (2.25,.005,.079), "ledger", rot=(0,-14,0))
    kettle(b, "Kettle", w, (3.13, .971, -2.5), -20)
    wall_clock(b, "Clock", w, (.55, 2.25, -2.985))
