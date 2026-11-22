#!/usr/bin/env python3
"""Inside the building under construction (建造中的大楼): `scenes/locations/site_interior/`.

The yard's construction site (`scenes/environment/props/playground_art/source/
construction_site.py`) is scenery seen over a hoarding. This is the room behind its porch
door, as a location of its own: an egg-shaped pour of raw concrete, far larger inside than
the ellipsoid is outside, seen the way the dream annex's stable is seen (#196, #200 pushed
toward the psychedelic):

* the back of the shell rises in stepped, unfinished lifts and leans in over the room; the
  side toward the camera is poured only to a knee-high stub, starter bars sprouting from it;
* stripes of colour flow up the concrete and the tie holes glow (`site_trip_paint`);
* the floor is a slowly turning op-art spiral (`site_trip_floor`), and outside the stub
  walls there is no ground, only the same spiral far below (`Vortex`);
* a scaffold tower stands in a column of rising coloured light (`site_trip_light`), its
  ladder climbing out of sight; the six marbles left on the roof deck orbit it, grown to
  the size of footballs (`site_trip_marble`);
* the chalk star from the roof deck is drawn on the floor, and the padlock key of the
  hoarding gate lies in its middle;
* `SiteTrip` (`site_trip.gd`, `site_trip_haze.gdshader`) bends the whole picture: a
  rainbow split, a kaleidoscope folding in at the edges, colours drifting round the wheel,
  stronger the closer the protagonist stands to the light.

Gameplay is three interactables: the porch door back out (closed until the key is held:
`StoryFlags.SITE_GATE_KEY`), the key (`site_key.gd`; its inspection sets the flag) and the
ladder. Every line they show is the owner's to write and is still a placeholder.

Each shaped mesh is its own text ArrayMesh under `meshes/`, like the construction site's,
so the scene stays far under the release's 1 MiB budget for a scene.

    python3 tools/build_site_interior.py           # write the scene and its meshes
    python3 tools/build_site_interior.py --check   # fail if they are not what this writes
"""
from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

import stable_meshes as sm  # also puts the site mesh kit on the path
from site_mesh import box, cylinder, fbm, noise, rand, smoothstep, tube

ROOT = Path(__file__).resolve().parent.parent
REL = "scenes/locations/site_interior"
RES = f"res://{REL}"
SCENE = ROOT / REL / "site_interior.tscn"
MESH_DIR = ROOT / REL / "meshes"
SHADERS = "res://assets/shaders/school"

# The room, in the location's own frame: the floor is an ellipse, x across, z deep.
AX, BZ = 6.0, 7.5
THICK = 0.28
# The scaffold tower and its column of light stand back and to the left of the middle,
# so the follow camera (which looks from +x +z) sees the whole of it.
COLUMN = (-1.4, 0.0, -1.8)
# The chalk star and the key in it.
KEY = (-3.0, 0.0, 3.2)
# The porch door is in the +x wall, facing in; this half-angle is left open for it.
DOOR_HALF = 0.09
SEGMENTS = 26
SPAWN = (4.7, 0.0, 0.0)
STUB = 1.05
TALL = 6.6
LEAN_FROM, LEAN_C = 1.2, 9.0
JOINTS = (2.75, 5.25)

CONCRETE = (0.63, 0.61, 0.58)
CONCRETE_DARK = (0.38, 0.36, 0.35)
PLY = (0.77, 0.63, 0.44)
DOOR_BLUE = (0.27, 0.38, 0.48)
BRASS = (0.86, 0.64, 0.24)
CHALK = (0.95, 0.94, 0.9)
STEEL = (0.42, 0.43, 0.44)


def v3(p) -> str:
    return "Vector3(" + ", ".join(f"{round(v, 4):g}" for v in p) + ")"


def colour(c, a=1.0) -> str:
    return "Color(" + ", ".join(f"{round(v, 4):g}" for v in (*c, a)) + ")"


