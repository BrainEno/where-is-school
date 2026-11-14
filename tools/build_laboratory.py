#!/usr/bin/env python3
"""Builds the laboratory location: its material presets and its scene.

The room is kept in tables here rather than only in a two-thousand-line `.tscn`, for the
same reason `tools/build_outdoor_locations.py` keeps the street's blocks in a table: the
layout is the design, and a reviewer can read it.

    python3 tools/build_laboratory.py            # rewrite the materials and the scene
    python3 tools/build_laboratory.py --check    # fail if either file is out of date

What it writes:

    assets/materials/laboratory/*.tres                       the room's own material presets
    scenes/locations/laboratory/laboratory.tscn              the location scene

The room in one paragraph. A fifteen by eleven metre laboratory: a wet bench and tile along
the west wall, a fume hood and a glassware cabinet on the north wall, an analysis island
with microscopes in the middle of the working half, a bank of instruments along the east
wall, and a large mixing drum running in the centre. Every one of those pieces of equipment
trails a cable. The cables gather on the floor between the benches, crawl north along the
partition wall and go through a narrow door in it into an annex the room does not explain:
a lower ceiling, one bulb, a second doorway whose corridor continues past the outside wall,
and a shaft that climbs higher than the building. The player can walk the whole of it; the
main aisle from the entrance door to that narrow door is kept clear, and the single cable
run that crosses it is covered by a walkable steel ramp.

Boundaries this file respects: no classroom file, no story entry, no catalogue entry. The
laboratory is a standalone location scene that `LocationHost.load_location()` can enter and
`tests/laboratory_visual_slice_test.gd` can check; how the chapter uses it is the owner's
decision, so nothing here registers it in `data/story/locations.json`.
"""

from __future__ import annotations

import argparse
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MATERIAL_DIR = os.path.join(ROOT, "assets", "materials", "laboratory")
SCENE_DIR = os.path.join(ROOT, "scenes", "locations", "laboratory")
SCENE_PATH = os.path.join(SCENE_DIR, "laboratory.tscn")
TEXTURE_DIR = "res://assets/materials/laboratory/textures/"
INK_OUTLINE = "res://scenes/environment/props/playground_art/materials/ink_outline.tres"
# Shared presets the room may draw with as they are: the project's one window-glass material
# (already alpha-blended for a pane) and the ink outline pass every material above borrows.
SHARED_MATERIALS = {
    "glass_pane": ("res://assets/materials/glass_pane.tres", "7_glass"),
}

# --- the room's colour ---------------------------------------------------------
#
# Cold and desaturated, with the lamps and the annex as the only chromatic events. Values
# are sRGB: the room's broad planes sit between 0.20 and 0.62 so that the pale glassware,
# the cream instrument bodies and the one green running light all separate from them.

MATERIALS = {
    # name: (albedo, texture, outline, unshaded, emission, uv_scale)
    "wall_plaster": ((1.0, 1.0, 1.0), "wall_plaster", True, False, None, 0.22),
    "wall_tile": ((1.0, 1.0, 1.0), "tile_glaze", True, False, None, 1.0),
    "floor_concrete": ((1.0, 1.0, 1.0), "floor_concrete", False, False, None, 0.16),
    "bench_resin": ((1.0, 1.0, 1.0), "bench_top", False, False, None, 1.4),
    "bench_steel": ((0.706, 0.729, 0.729), None, True, False, None, 0.0),
    "casework_pale": ((0.780, 0.792, 0.780), None, True, False, None, 0.0),
    "metal_dark": ((0.216, 0.239, 0.259), None, True, False, None, 0.0),
    "metal_pale": ((0.545, 0.576, 0.588), None, True, False, None, 0.0),
    "metal_frame": ((0.353, 0.384, 0.400), None, False, False, None, 0.0),
    "instrument_cream": ((0.792, 0.776, 0.706), None, True, False, None, 0.0),
    "instrument_grey": ((0.620, 0.647, 0.639), None, False, False, None, 0.0),
    "glassware": ((0.839, 0.886, 0.878), None, False, False, None, 0.0),
    "ceramic_white": ((0.882, 0.890, 0.871), None, False, False, None, 0.0),
    "accent_oxide": ((0.365, 0.478, 0.443), None, True, False, None, 0.0),
    "paper_pale": ((0.859, 0.851, 0.804), None, False, False, None, 0.0),
    "cable_ink": ((0.153, 0.169, 0.184), None, False, False, None, 0.0),
    "cable_pale": ((0.667, 0.655, 0.596), None, False, False, None, 0.0),
    "cable_oxide": ((0.396, 0.459, 0.420), None, False, False, None, 0.0),
    "annex_wall": ((0.478, 0.510, 0.502), None, True, False, None, 0.0),
    "annex_floor": ((0.322, 0.353, 0.361), None, False, False, None, 0.0),
    "lamp_panel": ((0.949, 0.973, 0.980), None, False, True, (1.0, 1.0, 1.0, 1.0), 0.0),
    "annex_bulb": ((0.741, 0.855, 0.812), None, False, True, (0.741, 0.855, 0.812, 1.0), 0.0),
    "led_running": ((0.478, 1.0, 0.612), None, False, True, (0.478, 1.0, 0.612, 1.0), 0.0),
    "led_dial": ((1.0, 0.741, 0.365), None, False, True, (1.0, 0.741, 0.365, 1.0), 0.0),
    "void_black": ((0.024, 0.027, 0.031), None, False, True, None, 0.0),
    "gauge_face": ((0.886, 0.902, 0.886), None, False, False, None, 0.0),
}

# The order materials are declared in. Hand-kept so the emitted ids are stable.
MATERIAL_ORDER = list(MATERIALS.keys())


def colour(rgba) -> str:
    return "Color(%s, %s, %s, %s)" % tuple(_num(channel) for channel in rgba)


def _num(value: float) -> str:
    text = ("%.4f" % float(value)).rstrip("0").rstrip(".")
    if text in ("", "-0"):
        return "0"
    return text


def material_tres(name: str) -> str:
    albedo, texture, outline, unshaded, emission, uv_scale = MATERIALS[name]
    ext = []
    if texture:
        ext.append(("Texture2D", TEXTURE_DIR + texture + ".png", "1_tex"))
    if outline:
        ext.append(("Material", INK_OUTLINE, "2_ink"))
    lines = []
    lines.append('[gd_resource type="StandardMaterial3D" load_steps=%d format=3]' % (len(ext) + 1))
    lines.append("")
    for kind, path, rid in ext:
        lines.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, rid))
    if ext:
        lines.append("")
    lines.append("[resource]")
    if outline:
        lines.append('next_pass = ExtResource("2_ink")')
    if unshaded:
        lines.append("shading_mode = 0")
    else:
        # The project's surface language: toon diffuse, no specular lobe, roughness 1.
        lines.append("diffuse_mode = 3")
        lines.append("specular_mode = 2")
        lines.append("roughness = 1.0")
    lines.append('resource_name = "lab_%s"' % name)
    lines.append("albedo_color = %s" % colour(albedo + (1.0,) if len(albedo) == 3 else albedo))
    if emission:
        lines.append("emission_enabled = true")
        lines.append("emission = %s" % colour(emission))
        lines.append("emission_energy_multiplier = 1.6")
    lines.append("texture_filter = 3")
    if texture:
        lines.append('albedo_texture = ExtResource("1_tex")')
        lines.append("uv1_scale = %s" % v3((uv_scale, uv_scale, uv_scale)))
        if name in ("wall_plaster", "floor_concrete"):
            # World triplanar: the shell is boxes, and a box's per-face UVs would stretch one
            # texture across every wall face at a different size.
            lines.append("uv1_triplanar = true")
            lines.append("uv1_world_triplanar = true")
    lines.append("")
    return "\n".join(lines)


# --- scene tables --------------------------------------------------------------


def v3(v) -> str:
    return "Vector3(%s, %s, %s)" % tuple(_num(x) for x in v)


def v2(v) -> str:
    return "Vector2(%s, %s)" % tuple(_num(x) for x in v)


