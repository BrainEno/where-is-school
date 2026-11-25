#!/usr/bin/env python3
"""Applies the stage pass to the street, courtyard and alley: writes the materials
and dresses each scene with visual-only nodes.

    python3 scenes/environment/props/stage_art/source/paint_stage_textures.py   # textures
    python3 scenes/environment/props/stage_art/source/paint_street_ditch.py     # the ditch
    python3 tools/build_outdoor_locations.py street residential alley            # graybox
    python3 scenes/environment/props/stage_art/source/build_stage_art.py         # this

The scenes are produced by `tools/build_outdoor_locations.py` (ground, walls,
colliders, interactables, exits, spawns). This script is a second, visual-only step,
written the same way as the yard's art pass
(`playground_art/source/build_playground_art.py`), whose helpers, textures and ink outline
it reuses. What it does to a scene, and nothing else:

* repoints `material_override` of existing meshes to the materials written here
  (`stage_art/materials/*.tres`) - by the material they used, or by node path - so
  `assets/materials/**` stays untouched for every other scene that uses it;
* replaces the Environment resource and retunes `Sun` (higher, so the tall blocks no
  longer bury the walkable ground in shadow; a cool ambient instead of brown murk);
* adds one `StageArt` subtree of mesh-only nodes (no bodies, no shapes), plus decals and
  extensions parented under the occluder bodies they belong to (names start with
  `Stage`), so the camera's occluder fader fades them with their wall.

It never adds a CollisionObject3D, never moves a body, a shape, an interactable, an exit
or a spawn - `tests/location_art_test.gd` checks that. It is idempotent: an earlier pass
(the `StageArt` subtree, `Stage*` nodes, `*_art<n>` meshes, `art_*` resources) is
stripped before the new one is applied. The teaching block has a separate generator
(`tools/build_teaching_block.py`); this script still writes the painted materials it reuses.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ART = HERE.parent
ROOT = HERE.parents[4]
MAT_DIR = ART / "materials"
RES = "res://scenes/environment/props/stage_art"
sys.path.insert(0, str(ROOT / "scenes" / "environment" / "props" / "playground_art" / "source"))

import build_playground_art as yard  # noqa: E402
from build_playground_art import Builder, material_tres, node_path, vec3  # noqa: E402

sys.path.insert(0, str(HERE))
from paint_stage_textures import DISTANCE  # noqa: E402

sys.path.insert(0, str(ROOT / "tools"))
from build_outdoor_locations import (  # noqa: E402
    BLEACHER_C_X, BLEACHER_RISE, BLEACHER_RUN, BLEACHER_TIERS, BLEACHER_WIDTH, DOOR_HEIGHT,
    FRONT_YARD_TREE_BOX, FRONT_YARD_TREES, FRONT_YARD_Z, GATE_HEIGHT, GATE_PIER, GROVE_RAIL_H_LEN,
    GROVE_FAR_TREES, GROVE_RAIL_V_LEN, GROVE_RAIL_Z, GROVE_TREES, SCHOOL_SOUTH_Z,
    SCHOOL_WALL_H, SCHOOL_WALL_X, STREET_DOOR_Z, STREET_GATE_Z, STREET_SCHOOL_Z, YARD_WALL_X,
)

import front_yard_meshes as yard_meshes  # noqa: E402

LOC = ROOT / "scenes" / "locations"
MARKER = '[node name="StageArt" type="Node3D" parent="."]'


def ptex(name: str) -> str:
    """A texture the yard's painter already made (reused, not copied)."""
    return yard.tex(name)


def stex(name: str) -> str:
    return f"{RES}/textures/{name}.png"


def tiled(color, texture: str = "plaster_tile", scale: float = 0.25, outline: bool = True) -> dict:
    return {"color": color, "texture": ptex(texture), "triplanar": "world", "scale": (scale, scale, scale), "outline": outline}


INK = (58, 52, 48)
GLASS = (58, 58, 78)
SCHOOL_TEAL = (120, 150, 148)
PALE = (226, 216, 190)
LIGHT_BEYOND = (236, 196, 140)

# How far the walkway goes on past the yard door (metres). The fog has taken it long before.
BEYOND = 96.0

# The street's ditch (tools/build_outdoor_locations.py places its water, pool and cover).
# The road runs z -36..20; the ditch is open from the north end to the slabs at the crossing.
STREET_LEN = 56.0
DITCH_X = (-9.725, -9.1)  # the west kerb's face to the bank
DITCH_FLOOR = -0.62
DITCH_OPEN_Z = (-36.0, 7.5)
DITCH_OPEN = DITCH_OPEN_Z[1] - DITCH_OPEN_Z[0]
EARTH_W = 4.8

# The front yard's trodden line, from the glass entrance's apron to the side door.
YARD_PATH_X = (-9.6, YARD_WALL_X - 0.2)
YARD_PATH_LEN = YARD_PATH_X[1] - YARD_PATH_X[0]
GATE_HEAD = 0.55