class Scene:
    """Just enough of a text scene: ext resources, sub resources, nodes, mesh files."""

    def __init__(self):
        self.ext: dict[str, str] = {}
        self.subs: list[str] = []
        self.nodes: list[str] = []
        self.files: dict[str, str] = {}

    def res(self, kind: str, path: str, rid: str) -> str:
        self.ext.setdefault(rid, f'[ext_resource type="{kind}" path="{path}" id="{rid}"]')
        return f'ExtResource("{rid}")'

    def sub(self, kind: str, rid: str, **props) -> str:
        body = "".join(f"{k} = {v}\n" for k, v in props.items())
        self.subs.append(f'[sub_resource type="{kind}" id="{rid}"]\n{body}')
        return f'SubResource("{rid}")'

    def mesh(self, name: str, mesh) -> str:
        file_name = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name).lower() + ".tres"
        if file_name in self.files:
            raise SystemExit(f"two interior meshes would share {file_name}")
        self.files[file_name] = f'[gd_resource type="ArrayMesh" format=3]\n\n[resource]\n_surfaces = {mesh.surface()}\n'
        return self.res("ArrayMesh", f"{RES}/meshes/{file_name}", f"mesh_{file_name.removesuffix('.tres')}")

    def shader_mat(self, rid: str, shader: str, **params) -> str:
        ref = self.res("Shader", f"{SHADERS}/{shader}.gdshader", f"sh_{shader}")
        props = {"shader": ref}
        props.update({f"shader_parameter/{k}": v for k, v in params.items()})
        return self.sub("ShaderMaterial", rid, **props)

    def node(self, name: str, parent: str | None, kind: str | None = None, *, instance: str | None = None,
             groups: list[str] | None = None, **props) -> str:
        head = f'[node name="{name}"'
        if kind:
            head += f' type="{kind}"'
        if parent is not None:
            head += f' parent="{parent}"'
        if instance:
            head += f" instance={instance}"
        if groups:
            head += " groups=[" + ", ".join(f'"{g}"' for g in groups) + "]"
        self.nodes.append(head + "]\n" + "".join(f"{k} = {v}\n" for k, v in props.items()))
        if parent is None:
            return "."
        return name if parent == "." else f"{parent}/{name}"

    def emit(self) -> str:
        steps = 1 + len(self.ext) + len(self.subs)
        return (f"[gd_scene load_steps={steps} format=3]\n\n" + "\n".join(self.ext.values()) + "\n\n"
                + "\n".join(self.subs) + "\n" + "\n".join(self.nodes))


# --- shapes -----------------------------------------------------------------------------


def lean(y: float) -> float:
    """How far in the shell has curved at height y (1 = straight up)."""
    if y <= LEAN_FROM:
        return 1.0
    return math.sqrt(max(0.05, 1.0 - ((y - LEAN_FROM) / LEAN_C) ** 2))


def wall_point(theta: float, y: float, out: float = 0.0):
    s = lean(y)
    nx, nz = math.cos(theta) / AX, math.sin(theta) / BZ
    k = math.hypot(nx, nz)
    return (AX * math.cos(theta) * s + out * nx / k, y, BZ * math.sin(theta) * s + out * nz / k)


def wall_height(theta: float, i: int) -> float:
    """Tall at the back, a stub on the camera's side; each lift a little different."""
    d = (math.cos(theta) + math.sin(theta)) / math.sqrt(2.0)
    tall = 1.0 - smoothstep(-0.45, 0.05, d)
    jitter = (rand(i, 31) - 0.5) * (0.5 * tall + 0.12)
    return STUB + TALL * tall + jitter


def concrete(p, seed=0, *, grime=True):
    x, y, z = p
    f = fbm(x * 0.7 + z * 0.4, y * 0.9 + z * 0.3, seed)
    c = sm.mix(CONCRETE, CONCRETE_DARK, 0.35 * f)
    if grime:
        c = sm.mix(c, CONCRETE_DARK, 0.45 * (1.0 - smoothstep(0.0, 0.5, y)))
    for joint in JOINTS:
        if abs(y - joint) < 0.035:
            c = sm.mix(c, (0.2, 0.19, 0.2), 0.8)
    return (*c, 1.0)


