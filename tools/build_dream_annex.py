"""The exam dream laid over the teaching block (2026-11-20; docs/EXAM_DREAM_ART.md).

`build_teaching_block.py` calls `annex()` and writes `dream_annex.tscn`, which the
hand-authored corridor instances beside `TeachingBlock`. Nothing here moves a wall,
exit or spawn. Four layers of generated meshes and primitives:

* the 02 -> 03 west stair is dressed as a metro escalator whose steps run down;
* a ticket counter just inside the 01 glass entrance with three synchronized clerks;
* 03 as an exam floor: paper room numbers, a seating grid, turned chairs and a
  troublemaker who punches the wall;
* behind 01, a walkable stable yard with a two-storey dream house, an outdoor
  escalator that ends in nothing, grain, quilts, horses, hens and their smell.

Round 10 (2026-11-11) turns the yard into a stink stable: shaped, painted horses, dung
and straw, swarms of flies and a giant one, paper stink clouds (`dream_stable.py`).
"""
from __future__ import annotations

import math
import random

from build_teaching_block import (
    ENTRANCE_X, GROUND_Y, GROUND_Z, OFFICE_X, RISE, UPPER_NORTH, UPPER_WEST, WEST_STAIR_WIDTH, WEST_STAIR_Z,
    child_path, plane, quad, slab, srgb, vec3,
)
import dream_stable
from dream_figures import PEOPLE, figure, shader_material, swivel_chair
from exam_crowd import exam_candidates, waiting_candidates
from fixture_geometry import FixtureBuild
from ticket_clerks import PRESS_Z, STATIONS, build_clerk, stamp_loop

G = GROUND_Y
STAIR_RUN, STAIR_ORIGIN = 7.55, (-2.2, 0.0, WEST_STAIR_Z)
# The stable yard: open to the 01 apron's west side, walled toward the village.
LANE_X, LANE_Z = (-40.2, -20.75), (14.68, 18.45)
YARD_X, YARD_Z = (-40.2, -26.95), (4.6, LANE_Z[0])
HOUSE_X, HOUSE_Z = (-40.2, -33.2), (4.6, 10.4)
HOUSE_STOREY, HOUSE_TOP = 3.1, 6.0
PIGMENTS = {
    **PEOPLE,
    # Hard-edged modern fields for the exam floor, cooler steel for the metro.
    "vermilion": (222, 76, 52), "cobalt": (40, 74, 162), "lemon": (238, 206, 72), "paper": (237, 232, 216),
    "graphite": (36, 38, 44), "steel": (170, 175, 181), "rubber": (24, 24, 28), "tile_white": (214, 216, 210),
    "wayfind": (28, 36, 58), "led": (226, 64, 48),
    "ticket_enamel": (48, 78, 105), "stamp_rubber": (70, 52, 55), "stamp_wood": (116, 78, 59),
    # The yard: earth, dung, straw and sun-dried colour.
    "earth": (128, 104, 76), "earth_dark": (96, 78, 58), "dung": (70, 55, 37), "straw": (212, 180, 98),
    "grain": (224, 177, 82), "grain_ridge": (184, 138, 58), "timber": (104, 76, 54), "mud_wall": (176, 150, 116),
    "mud_cap": (120, 104, 90), "lime": (220, 212, 190), "roof_tin": (126, 118, 112), "stall_dark": (44, 36, 30),
    "quilt_red": (184, 52, 62), "quilt_teal": (38, 126, 124), "quilt_pink": (232, 152, 160),
    "quilt_yellow": (236, 192, 70), "peony": (246, 226, 214), "leaf": (64, 120, 72), "window_warm": (244, 206, 140),
    "wire": (62, 60, 58), "stool": (150, 104, 66), "rake": (170, 132, 82), "coop_wire": (150, 150, 140),
}


def unlit(b, name, rgb, energy=1.0):
    r, g, bl = (round(c / 255.0 * energy, 3) for c in rgb)
    b.mat(name, shading_mode=0, albedo_color=f"Color({r:g}, {g:g}, {bl:g}, 1)")


def label(b, name, parent, pos, text, size=.0026, rot=(0, 0, 0), ink=(245, 240, 226)):
    b.node(name, parent, "Label3D", position=vec3(pos), rotation_degrees=vec3(rot), text=f'"{text}"',
           font_size=44, pixel_size=f"{size:g}", outline_size=0, modulate=srgb(ink))


def solid(b, name, parent, pos, size, *, fade=True, rot=(0, 0, 0)):
    p = b.shell(name, parent, pos, rot, ("camera_occluder",) if fade else ())
    b.shape("Solid", p, (0, size[1] / 2, 0), size)
    return p


# --- 02 -> 03: the stair becomes a down escalator -----------------------------------------