# name -> spec, in the yard builder's vocabulary (color, texture, triplanar, scale, offset,
# cut, cull_off, outline, unshaded).
MATERIALS: dict[str, dict] = {
    # shared by every scene of the pass
    "metal_ink": {"color": INK, "outline": True},
    "glass_dusk": {"color": GLASS},
    "school_teal": tiled(SCHOOL_TEAL),
    "light_beyond": {"color": LIGHT_BEYOND, "unshaded": True},
    "pale": {"color": PALE, "outline": True},
    "row_flats": {"color": (44, 40, 58), "texture": ptex("row_flats"), "cut": 0.5, "cull_off": True, "unshaded": True},
    "row_tower": {"color": (44, 40, 58), "texture": ptex("row_tower"), "cut": 0.5, "cull_off": True, "unshaded": True},
    "row_chimney": {"color": (52, 46, 66), "texture": ptex("row_chimney"), "cut": 0.5, "cull_off": True, "unshaded": True},
    "row_pylon": {"color": (44, 40, 58), "texture": ptex("row_pylon"), "cut": 0.5, "cull_off": True, "unshaded": True},
    # the walkway (docs/CORRIDOR_ART.md): lilac-white plaster, the classroom's deep wainscot,
    # a pale cast floor ruled like an answer sheet, and the same again past the yard door.
    "walk_plaster": tiled((206, 202, 216)),
    # Wall decal 16 x 3.1 m: the whole texture once across the quad.
    "walk_wall": {"color": (246, 246, 246), "texture": stex("corridor_wall")},
    # Keep #243's painted kit reproducible. The teaching block reuses the small
    # floor tile directly; its walls, storeys and glazing are three-dimensional.
    "walk_wall_far": {"color": (246, 246, 246), "texture": stex("corridor_wall_far"), "scale": (BEYOND / 8.0, 1.0, 1.0)},
    "walk_terrazzo": tiled((184, 176, 170), "plaster_tile"),
    "walk_floor": {"texture": stex("corridor_floor")},
    "walk_floor_far": {"texture": stex("corridor_floor_far"), "scale": (1.0, BEYOND / 4.0, 1.0)},
    "walk_dado": {"color": (60, 64, 104), "outline": True},
    "walk_door": tiled((70, 88, 132), "metal_tile", 0.5),
    "walk_step": tiled((196, 188, 180), "plaster_tile"),
    "walk_bin": tiled((96, 112, 120), "metal_tile", 0.5),
    # The upper storey's windows: a 2 m tile, 16.4 m on the walked part (8.2 tiles) and
    # BEYOND metres past the door, offset by the 0.2 tile the walked part ends on.
    "walk_windows": {"texture": stex("corridor_windows"), "cut": 0.5, "scale": (8.2, 1.0, 1.0)},
    "walk_windows_far": {"texture": stex("corridor_windows"), "cut": 0.5, "scale": (BEYOND / 2.0, 1.0, 1.0), "offset": (0.2, 0.0, 0.0)},
    "walk_distance": {"texture": stex("distance_corridor"), "unshaded": True},
    "yard_ground": tiled((214, 196, 164), "ground_tile"),
    "yard_court": {"texture": ptex("court_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25)},
    # the gym (体育馆): the hall's parquet floor and the court's lines on it, painted
    # boards on the bleacher tiers and the stage, and the scoreboard's slate.
    "gym_floor": {"color": (184, 148, 108), "roughness": 0.75, "outline": True},
    "court_line": {"texture": ptex("court_line"), "cut": 0.5, "scale": (3.0, 1.0, 1.0)},
    "bleacher_wood": {"color": (150, 112, 76), "roughness": 0.8, "outline": True},
    "stage_wood": {"color": (128, 94, 64), "roughness": 0.8, "outline": True},
    "score_slate": {"color": (58, 66, 64), "roughness": 0.6},
    # the street
    "street_asphalt": tiled((100, 98, 116), "plaster_tile"),
    "pavement": tiled((156, 148, 138), "plaster_tile"),
    "kerb": tiled((222, 212, 194), "plaster_tile"),
    "plinth_ivory": tiled((220, 208, 180)),
    "flats_rose": tiled((150, 106, 110), scale=0.2),
    "shop_ochre": tiled((184, 146, 86), scale=0.2),
    "shutter_blue": tiled((52, 68, 96), "metal_tile", 0.5),
    "road_dash": {"texture": stex("dash_line"), "cut": 0.5},
    "road_zebra": {"texture": stex("zebra"), "cut": 0.5},
    # School windows: an 8 x 6.5 m tile repeated along the 44 m wall (u = 44 / 8).
    "school_windows": {"texture": stex("window_tile"), "cut": 0.5, "scale": (5.5, 11.4 / 6.5, 1.0)},
    "street_distance": {"texture": stex("distance_street"), "unshaded": True},
    # The ditch along the west kerb and the bare earth beside it (paint_street_ditch.py).
    # The water is world-triplanar: 1.6 = 1 / 0.625 puts one texture width across the ditch,
    # the 0.56 offset lands the kerb's x -9.725 on a tile edge (u -15), and v runs 9.6 m.
    "street_earth": {"texture": stex("street_earth"), "cut": 0.5, "scale": (1.0, STREET_LEN / 9.6, 1.0)},
    "ditch_water": {"texture": stex("ditch_water"), "triplanar": "world", "scale": (1.6, 1.0, 1.0 / 9.6),
                    "offset": (0.56, 0.0, 0.0), "unshaded": True},
    "ditch_wall": {"texture": stex("ditch_wall"), "scale": (DITCH_OPEN / 2.48, 1.0, 1.0)},
    "ditch_mud": {"color": (34, 30, 36)},
    "ditch_slab": tiled((150, 144, 140), "plaster_tile"),
    "ditch_slab_new": tiled((192, 186, 178), "plaster_tile"),
    "ditch_grate": {"texture": stex("ditch_grate"), "triplanar": "world", "scale": (5.0, 5.0, 5.0), "outline": True},
    "ditch_panel": {"color": (220, 226, 160), "outline": True},
    # The school wall (围墙) and the gate in it, seen from the street and from the front yard
    # (docs/GLOSSARY.md). White facing tiles over a 1.2 m world tile, a red-brown coping.
    "school_wall": {"color": (238, 234, 228), "texture": stex("wall_tiles"), "triplanar": "world",
                    "scale": (1 / 1.2, 1 / 1.2, 1 / 1.2), "outline": True},
    "wall_coping": tiled((142, 82, 70)),
    "gate_steel": {"color": (200, 204, 212), "specular": 1, "roughness": 0.6},
    "gate_head": tiled((214, 216, 222), "metal_tile", 0.5),
    "gate_led": {"color": (232, 82, 60), "unshaded": True},
    "gate_track": {"color": (84, 86, 96)},
    "door_steel": {"color": (60, 76, 104), "outline": True},
    "door_bars": {"color": (66, 82, 110)},
    "reader_case": {"color": (46, 48, 58), "outline": True},
    "reader_face": {"texture": stex("card_reader")},
    # the front yard (前操场): packed dirt on a 4 m world tile, the trodden line across it,
    # dead trees, dead grass, a low railing to the sports ground beyond.
    "yard_dirt": {"texture": stex("yard_dirt"), "triplanar": "world", "scale": (0.25, 0.25, 0.25)},
    "yard_path": {"texture": stex("yard_path"), "cut": 0.5, "scale": (1.0, YARD_PATH_LEN / 6.0, 1.0)},
    "track_paint": {"texture": stex("track_oval"), "cut": 0.5},
    "tree_trunk": {"color": (92, 82, 78), "outline": True},
    "tree_bark": {"color": (98, 88, 82), "outline": True},
    "tree_twig": {"color": (112, 100, 94)},
    "dry_grass": {"texture": stex("dry_grass"), "cut": 0.5, "cull_off": True},
    "yard_rail": {"color": (74, 92, 88)},
    "goal_white": {"color": (226, 222, 214), "outline": True},
    "yard_school_windows": {"texture": stex("window_tile"), "cut": 0.5,
                            "scale": ((STREET_SCHOOL_Z[1] - STREET_SCHOOL_Z[0]) / 8.0, 11.4 / 6.5, 1.0)},
    "yard_school_windows_south": {"texture": stex("window_tile"), "cut": 0.5,
                                  "scale": ((SCHOOL_SOUTH_Z[1] - SCHOOL_SOUTH_Z[0]) / 8.0, 11.4 / 6.5, 1.0)},
    "front_yard_distance": {"texture": stex("distance_front_yard"), "unshaded": True},
    "north_grove_distance": {"texture": stex("distance_north_grove"), "unshaded": True},
    "gym_distance": {"texture": stex("distance_gym"), "unshaded": True},
    # the courtyard
    "court_concrete": tiled((132, 124, 120), "plaster_tile"),
    "housing_yellow": tiled((178, 160, 116), scale=0.2),
    "housing_rose": tiled((150, 110, 112), scale=0.2),
    "housing_sage": tiled((122, 138, 120), scale=0.2),
    "hedge": tiled((58, 80, 56), "foliage_tile", 0.5),
    "tank": tiled((214, 206, 186), "metal_tile", 0.5),
    "hopscotch": {"texture": stex("hopscotch"), "cut": 0.5},
    "residential_distance": {"texture": stex("distance_residential"), "unshaded": True},
    # the alley
    "alley_wall": {"color": (96, 116, 132), "texture": stex("streak_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25), "outline": True},
    "alley_wall_high": {"color": (78, 96, 116), "texture": stex("streak_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25), "outline": True},
    "alley_concrete": tiled((160, 150, 154), "plaster_tile"),
    "alley_ground": tiled((108, 104, 122), "plaster_tile"),
    "alley_paving": tiled((136, 128, 128), "plaster_tile"),
    "alley_distance": {"texture": stex("distance_alley"), "unshaded": True},
}


def environment(background, ambient, energy: float, exposure: float, fog: float, saturation: float) -> str:
    def col(c):
        return f"Color({c[0]:.3g}, {c[1]:.3g}, {c[2]:.3g}, 1)"

    lines = [
        '[sub_resource type="Environment" id="Environment_1"]',
        "background_mode = 1",
        f"background_color = {col(background)}",
        "ambient_light_source = 2",
        f"ambient_light_color = {col(ambient)}",
        f"ambient_light_energy = {energy:g}",
        "tonemap_mode = 2",
        f"tonemap_exposure = {exposure:g}",
    ]
    if fog > 0.0:
        lines += ["fog_enabled = true", "fog_light_color = Color(0.32, 0.3, 0.38, 1)", f"fog_density = {fog:g}"]
    lines += ["adjustment_enabled = true", f"adjustment_saturation = {saturation:g}", "adjustment_contrast = 1.04"]
    return "\n".join(lines) + "\n"


def sun(pitch: float, yaw: float, energy: float, color=(1, 0.8, 0.64)) -> str:
    return (
        '[node name="Sun" type="DirectionalLight3D" parent="."]\n'
        f"rotation_degrees = Vector3({pitch:g}, {yaw:g}, 0)\n"
        f"light_color = Color({color[0]:g}, {color[1]:g}, {color[2]:g}, 1)\n"
        f"light_energy = {energy:g}\n"
        "shadow_enabled = true\n"
        "directional_shadow_max_distance = 90.0\n"
    )


# The far sky band, also the clear colour, so the laid-flat sky meets the background.
SKY = (0.251, 0.29, 0.392)
COOL = (0.66, 0.64, 0.74)


def distance(b: Builder, parent: str, key: str, mat: str, y: float) -> None:
    size, (cx, cz), _rect = DISTANCE[key]
    b.node("Distance", parent)
    b.flat("SkyFloor", f"{parent}/Distance", yard.plane(b, size, size), mat, (cx, y, cz))


def cutouts(b: Builder, parent: str, rows, ground_y: float) -> None:
    """Flat cut-out ground rows (the yard's), standing on the laid-flat sky."""
    sizes = {"row_flats": (13.0, 5.4), "row_tower": (9.0, 3.75), "row_chimney": (11.0, 4.6), "row_pylon": (10.0, 4.2)}
    for name, mat, (x, z), yaw, scale in rows:
        w, h = sizes[mat]
        b.flat(name, f"{parent}/Distance", yard.quad(b, w * scale, h * scale), mat, (x, ground_y + h * scale / 2, z), (0, yaw, 0))


def box(b: Builder, size) -> str:
    return b.mesh("BoxMesh", size=vec3(size))


def return_plate(b: Builder, parent: str, name: str, pos, *, yaw=90, reverse=False, scale=1.0) -> None:
    """Enamel on a deep mount, with an asymmetric stamp readable without text."""
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)), scale=vec3((scale,) * 3))
    p = f"{parent}/{name}"
    b.flat("Case", p, box(b, (1.30, 0.72, 0.094)), "shutter_blue", (0, 0, 0.051), shadow=True)
    b.flat("Face", p, box(b, (1.15, 0.60, 0.018)), "pale", (0, 0.008, 0.102))
    b.flat("Brow", p, box(b, (1.38, 0.058, 0.15)), "metal_ink", (0, 0.354, 0.074))
    b.flat("Rule", p, box(b, (0.89, 0.023, 0.009)), "school_teal", (0.025, -0.004, 0.116))
    yard.route_mark(b, p, "Stamp", (0, 0.143, 0.119), "shutter_blue", mirrored=reverse, scale=0.92)
    yard.route_arrow(b, p, "Direction", (0, -0.145, 0.119), "shutter_blue", direction=-1 if reverse else 1)
    pin = b.mesh("CylinderMesh", top_radius="0.025", bottom_radius="0.025", height="0.016", radial_segments="10")
    for index, x in enumerate((-0.512, 0.506)):
        b.flat(f"CornerPin{index}", p, pin, "metal_ink", (x, 0.234, 0.113), (90, 0, 0))


# --- the school wall, its gate, and the front yard ---------------------------------------------

# The front yard's x minus this is the street's: the same wall, seen from either side.
YARD_TO_STREET = YARD_WALL_X - SCHOOL_WALL_X
WALL_PATHS = (r"(SchoolWallNorthExt|SchoolWallNorthWest|SchoolWallNorthEast|SchoolWallNorthDoor|SchoolWallNorth|"
              r"SchoolWall|SchoolWallSouth|GatePierNorth|"
              r"GatePierSouth|SideDoorPier|SideDoorLintel)/MeshInstance3D")


def imported(b: Builder, name: str, parent: str, mesh: str, mat: str, pos, rot=None, shadow=True) -> None:
    """A mesh from `front_yard_meshes.py` (stage_art/meshes/<mesh>.tres)."""
    b.stage_meshes = getattr(b, "stage_meshes", set()) | {mesh}
    props = {"position": vec3(pos)}
    if rot is not None:
        props["rotation_degrees"] = vec3(rot)
    props["mesh"] = f'ExtResource("stagemesh_{mesh}")'
    props["material_override"] = f'ExtResource("art_{mat}")'
    if not shadow:
        props["cast_shadow"] = "0"
    b.node(name, parent, "MeshInstance3D", **props)


def dead_tree(b: Builder, parent: str, name: str, pos, variant: str, yaw: float) -> str:
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)))
    p = f"{parent}/{name}"
    imported(b, "Trunk", p, f"dead_tree_{variant}_trunk", "tree_trunk", (0, 0, 0))
    imported(b, "Bark", p, f"dead_tree_{variant}_bark", "tree_bark", (0, 0, 0))
    imported(b, "Twig", p, f"dead_tree_{variant}_twig", "tree_twig", (0, 0, 0))
    return p