def wall_segment(theta0: float, theta1: float, height: float, i: int):
    steps = 4
    thetas = [theta0 + (theta1 - theta0) * k / steps for k in range(steps + 1)]
    tall = height > 2.5
    tops = []
    for k, _ in enumerate(thetas):
        broken = (noise(i * 3.1 + k * 0.7, height, 5) - 0.5) * (0.45 if tall else 0.1)
        tops.append(height + broken)
    levels = [0.0, 0.05, 1.2] + [y for j in JOINTS for y in (j - 0.07, j - 0.03, j + 0.03, j + 0.07)]
    levels += [height * f for f in (0.62, 0.8)]
    levels = sorted({round(y, 3) for y in levels if y < min(tops) - 0.08})
    m = sm.PaintMesh()
    for out, inward in ((0.0, True), (THICK, False)):
        rows, cols = [], []
        for y in levels + ["top"]:
            row = []
            for k, theta in enumerate(thetas):
                yy = tops[k] if y == "top" else y
                row.append(wall_point(theta, yy, out))
            rows.append(row)
            cols.append([concrete(p, i) for p in row])
        centers = [(0.0, r[0][1], 0.0) for r in rows]
        m.grid(rows, centers=centers, colors=cols, inward=inward)
    # The broken top of the lift, and the two cut ends.
    inner = [wall_point(t, tops[k]) for k, t in enumerate(thetas)]
    outer = [wall_point(t, tops[k], THICK) for k, t in enumerate(thetas)]
    m.grid([inner, outer], outward=(0, 1, 0), colors=[[concrete(p, i, grime=False) for p in inner]] * 2)
    for theta, top, sign in ((theta0, tops[0], -1), (theta1, tops[-1], 1)):
        a, b = wall_point(theta, 0.0), wall_point(theta, 0.0, THICK)
        c, d = wall_point(theta, top, THICK), wall_point(theta, top)
        tangent = (-math.sin(theta) * AX * sign, 0.0, math.cos(theta) * BZ * sign)
        m.mark()
        m.polygon([a, b, c, d], tangent)
        m.paint(lambda p, n: concrete(p, i))
    return m, tops


def floor_mesh():
    """The slab: an ellipse a little wider than the walls, with a skirt down its edge."""
    rings, sides = 10, 72
    rows, cols = [], []
    for r in range(rings + 1):
        f = r / rings
        row = [(math.cos(a) * (AX + 0.3) * f, 0.0, math.sin(a) * (BZ + 0.3) * f)
               for a in (k * math.tau / sides for k in range(sides))]
        rows.append(row)
        cols.append([(*sm.mix(CONCRETE, CONCRETE_DARK, 0.55 * fbm(p[0] * 0.5, p[2] * 0.5, 9)), 1.0) for p in row])
    m = sm.PaintMesh().grid(rows, wrap=True, outward=(0, 1, 0), colors=cols)
    rim = rows[-1]
    skirt = [rim, [(x, -0.6, z) for x, _, z in rim]]
    m.grid(skirt, wrap=True, centers=[(0, 0, 0), (0, -0.6, 0)],
           colors=[[(*CONCRETE_DARK, 1.0)] * sides] * 2)
    return m


def disc(radius, rings=12, sides=64):
    rows = [[(math.cos(a) * radius * r / rings, 0.0, math.sin(a) * radius * r / rings)
             for a in (k * math.tau / sides for k in range(sides))] for r in range(rings + 1)]
    return sm.PaintMesh().grid(rows, wrap=True, outward=(0, 1, 0))


def door():
    frame = sm.PaintMesh()
    for z in (-0.6, 0.6):
        frame.add(box((0.14, 2.3, 0.1), (0.0, 1.15, z), bevel=0.01), (*PLY, 1.0))
    frame.add(box((0.14, 0.12, 1.3), (0.0, 2.36, 0.0), bevel=0.01), (*PLY, 1.0))
    frame.add(box((0.3, 0.04, 1.3), (0.06, 0.02, 0.0)), (*CONCRETE_DARK, 1.0))
    leaf = sm.PaintMesh()
    leaf.add(box((0.05, 2.18, 1.08), (-0.02, 1.11, 0.0), bevel=0.008), (*DOOR_BLUE, 1.0))
    leaf.add(box((0.02, 0.5, 0.36), (-0.05, 1.62, 0.0)), (0.14, 0.2, 0.24, 1.0))
    leaf.add(box((0.06, 0.03, 0.16), (-0.07, 1.02, 0.36)), (*STEEL, 1.0))
    return frame, leaf