def escalator(b):
    s = "Escalator"
    b.node(s, ".", position=vec3(STAIR_ORIGIN), rotation_degrees=vec3((0, 90, 0)))
    run, rise, width = STAIR_RUN, RISE, WEST_STAIR_WIDTH
    length, pitch = math.hypot(run, rise), math.degrees(math.atan2(rise, run))
    belt = b.bind("dream_escalator", "res://assets/shaders/school/dream_escalator.gdshader", "Shader")
    b.local_mats["belt"] = (f'[sub_resource type="ShaderMaterial" id="Mat_belt"]\nshader = {belt}\n'
                            f"shader_parameter/width = {width - .02:g}\nshader_parameter/step_length = {length/20:.4f}\n")
    # One tilted frame on the line of the walkable slope. The belt covers the treads'
    # nosings; the player still walks on the teaching block's own ramp collider.
    b.node("Tilt", s, position=vec3((0, rise / 2, -run / 2)), rotation_degrees=vec3((pitch, 0, 0)))
    t = child_path(s, "Tilt")
    b.flat("Belt", t, plane(b, width - .02, length + .02), "belt", (0, .094, 0))
    for side, x in (("West", -1), ("East", 1)):
        gx = x * (width / 2 + .065)
        b.box(f"Skirt{side}", t, (gx, .54, 0), (.18, 1.09, length + .03), "steel", shadow=True)
        b.box(f"Deck{side}", t, (gx, 1.1, 0), (.24, .03, length + .2), "graphite")
        b.box(f"Handrail{side}", t, (gx, 1.16, 0), (.11, .08, length + .55), "rubber", shadow=True)
        b.box(f"Brush{side}", t, (x * (width / 2 - .015), .17, 0), (.03, .05, length), "lemon")
    # Thin bars of light over the slope, not a ceiling across the follow camera.
    for i in range(6):
        b.box(f"LightBar{i}", t, (0, 2.75, -length / 2 + .7 + i * (length - 1.4) / 5), (width + .5, .05, .07), "metro_light")
    for name, z, y in (("CombFoot", .27, .006), ("CombHead", -run - .27, rise + .006)):
        b.box(name, s, (0, y, z), (width - .04, .012, .54), "steel")
        for i in range(9):
            b.box(f"{name}Tooth{i}", s, (-width / 2 + .2 + i * (width - .4) / 8, y + .009, z + (.2 if z > 0 else -.2)),
                  (.06, .008, .12), "lemon")
    b.box("HeadNewelWest", s, (-width / 2 - .065, rise + 1.0, -run - .25), (.24, .2, .62), "rubber", shadow=True)
    b.box("HeadNewelEast", s, (width / 2 + .065, rise + 1.0, -run - .25), (.24, .2, .62), "rubber", shadow=True)

    # A metro totem at the mouth: the floor number is the only promise it makes.
    b.node("Totem", ".", position=vec3((-1.86, 0, -6.12)))
    b.box("Post", "Totem", (0, 1.15, 0), (.16, 2.3, .16), "graphite", shadow=True)
    b.box("Box", "Totem", (0, 2.08, .02), (.5, .66, .2), "wayfind", shadow=True)
    b.box("Face", "Totem", (0, 2.08, .124), (.42, .58, .01), "metro_light")
    b.box("Disc", "Totem", (0, 2.2, .132), (.3, .3, .006), "vermilion")
    label(b, "Floor", "Totem", (0, 2.2, .137), "03", .0042)
    label(b, "Line", "Totem", (0, 1.92, .137), "EXAM ↑", .0019, ink=(28, 36, 58))
    label(b, "Back", "Totem", (0, 2.08, -.084), "↓ 02", .0028, rot=(0, 180, 0))


def ticket_counter(b):
    """01, right after the glass threshold, with the wide face on the gallery side."""
    c = "TicketCounter"
    # To the entrant's right, outside the 2.66 m clear span. Set it in from the
    # wall for a clear camera ray on turning, but short of the gallery's east
    # lane, including the navigation bake's 0.50 m radius and voxel margin.
    b.node(c, ".", position=vec3((ENTRANCE_X + 4.03, G, GROUND_Z[1] - 1.16)),
           rotation_degrees=vec3((0, 180, 0)))
    body = solid(b, "Booth", c, (0, 0, 0), (3.02, .984, 1.12), fade=False)
    b.box("Plinth", body, (0, .491, .437), (3.02, .922, .226), "ticket_enamel", shadow=True)
    b.box("Kick", body, (0, .088, .557), (2.97, .166, .024), "graphite")
    b.box("Counter", body, (0, .958, .299), (3.06, .052, .574), "steel", shadow=True)
    b.box("Back", body, (0, .337, -.507), (3.0, .67, .072), "ticket_enamel", shadow=True)
    for side in (-1, 1):
        b.box(f"End{side+1}", body, (side*1.48, .463, 0), (.06, .926, 1.115), "ticket_enamel", shadow=True)
    b.box("SignBand", body, (0, .694, .555), (2.91, .164, .018), "lemon")
    label(b, "HeadText", body, (0, .694, .567), "EXAM FEE  ·  TICKETS", .00175, ink=(28, 36, 58))
    tracks = []
    for i, x in enumerate(STATIONS):
        b.box(f"Slot{i}", body, (x, .87, .558), (.27, .029, .018), "graphite")
        b.box(f"Open{i}", body, (x+.20, .87, .559), (.064, .029, .019), "led")
        b.round(f"Roll{i}", body, (x-.252, 1.026, .321), .043, .084, "paper", sides=10)
        b.box(f"Ticket{i}", body, (x+.199, .986, PRESS_Z), (.100, .004, .104), "paper")
        b.box(f"Stool{i}", body, (x, .242, -.235), (.352, .484, .319), "graphite")
        tracks.append(build_clerk(b, body, i, x))
    stamp_loop(b, body, tracks)