def tuft(b: Builder, parent: str, name: str, pos, yaw: float, size: float = 0.45) -> None:
    """Dead grass: two crossed cards."""
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)))
    card = yard.quad(b, size, size)
    for i in range(2):
        b.flat(f"Card{i}", f"{parent}/{name}", card, "dry_grass", (0, size / 2, 0), (0, i * 90, 0))


def school_wall_art(b: Builder, *, street: bool) -> None:
    """The wall's coping and pier caps, the retractable gate and the side door.

    Everything hangs under the wall's own bodies (camera occluders), so it fades with them.
    In each body's frame the gate and door turn to face the side the player is on: yaw 90
    faces east (the street), -90 west (the yard). Seen from either side, the gate's head
    (机头) is at the south end, by the pier between it and the side door."""
    h, pier = SCHOOL_WALL_H, GATE_PIER
    yaw = 90 if street else -90
    south = -1.0 if street else 1.0  # which way local +x runs, in terms of south
    span = (-36.0, 19.6) if street else (FRONT_YARD_Z[0] + 0.3, FRONT_YARD_Z[1] - 0.3)
    g0, g1 = STREET_GATE_Z
    d0, d1 = STREET_DOOR_Z
    lengths = {"SchoolWall": g0 - pier - span[0], "SchoolWallSouth": span[1] - d1 - pier}
    for wall, length in lengths.items():
        b.flat("StageCoping", wall, box(b, (0.42, 0.1, length)), "wall_coping", (0, h / 2 + 0.05, 0), shadow=True)
    for pier_name, depth in (("GatePierNorth", pier), ("GatePierSouth", d0 - g1), ("SideDoorPier", pier)):
        b.flat("StageCap", pier_name, box(b, (pier + 0.12, 0.12, depth + 0.12)), "wall_coping", (0, (h + 0.3) / 2 + 0.06, 0), shadow=True)
    b.flat("StageCoping", "SideDoorLintel", box(b, (0.48, 0.1, d1 - d0 + 0.02)), "wall_coping", (0, 0.3, 0), shadow=True)
    # a blank plaque on the gate's north pier, on the street face: the school's name would go here
    if street:
        b.flat("StagePlaque", "GatePierNorth", box(b, (0.03, 0.9, 0.42)), "pale", (pier / 2 + 0.015, 0.25, 0), shadow=True)
    # the retractable gate, shut: lattice from the north pier, the head against the south one
    length = g1 - g0
    lattice = length - GATE_HEAD
    b.node("StageGate", "RetractableGate", position=vec3((0, -GATE_HEIGHT / 2, 0)), rotation_degrees=vec3((0, yaw, 0)))
    g = "RetractableGate/StageGate"
    mesh = f"retractable_gate_{int(round(lattice * 100))}"
    if south > 0:
        imported(b, "Lattice", g, mesh, "gate_steel", (-length / 2, 0, 0))
    else:
        imported(b, "Lattice", g, mesh, "gate_steel", (length / 2, 0, 0), (0, 180, 0))
    hx = south * (length / 2 - GATE_HEAD / 2)
    b.flat("Head", g, box(b, (GATE_HEAD, 1.72, 0.38)), "gate_head", (hx, 0.92, 0), shadow=True)
    b.flat("HeadCap", g, box(b, (GATE_HEAD + 0.06, 0.06, 0.44)), "metal_ink", (hx, 1.81, 0))
    b.flat("HeadLed", g, box(b, (0.36, 0.07, 0.012)), "gate_led", (hx, 1.52, 0.196))
    b.flat("HeadWheels", g, box(b, (GATE_HEAD - 0.06, 0.08, 0.3)), "metal_ink", (hx, 0.04, 0))
    b.flat("Track", g, box(b, (length + pier, 0.025, 0.12)), "gate_track", (0, 0.0125, 0))
    # the side door: its frame and its leaf of bars, shut
    b.node("StageDoor", "SideDoor", position=vec3((0, -DOOR_HEIGHT / 2, 0)), rotation_degrees=vec3((0, yaw, 0)))
    imported(b, "Frame", "SideDoor/StageDoor", "side_door_frame", "door_steel", (0, 0, 0))
    imported(b, "Bars", "SideDoor/StageDoor", "side_door_bars", "door_bars", (0, 0, 0))
    if street:
        return
    # Inside the door, on its pier: the card reader (刷卡机), a box with its face, its conduit
    # running down the pier into the ground. Only to look at; the door opens without it.
    r = "SideDoorPier/StageCardReader"
    b.node("StageCardReader", "SideDoorPier", position=vec3((-pier / 2 - 0.002, 1.3 - (h + 0.3) / 2, 0)),
           rotation_degrees=vec3((0, -90, 0)))
    b.flat("Body", r, box(b, (0.15, 0.21, 0.055)), "reader_case", (0, 0, 0.0275), shadow=True)
    b.flat("Face", r, yard.quad(b, 0.12, 0.16), "reader_face", (0, 0, 0.0565))
    b.flat("Hood", r, box(b, (0.17, 0.02, 0.08)), "reader_case", (0, 0.115, 0.04))
    b.flat("Conduit", r, box(b, (0.025, 1.2, 0.025)), "metal_ink", (0.05, -0.705, 0.0125))