def scaffold():
    tubes, boards, ladder = sm.PaintMesh(), sm.PaintMesh(), sm.PaintMesh()
    corners = [(-0.8, -0.8), (0.8, -0.8), (0.8, 0.8), (-0.8, 0.8)]
    for x, z in corners:
        tubes.add(cylinder(0.035, 9.6, 8, center=(x, 4.8, z)), (*STEEL, 1.0))
    for y in (0.15, 2.0, 4.0, 6.0, 8.0):
        for (x0, z0), (x1, z1) in zip(corners, corners[1:] + corners[:1]):
            tubes.add(tube([(x0, y, z0), (x1, y, z1)], 0.03, 6), (*STEEL, 1.0))
    for j, y in enumerate((0.15, 2.0, 4.0, 6.0)):
        (x0, z0), (x1, z1) = corners[j % 4], corners[(j + 1) % 4]
        tubes.add(tube([(x0, y, z0), (x1, y + 2.0, z1)], 0.028, 6), (*STEEL, 1.0))
    for y in (2.0, 4.0):
        boards.add(box((1.66, 0.05, 1.3), (-0.05, y + 0.06, -0.15), bevel=0.01), (*PLY, 1.0))
        boards.add(box((1.66, 0.15, 0.03), (-0.05, y + 0.16, 0.8)), (0.9, 0.7, 0.2, 1.0))
    top = 11.5
    for z in (-0.22, 0.22):
        ladder.add(box((0.05, top, 0.05), (0.96, top / 2, z)), (*STEEL, 1.0))
    for k in range(int((top - 0.3) / 0.3)):
        ladder.add(cylinder(0.016, 0.44, 6, center=(0.96, 0.3 + k * 0.3, 0.0), axis="z"), (*STEEL, 1.0))
    return tubes, boards, ladder


def starter_bars(segments):
    """Rebar sprouting from the stub walls, its tips free to sway (vertex alpha = sway)."""
    bars = sm.PaintMesh()
    count = 0
    for theta0, theta1, tops in segments:
        if max(tops) > 2.0:
            continue
        span = (theta1 - theta0) * (AX + BZ) / 2
        n = max(1, int(span / 0.42))
        for k in range(n):
            t = theta0 + (theta1 - theta0) * (k + 0.5) / n
            base = wall_point(t, STUB - 0.05, THICK / 2)
            length = 0.5 + 0.6 * rand(count, 17)
            lean_x, lean_z = (rand(count, 3) - 0.5) * 0.18, (rand(count, 5) - 0.5) * 0.18
            path = [(base[0] + lean_x * f * f, base[1] + length * f, base[2] + lean_z * f * f)
                    for f in (0.0, 0.35, 0.7, 1.0)]
            bars.mark()
            bars.merge(tube(path, 0.012, 5))
            bottom = base[1]
            bars.paint(lambda p, nrm, b=bottom, ln=length: (0.55, 0.32, 0.22, max(0.0, min(1.0, (p[1] - b) / ln))))
            count += 1
    return bars


def chalk_star():
    star = sm.PaintMesh()
    y = 0.012
    for turn in (0.0, math.pi):
        tips = [(1.25 * math.cos(turn + j * math.tau / 3), y, 1.25 * math.sin(turn + j * math.tau / 3))
                for j in range(3)]
        for j, start in enumerate(tips):
            star.add(tube([start, tips[(j + 1) % 3]], 0.022, 5), (*CHALK, 1.0))
    ring = [(1.45 * math.cos(a), y, 1.45 * math.sin(a)) for a in (k * math.tau / 48 for k in range(48))]
    star.add(tube(ring, 0.018, 5, closed=True), (*CHALK, 1.0))
    return star


