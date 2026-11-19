#!/usr/bin/env python3
"""Build the three walkable school floors and the view through their windows.

The hand-authored corridor.tscn owns the story exits, spawn markers, audio and library
props. This tool owns the measured structure. Run it with --check to check the two
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
from build_outdoor_locations import build_playground  # noqa: E402

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
# A second stair hall, beyond the biology rear door (+Z). Both branches leave
# the same 02 floor and turn on level landings. The new 01 is at yard grade.
REAR_JUNCTION_Z = (3.45, MAIN_Z[1])
REAR_JUNCTION_X = (-4.95, MAIN_X[0])
UPPER_JOIN_Z = -0.65
GROUND_Y = YARD_Y
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
}
SCENES = {
    "bio_door": f"{PROPS}/classroom_art/classroom_door.tscn",
    "bio_rear_door": f"{PROPS}/classroom_art/classroom_rear_door.tscn",
    "interactable": "res://scenes/interaction/interactable.tscn",
    "lab_door": f"{PROPS}/laboratory_entry_door.tscn",
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
    for side, x in enumerate((-width/2+0.09, width/2-0.09)):
        b.box(f"Pier{side}", p, (x, 1.56, 0.06), (0.18, 3.12, 0.29), "gallery_base")
    # Cutaway ceiling: the return/beam and its shadow remain, not a roof across the
    # follow camera's line from the open side of the sectional model.
    b.box("CeilingReturn", p, (0, 3.15, 0.23), (width, 0.25, 0.66), "upper_concrete", shadow=True)
    for i, (start, end) in enumerate(complement(-width/2, width/2,
            [(x - DOOR_WIDTH/2, x + DOOR_WIDTH/2) for x in door_x])):
        b.box(f"Skirt{i}", p, ((start+end)/2, 0.06, 0.111), (end-start, 0.12, 0.065), "walk_dado")
    # Real depth and furnishings (not a pasted image). The only playable classroom
    # interior is still its own story scene. The floor behind each slit is off its datum.
    b.box("RoomFloor", p, (0, bias - 0.1, -depth / 2 - 0.1), (width - 0.04, 0.20, depth), "upper_concrete")
    b.box("RoomBack", p, (0, 1.53, -depth - 0.1), (width, 3.25, 0.20), "gallery_base")
    for index, x in enumerate((-width / 2 + 0.08, width / 2 - 0.08)):
        b.box(f"Return{index}", p, (x, 1.53, -depth / 2 - 0.1), (0.16, 3.25, depth), "walk_plaster")
    b.box("RoomRoof", p, (0, 3.18, -depth / 2 - 0.1), (width, 0.16, depth), "roof", shadow=True)
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
    """Separate supports per window bay: the normal fader can clear only the bay
    in front of the camera, including the glass's own alpha, not the whole wing."""
    b.node(name, parent)
    p = child_path(parent, name)
    for i, (start, end) in enumerate(complement(low, high, gap)):
        count = math.ceil((end-start) / 4.4)
        width = (end-start) / count
        for j in range(count):
            s = start + (j + 0.5) * width
            pos = (axis, y, s) if west else (s, y, axis)
            w = b.shell(f"Bay{i}_{j}", p, pos, (0, -90 if west else 180, 0), ("camera_occluder",))
            b.shape("Guard", w, (0, 0.48, 0), (width, 0.96, 0.26))
            # Player and camera occluder rays still meet the panel; ground-picking
            # and depth-test rays on layer 1 can see the hall through the glass.
            panel = b.shell("GlassSafety", w, layer=4)
            b.shape("Pane", panel, (0, 2.015, 0), (width, 2.11, 0.13))
            b.box("KneeWall", w, (0, 0.43, 0), (width, 0.86, 0.26), "gallery_base")
            b.box("Rail", w, (0, 0.92, 0.004), (width, 0.12, 0.248), "gallery_frame")
            b.box("Beam", w, (0, 3.012, 0), (width, 0.176, 0.24), "gallery_base")
            b.box("LeftPost", w, (-width/2+0.038, 1.95, 0), (0.076, 1.94, 0.16), "gallery_frame")
            b.box("Mullion", w, (0, 1.95, 0), (0.046, 1.94, 0.10), "gallery_frame")
            b.flat("ClearGlass", w, quad(b, width - 0.065, 1.94), "clear_glass", (0.022, 1.95, 0))
            b.box("Sash", w, (0, 1.61, 0.012), (width-0.062, 0.028, 0.093), "gallery_frame")
            if j == count-1:
                b.box("EndPost", w, (width/2-0.02, 1.95, 0), (0.045, 1.94, 0.16), "gallery_frame")


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
        b.box(f"Nosing{i+1}", p, (0, top_y-0.022, z+run/steps/2), (width, 0.043, 0.040), cap)
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