def front_yard_nodes() -> Builder:
    b = Builder()
    A = "StageArt"
    b.nodes.append(MARKER + "\n")
    distance(b, A, "front_yard", "front_yard_distance", -1.6)
    cutouts(b, A, [
        ("RowFlats", "row_flats", (-6.0, -50.0), 30, 1.3),
        ("RowPylon", "row_pylon", (16.0, -44.0), 40, 1.0),
        ("RowTower", "row_tower", (-26.0, -58.0), 20, 1.5),
        # Round 27: the rows lined up south, beyond the rail and the gym, facing the yard.
        ("RowFlatsSouth", "row_flats", (-2.0, 58.0), 180, 1.3),
        ("RowTowerSouth", "row_tower", (12.0, 64.0), 180, 1.5),
    ], -1.6)
    # The sports ground past the railings, north and south: the same dirt into the haze, a
    # few more dead trees, and a football goal with no net, far off to the north.
    beyond = f"{A}/Beyond"
    b.node("Beyond", A)
    z0, z1 = FRONT_YARD_Z
    b.flat("NorthGround", beyond, yard.plane(b, 70.0, 34.0), "yard_dirt", (2.0, -0.005, z0 - 17.0))
    b.flat("SouthGround", beyond, yard.plane(b, 70.0, 30.0), "yard_dirt", (2.0, -0.005, z1 + 15.0))
    far = [(-2.5, -14.5, "b", 0), (8.5, -19.0, "a", 90), (-8.0, -25.0, "c", 180), (15.0, -12.5, "c", 270),
           (2.5, -31.0, "a", 0), (-4.0, 39.5, "a", 180), (8.0, 44.0, "b", 0), (17.0, 40.0, "c", 90)]
    for i, (x, z, variant, yaw_) in enumerate(far):
        dead_tree(b, beyond, f"Tree{i}", (x, 0.0, z), variant, yaw_)
    goal = f"{beyond}/Goal"
    b.node("Goal", beyond, position=vec3((4.0, 0.0, -27.0)), rotation_degrees=vec3((0, 8, 0)))
    post = box(b, (0.1, 2.44, 0.1))
    for i, x in enumerate((-3.66, 3.66)):
        b.flat(f"Post{i}", goal, post, "goal_white", (x, 1.22, 0), shadow=True)
        b.flat(f"Stay{i}", goal, box(b, (0.06, 0.06, 1.6)), "goal_white", (x, 0.03, -0.8))
    b.flat("Bar", goal, box(b, (7.42, 0.1, 0.1)), "goal_white", (0, 2.44, 0), shadow=True)
    # Past the school wall, the street the side door goes out to, where the street scene has
    # it (its x + YARD_TO_STREET): the pavement under the wall, the road and its broken centre
    # line, the far pavement, and the rose flats and the ochre shop across it. Out of reach.
    street = f"{A}/PastTheGate"
    b.node("PastTheGate", A)
    sx = YARD_TO_STREET
    b.flat("Pavement", street, yard.plane(b, 1.4, 70.0), "pavement", (sx - 10.6, 0.07, -2.0))
    b.flat("Road", street, yard.plane(b, 19.9, 70.0), "street_asphalt", (sx + 0.05, -0.004, -2.0))
    b.flat("CentreLine", street, yard.plane(b, 0.4, 56.0), "road_dash", (sx - 0.6, 0.002, -8.0))
    b.flat("FarPavement", street, yard.plane(b, 8.0, 70.0), "pavement", (sx + 13.0, 0.07, -2.0))
    b.flat("FarKerb", street, box(b, (0.35, 0.24, 70.0)), "kerb", (sx + 8.9, 0.12, -2.0))
    for name, mat, pos, size in (("FlatsA", "flats_rose", (17.0, 5.5, 6.0), (10.0, 11.0, 16.0)),
                                 ("FlatsB", "flats_rose", (16.0, 7.0, -12.0), (8.0, 14.0, 14.0)),
                                 ("Shop", "shop_ochre", (14.0, 3.6, -24.0), (8.0, 7.2, 10.0))):
        b.flat(name, street, box(b, size), mat, (sx + pos[0], pos[1], pos[2]), shadow=True)
    # The yard's own trees, each inside its fader box (the generator's DeadTreeN body).
    bw, bh = FRONT_YARD_TREE_BOX
    for i, (_x, _z, variant, yaw_) in enumerate(FRONT_YARD_TREES):
        dead_tree(b, f"DeadTree{i}", "StageTree", (0, -(bh / 2 - 0.1), 0), variant, yaw_)
    # the railings (their graybox hidden); the trodden line from the entrance to the side door
    rail_len = YARD_WALL_X + 0.15 + 11.0
    for rail in ("NorthRail", "SouthRail"):
        imported(b, "StageRail", rail, f"yard_railing_{int(round(rail_len * 100))}", "yard_rail", (-rail_len / 2, -0.6, 0))
    # Round 26: coping on the wall's new north run, and the grove's mouth tree (its crown
    # box is on the grove's fade layer, so the stage tree fades with it like the yard's).
    b.flat("StageCoping", "SchoolWallNorthExt", box(b, (0.42, 0.1, 4.8)), "wall_coping",
           (0, SCHOOL_WALL_H / 2 + 0.05, 0), shadow=True)
    # Round 28: the north run carries the gym's door - coping on its two runs and a cap
    # over the leaf (the leaf's frame is the grove's business, on its side of the wall).
    b.flat("StageCoping", "SchoolWallNorthWest", box(b, (12.0, 0.1, 0.42)), "wall_coping",
           (0, SCHOOL_WALL_H / 2 + 0.05, 0), shadow=True)
    b.flat("StageCoping", "SchoolWallNorthEast", box(b, (12.7, 0.1, 0.42)), "wall_coping",
           (0, SCHOOL_WALL_H / 2 + 0.05, 0), shadow=True)
    b.flat("StageCoping", "SchoolWallNorthDoor", box(b, (1.72, 0.1, 0.44)), "wall_coping",
           (0, 1.65, 0), shadow=True)
    dead_tree(b, "GroveHintTree", "StageTree", (0, -3.55, 0), "c", 90)
    d_mid = sum(STREET_DOOR_Z) / 2.0
    b.node("Ground", A)
    b.flat("Path", f"{A}/Ground", yard.plane(b, 2.4, YARD_PATH_LEN), "yard_path",
           ((YARD_PATH_X[0] + YARD_PATH_X[1]) / 2, 0.003, d_mid), (0, 90, 0))
    # dead grass along the foot of the walls and railings, and round the trees
    rng_pts = []
    for i in range(14):
        rng_pts.append((-9.2 + i * 1.83 + 0.4 * ((i * 7) % 3 - 1), z0 + 0.55 + 0.15 * (i % 2)))
        rng_pts.append((-8.9 + i * 1.79 + 0.35 * ((i * 5) % 3 - 1), z1 - 0.55 - 0.15 * (i % 2)))
    for i, z in enumerate((-6.0, -2.4, 1.6, 5.2, 19.8, 23.0, 26.8, 30.0)):
        rng_pts.append((YARD_WALL_X - 0.5 - 0.15 * (i % 2), z))
    for x, z, _v, _y in FRONT_YARD_TREES:
        rng_pts += [(x + 0.55, z - 0.3), (x - 0.4, z + 0.5)]
    for i, (x, z) in enumerate(rng_pts):
        tuft(b, f"{A}/Ground", f"Tuft{i}", (x, 0.0, z), (i * 47) % 180, 0.38 + 0.12 * ((i * 3) % 4) / 3)
    # the teaching block's windows, as on the street before (children of the occluders)
    width = STREET_SCHOOL_Z[1] - STREET_SCHOOL_Z[0]
    b.flat("StageWindows", "SchoolBlock", yard.quad(b, width, 11.4), "yard_school_windows", (5.006, 0.5, 0.0), (0, 90, 0))
    south = SCHOOL_SOUTH_Z[1] - SCHOOL_SOUTH_Z[0]
    b.flat("StageWindows", "SchoolBlockSouth", yard.quad(b, south, 11.4), "yard_school_windows_south",
           (5.006, 0.5, 0.0), (0, 90, 0))
    # Round 29: the dirt oval's running track (操场跑道), the sketch's chalk ring east
    # of the block: three concentric lanes as one flat decal on the dirt, a clear of the
    # side door's path and the retractable gate, and of the fence's tree at x 10.2. Paint
    # on the ground - no collider, the ground's own body answers every sight line.
    b.flat("StageTrack", A, yard.plane(b, 9.0, 15.0), "track_paint", (7.0, 0.02, 12.0))
    school_wall_art(b, street=False)
    # Round 27: the gym (体育馆) beyond the school wall's north-east corner - a high window
    # band and its shut double doors on the south face, as children of the graybox body so
    # they fade with it. The equipment room's (器材室) graybox leaf stays; the stage pass
    # adds the frame round it.
    b.flat("StageGymWindows", "Gym", yard.quad(b, 13.0, 2.6), "yard_school_windows", (0, 1.9, 4.506))
    for name, x in (("StageGymDoorWest", -0.36), ("StageGymDoorEast", 0.36)):
        b.flat(name, "Gym", box(b, (0.72, 2.5, 0.12)), "gate_steel", (x, -1.85, 4.55), shadow=True)
    for side in (-1, 1):
        b.flat(f"StageDoorJamb{side}", "EquipmentRoom", box(b, (0.08, 2.3, 0.26)), "metal_ink",
               (side * 0.69, 0.45, 1.74), shadow=True)
    b.flat("StageDoorHead", "EquipmentRoom", box(b, (1.6, 0.12, 0.26)), "metal_ink", (0, 1.75, 1.74), shadow=True)
    # Round 29: the changing room's (更衣室) door frame, the equipment room's twin.
    for side in (-1, 1):
        b.flat(f"StageDoorJamb{side}", "ChangingRoom", box(b, (0.08, 2.3, 0.26)), "metal_ink",
               (side * 0.69, 0.45, 1.74), shadow=True)
    b.flat("StageDoorHead", "ChangingRoom", box(b, (1.6, 0.12, 0.26)), "metal_ink", (0, 1.75, 1.74), shadow=True)
    return b