def padlock_key():
    """The hoarding padlock's key, lying flat: bow, blade and bits, a little too large."""
    scale = (1.6, 1.6, 1.6)
    bow = sm.PaintMesh()
    ring = [(0.075 * math.cos(a), 0.016, 0.075 * math.sin(a)) for a in (k * math.tau / 20 for k in range(20))]
    bow.add(tube(ring, 0.017, 6, closed=True), (*BRASS, 1.0), scale=scale)
    blade = sm.PaintMesh()
    blade.add(box((0.25, 0.026, 0.032), (0.2, 0.016, 0.0), bevel=0.004), (*BRASS, 1.0), scale=scale)
    for x, depth in ((0.27, 0.06), (0.305, 0.045)):
        blade.add(box((0.026, 0.026, depth), (x, 0.016, -0.016 - depth / 2), bevel=0.003), (*BRASS, 1.0),
                  scale=scale)
    return bow, blade


# --- the scene --------------------------------------------------------------------------


def build() -> Scene:
    s = Scene()
    location = s.res("Script", "res://scripts/world/location_root.gd", "location")
    navigation = s.res("Script", "res://scripts/world/location_navigation.gd", "navigation")
    ambience = s.res("Script", "res://scripts/world/ambience_player.gd", "ambience")
    hum = s.res("AudioStream", "res://assets/audio/laboratory_hum.wav", "hum")
    exit_scene = s.res("PackedScene", "res://scenes/interaction/location_exit.tscn", "exit")
    tap_target = s.res("PackedScene", "res://scenes/interaction/interactable.tscn", "tap_target")
    key_script = s.res("Script", f"{RES}/site_key.gd", "key_script")
    trip_script = s.res("Script", f"{RES}/site_trip.gd", "trip_script")

    cx, _, cz = COLUMN
    centre = v3(COLUMN)
    env = s.sub("Environment", "TripEnvironment",
                background_mode="1", background_color=colour((0.07, 0.04, 0.12)),
                ambient_light_source="2", ambient_light_color=colour((0.66, 0.58, 0.78)),
                ambient_light_energy="0.55", tonemap_mode="2", tonemap_exposure="0.95",
                glow_enabled="true", glow_intensity="0.7", glow_bloom="0.05", glow_hdr_threshold="0.9")
    wall_mat = s.shader_mat("Mat_wall", "site_trip_paint", band_mix="0.62", band_pitch="0.85", dots="1.0",
                            glow="0.3", band_centre=centre)
    door_mat = s.shader_mat("Mat_door", "site_trip_paint", band_mix="0.78", band_pitch="0.22", glow="0.2",
                            band_twist="0.4", palette_shift="0.4", band_centre=centre)
    plain_mat = s.shader_mat("Mat_plain", "site_trip_paint", band_mix="0.18", band_pitch="1.6", glow="0.1",
                             band_centre=centre)
    stripe_mat = s.shader_mat("Mat_stripes", "site_trip_paint", band_mix="0.92", band_pitch="0.32",
                              band_twist="0.0", band_speed="0.3", glow="0.45", band_centre=centre)
    bar_mat = s.shader_mat("Mat_bars", "site_trip_paint", band_mix="0.9", band_pitch="0.14", band_twist="0.0",
                           band_speed="0.5", glow="0.5", sway="0.07", band_centre=centre)
    chalk_mat = s.shader_mat("Mat_chalk", "site_trip_paint", band_mix="0.35", band_pitch="0.6", glow="0.9",
                             band_centre=v3(KEY))
    key_mat = s.shader_mat("Mat_key", "site_trip_paint", band_mix="0.0", pulse="0.9", glow="0.0",
                           roughness_value="0.3", band_centre=v3(KEY))
    floor_mat = s.shader_mat("Mat_floor", "site_trip_floor", centre=centre, contrast="0.58", glow="0.16",
                             fade_radius="7.2")
    vortex_mat = s.shader_mat("Mat_vortex", "site_trip_floor", centre=centre, contrast="1.0", glow="1.1",
                              fade_radius="44.0", arms="6.0", twist="3.0", spin="0.03")
    light_mat = s.shader_mat("Mat_light", "site_trip_light", strength="0.55", height="14.0")
    haze_mat = s.shader_mat("Mat_haze", "site_trip_haze", trip="0.0")

    root = s.node("SiteInterior", None, "Node3D", script=location, location_id='&"site_interior"')
    s.node("WorldEnvironment", root, "WorldEnvironment", environment=env)
    s.node("Sun", root, "DirectionalLight3D", rotation_degrees=v3((-60, -30, 0)),
           light_color=colour((0.8, 0.7, 1.0)), light_energy="0.45", shadow_enabled="true",
           directional_shadow_max_distance="30")
    s.node("Navigation", root, "NavigationRegion3D", script=navigation)
    s.node("Ambience", root, "AudioStreamPlayer", stream=hum, script=ambience, volume_db="-30",
           target_db="-25", pitch_scale="0.62")

    # The slab, and the spiral far below it where the ground should be.
    s.node("Slab", root, "StaticBody3D", collision_layer="1", collision_mask="0")
    s.node("Collision", "Slab", "CollisionShape3D", position=v3((0, -0.1, 0)),
           shape=s.sub("BoxShape3D", "Shape_slab", size=v3((2 * AX + 0.6, 0.2, 2 * BZ + 0.6))))
    s.node("Surface", "Slab", "MeshInstance3D", mesh=s.mesh("Slab", floor_mesh()), material_override=floor_mat)
    s.node("Vortex", root, "MeshInstance3D", position=v3((0, -6.0, 0)), mesh=s.mesh("Vortex", disc(45.0)),
           material_override=vortex_mat, cast_shadow="0")

    # The shell, lift by lift. Every lift is a body of its own so the occluder fader can
    # take any one of them away; only the stubs on the camera's side ever need it.
    segments = []
    span = math.tau - 2 * DOOR_HALF
    s.node("Shell", root, "Node3D")
    for i in range(SEGMENTS):
        theta0 = DOOR_HALF + span * i / SEGMENTS
        theta1 = DOOR_HALF + span * (i + 1) / SEGMENTS
        height = wall_height((theta0 + theta1) / 2, i)
        mesh, tops = wall_segment(theta0, theta1, height, i)
        segments.append((theta0, theta1, tops))
        name = f"Lift{i:02d}"
        body = s.node(name, "Shell", "StaticBody3D", groups=["camera_occluder"], collision_layer="1",
                      collision_mask="0")
        a, b = wall_point(theta0, 0.0), wall_point(theta1, 0.0)
        mid_theta = (theta0 + theta1) / 2
        mid = wall_point(mid_theta, 0.0, THICK / 2)
        chord = math.dist((a[0], a[2]), (b[0], b[2]))
        solid = min(min(tops), 2.4)
        yaw = math.degrees(math.atan2(-(b[2] - a[2]), b[0] - a[0]))
        s.node("Solid", body, "CollisionShape3D", position=v3((mid[0], solid / 2, mid[2])),
               rotation_degrees=v3((0, yaw, 0)),
               shape=s.sub("BoxShape3D", f"Shape_lift{i:02d}", size=v3((chord + 0.14, solid, THICK + 0.06))))
        s.node("Pour", body, "MeshInstance3D", mesh=s.mesh(f"Lift{i:02d}", mesh), material_override=wall_mat)
    s.node("StarterBars", "Shell", "MeshInstance3D", mesh=s.mesh("StarterBars", starter_bars(segments)),
           material_override=bar_mat, cast_shadow="0")

    # The porch door, from inside: the way back out.
    frame, leaf = door()
    s.node("Door", root, "StaticBody3D", position=v3((AX, 0, 0)), collision_layer="1", collision_mask="0")
    s.node("Solid", "Door", "CollisionShape3D", position=v3((0.08, 1.2, 0)),
           shape=s.sub("BoxShape3D", "Shape_door", size=v3((0.32, 2.4, 1.44))))
    s.node("Frame", "Door", "MeshInstance3D", mesh=s.mesh("DoorFrame", frame), material_override=plain_mat)
    s.node("Leaf", "Door", "MeshInstance3D", mesh=s.mesh("DoorLeaf", leaf), material_override=door_mat)
    s.node("DoorLight", "Door", "OmniLight3D", position=v3((-0.6, 2.3, 0)), light_color=colour((1, 0.78, 0.52)),
           light_energy="0.7", omni_range="3.2")

    # The scaffold tower in its column of light, and the marbles going round it.
    tubes, boards, ladder = scaffold()
    s.node("Scaffold", root, "StaticBody3D", position=centre, collision_layer="1", collision_mask="0")
    s.node("Solid", "Scaffold", "CollisionShape3D", position=v3((0, 1.2, 0)),
           shape=s.sub("BoxShape3D", "Shape_scaffold", size=v3((1.84, 2.4, 1.84))))
    s.node("Tubes", "Scaffold", "MeshInstance3D", mesh=s.mesh("ScaffoldTubes", tubes), material_override=stripe_mat)
    s.node("Boards", "Scaffold", "MeshInstance3D", mesh=s.mesh("ScaffoldBoards", boards),
           material_override=plain_mat)
    s.node("Ladder", "Scaffold", "MeshInstance3D", mesh=s.mesh("ScaffoldLadder", ladder),
           material_override=stripe_mat)
    s.node("LightColumn", root, "MeshInstance3D", position=centre,
           mesh=s.mesh("LightColumn", cylinder(1.35, 14.0, 40, caps=False, center=(0, 7.02, 0))),
           material_override=light_mat, cast_shadow="0")
    s.node("ColumnLight", root, "OmniLight3D", position=v3((cx, 3.2, cz)), light_color=colour((1, 0.9, 1)),
           light_energy="2.2", omni_range="8.5")
    marble = s.mesh("Marble", sm.ellipsoid((0, 0, 0), (1, 1, 1), rings=14, sides=24))
    s.node("Marbles", root, "Node3D", position=centre)
    orbits = ((2.7, 2.7, 0.045, 0.00, 0.42, 0.02), (3.3, 3.6, 0.032, 0.21, 0.55, 0.16),
              (2.4, 4.6, -0.05, 0.43, 0.36, 0.33), (3.5, 2.9, -0.028, 0.6, 0.5, 0.5),
              (2.9, 4.1, 0.038, 0.77, 0.6, 0.66), (3.1, 5.3, -0.04, 0.9, 0.45, 0.82))
    for i, (radius, height, rate, phase, size, hue) in enumerate(orbits):
        mat = s.shader_mat(f"Mat_marble{i}", "site_trip_marble", orbit_radius=f"{radius}", orbit_height=f"{height}",
                           orbit_rate=f"{rate}", phase=f"{phase}", size=f"{size}", hue=f"{hue}")
        reach = radius + size + 0.2
        s.node(f"Marble_{i}", "Marbles", "MeshInstance3D", mesh=marble, material_override=mat, cast_shadow="0",
               custom_aabb=f"AABB({-reach:g}, {height - size - 0.5:g}, {-reach:g}, {2 * reach:g}, "
                           f"{2 * size + 1.0:g}, {2 * reach:g})")

    # The chalk star from the roof deck, and the key in the middle of it.
    s.node("Chalk", root, "MeshInstance3D", position=v3(KEY), mesh=s.mesh("Chalk", chalk_star()),
           material_override=chalk_mat, cast_shadow="0")
    bow, blade = padlock_key()
    s.node("Key", root, "Node3D", position=v3((KEY[0], 0.0, KEY[2])), rotation_degrees=v3((0, 25, 0)))
    s.node("Bow", "Key", "MeshInstance3D", position=v3((-0.25, 0, 0)), mesh=s.mesh("KeyBow", bow),
           material_override=key_mat, cast_shadow="0")
    s.node("Blade", "Key", "MeshInstance3D", position=v3((-0.25, 0, 0)), mesh=s.mesh("KeyBlade", blade),
           material_override=key_mat, cast_shadow="0")
    s.node("Glint", "Key", "OmniLight3D", position=v3((0, 0.45, 0)), light_color=colour((1, 0.8, 0.4)),
           light_energy="0.9", omni_range="2.0")

    # Three bare lamps on long flexes, in three colours that never agree.
    for i, ((x, z), tint) in enumerate((((2.6, -3.2), (1, 0.3, 0.8)), ((-4.0, -0.6), (0.3, 0.9, 1)),
                                        ((1.4, 4.4), (1, 0.7, 0.3)))):
        lamp = s.node(f"Lamp{i}", root, "Node3D", position=v3((x, 0, z)))
        low = 2.7 + 0.3 * i
        flex = sm.PaintMesh().add(tube([(0, 12.0, 0), (0, low + 0.12, 0)], 0.008, 4), (0.1, 0.1, 0.1, 1.0))
        flex.add(sm.ellipsoid((0, low, 0), (0.07, 0.1, 0.07), rings=6, sides=10), (*tint, 1.0))
        s.node("Flex", lamp, "MeshInstance3D", mesh=s.mesh(f"Lamp{i}", flex), material_override=plain_mat,
               cast_shadow="0")
        s.node("Light", lamp, "OmniLight3D", position=v3((0, low - 0.1, 0)), light_color=colour(tint),
               light_energy="1.4", omni_range="6.0")

    trip = s.node("SiteTrip", root, "CanvasLayer", groups=["world_filter"], layer="-3", visible="false",
                  script=trip_script, column=centre)
    s.node("Sheet", trip, "ColorRect", material=haze_mat, anchors_preset="15", anchor_right="1.0",
           anchor_bottom="1.0", grow_horizontal="2", grow_vertical="2", mouse_filter="2")

    s.node("SpawnPoints", root, "Node3D")
    s.node("FromPorch", "SpawnPoints", "Marker3D", groups=["spawn_point"], position=v3(SPAWN),
           rotation_degrees=v3((0, 90, 0)))

    s.node("Interactables", root, "Node3D")
    s.node("PorchDoor", "Interactables", instance=exit_scene, position=v3((AX - 0.55, 0.9, 0)),
           interact_id='&"site_interior_porch_door"', prompt_key='"prompt.site_porch_out"', radius="1.4",
           outline_paths='PackedStringArray("../../Door/Leaf", "../../Door/Frame")',
           support_paths='PackedStringArray("../../Door")',
           destination_scene='"res://scenes/locations/playground/playground.tscn"',
           destination_spawn='&"FromSite"', destination_id='&"playground"',
           required_flag='&"site_gate_key"', blocked_inspection_id='&"site_porch_locked"')
    s.node("KeyLook", "Interactables", instance=tap_target, script=key_script,
           position=v3((KEY[0], 0.3, KEY[2])), interact_id='&"site_interior_key"', inspection_id='&"site_key"',
           radius="1.2", outline_paths='PackedStringArray("../../Key/Bow", "../../Key/Blade")')
    s.node("LadderLook", "Interactables", instance=tap_target, position=v3((cx + 1.55, 1.0, cz)),
           interact_id='&"site_interior_ladder"', inspection_id='&"site_ladder"', radius="1.3",
           outline_paths='PackedStringArray("../../Scaffold/Ladder")',
           support_paths='PackedStringArray("../../Scaffold")')
    return s


def outputs() -> dict[Path, str]:
    s = build()
    files = {SCENE: s.emit()}
    for name, text in s.files.items():
        files[MESH_DIR / name] = text
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail if the files differ from what this writes")
    args = parser.parse_args()
    files = outputs()
    stale = {p for p in MESH_DIR.glob("*.tres")} - set(files) if MESH_DIR.exists() else set()
    if args.check:
        bad = [p for p, text in files.items() if not p.exists() or p.read_text() != text] + sorted(stale)
        if bad:
            print("site interior is stale; run python3 tools/build_site_interior.py:")
            for p in bad:
                print("  ", p.relative_to(ROOT))
            return 1
        print(f"site interior up to date ({len(files)} files)")
        return 0
    MESH_DIR.mkdir(parents=True, exist_ok=True)
    for p in stale:
        p.unlink()
    for p, text in files.items():
        p.write_text(text)
    size = SCENE.stat().st_size
    meshes = sum(p.stat().st_size for p in MESH_DIR.glob("*.tres"))
    print(f"wrote {SCENE.relative_to(ROOT)} ({size:,} bytes) and {len(files) - 1} meshes ({meshes:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