# --- 03: an exam floor that is also a waiting room ----------------------------------------

def bay_frame(b, parent, name, west, spec):
    centre = spec[0]
    pos, yaw = ((-14.25, RISE, centre), 90) if west else ((centre, RISE, -45.0), 0)
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)))
    return child_path(parent, name)


def exam_floor(b):
    e = "ExamFloor"
    b.node(e, ".")
    # Paper on every door: an exam-room number in marker, and the numbers disagree.
    numbers = iter(("07", "07", "13", "00", "07", "21", "07", "09", "07", "—"))
    rng = random.Random(1120)
    for west, specs in ((True, UPPER_WEST), (False, UPPER_NORTH)):
        for i, spec in enumerate(specs):
            p = bay_frame(b, e, f"{'West' if west else 'North'}Bay{i}", west, spec)
            for j, x in enumerate((-3.55, 3.55)):
                tilt = rng.uniform(-6, 6)
                b.node(f"Notice{j}", p, position=vec3((x, 1.52, .062)), rotation_degrees=vec3((0, 0, tilt)))
                n = child_path(p, f"Notice{j}")
                b.box("Sheet", n, (0, 0, 0), (.3, .42, .006), "paper")
                b.box("TapeTop", n, (0, .2, .004), (.12, .035, .004), "tile_white")
                label(b, "Room", n, (0, .1, .005), "EXAM ROOM", .0011, ink=(36, 38, 44))
                label(b, "Number", n, (0, -.06, .005), next(numbers), .0045, ink=(40, 74, 162))
            # Inside, behind the high slit: desks pushed askew and paper on the floor.
            depth, bias = spec[3], spec[4]
            for k in range(7):
                x, z = rng.uniform(-2.6, 2.6), rng.uniform(-depth + 1.2, -1.0)
                b.box(f"Dropped{k}", p, (x, bias + .012 + k * .001, z), (.21, .004, .3), "paper",
                      rot=(0, rng.uniform(0, 180), 0))
            b.box("TippedChair", p, (1.2, bias + .2, -2.9), (.42, .4, .42), "graphite", rot=(0, 31, 78))
    # A seating plan painted on the 03 floor, off-square, as if the corridor were the hall.
    b.node("SeatingGrid", e, position=vec3((-12.0, RISE + .006, -30.5)), rotation_degrees=vec3((0, 2.5, 0)))
    g = child_path(e, "SeatingGrid")
    seat = 1
    for row in range(3):
        for col in range(9):
            if (row, col) in ((1, 4), (2, 7)):
                continue
            x, z = -1.15 + row * 1.15, -8.4 + col * 2.05
            for k, (dx, dz, w, d) in enumerate(((0, -.27, .82, .03), (0, .27, .82, .03), (-.41, 0, .03, .57), (.41, 0, .03, .57))):
                b.box(f"Seat{seat}_{k}", g, (x + dx, 0, z + dz), (w, .004, d), "paper")
            label(b, f"SeatNo{seat}", g, (x, .004, z), f"{seat:02d}", .0034, rot=(-90, 0, 0), ink=(226, 222, 206))
            seat += 1
    # Hard colour fields on the walls: modern wayfinding that leads nowhere in particular.
    for i, (west, spec_i, x, y, w, h, colour) in enumerate((
        (True, 0, 0, .8, 3.6, .9, "cobalt"), (True, 1, 1.8, .5, 1.5, 2.2, "vermilion"),
        (True, 2, .6, 1.1, 4.0, .45, "lemon"), (False, 0, 0, .7, 3.0, 1.1, "lemon"),
        (False, 1, -1.75, .5, 1.2, 1.8, "cobalt"),
    )):
        p = child_path(e, f"{'West' if west else 'North'}Bay{spec_i}")
        b.box(f"Field{i}", p, (x, y + h / 2, .118), (w, h, .012), colour)
    b.box("FloorRule", e, (-13.9, RISE + .008, -26.0), (.16, .006, 38.0), "vermilion")
    b.box("FloorRuleTurn", e, ((OFFICE_X - 13.98) / 2, RISE + .008, -44.62), (OFFICE_X + 13.98, .006, .16), "vermilion")

    # Queue footprints to the staff office. The last pairs face the wrong way.
    for i in range(14):
        x = 9.2 + i * .62
        back = i >= 11
        ink = "graphite" if not back else "vermilion"
        for k, dz in enumerate((-.14, .14)):
            fx, fz = x + (.08 if k else 0), -42.0 + dz + (.15 if back else 0)
            b.box(f"Step{i}_{k}", e, (fx, RISE + .009, fz), (.22, .005, .09), ink)
            b.box(f"Toe{i}_{k}", e, (fx + (-.15 if back else .15), RISE + .009, fz), (.06, .005, .08), ink)
    # Turned chairs along the walls, drifting a little on their lifts.
    for i, (pos, yaw) in enumerate((((-13.62, RISE, -21.6), -90), ((-13.6, RISE, -23.1), -84),
                                    ((-13.66, RISE, -25.6), -97), ((10.2, RISE, -44.35), 180),
                                    ((12.0, RISE, -44.3), 172), ((-5.2, RISE, -44.35), 190))):
        swivel_chair(b, e, f"TurnedChair{i}", pos, yaw, i * .17)
    # Chat and revision by the glass, and the pair at the dented plaster.
    t = exam_candidates(b, e, RISE)
    for k, (dz, dy, w) in enumerate(((0, 1.3, .18), (.1, 1.22, .07), (-.08, 1.38, .09), (.05, 1.45, .05))):
        b.box(f"Dent{k}", t, (-.597, dy, dz), (.006, w, w * .8), "graphite")
    # Now serving: nobody.
    b.node("NowServing", e, position=vec3((OFFICE_X - 1.6, RISE, -40.9)))
    n = child_path(e, "NowServing")
    b.box("Pole", n, (0, 1.0, 0), (.07, 2.0, .07), "steel", shadow=True)
    b.box("Screen", n, (0, 2.15, 0), (.9, .42, .1), "graphite", shadow=True)
    label(b, "Number", n, (0, 2.15, .056), "— — —", .0034, ink=(226, 64, 48))
    label(b, "Caption", n, (0, 1.88, .056), "NOW SERVING", .0014)