FRONT_YARD = {
    "scene": LOC / "front_yard" / "front_yard.tscn",
    "environment": environment(SKY, COOL, 1.0, 0.8, 0.003, 1.0),
    "sun": sun(-48, 38, 0.5),
    "by_material": {
        "outdoor_concrete.tres": "pavement",
        "wall_paint.tres": "school_teal",
        "metal_dark.tres": "metal_ink",
        "outdoor_soil.tres": "yard_dirt",
    },
    "by_path": {
        r"SchoolPlinth(South)?/MeshInstance3D": "plinth_ivory",
        WALL_PATHS: "school_wall",
    },
    "hidden": [r"(RetractableGate|SideDoor|NorthRail|SouthRail)/MeshInstance3D", r"DeadTree\d+(Trunk)?/MeshInstance3D",
               r"GroveHintTree(Trunk)?/MeshInstance3D"],
    "nodes": front_yard_nodes,
}


# --- the north grove ----------------------------------------------------------------------------


def north_grove_nodes() -> Builder:
    """The strip's dressing: dirt past every edge, the trees, the railing meshes, the walls."""
    b = Builder()
    A = "StageArt"
    b.nodes.append(MARKER + "\n")
    # The painted distance: a sky floor a metre and a half under the walkable ground, so
    # the fog takes the strip's edges instead of a void; then the front yard's east margin
    # beyond the railings, on the same dirt.
    distance(b, A, "north_grove", "north_grove_distance", -1.6)
    b.node("Beyond", A)
    b.flat("Ground", f"{A}/Beyond", yard.plane(b, 70.0, 55.0), "yard_dirt", (-12.0, -0.01, -9.0))
    # The far trees hang under their fading bodies (the generator's GroveFarTreeN),
    # so a sight line that crosses one fades it instead of blocking the view.
    for i, (_x, _z, variant, yaw_) in enumerate(GROVE_FAR_TREES):
        dead_tree(b, f"GroveFarTree{i}", "StageTree", (0, -3.55, 0), variant, yaw_)
    # The trodden line down the L.
    b.node("Ground", A)
    b.flat("PathEast", f"{A}/Ground", yard.plane(b, 1.6, 20.0), "yard_path", (1.7, 0.003, -7.6))
    b.flat("PathNorth", f"{A}/Ground", yard.plane(b, 1.6, 22.6), "yard_path", (-11.7, 0.003, -18.85), (0, 90, 0))
    # The strip's own trees, each inside its crown box (the generator's GroveTreeN body).
    for i, (_x, _z, variant, yaw_) in enumerate(GROVE_TREES):
        dead_tree(b, f"GroveTree{i}", "StageTree", (0, -3.55, 0), variant, yaw_)
    # The railings (their graybox hidden): the yard's railing mesh, cut to the two runs.
    # The mesh runs along local x from 0 to its length with its foot at y 0, so the south
    # run takes it straight and the west run takes it turned (local x onto parent z, from
    # the corner post south to the mouth post).
    imported(b, "StageRail", "GroveRailRunWest", f"yard_railing_{int(round(GROVE_RAIL_V_LEN * 100))}",
             "yard_rail", (0, -0.6, GROVE_RAIL_Z), (0, -90, 0))
    imported(b, "StageRail", "GroveRailRunSouth", f"yard_railing_{int(round(GROVE_RAIL_H_LEN * 100))}",
             "yard_rail", (-GROVE_RAIL_H_LEN / 2, -0.6, 0))
    # Coping on the school wall's three runs and on the block's north face at the west end.
    h = SCHOOL_WALL_H
    b.flat("StageCoping", "GroveWallEast", box(b, (0.52, 0.1, 20.85)), "wall_coping", (0, h / 2 + 0.05, 0), shadow=True)
    b.flat("StageCoping", "GroveWallSouth", box(b, (0.52, 0.1, 2.4)), "wall_coping", (0, h / 2 + 0.05, 0), shadow=True)
    # Round 28: the north run carries the gym's door - coping on its two runs and a cap
    # over the leaf, then the leaf's own frame and dark inset (the exit outlines it).
    b.flat("StageCoping", "GroveWallNorthWest", box(b, (25.1, 0.1, 0.52)), "wall_coping", (0, h / 2 + 0.05, 0), shadow=True)
    b.flat("StageCoping", "GroveWallNorthEast", box(b, (0.8, 0.1, 0.52)), "wall_coping", (0, h / 2 + 0.05, 0), shadow=True)
    b.flat("StageCoping", "GroveWallDoor", box(b, (1.72, 0.1, 0.52)), "wall_coping", (0, 1.35, 0), shadow=True)
    b.flat("StageCoping", "GroveBlockFacade", box(b, (10.4, 0.1, 0.6)), "wall_coping", (0, 6.55, 0), shadow=True)
    # The mouth: a dark inset filling the east wall's opening, so the strip's south end
    # reads as a way through (and gives the exit something to outline).
    b.flat("Mouth", A, yard.quad(b, 1.4, 2.1), "metal_ink", (3.39, 1.05, 0.7), (0, -90, 0))
    # Round 28: the gym beyond the wall - the shell's south face carries the plinth edge,
    # the steel double doors and the window band, the yard's dressing again (children of
    # the far shell and its plinth, so they fade with them); the wall's own door gets its
    # jambs, head and a dark inset, so the strip's north end reads as a way through too.
    b.flat("StageGymWindowsFar", "GymShellFar", yard.quad(b, 13.0, 2.6), "yard_school_windows", (0, 1.9, 4.506))
    for name, x in (("StageGymDoorWestFar", -0.36), ("StageGymDoorEastFar", 0.36)):
        b.flat(name, "GymShellFar", box(b, (0.72, 2.5, 0.12)), "gate_steel", (x, -1.85, 4.55), shadow=True)
    b.flat("StageGymPlinthFar", "GymPlinthFar", box(b, (14.44, 0.12, 9.44)), "wall_coping", (0, 0.61, 0), shadow=True)
    b.flat("StageDoorJamb", "GroveWallDoor", box(b, (0.08, 2.7, 0.2)), "metal_ink", (-0.84, 0.05, 0.1), shadow=True)
    b.flat("StageDoorJamb", "GroveWallDoor", box(b, (0.08, 2.7, 0.2)), "metal_ink", (0.84, 0.05, 0.1), shadow=True)
    b.flat("StageDoorHead", "GroveWallDoor", box(b, (1.84, 0.2, 0.2)), "metal_ink", (0, 1.45, 0.1), shadow=True)
    # Dead grass along the railings and the wall foot, and round the trees.
    rng_pts = []
    for i in range(12):
        rng_pts.append((0.55 + (i % 2) * 2.25 + 0.2 * ((i * 5) % 3 - 1), 1.6 - i * 1.62))
    for i in range(10):
        rng_pts.append((-0.9 - i * 2.3, -17.75 + 0.15 * (i % 2)))
        rng_pts.append((-2.1 - i * 2.3, -20.0 - 0.15 * (i % 2)))
    for x, z, _v, _y in GROVE_TREES:
        rng_pts += [(x + 0.55, z - 0.3), (x - 0.4, z + 0.5)]
    for i, (x, z) in enumerate(rng_pts):
        tuft(b, f"{A}/Ground", f"Tuft{i}", (x, 0.0, z), (i * 47) % 180, 0.38 + 0.12 * ((i * 3) % 4) / 3)
    # The teaching block's barred windows on the facade, as the yard paints them.
    b.flat("StageWindows", "GroveBlockFacade", yard.quad(b, 10.0, 11.4), "yard_school_windows", (0, 0.5, 0.006))
    return b


NORTH_GROVE = {
    "scene": LOC / "north_grove" / "north_grove.tscn",
    "environment": environment(SKY, COOL, 1.0, 0.8, 0.003, 1.0),
    "sun": sun(-48, 38, 0.5),
    "by_material": {
        "outdoor_concrete.tres": "pavement",
        "wall_paint.tres": "school_teal",
        "metal_dark.tres": "metal_ink",
        "outdoor_soil.tres": "yard_dirt",
    },
    "by_path": {},
    "hidden": [r"(GroveTree\d+(Trunk)?)/MeshInstance3D",
               r"(GroveRailRunWest|GroveRailRunSouth)/MeshInstance3D"],
    "nodes": north_grove_nodes,
}


# --- the gym ------------------------------------------------------------------------------------