class Lab:
    def __init__(self) -> None:
        self.boxes: list[dict] = []
        self.quads: list[dict] = []
        self.cylinders: list[dict] = []
        self.cables: list[dict] = []
        self.lights: list[dict] = []
        self.interactables: list[dict] = []
        self.spawns: list[dict] = []
        self.groups: dict[str, list[str]] = {}

    # A solid the player collides with, or a decoration that only draws.
    def box(self, name, pos, size, mat, body=False, group=None, solid=True, rotation=None, script=None):
        self.boxes.append(
            {
                "name": name,
                "pos": pos,
                "size": size,
                "mat": mat,
                "body": body and solid,
                "group": group,
                "rotation": rotation,
                "script": script,
            }
        )

    def quad(self, name, pos, size, mat, rotation=None, body=False):
        self.quads.append(
            {"name": name, "pos": pos, "size": size, "mat": mat, "rotation": rotation, "body": body}
        )

    def cyl(self, name, pos, radius, height, mat, top_radius=None, segments=12, rotation=None):
        self.cylinders.append(
            {
                "name": name,
                "pos": pos,
                "radius": radius,
                "top": radius if top_radius is None else top_radius,
                "height": height,
                "mat": mat,
                "segments": segments,
                "rotation": rotation,
            }
        )

    def light(self, name, pos, energy, rng, color=(0.94, 0.97, 1.0), shadow=False, angle=None):
        self.lights.append(
            {
                "name": name,
                "pos": pos,
                "energy": energy,
                "range": rng,
                "color": color,
                "shadow": shadow,
                "angle": angle,
            }
        )


# --- geometry helpers ----------------------------------------------------------


def slab(lab: Lab, name, centre, size, mat, body=True, group=None, rotation=None):
    """A box that the player stands on or walks into: it carries its own collider."""
    lab.box(name, centre, size, mat, body=body, group=group, rotation=rotation)


def prop(lab: Lab, name, centre, size, mat, rotation=None):
    """A box that only draws. Props never collide; the furniture under them does."""
    lab.box(name, centre, size, mat, body=False, rotation=rotation)


def tube_along(p0, p1, radius):
    """The transform that turns a unit cylinder (radius 0.5, height 1) into this segment."""
    dx, dy, dz = (p1[i] - p0[i] for i in range(3))
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length < 1e-5:
        return None
    y = (dx / length, dy / length, dz / length)
    # Any axis not parallel to the segment will do for the first basis vector.
    ref = (0.0, 1.0, 0.0) if abs(y[1]) < 0.95 else (1.0, 0.0, 0.0)
    x = (
        y[1] * ref[2] - y[2] * ref[1],
        y[2] * ref[0] - y[0] * ref[2],
        y[0] * ref[1] - y[1] * ref[0],
    )
    norm = math.sqrt(x[0] ** 2 + x[1] ** 2 + x[2] ** 2)
    x = (x[0] / norm, x[1] / norm, x[2] / norm)
    z = (x[1] * y[2] - x[2] * y[1], x[2] * y[0] - x[0] * y[2], x[0] * y[1] - x[1] * y[0])
    scale = 2.0 * radius
    basis = (
        x[0] * scale, x[1] * scale, x[2] * scale,
        y[0] * length, y[1] * length, y[2] * length,
        z[0] * scale, z[1] * scale, z[2] * scale,
    )
    origin = ((p0[0] + p1[0]) * 0.5, (p0[1] + p1[1]) * 0.5, (p0[2] + p1[2]) * 0.5)
    return basis + origin


def control_path(points, step=0.62, sag=0.0):
    """Resamples a polyline into short segments, optionally sagging between the points."""
    out = []
    for index in range(len(points) - 1):
        a, b = points[index], points[index + 1]
        span = math.dist(a, b)
        count = max(1, int(math.ceil(span / step)))
        for i in range(count):
            t0 = i / count
            t1 = (i + 1) / count
            p0 = _lerp(a, b, t0)
            p1 = _lerp(a, b, t1)
            if sag:
                p0 = (p0[0], p0[1] - sag * 4.0 * t0 * (1.0 - t0), p0[2])
                p1 = (p1[0], p1[1] - sag * 4.0 * t1 * (1.0 - t1), p1[2])
            out.append((p0, p1))
    return out


def _lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def cable_route(lab: Lab, name, points, radius=0.011, mat="cable_ink", step=0.62, sag=0.03, jitter=0.0):
    """One cable as a chain of cylinder segments. `jitter` slides the whole run sideways."""
    moved = [(p[0] + jitter, p[1], p[2] + jitter) for p in points]
    for index, (p0, p1) in enumerate(control_path(moved, step=step, sag=sag)):
        lab.cables.append({"name": "%s_%03d" % (name, index), "p0": p0, "p1": p1, "radius": radius, "mat": mat})


# --- the room ------------------------------------------------------------------


def build_room(lab: Lab) -> None:
    # The shell. Interior x -7.6 .. 7.6, z -5.6 .. 5.6, walls 3.4 m up, and - like every
    # interior in this project - no ceiling over the working half: the camera looks down
    # into the room from above and the room has to stay readable from there.
    slab(lab, "Floor", (0.0, -0.1, 0.0), (15.6, 0.2, 11.6), "floor_concrete")
    # The opening in the north wall is 1.5 m wide and 2.45 m tall. Both numbers are a
    # navigation constraint, not a decoration: the bake erodes the walkable surface by the
    # agent's radius (0.5 m) on every side and quantises height in 0.25 m cells, so a
    # narrower or lower opening would be baked shut and the space behind it unreachable.
    slab(lab, "WallNorthLeft", (-2.125, 1.7, -5.7), (11.35, 3.4, 0.2), "wall_plaster", group="camera_occluder")
    slab(lab, "WallNorthRight", (6.425, 1.7, -5.7), (2.75, 3.4, 0.2), "wall_plaster", group="camera_occluder")
    slab(lab, "WallNorthLintel", (4.3, 2.925, -5.7), (1.5, 0.95, 0.2), "wall_plaster", group="camera_occluder")
    slab(lab, "WallSouth", (0.0, 1.7, 5.7), (15.6, 3.4, 0.2), "wall_plaster", group="camera_occluder")
    slab(lab, "WallWest", (-7.7, 1.7, 0.0), (0.2, 3.4, 11.6), "wall_plaster", group="camera_occluder")
    slab(lab, "WallEast", (7.7, 1.7, 0.0), (0.2, 3.4, 11.6), "wall_plaster", group="camera_occluder")
    # Skirting, in the metal the benches are made of, so the wall meets the floor with a line.
    for name, pos, size in (
        ("SkirtingNorth", (0.0, 0.06, -5.55), (15.2, 0.12, 0.05)),
        ("SkirtingWest", (-7.55, 0.06, 0.0), (0.05, 0.12, 11.2)),
        ("SkirtingEast", (7.55, 0.06, 0.0), (0.05, 0.12, 11.2)),
        ("SkirtingSouth", (0.0, 0.06, 5.55), (15.2, 0.12, 0.05)),
    ):
        prop(lab, name, pos, size, "metal_frame")

    # The entrance: a sealed double door on the south wall. The scene is a room, not a
    # corridor, and no exit is authored here on purpose (see the module docstring).
    prop(lab, "EntranceFrame", (-4.4, 1.05, 5.54), (1.9, 2.1, 0.08), "metal_frame")
    prop(lab, "EntranceLeafLeft", (-5.05, 1.02, 5.5), (0.86, 2.0, 0.06), "casework_pale")
    prop(lab, "EntranceLeafRight", (-3.75, 1.02, 5.5), (0.86, 2.0, 0.06), "casework_pale")
    prop(lab, "EntrancePushBar", (-4.4, 1.0, 5.45), (1.4, 0.06, 0.05), "metal_pale")
    prop(lab, "EntranceKickPlate", (-4.4, 0.24, 5.45), (1.7, 0.18, 0.05), "metal_frame")