# --- behind 01: the stable yard and the dream house ----------------------------------------

def low_wall(b, parent, name, a, z_or_x, along_x, height=1.25, *, end_trim=0.0):
    lo, hi = a
    length = hi - lo
    pos = ((lo + hi) / 2, G, z_or_x) if along_x else (z_or_x, G, (lo + hi) / 2)
    size = (length, height, .3) if along_x else (.3, height, length)
    p = solid(b, name, parent, pos, size)
    # Trim the visual end where it would overlap the perpendicular return, but keep
    # the original collision shape. Adjoining caps stop at their wall ends as well.
    visual = (size[0] - end_trim * along_x, size[1], size[2] - end_trim * (not along_x))
    dx = -end_trim / 2 if along_x and end_trim else 0.0
    dz = -end_trim / 2 if not along_x and end_trim else 0.0
    b.box("Mud", p, (dx, height / 2 - .05, dz), (visual[0], height - .1, visual[2]), "mud_wall", shadow=True)
    b.box("Cap", p, (dx, height - .04, dz), (visual[0], .1, visual[2]), "mud_cap")
    # The stripe must sit just outside the mud, not share its two long faces.
    b.box("Lime", p, (dx, .45, dz),
          (visual[0] - .02 if along_x else visual[0] + .02, .3,
           visual[2] + .02 if along_x else visual[2] - .02), "lime")


def yard_ground(b, y):
    slab(b, y, "Lane", LANE_X, LANE_Z, G)
    slab(b, y, "Yard", YARD_X, YARD_Z, G)
    # Everything past the wall is village ground, never walkable.
    # Round 22: the same front-yard dirt as the yard, a shade darker.
    b.box("VillageGround", y, (-49.5, G - .13, 6), (45, .2, 40), dream_stable.earth_material(b, .75))
    # Round 19: the yard and lane are uneven earth over the flat slabs (tools/stable_ground.py).
    dream_stable.yard_ground(b, y)


def quilts(b, y):
    q = solid(b, "QuiltLine", y, (-37.8, G, 12.0), (4.8, 1.85, .12))
    for i, x in enumerate((-2.45, 2.45)):
        b.box(f"Pole{i}", q, (x, 1.05, 0), (.07, 2.1, .07), "timber", shadow=True)
    b.box("Wire", q, (0, 2.0, 0), (4.9, .015, .015), "wire")
    # Round 18: three modelled quilts folded over the wire, with soft folds and printed motifs.
    for i, x in enumerate((-1.6, 0, 1.6)):
        dream_stable.quilt(b, q, f"Quilt{i}", (x, 2.0, 0), i)


