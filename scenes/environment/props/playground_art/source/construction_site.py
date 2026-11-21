#!/usr/bin/env python3
"""The building under construction (建造中的大楼) past the yard's south-west corner.

Writes `construction_site.tscn`, a text scene of generated ArrayMeshes (site_meshes.py)
that playground.tscn instances as `ConstructionSite`. It is not part of the binary
scenery bake any more, so it rebuilds without the engine:

    python scenes/environment/props/playground_art/source/construction_site.py

The site is still a visual layer only: no collision, no navigation. Its gameplay (the
way in, the lock on the gate) is wired in playground.tscn's own tables. Nothing here
may reach past the yard's west edge, x = -23.05 (tests/playground_art_slice_test.gd).
"""

from __future__ import annotations

import math
from pathlib import Path

import site_meshes as sm
from site_mesh import Mesh, add, apply, euler, rot_y, smoothstep

ROOT = Path(__file__).resolve().parents[5]
ART = ROOT / "scenes/environment/props/playground_art"
RES = "res://scenes/environment/props/playground_art"
SCENE = ART / "construction_site.tscn"

# The yard is walkable to x = -22.5. Nothing here stands between it and the camera.
YARD_EDGE_X = -23.05
PLOT = {"x": (-35.25, YARD_EDGE_X), "z": (7.0, 19.6), "top": -0.015}
GATE_X = -26.6
GATE_Z = (11.4, 15.0)
HOARD_H = sm.PANEL_H

TOWER = {"x": -31.6, "z": 11.6, "a": 3.2, "b": 4.1, "cy": 5.4, "c": 6.3}
CAST_JOINTS = (2.75, 5.25, 7.75)
DECK = 10.25
# The porch's front face, in the building's frame; the door faces the gate (+x).
PORCH_FRONT = 3.15
DOOR_WORLD = (TOWER["x"] + PORCH_FRONT, 0.0, TOWER["z"])
# (name, x, z, half-length x, half-length z, height, seed, crater, bite)
PILES = (
    ("PileNorth", -24.75, 11.85, 1.12, 1.45, 1.02, 3, False, None),
    ("PileMiddle", -24.85, 14.55, 1.2, 1.3, 1.16, 7, False, (200.0, 0.5)),
    ("PileSouth", -24.55, 17.05, 1.02, 1.12, 0.88, 11, False, (190.0, 0.8)),
)
EXCAVATOR = (-29.7, 17.0)

TEX = f"{RES}/textures"
MAT_DIR = ART / "materials/site"
# The site's own paint: the yard's tiles under per-vertex grime, rust and wet. Every one
# multiplies its vertex colours in (vertex_color_use_as_albedo), so the same panel reads
# clean at the top and muddy at the foot without another texture. Lambert, not toon:
# curved sand and concrete shade gradually instead of in steps.
MATERIALS = {
    "site_earth": {"color": (237, 199, 174), "texture": "ground_tile", "scale": 0.40},
    "site_sand": {"color": (239, 216, 173), "texture": "plaster_tile", "scale": 0.78},
    "hoarding": {"color": (81, 119, 156), "texture": "metal_tile", "scale": 0.60, "cull_off": True},
    "hoard_fold": {"color": (70, 97, 123), "texture": "metal_tile", "scale": 0.60},
    "slab": {"color": (181, 177, 166), "texture": "plaster_tile", "scale": 0.33},
    "site_steel": {"color": (72, 74, 73), "texture": "metal_tile", "scale": 0.77},
    "site_yellow": {"color": (218, 163, 69), "texture": "metal_tile", "scale": 0.62, "roughness": 0.82},
    "site_glass": {"color": (62, 82, 88), "roughness": 0.35},
    "site_ply": {"color": (196, 160, 112), "texture": "plaster_tile", "scale": 0.5},
    "site_timber": {"color": (150, 112, 78), "texture": "plaster_tile", "scale": 0.9},
    "site_rust": {"color": (128, 72, 48), "texture": "metal_tile", "scale": 0.9},
    "site_paint": {"color": (230, 176, 56), "texture": "metal_tile", "scale": 0.62},
    "site_ink": {"color": (43, 38, 34)},
    "site_bright": {"color": (165, 167, 166), "roughness": 0.45},
    "site_pale": {"color": (226, 220, 206)},
    "site_brass": {"color": (196, 150, 66), "roughness": 0.4},
    "site_blue": {"color": (52, 86, 140)},
    "site_lamp": {"color": (255, 229, 170), "unshaded": True},
    "cold_water": {"color": (59, 78, 79), "unshaded": True},
    "marble_red": {"color": (186, 64, 52), "roughness": 0.3},
    "marble_green": {"color": (62, 132, 88), "roughness": 0.3},
    "marble_blue": {"color": (64, 98, 176), "roughness": 0.3},
    "marble_amber": {"color": (214, 150, 52), "roughness": 0.3},
}
# The part libraries name parts by what they are; this is what each wears here.
PAINT = {
    "container_deck": "site_timber", "container_oxide": "site_rust", "frame_yellow": "site_paint",
    "metal_ink": "site_ink", "exit_steel": "site_bright", "pale": "site_pale", "brass": "site_brass",
    "container": "site_blue", "lane_light": "site_lamp", "ball": "marble_red", "hoop_rim": "marble_amber",
    "door_green": "marble_green", "fire_door": "marble_red", "tyre": "site_ink",
}