def build_wet_bench(lab: Lab) -> None:
    """West wall: the wet bench. Two sinks, a rack of drying glass, and the day's washing up."""
    top_y = 0.92
    prop(lab, "WetBenchTop", (-7.05, top_y, -1.4), (0.92, 0.06, 5.6), "bench_resin")
    slab(lab, "WetBenchBody", (-7.08, 0.45, -1.4), (0.86, 0.9, 5.6), "bench_steel")
    prop(lab, "WetBenchPlinth", (-7.05, 0.04, -1.4), (0.8, 0.08, 5.5), "metal_frame")
    # The tiled splashback: the one place in the room that says "washable" at a glance.
    prop(lab, "WetBenchTile", (-7.55, 1.42, -1.4), (0.05, 1.0, 5.6), "wall_tile")
    prop(lab, "WetBenchShelf", (-7.35, 1.98, -1.4), (0.34, 0.04, 3.4), "bench_steel")
    prop(lab, "WetBenchShelfLip", (-7.2, 2.02, -1.4), (0.04, 0.1, 3.4), "metal_pale")

    for index, z in enumerate((-2.9, 1.1)):
        prop(lab, "SinkRim%d" % index, (-7.05, top_y + 0.02, z), (0.52, 0.05, 0.62), "ceramic_white")
        prop(lab, "SinkBowl%d" % index, (-7.05, top_y - 0.02, z), (0.42, 0.12, 0.52), "metal_frame")
        lab.cyl("TapStem%d" % index, (-7.4, top_y + 0.2, z), 0.022, 0.42, "metal_pale")
        lab.cyl("TapSpout%d" % index, (-7.24, top_y + 0.4, z), 0.018, 0.3, "metal_pale", rotation=(0, 0, 90))
        prop(lab, "TapHandle%d" % index, (-7.4, top_y + 0.44, z), (0.06, 0.05, 0.18), "metal_dark")

    # A drying rack over the bench: rails and pegs, with three flasks left upside down.
    prop(lab, "DryingRackTray", (-7.05, top_y + 0.05, -0.5), (0.5, 0.03, 0.9), "metal_pale")
    for index in range(6):
        lab.cyl(
            "DryingPeg%d" % index,
            (-7.05 + 0.14 * ((index % 3) - 1), top_y + 0.14, -0.8 + 0.3 * (index // 3)),
            0.008, 0.16, "metal_pale",
        )
    for index, (x, z) in enumerate(((-7.15, -0.75), (-6.95, -0.45), (-7.1, -0.2))):
        lab.cyl("DryingFlask%d" % index, (x, top_y + 0.15, z), 0.072, 0.17, "glassware", top_radius=0.026)

    # Glassware on the bench, in two clusters rather than spread evenly: someone was working
    # here, and the rest of the surface is clear.
    for index, (x, z, kind) in enumerate(
        (
            (-6.85, -3.5, "flask"),
            (-7.15, -3.35, "flask"),
            (-6.7, -3.25, "beaker"),
            (-7.3, -3.6, "beaker"),
            (-6.78, 1.8, "flask"),
            (-7.12, 1.95, "cylinder"),
            (-6.9, 2.15, "beaker"),
        )
    ):
        if kind == "flask":
            lab.cyl("GlassFlask%d" % index, (x, top_y + 0.09, z), 0.075, 0.18, "glassware", top_radius=0.028)
        elif kind == "beaker":
            lab.cyl("GlassBeaker%d" % index, (x, top_y + 0.07, z), 0.046, 0.14, "glassware", top_radius=0.05)
        else:
            lab.cyl("GlassCylinder%d" % index, (x, top_y + 0.14, z), 0.019, 0.28, "glassware")

    # The waste jar, amber-lidded and labelled, kept off the working surface on the floor.
    lab.cyl("WasteJar", (-7.1, 0.14, 2.75), 0.13, 0.28, "glassware")
    lab.cyl("WasteJarLid", (-7.1, 0.3, 2.75), 0.135, 0.05, "metal_dark")
    prop(lab, "WasteJarLabel", (-6.97, 0.15, 2.75), (0.01, 0.09, 0.11), "paper_pale")

    # A bench lamp, warm, clamped to the shelf: the one warm thing on this side of the room.
    prop(lab, "BenchLampArm", (-7.3, 2.28, -1.9), (0.03, 0.5, 0.03), "metal_dark")
    prop(lab, "BenchLampShade", (-7.15, 2.05, -1.9), (0.22, 0.08, 0.14), "instrument_cream")
    prop(lab, "BenchLampGlow", (-7.15, 2.0, -1.9), (0.2, 0.02, 0.12), "led_dial")
    lab.light("BenchLampLight", (-7.05, 1.9, -1.9), 0.55, 3.4, color=(1.0, 0.87, 0.71))


def build_north_wall(lab: Lab) -> None:
    """North wall: the fume hood, the glassware cabinet, and the sockets everything hangs off."""
    # Fume hood: an alcove with a sash, a baffle and a duct that keeps going up.
    prop(lab, "HoodSideWest", (-5.86, 1.28, -5.16), (0.1, 2.3, 0.86), "casework_pale")
    prop(lab, "HoodSideEast", (-3.34, 1.28, -5.16), (0.1, 2.3, 0.86), "casework_pale")
    prop(lab, "HoodCanopy", (-4.6, 2.42, -5.16), (2.6, 0.16, 0.86), "casework_pale")
    prop(lab, "HoodBackTile", (-4.6, 1.2, -5.56), (2.5, 1.5, 0.04), "wall_tile")
    prop(lab, "HoodDeck", (-4.6, 0.95, -5.16), (2.4, 0.07, 0.8), "bench_resin")
    prop(lab, "HoodDeckFront", (-4.6, 0.86, -4.78), (2.4, 0.18, 0.06), "casework_pale")
    prop(lab, "HoodBaffle", (-4.6, 1.72, -5.46), (2.3, 0.5, 0.04), "metal_pale")
    # The sash: a glass pane in a frame, pulled down to the working height and left there.
    prop(lab, "HoodSashFrameTop", (-4.6, 2.2, -4.78), (2.5, 0.07, 0.06), "metal_pale")
    prop(lab, "HoodSashFrameBottom", (-4.6, 1.66, -4.78), (2.5, 0.06, 0.06), "metal_pale")
    prop(lab, "HoodSashHandle", (-4.6, 1.5, -4.78), (0.7, 0.04, 0.05), "metal_dark")
    lab.quad("HoodSashGlass", (-4.6, 1.93, -4.785), (2.4, 0.5), "glass_pane", body=False)
    prop(lab, "HoodDuct", (-4.6, 3.16, -5.3), (0.44, 1.0, 0.44), "metal_pale")
    prop(lab, "HoodDuctRing", (-4.6, 2.68, -5.3), (0.5, 0.06, 0.5), "metal_dark")
    for index, (x, z) in enumerate(((-5.2, -5.2), (-4.9, -5.3), (-4.1, -5.25))):
        lab.cyl("HoodBottle%d" % index, (x, 1.09, z), 0.05, 0.2, "glassware", top_radius=0.032)
    prop(lab, "HoodStand", (-4.2, 1.3, -5.3), (0.03, 0.62, 0.03), "metal_pale")
    prop(lab, "HoodStandBase", (-4.2, 1.0, -5.3), (0.24, 0.04, 0.16), "metal_pale")

    # Glassware cabinet: glass doors, three shelves, and the clean glass behind them.
    slab(lab, "GlassCabinetBody", (-1.8, 1.05, -5.36), (1.7, 2.1, 0.42), "casework_pale")
    prop(lab, "GlassCabinetDoorFrame", (-1.8, 1.05, -5.14), (1.74, 2.14, 0.05), "metal_frame")
    lab.quad("GlassCabinetDoorLeft", (-2.22, 1.05, -5.11), (0.78, 1.96), "glass_pane")
    lab.quad("GlassCabinetDoorRight", (-1.38, 1.05, -5.11), (0.78, 1.96), "glass_pane")
    prop(lab, "GlassCabinetMullion", (-1.8, 1.05, -5.1), (0.05, 2.0, 0.03), "metal_frame")
    for index, y in enumerate((0.5, 1.05, 1.6)):
        prop(lab, "GlassCabinetShelf%d" % index, (-1.8, y, -5.34), (1.6, 0.03, 0.36), "metal_pale")
    for index in range(9):
        x = -2.4 + 0.15 * index
        shelf = 0.5 + 0.55 * (index % 3)
        lab.cyl(
            "CabinetGlass%d" % index,
            (x, shelf + 0.09, -5.34),
            0.045, 0.16, "glassware",
            top_radius=0.02 if index % 2 else 0.05,
            segments=10,
        )

    # Sockets and the wall trunking the cables start from.
    prop(lab, "SocketTrunking", (-3.0, 1.02, -5.5), (4.6, 0.14, 0.08), "metal_frame")
    for index in range(5):
        prop(lab, "SocketFace%d" % index, (-4.6 + 1.0 * index, 1.02, -5.44), (0.16, 0.16, 0.03), "casework_pale")
    prop(lab, "DistributionBoard", (1.4, 1.62, -5.5), (0.7, 0.9, 0.12), "instrument_grey")
    prop(lab, "DistributionBoardDoor", (1.4, 1.62, -5.43), (0.62, 0.8, 0.03), "metal_frame")
    prop(lab, "DistributionLed", (1.16, 1.94, -5.41), (0.05, 0.03, 0.02), "led_running")


def build_island(lab: Lab) -> None:
    """The analysis island: two microscopes, a centrifuge, and the book someone writes in."""
    top_y = 0.92
    prop(lab, "IslandTop", (-2.4, top_y, -2.9), (3.4, 0.06, 1.15), "bench_resin")
    slab(lab, "IslandBody", (-2.4, 0.45, -2.9), (3.2, 0.9, 1.0), "bench_steel")
    prop(lab, "IslandPlinth", (-2.4, 0.04, -2.9), (3.1, 0.08, 0.9), "metal_frame")
    prop(lab, "IslandKick", (-2.4, top_y - 0.1, -2.36), (3.2, 0.16, 0.04), "metal_frame")
    # A low rail on the far side holds the instruments' cables off the bench surface.
    prop(lab, "IslandCableRail", (-2.4, top_y + 0.06, -3.44), (3.2, 0.03, 0.03), "metal_frame")

    for index, x in enumerate((-3.3, -1.6)):
        base = (x, top_y + 0.03, -3.05)
        prop(lab, "MicroBase%d" % index, base, (0.24, 0.06, 0.3), "instrument_grey")
        prop(lab, "MicroColumn%d" % index, (x, top_y + 0.24, -3.14), (0.07, 0.42, 0.07), "instrument_grey")
        lab.cyl("MicroTube%d" % index, (x, top_y + 0.34, -3.0), 0.035, 0.3, "instrument_cream", rotation=(28, 0, 0))
        lab.cyl("MicroEye%d" % index, (x, top_y + 0.47, -2.94), 0.022, 0.09, "metal_dark", rotation=(28, 0, 0))
        prop(lab, "MicroStage%d" % index, (x, top_y + 0.14, -3.0), (0.16, 0.02, 0.16), "metal_pale")
        prop(lab, "MicroKnob%d" % index, (x + 0.1, top_y + 0.2, -3.12), (0.04, 0.04, 0.04), "metal_dark")

    # Centrifuge: a squat cylinder with a lid, its own cable leaving the back.
    lab.cyl("CentrifugeBody", (-2.4, top_y + 0.15, -3.1), 0.2, 0.3, "instrument_grey", segments=14)
    lab.cyl("CentrifugeLid", (-2.4, top_y + 0.32, -3.1), 0.21, 0.05, "instrument_cream", segments=14)
    prop(lab, "CentrifugeLatch", (-2.4, top_y + 0.28, -2.92), (0.1, 0.05, 0.04), "metal_dark")
    prop(lab, "CentrifugeLed", (-2.55, top_y + 0.2, -2.92), (0.03, 0.02, 0.02), "led_running")

    # The book: a ring binder open on the bench, a pen across it, a strip of tape on the page.
    prop(lab, "LogBookLeft", (-1.1, top_y + 0.035, -2.62), (0.24, 0.03, 0.32), "paper_pale")
    prop(lab, "LogBookRight", (-0.86, top_y + 0.04, -2.62), (0.24, 0.03, 0.32), "paper_pale")
    prop(lab, "LogBookRuled", (-1.1, top_y + 0.052, -2.62), (0.2, 0.002, 0.28), "instrument_grey")
    lab.cyl("LogPen", (-1.05, top_y + 0.09, -2.52), 0.006, 0.15, "metal_dark", rotation=(0, 0, 82))

    # A rack of clean tubes and two reagent bottles.
    prop(lab, "TubeRackBase", (-1.9, top_y + 0.04, -2.6), (0.22, 0.08, 0.1), "metal_pale")
    for index in range(5):
        lab.cyl("RackTube%d" % index, (-2.0 + 0.05 * index, top_y + 0.12, -2.6), 0.009, 0.14, "glassware", segments=8)
    for index, (x, z) in enumerate(((-3.05, -2.55), (-2.95, -2.72))):
        lab.cyl("IslandBottle%d" % index, (x, top_y + 0.11, z), 0.055, 0.22, "glassware", top_radius=0.036)
        prop(lab, "IslandBottleCap%d" % index, (x, top_y + 0.23, z), (0.05, 0.03, 0.05), "metal_dark")

    # Stools, pulled out at the angle someone left them. They collide: they are seats.
    for index, (x, z, spin) in enumerate(((-3.2, -2.1, 8), (-2.4, -2.05, -14), (-1.6, -2.1, 4))):
        slab(lab, "StoolSeat%d" % index, (x, 0.62, z), (0.34, 0.06, 0.34), "instrument_cream", rotation=(0, spin, 0))
        for leg in range(3):
            angle = math.radians(90 * leg + spin)
            lab.cyl(
                "StoolLeg%d_%d" % (index, leg),
                (x + 0.1 * math.cos(angle), 0.31, z + 0.1 * math.sin(angle)),
                0.016, 0.6, "metal_frame",
            )


def build_instruments(lab: Lab) -> None:
    """East wall: the bank of machines every cable in the room can be traced back to."""
    top_y = 0.92
    prop(lab, "InstrumentBenchTop", (7.14, top_y, 2.8), (0.87, 0.06, 4.3), "bench_resin")
    slab(lab, "InstrumentBenchBody", (7.18, 0.45, 2.8), (0.8, 0.9, 4.3), "bench_steel")
    prop(lab, "InstrumentBenchPlinth", (7.14, 0.04, 2.8), (0.74, 0.08, 4.2), "metal_frame")
    prop(lab, "InstrumentBackTile", (7.55, 1.5, 2.8), (0.05, 1.1, 4.3), "wall_tile")
    prop(lab, "InstrumentShelf", (7.36, 2.02, 2.8), (0.34, 0.04, 4.0), "bench_steel")

    # 1. The incubator: a cream box with a glass door and a green running light.
    prop(lab, "IncubatorBody", (7.16, top_y + 0.4, 1.02), (0.72, 0.8, 0.66), "instrument_cream")
    prop(lab, "IncubatorDoor", (6.82, top_y + 0.4, 1.02), (0.05, 0.66, 0.56), "metal_frame")
    # The one quad that does not face +Z: the incubator's glass is in its west face, towards
    # the room, so it is turned a quarter turn about Y or it would be seen edge-on.
    lab.quad("IncubatorGlass", (6.79, top_y + 0.42, 1.02), (0.5, 0.5), "glass_pane", rotation=(0, -90, 0))
    prop(lab, "IncubatorPanel", (6.83, top_y + 0.72, 0.72), (0.04, 0.1, 0.14), "instrument_grey")
    prop(lab, "IncubatorLed", (6.8, top_y + 0.74, 0.68), (0.02, 0.025, 0.025), "led_running")

    # 2. The centrifuge: a lid, a rotor housing, and a dial.
    lab.cyl("BankCentrifugeBody", (7.16, top_y + 0.19, 2.1), 0.28, 0.38, "instrument_grey", segments=16)
    lab.cyl("BankCentrifugeLid", (7.16, top_y + 0.41, 2.1), 0.29, 0.06, "instrument_cream", segments=16)
    lab.cyl("BankCentrifugeDial", (6.9, top_y + 0.3, 2.34), 0.05, 0.03, "instrument_cream", rotation=(0, 0, 90))
    prop(lab, "BankCentrifugeLed", (6.9, top_y + 0.22, 2.34), (0.02, 0.02, 0.02), "led_dial")

    # 3. The pump: dark, bolted down, with a pipe that goes up to the shelf.
    prop(lab, "PumpBody", (7.14, top_y + 0.19, 3.2), (0.56, 0.4, 0.46), "metal_dark")
    prop(lab, "PumpHead", (7.02, top_y + 0.44, 3.2), (0.3, 0.14, 0.3), "metal_pale")
    lab.cyl("PumpPipe", (7.32, top_y + 0.62, 3.2), 0.035, 0.5, "metal_pale")
    lab.cyl("PumpPipeElbow", (7.32, top_y + 0.86, 3.2), 0.035, 0.22, "metal_pale", rotation=(0, 0, 90))

    # 4. The controller: two dials, a gauge, a blank plate where a switch would be.
    prop(lab, "ControllerBody", (7.16, top_y + 0.22, 4.1), (0.62, 0.46, 0.42), "instrument_cream")
    lab.cyl("ControllerDialA", (6.84, top_y + 0.3, 3.98), 0.06, 0.04, "metal_dark", rotation=(0, 0, 90))
    lab.cyl("ControllerDialB", (6.84, top_y + 0.3, 4.22), 0.06, 0.04, "metal_dark", rotation=(0, 0, 90))
    lab.cyl("ControllerGauge", (6.84, top_y + 0.42, 4.1), 0.075, 0.03, "gauge_face", rotation=(0, 0, 90))
    prop(lab, "ControllerBlank", (6.83, top_y + 0.14, 4.1), (0.02, 0.1, 0.2), "instrument_grey")
    prop(lab, "ControllerLed", (6.83, top_y + 0.14, 3.94), (0.02, 0.02, 0.02), "led_running")

    # The tray the cables run in, and the conduit that takes them out of the room's sight.
    prop(lab, "CableTrayEast", (7.3, 2.42, 2.8), (0.3, 0.08, 4.2), "metal_frame")
    prop(lab, "CableTrayBracketA", (7.36, 2.3, 1.2), (0.22, 0.24, 0.05), "metal_frame")
    prop(lab, "CableTrayBracketB", (7.36, 2.3, 4.3), (0.22, 0.24, 0.05), "metal_frame")
    prop(lab, "ConduitDropWest", (7.44, 1.82, 0.78), (0.12, 1.2, 0.12), "metal_pale")


def build_mixer(lab: Lab) -> None:
    """The mixing drum in the middle of the room: the largest object, and the loudest."""
    cx, cz = 0.7, 1.0
    prop(lab, "MixerTray", (cx, 0.03, cz), (2.0, 0.06, 2.0), "metal_frame")
    for index, (dx, dz) in enumerate(((-0.62, -0.62), (0.62, -0.62), (-0.62, 0.62), (0.62, 0.62))):
        prop(lab, "MixerLeg%d" % index, (cx + dx, 0.62, cz + dz), (0.11, 1.2, 0.11), "metal_dark")
    prop(lab, "MixerCrossA", (cx, 1.06, cz - 0.62), (1.34, 0.1, 0.08), "metal_dark")
    prop(lab, "MixerCrossB", (cx, 1.06, cz + 0.62), (1.34, 0.1, 0.08), "metal_dark")
    prop(lab, "MixerCrossC", (cx - 0.62, 1.06, cz), (0.08, 0.1, 1.34), "metal_dark")
    prop(lab, "MixerCrossD", (cx + 0.62, 1.06, cz), (0.08, 0.1, 1.34), "metal_dark")
    slab(lab, "MixerDrum", (cx, 1.62, cz), (1.2, 1.1, 1.2), "metal_pale")
    lab.cyl("MixerDrumSkin", (cx, 1.62, cz), 0.63, 1.12, "metal_pale", segments=18)
    lab.cyl("MixerBandLow", (cx, 1.2, cz), 0.645, 0.08, "metal_dark", segments=18)
    lab.cyl("MixerBandHigh", (cx, 2.0, cz), 0.645, 0.08, "metal_dark", segments=18)
    lab.cyl("MixerLid", (cx, 2.2, cz), 0.62, 0.07, "metal_pale", segments=18)
    prop(lab, "MixerMotor", (cx, 2.45, cz), (0.46, 0.4, 0.46), "metal_dark")
    prop(lab, "MixerMotorFan", (cx, 2.45, cz - 0.24), (0.34, 0.34, 0.03), "metal_frame")
    # The one moving part in the room: a flat vane on the motor shaft, turning at a constant
    # speed (scenes/locations/laboratory/spinner.gd). The drum itself does not move.
    lab.box("MixerBlade", (cx, 2.74, cz), (0.32, 0.03, 0.08), "metal_pale", body=False, script="spinner")
    lab.cyl("MixerShaft", (cx, 2.66, cz), 0.04, 0.14, "metal_pale", segments=10)
    prop(lab, "MixerShaftCoupling", (cx, 2.82, cz), (0.12, 0.06, 0.12), "instrument_cream")
    # A control box with a running light and no switch on it at all.
    prop(lab, "MixerControlBox", (cx + 0.78, 1.62, cz - 0.3), (0.2, 0.34, 0.3), "instrument_cream")
    prop(lab, "MixerControlLed", (cx + 0.89, 1.7, cz - 0.36), (0.02, 0.025, 0.025), "led_running")
    prop(lab, "MixerControlPlate", (cx + 0.89, 1.56, cz - 0.26), (0.02, 0.16, 0.18), "instrument_grey")
    # The pipe out of the lid, west, to the wall, where it turns down into the floor.
    lab.cyl("MixerPipeUp", (cx - 0.1, 2.5, cz - 0.2), 0.07, 0.5, "metal_pale", segments=10)
    lab.cyl("MixerPipeRun", (-2.2, 2.72, cz - 0.2), 0.07, 4.2, "metal_pale", segments=10, rotation=(0, 0, 90))
    lab.cyl("MixerPipeDrop", (-4.3, 1.4, cz - 0.2), 0.07, 2.7, "metal_pale", segments=10)


def build_annex(lab: Lab) -> None:
    """The room behind the narrow door, and the three things in it that do not add up."""
    # Partition between the laboratory and the annex, with a 0.95 m door in it.
    slab(lab, "PartitionWestA", (2.2, 1.7, -4.6), (0.18, 3.4, 2.0), "wall_plaster", group="camera_occluder")
    slab(lab, "PartitionWestB", (2.2, 1.7, -1.35), (0.18, 3.4, 1.5), "wall_plaster", group="camera_occluder")
    slab(lab, "PartitionLintel", (2.2, 2.925, -2.85), (0.18, 0.95, 1.5), "wall_plaster", group="camera_occluder")
    slab(lab, "PartitionSouth", (4.9, 1.7, -0.6), (5.4, 3.4, 0.18), "wall_plaster", group="camera_occluder")
    # The door frame: steel, plain, with no signage anywhere on it.
    prop(lab, "AnnexDoorJambA", (2.2, 1.15, -3.55), (0.24, 2.3, 0.1), "metal_frame")
    prop(lab, "AnnexDoorJambB", (2.2, 1.15, -2.15), (0.24, 2.3, 0.1), "metal_frame")
    prop(lab, "AnnexDoorHead", (2.2, 2.42, -2.85), (0.24, 0.14, 1.5), "metal_frame")
    prop(lab, "AnnexDoorSill", (2.2, 0.03, -2.85), (0.3, 0.05, 1.4), "metal_frame")

    # The annex floor sits a step down and a shade darker than the laboratory's.
    slab(lab, "AnnexFloor", (4.9, -0.06, -3.1), (5.3, 0.12, 4.9), "annex_floor")
    prop(lab, "AnnexStep", (2.32, 0.04, -2.85), (0.24, 0.08, 1.4), "metal_frame")

    # A ceiling at 2.6 m over a room whose neighbours have none, in three pieces so the
    # shaft can pass through it. It is in the occluder group: standing inside, the camera
    # is above it, and it has to thin out exactly like a wall does.
    for name, pos, size in (
        ("AnnexCeilingWest", (4.15, 2.66, -3.1), (3.9, 0.12, 5.0)),
        ("AnnexCeilingNorth", (6.85, 2.66, -5.0), (1.5, 0.12, 1.2)),
        ("AnnexCeilingSouth", (6.85, 2.66, -1.6), (1.5, 0.12, 2.0)),
    ):
        slab(lab, name, pos, size, "annex_wall", group="camera_occluder")

    # 1. One bulb, on a cord, hanging lower than it should.
    lab.cyl("AnnexCord", (5.1, 2.42, -3.3), 0.008, 0.5, "metal_frame", segments=6)
    lab.cyl("AnnexBulb", (5.1, 2.12, -3.3), 0.06, 0.12, "annex_bulb", top_radius=0.04, segments=10)
    prop(lab, "AnnexBulbCage", (5.1, 2.06, -3.3), (0.16, 0.02, 0.16), "metal_frame")
    lab.light("AnnexBulbLight", (5.1, 2.0, -3.3), 1.05, 6.5, color=(0.757, 0.867, 0.816), shadow=True)

    # 2. The shaft: it leaves the annex ceiling and climbs past the top of the building.
    for name, pos, size in (
        ("ShaftWest", (6.1, 4.05, -3.5), (0.12, 2.9, 1.9)),
        ("ShaftNorth", (6.82, 4.05, -4.4), (1.6, 2.9, 0.12)),
        ("ShaftSouth", (6.82, 4.05, -2.6), (1.6, 2.9, 0.12)),
        ("ShaftEast", (7.56, 4.05, -3.5), (0.12, 2.9, 1.9)),
    ):
        prop(lab, name, pos, size, "annex_wall")
    prop(lab, "ShaftGlow", (6.82, 5.42, -3.5), (1.3, 0.03, 1.6), "annex_bulb")
    prop(lab, "ShaftLedge", (6.82, 2.72, -3.5), (1.3, 0.06, 0.12), "metal_frame")
    # The cables go up it. Four of them, out of sight.
    for index in range(4):
        lab.cyl(
            "ShaftCable%d" % index,
            (6.5 + 0.16 * index, 4.0, -3.4 + 0.14 * index),
            0.012, 2.7, "cable_ink", segments=6,
        )

    # 3. The far doorway: a second frame in the annex's north wall, and the corridor behind
    # it that has no business being there - the floor runs on, the walls stop, and the end
    # is black.
    prop(lab, "FarDoorJambA", (3.58, 1.1, -5.58), (0.1, 2.2, 0.16), "metal_frame")
    prop(lab, "FarDoorJambB", (5.02, 1.1, -5.58), (0.1, 2.2, 0.16), "metal_frame")
    prop(lab, "FarDoorHead", (4.3, 2.42, -5.58), (1.5, 0.14, 0.16), "metal_frame")
    slab(lab, "FarCorridorFloor", (4.3, -0.06, -7.0), (1.8, 0.12, 2.8), "annex_floor")
    prop(lab, "FarCorridorWallA", (3.42, 1.2, -7.0), (0.1, 2.4, 2.8), "annex_wall")
    prop(lab, "FarCorridorWallB", (5.18, 1.2, -7.0), (0.1, 2.4, 2.8), "annex_wall")
    prop(lab, "FarCorridorCeiling", (4.3, 2.42, -7.0), (1.9, 0.1, 2.8), "annex_wall")
    # The end of the corridor: an unshaded black wall, so what the player walks into is the
    # surface they can see. There is no invisible blocker anywhere in this room.
    slab(lab, "FarCorridorEnd", (4.3, 1.2, -8.42), (1.9, 2.6, 0.2), "void_black")
    lab.light("FarCorridorGlow", (4.3, 1.5, -7.6), 0.3, 3.2, color=(0.62, 0.74, 0.72))

    # 4. The floor hatch the bundle ends in.
    prop(lab, "AnnexHatchRim", (6.5, 0.02, -1.5), (0.7, 0.06, 0.5), "metal_frame")
    prop(lab, "AnnexHatchVoid", (6.5, -0.02, -1.5), (0.5, 0.05, 0.32), "void_black")


def build_lights(lab: Lab) -> None:
    """Six ceiling fixtures - no ceiling over the working half, so they hang from the roof."""
    # Eight omni lights in the whole room, and no more: the Compatibility renderer shades an
    # object with eight of them, and a ninth would only be ignored per object anyway.
    fixtures = (
        ("A", (-4.9, -3.4), True),
        ("B", (-4.9, 0.9), False),
        ("C", (-1.7, -3.4), True),
        ("D", (-1.7, 0.9), False),
        ("E", (4.5, 2.9), False),
    )
    for tag, (x, z), shadow in fixtures:
        prop(lab, "CeilingFixture" + tag, (x, 3.06, z), (1.5, 0.12, 0.3), "metal_dark")
        prop(lab, "CeilingTube" + tag, (x, 2.99, z), (1.4, 0.04, 0.22), "lamp_panel")
        # The hangers that hold the fixture to a ceiling the room does not have.
        for index, dx in enumerate((-0.55, 0.55)):
            lab.cyl(("FixtureHanger%s%d" % (tag, index)).replace("-", "n"), (x + dx, 3.24, z), 0.008, 0.26, "metal_frame", segments=6)
        lab.light("CeilingLight" + tag, (x, 2.86, z), 1.45, 8.0, shadow=shadow)


def build_cables(lab: Lab) -> None:
    """Every cable in the room, from the machine it belongs to to the hatch it ends in."""
    floor = 0.035
    # --- the instrument bank, four machines, four cables ---
    bank = [
        ((6.95, 0.72, 1.02), ((6.98, 0.3, 1.02), (6.9, floor, 1.3), (6.2, floor, 1.05), (5.2, floor, 0.62))),
        ((6.95, 0.66, 2.1), ((6.98, 0.3, 2.1), (6.9, floor, 2.2), (6.0, floor, 1.5), (5.2, floor, 0.86))),
        ((6.95, 0.7, 3.2), ((6.98, 0.3, 3.2), (6.86, floor, 3.05), (5.6, floor, 1.9), (5.0, floor, 1.02))),
        ((6.95, 0.76, 4.1), ((6.98, 0.3, 4.1), (6.8, floor, 3.85), (5.4, floor, 2.6), (4.6, floor, 1.4))),
    ]
    for index, (start, tail) in enumerate(bank):
        cable_route(lab, "CableBank%d" % index, (start,) + tail, radius=0.013, sag=0.0)

    # --- the north wall's sockets and the hood's duct, running down to the floor ---
    cable_route(
        lab, "CableHood",
        ((1.95, 1.02, -5.42), (1.7, 0.12, -5.4), (1.9, floor, -4.6), (2.6, floor, -3.4), (3.2, floor, -2.0), (3.6, floor, -0.2)),
        radius=0.012, sag=0.05,
    )
    cable_route(
        lab, "CableBoard",
        ((1.4, 1.2, -5.4), (1.2, 0.1, -5.4), (1.5, floor, -4.4), (2.4, floor, -2.9), (3.1, floor, -1.0), (3.5, floor, 0.4)),
        radius=0.016, sag=0.04,
    )

    # --- the island's instruments and the bench lamp, west to east across the room ---
    cable_route(
        lab, "CableCentrifuge",
        ((-2.4, 0.95, -3.34), (-2.5, 0.1, -3.4), (-2.2, floor, -2.9), (-1.0, floor, -1.6), (0.6, floor, -0.4), (1.5, floor, 0.3)),
        radius=0.011, sag=0.06,
    )
    cable_route(
        lab, "CableBenchLamp",
        ((-7.05, 1.85, -1.9), (-7.2, 0.6, -1.95), (-7.1, floor, -1.4), (-6.0, floor, 0.3), (-3.6, floor, 0.42), (-2.2, floor, 0.4), (0.4, floor, 0.42), (1.45, floor, 0.5)),
        radius=0.010, sag=0.05,
    )
    cable_route(
        lab, "CableBalance",
        ((-6.6, 0.95, -3.9), (-6.7, 0.2, -3.7), (-6.4, floor, -2.9), (-4.4, floor, -0.6), (-2.0, floor, 0.3), (0.5, floor, 0.35)),
        radius=0.010, sag=0.06,
    )
    # The overflow: three cables that belong to nothing in particular and go the same way.
    cable_route(
        lab, "CableLoose0",
        ((-0.6, 3.0, -3.4), (-0.9, 1.6, -2.6), (-1.2, 0.5, -1.6), (-0.4, floor, -0.5), (0.9, floor, 0.15), (1.5, floor, 0.42)),
        radius=0.009, sag=0.22,
    )
    cable_route(
        lab, "CableLoose1",
        ((1.9, 1.0, -5.4), (1.6, 0.4, -5.0), (1.2, floor, -3.8), (1.4, floor, -2.0), (1.6, floor, -0.6), (1.7, floor, 0.2)),
        radius=0.009, sag=0.18,
    )
    cable_route(
        lab, "CableLoose2",
        ((4.4, 2.36, 2.8), (4.6, 1.2, 2.6), (4.2, 0.4, 2.0), (3.6, floor, 1.4), (2.4, floor, 0.9), (1.7, floor, 0.5)),
        radius=0.008, sag=0.2,
    )

    # --- the mixer's own feed, and the drop from the ceiling fixture ---
    cable_route(
        lab, "CableMixer",
        ((1.48, 1.5, 0.7), (1.6, 0.4, 0.8), (1.8, floor, 0.9), (2.2, floor, 0.6), (1.9, floor, 0.2)),
        radius=0.014, sag=0.05,
    )
    cable_route(
        lab, "CableCeilingDrop",
        ((-1.7, 2.98, 0.9), (-1.75, 2.2, 0.85), (-1.9, 1.2, 0.7), (-1.8, 0.4, 0.5), (-1.5, 0.12, 0.2), (-1.2, floor, -0.2), (0.2, floor, -0.1), (1.2, floor, 0.3)),
        radius=0.010, sag=0.3,
    )

    # --- the crossing: one run over the main aisle, under a steel ramp ---
    cable_route(
        lab, "CableCrossing",
        ((-6.9, floor, 2.7), (-4.4, floor, 2.62), (-2.9, floor, 2.55), (-2.0, floor, 1.9), (-1.9, floor, 1.1), (-1.9, floor, 0.5)),
        radius=0.012, sag=0.02,
    )
    slab(lab, "CrossingRamp", (-4.4, 0.03, 2.64), (1.5, 0.06, 0.62), "metal_frame")
    prop(lab, "CrossingRampLipA", (-5.2, 0.015, 2.64), (0.2, 0.03, 0.62), "metal_frame")
    prop(lab, "CrossingRampLipB", (-3.6, 0.015, 2.64), (0.2, 0.03, 0.62), "metal_frame")

    # --- the knot: where they all meet, and the bundle that leaves it ---
    # Slack loops piled on the floor: a cable that arrives with more length than it needs.
    for index, (cx, cz, r) in enumerate(((1.15, 0.05, 0.34), (1.35, -0.25, 0.28), (1.6, 0.55, 0.24))):
        points = []
        for step in range(13):
            angle = step / 12.0 * math.tau
            points.append((cx + r * math.cos(angle), 0.06 + 0.01 * math.sin(angle * 3), cz + r * math.sin(angle)))
        cable_route(lab, "CableCoil%d" % index, points, radius=0.011, step=0.2, sag=0.0)

    # The bundle: eight cables side by side, north along the partition to the narrow door.
    bundle = (
        (1.75, 0.4), (1.85, -0.6), (1.9, -1.4), (1.9, -2.2), (1.95, -3.0),
        (2.3, -3.1), (3.0, -3.2), (4.0, -3.3), (5.0, -3.35), (6.2, -1.6), (6.5, -1.5),
    )
    for index in range(8):
        offset = -0.05 + 0.014 * index
        points = [(x + offset, 0.045 + 0.004 * (index % 3), z + offset * 0.6) for x, z in bundle]
        mat = "cable_ink" if index % 3 else ("cable_pale" if index % 2 else "cable_oxide")
        cable_route(lab, "CableBundle%d" % index, points, radius=0.011, step=0.62, sag=0.0)

    # Out of the shaft and down its far wall, so the vertical run is visible from below.
    for index in range(3):
        cable_route(
            lab, "CableRiser%d" % index,
            ((6.9 + 0.05 * index, 0.1, -2.2), (7.4, 0.1, -3.5), (7.4, 2.0, -3.6), (7.1, 4.6, -3.6)),
            radius=0.011, step=0.7, sag=0.0,
        )


def build_interactables(lab: Lab) -> None:
    lab.interactables = [
        {
            "name": "WetBenchLook",
            "pos": (-6.75, 1.05, -3.35),
            "id": "laboratory_wet_bench",
            "inspection": "laboratory_wet_bench",
            "radius": 1.5,
            "outline": ["../../WetBenchTop", "../../GlassFlask0", "../../GlassBeaker2", "../../DryingRackTray"],
            "support": ["../../WetBenchBody"],
        },
        {
            "name": "HoodLook",
            "pos": (-4.6, 1.35, -4.7),
            "id": "laboratory_fume_hood",
            "inspection": "laboratory_fume_hood",
            "radius": 1.4,
            "outline": ["../../HoodSashFrameTop", "../../HoodSashHandle", "../../HoodDeck"],
            "support": ["../../HoodSideWest", "../../HoodSideEast"],
        },
        {
            "name": "GlassCabinetLook",
            "pos": (-1.8, 1.2, -4.85),
            "id": "laboratory_glass_cabinet",
            "inspection": "laboratory_glass_cabinet",
            "radius": 1.3,
            "outline": ["../../GlassCabinetDoorLeft", "../../GlassCabinetDoorRight", "../../GlassCabinetMullion"],
            "support": ["../../GlassCabinetBody"],
        },
        {
            "name": "LogBookLook",
            "pos": (-1.0, 1.1, -2.55),
            "id": "laboratory_log_book",
            "inspection": "laboratory_log_book",
            "radius": 1.3,
            "outline": ["../../LogBookLeft", "../../LogBookRight", "../../LogPen"],
            "support": ["../../IslandBody"],
        },
        {
            "name": "MicroscopeLook",
            "pos": (-3.3, 1.15, -2.95),
            "id": "laboratory_microscope",
            "inspection": "laboratory_microscope",
            "radius": 1.3,
            "outline": ["../../MicroBase0", "../../MicroColumn0", "../../MicroTube0", "../../MicroStage0"],
            "support": ["../../IslandTop"],
        },
        {
            "name": "MixerLook",
            "pos": (0.7, 1.35, 1.95),
            "id": "laboratory_mixer",
            "inspection": "laboratory_mixer",
            "radius": 1.7,
            "outline": ["../../MixerDrumSkin", "../../MixerMotor", "../../MixerControlBox", "../../MixerBandHigh"],
            "support": ["../../MixerCrossA", "../../MixerCrossB"],
        },
        {
            "name": "InstrumentBankLook",
            "pos": (6.6, 1.2, 2.1),
            "id": "laboratory_instruments",
            "inspection": "laboratory_instruments",
            "radius": 1.5,
            "outline": ["../../BankCentrifugeBody", "../../BankCentrifugeLid", "../../IncubatorBody", "../../ControllerBody"],
            "support": ["../../InstrumentBenchBody"],
        },
        {
            "name": "CableKnotLook",
            "pos": (1.35, 0.55, 0.35),
            "id": "laboratory_cable_knot",
            "inspection": "laboratory_cable_knot",
            "radius": 1.4,
            "outline": ["../../CableCoil0_000", "../../CableCoil1_000", "../../CableCoil2_000", "../../CableBundle0_004"],
            "support": [],
        },
        {
            "name": "AnnexDoorLook",
            "pos": (1.95, 1.15, -2.85),
            "id": "laboratory_annex_door",
            "inspection": "laboratory_annex_door",
            "radius": 1.3,
            "outline": ["../../AnnexDoorJambA", "../../AnnexDoorJambB", "../../AnnexDoorHead"],
            "support": ["../../PartitionWestA", "../../PartitionWestB"],
        },
    ]
    lab.spawns = [
        {"name": "Entry", "pos": (-4.4, 0.0, 4.4)},
        {"name": "FromAnnex", "pos": (3.4, 0.0, -2.85)},
    ]


# --- emission ------------------------------------------------------------------


def build_scene(lab: Lab) -> str:
    ext = [("Script", "res://scripts/world/location_root.gd", "1_location_root")]
    ext.append(("Script", "res://scripts/world/location_navigation.gd", "2_navigation"))
    ext.append(("PackedScene", "res://scenes/interaction/interactable.tscn", "3_interactable"))
    ext.append(("Script", "res://scenes/locations/laboratory/spinner.gd", "4_spinner"))
    ext.append(("AudioStream", "res://assets/audio/laboratory_hum.wav", "5_ambience"))
    ext.append(("Script", "res://scripts/world/ambience_player.gd", "6_ambience_player"))
    ext.append(("Material", "res://assets/materials/glass_pane.tres", "7_glass"))
    mat_ids = {}
    for index, name in enumerate(MATERIAL_ORDER):
        rid = "m%02d_%s" % (index, name)
        mat_ids[name] = rid
        ext.append(("StandardMaterial3D", "res://assets/materials/laboratory/%s.tres" % name, rid))

    subs: list[tuple[str, str, list[str]]] = []
    # Cylinder meshes are shared by every prop with the same proportions.
    cyl_ids: dict[tuple, str] = {}
    # One unit cylinder for every cable segment: its transform carries radius and length.
    unit_cyl = "CylinderMesh_cable"
    subs.append(
        (
            unit_cyl,
            "CylinderMesh",
            ["top_radius = 0.5", "bottom_radius = 0.5", "height = 1.0", "radial_segments = 8", "rings = 1"],
        )
    )

    body_index = 0
    box_rows: list[dict] = []
    for item in lab.boxes:
        row = dict(item)
        row["mesh"] = "BoxMesh_%03d" % len(box_rows)
        subs.append((row["mesh"], "BoxMesh", ["size = %s" % v3(item["size"])]))
        if item["body"]:
            row["shape"] = "BoxShape3D_%03d" % body_index
            body_index += 1
            subs.append((row["shape"], "BoxShape3D", ["size = %s" % v3(item["size"])]))
        box_rows.append(row)

    quad_rows: list[dict] = []
    for item in lab.quads:
        row = dict(item)
        row["mesh"] = "QuadMesh_%03d" % len(quad_rows)
        subs.append((row["mesh"], "QuadMesh", ["size = %s" % v2(item["size"])]))
        quad_rows.append(row)

    cyl_rows: list[dict] = []
    for item in lab.cylinders:
        key = (round(item["top"], 5), round(item["radius"], 5), round(item["height"], 5), item["segments"])
        if key not in cyl_ids:
            mesh_id = "CylinderMesh_%03d" % len(cyl_ids)
            cyl_ids[key] = mesh_id
            subs.append(
                (
                    mesh_id,
                    "CylinderMesh",
                    [
                        "top_radius = %s" % _num(item["top"]),
                        "bottom_radius = %s" % _num(item["radius"]),
                        "height = %s" % _num(item["height"]),
                        "radial_segments = %d" % item["segments"],
                    ],
                )
            )
        row = dict(item)
        row["mesh"] = cyl_ids[key]
        cyl_rows.append(row)

    env_subs = [
        (
            "Environment_1",
            "Environment",
            [
                "background_mode = 1",
                "background_color = Color(0.0314, 0.0353, 0.0392, 1)",
                "ambient_light_source = 2",
                "ambient_light_color = Color(0.5765, 0.6118, 0.6510, 1)",
                "ambient_light_energy = 0.62",
                "tonemap_mode = 2",
                "adjustment_enabled = true",
                "adjustment_saturation = 0.88",
                "adjustment_brightness = 1.02",
            ],
        )
    ]

    lines: list[str] = []
    total_subs = len(env_subs) + len(subs) + 1
    lines.append("[gd_scene load_steps=%d format=3]" % (len(ext) + total_subs))
    lines.append("")
    for kind, path, rid in ext:
        lines.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, rid))
    lines.append("")
    for sid, stype, body in env_subs + subs:
        lines.append('[sub_resource type="%s" id="%s"]' % (stype, sid))
        lines.extend(body)
        lines.append("")

    # Root and the nodes every location carries.
    lines.append('[node name="Laboratory" type="Node3D"]')
    lines.append('script = ExtResource("1_location_root")')
    lines.append('location_id = &"laboratory"')
    lines.append("")
    lines.append('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]')
    lines.append('environment = SubResource("Environment_1")')
    lines.append("")
    lines.append('[node name="Navigation" type="NavigationRegion3D" parent="."]')
    lines.append('script = ExtResource("2_navigation")')
    lines.append("")
    lines.append('[node name="Lights" type="Node3D" parent="."]')
    lines.append("")
    for light in lab.lights:
        lines.append('[node name="%s" type="OmniLight3D" parent="Lights"]' % light["name"])
        lines.append("position = %s" % v3(light["pos"]))
        lines.append("light_color = %s" % colour(light["color"] + (1.0,)))
        lines.append("light_energy = %s" % _num(light["energy"]))
        lines.append("light_specular = 0.0")
        lines.append("omni_range = %s" % _num(light["range"]))
        if light["shadow"]:
            lines.append("shadow_enabled = true")
        lines.append("")

    def material_id(mat_name: str) -> str:
        if mat_name in mat_ids:
            return mat_ids[mat_name]
        if mat_name in SHARED_MATERIALS:
            return SHARED_MATERIALS[mat_name][1]
        raise KeyError("no material named %r" % mat_name)

    def rotation_line(rotation):
        if not rotation:
            return None
        return "rotation_degrees = %s" % v3(rotation)

    for row in box_rows:
        groups = ' groups=["%s"]' % row["group"] if row["group"] else ""
        if row["body"]:
            lines.append('[node name="%s" type="StaticBody3D" parent="."%s]' % (row["name"], groups))
            lines.append("position = %s" % v3(row["pos"]))
            rot = rotation_line(row["rotation"])
            if rot:
                lines.append(rot)
            lines.append("")
            lines.append('[node name="CollisionShape3D" type="CollisionShape3D" parent="%s"]' % row["name"])
            lines.append('shape = SubResource("%s")' % row["shape"])
            lines.append("")
            lines.append('[node name="MeshInstance3D" type="MeshInstance3D" parent="%s"]' % row["name"])
            lines.append('mesh = SubResource("%s")' % row["mesh"])
            lines.append('material_override = ExtResource("%s")' % material_id(row["mat"]))
        else:
            lines.append('[node name="%s" type="MeshInstance3D" parent="."%s]' % (row["name"], groups))
            lines.append("position = %s" % v3(row["pos"]))
            rot = rotation_line(row["rotation"])
            if rot:
                lines.append(rot)
            lines.append('mesh = SubResource("%s")' % row["mesh"])
            lines.append('material_override = ExtResource("%s")' % material_id(row["mat"]))
            if row["script"]:
                lines.append('script = ExtResource("4_spinner")')
        lines.append("")

    for row in quad_rows:
        lines.append('[node name="%s" type="MeshInstance3D" parent="."]' % row["name"])
        lines.append("position = %s" % v3(row["pos"]))
        rot = rotation_line(row["rotation"])
        if rot:
            lines.append(rot)
        lines.append('mesh = SubResource("%s")' % row["mesh"])
        lines.append('material_override = ExtResource("%s")' % material_id(row["mat"]))
        lines.append("")

    for row in cyl_rows:
        lines.append('[node name="%s" type="MeshInstance3D" parent="."]' % row["name"])
        lines.append("position = %s" % v3(row["pos"]))
        rot = rotation_line(row["rotation"])
        if rot:
            lines.append(rot)
        lines.append('mesh = SubResource("%s")' % row["mesh"])
        lines.append('material_override = ExtResource("%s")' % material_id(row["mat"]))
        lines.append("")

    # Cables: each segment is the shared unit cylinder with radius and length in its basis.
    lines.append('[node name="Cables" type="Node3D" parent="."]')
    lines.append("")
    for cable in lab.cables:
        transform = tube_along(cable["p0"], cable["p1"], cable["radius"])
        if transform is None:
            continue
        lines.append('[node name="%s" type="MeshInstance3D" parent="Cables"]' % cable["name"])
        lines.append("transform = Transform3D(%s)" % ", ".join(_num(v) for v in transform))
        lines.append('mesh = SubResource("%s")' % unit_cyl)
        lines.append('material_override = ExtResource("%s")' % mat_ids[cable["mat"]])
        lines.append("")

    lines.append('[node name="Ambience" type="AudioStreamPlayer" parent="."]')
    lines.append('stream = ExtResource("5_ambience")')
    lines.append('script = ExtResource("6_ambience_player")')
    lines.append("")
    lines.append('[node name="Interactables" type="Node3D" parent="."]')
    lines.append("")
    for item in lab.interactables:
        lines.append('[node name="%s" parent="Interactables" instance=ExtResource("3_interactable")]' % item["name"])
        lines.append("position = %s" % v3(item["pos"]))
        lines.append('interact_id = &"%s"' % item["id"])
        if item.get("inspection"):
            lines.append('inspection_id = &"%s"' % item["inspection"])
        lines.append("radius = %s" % _num(item["radius"]))
        if item.get("support"):
            lines.append("support_paths = PackedStringArray(%s)" % ", ".join('"%s"' % p for p in item["support"]))
        if item.get("outline"):
            lines.append("outline_paths = PackedStringArray(%s)" % ", ".join('"%s"' % p for p in item["outline"]))
        lines.append("")

    lines.append('[node name="SpawnPoints" type="Node3D" parent="."]')
    lines.append("")
    for spawn in lab.spawns:
        lines.append('[node name="%s" type="Marker3D" parent="SpawnPoints" groups=["spawn_point"]]' % spawn["name"])
        lines.append("position = %s" % v3(spawn["pos"]))
        lines.append("")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the laboratory materials and scene.")
    parser.add_argument("--check", action="store_true", help="fail if the files on disk differ")
    args = parser.parse_args()

    lab = Lab()
    build_room(lab)
    build_wet_bench(lab)
    build_north_wall(lab)
    build_island(lab)
    build_instruments(lab)
    build_mixer(lab)
    build_annex(lab)
    build_lights(lab)
    build_cables(lab)
    build_interactables(lab)

    scene = build_scene(lab)

    stale: list[str] = []
    for name in MATERIAL_ORDER:
        path = os.path.join(MATERIAL_DIR, name + ".tres")
        text = material_tres(name)
        if args.check:
            current = ""
            if os.path.exists(path):
                with open(path, "r", encoding="utf-8") as handle:
                    current = handle.read()
            if current != text:
                stale.append(path)
        else:
            os.makedirs(MATERIAL_DIR, exist_ok=True)
            with open(path, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(text)

    os.makedirs(SCENE_DIR, exist_ok=True)
    if args.check:
        current = ""
        if os.path.exists(SCENE_PATH):
            with open(SCENE_PATH, "r", encoding="utf-8") as handle:
                current = handle.read()
        if current != scene:
            stale.append(SCENE_PATH)
    else:
        with open(SCENE_PATH, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(scene)

    print(
        "laboratory: %d boxes, %d quads, %d cylinders, %d cable segments, %d lights, %d interactables"
        % (
            len(lab.boxes),
            len(lab.quads),
            len(lab.cylinders),
            len(lab.cables),
            len(lab.lights),
            len(lab.interactables),
        )
    )
    if args.check:
        if stale:
            for path in stale:
                print("STALE: %s" % os.path.relpath(path, ROOT), file=sys.stderr)
            return 1
        print("laboratory materials and scene match the builder")
        return 0
    print("wrote %d materials and %s" % (len(MATERIAL_ORDER), os.path.relpath(SCENE_PATH, ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
