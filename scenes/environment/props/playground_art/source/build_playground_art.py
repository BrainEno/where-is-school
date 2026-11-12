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
* adds one `PlaygroundArt` subtree of mesh-only nodes (no bodies, no shapes), plus two
  flat decals parented under the occluder bodies they are painted on, so the camera's
  occluder fader fades them together with their wall.

It never adds a CollisionObject3D, never moves a body, a shape, an interactable, an exit
or a spawn - `tests/playground_art_slice_test.gd` checks exactly that.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ART = HERE.parent
ROOT = HERE.parents[4]
SCENE = ROOT / "scenes" / "locations" / "playground" / "playground.tscn"
MAT_DIR = ART / "materials"
RES = "res://scenes/environment/props/playground_art"
MARKER = '[node name="PlaygroundArt" type="Node3D" parent="."]'


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
BRASS = (190, 150, 62)
CONTAINER = (66, 86, 120)
SHUTTER = (52, 68, 96)
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
    "container": {"color": CONTAINER, "texture": tex("metal_tile"), "triplanar": "world", "scale": (0.5, 0.5, 0.5), "outline": True},
    "shutter": {"color": SHUTTER, "texture": tex("metal_tile"), "triplanar": "world", "scale": (0.5, 0.5, 0.5)},
    "container_gesture": {"texture": tex("container_gesture"), "cut": 0.5},
    # the shed corner
    "shed_wall": {"color": SHED_IVORY, "texture": tex("plaster_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25), "outline": True},
    "shed_roof": {"color": ROOF_PLUM, "texture": tex("plaster_tile"), "triplanar": "world", "scale": (0.25, 0.25, 0.25), "outline": True},
    "door_green": {"color": DOOR_GREEN, "texture": tex("metal_tile"), "triplanar": "world", "scale": (0.5, 0.5, 0.5), "outline": True},
    "brass": {"color": BRASS, "outline": True},
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
    # The fence that carries on past the yard: the panel texture once per 3 x 2 m quad
    # (plain UVs, not world triplanar, so each panel can sink without its rails sliding).
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
        lines += ["diffuse_mode = 3", "specular_mode = 2"]
    lines.append(f"albedo_color = {srgb(spec.get('color', (255, 255, 255)))}")
    if "texture" in spec:
        lines.append('albedo_texture = ExtResource("2_tex")')
    if not spec.get("unshaded"):
        lines.append("roughness = 1.0")
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
    (r"ContainerBody/MeshInstance3D", "container"),
    (r"ContainerDoorLine", "shutter"),
    (r"TreeTrunk/MeshInstance3D", "trunk"),
    (r"TreeCrown", "crown"),
    (
        r"BackBars_\d_\d|FencePostGap(West|East)/MeshInstance3D|BoardPost[AB]/MeshInstance3D|BoardBacking|ContainerBar"
        r"|FitnessPost_\d/MeshInstance3D|FitnessBar(High|Low)|SitupFrame/MeshInstance3D|SitupFootBar"
        r"|Bird_\d|BirdWire|TapPost/MeshInstance3D|TapSpout|TapDrain"
        r"|SouthGatePost(West|East)|SouthGateLintel",
        "metal_ink",
    ),
]

# Ruled graybox boxes the painted planes / ring tyres below replace.
HIDE = re.compile(r"CourtLine(South|North|West|East)|CourtCentre|Key(Near|Far)|TyreStack_\d|TyreLoose")

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

    def flat(self, name: str, parent: str, mesh_id: str, mat: str, pos, rot=None, shadow: bool = False) -> None:
        props = {"position": vec3(pos)}
        if rot is not None:
            props["rotation_degrees"] = vec3(rot)
        props["mesh"] = f'SubResource("{mesh_id}")'
        props["material_override"] = f'ExtResource("art_{mat}")'
        if not shadow:
            props["cast_shadow"] = "0"
        self.node(name, parent, "MeshInstance3D", **props)


def plane(b: Builder, w: float, d: float) -> str:
    return b.mesh("PlaneMesh", size=f"Vector2({w:g}, {d:g})")


def quad(b: Builder, w: float, h: float) -> str:
    return b.mesh("QuadMesh", size=f"Vector2({w:g}, {h:g})")


def build_nodes() -> Builder:
    b = Builder()
    A = "PlaygroundArt"
    b.nodes.append(MARKER + "\n")

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
        ("RowPylon", "row_pylon", (10.0, 4.2), (-33.0, 14.0)),
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

    # The court, repainted by hand on the graybox's lines.
    b.node("Court", A)
    long_x = plane(b, 22.24, 0.24)
    long_z = plane(b, 26.24, 0.24)
    b.flat("LineSouth", f"{A}/Court", long_x, "court_line", (0, 0.022, 11))
    b.flat("LineNorth", f"{A}/Court", long_x, "court_line", (0.06, 0.022, -15), (0, 180, 0))
    b.flat("LineCentre", f"{A}/Court", long_x, "court_line", (-0.04, 0.022, -2))
    b.flat("LineWest", f"{A}/Court", long_z, "court_line", (-11, 0.022, -2), (0, 90, 0))
    b.flat("LineEast", f"{A}/Court", long_z, "court_line", (11, 0.022, -1.95), (0, -90, 0))
    key = plane(b, 5.0, 3.2)
    b.flat("KeyNear", f"{A}/Court", key, "court_key", (0, 0.02, 7.2))
    b.flat("KeyFar", f"{A}/Court", key, "court_key", (0, 0.02, -11.2), (0, 180, 0))

    # Equipment the graybox had as sticks and boxes.
    b.node("Equipment", A)
    rim = b.mesh("TorusMesh", inner_radius="0.2", outer_radius="0.235", rings="24", ring_segments="6")
    b.flat("HoopNearRing", f"{A}/Equipment", rim, "hoop_rim", (-8.0, 2.6, 6.98), shadow=True)
    b.flat("HoopFarRing", f"{A}/Equipment", rim, "hoop_rim", (8.0, 2.6, -12.02), shadow=True)
    net = b.mesh("CylinderMesh", top_radius="0.215", bottom_radius="0.15", height="0.42", radial_segments="16", rings="1", cap_top="false", cap_bottom="false")
    b.flat("HoopFarNet", f"{A}/Equipment", net, "hoop_net", (8.0, 2.39, -12.02))
    tyre = b.mesh("TorusMesh", inner_radius="0.27", outer_radius="0.5", rings="24", ring_segments="10")
    for i, y in enumerate((0.12, 0.36, 0.6)):
        b.flat(f"Tyre_{i}", f"{A}/Equipment", tyre, "tyre", (-15.2 + (0.05 if i == 1 else 0.0), y, 2.6 - (0.04 if i == 2 else 0.0)), (0, 20 * i, 0), shadow=True)
    b.flat("TyreLoose", f"{A}/Equipment", tyre, "tyre", (-14.1, 0.14, 3.5), (6, 0, 0), shadow=True)
    # The shed door's hasp and padlock (the inspection text describes both).
    b.flat("ShedHasp", f"{A}/Equipment", b.mesh("BoxMesh", size=vec3((0.03, 0.06, 0.2))), "metal_ink", (-13.875, 1.12, -3.62))
    b.flat("ShedPadlock", f"{A}/Equipment", b.mesh("BoxMesh", size=vec3((0.05, 0.09, 0.07))), "brass", (-13.85, 1.04, -3.56))

    # Decals on the occluder bodies: children of the body, so they fade with it.
    b.flat("WallPatches", "SchoolBackWall", quad(b, 6.0, 2.4), "wall_patches", (4.0, -3.0, 1.006))
    b.flat("Gesture", "ContainerBody", quad(b, 5.0, 2.0), "container_gesture", (0.0, 0.0, 1.27))
    return b


# --- scene surgery ----------------------------------------------------------------------------


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
    if MARKER in text:
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
            if HIDE.fullmatch(path):
                block = block.replace(head, head + "\nvisible = false", 1)
            if path == "CourtFarHalf":
                block = block.replace("position = Vector3(0, 0.008, -9.5)", "position = Vector3(0, 0.012, -9.5)")
        out.append(block)
    leftover = [node_path(b.split("\n", 1)[0]) for b in out if b.startswith("[node") and re.search(r'material_override = ExtResource\("\d+_', b)]
    if leftover:
        sys.exit("graybox meshes without an art material: " + ", ".join(leftover))
    return "".join(b + s for b, s in zip(out, seps)), used


def finish(text: str, used: set[str], b: Builder) -> str:
    for block in b.nodes:
        for m in re.findall(r'ExtResource\("art_([a-z_]+)"\)', block):
            used.add(m)
    # Drop the graybox's shared-material ext_resources nothing refers to any more.
    def keep(match: re.Match) -> str:
        rid = match.group(1)
        return match.group(0) if f'ExtResource("{rid}")' in text else ""

    text = re.sub(r'\[ext_resource type="StandardMaterial3D" path="res://assets/materials/[^"]+" id="([^"]+)"\]\n', keep, text)
    new_ext = "".join(f'[ext_resource type="Material" path="{RES}/materials/{m}.tres" id="art_{m}"]\n' for m in sorted(used))
    first_sub = text.index("\n\n[sub_resource")
    text = text[: first_sub + 1] + new_ext + text[first_sub + 1 :]
    first_node = text.index('\n[node name="Playground"')
    text = text[: first_node + 1] + "\n".join(b.subs) + "\n" + text[first_node + 1 :]
    anchor = text.index('\n[node name="Interactables"')
    text = text[: anchor + 1] + "\n".join(b.nodes) + "\n" + text[anchor + 1 :]
    steps = len(re.findall(r"^\[(ext|sub)_resource", text, re.M)) + 1
    text = re.sub(r"^\[gd_scene load_steps=\d+", f"[gd_scene load_steps={steps}", text, count=1, flags=re.M)
    return text


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--scene", type=Path, default=SCENE)
    parser.add_argument("--materials-only", action="store_true")
    args = parser.parse_args()

    MAT_DIR.mkdir(parents=True, exist_ok=True)
    (MAT_DIR / "ink_outline.tres").write_text(OUTLINE_TRES)
    for name, spec in MATERIALS.items():
        (MAT_DIR / f"{name}.tres").write_text(material_tres(name, spec))
    print(f"wrote {len(MATERIALS) + 1} materials to {MAT_DIR.relative_to(ROOT)}")
    if args.materials_only:
        return

    text, used = apply(args.scene.read_text())
    b = build_nodes()
    text = finish(text, used, b)
    unknown = sorted(m for m in used if m not in MATERIALS)
    if unknown:
        sys.exit("unknown materials: " + ", ".join(unknown))
    unused = sorted(set(MATERIALS) - used)
    if unused:
        sys.exit("materials written but not used: " + ", ".join(unused))
    args.scene.write_text(text)
    print(f"dressed {args.scene.relative_to(ROOT)}: {len(b.nodes)} nodes, {len(b.subs)} meshes added")


if __name__ == "__main__":
    main()