def gym_nodes() -> Builder:
    """The hall's dressing: the court's lines, the bleacher seats, the stage's boards, the
    doors' frame, the window band glowing on the south face, the scoreboard's face."""
    b = Builder()
    A = "StageArt"
    b.nodes.append(MARKER + "\n")
    # The painted distance: a sky floor 1.4 m under the hall floor (its top must sit a
    # metre below the floor box's underside, the lowest box bottom in the room).
    distance(b, A, "gym", "gym_distance", -0.2)
    # The court's lines on the parquet (GymFloor's top, y 1.2): the border and the mid line.
    b.node("Court", A)
    b.flat("LineNorth", f"{A}/Court", yard.plane(b, 13.0, 0.06), "court_line", (6.5, 1.206, -31.9))
    b.flat("LineSouth", f"{A}/Court", yard.plane(b, 13.0, 0.06), "court_line", (6.5, 1.206, -24.1))
    b.flat("LineWest", f"{A}/Court", yard.plane(b, 0.06, 7.9), "court_line", (2.36, 1.206, -28.0))
    b.flat("LineEast", f"{A}/Court", yard.plane(b, 0.06, 7.9), "court_line", (13.0, 1.206, -28.0))
    b.flat("LineMid", f"{A}/Court", yard.plane(b, 0.06, 2.2), "court_line", (6.5, 1.206, -25.2))
    # The bleacher seats' painted boards (children of the tiers, so they fade with them).
    for i in range(BLEACHER_TIERS):
        b.flat(f"StageSeat{i}", f"Bleacher{i}", yard.plane(b, BLEACHER_WIDTH - 0.1, BLEACHER_RUN - 0.05),
               "bleacher_wood", (0, (i + 1) * BLEACHER_RISE / 2 + 0.006, 0))
    # The stage's boards: the platform top and its front face (children of the Deck body;
    # the flats keep the Stage prefix, so the surgery recycles them with the rest).
    b.flat("StageTop", "Deck", yard.plane(b, 2.4, 4.9), "stage_wood", (0.0, 0.48, 0))
    b.flat("StageFace", "Deck", yard.quad(b, 4.9, 0.9), "stage_wood", (1.26, 0.0, 0.0), (0, 90, 0))
    # The steel doors' frame round the leaves, and the window band glowing on the south
    # face's inside (the same band the yard paints on the face outside, one quad per run
    # of the wall so each fades with its own body).
    b.flat("StageDoorJamb", "GymDoorWest", box(b, (0.1, 2.6, 0.2)), "metal_ink", (-0.41, -0.05, 0.0), shadow=True)
    b.flat("StageDoorJamb", "GymDoorEast", box(b, (0.1, 2.6, 0.2)), "metal_ink", (0.41, -0.05, 0.0), shadow=True)
    b.flat("StageDoorHead", "GymDoorHead", box(b, (1.7, 0.1, 0.2)), "metal_ink", (0, -2.325, -0.05), shadow=True)
    b.flat("StageWindowsIn", "GymWallSouthWest", yard.quad(b, 6.0, 2.6), "yard_school_windows", (0.2, 1.4, -0.16))
    b.flat("StageWindowsIn", "GymWallSouthEast", yard.quad(b, 6.0, 2.6), "yard_school_windows", (-0.2, 1.4, -0.16))
    # The scoreboard's slate face and its pale score dashes (children of the board).
    b.flat("StageScoreFace", "Scoreboard", yard.quad(b, 3.0, 1.5), "score_slate", (-0.13, 0.0, 0.0), (0, -90, 0))
    for i, z in enumerate((-0.85, -0.65, -0.45, 0.45, 0.65, 0.85)):
        b.flat(f"StageScoreDash{i}", "Scoreboard", box(b, (0.005, 0.28, 0.12)), "pale", (-0.15, 0.2, z), shadow=False)
    return b


GYM = {
    "scene": LOC / "gym" / "gym.tscn",
    "environment": environment(SKY, COOL, 1.0, 0.8, 0.003, 1.0),
    "sun": sun(-48, 38, 0.5),
    "by_material": {
        "outdoor_concrete.tres": "pavement",
        "wall_paint.tres": "school_teal",
        "metal_dark.tres": "metal_ink",
        "floor_concrete.tres": "gym_floor",
        "desk_wood.tres": "stage_wood",
    },
    "by_path": {},
    "hidden": [],
    "nodes": gym_nodes,
}


# --- the street ---------------------------------------------------------------------------------


def street_ditch(b: Builder, A: str) -> None:
    """The gutter as a ditch cut along the west kerb, and bare earth on its road side.

    The graybox Road mesh is hidden (its collider stays, so nothing about the walk or the
    navigation changes) and redrawn here east of the bank; the ditch between is lined, with
    its water (`Gutter`, `GutterPool`) 0.38 m down. From the crossing to the school entrance it
    runs under precast slabs, as ditches do where people cross them. Past the street's north
    end, where the road gives out into the laid-flat sky, one pale ribbed panel stands in
    the ditch's line: the owner's reference collage, pasted in."""
    x0, x1 = DITCH_X
    wd, mid_x = x1 - x0, (x0 + x1) / 2
    z_mid = -36.0 + STREET_LEN / 2
    p = f"{A}/Ditch"
    b.node("Ditch", A)
    # the road again, east of the bank; the bed under the kerb, and the ditch's shell
    b.flat("RoadBed", p, box(b, (11.0 - x1, 0.2, STREET_LEN)), "street_asphalt", ((11.0 + x1) / 2, -0.1, z_mid), shadow=True)
    b.flat("KerbBed", p, box(b, (x0 + 11.0, 0.715, STREET_LEN)), "pavement", ((x0 - 11.0) / 2, -0.3625, z_mid))
    b.flat("Bank", p, box(b, (0.2, 0.715, STREET_LEN)), "pavement", (x1 + 0.1, -0.3625, z_mid))
    b.flat("Floor", p, box(b, (wd, 0.1, STREET_LEN)), "ditch_mud", (mid_x, DITCH_FLOOR - 0.05, z_mid))
    b.flat("NorthEnd", p, box(b, (wd, 0.72, 0.1)), "pavement", (mid_x, -0.36, DITCH_OPEN_Z[0] + 0.05))
    # the lining under the kerb, the face the camera looks at across the ditch
    b.flat("Lining", p, yard.quad(b, DITCH_OPEN, -DITCH_FLOOR), "ditch_wall",
           (x0 + 0.003, DITCH_FLOOR / 2, (DITCH_OPEN_Z[0] + DITCH_OPEN_Z[1]) / 2), (0, 90, 0))
    # a cast coping on the bank: with the kerb, two pale edges that frame the dark water
    b.flat("Coping", p, box(b, (0.14, 0.06, DITCH_OPEN)), "kerb", (x1 + 0.07, -0.006, (DITCH_OPEN_Z[0] + DITCH_OPEN_Z[1]) / 2))
    # the earth on the road side, crumbling out over the asphalt
    b.flat("Earth", p, yard.plane(b, EARTH_W, STREET_LEN), "street_earth", (x1 + EARTH_W / 2, 0.002, z_mid))
    # slabs from the crossing to the end of the street: one replaced, paler than the rest
    z, end, gap = DITCH_OPEN_Z[1], 20.0, 0.025
    count = 12
    length = (end - z - gap * count) / count
    covered = end - z
    b.flat("Covered", p, box(b, (wd, 0.24, covered)), "ditch_mud", (mid_x, -0.2, z + covered / 2))
    slab = box(b, (wd, 0.07, length))
    for i in range(count):
        zc = z + gap / 2 + length / 2 + i * (length + gap)
        b.flat(f"Slab{i}", p, slab, "ditch_slab_new" if i == 4 else "ditch_slab", (mid_x, -0.035, zc))
    # the panel past the north end, standing in the ditch's line on nothing
    q = f"{p}/Panel"
    b.node("Panel", p, position=vec3((mid_x, 0.0, -38.4)), rotation_degrees=vec3((0, 7, 0)))
    b.flat("Board", q, box(b, (0.05, 2.0, 2.6)), "ditch_panel", (0, 0.4, 0), shadow=True)
    rib = box(b, (0.07, 1.94, 0.1))
    for i in range(15):
        b.flat(f"Rib{i}", q, rib, "ditch_panel", (0.06, 0.4, -1.12 + i * 0.16), shadow=True)
    post = box(b, (0.04, 2.0, 0.04))
    for i, zp in enumerate((1.34, 1.52)):
        b.flat(f"Post{i}", q, post, "ditch_panel", (0.02, 0.4, zp), shadow=True)
    brace = box(b, (0.03, 0.24, 0.03))
    for i in range(7):
        b.flat(f"Brace{i}", q, brace, "ditch_panel", (0.02, -0.45 + i * 0.27, 1.43), (40 if i % 2 else -40, 0, 0))