def dream_house(b, y):
    h = "DreamHouse"
    x0, x1 = HOUSE_X
    z0, z1 = HOUSE_Z
    w, d = x1 - x0, z1 - z0
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    body = solid(b, h, y, (cx, G, cz), (w, HOUSE_TOP, d), fade=False)
    # 1F: stalls open to the east; 2F: a lit ticket hall that nobody can reach. The stalls are
    # deep enough (round 18) for a full-sized horse to stand in, head over the half door.
    stall_back = 2.8
    b.box("WestWall", body, (-w / 2 + .12, HOUSE_STOREY / 2, 0), (.24, HOUSE_STOREY, d), "mud_wall", shadow=True)
    b.box("NorthWall", body, (0, HOUSE_STOREY / 2, -d / 2 + .12), (w, HOUSE_STOREY, .24), "mud_wall", shadow=True)
    b.box("SouthWall", body, (0, HOUSE_STOREY / 2, d / 2 - .12), (w, HOUSE_STOREY, .24), "mud_wall", shadow=True)
    b.box("StallBack", body, (w / 2 - stall_back, HOUSE_STOREY / 2, 0), (.2, HOUSE_STOREY, d - .4), "stall_dark")
    b.box("StallFloor", body, (w / 2 - stall_back / 2, .02, 0), (stall_back, .04, d - .4),
          dream_stable.earth_material(b, .8))
    b.box("UpperFloor", body, (0, HOUSE_STOREY + .1, 0), (w + .1, .22, d + .1), "timber", shadow=True)
    # 2F is solid except for a one-metre slice behind the south window.
    top, sill, head, hall = HOUSE_TOP, HOUSE_STOREY + .8, HOUSE_STOREY + 2.1, 1.0
    mid = (HOUSE_STOREY + .21 + top) / 2
    tall = top - HOUSE_STOREY - .21
    b.box("Upper", body, (0, mid, -hall / 2), (w, tall, d - hall), "lime", shadow=True)
    b.box("HallBack", body, (.3, (sill + head) / 2, d / 2 - hall + .005), (5.0, head - sill, .01), "window_warm")
    for name, x, width in (("HallEndWest", -w / 2 + .12, .24), ("HallEndEast", w / 2 - .12, .24)):
        b.box(name, body, (x, mid, d / 2 - hall / 2), (width, tall, hall), "lime", shadow=True)
    face = d / 2 - .1
    for name, pos, size in (("Sill", (0, (HOUSE_STOREY + .21 + sill) / 2, face), (w, sill - HOUSE_STOREY - .21, .2)),
                            ("Lintel", (0, (head + top) / 2, face), (w, top - head, .2)),
                            ("PierWest", ((-w / 2 - 2.2) / 2, (sill + head) / 2, face), (w / 2 - 2.2, head - sill, .2)),
                            ("PierEast", ((w / 2 + 2.8) / 2, (sill + head) / 2, face), (w / 2 - 2.8, head - sill, .2))):
        b.box("Hall" + name, body, pos, size, "lime", shadow=True)
    b.box("HallGlass", body, (.3, (sill + head) / 2, d / 2 - .02), (5.0, head - sill, .01), "booth_glass")
    b.box("Roof", body, (0, HOUSE_TOP + .06, 0), (w + .5, .12, d + .5), "roof_tin", shadow=True)
    posts = (-d / 2 + .1, -d / 6, d / 6, d / 2 - .1)
    for i, z in enumerate(posts):
        # Round 22: 22 cm posts, 1 cm proud of the stall front and of the end walls they
        # stand against, instead of sharing those faces (the corner posts flickered).
        b.box(f"Post{i}", body, (w / 2 - .1, HOUSE_STOREY / 2, z), (.22, HOUSE_STOREY, .22), "timber", shadow=True)
    for i in range(3):
        z = (posts[i] + posts[i + 1]) / 2
        b.box(f"Partition{i}", body, (w / 2 - stall_back / 2 - .01, .8, posts[i + 1]), (stall_back - .02, 1.6, .08),
              "timber")
        b.node(f"StallLamp{i}", body, "OmniLight3D", position=vec3((w / 2 - .9, 2.5, z)),
               light_color=srgb((255, 204, 150)), light_energy=1.7 if i == 0 else .95,
               omni_range=4.4 if i == 0 else 3.8)
    # Round 18: sculpted horses with their heads over the half doors, grazing at their own pace.
    dream_stable.horse(b, body, "BayHorse", (w / 2 - 1.15, 0, (posts[0] + posts[1]) / 2), 90, dream_stable.sa.BAY,
                       graze=.62, phase=.1)
    dream_stable.horse(b, body, "GreyHorse", (w / 2 - 1.17, 0, (posts[2] + posts[3]) / 2), 84, dream_stable.sa.GREY,
                       graze=.34, phase=.55, swish=.2, rate=.05)
    dream_stable.stall_dressing(b, body, w, d, stall_back, posts)
    # The only way in: a small doorway at the south-west corner, easy to walk past.
    b.box("CornerDoorway", body, (-w / 2 + .75, 1.0, d / 2 + .004), (.82, 1.96, .02), "void")
    b.box("CornerStep", body, (-w / 2 + .75, .05, d / 2 + .2), (1.0, .1, .4), "mud_cap")
    b.box("CornerPlate", body, (-w / 2 + .75, 2.14, d / 2 + .02), (.16, .12, .01), "lime")
    label(b, "CornerNumber", body, (-w / 2 + .75, 2.14, d / 2 + .03), "1", .002, ink=(70, 64, 58))
    # Three seated silhouettes in the lit slice, all stamping in step.
    for i, x in enumerate((-1.3, .3, 1.9)):
        b.box(f"ClerkStool{i}", body, (x - .05, HOUSE_STOREY + .45, d / 2 - .5), (.3, .48, .3), "coat_ink")
        figure(b, body, f"Clerk{i}", (x - .2, HOUSE_STOREY + .31, d / 2 - .5), 90,
               {"coat": "coat_ink", "hair": "coat_ink", "skin": "coat_ink"}, pose="sit", hand="stamp",
               phase=0.0, shadow=False)
    b.box("Sign", body, (w / 2 + .06, 4.5, -.6), (.06, .9, 2.4), "wayfind", shadow=True)
    label(b, "SignText", body, (w / 2 + .095, 4.68, -.6), "TICKETS", .0036, rot=(0, 90, 0))
    label(b, "SignSub", body, (w / 2 + .095, 4.3, -.6), "EXAM · 2F →", .0021, rot=(0, 90, 0), ink=(238, 206, 72))
    b.node("SignLight", body, "OmniLight3D", position=vec3((w / 2 + .9, 4.5, -.6)),
           light_color=srgb((214, 226, 255)), light_energy=.5, omni_range=4.0)
    sky_escalator(b, body, (-w / 2 + 3.0, HOUSE_TOP, -d / 2 + 1.4))


