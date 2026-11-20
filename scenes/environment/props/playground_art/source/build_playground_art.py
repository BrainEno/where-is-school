#!/usr/bin/env python3
"""Applies the schoolyard's art pass: writes the materials and dresses `playground.tscn`.

    python3 scenes/environment/props/playground_art/source/paint_playground_textures.py
    python3 scenes/environment/props/playground_art/source/build_playground_art.py

`scenes/locations/playground/playground.tscn` is produced by
`tools/build_outdoor_locations.py` (the graybox: ground, walls, colliders, interactables,
exits, spawns). This script is the second, visual-only step on top of that output, so the
two can be rerun in order whenever the graybox changes:

    python3 tools/build_outdoor_locations.py      # rewrites the graybox scene
    python3 scenes/environment/props/playground_art/source/build_playground_art.py

What it does to the scene, and nothing else:

* repoints `material_override` of the graybox meshes to the materials written here
  (`playground_art/materials/*.tres`), so `assets/materials/**` stays untouched;
* hides the seven ruled court-line/key boxes and the four box "tyres", which the painted
  court and the ring tyres replace (mesh-only nodes - no collider is touched);
* lifts `CourtFarHalf` 4 mm so it is no longer buried under `CourtSurface`;
* replaces the Environment resource and retunes `Sun`;
* adds one `PlaygroundArt` subtree of mesh-only nodes (no bodies, no shapes), plus one
  set of wall fittings and decals under the bodies they belong to, so the camera's
  occluder fader fades them together with their wall.

The dressing pass never adds a CollisionObject3D, moves a body, shape, interactable,
exit or spawn. The separate container prefab owns its own shell and ladder.
"""

from __future__ import annotations

import argparse
import math
from functools import lru_cache
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import construction_site
import yard_details

HERE = Path(__file__).resolve().parent
ART = HERE.parent
ROOT = HERE.parents[4]
SCENE = ROOT / "scenes" / "locations" / "playground" / "playground.tscn"
MAT_DIR = ART / "materials"
RES = "res://scenes/environment/props/playground_art"
ART_ROOT = '[node name="PlaygroundArt" type="Node3D"]'
ART_INSTANCE = '[node name="PlaygroundArt" parent="." instance=ExtResource("yard_scenery")]'
SCENERY_FILE = "scenery.scn"
# These overrides belong only to the static yard scenery. Shared wall, prop and
# distant-row colours stay addressable by path; do not ship these ones twice.
SCENERY_MATERIALS = {
    "site_earth", "site_compacted", "hoarding", "hoard_fold", "sand_glare", "sand_wet",
    "cold_water", "water_glint", "slab", "site_yellow", "site_steel", "site_glass",
    "bench_patch", "hoop_patch", "pour_b", "seam", "sky_floor", "fence_far", "tap_runoff",
}


def srgb(c) -> str:
    r, g, b = (round(v / 255.0, 3) for v in c)
    return f"Color({r:g}, {g:g}, {b:g}, 1)"


def vec3(v) -> str:
    return "Vector3(" + ", ".join(f"{round(x, 4):g}" for x in v) + ")"


# --- the yard's colour system (sRGB 0..255); see ../README.md --------------------------
INK = (43, 38, 34)
METAL_INK = (58, 52, 48)
GLASS = (58, 58, 78)
SCHOOL_TEAL = (120, 150, 148)
WALL_FRESH = (130, 162, 158)
IVORY = (220, 208, 180)
SHED_IVORY = (204, 190, 164)
ROOF_PLUM = (104, 78, 90)
DOOR_GREEN = (86, 112, 64)
HEDGE = (58, 80, 56)
CROWN = (76, 102, 66)
TRUNK = (64, 52, 44)
YELLOW = (214, 168, 60)
FIRE_RED = (150, 58, 42)

# Shared fittings for the two faces of the schoolyard exit; leaf paints are local.
SCHOOL_EXIT_MATERIALS = {
    "exit_frame": {"color": (49, 67, 68)},
    "exit_glass": {"color": (82, 111, 120)},
    "exit_steel": {"color": (150, 158, 151)},
}
BRASS = (190, 150, 62)
ESTATE = (128, 104, 116)
DISTANT = (44, 40, 58)
PALE = (226, 216, 190)
BALL = (240, 236, 226)


def tex(name: str) -> str:
    return f"{RES}/textures/{name}.png"