def solid_wall(b, parent, name, pos, width, yaw=0, height=3.05, base="deep_plum"):
    """An opaque architectural return: the visible surface owns the blocking body."""
    p = b.shell(name, parent, pos, (0, yaw, 0), ("camera_occluder",))
    b.shape("Solid", p, (0, height/2, 0), (width, height, 0.22))
    b.box("Dado", p, (0, 0.47, 0), (width, 0.94, 0.22), base)
    b.box("RosePlaster", p, (0, (height+0.94)/2, 0), (width, height-0.94, 0.22), "chalk_rose")
    b.box("Frieze", p, (0, height-0.16, 0.045), (width, 0.32, 0.16), "arch_chalk")
    return p


def blind_arch(b, parent, radius, head, material, open_quarter=False):
    """A painted arcade with no door: curved trim on the solid wall's hall face."""
    b.box("Recess", parent, (0, 0.94, 0.126), (radius*1.76, 1.84, 0.045), "night_blue")
    for side, x in enumerate((-radius, radius)):
        b.box(f"Jamb{side}", parent, (x, head/2, 0.165), (0.19, head, 0.20), material)
    segments = 12
    delta = math.pi/segments
    for index in range(3 if open_quarter else 0, segments):
        a = (index+0.5)*delta
        b.box(f"Arch{index}", parent, (radius*math.cos(a), head+radius*math.sin(a), 0.165),
              (2*radius*math.tan(delta/2)+0.022, 0.19, 0.20), material,
              (0, 0, math.degrees(a)+90))


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
    ground_x, ground_z = (-26.8, -9.1), (10.55, 14.55)
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

    # 01 is a complete, roofless-for-camera gallery. Its repetition promises
    # an arcade but all four arches are blind; only the folded end is a route.
    alcove_x, alcove_z = (ground_x[0], -23.2), (5.65, ground_z[0])
    slab(b, g, "Arcade", ground_x, ground_z, GROUND_Y, "arcade_tile", rotate=True)
    slab(b, g, "Recess", alcove_x, alcove_z, GROUND_Y, "recess_tile")
    guard_edges(b, g, "ArcadeRail", ground_x, ground_z, GROUND_Y,
                {"North": [ground_x], "East": [low_track], "West": [ground_z]},
                "night_blue", "arch_chalk")
    bays = (ground_x[1]-alcove_x[1])/4
    for i, (radius, height, material) in enumerate((
            (0.86, 1.47, "arch_chalk"), (1.05, 1.29, "fern_blue"),
            (0.86, 1.47, "arch_chalk"), (0.72, 1.55, "iron_red"))):
        x = ground_x[1]-(i+0.5)*bays
        side = solid_wall(b, g, f"BlindBay{i+1}", (x, GROUND_Y, ground_z[0]), bays)
        blind_arch(b, side, radius, height, material, open_quarter=i == 3)
        # The slabs above are fragments of cornice, not roofs over the camera.
        b.box("OffsetCornice", side, ((i % 2 - 0.5)*0.44, 2.99, 0.37),
              (bays-0.24, 0.20, 0.75), material, shadow=True)
        if i % 2 == 0:
            lamp(b, "GalleryLight", side, (0.85, 2.79, 0.40), 0.59)
    sign(b, g, "FirstFloorPlate", (-9.78, GROUND_Y+2.41, ground_z[0]+0.15), "01", 0.72, plate="iron_red")
    b.box("HallInlay", g, (sum(ground_x)/2, GROUND_Y+0.009, 13.28),
          (ground_x[1]-ground_x[0]-0.7, 0.01, 0.10), "apricot")
    for i, x in enumerate((-9.6, -13.1, -16.6, -20.1, -23.6, -26.1)):
        b.box(f"CrossRule{i}", g, (x, GROUND_Y+0.007, sum(ground_z)/2),
              (0.052, 0.008, ground_z[1]-ground_z[0]-0.20), "deep_plum")

    # The opaque east return blocks a straight view from the arcade. A short
    # line of amber turns the corner, without a quest marker or a false exit.
    solid_wall(b, g, "EndWall", (ground_x[0], GROUND_Y, (alcove_z[0]+ground_z[1])/2),
               ground_z[1]-alcove_z[0], yaw=90, base="night_blue")
    return_wall = solid_wall(b, g, "RecessScreen", (alcove_x[1], GROUND_Y, sum(alcove_z)/2),
                             alcove_z[1]-alcove_z[0], yaw=-90, base="night_blue")
    b.box("AmberRule", return_wall, (0.25, 0.96, 0.123), (3.35, 0.07, 0.05), "apricot")
    b.box("ReturnInlay", g, (-25.25, GROUND_Y+0.009, (alcove_z[0]+13.28)/2),
          (0.1, 0.013, 13.28-alcove_z[0]), "apricot")
    p = solid_wall(b, g, "LaboratoryPortal", (sum(alcove_x)/2, GROUND_Y, alcove_z[0]),
                   alcove_x[1]-alcove_x[0], base="night_blue")
    b.instance("Door", p, "lab_door", (0, 0, 0))
    b.box("EnamelLintel", p, (0, 2.36, 0.23), (2.42, 0.21, 0.48), "fern_blue", shadow=True)
    lamp(b, "BorrowedLight", p, (0, 2.28, 0.34), 0.60)


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
    slab(b, u, "Turn", (-9.75, 18.25), UPPER_TURN, RISE, "upper_turn", rotate=True)
    classroom_run(b, l, True, -2.2, 0, MAIN_Z, LOWER_WEST, (west_gap, REAR_JUNCTION_Z), biology=True)
    classroom_run(b, l, False, -30, 0, (-2.2, EAST_END), LOWER_NORTH, (north_gap,))
    classroom_run(b, u, True, -14.25, RISE, UPPER_Z, UPPER_WEST)
    classroom_run(b, u, False, -45, RISE, (-14.25, 18.25), UPPER_NORTH)
    glass_run(b, l, "EastGlazing", True, 2.1, 0, -25.5, 6.95)
    glass_run(b, l, "SouthGlazing", False, TURN_Z[1], 0, MAIN_X[1], EAST_END, (yard_gap,))
    rail(b, l, "EastEnd", EAST_END, 0, sum(TURN_Z)/2, 0.19, TURN_Z[1]-TURN_Z[0])
    for side, x in zip(("West", "East"), MAIN_X):
        rail(b, l, "GateStepSide"+side, x, -0.36, 7.25, 0.19, 0.6)
    glass_run(b, u, "EastGlazing", True, -9.75, RISE, -40.5, -6.5, (west_gap,))
    glass_run(b, u, "SouthGlazing", False, -40.5, RISE, -9.75, 18.25, (upper_gap,))
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
    rail(b, u, "EastEnd", 18.25, RISE, -42.75, 0.19, 4.5)
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
    for name, parent, pos, energy in (
        ("LampBySchoolDoor", l, (-1.84, 2.91, 1.95), 0.57),
        ("LampByShortStair", l, (-1.81, 2.91, WEST_STAIR_Z), 0.44),
        ("LampAtTurn", l, (0.2, 2.91, -29.52), 0.52),
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
    # Reuse the small painted field; value, repeat and rule direction change on 01.
    for name, colour, repeat in (
        ("folded_tile", (0.66, 0.60, 0.63), 1.3),
        ("arcade_tile", (0.70, 0.55, 0.57), 4.4),
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
    b.box("WestApron", p, (-15.7, YARD_Y-0.12, -3.1), (22.6, 0.20, 30), f"yard/{ground}")
    b.box("GroundWingApron", p, (-16.0, GROUND_Y-0.22, 12.30), (28.3, 0.18, 13.0), f"yard/{ground}")
    for name, x, z, w, d, top in (
        ("LowerWest", -5.35, -11.55, 6.2, 36.5, -0.34),
        ("LowerNorth", 13.4, -33.0, 30.6, 6.0, -0.34),
        ("UpperWest", -17.2, -25.7, 5.9, 38.5, RISE-0.60),
        ("UpperNorth", 2.05, -48.2, 31.8, 6.4, RISE-0.65),
    ):
        b.box(name, p, (x, (top+YARD_Y)/2, z), (w, top-YARD_Y, d), "yard/plinth")
    for tag, top, positions in (
        ("Lower", -0.24, [(2.0, z) for z in (-22, -13, -4, 5)] +
         [(x, -25.75) for x in (5, 11, 21, 28.2)]),
        ("Upper", RISE-0.24, [(-9.96, z) for z in (-37.4, -28, -16)] +
         [(x, -40.66) for x in (-7.4, 9.6, 17.6)]),
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
    for name, pos, size, _, _, body, _ in build_playground().boxes:
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
    for filename, generated in (("teaching_block.tscn", teaching_block()), ("courtyard_view.tscn", courtyard_view())):
        path = LOC / filename
        text = generated.emit()
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                stale.append(filename)
        else:
            path.write_text(text, encoding="utf-8", newline="\n")
    if stale:
        sys.exit("Teaching block needs regeneration: " + ", ".join(stale))
    print("Teaching block and yard view " + ("match the generator." if args.check else "generated."))


if __name__ == "__main__":
    main()