def street_nodes() -> Builder:
    b = Builder()
    A = "StageArt"
    b.nodes.append(MARKER + "\n")
    # The road runs off its north end into the laid-flat sky; cut-out rows stand out there.
    distance(b, A, "street", "street_distance", -1.6)
    cutouts(b, A, [
        ("RowFlats", "row_flats", (-8.0, -52.0), 30, 1.3),
        ("RowTower", "row_tower", (6.0, -60.0), 20, 1.6),
        ("RowPylon", "row_pylon", (-22.0, -46.0), 45, 1.0),
        ("RowChimney", "row_chimney", (-30.0, 30.0), 60, 1.2),
    ], -1.6)
    # One sign past the end of the road, on a pole that stands in the sky. Nothing on it.
    b.node("Landmark", A)
    b.flat("SignPole", f"{A}/Landmark", box(b, (0.12, 6.6, 0.12)), "metal_ink", (-3.0, 1.7, -40.0), shadow=True)
    b.flat("SignBoard", f"{A}/Landmark", box(b, (1.6, 1.0, 0.06)), "pale", (-3.0, 4.6, -39.95), (0, 18, 0), shadow=True)
    street_ditch(b, A)
    # Paint on the road.
    b.node("Road", A)
    b.flat("CentreLine", f"{A}/Road", yard.plane(b, 0.4, 56.0), "road_dash", (-0.6, 0.004, -8.0))
    b.flat("Crossing", f"{A}/Road", yard.plane(b, 18.4, 3.0), "road_zebra", (-0.5, 0.005, 9.5))
    # Over the wall (west): the front yard's dirt, two of its dead trees where they stand in
    # the yard, and the teaching block across it, all where the front yard has them
    # (that scene's x minus YARD_TO_STREET). Nothing over there can be walked to.
    beyond = f"{A}/OverTheWall"
    b.node("OverTheWall", A)
    b.flat("YardDirt", beyond, yard.plane(b, 60.0, 56.0), "yard_dirt", (SCHOOL_WALL_X - 30.2, -0.005, -8.0))
    for i, (x, z, variant, yaw) in enumerate(FRONT_YARD_TREES):
        if z < 19.0:
            dead_tree(b, beyond, f"Tree{i}", (x - YARD_TO_STREET, 0.0, z), variant, yaw)
    block = f"{beyond}/TeachingBlock"
    width = STREET_SCHOOL_Z[1] - STREET_SCHOOL_Z[0]
    mid = sum(STREET_SCHOOL_Z) / 2.0
    b.node("TeachingBlock", beyond, position=vec3((-16.0 - YARD_TO_STREET, 6.5, mid)))
    b.flat("Mass", block, box(b, (10.0, 13.0, width)), "school_teal", (0, 0, 0), shadow=True)
    b.flat("Windows", block, yard.quad(b, width, 11.4), "yard_school_windows", (5.006, 0.5, 0.0), (0, 90, 0))
    school_wall_art(b, street=True)
    # The return plate, on the school wall now where it was on the school's front.
    wall_mid = (-36.0 + STREET_GATE_Z[0] - GATE_PIER) / 2.0
    return_plate(b, "SchoolWall", "StageReturnPlate", (0.154, 1.58 - SCHOOL_WALL_H / 2, -10.8 - wall_mid))
    # A receipt hatch farther down the wall's foot. The lip, not the wall, is pickable.
    name = "StageReceiptSlot"
    b.node(name, "SchoolWallDado", position=vec3((0.254, 0.34, -24.7 - wall_mid)), rotation_degrees=vec3((0, 90, 0)))
    p = "SchoolWallDado/" + name
    b.flat("Housing", p, box(b, (0.92, 0.48, 0.104)), "shutter_blue", (0, 0, 0.053), shadow=True)
    b.flat("Slot", p, box(b, (0.68, 0.052, 0.024)), "metal_ink", (-0.022, 0.082, 0.109))
    b.flat("DripEdge", p, box(b, (0.85, 0.048, 0.154)), "school_teal", (0, 0.193, 0.082))
    b.flat("WoodStop", p, box(b, (0.70, 0.07, 0.112)), "shop_ochre", (-0.02, -0.126, 0.143))
    b.flat("Polish", p, box(b, (0.41, 0.009, 0.049)), "pale", (-0.082, -0.087, 0.171))
    for i, x in enumerate((-0.382, 0.389)):
        b.flat(f"Bolt{i}", p, box(b, (0.038, 0.036, 0.017)), "pale", (x, -0.089, 0.109), (0, 0, 10 + i * 16))
    return b


STREET = {
    "scene": LOC / "street" / "street.tscn",
    "environment": environment(SKY, COOL, 1.0, 0.78, 0.003, 1.0),
    "sun": sun(-48, 38, 0.5),
    "by_material": {
        "outdoor_asphalt.tres": "street_asphalt",
        "outdoor_concrete.tres": "pavement",
        "wall_paint.tres": "school_teal",
        "outdoor_brick.tres": "flats_rose",
        "metal_dark.tres": "metal_ink",
        "shutter_metal.tres": "shutter_blue",
    },
    "by_path": {
        r"SchoolWallDado/MeshInstance3D": "plinth_ivory",
        WALL_PATHS: "school_wall",
        r"Kerb(East|West)/MeshInstance3D": "kerb",
        r"ShopBlock/MeshInstance3D": "shop_ochre",
        r"Gutter|GutterPool": "ditch_water",
        r"DrainCover": "ditch_grate",
    },
    # The graybox road is redrawn around the ditch (street_ditch); its collider stays.
    "hidden": [r"Road/MeshInstance3D", r"(RetractableGate|SideDoor)/MeshInstance3D"],
    "nodes": street_nodes,
}


# --- the courtyard ------------------------------------------------------------------------------


def residential_nodes() -> Builder:
    b = Builder()
    A = "StageArt"
    b.nodes.append(MARKER + "\n")
    distance(b, A, "residential", "residential_distance", -3.0)
    cutouts(b, A, [("RowTower", "row_tower", (-34.0, -30.0), 45, 1.4), ("RowChimney", "row_chimney", (30.0, -44.0), 30, 1.3)], -3.0)
    # Chalk on the courtyard: hopscotch, one square drawn twice.
    b.flat("Hopscotch", A, yard.plane(b, 1.6, 4.4), "hopscotch", (-1.5, 0.004, 3.0), (0, 10, 0))
    # Roofs: water tanks and a leaning aerial, the silhouette every block like this has.
    b.node("Roofs", A)
    tank = b.mesh("CylinderMesh", top_radius="0.9", bottom_radius="0.9", height="1.6", radial_segments="12", rings="1")
    b.flat("TankNorth", f"{A}/Roofs", tank, "tank", (-11.0, 17.8, -23.0), shadow=True)
    b.flat("TankWest", f"{A}/Roofs", tank, "tank", (-17.5, 14.8, 4.0), shadow=True)
    stand = box(b, (2.0, 0.3, 2.0))
    b.flat("TankNorthStand", f"{A}/Roofs", stand, "metal_ink", (-11.0, 17.15, -23.0))
    b.flat("TankWestStand", f"{A}/Roofs", stand, "metal_ink", (-17.5, 14.15, 4.0))
    b.flat("Aerial", f"{A}/Roofs", box(b, (0.07, 4.6, 0.07)), "metal_ink", (-3.0, 19.3, -21.0), (0, 0, 8), shadow=True)
    b.flat("AerialBar", f"{A}/Roofs", box(b, (1.8, 0.05, 0.05)), "metal_ink", (-3.3, 20.8, -21.0), (0, 0, 8), shadow=True)
    # One window that is not on the grid: long, low, lit, between the floors.
    b.flat("StageLongWindow", "BlockNorthWest", yard.quad(b, 3.0, 1.6), "light_beyond", (-0.4, -0.5, 5.006))
    # A visual stepping stone only: the courtyard passage is still the same passage.
    return_plate(b, "BlockNorthWest", "StageAlleyGuide", (8.66, -6.96, 5.006), yaw=0, scale=0.82)
    # The existing bench has a dark replacement slat. One small sweep pile below
    # it makes the other half of the inspection true without dressing the courtyard centre.
    p = f"{A}/BenchSweepings"
    b.node("BenchSweepings", A, position=vec3((-3.27, 0, 6.08)))
    scraps = ((-0.20, 0.008, 0.036, 0.095, -24), (-0.091, -0.025, 0.109, 0.063, 35),
              (0.037, 0.016, 0.146, 0.036, -16), (0.173, -0.061, 0.074, 0.026, 22),
              (-0.008, 0.087, 0.054, 0.022, -33), (0.086, -0.032, 0.037, 0.078, 14))
    for i, (x, z, w, d, yaw) in enumerate(scraps):
        b.flat(f"Scrap{i}", p, box(b, (w, 0.012, d)), "shop_ochre" if i % 3 else "pale",
               (x, 0.007 + i * 0.001, z), (0, yaw, 0))
    return b


RESIDENTIAL = {
    "scene": LOC / "residential" / "residential.tscn",
    "environment": environment(SKY, (0.68, 0.64, 0.72), 1.0, 0.78, 0.003, 1.0),
    "sun": sun(-52, 40, 0.5),
    "by_material": {
        "outdoor_concrete.tres": "court_concrete",
        "outdoor_brick.tres": "housing_yellow",
        "metal_dark.tres": "metal_ink",
        "outdoor_hedge.tres": "hedge",
        "outdoor_asphalt.tres": "street_asphalt",
    },
    "by_path": {
        r"BlockWest/MeshInstance3D": "housing_rose",
        r"BlockEast/MeshInstance3D": "housing_sage",
    },
    "nodes": residential_nodes,
}


# --- the alley ----------------------------------------------------------------------------------