def sky_escalator(b, parent, base):
    """Leaves the roof toward the north and stops in the air. The riders keep going."""
    run, rise, width = 11.5, 5.6, 1.4
    length, pitch = math.hypot(run, rise), math.degrees(math.atan2(rise, run))
    b.node("SkyEscalator", parent, position=vec3(base))
    s = child_path(parent, "SkyEscalator")
    b.node("Tilt", s, position=vec3((0, rise / 2, -run / 2)), rotation_degrees=vec3((pitch, 0, 0)))
    t = child_path(s, "Tilt")
    b.box("Truss", t, (0, -.35, 0), (width + .2, .7, length), "steel", shadow=True)
    b.flat("Belt", t, plane(b, width, length), "belt_sky", (0, .005, 0))
    for side, x in (("West", -1), ("East", 1)):
        b.box(f"Glass{side}", t, (x * (width / 2 + .05), 1.05, 0), (.02, 2.1, length), "booth_glass")
        b.box(f"Rail{side}", t, (x * (width / 2 + .05), 1.0, 0), (.08, .07, length), "rubber")
    b.box("GlassRoof", t, (0, 2.1, 0), (width + .1, .02, length), "booth_glass")
    b.box("Void", s, (0, rise + 1.05, -run - .02), (width + .14, 2.15, .04), "void")
    b.box("VoidFrame", s, (0, rise + 1.05, -run - .07), (width + .34, 2.34, .03), "metro_light")
    top = rise * .62 - .75
    b.box("Mast", s, (0, (top - HOUSE_TOP) / 2, -run * .62), (.18, top + HOUSE_TOP, .18), "steel", shadow=True)
    # The riders face up the slope (their +Z is the escalator's -Z).
    travel = (0, rise, run)
    extra = {"travel": travel, "travel_rate": .045, "fade_edge": .12}
    for i in range(7):
        figure(b, s, f"Rider{i}", ((i % 2) * .3 - .15, .05, 0), 180,
               {"coat": ("coat_grey", "coat_navy", "coat_olive", "coat_cream")[i % 4]},
               pose="bowed", body="rider_sky", phase=i / 7, extra=extra, shadow=False)


def chickens_and_smell(b, y):
    # Round 18: a modelled hen house with a wire run, sculpted hens, and the muck kept in a bay.
    coop = solid(b, "Coop", y, (-28.6, G, 6.2), (2.2, 1.3, 1.6))
    dream_stable.coop(b, coop)
    white, brown = dream_stable.sa.WHITE_HEN, dream_stable.sa.BROWN_HEN
    dream_stable.hens(b, coop, (("CoopHen0", (.35, 0, .25), 200, brown, .0),
                                ("CoopHen1", (.78, 0, -.12), -70, white, .37)))
    dream_stable.hens(b, y, (("YardHen0", (-29.7, G, 7.9), 20, white, .21),
                             ("YardHen1", (-28.5, G, 8.1), 205, brown, .58),
                             ("YardHen2", (-30.3, G, 9.3), 95, brown, .83)))
    b.node("Heap", y, position=vec3(dream_stable.HEAP), rotation_degrees=vec3((0, dream_stable.HEAP_YAW, 0)))
    dream_stable.heap(b, y, child_path(y, "Heap"))
    dream_stable.flies(b, y)
    dream_stable.stink(b, y)
    # One faint trace of the smell over the heap.
    odor = b.bind("dream_odor", "res://assets/shaders/school/dream_odor.gdshader", "Shader")
    mat = shader_material(b, "odor", odor, {"phase": 0.0, "tint": "Color(0.6, 0.6, 0.45, 1)"})
    b.node("Smell0", y, "MeshInstance3D", position=vec3((dream_stable.HEAP[0], G + 1.5, dream_stable.HEAP[2] + .3)),
           mesh=f'SubResource("{quad(b, .6, 2.4)}")', material_override=b.surface(mat), cast_shadow=0)