def _srgb(c) -> str:
    r, g, b = (round(v / 255.0, 3) for v in c)
    return f"Color({r:g}, {g:g}, {b:g}, 1)"


def material_tres(name: str, spec: dict) -> str:
    ext = []
    if "texture" in spec:
        ext.append(f'[ext_resource type="Texture2D" path="{TEX}/{spec["texture"]}.png" id="1_tex"]')
    lines = [f'[gd_resource type="StandardMaterial3D" load_steps={len(ext) + 1} format=3]', ""]
    if ext:
        lines += ext + [""]
    lines += ["[resource]", f'resource_name = "{name}"']
    if spec.get("cull_off"):
        lines.append("cull_mode = 2")
    if spec.get("unshaded"):
        lines += ["shading_mode = 0", "disable_receive_shadows = true"]
    else:
        lines += ["diffuse_mode = 1", "specular_mode = 2"]
    lines.append("vertex_color_use_as_albedo = true")
    lines.append(f"albedo_color = {_srgb(spec['color'])}")
    if "texture" in spec:
        lines.append('albedo_texture = ExtResource("1_tex")')
    if not spec.get("unshaded"):
        lines.append(f"roughness = {spec.get('roughness', 1.0)}")
    if "texture" in spec:
        s = spec["scale"]
        lines += [f"uv1_scale = Vector3({s:g}, {s:g}, {s:g})", "uv1_triplanar = true", "uv1_world_triplanar = true"]
    lines.append("texture_filter = 3")
    return "\n".join(lines) + "\n"


def _v3(values) -> str:
    return "Vector3(" + ", ".join(f"{round(v, 4):g}" for v in values) + ")"