def alley_nodes() -> Builder:
    b = Builder()
    A = "StageArt"
    b.nodes.append(MARKER + "\n")
    distance(b, A, "alley", "alley_distance", -1.5)
    # Behind the west wall, close: cut-out rooftops at the wrong scale for the distance.
    cutouts(b, A, [
        ("RowChimney", "row_chimney", (-13.0, -6.0), 70, 1.2),
        ("RowFlats", "row_flats", (-15.0, 8.0), 75, 1.0),
        ("RowTower", "row_tower", (-12.0, -20.0), 65, 1.5),
    ], -1.5)
    # The west wall goes on up past its coping, leaning out over the lane. Children of the
    # occluder body (2 m up, at x -3.9), so they fade with it; they stop either side of the
    # bay so the bay still reads as an opening.
    # The south run stops 4 m short of the bay: from the bay the camera looks back east
    # over the wall top, and a mesh-only piece has no collider for the fader to hit.
    for name, z0, z1 in (("StageLeanSouth", 15.0, -4.0), ("StageLeanNorth", -16.4, -23.0)):
        length = z0 - z1
        mid = (z0 + z1) / 2
        b.flat(name, "WallWest", box(b, (0.5, 4.0, length)), "alley_wall_high", (0.35, 3.9, mid + 4.0), (0, 0, -8), shadow=True)
    # Past the gate, where the yard is: light, not a view.
    b.flat("GateLight", A, yard.quad(b, 3.0, 3.6), "light_beyond", (0.0, 1.8, -25.0))
    return_plate(b, "WallWest", "StageReturnPlate", (0.257, -0.49, -14.55), reverse=True)
    # A cart guide at the quiet end of the lane. The notch is padded with a shim
    # rather than redrilled. It is part of the wall dressing, not a hidden collision.
    name = "StageTrolleyGuide"
    b.node(name, "WallWest", position=vec3((0.257, -1.26, 9.6)), rotation_degrees=vec3((0, 90, 0)))
    p = "WallWest/" + name
    b.flat("Rail", p, box(b, (1.48, 0.27, 0.12)), "shutter_blue", (0, 0, 0.061), shadow=True)
    b.flat("WearFace", p, box(b, (1.34, 0.124, 0.016)), "school_teal", (0, -0.011, 0.126))
    for i, x in enumerate((-0.43, 0.43)):
        for side in (-1, 1):
            b.flat(f"Stop{i}_{side + 1}", p, box(b, (0.071, 0.25, 0.12)), "metal_ink",
                   (x + side * 0.095, 0.019, 0.16))
    b.flat("WoodShim", p, box(b, (0.109, 0.086, 0.166)), "shop_ochre", (0.412, -0.041, 0.153), (0, 0, -11))
    b.flat("OldScrew", p, box(b, (0.041, 0.041, 0.014)), "metal_ink", (0.572, 0.062, 0.129), (0, 0, 14))
    return b


ALLEY = {
    "scene": LOC / "alley" / "alley.tscn",
    "environment": environment((0.29, 0.29, 0.39), (0.64, 0.64, 0.74), 1.0, 0.76, 0.0, 1.0),
    "sun": sun(-50, 100, 0.55),
    "by_material": {
        "outdoor_brick.tres": "alley_wall",
        "outdoor_concrete.tres": "alley_concrete",
        "outdoor_asphalt.tres": "alley_ground",
        "floor_concrete.tres": "alley_paving",
        "metal_dark.tres": "metal_ink",
        "shutter_metal.tres": "shutter_blue",
    },
    "by_path": {},
    "nodes": alley_nodes,
}

SCENES = {"front_yard": FRONT_YARD, "north_grove": NORTH_GROVE, "street": STREET, "residential": RESIDENTIAL, "alley": ALLEY, "gym": GYM}


# --- scene surgery ------------------------------------------------------------------------------


def blocks_of(text: str) -> tuple[list[str], list[str]]:
    parts = re.split(r"(\n+)(?=\[)", text.rstrip("\n"))
    return parts[0::2], parts[1::2] + ["\n"]


def is_stage_block(block: str) -> bool:
    head = block.split("\n", 1)[0]
    if head == MARKER:
        return True
    if head.startswith("[node"):
        path = node_path(head)
        name = path.rsplit("/", 1)[-1]
        return path.startswith("StageArt/") or name.startswith("Stage") or "/Stage" in path
    if head.startswith("[sub_resource") and re.search(r'id="\w+_art\d+"', head):
        return True
    return head.startswith("[ext_resource") and ('id="art_' in head or 'id="stagemesh_' in head)


def apply(text: str, cfg: dict) -> tuple[str, set[str]]:
    blocks, seps = blocks_of(text)
    ext_files = {}
    for block in blocks:
        m = re.match(r'\[ext_resource [^\]]*path="([^"]+)" id="([^"]+)"\]', block)
        if m:
            ext_files[m.group(2)] = m.group(1).rsplit("/", 1)[-1]
    out: list[tuple[str, str]] = []
    used: set[str] = set()
    for block, sep in zip(blocks, seps):
        if is_stage_block(block):
            continue
        head = block.split("\n", 1)[0]
        if head.startswith('[sub_resource type="Environment"'):
            block = cfg["environment"].rstrip("\n")
        elif head.startswith('[node name="Sun"'):
            block = cfg["sun"].rstrip("\n")
        elif head.startswith("[node"):
            path = node_path(head)
            m = re.search(r'material_override = ExtResource\("([^"]+)"\)', block)
            if m:
                mat = None
                for pattern, name in cfg["by_path"].items():
                    if re.fullmatch(pattern, path):
                        mat = name
                if mat is None:
                    mat = cfg["by_material"].get(ext_files.get(m.group(1), ""))
                if mat is None and m.group(1).startswith("art_"):
                    mat = m.group(1)[4:]
                if mat is not None:
                    block = block.replace(m.group(0), f'material_override = ExtResource("art_{mat}")')
                    used.add(mat)
            if any(re.fullmatch(pattern, path) for pattern in cfg.get("no_shadow", [])) and "cast_shadow" not in block:
                block += "\ncast_shadow = 0"
            # Hidden meshes keep their place (and their body's collider); only the picture goes.
            if any(re.fullmatch(pattern, path) for pattern in cfg.get("hidden", [])) and "visible = false" not in block:
                block += "\nvisible = false"
        out.append((block, sep))
    return "".join(b + s for b, s in out), used


def finish(text: str, used: set[str], b: Builder) -> str:
    for block in b.nodes:
        used.update(re.findall(r'ExtResource\("art_([a-z_]+)"\)', block))
    unknown = sorted(m for m in used if m not in MATERIALS)
    if unknown:
        sys.exit("unknown materials: " + ", ".join(unknown))

    # Drop the shared-material ext_resources nothing refers to any more.
    def keep(match: re.Match) -> str:
        rid = match.group(1)
        return match.group(0) if f'ExtResource("{rid}")' in text else ""

    text = re.sub(r'\[ext_resource type="StandardMaterial3D" path="res://assets/materials/[^"]+" id="([^"]+)"\]\n', keep, text)
    new_ext = "".join(f'[ext_resource type="Material" path="{RES}/materials/{m}.tres" id="art_{m}"]\n' for m in sorted(used))
    new_ext += "".join(f'[ext_resource type="ArrayMesh" path="{RES}/meshes/{m}.tres" id="stagemesh_{m}"]\n'
                       for m in sorted(getattr(b, "stage_meshes", ())))
    first_sub = text.index("\n[sub_resource")
    text = text[: first_sub + 1] + new_ext + "\n" + text[first_sub + 1 :]
    first_node = text.index("\n[node ")
    text = text[: first_node + 1] + "\n".join(b.subs) + "\n" + text[first_node + 1 :]
    text = text.rstrip("\n") + "\n\n" + "\n".join(b.nodes)
    text = re.sub(r"\n{3,}", "\n\n", text)
    steps = len(re.findall(r"^\[(ext|sub)_resource", text, re.M)) + 1
    text = re.sub(r"^\[gd_scene load_steps=\d+", f"[gd_scene load_steps={steps}", text, count=1, flags=re.M)
    return text


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("scenes", nargs="*", help="only these locations (" + ", ".join(SCENES) + ")")
    args = parser.parse_args()
    names = args.scenes or list(SCENES)
    bad = [n for n in names if n not in SCENES]
    if bad:
        sys.exit("unknown locations: " + ", ".join(bad))

    MAT_DIR.mkdir(parents=True, exist_ok=True)
    for name, spec in MATERIALS.items():
        (MAT_DIR / f"{name}.tres").write_text(material_tres(name, spec))
    print(f"wrote {len(MATERIALS)} materials to {MAT_DIR.relative_to(ROOT)}")
    meshes = yard_meshes.write_all([STREET_GATE_Z[1] - STREET_GATE_Z[0] - GATE_HEAD],
                                   [YARD_WALL_X + 0.15 + 11.0, GROVE_RAIL_V_LEN, GROVE_RAIL_H_LEN])
    print(f"wrote {len(meshes)} meshes to {yard_meshes.MESH_DIR.relative_to(ROOT)}")
    for name in names:
        cfg = SCENES[name]
        text, used = apply(cfg["scene"].read_text(), cfg)
        b = cfg["nodes"]()
        text = finish(text, used, b)
        cfg["scene"].write_text(text)
        print(f"dressed {cfg['scene'].relative_to(ROOT)}: {len(b.nodes)} nodes, {len(b.subs)} meshes added")


if __name__ == "__main__":
    main()