def village(b, y):
    rng = random.Random(9)
    for i, (x, z, w, d, hgt) in enumerate(((-47, -2, 6, 5, 3.2), (-46, 10, 5, 7, 2.8), (-45, 21, 6, 5, 3.6),
                                           (-36, -4, 7, 5, 3.0), (-27, -6, 5, 4, 2.6))):
        b.node(f"House{i}", y, position=vec3((x, G, z)))
        p = child_path(y, f"House{i}")
        b.box("Mass", p, (0, hgt / 2, 0), (w, hgt, d), "mud_wall" if i % 2 else "lime", shadow=True)
        b.box("Roof", p, (0, hgt + .08, 0), (w + .4, .16, d + .4), "roof_tin", shadow=True)
        b.box("Door", p, (w / 2 - 1.2, .9, d / 2 + .01), (.8, 1.8, .02), "stall_dark")
        b.box("Window", p, (-w / 4, 1.7, d / 2 + .01), (.9, .7, .02), "window_warm" if i % 2 == 0 else "stall_dark")
        if rng.random() < .7:
            b.box("Laundry", p, (0, hgt + .7, d / 2 - .4), (w * .6, .6, .03), ("quilt_pink", "quilt_teal", "quilt_yellow")[i % 3])


def stable_yard(b):
    y = "StableYard"
    # Move the complete yard west, away from the separate restroom volume.
    # The connecting strip remains at the entrance so the route stays walkable.
    b.node(y, ".", position=vec3((-4, 0, 0)))
    slab(b, ".", "StableLaneConnector", (-24.8, -20.75), LANE_Z, G)
    # The connector is a flat walking surface, but shares the yard's soil; the dirt is laid
    # in world space (round 22), so it meets the relief with no offset.
    connector_x, connector_z = -22.75, sum(LANE_Z) / 2
    connector_soil = dream_stable.earth_material(b)
    # Meet the relief at x = -24.75 rather than overlapping its last five centimetres.
    b.flat("StableLaneConnectorEarth", ".", plane(b, 4.0, LANE_Z[1]-LANE_Z[0]), connector_soil,
           (connector_x, G + .004, connector_z))
    yard_ground(b, y)
    low_wall(b, y, "WallSouth", (LANE_X[0], LANE_X[1]), LANE_Z[1] + .15, True)
    low_wall(b, y, "WallWest", (HOUSE_Z[1], LANE_Z[1]), LANE_X[0] - .15, False)
    low_wall(b, y, "WallNorth", (HOUSE_X[1], YARD_X[1] + .02), YARD_Z[0] - .15, True, end_trim=.02)
    low_wall(b, y, "WallNorthEast", (YARD_Z[0] - .3, 5.52), YARD_X[1] + .15, False)
    dream_house(b, y)
    quilts(b, y)
    # Round 18: one mat of grain between the two women, so the middle of the yard stays open.
    dream_stable.grain(b, y, "GrainMat0", (-31.2, G, 12.7), (3.0, 2.0), 4)
    # Round 19: two sculpted women at work - one shakes grain through a sieve on a low stool,
    # the other draws a grain rake through it (tools/stable_workers.py, tools/stable_people.py).
    import stable_people
    stable_people.sifter(b, y, "OldWoman0", (-33.1, G, 12.4), 90)
    stable_people.raker(b, y, "OldWoman1", (-28.6, G, 12.9), -90)
    # The bales are stacked out of the way at the lane's west end, and stand solid.
    stack = solid(b, "HayStack", y, (-39.45, G, 17.62), (1.0, 1.0, 1.1), fade=False)
    for i, (pos, yaw) in enumerate((((0, 0, -.27), 0), ((0, 0, .27), 2), ((0, .45, 0), 84))):
        dream_stable.bale(b, stack, f"HayBale{i}", pos, yaw)
    chickens_and_smell(b, y)
    village(b, y)
    # A metro pictogram where the lane leaves the glass entrance: a horse and an arrow.
    b.node("Pictogram", y, position=vec3((-21.2, G, 18.0)))
    p = child_path(y, "Pictogram")
    b.box("Post", p, (0, 1.0, 0), (.1, 2.0, .1), "graphite", shadow=True)
    b.box("Board", p, (.06, 2.05, 0), (.06, .62, 1.0), "metro_light", shadow=True)
    for name, (pz, py, w, h) in (("Body", (0, 2.08, .36, .14)), ("Neck", (-.17, 2.18, .06, .16)),
                                 ("Head", (-.23, 2.25, .14, .06)), ("FrontLeg", (-.12, 1.94, .04, .16)),
                                 ("BackLeg", (.13, 1.94, .04, .16)), ("Tail", (.21, 2.08, .04, .12))):
        b.box(f"Horse{name}", p, (.095, py, pz), (.01, h, w), "wayfind")
    label(b, "Arrow", p, (.1, 1.86, 0), "↑", .004, rot=(0, 90, 0), ink=(28, 36, 58))
    lane_barrier(b, y)
    for i, (pos, energy) in enumerate((((-34.0, G + 2.7, 13.0), .9), ((-29.6, G + 2.8, 8.0), .7),
                                       ((-23.5, G + 2.6, 16.6), .55))):
        b.node(f"YardLight{i}", y, "OmniLight3D", position=vec3(pos), light_color=srgb((255, 214, 160)),
               light_energy=energy, omni_range=8.5)


