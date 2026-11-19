#!/usr/bin/env python3
"""Build the three walkable school floors and the view through their windows.

The hand-authored corridor.tscn owns the story exits, spawn markers, audio and library
props. This tool owns the measured structure. Run it with --check to check the
shipped PackedScenes rather than replacing the runtime layout from an editor script.
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOC = ROOT / "scenes/locations/corridor"
PROPS = "res://scenes/environment/props"
STAGE = f"{PROPS}/stage_art"
YARD = f"{PROPS}/playground_art"
sys.path.insert(0, str(ROOT / "scenes/environment/props/playground_art/source"))
from build_playground_art import (  # noqa: E402
    Builder, HIDE, court_landmarks, material_for, plane, quad, school_exit_fittings,
    school_plinth_returns, srgb, vec3,
)
from build_outdoor_locations import BAKE_ONLY_LAYER, PLAYER_ONLY_LAYER, build_playground  # noqa: E402
from school_annex_layout import (  # noqa: E402
    ARCHIVE, PLAN_ROOM, PROJECTION, COMPUTER, VACANT, PRINCIPAL, WASH_02, WASH_03, THRESHOLDS,
)

# Geometry in metres. +Z is the local face of each facade. Upper wings are set back
# west and north of the lower walk (no upper slab between the fixed camera and player).
WALL_HEIGHT = 3.15
RISE = 3.6
MAIN_X = (-2.2, 2.2)
MAIN_Z = (-30, 6.95)
TURN_Z = (-30, -25.5)
EAST_END = 29.0
YARD_X = 15.6
YARD_WIDTH = 3.2
YARD_APPROACH_Z = TURN_Z[1]
YARD_RUN = 5.6
YARD_Y = -3.4
YARD_PORTAL_Z = -18.0
# Align the two faces of the fire door. The painted court has yard-local coordinates.
YARD_OFFSET = (YARD_X + 3.0, YARD_Y, YARD_PORTAL_Z + 19.90)
UPPER_X = (-14.25, -9.75)
UPPER_Z = (-45.0, -6.5)
UPPER_TURN = (-45.0, -40.5)
UPPER_END = 20.65
OFFICE_X = 18.48
RESTROOM_Z = 12.56
ROOM_PORTAL_WIDTH = 1.84
# A second stair hall, beyond the biology rear door (+Z). Both branches leave
# the same 02 floor and turn on level landings. The new 01 is at yard grade.
REAR_JUNCTION_Z = (3.45, MAIN_Z[1])
REAR_JUNCTION_X = (-4.95, MAIN_X[0])
UPPER_JOIN_Z = -0.65
GROUND_Y = YARD_Y
GROUND_X = (-26.8, -9.1)
GROUND_Z = (10.55, 14.55)
ENTRANCE_X = -17.65
ENTRANCE_WIDTH = 6.2
ENTRANCE_APRON_END = 18.45
WEST_STAIR_Z = -8.45
WEST_STAIR_WIDTH = 3.2
BEND_STAIR_WIDTH = 2.8
BEND_STAIR_X = 4.5

# (centre along the run, width, room plate, depth, floor bias). The repeated plates and
# the shifted floors/landings are architecture; routes do not secretly teleport.
LOWER_WEST = [(-1.55, 10, "101", 5.6, 0), (-15.25, 9.5, "102", 5.2, -0.22),
              (-24.8, 9.0, "104", 6.4, 0.18)]
LOWER_NORTH = [(11.45, 10, "104", 5.8, -0.31), (23.05, 10, "105", 6.3, 0)]
UPPER_WEST = [(-12.2, 9, "201", 6.6, 0), (-23.5, 9.5, "202", 5.1, 0.22),
              (-35.1, 10, "202", 6.1, -0.30)]
UPPER_NORTH = [(-3.5, 9.5, "204", 5.6, 0.22), (11.2, 10.5, "205", 7.2, -0.45)]

DOOR_WIDTH = 1.205
DOOR_HEIGHT = 2.207
DOOR_SPACING = 7.10
SILL = 2.00
SLIT_HEIGHT = 0.30
SLIT_WIDTH = 1.98
# LocationNavigation samples box undersides on a 0.25 m grid. Follow the thin
# colliders in build_outdoor_locations._ramp/_tread; thick slabs disconnect slopes.
WALK_SURFACE = 0.10

EXTERNAL = {
    **{name: f"{STAGE}/materials/{name}.tres" for name in (
        "walk_plaster", "walk_dado", "walk_step", "school_haze_floor",
    )},
    **{name: f"{YARD}/materials/{name}.tres" for name in ("exit_frame", "exit_glass", "exit_steel")},
}
SOLIDS = {
    "gallery_frame": (64, 73, 83), "gallery_base": (109, 114, 132), "cool_trim": (62, 65, 98),
    "room_blue": (85, 100, 123), "room_pale": (137, 137, 145), "room_ink": (44, 52, 63),
    "room_wood": (117, 93, 79), "upper_concrete": (111, 109, 121), "roof": (105, 107, 126),
    "warm_tile": (141, 111, 84),
    # Pigment, not a different rendering model: faded rose concrete, petrol blue
    # and one hot, enamelled wayfinding colour against the classroom palette.
    "chalk_rose": (197, 171, 168), "deep_plum": (69, 56, 77),
    "fern_blue": (86, 128, 140), "night_blue": (48, 66, 86),
    "iron_red": (160, 91, 77), "apricot": (232, 173, 109),
    "arch_chalk": (222, 199, 171), "landing_stone": (152, 139, 146),
    "municipal_rose": (185, 116, 108), "directory_black": (49, 40, 59),
    "clay_red": (143, 77, 75), "brass_rule": (218, 153, 81),
    "atrium_mint": (140, 188, 179), "entry_glaze": (42, 69, 73),
    "office_sage": (112, 148, 136), "office_ochre": (190, 153, 101),
    "night_lilac": (154, 145, 179), "blue_hour": (63, 69, 106),
    "signal_ivory": (211, 204, 182),
}
SCENES = {
    "bio_door": f"{PROPS}/classroom_art/classroom_door.tscn",
    "bio_rear_door": f"{PROPS}/classroom_art/classroom_rear_door.tscn",
    "interactable": "res://scenes/interaction/interactable.tscn",
    "office_door": f"{PROPS}/staff_office_door.tscn",
    "restroom_door": f"{PROPS}/restroom_door.tscn",
    "lab_door": f"{PROPS}/laboratory_entry_door.tscn",
    "teaching_entrance": f"{PROPS}/teaching_block_entrance.tscn",
    **{r.id: f"{PROPS}/{r.id}_door.tscn" for r in THRESHOLDS},
}


def complement(low, high, holes):
    cursor = low
    for start, end in sorted(holes):
        if start > cursor + 0.0001:
            yield cursor, start
        cursor = max(cursor, end)
    if high > cursor + 0.0001:
        yield cursor, high


class Build(Builder):
    def __init__(self, name):
        super().__init__()
        self.name = name
        self.ext = {}
        self.local_mats = {}
        self.meshes = {}
        self.nodes.append(f'[node name="{name}" type="Node3D"]\n')

    def mesh(self, kind, **props):
        key = (kind, tuple(props.items()))
        if key not in self.meshes:
            self.meshes[key] = super().mesh(kind, **props)
        return self.meshes[key]

    def bind(self, key, path, kind):
        self.ext[key] = f'[ext_resource type="{kind}" path="{path}" id="{key}"]'
        return f'ExtResource("{key}")'

    def surface(self, name):
        if name in EXTERNAL:
            return self.bind(f"art_{name}", EXTERNAL[name], "Material")
        if name.startswith("yard/"):
            key = name.removeprefix("yard/")
            return self.bind(f"yard_{key}", f"{YARD}/materials/{key}.tres", "Material")
        if name not in self.local_mats:
            self.mat(name, albedo_color=srgb(SOLIDS[name]))
        return f'SubResource("Mat_{name}")'

    def mat(self, name, **props):
        standard = {"diffuse_mode": "3", "specular_mode": "2", "roughness": "1.0", **props}
        self.local_mats[name] = (
            f'[sub_resource type="StandardMaterial3D" id="Mat_{name}"]\n'
            + "\n".join(f"{key} = {value}" for key, value in standard.items()) + "\n"
        )

    def flat(self, name, parent, mesh_id, mat, pos, rot=None, shadow=False):
        args = {"position": vec3(pos), "mesh": f'SubResource("{mesh_id}")',
                "material_override": self.surface(mat)}
        if rot:
            args["rotation_degrees"] = vec3(rot)
        if not shadow:
            args["cast_shadow"] = 0
        self.node(name, parent, "MeshInstance3D", **args)

    def box(self, name, parent, pos, size, material, rot=None, shadow=False):
        self.flat(name, parent, self.mesh("BoxMesh", size=vec3(size)), material, pos, rot, shadow)

    def shell(self, name, parent, pos=(0, 0, 0), rot=(0, 0, 0), groups=(), layer=1):
        group = " groups=[" + ", ".join(f'"{g}"' for g in groups) + "]" if groups else ""
        self.nodes.append(f'[node name="{name}" type="StaticBody3D" parent="{parent}"{group}]\n'
                          f'position = {vec3(pos)}\nrotation_degrees = {vec3(rot)}\n'
                          f'collision_layer = {layer}\ncollision_mask = 0\n')
        return child_path(parent, name)

    def shape(self, name, parent, pos, size, rot=None):
        resource = self.mesh("BoxShape3D", size=vec3(size))
        args = {"position": vec3(pos), "shape": f'SubResource("{resource}")'}
        if rot:
            args["rotation_degrees"] = vec3(rot)
        self.node(name, parent, "CollisionShape3D", **args)

    def instance(self, name, parent, key, pos, rot=None, **props):
        self.bind(key, SCENES[key], "PackedScene")
        args = {"position": vec3(pos), **props}
        if rot:
            args["rotation_degrees"] = vec3(rot)
        self.nodes.append(f'[node name="{name}" parent="{parent}" instance=ExtResource("{key}")]\n'
                          + "\n".join(f"{k} = {v}" for k, v in args.items()) + "\n")

    def emit(self):
        steps = 1 + len(self.ext) + len(self.local_mats) + len(self.subs)
        return (f"[gd_scene load_steps={steps} format=3]\n\n"
                + "\n".join(self.ext.values()) + "\n\n"
                + "\n".join([*self.local_mats.values(), *self.subs, *self.nodes]))


def child_path(parent, name):
    return name if parent == "." else f"{parent}/{name}"


def facade_sections(b, parent, width, openings):
    """Build opaque sections around actual holes in the visible wall. One separate body
    still closes each room; panes are not things the actor can climb or run through."""
    ys = sorted({0, 1.05, WALL_HEIGHT, *(y for hole in openings for y in hole[2:])})
    for band, (bottom, top) in enumerate(zip(ys, ys[1:])):
        gaps = [(x0, x1) for x0, x1, y0, y1 in openings if y0 <= bottom and y1 >= top]
        for col, (x0, x1) in enumerate(complement(-width / 2, width / 2, gaps)):
            b.box(f"Wall{band}_{col}", parent, ((x0 + x1) / 2, (bottom + top) / 2, 0),
                  (x1 - x0, top - bottom, 0.20), "walk_plaster" if bottom >= 1.05 else "cool_trim")


def glazing(b, parent, name, x, y, width, height, mat):
    b.flat(name, parent, quad(b, width, height), mat, (x, y, 0.104))
    b.box(name + "Sill", parent, (x, y - height / 2, 0.095), (width + 0.10, 0.052, 0.25), "gallery_frame")
    b.box(name + "Head", parent, (x, y + height / 2, 0.08), (width + 0.10, 0.045, 0.22), "gallery_frame")
    stile = (0.05, height - 0.044, 0.22)
    for end, sign in (("Left", -1), ("Right", 1)):
        b.box(name + end, parent, (x + sign * width / 2, y, 0.081), stile, "gallery_frame")


def plain_door(b, parent, name, x, mat):
    b.node(name, parent, position=vec3((x, 0, 0)))
    p = child_path(parent, name)
    b.box("Rebate", p, (0, DOOR_HEIGHT / 2, -0.06), (DOOR_WIDTH, DOOR_HEIGHT, 0.05), "room_ink")
    b.box("Leaf", p, (0, 1.08, 0.017), (1.047, 2.144, 0.065), mat)
    for side, sign in (("Left", -1), ("Right", 1)):
        b.box("Jamb" + side, p, (sign * 0.562, 1.076, 0.073), (0.080, 2.152, 0.15), "gallery_frame")
    b.box("Head", p, (0, 2.176, 0.073), (DOOR_WIDTH, 0.060, 0.15), "gallery_frame")
    b.box("HandlePlate", p, (0.38, 1.02, 0.058), (0.085, 0.21, 0.02), "exit_frame")
    b.box("Lever", p, (0.314, 1.06, 0.103), (0.17, 0.039, 0.08), "exit_steel")
    b.box("Kick", p, (0, 0.19, 0.062), (0.93, 0.15, 0.024), "exit_frame")


def classroom_bay(b, name, parent, pos, yaw, spec, biology=False):
    _, width, plate, depth, bias = spec
    p = b.shell(name, parent, pos, (0, yaw, 0), ("camera_occluder", "teaching_bay"))
    b.shape("WallCollision", p, (0, WALL_HEIGHT / 2, 0), (width, WALL_HEIGHT, 0.20))
    # Match WallEast in classroom.tscn: the blackboard-end door is at -Z. The
    # west bay turns its local +X toward -Z, so its front door uses positive X.
    half_spacing = DOOR_SPACING / 2
    door_x = (half_spacing, -half_spacing) if biology else (-half_spacing, half_spacing)
    slit_x = 1.8 if biology else 0.0
    openings = [(x - DOOR_WIDTH / 2, x + DOOR_WIDTH / 2, 0, DOOR_HEIGHT) for x in door_x]
    openings += [(x - 0.41, x + 0.41, 2.41, 2.73) for x in door_x]
    openings += [(slit_x - SLIT_WIDTH / 2, slit_x + SLIT_WIDTH / 2, SILL, SILL + SLIT_HEIGHT)]
    facade_sections(b, p, width, openings)
    for i, (which, x) in enumerate(zip(("FrontDoor", "RearDoor"), door_x)):
        if biology:
            # Bay-local +Z is toward the hall, as is the fitted door's +Z in
            # the classroom. Do not turn the assembly around to face the camera.
            scene = "bio_rear_door" if i else "bio_door"
            b.instance(which, p, scene, (x, 0, -0.04))
        else:
            plain_door(b, p, which, x, "room_blue" if not i else "room_pale")
        glazing(b, p, which + "Transom", x, 2.57, 0.82, 0.32, "transom")
    glazing(b, p, "HighGlass", slit_x, SILL + SLIT_HEIGHT / 2, SLIT_WIDTH, SLIT_HEIGHT, "peek_glass")
    plate_x = door_x[0] - 0.9 if biology else door_x[0] + 0.9
    plate_y = 1.83 if biology else 1.89  # Below the biology high window sill.
    sign(b, p, "Number", (plate_x, plate_y, 0.112), plate, 0.33)
    upper = name.startswith("Upper")
    for side, x in enumerate((-width/2+0.09, width/2-0.09)):
        b.box(f"Pier{side}", p, (x, 1.56, 0.104), (0.18, 3.12, 0.29),
              "blue_hour" if upper else "office_sage")
    # Cutaway ceiling: the return/beam and its shadow remain, not a roof across the
    # follow camera's line from the open side of the sectional model.
    # The beam's back sits inside the plaster, not flush with the wall's rear face.
    b.box("CeilingReturn", p, (0, 3.15, 0.262), (width-0.034, 0.25, 0.626),
          "blue_hour" if upper else "office_sage", shadow=True)
    b.box("CeilingFascia", p, (0, 3.177, 0.583), (width-0.22, 0.094, 0.036),
          "night_lilac" if upper else "office_ochre")
    for i, (start, end) in enumerate(complement(-width/2, width/2,
            [(x - DOOR_WIDTH/2, x + DOOR_WIDTH/2) for x in door_x])):
        b.box(f"Skirt{i}", p, ((start+end)/2, 0.06, 0.111), (end-start, 0.12, 0.065), "walk_dado")
    # Real depth and furnishings (not a pasted image). The only playable classroom
    # interior is still its own story scene. The floor behind each slit is off its datum.
    b.box("RoomFloor", p, (0, bias - 0.1, -depth / 2 - 0.1), (width - 0.04, 0.20, depth), "upper_concrete")
    b.box("RoomBack", p, (0, 1.53, -depth - 0.1), (width, 3.25, 0.20), "gallery_base")
    for index, x in enumerate((-width / 2 + 0.08, width / 2 - 0.08)):
        b.box(f"Return{index}", p, (x, 1.505, -depth / 2 - 0.048),
              (0.16, 3.20, depth-0.104), "walk_plaster")
    b.box("RoomRoof", p, (0, 3.206, -depth / 2 - 0.12), (width-0.024, 0.16, depth+0.036),
          "blue_hour" if upper else "roof", shadow=True)
    b.box("Blackboard", p, (0.55, 1.64 + bias, -depth + 0.024), (2.9, 1.16, 0.075), "room_ink")
    b.box("Lectern", p, (0.46, 0.44 + bias, -depth + 0.82), (1.18, 0.88, 0.6), "room_wood")
    b.box("LecternTop", p, (0.46, 0.91 + bias, -depth + 0.82), (1.29, 0.064, 0.68), "room_ink")
    for row in range(2):
        for col in range(3):
            x, z = -1.8 + col * 1.7 + (0.24 if bias < 0 else 0), -2.0 - row * 1.55
            b.box(f"Desk{row}_{col}", p, (x, 0.79 + bias, z), (1.12, 0.08, 0.54), "room_wood")
            b.box(f"DeskBase{row}_{col}", p, (x, 0.37 + bias, z), (0.86, 0.75, 0.28), "room_ink")
    if not biology:
        script = b.bind("peek", "res://scenes/locations/corridor/high_window_peek.gd", "Script")
        b.instance("Peek", p, "interactable", (slit_x, 0.84, 0.68),
                   script=script, interact_id=f'&"high_window_{name.lower()}"',
                   prompt_text='"Jump to look through the high window"',
                   inspection_id='&"corridor_high_window"', radius=1.15,
                   outline_paths='PackedStringArray("../HighGlass", "../HighGlassSill")',
                   support_paths='PackedStringArray("..")', pane_path='NodePath("../HighGlass")')


def classroom_run(b, parent, west, axis, y, span, specs, gap=(), biology=False):
    yaw = 90 if west else 0
    def at(s):
        return (axis, y, s) if west else (s, y, axis)
    for i, spec in enumerate(specs):
        wing = "West" if west else "North"
        floor = "Lower" if y == 0 else "Upper"
        classroom_bay(b, f"{floor}{wing}{i+1}", parent, at(spec[0]), yaw, spec, biology and i == 0)
    breaks = [(centre - width/2, centre + width/2) for centre, width, *_ in specs]
    breaks += list(gap)
    for i, (lo, hi) in enumerate(complement(*span, breaks)):
        p = b.shell(f"{'West' if west else 'North'}Pier{i}", parent, at((lo+hi)/2), (0, yaw, 0), ("camera_occluder",))
        b.shape("Collision", p, (0, WALL_HEIGHT/2, 0), (hi-lo, WALL_HEIGHT, 0.20))
        facade_sections(b, p, hi-lo, [])


def glass_run(b, parent, name, west, axis, y, low, high, gap=()):
    """Deep reveals and normal-height sashes in real masonry, not an alpha wall.

    The plaster, sill and glazed aperture have separate physical jobs. Picking
    can pass through the glass (layer 4), but only the local bay can cut away.
    """
    b.node(name, parent)
    p = child_path(parent, name)
    sill, lintel = 1.06, 2.35
    upper = parent == "UpperFloor"
    base, field = ("blue_hour", "night_lilac") if upper else ("office_sage", "walk_plaster")
    for i, (start, end) in enumerate(complement(low, high, gap)):
        count = math.ceil((end-start) / 4.4)
        width = (end-start) / count
        for j in range(count):
            centre = start + (j + .5) * width
            pos = (axis, y, centre) if west else (centre, y, axis)
            w = b.shell(f"Bay{i}_{j}", p, pos, (0, -90 if west else 180, 0), ("camera_occluder",))
            glass_width = min(1.82, width*.49)
            window_y = (sill+lintel)/2
            h = lintel-sill
            for part, pos, size, material in (
                ("SillWall", (0, sill/2, 0), (width, sill, .26), base),
                ("LintelWall", (0, (lintel+WALL_HEIGHT)/2, 0), (width, WALL_HEIGHT-lintel, .26), field),
                ("LeftPier", (-(width+glass_width)/4, window_y, 0), ((width-glass_width)/2, h, .26), field),
                ("RightPier", ((width+glass_width)/4, window_y, 0), ((width-glass_width)/2, h, .26), field),
            ):
                b.shape(part + "Solid", w, pos, size)
                b.box(part, w, pos, size, material, shadow=True)
            panel = b.shell("GlassSafety", w, layer=4)
            b.shape("Pane", panel, (0, window_y, 0), (glass_width, h, .084))
            for height, strip in ((sill, "WindowSill"), (lintel, "WindowHead")):
                b.box(strip, w, (0, height, .006), (glass_width+.16, .082, .347), "gallery_frame")
            for suffix, x in (("Left", -glass_width/2), ("Right", glass_width/2), ("Centre", 0)):
                b.box("Sash"+suffix, w, (x, window_y, 0), (.05, h, .124), "gallery_frame")
            b.flat("ClearGlass", w, quad(b, glass_width, h), "clear_glass", (0, window_y, 0))
            b.box("DadoLine", w, (0, .87, .133), (width-.008, .032, .018), "gallery_frame")
            b.box("FootRail", w, (0, .11, .134), (width-.008, .14, .03), base)


def slab(b, parent, name, x_span, z_span, y, surface_mat=None, rotate=False, *, through_z=None):
    x0, x1 = x_span
    z0, z1 = z_span
    w, d = x1-x0, z1-z0
    p = b.shell(name, parent, ((x0+x1)/2, y, (z0+z1)/2))
    # A continuous floor can carry more than one paint/mesh section without a
    # physics seam between them. Extend only its collider, not this section's tile.
    solid_end = z1 if through_z is None else through_z
    b.shape("Solid", p, (0, -WALK_SURFACE/2, (solid_end-z1)/2), (w, WALK_SURFACE, solid_end-z0))
    slab_dressing(b, p, w, d, surface_mat, rotate)


def slab_dressing(b, p, w, d, surface_mat, rotate=False):
    b.box("Slab", p, (0, -0.140, 0), (w, 0.27, d), "upper_concrete")
    if surface_mat:
        # Use #243's small ruled tile; its physical four-metre repeat follows the turn.
        b.flat("RuledPour", p, plane(b, d if rotate else w, w if rotate else d), surface_mat,
               (0, 0.003, 0), (0, -90, 0) if rotate else None)


def rail(b, parent, name, x, y, z, w, d, panel="gallery_base", cap="gallery_frame"):
    p = b.shell(name, parent, (x, y, z), groups=("camera_occluder",))
    b.shape("Guard", p, (0, 0.55, 0), (w, 1.10, d))
    b.box("Panel", p, (0, 0.50, 0), (w, 1.0, d), panel)
    b.box("Cap", p, (0, 1.04, 0), (w, 0.08, d), cap)


def flight(b, parent, name, origin, yaw, run, rise, width, steps, accent,
           panel="gallery_base", cap="gallery_frame", tread="upper_concrete"):
    """The treads are visual, one continuous physics slope keeps mouse paths smooth.

    Start at the low end; the flight's -Z is uphill (rotate the assembly as needed).
    """
    b.node(name, parent, position=vec3(origin), rotation_degrees=vec3((0, yaw, 0)))
    p = child_path(parent, name)
    length = math.hypot(run, rise)
    pitch = math.degrees(math.atan2(rise, run))
    normal_z, normal_y = rise/length, run/length
    ramp = b.shell("Ramp", p)
    offset = WALK_SURFACE / 2
    b.shape("Slope", ramp, (0, rise/2 - offset*normal_y, -run/2 - offset*normal_z),
            (width + 0.05, WALK_SURFACE, length + 0.12), (pitch, 0, 0))
    for i in range(steps):
        t = (i + 0.5) / steps
        top_y = rise*t
        z = -run*t
        b.box(f"Tread{i+1}", p, (0, top_y-0.13, z), (width, 0.26, run/steps+0.004),
              tread if i % 4 else accent)
        # Set the metal on the riser, not a second surface half a millimetre below
        # the tread. The top and front planes stay distinct at the grazing camera angle.
        b.box(f"Nosing{i+1}", p, (0, top_y-0.042, z+run/steps/2+0.014), (width-0.018, 0.043, 0.040), cap)
    for sign, side in ((-1, "West"), (1, "East")):
        guard = b.shell(side + "Guard", p, (sign*(width/2+0.065), rise/2, -run/2),
                        (pitch, 0, 0), ("camera_occluder",))
        b.shape("Guard", guard, (0, 0.54, 0), (0.14, 1.13, length))
        b.box("Panel", guard, (0, 0.5, 0), (0.14, 1.0, length), panel)
        b.box("Cap", guard, (0, 1.02, 0), (0.16, 0.08, length), cap)


def sign(b, parent, name, pos, text, width=0.55, yaw=0, plate="gallery_frame"):
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)))
    p = child_path(parent, name)
    b.box("Plate", p, (0, 0, 0), (width, 0.21, 0.035), plate)
    b.node("Text", p, "Label3D", position=vec3((0, 0, 0.023)), text=f'"{text}"',
           font_size=44, pixel_size=0.0024, outline_size=0, modulate="Color(0.93, 0.86, 0.73, 1)")


def lamp(b, name, parent, pos, warmth):
    b.box(name + "Tray", parent, pos, (0.68, 0.077, 0.27), "gallery_frame")
    b.box(name + "Tube", parent, (pos[0], pos[1]-0.047, pos[2]), (0.55, 0.034, 0.11), "lamp_tube")
    b.node(name, parent, "OmniLight3D", position=vec3((pos[0], pos[1]-0.21, pos[2])),
           light_color="Color(1, 0.83, 0.64, 1)", light_energy=warmth, omni_range=5.3)


def guard_edges(b, parent, prefix, xs, zs, y, openings, panel, cap):
    """Guard platform edges, leaving only the spans that actually join a flight."""
    for side, axis, span in (("North", zs[0], xs), ("South", zs[1], xs),
                             ("West", xs[0], zs), ("East", xs[1], zs)):
        for index, (lo, hi) in enumerate(complement(*span, openings.get(side, ()))):
            along = (lo+hi)/2
            if side in ("North", "South"):
                x, z, w, d = along, axis, hi-lo, 0.16
            else:
                x, z, w, d = axis, along, 0.16, hi-lo
            rail(b, parent, f"{prefix}{side}{index}", x, y, z, w, d, panel, cap)


def solid_wall(b, parent, name, pos, width, yaw=0, height=3.05, base="deep_plum", field="chalk_rose"):
    """One blocking body, three non-overlapping courses meeting at their edges."""
    p = b.shell(name, parent, pos, (0, yaw, 0), ("camera_occluder",))
    b.shape("Solid", p, (0, height/2, 0), (width, height, 0.22))
    b.box("Dado", p, (0, 0.47, 0), (width, 0.94, 0.22), base)
    cap_y = height-0.19
    b.box("Plaster", p, (0, (cap_y+0.94)/2, 0), (width, cap_y-0.94, 0.22), field)
    b.box("Frieze", p, (0, height-0.095, 0), (width, 0.19, 0.24), "arch_chalk")
    return p


def teaching_entrance():
    """The same open glass assembly, seen from the street and the 01 forecourt.

    The sidelights and parked leaves are one continuous pane per side. Intact
    glass is solid to the capsule and transparent to click rays, just as above.
    Nothing, including the bake, crosses the 2.66 m clear opening below the header.
    """
    b = Build("TeachingBlockEntrance")
    b.mat("entry_pane", transparency=1, cull_mode=2, albedo_color="Color(0.52, 0.77, 0.72, 0.32)")
    b.mat("entry_ribbon", shading_mode=0, albedo_color="Color(0.67, 0.81, 0.73, 1)")
    half = ENTRANCE_WIDTH / 2
    for tag, direction in (("Left", -1), ("Right", 1)):
        edge = b.shell(tag, ".", groups=("camera_occluder",))
        for part, x, width in (("Jamb", half-0.16, 0.32), ("Stile", 1.38, 0.10)):
            b.shape(part+"Body", edge, (direction*x, 1.32, 0), (width, 2.64, 0.35))
            b.box(part, edge, (direction*x, 1.32, 0), (width, 2.64, 0.35), "entry_glaze", shadow=True)
        b.box("Mullion", edge, (direction*2.14, 1.28, 0), (0.061, 2.54, 0.17), "entry_glaze")
        # The sill sits under the pane, not across the clear opening.
        kick_pos, kick_size = (direction*2.18, 0.185, 0), (1.55, 0.38, 0.14)
        b.shape("KickBody", edge, kick_pos, kick_size)
        b.box("Kick", edge, kick_pos, kick_size, "entry_glaze")
        b.flat("Pane", edge, quad(b, 1.57, 2.26), "entry_pane", (direction*2.18, 1.44, 0.018))
        # An apron-to-stair route otherwise treats the low kick as a voxel step.
        # Let the full pane take part in the bake without adding it to pick rays.
        safety = b.shell("GlassSafety", edge, layer=PLAYER_ONLY_LAYER | BAKE_ONLY_LAYER)
        b.shape("Pane", safety, (direction*2.18, 1.32, 0.018), (1.58, 2.64, 0.10))
        # Short opaque silk-screen bands give the pane a readable silhouette
        # from either side without a second transparency layer to depth-sort.
        for i, (shift, length) in enumerate(((0.0, 1.50), (-0.12, 1.23), (-0.31, 0.85))):
            b.box(f"Silkscreen{i}", edge, (direction*(2.18+shift), 1.17+0.17*i, 0.018),
                  (length, 0.037, 0.023), "entry_ribbon")
        for face, z in (("Outside", 0.155), ("Inside", -0.14)):
            b.box(face+"Pull", edge, (direction*1.65, 1.03, z), (0.052, 0.31, 0.066), "brass_rule")
            for i, y in enumerate((0.91, 1.15)):
                y += 0.011 if face == "Inside" else 0
                b.box(f"{face}Mount{i}", edge, (direction*1.65, y, (z+0.018)*0.5),
                      (0.056 if face == "Inside" else 0.061, 0.058, abs(z-0.018)+0.015), "brass_rule")
    top = b.shell("Header", ".", groups=("camera_occluder",))
    # Match the projecting cap's silhouette: the old slim lintel volume missed
    # the camera ray while the cap itself still covered the player inside 01.
    b.shape("Lintel", top, (-0.08, 3.43, 0.03), (ENTRANCE_WIDTH+0.52, 1.58, 0.72))
    b.box("Shoe", top, (0, 2.72, 0), (ENTRANCE_WIDTH, 0.16, 0.40), "entry_glaze", shadow=True)
    for i in range(5):
        x = (i-2)*1.22
        b.flat(f"Transom{i}", top, quad(b, 1.16, 0.69), "entry_pane", (x, 3.138, 0.023))
        if i != 4:
            b.box(f"TransomStile{i}", top, (x+0.61, 3.14, 0), (0.065, 0.7, 0.20), "entry_glaze")
    for side, x in (("Left", -2.98), ("Right", 2.98)):
        b.box(side+"TransomPost", top, (x, 3.14, 0), (0.229, 0.7, 0.36), "entry_glaze")
    b.box("EnamelHeader", top, (0.04, 3.76, 0), (ENTRANCE_WIDTH+0.30, 0.52, 0.56), "municipal_rose", shadow=True)
    b.box("EnamelCap", top, (-0.08, 4.10, 0.03), (ENTRANCE_WIDTH+0.52, 0.16, 0.72), "directory_black", shadow=True)
    for side, direction, yaw in (("Outside", 1, 0), ("Inside", -1, 180)):
        sign(b, top, side+"Plate", (direction*1.98, 3.75, direction*0.29), "01 / 01", 1.19, yaw, "directory_black")
        b.box(side+"LightStrip", top, (-direction*0.77, 3.72, direction*0.296),
              (3.0, 0.042, 0.045), "entry_ribbon")
    return b


def directory_wall(b, parent):
    pivot, height = -16.205, 3.05
    wall = b.shell("DirectoryWall", parent, (pivot, GROUND_Y, GROUND_Z[0]), groups=("camera_occluder",))
    for i, (lo, hi) in enumerate(complement(-23.31, GROUND_X[1], [threshold_gap(ARCHIVE), threshold_gap(PLAN_ROOM)])):
        x, width = (lo+hi)/2-pivot, hi-lo
        b.shape(f"Solid{i}", wall, (x,height/2,0), (width,height,.22))
        b.box(f"Dado{i}", wall, (x,.47,0), (width,.94,.22), "clay_red")
        b.box(f"Plaster{i}", wall, (x,1.9,0), (width,1.92,.22), "municipal_rose")
        b.box(f"Frieze{i}", wall, (x,2.955,0), (width,.19,.24), "arch_chalk")
    # Keep the main directory's mounted clue and plate; the 03 strip moves to
    # the pier between the two new rooms. Both doors face the gameplay camera.
    for i, (x, width, height) in enumerate(((-4.80,2.15,1.88), (-1.44,3.50,2.20), (3.58,1.39,1.59))):
        house = f"Index{i}"
        b.node(house, wall, position=vec3((x, 0.93, 0.205)))
        p = child_path(wall, house)
        b.box("Backing", p, (0, height/2-0.13, -0.03), (width, height-0.26, 0.16), "directory_black", shadow=True)
        b.box("Paper", p, (0.09, height/2-0.13, 0.058), (width-0.36, height-0.52, 0.028), "night_blue")
        for j in range(6):
            xx = -width/2+0.43+j*(width-0.7)/6
            rule_h = (height-0.84)*(0.42+0.18*((j+i) % 4))
            b.box(f"Register{j}", p, (xx, 0.17+rule_h/2, 0.081),
                  (0.047 if j != 2 else 0.105, rule_h, 0.016), "atrium_mint" if j != 2 else "brass_rule")
        b.box("RouteRule", p, (0.08, 0.33, 0.096), (width-0.53, 0.043, 0.021), "signal_ivory")
        if i == 1:
            for edge, (xx, y, w, h) in enumerate(((1.31, 0.71, 0.12, 0.023), (1.31, 0.81, 0.12, 0.023),
                                                  (1.26, 0.76, 0.024, 0.08), (1.36, 0.76, 0.024, 0.08))):
                b.box(f"PencilSquare{edge}", p, (xx, y, 0.081), (w, h, 0.017), "signal_ivory")
            b.box("Screw", p, (1.31, 0.76, 0.079), (0.036, 0.036, 0.029), "gallery_frame")
        b.box("LabelRail", p, (0, -0.18, 0), (width+0.13, 0.089, 0.41), "clay_red", shadow=True)
        sign(b, p, "IndexPlate", (0.21, height-0.53, 0.086), ("01 →", "← 01", "03")[i],
             width=0.58, plate="directory_black")
    for i, x in enumerate((-5.5, -1.7, 3.58)):
        lamp(b, f"DirectoryLight{i}", wall, (x, 2.86, 0.22), 0.42)


def landing_support(b, parent, name, x, z, landing_y, width):
    # A solid-looking pier below the section, outside any walkable volume.
    top = landing_y-0.24
    b.box(name, parent, (x, (GROUND_Y+top)/2, z), (width, top-GROUND_Y, width), "chalk_rose", shadow=True)


def rear_stair_and_ground_wing(b):
    # The hub attaches to the corridor slab after the white rear door. Splay up
    # toward the old 03 return and down toward the south apron. Neither branch
    # sits directly over the other: the isometric camera can read both landings.
    s = "RearStair"
    g = "GroundFloor"
    b.node(s, ".")
    b.node(g, ".")
    junction_x, junction_z = REAR_JUNCTION_X, REAR_JUNCTION_Z
    z_axis = sum(junction_z)/2
    down_x = sum(junction_x)/2
    up_width, down_width = 3.0, 2.55
    down_entry = (down_x-down_width/2, down_x+down_width/2)
    across = (z_axis-up_width/2, z_axis+up_width/2)
    slab(b, s, "Junction", junction_x, junction_z, 0, "folded_tile")
    guard_edges(b, s, "JunctionRail", junction_x, junction_z, 0,
                {"East": [junction_z], "West": [across], "South": [down_entry]},
                "iron_red", "arch_chalk")
    sign(b, s, "UpPlate", (-4.35, 0.87, junction_z[0]+0.12), "03 ↑", 0.72, plate="deep_plum")
    sign(b, s, "DownPlate", (-2.96, 0.87, junction_z[0]+0.12), "01 ↓", 0.72, plate="night_blue")
    b.box("ApricotRoute", s, (-3.67, 0.009, 5.83), (0.12, 0.013, 2.19), "apricot")
    b.box("JunctionLightPost", s, (-3.22, 1.75, junction_z[0]+0.027), (0.13, 1.92, 0.14), "night_blue", shadow=True)
    lamp(b, "JunctionLight", s, (-3.02, 2.66, junction_z[0]+0.10), 0.63)

    up_x = (UPPER_X[0], -9.05)
    high_track = (-13.45, -10.55)
    up_y = RISE/2
    flight(b, s, "UpLowerFlight", (junction_x[0], 0, z_axis), 90,
           junction_x[0]-up_x[1], up_y, up_width, 10, "arch_chalk",
           panel="iron_red", cap="deep_plum", tread="landing_stone")
    slab(b, s, "UpLanding", up_x, junction_z, up_y, "folded_tile")
    guard_edges(b, s, "UpLandingRail", up_x, junction_z, up_y,
                {"East": [across], "North": [high_track]}, "iron_red", "deep_plum")
    flight(b, s, "UpUpperFlight", (sum(high_track)/2, up_y, junction_z[0]), 0,
           junction_z[0]-UPPER_JOIN_Z, up_y, high_track[1]-high_track[0], 10, "arch_chalk",
           panel="iron_red", cap="deep_plum", tread="landing_stone")
    upper_link = (UPPER_Z[1], UPPER_JOIN_Z)
    b.node("UpperLink", s, position=vec3((sum(UPPER_X)/2, RISE, sum(upper_link)/2)))
    slab_dressing(b, child_path(s, "UpperLink"), UPPER_X[1]-UPPER_X[0], upper_link[1]-upper_link[0], "folded_tile")
    guard_edges(b, s, "UpperLinkRail", UPPER_X, upper_link, RISE,
                {"North": [UPPER_X], "South": [high_track]}, "iron_red", "deep_plum")
    for i, x in enumerate((up_x[0]+0.49, up_x[1]-0.53)):
        landing_support(b, s, f"UpLandingPier{i}", x, junction_z[1]-0.42, up_y, 0.76)
    for i, x in enumerate((UPPER_X[0]+0.43, UPPER_X[1]-0.45)):
        landing_support(b, s, f"UpperLinkPier{i}", x, UPPER_JOIN_Z-0.52, RISE, 0.65)

    down_half_y = GROUND_Y/2
    down_half_x, down_half_z = (-5.05, junction_x[1]), (10.85, 14.4)
    ground_x, ground_z = GROUND_X, GROUND_Z
    low_track = (11.15, 14.05)
    flight(b, s, "DownUpperFlight", (down_x, down_half_y, down_half_z[0]), 0,
           down_half_z[0]-junction_z[1], -down_half_y, down_width, 10, "fern_blue",
           panel="night_blue", cap="apricot", tread="landing_stone")
    slab(b, s, "DownLanding", down_half_x, down_half_z, down_half_y, "folded_tile")
    guard_edges(b, s, "DownLandingRail", down_half_x, down_half_z, down_half_y,
                {"North": [down_entry], "West": [low_track]}, "night_blue", "apricot")
    landing_support(b, s, "DownLandingPier", sum(down_half_x)/2, down_half_z[1]-0.65, down_half_y, 0.92)
    flight(b, s, "DownLowerFlight", (ground_x[1], GROUND_Y, sum(low_track)/2), -90,
           down_half_x[0]-ground_x[1], down_half_y-GROUND_Y,
           low_track[1]-low_track[0], 10, "fern_blue",
           panel="night_blue", cap="apricot", tread="landing_stone")

    # 01: municipal terrazzo and an over-scaled entrance, across from the
    # folded room directory. The lobby itself is a passage, not a teleport plane.
    alcove_x, alcove_z = (ground_x[0], -23.2), (5.65, ground_z[0])
    entrance_x = (ENTRANCE_X-ENTRANCE_WIDTH/2, ENTRANCE_X+ENTRANCE_WIDTH/2)
    apron_z = (ground_z[1], ENTRANCE_APRON_END)
    slab(b, g, "Gallery", ground_x, ground_z, GROUND_Y, "gallery_tile", rotate=True)
    slab(b, g, "Recess", alcove_x, alcove_z, GROUND_Y, "recess_tile")
    slab(b, g, "EntranceApron", entrance_x, apron_z, GROUND_Y, "apron_tile")
    # Only the east end of the gallery needs a guard; full height walls take the other sides.
    guard_edges(b, g, "GalleryRail", ground_x, ground_z, GROUND_Y,
                {"North": [ground_x], "South": [ground_x], "East": [low_track], "West": [ground_z]},
                "night_blue", "arch_chalk")
    directory_wall(b, g)
    for name, ends in (("EntranceWallWest", (ground_x[0]+0.11, entrance_x[0])),
                       ("EntranceWallEast", (entrance_x[1], ground_x[1]))):
        solid_wall(b, g, name, (sum(ends)/2, GROUND_Y, ground_z[1]), ends[1]-ends[0],
                   base="entry_glaze", field="municipal_rose", height=2.83)
    b.instance("GlassEntrance", g, "teaching_entrance", (ENTRANCE_X, GROUND_Y, ground_z[1]))
    guard_edges(b, g, "ApronRail", entrance_x, apron_z, GROUND_Y, {"North": [entrance_x]},
                "entry_glaze", "brass_rule")
    b.box("StreetPlateRiser", g, (ENTRANCE_X, GROUND_Y+0.7, ENTRANCE_APRON_END-0.104),
          (0.26, 0.14, 0.08), "entry_glaze")
    sign(b, g, "StreetPlate", (ENTRANCE_X, GROUND_Y+0.7, ENTRANCE_APRON_END-0.14), "STREET", 0.66, 180,
         "directory_black")
    sign(b, g, "FirstFloorPlate", (-9.78, GROUND_Y+2.41, ground_z[0]+0.15), "01", 0.72, plate="clay_red")

    # Floor rules meet edge-to-edge. Brighter copper continues to the lab while
    # the paired ivory tracks carry a separate sight line across the glass threshold.
    b.box("HallInlay", g, (-17.7, GROUND_Y+0.009, 13.28), (15, 0.01, 0.10), "apricot")
    for i, x in enumerate((-9.6, -12.8, -22.2, -26.1)):
        b.box(f"CrossRule{i}", g, (x, GROUND_Y+0.007, 12.0), (0.07, 0.008, 2.36), "clay_red")
    for i, x in enumerate((ENTRANCE_X-1.11, ENTRANCE_X+1.11)):
        for j, (start, end) in enumerate(((11.44, 13.205), (13.355, 17.98))):
            b.box(f"DoorTrack{i}_{j}", g, (x, GROUND_Y+0.009, (start+end)/2),
                  (0.068, 0.01, end-start), "signal_ivory")

    # The opaque return blocks a straight view from the gallery. A short
    # line of amber turns the corner, without a quest marker or a false exit.
    room_portal(b, g, "RestroomPortal", (ground_x[0], GROUND_Y, RESTROOM_Z), 90,
                "restroom_door", "night_blue", "chalk_rose")
    wash_gap = (RESTROOM_Z-ROOM_PORTAL_WIDTH/2, RESTROOM_Z+ROOM_PORTAL_WIDTH/2)
    for name, (lo, hi) in zip(("EndWall", "WashReturnWall"), complement(
            alcove_z[0], ground_z[1], [wash_gap])):
        solid_wall(b, g, name, (ground_x[0], GROUND_Y, (lo+hi)/2), hi-lo, yaw=90, base="night_blue")
    b.box("WashFloorRule", g, (ground_x[0]+0.64, GROUND_Y+0.009, RESTROOM_Z-0.58),
          (1.26, 0.01, 0.082), "atrium_mint")
    screen_z = (alcove_z[0]+0.12, alcove_z[1]-0.11)
    return_wall = solid_wall(b, g, "RecessScreen", (alcove_x[1], GROUND_Y, sum(screen_z)/2),
                             screen_z[1]-screen_z[0], yaw=-90, base="night_blue")
    b.box("AmberRule", return_wall, (0.25, 0.96, 0.123), (3.35, 0.07, 0.05), "apricot")
    b.box("ReturnInlay", g, (-25.25, GROUND_Y+0.009, (alcove_z[0]+13.33)/2),
          (0.1, 0.01, 13.33-alcove_z[0]), "apricot")
    lab_left = alcove_x[0]+0.12
    p = solid_wall(b, g, "LaboratoryPortal", ((lab_left+alcove_x[1])/2, GROUND_Y, alcove_z[0]),
                   alcove_x[1]-lab_left, base="night_blue")
    b.instance("Door", p, "lab_door", (-0.06, 0, 0))
    b.box("EnamelLintel", p, (0, 2.36, 0.23), (2.42, 0.21, 0.48), "fern_blue", shadow=True)
    lamp(b, "BorrowedLight", p, (0, 2.28, 0.34), 0.60)


def room_portal(b, parent, name, pos, yaw, scene, trim, plaster):
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)))
    path = child_path(parent, name)
    b.instance("Door", path, scene, (0, 0, 0))
    head = b.shell("WallHead", path, (0, 2.36, 0), groups=("camera_occluder",))
    b.shape("Solid", head, (0, 0.345, 0), (ROOM_PORTAL_WIDTH, 0.69, 0.22))
    b.box("Face", head, (0, 0.345, 0), (ROOM_PORTAL_WIDTH, 0.69, 0.22), plaster)
    b.box("Header", head, (0, 0.064, 0.112), (ROOM_PORTAL_WIDTH+0.012, 0.13, 0.082), trim)
    lamp(b, "DoorLight", head, (0, 0.37, 0.32), 0.45)


def gallery_details(b, lower, upper):
    # 02: the public-office floor is laid in wide, increasingly short strips.
    # Keep the well-trodden centre unmarked and the biology thresholds unchanged.
    b.node("WaitingRegister", lower, position=vec3((-2.084, 0, -12.65)),
           rotation_degrees=vec3((0, 90, 0)))
    p = child_path(lower, "WaitingRegister")
    b.box("Case", p, (0, 1.48, 0.065), (1.74, 0.8, 0.17), "gallery_frame", shadow=True)
    b.box("Card", p, (-0.03, 1.48, 0.16), (1.53, 0.62, 0.04), "signal_ivory")
    for i in range(5):
        b.box(f"Rule{i}", p, (-0.17+0.086*i, 1.68-0.096*i, 0.187),
              (1.05-0.164*i, 0.028, 0.018), "office_sage")
    for i, (z, length, width) in enumerate(((-10.9, 1.51, 0.74), (-13.4, 1.23, 0.65),
                                               (-15.6, 0.97, 0.51), (-17.5, 0.74, 0.40),
                                               (-19.05, 0.57, 0.33), (-20.3, 0.40, 0.29))):
        b.box(f"WaitingStripe{i}", lower, (-1.22, 0.009, z), (width, 0.01, length),
              "office_ochre" if i % 2 == 0 else "office_sage")
    for i, x in enumerate((3.3, 6.15, 8.78, 22.5, 24.75, 26.19)):
        b.box(f"TurnIndex{i}", lower, (x, 0.009, -29.22), (0.43, 0.01, 0.53), "office_ochre")

    # 03: violet ledger with ruled offsets; no false doorway at the end of the hall.
    for i, x in enumerate((-8.6, -5.15, -1.75, 1.65, 7.1, 10.46, 13.29, 15.6)):
        for j in range(3):
            b.box(f"NightIndex{i}_{j}", upper, (x+0.24*j, RISE+0.009, -43.78+0.98*j),
                  (0.12, 0.01, 0.58), "night_lilac" if j != i % 3 else "signal_ivory")
    room_portal(b, upper, "OfficePortal", (OFFICE_X, RISE, UPPER_TURN[0]), 0,
                "office_door", "blue_hour", "night_lilac")
    b.box("OfficeThresholdIndex", upper, (OFFICE_X, RISE+0.009, -44.17),
          (1.42, 0.01, 0.07), "apricot")
    # Keep a quiet ledger beside the new rest-room threshold, rather than
    # covering the end with an unwalkable decorative door.
    b.node("HourRegister", upper, position=vec3((UPPER_END, RISE, -44.56)),
           rotation_degrees=vec3((0, -90, 0)))
    end = child_path(upper, "HourRegister")
    for j, width in enumerate((.44, .32, .19, .38, .25)):
        b.box(f"HourRule{j}", end, (0, 2.62-.33*j, .124),
              (width, .050, .040), "apricot" if j == 2 else "blue_hour")


def threshold_gap(r, along_z=False):
    centre = r.pos[2 if along_z else 0]
    return centre-ROOM_PORTAL_WIDTH/2, centre+ROOM_PORTAL_WIDTH/2


def wing_end(b, r, span):
    for i, (lo, hi) in enumerate(complement(*span, [threshold_gap(r, True)])):
        solid_wall(b, r.parent, f"{r.name}Return{i}", (r.pos[0], r.pos[1], (lo+hi)/2), hi-lo, -90,
                   base="night_blue", field="chalk_rose")


def registration_plate(b, p, role):
    """Door-scale versions of the alignment mark. The same broken geometry is
    composed at room scale beyond the threshold. No literal lock UI on the HUD."""
    b.box("RegistrationSlide", p, (-.64, 1.33, .124), (.33, .39, .075), "gallery_frame")
    b.box("SlideGrip", p, (-.61, 1.178, .172), (.217, .045, .029), "brass_rule")

    def rule(name, x, y, width, height, tone):
        b.box(name, p, (-.64+x, 1.36+y, .171), (width, height, .013), tone)

    def hole(name, x, y, radius):
        mesh = b.mesh("CylinderMesh", top_radius=radius, bottom_radius=radius, height=.013,
                      radial_segments=10, rings=0)
        b.flat(name, p, mesh, "night_blue", (-.64+x, 1.36+y, .179), (90, 0, 0))

    def frame(name, x, y, w, h, ink):
        for i, (a, d, u, v) in enumerate(((x-w/2,y,.010,h),(x+w/2,y,.010,h),
                                           (x,y-h/2,w,.010),(x,y+h/2,w,.010))):
            rule(f"{name}{i}", a, d, u, v, ink)

    if role == "archive":
        rule("CarbonCopy", 0, -.056, .201, .054, "brass_rule")
        rule("TopCopy", -.019, .048, .246, .054, "signal_ivory")
        hole("CarbonHole", -.053, -.055, .019)
        hole("TopHole", -.053, .048, .019)
    elif role == "plan_room":
        rule("LongLine", -.02, .071, .227, .014, "night_lilac")
        rule("ShortLine", -.061, -.06, .108, .014, "atrium_mint")
        rule("Elbow", -.01, -.034, .014, .058, "atrium_mint")
        rule("Landing", .050, -.005, .104, .014, "atrium_mint")
        frame("LandingSquare", .095, -.005, .043, .043, "brass_rule")
    elif role == "projection_room":
        frame("OutsideFrame", -.02, 0, .215, .21, "night_lilac")
        frame("MiddleFrame", .012, .006, .142, .150, "signal_ivory")
        frame("InsideFrame", .035, .024, .069, .082, "atrium_mint")
        rule("Nick", .061, -.069, .019, .026, "brass_rule")
    elif role == "computer_room":
        for i in range(3):
            rule(f"RasterA{i}", -.080 + .017*i, .085-i*.071, .087, .014, "atrium_mint")
            rule(f"RasterB{i}", .062 + .012*i, .084-i*.071, .073, .014, "atrium_mint")
        rule("Notch", .127, -.057, .026, .031, "brass_rule")
    elif role == "vacant_office":
        rule("PrintA", -.006, .070, .188, .016, "iron_red")
        rule("PrintB", .081, .032, .017, .076, "iron_red")
        rule("IndentA", -.031, -.052, .182, .015, "signal_ivory")
        rule("IndentB", .054, -.090, .017, .073, "signal_ivory")
    elif role == "principal_office":
        rule("FalseCentre", 0, .011, .014, .230, "brass_rule")
        rule("CutPaper", .069, .019, .090, .178, "night_lilac")
        for i in range(2):
            hole(f"OffsetPin{i}", .064, .063-i*.092, .021)


def annex_portals(b):
    for r in THRESHOLDS:
        room_portal(b, r.parent, r.name + "Portal", r.pos, r.yaw, r.id, "night_blue", "chalk_rose")
        p = f"{r.parent}/{r.name}Portal"
        # Painted threshold index, outside the pickable silhouette. The trapped
        # registration slide beside the hinge is the only check affordance.
        b.box("FloorIndex", p, (0, .011, .43), (1.46, .012, .059),
              "brass_rule" if r.gated else "atrium_mint")
        if r.gated:
            registration_plate(b, p, r.id)



def teaching_block():
    b = Build("TeachingBlock")
    b.mat("clear_glass", transparency=1, cull_mode=2, albedo_color="Color(0.67, 0.81, 0.88, 0.15)")
    b.mat("peek_glass", transparency=1, cull_mode=2, albedo_color="Color(0.28, 0.43, 0.48, 0.64)")
    b.mat("transom", transparency=1, cull_mode=2, albedo_color="Color(0.68, 0.57, 0.44, 0.79)",
          emission_enabled="true", emission="Color(0.72, 0.53, 0.33, 1)", emission_energy_multiplier="0.25")
    b.mat("lamp_tube", shading_mode=0, albedo_color="Color(0.88, 0.75, 0.51, 1)")
    ruled = b.bind("ruled_floor_tile", f"{STAGE}/textures/corridor_floor_far.png", "Texture2D")
    spans = {"lower": MAIN_Z[1]-MAIN_Z[0], "lower_turn": EAST_END-MAIN_X[1],
             "upper": UPPER_Z[1]-UPPER_Z[0], "upper_turn": 18.25-UPPER_X[1]}
    for label, length in spans.items():
        b.mat(label, albedo_color="Color(0.69, 0.66, 0.66, 1)" if label.startswith("lower") else
              "Color(0.65, 0.68, 0.74, 1)", albedo_texture=ruled, texture_filter=3,
              uv1_scale=vec3((1, length/4, 1)))
    l, u, s = "LowerFloor", "UpperFloor", "Stairs"
    for name in (l, u, s):
        b.node(name, ".")
    west_gap = (WEST_STAIR_Z - WEST_STAIR_WIDTH/2, WEST_STAIR_Z + WEST_STAIR_WIDTH/2)
    north_gap = (-BEND_STAIR_WIDTH/2, BEND_STAIR_WIDTH/2)
    upper_gap = (BEND_STAIR_X - BEND_STAIR_WIDTH/2, BEND_STAIR_X + BEND_STAIR_WIDTH/2)
    slab(b, l, "Main", MAIN_X, MAIN_Z, 0, "lower")
    yard_gap = (YARD_X-YARD_WIDTH/2, YARD_X+YARD_WIDTH/2)
    slab(b, l, "Turn", (MAIN_X[1], EAST_END), TURN_Z, 0, "lower_turn", rotate=True)
    slab(b, u, "Main", UPPER_X, UPPER_Z, RISE, "upper", through_z=UPPER_JOIN_Z)
    slab(b, u, "Turn", (-9.75, UPPER_END), UPPER_TURN, RISE, "upper_turn", rotate=True)
    classroom_run(b, l, True, -2.2, 0, MAIN_Z, LOWER_WEST, (west_gap, REAR_JUNCTION_Z), biology=True)
    classroom_run(b, l, False, -30, 0, (-2.2, EAST_END), LOWER_NORTH,
                  (north_gap, threshold_gap(PROJECTION), threshold_gap(COMPUTER)))
    classroom_run(b, u, True, -14.25, RISE, UPPER_Z, UPPER_WEST, (threshold_gap(VACANT, True),))
    classroom_run(b, u, False, -45, RISE, (-14.25, UPPER_END), UPPER_NORTH,
                  ((OFFICE_X-ROOM_PORTAL_WIDTH/2, OFFICE_X+ROOM_PORTAL_WIDTH/2), threshold_gap(PRINCIPAL)))
    glass_run(b, l, "EastGlazing", True, 2.1, 0, -25.5, 6.95)
    glass_run(b, l, "SouthGlazing", False, TURN_Z[1], 0, MAIN_X[1], EAST_END, (yard_gap,))
    wing_end(b, WASH_02, TURN_Z)
    wing_end(b, WASH_03, UPPER_TURN)
    annex_portals(b)
    for side, x in zip(("West", "East"), MAIN_X):
        rail(b, l, "GateStepSide"+side, x, -0.36, 7.25, 0.19, 0.6)
    glass_run(b, u, "EastGlazing", True, -9.75, RISE, -40.5, -6.5, (west_gap,))
    glass_run(b, u, "SouthGlazing", False, -40.5, RISE, -9.75, UPPER_END, (upper_gap,))
    # The short flight closes the loop near the biology room. The far stair breaks
    # alignment by 4.5 m across its deep intermediate landing before it climbs again.
    flight(b, s, "WestFlight", (-2.2, 0, WEST_STAIR_Z), 90, 7.55, RISE, WEST_STAIR_WIDTH, 20, "warm_tile")
    flight(b, s, "NorthFlight", (0, 0, -30), 0, 4.25, 1.8, BEND_STAIR_WIDTH, 10, "upper_concrete")
    slab(b, s, "HalfLanding", (-1.4, 5.9), (-37.25, -34.25), 1.8)
    rail(b, s, "LandingNorth", 0.85, 1.8, -37.24, 4.5, 0.14)
    rail(b, s, "LandingSouth", 3.65, 1.8, -34.26, 4.5, 0.14)
    rail(b, s, "LandingWest", -1.4, 1.8, -35.75, 0.14, 3)
    rail(b, s, "LandingEast", 5.9, 1.8, -35.75, 0.14, 3)
    flight(b, s, "OffsetFlight", (4.5, 1.8, -37.25), 0, 3.25, 1.8, BEND_STAIR_WIDTH, 10, "upper_concrete")
    gallery_details(b, l, u)
    foot = YARD_APPROACH_Z+YARD_RUN
    flight(b, s, "YardFlight", (YARD_X, YARD_Y, foot), 0, YARD_RUN, -YARD_Y,
           YARD_WIDTH, 15, "warm_tile")
    slab(b, s, "YardLanding", yard_gap, (foot, YARD_PORTAL_Z), YARD_Y)
    # Short, full-height returns at the landing only. From the stair the door sits
    # in a recess, not on a free-standing screen looking out over the court.
    for side, x in enumerate(yard_gap):
        length = YARD_PORTAL_Z - foot
        jamb = b.shell(f"YardLandingSide{side}", s, (x, YARD_Y, (foot+YARD_PORTAL_Z)/2),
                       groups=("camera_occluder",))
        b.shape("Solid", jamb, (0, WALL_HEIGHT/2, 0), (0.18, WALL_HEIGHT, length))
        b.box("Base", jamb, (0, 0.5, 0), (0.18, 1.0, length), "cool_trim")
        b.box("Plaster", jamb, (0, (WALL_HEIGHT+1.0)/2, 0),
              (0.18, WALL_HEIGHT-1.0, length), "walk_plaster")
    sign(b, l, "ClassroomFloorPlate", (-2.084, 2.58, -6.43), "02", 0.36, yaw=90)
    b.box("WestLandingApron", s, (-2.18, -0.16, WEST_STAIR_Z), (0.32, 0.105, WEST_STAIR_WIDTH), "warm_tile")
    sign(b, u, "ThirdFloorPlate", (-14.135, RISE+2.67, WEST_STAIR_Z), "03", 0.36, yaw=90)
    sign(b, u, "NorthLandingPlate", (BEND_STAIR_X, RISE+2.50, -44.875), "03")
    sign(b, l, "YardStairPlate", (YARD_X + 0.38, 2.52, -29.875), "↓", width=0.42)
    b.box("LowerLampCleat", l, (2.1, 2.91, -29.85), (0.25, 0.13, 0.22), "gallery_frame")
    b.box("UpperLampCleat", u, (4.5, RISE+2.91, -44.86), (0.25, 0.13, 0.22), "gallery_frame")
    for name, parent, pos, energy in (
        ("LampBySchoolDoor", l, (-1.84, 2.91, 1.95), 0.57),
        ("LampByShortStair", l, (-1.81, 2.91, -6.37), 0.44),
        ("LampAtTurn", l, (2.1, 2.91, -29.61), 0.52),
        ("LampByYardStair", l, (YARD_X, 2.91, -29.74), 0.65),
        ("LampOnTop", u, (4.5, RISE + 2.91, -44.72), 0.51),
        ("LampAtReturn", u, (-13.92, RISE + 2.91, -15.8), 0.42),
    ):
        lamp(b, name, parent, pos, energy)

    # Corridor side of the play yard's red fire door: same fittings as the outside;
    # not a facade suspended in the tail of the corridor.
    p = b.shell("YardPortal", ".", (YARD_X, YARD_Y, YARD_PORTAL_Z), (0, 180, 0), ("camera_occluder",))
    b.shape("Stop", p, (0, 1.6, 0), (YARD_WIDTH, 3.2, 0.20))
    facade_sections(b, p, YARD_WIDTH, [(-0.7, 0.7, 0, 2.6)])
    b.box("YardDoorLeaf", p, (0, 1.3, 0.03), (1.4, 2.6, 0.14), "yard/fire_door")
    b.box("YardDoorStep", p, (0, 0.06, 0.18), (1.7, 0.12, 0.36), "walk_step")
    b.box("CeilingReturn", p, (0, 3.13, 0.41), (YARD_WIDTH+0.18, 0.17, 0.77), "upper_concrete", shadow=True)
    fittings = child_path(p, "Fittings")
    b.node("Fittings", p, position=vec3((0, 1.3, 0.03)))
    school_exit_fittings(b, fittings, 1.4, 2.6, 0.07, inside=True)
    lamp(b, "ExitLamp", p, (0, 2.87, 0.2), 0.88)
    # Reuse the small painted field; pigment, repeat and rule direction change on 01.
    for name, colour, repeat in (
        ("folded_tile", (0.66, 0.60, 0.63), 1.3),
        ("gallery_tile", (0.75, 0.55, 0.56), 4.4),
        ("apron_tile", (0.53, 0.64, 0.62), 1.2),
        ("recess_tile", (0.45, 0.54, 0.59), 1.3),
    ):
        b.mat(name, albedo_color=srgb(tuple(round(c*255) for c in colour)),
              albedo_texture=ruled, texture_filter=3, uv1_scale=vec3((1, repeat, 1)))
    rear_stair_and_ground_wing(b)
    return b


def foundations(b):
    """Below the walkable section; these support the set-back wings in the cutaway.

    The extension of the yard's concrete stops just under the actual yard surface,
    rather than showing a hole between the stairs and the edge of the real court.
    """
    p = "Foundations"
    b.node(p, ".")
    ground = material_for("YardGround/MeshInstance3D")
    b.box("NorthApron", p, (8, YARD_Y-0.12, -37.9), (70, 0.20, 39.8), f"yard/{ground}")
    b.box("WestApron", p, (-15.7, YARD_Y-0.12, -3.0), (22.6, 0.20, 29.8), f"yard/{ground}")
    b.box("GroundWingApron", p, (-16.0, GROUND_Y-0.22, 13.25), (28.3, 0.18, 14.9), f"yard/{ground}")
    for name, x, z, w, d, top in (
        ("LowerWest", -5.35, -11.55, 6.2, 36.5, -0.34),
        ("LowerNorth", 13.4, -33.0, 30.6, 6.0, -0.34),
        ("UpperWest", -17.2, -25.7, 5.9, 38.5, RISE-0.60),
        ("UpperNorth", (UPPER_END-14.25)/2, -48.2, UPPER_END+14.25, 6.4, RISE-0.65),
    ):
        b.box(name, p, (x, (top+YARD_Y)/2, z), (w, top-YARD_Y, d), "yard/plinth")
    for tag, top, positions in (
        ("Lower", -0.24, [(2.0, z) for z in (-22, -13, -4, 5)] +
         [(x, -25.75) for x in (5, 11, 21, 28.2)]),
        ("Upper", RISE-0.24, [(-9.96, z) for z in (-37.4, -28, -16)] +
         [(x, -40.66) for x in (-7.4, 9.6, 17.6, UPPER_END-0.55)]),
    ):
        for i, (x, z) in enumerate(positions):
            b.box(f"{tag}Column{i}", p, (x, (top+YARD_Y)/2, z), (0.47, top-YARD_Y, 0.47), "yard/plinth")


def courtyard_view():
    # The actual schoolyard layout and court paint, from the same source as the
    # playable scene. Only visible landmarks, never its physics, actors, scripts or exits.
    b = Build("CourtyardView")
    b.node("Distance", ".")
    b.flat("SkyFloor", "Distance", plane(b, 179, 180), "school_haze_floor", (16, -9, -9))
    b.node("Yard", ".", position=vec3(YARD_OFFSET))
    prefixes = ("Hoop", "Shed", "Container", "Frame", "FencePostGap", "Bird", "Tree", "SouthGate")
    named = {"YardGround", "CourtSurface", "CourtFarHalf", "SouthFenceWest", "SouthFenceEast"}
    for name, pos, size, _, _, body, _ in build_playground(for_courtyard_view=True).boxes:
        if not (name in named or name.startswith(prefixes)) or HIDE.fullmatch(name):
            continue
        # The full-height estate blocks and the yard back wall are absent from this
        # cutaway. They would slice the hall camera's view or cover the fire stair.
        path = f"{name}/MeshInstance3D" if body else name
        mat = material_for(path)
        if mat is None:
            raise ValueError(f"No yard material for {path}")
        if name == "CourtFarHalf":
            pos = (pos[0], 0.012, pos[2])
        b.box(name, "Yard", pos, size, f"yard/{mat}")
    court_landmarks(b, "Yard", material_prefix="yard/")
    b.node("SchoolPlinth", "Yard", position=vec3((0, 0.6, -19.9)))
    school_plinth_returns(b, "Yard/SchoolPlinth", material_prefix="yard/")
    foundations(b)
    return b


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stale = []
    scenes = ((LOC / "teaching_block.tscn", teaching_block()),
              (LOC / "courtyard_view.tscn", courtyard_view()),
              (ROOT / "scenes/environment/props/teaching_block_entrance.tscn", teaching_entrance()))
    for path, generated in scenes:
        text = generated.emit()
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                stale.append(str(path.relative_to(ROOT)))
        else:
            path.write_text(text, encoding="utf-8", newline="\n")
    if stale:
        sys.exit("Teaching block needs regeneration: " + ", ".join(stale))
    print("Teaching block, glass entrance and yard view " + ("match the generator." if args.check else "generated."))


if __name__ == "__main__":
    main()
