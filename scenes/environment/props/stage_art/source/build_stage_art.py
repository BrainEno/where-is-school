#!/usr/bin/env python3
"""Applies the stage pass to the walkway, street, courtyard and alley: writes the materials
and dresses each scene with visual-only nodes.

    python3 scenes/environment/props/stage_art/source/paint_stage_textures.py   # textures
    python3 tools/build_outdoor_locations.py street residential alley            # graybox
    python3 scenes/environment/props/stage_art/source/build_stage_art.py         # this

The street, courtyard and alley scenes are produced by `tools/build_outdoor_locations.py`
(ground, walls, colliders, interactables, exits, spawns); the walkway
(`scenes/locations/corridor/corridor.tscn`) is hand-authored. This script is a second,
visual-only step on top of either, written the same way as the yard's art pass
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
stripped before the new one is applied, so the hand-authored walkway can be re-dressed.
"""

from __future__ import annotations

import argparse
import math
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
    # the walkway
    "walk_plaster": tiled((206, 198, 174)),
    # Wall decal 16 x 3.1 m: the whole texture once across the quad.
    "walk_wall": {"texture": stex("corridor_wall")},
    "walk_terrazzo": tiled((92, 56, 48), "plaster_tile"),
    "walk_floor": {"texture": stex("corridor_floor")},
    "walk_dado": {"color": (52, 94, 80), "outline": True},
    "walk_door": tiled((66, 104, 128), "metal_tile", 0.5),
    "walk_step": tiled((176, 164, 150), "plaster_tile"),
    "walk_bin": tiled((74, 106, 76), "metal_tile", 0.5),
    "walk_distance": {"texture": stex("distance_corridor"), "unshaded": True},
    "yard_ground": tiled((236, 232, 226), "ground_tile"),
    "yard_court": {"texture": ptex("court_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25)},
    # the street
    "street_asphalt": tiled((118, 110, 136), "plaster_tile"),
    "pavement": tiled((200, 188, 170), "plaster_tile"),
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
    # the courtyard
    "court_concrete": tiled((206, 196, 182), "plaster_tile"),
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
    "alley_ground": tiled((120, 112, 132), "plaster_tile"),
    "alley_paving": tiled((176, 166, 156), "plaster_tile"),
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


# --- the walkway -------------------------------------------------------------------------------


def corridor_nodes() -> Builder:
    b = Builder()
    A = "StageArt"
    b.nodes.append(MARKER + "\n")
    # Under and beyond the walkway: the yard far below, the sky laid flat beneath it.
    distance(b, A, "corridor", "walk_distance", -3.9)
    cutouts(b, A, [("RowFlats", "row_flats", (6.0, -24.0), 30, 1.0), ("RowPylon", "row_pylon", (22.0, -16.0), 45, 0.9)], -3.9)

    # The yard seen from above: a fragment of the court, off the building's grid, and one
    # hoop on a short post - too small for the drop it stands at the bottom of.
    b.node("Yard", A)
    b.flat("CourtFragment", f"{A}/Yard", yard.plane(b, 9.0, 12.0), "yard_court", (8.0, -3.488, -2.5), (0, 14, 0))
    b.flat("HoopPost", f"{A}/Yard", box(b, (0.12, 2.4, 0.12)), "pale", (6.2, -2.3, -6.4), shadow=True)
    b.flat("HoopBoard", f"{A}/Yard", box(b, (0.9, 0.6, 0.06)), "pale", (6.2, -1.0, -6.3), (0, 14, 0), shadow=True)

    # The wall as a painted plane: plaster, pilasters closing up, the wainscot sinking
    # along the walkway. A child of the occluder body, 3 mm proud of its face.
    b.flat("StageWallPaint", "WallBuilding", yard.quad(b, 16.0, 3.1), "walk_wall", (0.103, 0.0, 0.0), (0, 90, 0))
    b.flat("StageEndDado", "WallEndNorth", box(b, (4.36, 0.8, 0.01)), "walk_dado", (0.0, -1.15, 0.106))
    # Above the wall the school goes on: an upper storey set back and leaning a few degrees
    # out over the walkway, its windows shrinking towards the yard door.
    b.flat("StageUpperStorey", "WallBuilding", box(b, (3.0, 3.6, 16.4)), "walk_plaster", (-1.4, 3.35, 0.0), (0, 0, -3), shadow=True)
    up = "WallBuilding/StageUpperStorey"
    b.flat("StageCoping", up, box(b, (3.2, 0.16, 16.6)), "walk_dado", (0.0, 1.86, 0.0), shadow=True)
    z, w, h = 7.4, 1.5, 1.2
    k = 0
    while z - w > -8.8:
        b.flat(f"StageWindow{k}", up, yard.quad(b, w, h), "glass_dusk", (1.506, 0.1 - (1.2 - h) * 0.3, z - w / 2 - (-1.0)), (0, 90, 0))
        z -= w + 0.9 * (w / 1.5)
        w, h = w * 0.86, h * 0.88
        k += 1
    # The yard door made tall: a frame to 3 m, a transom of light from the yard above it.
    b.node("YardDoor", A)
    b.flat("Transom", f"{A}/YardDoor", yard.quad(b, 1.3, 0.8), "light_beyond", (0.0, 2.52, -8.993))
    frame_v = box(b, (0.1, 3.0, 0.06))
    b.flat("FrameWest", f"{A}/YardDoor", frame_v, "walk_dado", (-0.7, 1.5, -8.97))
    b.flat("FrameEast", f"{A}/YardDoor", frame_v, "walk_dado", (0.7, 1.5, -8.97))
    b.flat("FrameHead", f"{A}/YardDoor", box(b, (1.5, 0.1, 0.06)), "walk_dado", (0.0, 2.97, -8.97))
    b.flat("FrameMullion", f"{A}/YardDoor", box(b, (1.3, 0.06, 0.05)), "walk_dado", (0.0, 2.12, -8.97))
    # The terrazzo, its brass strips converging and bunching towards the yard door.
    b.flat("FloorPaint", A, yard.plane(b, 4.4, 16.0), "walk_floor", (0.0, 0.003, -1.0))
    return b


CORRIDOR = {
    "scene": LOC / "corridor" / "corridor.tscn",
    "environment": environment(SKY, COOL, 0.9, 0.72, 0.0, 0.95),
    "sun": sun(-24, 62, 0.6, (1, 0.82, 0.68)),
    "no_shadow": [r"FarBuilding"],
    "by_material": {
        "wall_paint.tres": "walk_plaster",
        "floor_concrete.tres": "walk_step",
        "wall_trim.tres": "walk_dado",
        "door_blue.tres": "walk_door",
        "metal_dark.tres": "metal_ink",
    },
    "by_path": {
        r"Floor/MeshInstance3D": "walk_terrazzo",
        r"YardGround": "yard_ground",
        r"FarBuilding": "school_teal",
        r"BinRow": "walk_bin",
    },
    "nodes": corridor_nodes,
}


# --- the street ---------------------------------------------------------------------------------


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
    # Paint on the road.
    b.node("Road", A)
    b.flat("CentreLine", f"{A}/Road", yard.plane(b, 0.4, 56.0), "road_dash", (-0.6, 0.004, -8.0))
    b.flat("Crossing", f"{A}/Road", yard.plane(b, 18.4, 3.0), "road_zebra", (-0.5, 0.005, 9.5))
    # The school's barred windows, painted on its long wall (a child of the occluder).
    b.flat("StageWindows", "SchoolBlock", yard.quad(b, 44.0, 11.4), "school_windows", (5.006, 0.5, 0.0), (0, 90, 0))
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
        r"SchoolPlinth/MeshInstance3D": "plinth_ivory",
        r"Kerb(East|West)/MeshInstance3D": "kerb",
        r"ShopBlock/MeshInstance3D": "shop_ochre",
    },
    "nodes": street_nodes,
}


# --- the courtyard ------------------------------------------------------------------------------


def residential_nodes() -> Builder:
    b = Builder()
    A = "StageArt"
    b.nodes.append(MARKER + "\n")
    distance(b, A, "residential", "residential_distance", -2.6)
    cutouts(b, A, [("RowTower", "row_tower", (-34.0, -30.0), 45, 1.4), ("RowChimney", "row_chimney", (30.0, -44.0), 30, 1.3)], -2.6)
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

SCENES = {"corridor": CORRIDOR, "street": STREET, "residential": RESIDENTIAL, "alley": ALLEY}


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
    return head.startswith("[ext_resource") and 'id="art_' in head


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
    for name in names:
        cfg = SCENES[name]
        text, used = apply(cfg["scene"].read_text(), cfg)
        b = cfg["nodes"]()
        text = finish(text, used, b)
        cfg["scene"].write_text(text)
        print(f"dressed {cfg['scene'].relative_to(ROOT)}: {len(b.nodes)} nodes, {len(b.subs)} meshes added")


if __name__ == "__main__":
    main()