# name -> spec. Keys: color, texture, triplanar ("world"/"local"), scale, offset,
# cut (alpha scissor threshold), cull_off, outline, unshaded, no_shadow (receive).
MATERIALS: dict[str, dict] = {
    # ground and things painted on it
    "ground": {"texture": tex("ground_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25), "outline": True},
    "concrete": {"color": (238, 238, 242), "texture": tex("ground_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25), "outline": True},
    "concrete_patch": {"color": (206, 218, 232), "texture": tex("ground_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25), "outline": True},
    "pour_b": {"texture": tex("pour_b"), "cut": 0.5},
    "seam": {"texture": tex("seam"), "cut": 0.5},
    "court": {"texture": tex("court_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25)},
    "court_far": {"color": (214, 206, 212), "texture": tex("court_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25)},
    "court_line": {"texture": tex("court_line"), "cut": 0.5, "scale": (3.0, 1.0, 1.0)},
    "court_key": {"texture": tex("key_area"), "cut": 0.5},
    "hoop_patch": {"texture": tex("hoop_patch"), "cut": 0.5},
    "bench_patch": {"texture": tex("bench_patch"), "cut": 0.5},
    # the school and the fences
    **SCHOOL_EXIT_MATERIALS,
    "school_wall": {"color": SCHOOL_TEAL, "texture": tex("plaster_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25), "outline": True},
    "wall_patches": {"color": WALL_FRESH, "texture": tex("wall_patches"), "cut": 0.5},
    "plinth": {"color": IVORY, "texture": tex("plaster_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25), "outline": True},
    "glass": {"color": GLASS},
    "metal_ink": {"color": METAL_INK, "outline": True},
    "fire_door": {"color": FIRE_RED, "texture": tex("metal_tile"), "triplanar": "world", "scale": (0.5, 0.5, 0.5), "outline": True},
    # Fence panels: 3 m x 2 m tile; u = x / 3, v = -(y / height) puts the bottom rail on
    # the ground (see the painter's docstring for the triplanar sign conventions).
    "fence_panel": {"texture": tex("fence_panel"), "triplanar": "world", "scale": (1 / 3, 0.5, 1 / 3), "cut": 0.35, "cull_off": True},
    "fence_panel_tall": {"texture": tex("fence_panel"), "triplanar": "world", "scale": (1 / 3, 1 / 2.2, 1 / 3), "cut": 0.35, "cull_off": True},
    # The gap run spans x -19.5..-8.5: u = (x + 19.5) / 11 puts the cut at x = -14.
    "fence_gap": {"texture": tex("fence_gap"), "triplanar": "world", "scale": (1 / 11, 0.5, 1 / 11), "offset": (19.5 / 11, 0.0, 0.0), "cut": 0.35, "cull_off": True},
    # the lit lane seen through the estate gate: unshaded, so it reads as light beyond
    "lane_light": {"color": (232, 172, 112), "unshaded": True},
    "estate": {"color": ESTATE, "texture": tex("plaster_tile"), "triplanar": "world", "scale": (0.2, 0.2, 0.2), "outline": True},
    # equipment
    "hoop_pole": {"color": IVORY, "outline": True},
    "hoop_rim": {"color": YELLOW, "outline": True},
    # Board box 1.8 x 1.1 m: local triplanar maps its face onto the whole texture.
    "backboard": {"texture": tex("backboard"), "triplanar": "local", "scale": (1 / 1.8, 1 / 1.1, 1.0), "offset": (0.5, 0.5, 0.0), "outline": True},
    "hoop_net": {"texture": tex("hoop_net"), "cut": 0.4, "cull_off": True},
    "frame_yellow": {"color": YELLOW, "outline": True},
    "tyre": {"texture": tex("tyre"), "outline": True},
    "notice": {"texture": tex("notice_sheet"), "triplanar": "local", "scale": (1.0, 1 / 1.1, -1 / 1.8), "offset": (0.0, 0.5, 0.5)},
    "container": {"color": (48, 92, 146), "texture": tex("metal_tile"), "triplanar": "local", "scale": (0.58, 0.58, 0.58)},
    "container_rib": {"color": (60, 111, 164), "texture": tex("metal_tile"), "triplanar": "local", "scale": (0.72, 0.72, 0.72)},
    "container_frame": {"color": (51, 71, 97), "texture": tex("metal_tile"), "triplanar": "local", "scale": (0.73, 0.73, 0.73), "outline": True},
    "container_lining": {"color": (136, 145, 143), "texture": tex("metal_tile"), "triplanar": "local", "scale": (0.56, 0.56, 0.56)},
    "container_steel": {"color": (139, 161, 169), "texture": tex("metal_tile"), "triplanar": "local", "scale": (0.9, 0.9, 0.9)},
    "container_deck": {"color": (117, 83, 63), "texture": tex("metal_tile"), "triplanar": "local", "scale": (1.6, 0.8, 0.8)},
    "container_bedding": {"texture": tex("sheet_weave"), "cull_off": True},
    "pale_paper_edge": {"color": (228, 218, 192)},
    "container_blanket": {"texture": tex("blanket_weave"), "cull_off": True},
    "old_newsprint": {"texture": tex("old_newsprint"), "cull_off": True},
    "noodle_film": {"texture": tex("noodle_film"), "roughness": 0.58, "specular": 0},
    "container_oxide": {"color": (118, 75, 58)},
    # the shed corner
    "shed_wall": {"color": SHED_IVORY, "texture": tex("plaster_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25), "outline": True},
    "shed_roof": {"color": ROOF_PLUM, "texture": tex("plaster_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25), "outline": True},
    "door_green": {"color": DOOR_GREEN, "texture": tex("metal_tile"), "triplanar": "world", "scale": (0.5, 0.5, 0.5), "outline": True},
    "brass": {"color": BRASS, "outline": True},
    "shed_clean_paint": {"color": (114, 137, 82)},
    "shed_sign": {"texture": tex("shed_sign")},
    "tap_steel": {"color": (159, 173, 161)},
    "tap_runoff": {"texture": tex("tap_runoff"), "cut": 0.42},
    # Sheet box 0.9 x 0.5 m facing +x.
    "rota": {"texture": tex("rota_sheet"), "triplanar": "local", "scale": (1.0, 2.0, 1 / 0.9), "offset": (0.0, 0.5, 0.5)},
    "hedge": {"color": HEDGE, "texture": tex("foliage_tile"), "triplanar": "world", "scale": (0.5, 0.5, 0.5), "outline": True},
    "crown": {"color": CROWN, "texture": tex("foliage_tile"), "triplanar": "world", "scale": (0.5, 0.5, 0.5), "outline": True},
    "trunk": {"color": TRUNK, "outline": True},
    "pale": {"color": PALE},
    "ball": {"color": BALL},
    # beyond the yard: flat, unlit, a painted drop rather than a place
    "sky_floor": {"texture": tex("sky_floor"), "unshaded": True},
    "row_flats": {"color": DISTANT, "texture": tex("row_flats"), "cut": 0.5, "cull_off": True, "unshaded": True},
    "row_tower": {"color": DISTANT, "texture": tex("row_tower"), "cut": 0.5, "cull_off": True, "unshaded": True},
    "row_chimney": {"color": DISTANT, "texture": tex("row_chimney"), "cut": 0.5, "cull_off": True, "unshaded": True},
    "row_pylon": {"color": DISTANT, "texture": tex("row_pylon"), "cut": 0.5, "cull_off": True, "unshaded": True},
    # The construction plot shares the yard's painted tiles. Lambert shading keeps
    # gradual curvature on sand and concrete instead of a toon step on each ring.
    "site_earth": {"color": (237, 199, 174), "texture": tex("ground_tile"),
                   "triplanar": "world", "scale": (0.40, 0.40, 0.40)},
    "site_compacted": {"color": (194, 168, 146), "texture": tex("ground_tile"),
                       "triplanar": "world", "scale": (0.53, 0.53, 0.53)},
    "hoarding": {"color": (81, 119, 156), "texture": tex("metal_tile"),
                  "triplanar": "world", "scale": (0.60, 0.60, 0.60)},
    "hoard_fold": {"color": (70, 97, 123), "texture": tex("metal_tile"),
                   "triplanar": "world", "scale": (0.60, 0.60, 0.60)},
    "sand_glare": {"color": (239, 216, 173), "texture": tex("plaster_tile"), "diffuse": 1,
                   "triplanar": "world", "scale": (0.78, 0.78, 0.78)},
    "sand_wet": {"color": (130, 105, 80), "texture": tex("plaster_tile"), "diffuse": 1,
                 "triplanar": "world", "scale": (0.92, 0.92, 0.92)},
    "cold_water": {"color": (59, 78, 79), "unshaded": True},
    "water_glint": {"color": (117, 143, 139), "unshaded": True},
    "slab": {"color": (181, 177, 166), "texture": tex("plaster_tile"), "diffuse": 1,
             "triplanar": "world", "scale": (0.33, 0.33, 0.33)},
    "site_yellow": {"color": (218, 163, 69), "texture": tex("metal_tile"), "diffuse": 1,
                    "triplanar": "world", "scale": (0.62, 0.62, 0.62), "roughness": 0.82},
    "site_steel": {"color": (72, 74, 73), "texture": tex("metal_tile"), "diffuse": 1,
                   "triplanar": "world", "scale": (0.77, 0.77, 0.77)},
    "site_glass": {"color": (62, 82, 88), "roughness": 0.7},
    # One panel tile per 3 x 2 m quad so its rails stay put as the fence sinks.
    "fence_far": {"color": (150, 146, 170), "texture": tex("fence_panel"), "cut": 0.35, "cull_off": True, "unshaded": True},
}


def material_tres(name: str, spec: dict) -> str:
    ext = []
    if spec.get("outline"):
        ext.append(f'[ext_resource type="Material" path="{RES}/materials/ink_outline.tres" id="1_ink"]')
    if "texture" in spec:
        ext.append(f'[ext_resource type="Texture2D" path="{spec["texture"]}" id="2_tex"]')
    lines = [f'[gd_resource type="StandardMaterial3D" load_steps={len(ext) + 1} format=3]', ""]
    if ext:
        lines += ext + [""]
    lines += ["[resource]", f'resource_name = "{name}"']
    if spec.get("outline"):
        lines.append('next_pass = ExtResource("1_ink")')
    if "cut" in spec:
        lines += ["transparency = 2", f"alpha_scissor_threshold = {spec['cut']}"]
    if spec.get("cull_off"):
        lines.append("cull_mode = 2")
    if spec.get("unshaded"):
        lines += ["shading_mode = 0", "disable_receive_shadows = true"]
    else:
        lines += [f"diffuse_mode = {spec.get('diffuse', 3)}", f"specular_mode = {spec.get('specular', 2)}"]
    lines.append(f"albedo_color = {srgb(spec.get('color', (255, 255, 255)))}")
    if "texture" in spec:
        lines.append('albedo_texture = ExtResource("2_tex")')
    if not spec.get("unshaded"):
        lines.append(f"roughness = {spec.get('roughness', 1.0)}")
    if "scale" in spec:
        lines.append(f"uv1_scale = {vec3(spec['scale'])}")
    if "offset" in spec:
        lines.append(f"uv1_offset = {vec3(spec['offset'])}")
    if "triplanar" in spec:
        lines.append("uv1_triplanar = true")
        if spec["triplanar"] == "world":
            lines.append("uv1_world_triplanar = true")
    lines.append("texture_filter = 3")
    return "\n".join(lines) + "\n"


OUTLINE_TRES = """[gd_resource type="StandardMaterial3D" format=3]

[resource]
resource_name = "ink_outline"
cull_mode = 1
shading_mode = 0
specular_mode = 2
disable_receive_shadows = true
albedo_color = Color(0.169, 0.149, 0.133, 1)
grow = true
grow_amount = 0.016
"""


# --- graybox node -> material ---------------------------------------------------------------
# Keys are scene paths relative to the root (`parent/name`, or `name` for root children).
REPOINT: list[tuple[str, str]] = [
    (r"YardGround/MeshInstance3D", "ground"),
    (r"CourtSurface", "court"),
    (r"CourtFarHalf", "court_far"),
    (r"CourtLine(South|North|West|East)|CourtCentre", "court_line"),
    (r"Key(Near|Far)", "court_key"),
    (r"SchoolBackWall/MeshInstance3D", "school_wall"),
    (r"SchoolPlinth/MeshInstance3D", "plinth"),
    (r"BackWindow_\d_\d|ShedWindow", "glass"),
    (r"FireDoor", "fire_door"),
    (r"FireStep|HoopFarFooting/MeshInstance3D|ShedFooting(West|East)/MeshInstance3D|ContainerFooting[AB]/MeshInstance3D", "concrete"),
    (r"HoopNearFooting/MeshInstance3D", "concrete_patch"),
    (r"FenceRunNorth", "fence_panel"),
    (r"FenceRunGap", "fence_gap"),
    (r"SouthFence(West|East)/MeshInstance3D", "fence_panel_tall"),
    (r"EstateBlock(South|East)/MeshInstance3D", "estate"),
    (r"SouthGateLight", "lane_light"),
    (r"Hoop(Near|Far)Pole/MeshInstance3D", "hoop_pole"),
    (r"Hoop(Near|Far)Board", "backboard"),
    (r"Hoop(Near|Far)Rim/MeshInstance3D", "hoop_rim"),
    (r"ShedBody/MeshInstance3D", "shed_wall"),
    (r"ShedRoof", "shed_roof"),
    (r"ShedDoor", "door_green"),
    (r"ShedSheet", "rota"),
    (r"ShedHedge", "hedge"),
    (r"PaleUnderHedge", "pale"),
    (r"PingPongBall", "ball"),
    (r"BoardSheet", "notice"),
    (r"FramePost_\d/MeshInstance3D|FrameRung_\d|FrameTopBar", "frame_yellow"),
    (r"TyreStack_\d|TyreLoose", "tyre"),
    # Low-detail version emitted only for build_teaching_block's distant view.
    (r"ContainerBody/MeshInstance3D", "container"),
    (r"ContainerDoorLine", "shutter"),
    (r"ContainerBar", "metal_ink"),
    (r"TreeTrunk/MeshInstance3D", "trunk"),
    (r"TreeCrown", "crown"),
    # The tap sits in the south fence's shadow. The pale fitting separates it from the ground.
    (r"TapPost/MeshInstance3D", "exit_steel"),
    (
        r"BackBars_\d_\d|FencePostGap(West|East)/MeshInstance3D|BoardPost[AB]/MeshInstance3D|BoardBacking"
        r"|FitnessPost_\d/MeshInstance3D|FitnessBar(High|Low)|SitupFrame/MeshInstance3D|SitupFootBar"
        r"|Bird_\d|BirdWire"
        r"|SouthGatePost(West|East)|SouthGateLintel",
        "metal_ink",
    ),
]

# Ruled graybox boxes the painted planes / ring tyres below replace.
HIDE = re.compile(
    r"CourtLine(South|North|West|East)|CourtCentre|Key(Near|Far)|TyreStack_\d|TyreLoose"
    r"|SchoolPlinth/MeshInstance3D|TapPost/MeshInstance3D"
)

ENVIRONMENT = """[sub_resource type="Environment" id="Environment_1"]
background_mode = 1
background_color = Color(0.239, 0.275, 0.361, 1)
ambient_light_source = 2
ambient_light_color = Color(0.66, 0.64, 0.74, 1)
ambient_light_energy = 0.8
tonemap_mode = 2
tonemap_exposure = 0.62
fog_enabled = true
fog_light_color = Color(0.32, 0.3, 0.38, 1)
fog_density = 0.003
adjustment_enabled = true
adjustment_saturation = 0.98
adjustment_contrast = 1.04
"""

SUN = """[node name="Sun" type="DirectionalLight3D" parent="."]
rotation_degrees = Vector3(-20, 32, 0)
light_color = Color(1, 0.8, 0.62, 1)
light_energy = 0.2
shadow_enabled = true
directional_shadow_max_distance = 90.0
"""


# --- the added nodes --------------------------------------------------------------------------


class Builder:
    def __init__(self) -> None:
        self.subs: list[str] = []
        self.nodes: list[str] = []
        self.imported_meshes: set[str] = set()
        self.n = 0

    def mesh(self, kind: str, **props) -> str:
        self.n += 1
        sid = f"{kind}_art{self.n}"
        body = [f'[sub_resource type="{kind}" id="{sid}"]']
        for k, v in props.items():
            body.append(f"{k} = {v}")
        self.subs.append("\n".join(body) + "\n")
        return sid

    def node(self, name: str, parent: str, type_: str = "Node3D", **props) -> None:
        body = [f'[node name="{name}" type="{type_}" parent="{parent}"]']
        for k, v in props.items():
            body.append(f"{k} = {v}")
        self.nodes.append("\n".join(body) + "\n")

    def flat(self, name: str, parent: str, mesh_id: str, mat: str, pos, rot=None,
             shadow: bool = False, *, imported: bool = False) -> None:
        props = {"position": vec3(pos)}
        if rot is not None:
            props["rotation_degrees"] = vec3(rot)
        if imported:
            self.imported_meshes.add(mesh_id)
            props["mesh"] = f'ExtResource("mesh_{mesh_id}")'
        else:
            props["mesh"] = f'SubResource("{mesh_id}")'
        props["material_override"] = f'ExtResource("art_{mat}")'
        if not shadow:
            props["cast_shadow"] = "0"
        self.node(name, parent, "MeshInstance3D", **props)

    def mesh_resources(self, extension: str = "mesh") -> list[str]:
        return [f'[ext_resource type="Mesh" path="{RES}/meshes/{name}.{extension}" id="mesh_{name}"]'
                for name in sorted(self.imported_meshes)]


def dressed_materials(b: Builder) -> set[str]:
    return {name for block in b.nodes for name in re.findall(r'ExtResource\("art_([a-z_]+)"\)', block)}


def material_resources(used: set[str]) -> list[str]:
    return [f'[ext_resource type="Material" path="{RES}/materials/{name}.tres" id="art_{name}"]'
            for name in sorted(used)]

def plane(b: Builder, w: float, d: float) -> str:
    return b.mesh("PlaneMesh", size=f"Vector2({w:g}, {d:g})")


def quad(b: Builder, w: float, h: float) -> str:
    return b.mesh("QuadMesh", size=f"Vector2({w:g}, {h:g})")


def school_exit_fittings(b: Builder, parent: str, width: float, height: float, face_z: float,
                         *, inside: bool) -> None:
    """Dress a closed leaf centred at the local origin, seen from +Z. Keep the leaf/step
    as the two outlined meshes. A recessed pane, steel shoes and a frame follow the
    same construction on both sides; an interior push bar becomes an exterior handle.
    """
    def piece(name, size, material, x, y, z):
        mesh = b.mesh("BoxMesh", size=vec3(size))
        b.flat(name, parent, mesh, material, (x, y, z))

    jamb = 0.09
    half_w, half_h = width / 2, height / 2
    for side, sign in (("Left", -1), ("Right", 1)):
        piece("Jamb" + side, (jamb, height - 0.04, 0.20), "exit_frame",
              sign * (half_w + jamb / 2 - 0.015), -0.02, face_z - 0.058)
    piece("Head", (width + 0.15, 0.08, 0.20), "exit_frame", 0, half_h, face_z - 0.058)

    window_y = height * 0.25
    piece("GlazingBead", (0.49, 0.61, 0.028), "exit_frame", 0, window_y, face_z + 0.013)
    piece("VisionLight", (0.40, 0.52, 0.012), "exit_glass", 0, window_y, face_z + 0.028)
    piece("VisionRail", (0.40, 0.025, 0.020), "exit_frame", 0, window_y + 0.11, face_z + 0.037)
    piece("KickPlate", (width - 0.22, 0.18, 0.018), "exit_steel", 0, -half_h + 0.32, face_z + 0.011)
    if inside:
        for side, sign in (("Left", -1), ("Right", 1)):
            piece("BarMount" + side, (0.115, 0.118, 0.055), "exit_frame",
                  sign * width * 0.32, -0.045, face_z + 0.030)
        piece("PushBar", (width * 0.72, 0.055, 0.042), "exit_steel", 0, -0.045, face_z + 0.066)
    else:
        latch_x = width * 0.31
        piece("PullPlate", (0.115, 0.34, 0.027), "exit_frame", latch_x, -0.19, face_z + 0.0135)
        for end, y in (("Top", -0.09), ("Bottom", -0.29)):
            piece("PullMount" + end, (0.062, 0.055, 0.066), "exit_steel", latch_x, y, face_z + 0.047)
        piece("PullHandle", (0.045, 0.255, 0.035), "exit_steel", latch_x, -0.19, face_z + 0.082)


def school_plinth_returns(b: Builder, parent: str, *, material_prefix: str = "") -> None:
    """Leave the opening around the fire door clear on both views of the yard."""
    for name, low, high in (("PlinthWest", -23, -3.775), ("PlinthEast", -2.225, 23)):
        mesh = b.mesh("BoxMesh", size=vec3((high - low, 1.2, 0.4)))
        b.flat(name, parent, mesh, material_prefix + "plinth", ((low + high) / 2, 0, 0), shadow=True)


def court_landmarks(b: Builder, parent: str, *, material_prefix: str = "") -> None:
    """The painted court and hoops are also seen out of the teaching block."""
    def flat(name, parent, mesh_id, mat, pos, rot=None, shadow=False):
        b.flat(name, parent, mesh_id, material_prefix + mat, pos, rot, shadow=shadow)

    # The court, repainted by hand on the graybox's lines.
    b.node("Court", parent)
    long_x = plane(b, 22.24, 0.24)
    long_z = plane(b, 26.24, 0.24)
    flat("LineSouth", f"{parent}/Court", long_x, "court_line", (0, 0.022, 11))
    flat("LineNorth", f"{parent}/Court", long_x, "court_line", (0.06, 0.022, -15), (0, 180, 0))
    flat("LineCentre", f"{parent}/Court", long_x, "court_line", (-0.04, 0.022, -2))
    flat("LineWest", f"{parent}/Court", long_z, "court_line", (-11, 0.022, -2), (0, 90, 0))
    flat("LineEast", f"{parent}/Court", long_z, "court_line", (11, 0.022, -1.95), (0, -90, 0))
    key = plane(b, 5.0, 3.2)
    flat("KeyNear", f"{parent}/Court", key, "court_key", (0, 0.02, 7.2))
    flat("KeyFar", f"{parent}/Court", key, "court_key", (0, 0.02, -11.2), (0, 180, 0))

    # The same boards, rings and painted boundaries read from inside the school.
    b.node("Equipment", parent)
    rim = b.mesh("TorusMesh", inner_radius="0.2", outer_radius="0.235", rings="24", ring_segments="6")
    flat("HoopNearRing", f"{parent}/Equipment", rim, "hoop_rim", (-8.0, 2.6, 6.98), shadow=True)
    flat("HoopFarRing", f"{parent}/Equipment", rim, "hoop_rim", (8.0, 2.6, -12.02), shadow=True)
    net = b.mesh("CylinderMesh", top_radius="0.215", bottom_radius="0.15", height="0.42", radial_segments="16", rings="1", cap_top="false", cap_bottom="false")
    flat("HoopFarNet", f"{parent}/Equipment", net, "hoop_net", (8.0, 2.39, -12.02))


def route_mark(b: Builder, parent: str, name: str, center, mat: str, *, mirrored=False, scale=1.0) -> None:
    """One long stroke, two short strokes at the same end. Local +Z is the printed face."""
    x, y, z = center
    sign = -1 if mirrored else 1
    for i, (dx, dy, width, height) in enumerate(((0, 0.075, 0.46, 0.055),
                                                 (0.075, -0.022, 0.045, 0.15),
                                                 (0.181, -0.001, 0.052, 0.11))):
        b.flat(f"{name}Stroke{i}", parent, b.mesh("BoxMesh", size=vec3((width * scale, height * scale, 0.006))),
               mat, (x + sign * dx * scale, y + dy * scale, z + (0.002 if i else 0)))


def route_arrow(b: Builder, parent: str, name: str, center, mat: str, *, direction=1, scale=1.0) -> None:
    x, y, z = center
    b.flat(name + "Shaft", parent, b.mesh("BoxMesh", size=vec3((0.41 * scale, 0.038 * scale, 0.006))),
           mat, (x, y, z))
    for index, side in enumerate((-1, 1)):
        b.flat(f"{name}Head{index}", parent, b.mesh("BoxMesh", size=vec3((0.15 * scale, 0.035 * scale, 0.006))),
               mat, (x + direction * 0.173 * scale, y + side * 0.044 * scale, z + 0.004 + 0.001 * index),
               (0, 0, -side * direction * 40))


def _return_board(b: Builder, parent: str) -> None:
    # A low, pitched reading surface: the two faces stay below the player's waist,
    # so neither hides the capsule in the follow camera. Keep the old post spacing,
    # solids and approach from the bench. Both faces point at the real gates.
    post = b.mesh("BoxMesh", size=vec3((0.12, 0.86, 0.12)))
    for name in ("BoardPostA", "BoardPostB"):
        b.flat("ReturnBoardSupport", name, post, "metal_ink", (0, -0.87, 0), shadow=True)
    for i, (width, y) in enumerate(((0.56, 0.32), (0.14, 0.80))):
        rail = b.mesh("BoxMesh", size=vec3((width, 0.064, 2.46)))
        b.flat(f"ReturnBoardRail{i}", parent, rail, "exit_frame", (14, y, 3.2))
    for side, sign in (("East", 1), ("West", -1)):
        name = "ReturnBoard" + side
        b.node(name, parent, position=vec3((14.0 + sign * 0.15, 0.56, 3.2)),
               rotation_degrees=vec3((-33, sign * 90, 0)), scale=vec3((1.0, 0.42, 1.0)))
        p = f"{parent}/{name}"

        def box(part, pos, size, mat, rot=None):
            b.flat(part, p, b.mesh("BoxMesh", size=vec3(size)), mat, pos, rot)

        box("Case", (0, 0, 0), (1.92, 1.16, 0.10), "exit_frame")
        box("Lip", (0, 0.545, 0.065), (1.99, 0.10, 0.19), "exit_steel")
        box("Paper", (-0.015, 0.145, 0.065), (1.72, 0.72, 0.018), "pale")
        box("BackingStrip", (0.065, -0.31, 0.064), (1.50, 0.28, 0.017), "container_steel", (0, 0, -2))
        box("Rail", (0, -0.49, 0.069), (1.78, 0.075, 0.11), "container_oxide")
        box("UpperRule", (-0.02, 0.26, 0.081), (1.58, 0.025, 0.008), "exit_frame")
        route_mark(b, p, "Header", (0.04, 0.382, 0.085), "exit_frame", scale=0.85)
        route_arrow(b, p, "ToStairs", (sign * 0.49, 0.025, 0.087), "fire_door", direction=sign)
        route_arrow(b, p, "ToEstateGate", (-sign * 0.49, 0.025, 0.087), "exit_frame", direction=-sign)
        # Real pictograms; the fold and the strip aren't decorative pseudo-writing.
        for i in range(3):
            box(f"Stair{i}", (sign * (0.073 + i * 0.05), 0.005 + i * 0.04, 0.087),
                (0.063, 0.041, 0.012), "fire_door")
        for i in (-1, 1):
            box(f"GatePost{i + 1}", (-sign * 0.15 + i * 0.063, 0.05, 0.087),
                (0.026, 0.123, 0.012), "exit_frame")
        box("GateLintel", (-sign * 0.15, 0.119, 0.087), (0.153, 0.023, 0.012), "exit_frame")
        route_mark(b, p, "OldStamp", (-0.44, -0.316, 0.087), "exit_frame", mirrored=True, scale=0.74)
        box("Fold", (0.72, -0.249, 0.085), (0.175, 0.105, 0.014), "container_bedding", (0, 0, -17))
        for i, x in enumerate((-0.77, 0.74)):
            box(f"PaperClip{i}", (x, 0.425, 0.093), (0.053, 0.108, 0.035), "brass", (0, 0, -6 + 10 * i))


def _yard_return_details(b: Builder, parent: str) -> None:
    _return_board(b, parent)
    # The clipped copy against the old duty sheet can be compared from the shed door.
    b.node("ShedReturnCopy", "ShedBody", position=vec3((3.151, 0.295, -2.15)),
           rotation_degrees=vec3((0, 90, 0)))
    p = "ShedBody/ShedReturnCopy"
    b.flat("Strip", p, b.mesh("BoxMesh", size=vec3((0.48, 0.198, 0.009))), "pale", (0, 0, 0), (0, 0, -7))
    route_mark(b, p, "BackStamp", (0.038, 0.009, 0.013), "exit_frame", mirrored=True, scale=0.62)
    b.flat("RoundPunch", p, b.mesh("CylinderMesh", top_radius="0.021", bottom_radius="0.021", height="0.004",
                                  radial_segments="12"), "metal_ink", (0.187, 0.036, 0.013), (90, 0, 0))
    b.flat("SlottedPunch", p, b.mesh("BoxMesh", size=vec3((0.027, 0.067, 0.004))), "metal_ink", (0.184, -0.037, 0.013))
    b.flat("Crease", p, b.mesh("BoxMesh", size=vec3((0.073, 0.015, 0.007))), "pale_paper_edge",
           (0.180, -0.040, 0.018), (0, 0, 29))

    # A low marking kit parked off the court at the shed's edge, not a new obstacle.
    b.node("ChalkGuide", parent, position=vec3((-12.7, 0.005, -9.6)), rotation_degrees=vec3((0, 18, 0)))
    p = f"{parent}/ChalkGuide"
    b.flat("Foot", p, b.mesh("BoxMesh", size=vec3((1.18, 0.074, 0.76))), "plinth", (0, 0.037, 0))
    b.flat("Caddy", p, b.mesh("BoxMesh", size=vec3((0.88, 0.155, 0.42))), "door_green", (-0.05, 0.1515, 0.025), shadow=True)
    b.flat("Offcut", p, b.mesh("BoxMesh", size=vec3((0.81, 0.018, 0.38))), "pale", (0.01, 0.238, 0.02), (0, -8, 0))
    b.flat("Guide", p, b.mesh("BoxMesh", size=vec3((0.70, 0.039, 0.21))), "exit_steel", (0, 0.269, 0.044))
    reel = b.mesh("CylinderMesh", top_radius="0.125", bottom_radius="0.125", height="0.059", radial_segments="14")
    b.flat("CordReel", p, reel, "container_oxide", (-0.19, 0.318, 0.031))
    b.flat("RoundPunch", p, b.mesh("CylinderMesh", top_radius="0.034", bottom_radius="0.034", height="0.007",
                                  radial_segments="12"), "metal_ink", (0.165, 0.291, 0.044))
    b.flat("SlottedPunch", p, b.mesh("BoxMesh", size=vec3((0.045, 0.007, 0.103))), "metal_ink", (0.278, 0.291, 0.044))
    # The exposed end of the offcut is ruled by the two chalk rubbings, not a second prop.
    rub = b.mesh("CylinderMesh", top_radius="0.032", bottom_radius="0.032", height="0.004", radial_segments="12")
    b.flat("RoundRubbing", p, rub, "concrete_patch", (0.147, 0.249, 0.173))
    b.flat("SlotRubbing", p, b.mesh("BoxMesh", size=vec3((0.086, 0.004, 0.038))), "concrete_patch", (0.264, 0.249, 0.181))


def build_nodes() -> Builder:
    b = Builder()
    A = "PlaygroundArt"
    b.node(A, ".")

    # Beyond the yard. The camera looks down at ~53 degrees from the south-east, so past the
    # open west edge it sees *below* the horizon: the sky is laid flat under the stage, and
    # a few cut-out ground rows stand on it. Unlit, no shadows, far from every walkable
    # cell (west of x = -27, which the camera never looks back through).
    b.node("Distance", A)
    b.flat("SkyFloor", f"{A}/Distance", plane(b, 240, 240), "sky_floor", (0, -1.2, 0))
    rows = [
        ("RowFlats", "row_flats", (13.0, 5.4), (-31.0, -12.0)),
        ("RowTower", "row_tower", (9.0, 3.75), (-29.5, 3.0)),
        ("RowChimney", "row_chimney", (11.0, 4.6), (-36.0, -26.0)),
        # Moved out from behind the construction plot (x -35..-23, z 7..19.6).
        ("RowPylon", "row_pylon", (10.0, 4.2), (-42.0, 21.0)),
    ]
    for name, mat, (w, h), (x, z) in rows:
        b.flat(name, f"{A}/Distance", quad(b, w, h), mat, (x, -1.2 + h / 2, z), (0, 45, 0))
    # The north fence does not stop where the yard does: past the open west edge a run of
    # panels goes on along its line, each a little lower, until the last one is wading in
    # the sky. A boundary that is not continuous and not finished.
    panel = quad(b, 3.0, 2.0)
    for i in range(4):
        b.flat(f"FenceRun_{i}", f"{A}/Distance", panel, "fence_far", (-27.5 - i * 3.1, 1.0 - i * 0.55, -18.6 + i * 0.25), (0, 4.0 * i, 0))
    # A floodlight mast at the wrong scale: twenty metres of pole standing in the laid-flat
    # sky, its lamp lit, lighting nothing anyone plays on.
    b.flat("Mast", f"{A}/Distance", b.mesh("BoxMesh", size=vec3((0.3, 20.0, 0.3))), "metal_ink", (-44.0, 8.8, -6.0))
    b.flat("MastHead", f"{A}/Distance", b.mesh("BoxMesh", size=vec3((2.6, 0.7, 1.0))), "metal_ink", (-44.0, 18.9, -6.0), (0, 45, 0))
    b.flat("MastLamp", f"{A}/Distance", b.mesh("BoxMesh", size=vec3((2.2, 0.08, 0.7))), "lane_light", (-44.0, 18.52, -6.0), (0, 45, 0))
    # One chair out there, facing the yard, as if someone had carried it out to wait.
    chair = f"{A}/Distance/Chair"
    b.node("Chair", f"{A}/Distance", position=vec3((-30.5, -1.2, 5.0)), rotation_degrees=vec3((0, 70, 0)))
    b.flat("Seat", chair, b.mesh("BoxMesh", size=vec3((0.46, 0.04, 0.42))), "pale", (0.0, 0.45, 0.0))
    b.flat("Back", chair, b.mesh("BoxMesh", size=vec3((0.46, 0.34, 0.03))), "pale", (0.0, 0.74, -0.2))
    leg = b.mesh("BoxMesh", size=vec3((0.03, 0.45, 0.03)))
    for i, (lx, lz) in enumerate(((-0.2, -0.18), (0.2, -0.18), (-0.2, 0.18), (0.2, 0.18))):
        b.flat(f"Leg_{i}", chair, leg, "metal_ink", (lx, 0.225, lz))
    b.flat("BackPostL", chair, b.mesh("BoxMesh", size=vec3((0.03, 0.5, 0.03))), "metal_ink", (-0.2, 0.7, -0.19))
    b.flat("BackPostR", chair, b.mesh("BoxMesh", size=vec3((0.03, 0.5, 0.03))), "metal_ink", (0.2, 0.7, -0.19))

    # The ground: the newer pour east of the seam, the seam itself (over the court paint,
    # too), the newer concrete round the near hoop, the colour block under bench and bag.
    b.node("Ground", A)
    b.flat("PourB", f"{A}/Ground", plane(b, 20.5, 40.0), "pour_b", (12.75, 0.003, 0.0))
    b.flat("HoopNearPatch", f"{A}/Ground", plane(b, 2.8, 2.4), "hoop_patch", (-8.0, 0.006, 7.5))
    b.flat("BenchPatch", f"{A}/Ground", plane(b, 3.6, 3.0), "bench_patch", (11.0, 0.006, 3.2), (0, 90, 0))
    b.flat("Seam", f"{A}/Ground", plane(b, 20.5, 40.0), "seam", (12.75, 0.024, 0.0))

    court_landmarks(b, A)
    tyre = b.mesh("TorusMesh", inner_radius="0.27", outer_radius="0.5", rings="24", ring_segments="10")
    for i, y in enumerate((0.12, 0.36, 0.6)):
        b.flat(f"Tyre_{i}", f"{A}/Equipment", tyre, "tyre", (-15.2 + (0.05 if i == 1 else 0.0), y, 2.6 - (0.04 if i == 2 else 0.0)), (0, 20 * i, 0), shadow=True)
    b.flat("TyreLoose", f"{A}/Equipment", tyre, "tyre", (-14.1, 0.14, 3.5), (6, 0, 0), shadow=True)
    yard_details.shed(b)
    yard_details.tap(b, A)

    # Decals on the occluder bodies: children of the body, so they fade with it.
    b.flat("WallPatches", "SchoolBackWall", quad(b, 6.0, 2.4), "wall_patches", (4.0, -3.0, 1.006))

    # The plinth returns into the jambs instead of passing through the bottom half
    # of the door. Only the mesh is replaced; the plinth keeps its full-width collider.
    school_plinth_returns(b, "SchoolPlinth")
    # Separate art sibling: FireDoor and FireStep retain their original pick boxes.
    b.node("DoorFittings", A, position=vec3((-3, 1.3, -19.9)))
    school_exit_fittings(b, f"{A}/DoorFittings", 1.4, 2.6, 0.07, inside=False)
    _yard_return_details(b, A)
    construction_site.build(b, A)
    return b


# --- scene surgery ----------------------------------------------------------------------------


def build_container() -> tuple[str, set[str]]:
    """Hollow 6 × 2.4 m shipping container. Everything is authored in prop space:
    five structural plates, opening hardware, improvised bedding, and a climbable steel ladder.
    Only the shell, open leaves and entry plate are solid. The corrugation, grips and
    bedding don't add little obstacles to the schoolyard bake.
    """
    b = Builder()

    @lru_cache(maxsize=None)
    def box_mesh(size):
        return b.mesh("BoxMesh", size=vec3(size))

    def box(name, size, where, mat, parent=".", rot=None, shadow=True):
        b.flat(name, parent, box_mesh(size), mat, where, rot, shadow=shadow)

    def shape(name, size, where, rot=None):
        props = {"position": vec3(where), "shape": f'SubResource("{b.mesh("BoxShape3D", size=vec3(size))}")'}
        if rot is not None:
            props["rotation_degrees"] = vec3(rot)
        b.node(name, ".", "CollisionShape3D", **props)

    def plate(name, size, where, mat, rot=None):
        box(name, size, where, mat, rot=rot)
        shape(name + "Collision", size, where, rot)

    plate("Roof", (6.0, 0.10, 2.40), (0, 2.55, 0), "container")
    plate("Deck", (6.0, 0.22, 2.40), (0, 0.11, 0), "container_deck")
    plate("Rear", (0.12, 2.32, 2.40), (-2.94, 1.34, 0), "container")
    for name, side in (("South", 1), ("North", -1)):
        plate("Side" + name, (5.76, 2.32, 0.08), (0, 1.34, side * 1.13), "container")
        box("Lining" + name, (5.68, 2.26, 0.018), (0, 1.37, side * 1.076), "container_lining")
        for n in range(19):
            # Raised folded web and its narrow crown; dark channels are the real panel.
            x = -2.57 + 0.285 * n
            box(f"Web{name}{n:02}", (0.154, 2.06, 0.042), (x, 1.34, side * 1.177), "container", shadow=False)
            box(f"Crown{name}{n:02}", (0.113, 2.06, 0.032), (x, 1.34, side * 1.199), "container_rib", shadow=False)
        for end, x in (("Rear", -2.89), ("End", 2.89)):
            box(f"{end}Post{name}", (0.21, 2.31, 0.15), (x, 1.34, side * 1.125), "container_frame")
            for y, key in ((0.11, "Foot"), (2.49, "Cap")):
                box(f"{end}{key}{name}", (0.22, 0.18, 0.19), (x, y, side * 1.126), "container_frame")
                box(f"{end}{key}{name}Socket", (0.108, 0.070, 0.010), (x, y, side * 1.228), "metal_ink")
        for y, key in ((0.23, "Sill"), (2.45, "TopRail")):
            box(key + name, (5.65, 0.134, 0.130), (0, y, side * 1.147), "container_frame")
    for n in range(18):
        box(f"RoofFold{n:02}", (0.128, 0.023, 2.21), (-2.50 + n * 0.294, 2.600, 0),
            "container_rib", shadow=False)
    box("EndHeader", (0.17, 0.165, 2.16), (2.91, 2.432, 0), "container_frame")
    box("EndSill", (0.18, 0.097, 2.16), (2.91, 0.165, 0), "container_frame")
    # A scuffed steel threshold plate slopes from the deck to the yard. No hidden
    # face blocking the door; the real player can walk to the cot.
    plate("Threshold", (0.669, 0.043, 1.74), (3.268, 0.098, 0), "container_steel", (0, 0, -18))
    for z in (-0.79, -0.49, -0.19, 0.11, 0.41, 0.71):
        box(f"DeckSeam{round((z + 0.79) * 100):03}", (5.72, 0.003, 0.009), (0.01, 0.221, z), "container_oxide", shadow=False)

    for side, z, angle in (("South", 1.16, -171), ("North", -1.16, 58)):
        parent = "Door" + side
        b.node(parent, ".", position=vec3((2.96, 0, z)), rotation_degrees=vec3((0, angle, 0)))
        # The near leaf is latched back, the far leaf stays part open. The dark gasket,
        # hinges, keeper shoes, lock rods and two levers are on the leaves, not decals.
        box("Panel", (1.08, 2.13, 0.065), (0.55, 1.32, 0), "container", parent)
        theta = math.radians(angle)
        shape(parent + "Collision", (1.08, 2.13, 0.067),
              (2.96 + 0.55 * math.cos(theta), 1.32, z - 0.55 * math.sin(theta)), (0, angle, 0))
        for j in range(4):
            box(f"Pressing{j}", (0.14, 1.90, 0.028), (0.185 + 0.238 * j, 1.32, 0.035),
                "container_rib", parent, shadow=False)
        for x, name in ((0.057, "HingeRail"), (1.078, "LockEdge")):
            box(name, (0.043, 2.19, 0.085), (x, 1.32, 0.001), "container_frame", parent)
        for k, y in enumerate((0.33, 1.01, 1.64, 2.25)):
            box(f"Hinge{k}", (0.136, 0.080, 0.105), (0.038, y, 0.025), "container_steel", parent)
        for idx, x in enumerate((0.29, 0.83)):
            box(f"LockRod{idx}", (0.033, 2.08, 0.042), (x, 1.32, 0.067), "container_steel", parent)
            for key, y in (("Lower", 0.54), ("Upper", 2.10)):
                box(f"Keeper{idx}{key}", (0.112, 0.047, 0.049), (x, y, 0.073), "metal_ink", parent)
            box(f"Lever{idx}", (0.26, 0.038, 0.041), (x + 0.12, 0.99, 0.103),
                "container_steel", parent, (0, 0, 8))
    # Faded inspection plate and lower oxidation, concentrated at hardware/edges.
    box("DataPlate", (0.48, 0.29, 0.019), (-1.84, 1.88, 1.225), "container_frame")
    b.node("Stencil", ".", "Label3D", position=vec3((-1.84, 1.89, 1.239)),
           text='"SU  214\n22G1"'.replace('\n', '\\n'), font_size=28, outline_size=0,
           pixel_size=0.0034, modulate="Color(0.89, 0.83, 0.68, 1)")
    for n, (x, w) in enumerate(((-2.74, 0.29), (-1.63, 0.17), (0.47, 0.12), (2.75, 0.23))):
        box(f"WornSill{n}", (w, 0.035, 0.010), (x, 0.254, 1.215), "container_oxide", shadow=False)

    yard_details.cabin(b)
    b.node("DoorLight", "Cabin", "OmniLight3D", position=vec3((1.98, 1.65, 0.10)),
           light_color="Color(1, 0.84, 0.68, 1)", light_energy=0.92, omni_range=2.64, omni_attenuation=1.12)

    ladder_x, rung_z, trace_z = 1.39, 1.48, 1.76
    # A small patch of warm, reflected yard light picks out the near rails and the
    # actor on the blue roof without changing the lighting of the surrounding routes.
    b.node("LandingFill", ".", "OmniLight3D", position=vec3((1.10, 4.40, 2.55)),
           light_color="Color(1, 0.86, 0.72, 1)", light_energy=0.95, omni_range=5.2, omni_attenuation=1.2)
    b.node("Ladder", ".")
    for key, side in (("Left", -1), ("Right", 1)):
        rail = b.mesh("CylinderMesh", top_radius=0.033, bottom_radius=0.033, height=3.52, radial_segments=10)
        x = ladder_x + side * 0.38
        b.flat("SteelRail" + key, "Ladder", rail, "container_steel", (x, 1.80, rung_z), shadow=True)
        for j, y in enumerate((0.24, 1.26, 2.39)):
            box(f"Stay{key}{j}", (0.082, 0.063, 0.32), (x, y, 1.328), "container_frame", "Ladder")
        grip = b.mesh("CylinderMesh", top_radius=0.033, bottom_radius=0.033, height=0.30, radial_segments=10)
        b.flat("Grab" + key, "Ladder", grip, "container_steel", (x, 3.48, 1.355), (-90, 0, 0), shadow=True)
    tf = b.mesh("CylinderMesh", top_radius=0.021, bottom_radius=0.021, height=0.76, radial_segments=10)
    b.node("Steps", "Ladder")
    b.node("RoofMark", "Ladder", "Marker3D", position=vec3((ladder_x, 2.60, 0.82)))
    b.node("GroundMark", "Ladder", "Marker3D", position=vec3((ladder_x + 0.14, 0.014, 2.02)))
    for rung in range(8):
        y = round(2.35 - rung * 0.30, 2)
        b.flat(f"Rung{rung}", "Ladder", tf, "container_steel", (ladder_x, y, rung_z), (0, 0, 90), shadow=True)
        b.node(f"Step{rung}", "Ladder/Steps", "Marker3D", position=vec3((ladder_x, y + 0.022, trace_z)))
    ext = [
        '[ext_resource type="Script" path="res://scenes/locations/playground/container_ladder.gd" id="ladder"]',
        '[ext_resource type="PackedScene" path="res://scenes/interaction/interactable.tscn" id="interactable"]',
        '[ext_resource type="Script" path="res://scripts/interaction/staged_interactable.gd" id="staged"]',
        '[ext_resource type="Resource" path="res://assets/camera/shots/container_ladder.tres" id="shot"]',
    ]
    used = dressed_materials(b)
    ext += material_resources(used) + b.mesh_resources()
    root = '[node name="ContainerBody" type="StaticBody3D" groups=["camera_occluder"]]\nscript = ExtResource("ladder")'
    use = f'''[node name="LadderUse" parent="." instance=ExtResource("interactable")]
script = ExtResource("staged")
position = {vec3((ladder_x, 3.35, 1.30))}
interact_id = &"pg_container_ladder"
prompt_text = "Climb down the steel ladder"
prompt_key = "prompt.container_ladder_down"
radius = 0.45
camera_shot = ExtResource("shot")
outline_paths = PackedStringArray("../Ladder/GrabLeft", "../Ladder/GrabRight")
support_paths = PackedStringArray("..")
'''
    scene = [f'[gd_scene load_steps={len(ext) + len(b.subs) + 1} format=3]\n', '\n'.join(ext) + '\n']
    return '\n'.join(scene + b.subs + [root + '\n'] + b.nodes + [use]), used


def build_noodle_wrapper() -> str:
    b = Builder()
    b.flat("Film", ".", "noodle_wrapper", "noodle_film", (0, 0, 0), imported=True)
    ext = material_resources(dressed_materials(b)) + b.mesh_resources()
    return "\n".join([f"[gd_scene load_steps={len(ext) + 1} format=3]\n", *ext, "",
                      '[node name="NoodleWrapper" type="Node3D"]\n', *b.nodes])


def node_path(head: str) -> str:
    name = re.search(r'name="([^"]+)"', head).group(1)
    parent = re.search(r'parent="([^"]+)"', head)
    if parent is None:
        return ""
    return name if parent.group(1) == "." else f"{parent.group(1)}/{name}"


def material_for(path: str) -> str | None:
    for pattern, mat in REPOINT:
        if re.fullmatch(pattern, path):
            return mat
    return None


def apply(text: str) -> tuple[str, set[str]]:
    if '[node name="PlaygroundArt"' in text:
        sys.exit("playground.tscn already has the art pass; regenerate the graybox first (tools/build_outdoor_locations.py)")
    # Keep the generator's own separators so the diff shows only what changed.
    parts = re.split(r"(\n+)(?=\[)", text.rstrip("\n"))
    blocks, seps = parts[0::2], parts[1::2] + ["\n"]
    out: list[str] = []
    used: set[str] = set()
    repointed: set[str] = set()
    for block in blocks:
        head = block.split("\n", 1)[0]
        if head.startswith('[sub_resource type="Environment"'):
            out.append(ENVIRONMENT.rstrip("\n"))
            continue
        if head.startswith('[node name="Sun"'):
            out.append(SUN.rstrip("\n"))
            continue
        if head.startswith("[node"):
            path = node_path(head)
            mat = material_for(path)
            if mat is not None and "material_override" in block:
                block = re.sub(r'material_override = ExtResource\("[^"]+"\)', f'material_override = ExtResource("art_{mat}")', block)
                used.add(mat)
                repointed.add(path)
            if HIDE.fullmatch(path) or path in (
                "BoardSheet", "BoardBacking", "BoardPostA/MeshInstance3D", "BoardPostB/MeshInstance3D",
            ):
                block = block.replace(head, head + "\nvisible = false", 1)
            if path == "CourtFarHalf":
                block = block.replace("position = Vector3(0, 0.008, -9.5)", "position = Vector3(0, 0.012, -9.5)")
        out.append(block)
    leftover = [node_path(b.split("\n", 1)[0]) for b in out if b.startswith("[node") and re.search(r'material_override = ExtResource\("\d+_', b)]
    if leftover:
        sys.exit("graybox meshes without an art material: " + ", ".join(leftover))
    return "".join(b + s for b, s in zip(out, seps)), used


def split_scenery(b: Builder) -> tuple[str, Builder]:
    """Separate visual-only descendants without moving any node across an occluder."""
    inner = Builder()
    outer = Builder()
    inner.nodes.append(ART_ROOT + "\n")
    outer.nodes.append(ART_INSTANCE + "\n")
    for node in b.nodes[1:]:
        head, _, props = node.partition("\n")
        parent = re.search(r'parent="([^"]+)"', head).group(1)
        if parent == "PlaygroundArt" or parent.startswith("PlaygroundArt/"):
            local = parent.removeprefix("PlaygroundArt/") if "/" in parent else "."
            inner.nodes.append(head.replace(f'parent="{parent}"', f'parent="{local}"') + "\n" + props)
        else:
            outer.nodes.append(node)
    for part in (inner, outer):
        body = "\n".join(part.nodes)
        refs = set(re.findall(r'SubResource\("([^"]+)"\)', body))
        part.subs = [block for block in b.subs if re.search(r' id="([^"]+)"', block)[1] in refs]
        part.imported_meshes = {name for name in b.imported_meshes if f'ExtResource("mesh_{name}")' in body}
    ext = material_resources(dressed_materials(inner)) + inner.mesh_resources("obj")
    header = f"[gd_scene load_steps={1 + len(ext) + len(inner.subs)} format=3]\n"
    # A fresh PackedScene.pack otherwise generates random node IDs at each bake.
    nodes = [node.replace("]\n", f" unique_id={i}]\n", 1)
             for i, node in enumerate(inner.nodes, start=1)]
    text = "\n".join([header, *ext, "", *inner.subs, *nodes])
    return text, outer


def bake_scenery(text: str, engine: str) -> None:
    """Import generated shapes in isolation, then embed them in an RSCC scene."""
    prefix = RES.removeprefix("res://")
    with tempfile.TemporaryDirectory(prefix="wis-yard-art-") as tmp:
        stage = Path(tmp)
        staged_art = stage / prefix
        # Isolate the generated imports from the editor's main asset cache.
        write_materials(staged_art / "materials", MATERIALS)
        shutil.copytree(ART / "textures", staged_art / "textures")
        construction_site.write_assets(staged_art, RES)
        yard_details.write_detail_meshes(staged_art, RES)
        (stage / "project.godot").write_text('''config_version=5

[application]
config/name="Playground scenery bake"

[compression]
formats/zstd/compression_level=15

[rendering]
renderer/rendering_method="gl_compatibility"
''')
        (stage / "scenery_source.tscn").write_text(text)
        common = [engine, "--headless", "--path", tmp]
        for args in (
            ["--import"],
            ["--script", str(ROOT / "tools" / "bake_playground_scenery.gd"), "--",
             "res://scenery_source.tscn", f"{RES}/{SCENERY_FILE}", *sorted(SCENERY_MATERIALS)],
        ):
            result = subprocess.run(common + args, capture_output=True, text=True, timeout=180)
            errors = {line for line in result.stderr.splitlines() if "ERROR:" in line}
            # Headless builds without system fonts can still import these meshes.
            no_fontconfig = "ERROR: Godot was compiled without fontconfig, system font support is disabled."
            if args[0] == "--import" and no_fontconfig in errors:
                print(no_fontconfig, file=sys.stderr)
                errors.remove(no_fontconfig)
            if result.returncode or errors:
                sys.exit(f"scenery bake failed ({result.returncode}):\n{result.stdout}\n{result.stderr}")
        shutil.copyfile(staged_art / SCENERY_FILE, ART / SCENERY_FILE)
        for mesh in sorted((staged_art / "meshes").glob("*.mesh")):
            shutil.copyfile(mesh, ART / "meshes" / mesh.name)


def finish(text: str, used: set[str], b: Builder) -> str:
    # Drop the graybox's shared-material ext_resources nothing refers to any more.
    def keep(match: re.Match) -> str:
        rid = match.group(1)
        return match.group(0) if f'ExtResource("{rid}")' in text else ""

    text = re.sub(r'\[ext_resource type="StandardMaterial3D" path="res://assets/materials/[^"]+" id="([^"]+)"\]\n', keep, text)
    ext = [f'[ext_resource type="PackedScene" path="{RES}/{SCENERY_FILE}" id="yard_scenery"]']
    new_ext = "\n".join(ext + material_resources(used) + b.mesh_resources()) + "\n"
    first_sub = text.index("\n\n[sub_resource")
    text = text[: first_sub + 1] + new_ext + text[first_sub + 1 :]
    first_node = text.index('\n[node name="Playground"')
    text = text[: first_node + 1] + "\n".join(b.subs) + "\n" + text[first_node + 1 :]
    anchor = text.index('\n[node name="Interactables"')
    text = text[: anchor + 1] + "\n".join(b.nodes) + "\n" + text[anchor + 1 :]
    steps = len(re.findall(r"^\[(ext|sub)_resource", text, re.M)) + 1
    text = re.sub(r"^\[gd_scene load_steps=\d+", f"[gd_scene load_steps={steps}", text, count=1, flags=re.M)
    return text


def write_materials(directory: Path, names) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "ink_outline.tres").write_text(OUTLINE_TRES)
    for name in sorted(names):
        (directory / f"{name}.tres").write_text(material_tres(name, MATERIALS[name]))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--scene", type=Path, default=SCENE)
    parser.add_argument("--materials-only", action="store_true")
    parser.add_argument("--engine", default="godot", help="Godot editor binary for the scenery bake")
    args = parser.parse_args()

    if not args.materials_only:
        engine = shutil.which(args.engine)
        if engine is None:
            parser.error("Godot is required to bake the scenery (set --engine)")
        version = subprocess.check_output([engine, "--version"], text=True).strip()
        pin = (ROOT / ".godot-version").read_text().strip()
        if not version.startswith(pin + ".stable."):
            parser.error(f"need Godot {pin} stable, got {version}")
        text, used = apply(args.scene.read_text())

    loose_materials = set(MATERIALS) - SCENERY_MATERIALS
    if args.materials_only:
        write_materials(MAT_DIR, loose_materials)
        return

    container, container_materials = build_container()
    full = build_nodes()
    scenery, fittings = split_scenery(full)
    used.update(dressed_materials(fittings))
    shared = (used | container_materials | {"noodle_film"}) & SCENERY_MATERIALS
    if shared:
        sys.exit("scenery-only materials used outside the bake: " + ", ".join(sorted(shared)))
    text = finish(text, used, fittings)
    used.update(dressed_materials(full) | container_materials | {"noodle_film"})
    unknown = sorted(m for m in used if m not in MATERIALS)
    if unknown:
        sys.exit("unknown materials: " + ", ".join(unknown))
    unused = sorted(set(MATERIALS) - used)
    if unused:
        sys.exit("materials written but not used: " + ", ".join(unused))
    bake_scenery(scenery, engine)
    write_materials(MAT_DIR, loose_materials)
    (ART / "container.tscn").write_text(container)
    (ART / "noodle_wrapper.tscn").write_text(build_noodle_wrapper())
    args.scene.write_text(text)
    print(f"wrote {len(loose_materials) + 1} shared materials to {MAT_DIR.relative_to(ROOT)}")
    print(f"dressed {args.scene.relative_to(ROOT)}: {len(full.nodes)} nodes, {len(full.subs)} meshes added")
    print(f"baked {SCENERY_FILE}: {(ART / SCENERY_FILE).stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