class _Scene:
    def __init__(self, root: str):
        self.ext: dict[str, str] = {}
        self.subs: list[str] = []
        self.nodes: list[str] = [f'[node name="{root}" type="Node3D"]\n']
        self.triangles = 0
        self.used: set[str] = set()
        self.xforms: dict[str, tuple] = {".": ((0, 0, 0), None, None, None)}
        self.bounds: dict[str, tuple] = {}
        self.extent: list[tuple[str, float]] = []

    def mat(self, name: str) -> str:
        name = PAINT.get(name, name)
        if name not in MATERIALS:
            raise KeyError(f"construction site material '{name}' is not declared in MATERIALS")
        key = f"m_{name}"
        self.used.add(name)
        self.ext[key] = f'[ext_resource type="Material" path="{RES}/materials/site/{name}.tres" id="{key}"]'
        return f'ExtResource("{key}")'

    def mesh(self, mesh: Mesh) -> str:
        rid = f"Mesh_{len(self.subs)}"
        self.subs.append(f'[sub_resource type="ArrayMesh" id="{rid}"]\n_surfaces = {mesh.surface()}\n')
        self.triangles += mesh.triangles()
        self.bounds[rid] = mesh.bounds()
        return rid

    def node(self, name, parent, kind="Node3D", *, _xf=None, **props):
        head = f'[node name="{name}" type="{kind}" parent="{parent}"]'
        body = "".join(f"{k} = {v}\n" for k, v in props.items())
        self.nodes.append(head + "\n" + body)
        path = name if parent == "." else f"{parent}/{name}"
        self.xforms[path] = (*(_xf or ((0, 0, 0), None, None)), parent)
        return path

    def to_site(self, path, point):
        """`point` in node `path`'s space, in the site's (= the yard's) space."""
        while path != ".":
            pos, rot, scale, parent = self.xforms[path]
            if scale:
                point = tuple(p * s for p, s in zip(point, scale))
            if rot:
                point = apply(euler(rot), point)
            point = add(point, pos)
            path = parent
        return point

    def group(self, name, parent, pos=(0, 0, 0), rot=None, scale=None):
        props = {"position": _v3(pos)}
        if rot:
            props["rotation_degrees"] = _v3(rot)
        if scale:
            props["scale"] = _v3(scale)
        return self.node(name, parent, _xf=(pos, rot, scale), **props)

    def put(self, name, parent, mesh, mat, pos=(0, 0, 0), rot=None, scale=None, *, shadow=True):
        if isinstance(mesh, Mesh):
            if not mesh.indices:
                return None
            mesh = self.mesh(mesh)
        props = {"position": _v3(pos)}
        lo, hi = self.bounds[mesh]
        if rot:
            props["rotation_degrees"] = _v3(rot)
        if scale:
            props["scale"] = _v3(scale)
        props["mesh"] = f'SubResource("{mesh}")'
        props["material_override"] = self.mat(mat)
        if not shadow:
            props["cast_shadow"] = "0"
        path = self.node(name, parent, "MeshInstance3D", _xf=(pos, rot, scale), **props)
        corners = [(x, y, z) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
        self.extent.append((path, max(self.to_site(path, c)[0] for c in corners)))
        return path

    def emit(self) -> str:
        steps = 1 + len(self.ext) + len(self.subs)
        return (f"[gd_scene load_steps={steps} format=3]\n\n" + "\n".join(self.ext.values()) + "\n\n"
                + "\n".join(self.subs) + "\n" + "\n".join(self.nodes))


def radius_at(y):
    t = TOWER
    f = math.sqrt(max(0.0, 1.0 - ((y - t["cy"]) / t["c"]) ** 2))
    return t["a"] * f, t["b"] * f


# --- pieces -----------------------------------------------------------------------------------


def _ground(s: _Scene) -> None:
    (x0, x1), (z0, z1), top = PLOT["x"], PLOT["z"], PLOT["top"]
    ruts = [
        ([(-29.6, 18.4), (-29.2, 16.6), (-28.3, 15.0), (-27.2, 13.6), (-26.4, 13.2)], 1.84),
        ([(-26.5, 12.9), (-27.6, 12.1), (-28.6, 11.7)], 1.6),
    ]
    sand = [(x, z, max(rx, rz) * 1.1) for _, x, z, rx, rz, *_ in PILES] + [(-28.1, 11.6, 1.0)]

    def keep_flat(x, z):
        return smoothstep(YARD_EDGE_X - 0.7, YARD_EDGE_X - 0.05, x)

    ground, _ = sm.plot_ground((x0, x1), (z0, z1), top, ruts, sand, keep_flat)
    s.put("Plot", ".", ground, "site_earth", shadow=False)
    water = Mesh()
    for i, (x, z, rx, rz) in enumerate(((-28.55, 15.35, 0.36, 0.2), (-27.75, 14.05, 0.28, 0.16),
                                        (-27.9, 12.0, 0.3, 0.17))):
        water.merge(sm.puddle((x, z), rx, rz, i + 4, top - 0.036))
    s.put("Puddles", ".", water, "cold_water", shadow=False)


def _hoarding_runs():
    return (
        ("HoardEastNorth", (GATE_X, 7.3), (GATE_X, GATE_Z[0] - 0.14), (1, 0), 90),
        ("HoardEastSouth", (GATE_X, GATE_Z[1] + 0.14), (GATE_X, 19.5), (1, 0), 90),
        ("HoardNorth", (-35.15, 7.3), (GATE_X, 7.3), (0, -1), 180),
        ("HoardWest", (-35.15, 7.3), (-35.15, 19.5), (-1, 0), -90),
        ("HoardSouthWest", (-35.15, 19.5), (-32.35, 19.5), (0, 1), 0),
        ("HoardSouth", (-30.25, 19.5), (GATE_X, 19.5), (0, 1), 0),
    )


def _hoarding(s: _Scene) -> None:
    top = PLOT["top"]
    p = s.group("Hoarding", ".")
    variants = [s.mesh(sm.hoarding_panel(v)) for v in range(3)]
    runs = _hoarding_runs()
    cap = Mesh()
    for name, start, end, outward, yaw in runs:
        span = math.dist(start, end)
        bays = max(1, round(span / sm.PANEL_W))
        width = span / bays
        for i in range(bays):
            t = (i + 0.5) / bays
            pos = (start[0] + (end[0] - start[0]) * t, top, start[1] + (end[1] - start[1]) * t)
            v = (len(name) + i * 2) % 3
            s.put(f"{name}Panel{i}", p, variants[v], "hoarding", pos, (0, yaw, 0),
                  ((width - 0.012) / sm.PANEL_W, 1, 1))
        dx, dz = (end[0] - start[0]) / span, (end[1] - start[1]) / span
        cap.merge(sm.hoarding_cap(span), rot_y(math.degrees(math.atan2(-dz, dx))),
                  ((start[0] + end[0]) / 2, top + HOARD_H + 0.015, (start[1] + end[1]) / 2))
    steel, concrete, fittings = sm.hoarding_frame([(a, b, o) for _, a, b, o, _ in runs], top)
    s.put("Posts", p, steel, "site_steel")
    s.put("Ballast", p, concrete, "slab")
    s.put("Couplers", p, fittings, "exit_steel", shadow=False)
    s.put("Capping", p, cap, "pale")
    # The panel that fell inward through the gap in the south run.
    s.put("FallenPanel", p, variants[1], "hoarding", (-31.3, top + 0.035, 19.38), (-88.0, -9.0, 2.5),
          (1.1 / 1.0, 1, 1))


def _gate(s: _Scene) -> None:
    top = PLOT["top"]
    z0, z1 = GATE_Z
    mid = (z0 + z1) / 2
    g = s.group("Gate", ".", (GATE_X, top, 0))
    posts, shoes = Mesh(), Mesh()
    for z in (z0, z1):
        posts.merge(sm.box((0.14, 3.0, 0.14), bevel=0.01), offset=(0, 1.5, z))
        posts.merge(sm.cylinder(0.075, 0.02, 12), offset=(0, 3.01, z))
        shoes.merge(sm.box((0.42, 0.2, 0.42), bevel=0.03), offset=(0, 0.1, z))
    posts.merge(sm.box((0.16, 0.16, z1 - z0 + 0.3), bevel=0.012), offset=(0, 2.92, mid))
    s.put("Posts", g, posts, "site_steel")
    s.put("Shoes", g, shoes, "slab")
    leaf = (z1 - z0) / 2 - 0.1
    frame, infill = sm.gate_leaf(leaf)
    frame_id, infill_id = s.mesh(frame), s.mesh(infill)
    for name, z, yaw in (("LeafNorth", z0 + 0.08, 0), ("LeafSouth", z1 - 0.08, 180)):
        q = s.group(name, g, (0, 0, z), (0, yaw, 0))
        s.put("Frame", q, frame_id, "site_steel")
        s.put("Bars", q, infill_id, "site_steel")
    # Blank name board over the gate; hazard boards on both posts.
    s.put("NamePlateRim", g, sm.box((0.1, 0.5, 2.44), bevel=0.01), "site_steel", (0, 3.25, mid))
    s.put("NamePlate", g, sm.box((0.03, 0.41, 2.32), bevel=0.004), "pale", (0.06, 3.25, mid))
    yellow, black = Mesh(), Mesh()
    for z in (z0, z1):
        y_, b_ = sm.hazard_board(0.12, 1.1)
        yellow.merge(y_, offset=(0.085, 0.95, z))
        black.merge(b_, offset=(0.085, 0.95, z))
    s.put("HazardBoards", g, yellow, "frame_yellow", shadow=False)
    s.put("HazardStripes", g, black, "metal_ink", shadow=False)
    # Chain round both free stiles, the padlock hanging at the bottom of the swag.
    stile_n, stile_s = z0 + 0.08 + leaf - 0.02, z1 - 0.08 - leaf + 0.02
    lock_y = 0.97
    links = sm.chain([(0.03, 1.2, stile_n - 0.07), (0.075, 1.04, mid - 0.04), (0.08, lock_y + 0.07, mid),
                      (0.075, 1.04, mid + 0.04), (0.03, 1.2, stile_s + 0.07)])
    links.merge(sm.chain([(-0.03, 1.2, stile_n - 0.07), (-0.05, 1.16, mid), (-0.03, 1.2, stile_s + 0.07)]))
    s.put("GateChain", g, links, "exit_steel", shadow=False)
    body, shackle, key = sm.padlock()
    lock = s.group("Padlock", g, (0.085, lock_y - 0.06, mid))
    q = s.group("Scale", lock, scale=(1.35, 1.35, 1.35))
    s.put("GateLock", q, body, "brass", shadow=False)
    s.put("LockShackle", q, shackle, "exit_steel", shadow=False)
    s.put("Keyway", q, key, "metal_ink", shadow=False)
    pole, head, lens = sm.floodlight()
    lamp = s.group("Floodlight", g, (-0.3, 0, 9.7 - 0.0))
    s.put("Pole", lamp, pole, "site_steel")
    s.put("Head", lamp, head, "site_steel", shadow=False)
    s.put("Lens", lamp, lens, "lane_light", shadow=False)


def _sand(s: _Scene) -> None:
    top = PLOT["top"]
    p = s.group("Sand", ".")
    for name, x, z, rx, rz, h, seed, crater, bite in PILES:
        sand, water, height_at = sm.sand_pile(rx, rz, h, seed, crater=crater, bite=bite)
        lo, hi = sand.bounds()
        if x + hi[0] > YARD_EDGE_X - 0.01:
            raise SystemExit(f"{name} reaches x = {x + hi[0]:.3f}, past the yard edge {YARD_EDGE_X}")
        q = s.group(name, p, (x, top, z))
        s.put("Body", q, sand, "site_sand")
        if water is not None:
            s.put("Water", q, water, "cold_water", shadow=False)
        if name == "PileMiddle":
            wood, steel = sm.shovel()
            sx, sz = -0.35, -0.4
            spot = (sx, height_at(sx, sz) - 0.12, sz)
            sh = s.group("Shovel", q, spot, (14, 35, -22))
            s.put("Shaft", sh, wood, "container_deck", shadow=False)
            s.put("Blade", sh, steel, "site_steel", shadow=False)
    tub, frame, tyre = sm.wheelbarrow()
    wb = s.group("Wheelbarrow", p, (-23.95, top, 19.0), (0, 96, -1))
    s.put("Tub", wb, tub, "container")
    s.put("Frame", wb, frame, "site_steel", shadow=False)
    s.put("Tyre", wb, tyre, "metal_ink", shadow=False)
    mound, _, _ = sm.sand_pile(1.4, 1.0, 0.55, 23, crater=False, rills=9, pebbles=18, base=(0.7, 0.62, 0.55),
                               rings=18, segments=56)
    s.put("SpoilMound", p, mound, "site_earth", (-33.9, top, 13.4), (0, 30, 0))


def _excavator(s: _Scene) -> None:
    top = PLOT["top"]
    q = s.group("Excavator", ".", (EXCAVATOR[0], top, EXCAVATOR[1]))
    meshes, (load, rot, place) = sm.excavator_meshes()
    names = {"site_yellow": "Body", "site_steel": "Undercarriage", "metal_ink": "Hydraulics",
             "exit_steel": "Rods", "site_glass": "Glazing", "tyre": "Hoses", "lane_light": "Lamps"}
    for mat, mesh in meshes.items():
        material = "metal_ink" if mat == "tyre" else mat
        s.put(names[mat], q, mesh, material, shadow=mat not in ("lane_light", "site_glass", "exit_steel"))
    s.put("BucketLoad", q, Mesh().merge(load, rot, place), "site_sand", shadow=False)


def _tower(s: _Scene) -> None:
    top = PLOT["top"]
    q = s.group("EllipsoidBuilding", ".", (TOWER["x"], top, TOWER["z"]))
    s.put("CastShell", q, sm.tower_shell(radius_at, DECK, CAST_JOINTS), "slab")

    drains = (-0.78, 0.98)

    def skip(theta, y):
        a = math.atan2(math.sin(theta), math.cos(theta))
        if abs(a) < 0.62 and y < 3.2:
            return True
        return any(abs(math.atan2(math.sin(theta - d), math.cos(theta - d))) < 0.08 for d in drains)

    s.put("TieHoles", q, sm.tie_holes(radius_at, DECK, CAST_JOINTS, skip), "metal_ink", shadow=False)
    timber, rails, toe = sm.deck_edge(radius_at, DECK)
    s.put("Formwork", q, timber, "container_deck")
    s.put("EdgeProtection", q, rails, "frame_yellow")
    s.put("ToeBoard", q, toe, "site_ply", shadow=False)
    s.put("StarterBars", q, sm.starter_bars(radius_at, DECK), "container_oxide", shadow=False)
    pipes, clamps = Mesh(), Mesh()
    for angle in drains:
        pipe, clamp = sm.drain_pipe(radius_at, angle, (0.35, 1.2, 3.2, 5.4, 7.65, 9.6, DECK - 0.05))
        pipes.merge(pipe)
        clamps.merge(clamp)
    s.put("DrainPipes", q, pipes, "exit_steel")
    s.put("DrainClamps", q, clamps, "site_steel", shadow=False)

    # Chalk outlines and six marbles stay on the deck, seen only from above.
    deck_y = DECK + 0.004
    chalk = Mesh()
    for turn in (0, math.pi):
        tips = [(1.17 * math.cos(turn + j * math.tau / 3), deck_y + 0.008, 1.17 * math.sin(turn + j * math.tau / 3))
                for j in range(3)]
        for j, start in enumerate(tips):
            chalk.merge(sm.tube([start, tips[(j + 1) % 3]], 0.014, 5))
    s.put("Chalk", q, chalk, "pale", shadow=False)
    marble = s.mesh(sm.marble())
    for i, mat in enumerate(("marble_red", "marble_amber", "marble_green", "site_blue", "marble_blue", "site_brass")):
        angle = i * math.tau / 6 + 0.3 * (i % 2)
        s.put(f"Marble_{i}", q, marble, mat, (0.68 * math.cos(angle), deck_y + 0.07, 0.68 * math.sin(angle)),
              shadow=False)

    # The way in: a plywood porch under the overhang, its door facing the gate.
    meshes, (yellow, black) = sm.entrance()
    e = s.group("Entrance", q, (PORCH_FRONT, 0, 0))
    for mat, mesh in meshes.items():
        s.put({"site_ply": "Porch", "site_steel": "Frame", "hoard_fold": "Door", "site_glass": "VisionPanel",
               "exit_steel": "Ironmongery", "lane_light": "Lamp", "pale": "SiteBoard",
               "metal_ink": "Fittings"}[mat], e, mesh, mat, shadow=mat in ("site_ply", "site_steel"))
    s.put("Hazard", e, yellow, "frame_yellow", (0.025, 2.32, 0), shadow=False)
    s.put("HazardStripes", e, black, "metal_ink", (0.025, 2.32, 0), shadow=False)
    s.node("DoorLight", e, "OmniLight3D", _xf=((0.35, 2.2, 0), None, None), position=_v3((0.35, 2.2, 0)),
           light_color="Color(1, 0.78, 0.52, 1)", light_energy="0.9", omni_range="3.4",
           omni_attenuation="1.6")


def _stores(s: _Scene) -> None:
    top = PLOT["top"]
    steel, timber = sm.rebar_bundle()
    r = s.group("RebarBundle", ".", (-33.4, top, 16.2), (0, 78, 0))
    s.put("Bars", r, steel, "container_oxide", shadow=False)
    s.put("Bearers", r, timber, "container_deck", shadow=False)
    timber, blocks = sm.block_pallet()
    b = s.group("BlockPallet", ".", (-33.7, top, 9.0), (0, 12, 0))
    s.put("Pallet", b, timber, "container_deck", shadow=False)
    s.put("Blocks", b, blocks, "slab")


def build() -> _Scene:
    s = _Scene("ConstructionSite")
    _ground(s)
    _hoarding(s)
    _gate(s)
    _sand(s)
    _excavator(s)
    _tower(s)
    _stores(s)
    return s


def write() -> int:
    s = build()
    over = [(path, x) for path, x in s.extent if x > YARD_EDGE_X + 0.0005]
    if over:
        raise SystemExit("past the yard edge: " + ", ".join(f"{p} ({x:.3f})" for p, x in over))
    unused = sorted(set(MATERIALS) - s.used)
    if unused:
        raise SystemExit("materials declared but not drawn: " + ", ".join(unused))
    MAT_DIR.mkdir(parents=True, exist_ok=True)
    for old in MAT_DIR.glob("*.tres"):
        old.unlink()
    for name in sorted(MATERIALS):
        (MAT_DIR / f"{name}.tres").write_text(material_tres(name, MATERIALS[name]))
    SCENE.write_text(s.emit())
    return s.triangles


if __name__ == "__main__":
    tris = write()
    print(f"wrote {SCENE.relative_to(ROOT)}: {tris:,} triangles, {SCENE.stat().st_size:,} bytes")