# Round 23: a horizontal board (挡板) across the lane's mouth, so the stable is no longer
# somewhere the player drifts into from the glass entrance. It closes the south of the lane
# and leaves a squeeze against the teaching block's wall that is still wider than the
# navigation agent (radius 0.5) plus a cell, so the yard stays routed (dream_annex_test).
BARRIER_X = LANE_X[1] - .2
BARRIER_Z = (16.35, LANE_Z[1] - .1)


def lane_barrier(b, y):
    z0, z1 = BARRIER_Z
    span = z1 - z0
    bar = solid(b, "LaneBarrier", y, (BARRIER_X, G, (z0 + z1) / 2), (.16, 1.15, span))
    for i, z in enumerate((-span / 2 + .06, span / 2 - .06)):
        b.box(f"Post{i}", bar, (0, .6, z), (.1, 1.2, .1), "timber", shadow=True)
    b.box("LowBoard", bar, (0, .42, 0), (.05, .24, span - .2), "timber", shadow=True)
    # The top board is painted in red and white stripes, the usual 挡板.
    count = 6
    for i in range(count):
        length = (span - .2) / count
        b.box(f"Stripe{i}", bar, (0, .92, -span / 2 + .1 + length * (i + .5)), (.06, .26, length),
              "vermilion" if i % 2 == 0 else "paper", shadow=True)


WAITING_LOOKS = (
    {"seat": "pomo_pink", "back": "pomo_black", "frame": "pomo_black", "crest": "pomo_lemon"},
    {"seat": "pomo_lemon", "back": "pomo_cobalt", "frame": "pomo_black", "crest": "pomo_red"},
    {"seat": "pomo_mint", "back": "pomo_pink", "frame": "pomo_black", "crest": "pomo_cobalt"},
    {"seat": "pomo_cobalt", "back": "pomo_lilac", "frame": "pomo_black", "crest": "pomo_mint"},
)


def waiting_room(b):
    """The staff office as the dream's waiting room: chairs turned away, cliques with snacks.

    Called from build_school_rooms.office(). Visual only: no collider joins the room's
    routes or the inspection shots, and nothing here is an actor.
    """
    b.pigments.update({k: v for k, v in PIGMENTS.items() if k not in b.pigments})
    w = "WaitingRoom"
    b.node(w, ".")
    for i, (pos, yaw) in enumerate((((.2, 0, -2.0), 180), ((3.55, 0, 1.6), 90), ((-.6, 0, 2.55), 0),
                                    ((-3.85, 0, 1.25), -90))):
        # Round 2 (2026-11-20): postmodern upholstery, still turning away on the lift.
        swivel_chair(b, w, f"TurnedChair{i}", pos, yaw, i * .23, look=WAITING_LOOKS[i])
    waiting_candidates(b, w)
    q = child_path(w, "Clique0")
    rng = random.Random(40)
    for k in range(14):
        b.box(f"Shell{k}", q, (rng.uniform(-.6, .6), .004, rng.uniform(-.5, .5)), (.02, .004, .012), "paper",
              rot=(0, rng.uniform(0, 180), 0))
    b.node("Number", w, position=vec3((-.4, 1.95, -2.99)))
    b.box("Card", "WaitingRoom/Number", (0, 0, 0), (.62, .4, .01), "paper")
    label(b, "Text", "WaitingRoom/Number", (0, .07, .007), "WAITING ROOM", .0012, ink=(36, 38, 44))
    label(b, "Seat", "WaitingRoom/Number", (0, -.07, .007), "EXAM — —", .0016, ink=(222, 76, 52))


def annex():
    b = FixtureBuild("DreamAnnex", PIGMENTS)
    b.stable_files = {}
    unlit(b, "metro_light", (238, 242, 246), .96)
    unlit(b, "void", (6, 6, 9))
    unlit(b, "window_warm", PIGMENTS["window_warm"])
    unlit(b, "led", PIGMENTS["led"])
    b.mat("booth_glass", transparency=1, cull_mode=2, albedo_color="Color(0.62, 0.78, 0.84, 0.22)")
    belt = b.bind("dream_escalator", "res://assets/shaders/school/dream_escalator.gdshader", "Shader")
    b.local_mats["belt_sky"] = (f'[sub_resource type="ShaderMaterial" id="Mat_belt_sky"]\nshader = {belt}\n'
                                "shader_parameter/width = 1.4\nshader_parameter/speed = -0.5\n")
    escalator(b)
    ticket_counter(b)
    exam_floor(b)
    stable_yard(b)
    return b
