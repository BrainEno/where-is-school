#!/usr/bin/env python3
"""The container yard (集装箱堆场): `scenes/locations/container_yard/`.

Past the yard's blue container, through the chain-link behind it, the essay's candidate
space (docs/NARRATIVE_BIBLE.md, docs/MAP_PLAN.md): a car park that is mostly shipping
containers, which you walk through by the gaps between them.

* Blue and red containers, very rarely an orange one, in stacks of one, two and three, so
  the roofs stand at different heights. Seen from above the rows and their gaps are a maze:
  lanes that run the width of the yard, a few gaps from one lane to the next, and two
  containers turned across a gap that leave dead-end pockets.
* Stacked truck tyres are the stairs: one flight from the apron onto a single container,
  a second flight on that roof up onto a double stack.
* Long timber planks, some level and some sloping, link the roofs; they sag and sway
  (`plank_sway.gdshader`) while their colliders stay put.
* An apron with faded parking-bay paint by the way in, floodlight masts, the precast back
  wall of the yard; past it and the west fence the rest of the terminal (more stacks, a
  shed, floodlight towers) and two of the port's quay cranes far off in the fog.
* A truck on the apron, its 40 ft box open at the tail and bound for the dock: climbing in
  is the way to the port (build_port.py, which parks the same truck there).

Gameplay is art-first: the tyre flights and the planks are real ramps and boards that the
player can walk with the keys (they are narrower than the click-to-walk agent), the way in
is the gap in the fence back to the schoolyard, and three looks (tyres, the long plank, the
orange container) whose lines are the owner's to write and are still placeholders.

Each shaped mesh is its own text ArrayMesh under `meshes/`, like the site interior's, so
the scene stays far under the release's 1 MiB budget for a scene.

    python3 tools/build_container_yard.py           # write the scene and its meshes
    python3 tools/build_container_yard.py --check   # fail if they are not what this writes
"""
from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

import stable_meshes as sm  # also puts the site mesh kit on the path
from site_mesh import box, cylinder, euler, fbm, noise, rand, smoothstep, tube

ROOT = Path(__file__).resolve().parent.parent
REL = "scenes/locations/container_yard"
RES = f"res://{REL}"
SCENE = ROOT / REL / "container_yard.tscn"
MESH_DIR = ROOT / REL / "meshes"
ART = "res://scenes/environment/props/playground_art"

# ISO containers: 20 ft and 40 ft, 8 ft wide, 8 ft 6 in high.
L20, L40, CW, CH = 6.06, 12.19, 2.44, 2.59
# The maze: rows of containers lying along x, in slots 6.5 m apart; lanes between rows.
COLS = (-16.25, -9.75, -3.25, 3.25, 9.75, 16.25)
ROWS = (-15.5, -11.0, -6.5, -2.0, 2.5, 7.0)
# Per row: (first slot, last slot, colours from the ground up). One slot is a 20 ft box,
# two slots a 40 ft box. An empty slot is a gap through the row.
LAYOUT = (
    ((0, 1, ("red", "blue", "blue")), (2, 3, ("blue", "red")), (4, 5, ("blue_deep", "red", "red"))),
    ((0, 0, ("blue", "red_dark")), (2, 3, ("red",)), (4, 4, ("orange",))),
    ((0, 1, ("blue_deep", "blue")), (2, 2, ("red",)), (4, 4, ("red", "blue", "red_dark")), (5, 5, ("blue",))),
    ((1, 1, ("blue",)), (2, 3, ("red_dark", "blue")), (5, 5, ("blue", "red"))),
    ((0, 0, ("red",)), (1, 1, ("blue", "red")), (3, 3, ("blue_deep",)), (4, 5, ("red",))),
    ((0, 1, ("blue",)), (3, 3, ("red", "blue")), (4, 4, ("blue",))),
)
# 20 ft boxes turned across a gap: (row, slot, colours). They cut the lanes either side.
CROSSWISE = ((1, 5, ("blue",)), (3, 0, ("red",)))
# The left side of the yard is a wall of 40 ft boxes standing end to end along z.
LEFT_WALL = ((-21.0, -9.0, ("blue", "red")), (-21.0, 3.4, ("red_dark", "blue_deep")))

COLOURS = {
    "blue": (0.188, 0.361, 0.573),
    "blue_deep": (0.14, 0.27, 0.47),
    "red": (0.62, 0.18, 0.14),
    "red_dark": (0.47, 0.17, 0.15),
    "orange": (0.88, 0.45, 0.1),
}

# The yard's edges: back wall, side fences, and the front fence with the way in.
X_MIN, X_MAX, Z_MIN, Z_MAX = -22.4, 19.9, -17.5, 17.2
GAP_X = 14.0
SPAWN = (GAP_X, 0.0, 15.2)
# The truck on the apron, a box on its trailer bound for the dock, doors open toward +x:
# climbing in is the way to the port (build_port.py parks the same truck there).
TRUCK_DECK = 1.35
TRUCK_TAIL_X, TRUCK_Z = 7.0, 11.8

# Tyres: a flat-laid truck tyre is 0.36 m high, so seven of them reach a single roof.
TYRE_H, TYRE_R, TYRE_HOLE = 0.36, 0.47, 0.26
# Flight A: on the apron, up the south face of the single box in row 5, slot 4.
FLIGHT_A_X = 10.5
# Flight B: on that roof, up to the double stack in slot 3.
FLIGHT_B_Z = 6.75

# Planks: (name, from, to); the points are where the plank rests on the roofs.
PLANKS = (
    ("LongDown", (1.0, 2 * CH, 7.0), (-7.7, CH, 7.0)),
    ("ToCorner", (-16.25, CH, 6.1), (-16.25, CH, 3.4)),
    ("ToFortyFoot", (12.4, CH, 6.1), (12.4, CH, 3.4)),
    ("UpToDouble", (12.0, CH, 2.0), (17.0, 2 * CH, -1.6)),
    ("HighAcross", (9.75, 3 * CH, -14.6), (9.75, 3 * CH, -7.4)),
    ("BackPair", (-16.0, 2 * CH, -7.4), (-16.0, 2 * CH, -10.1)),
    ("MiddleDiagonal", (-5.6, 2 * CH, -1.1), (-8.0, 2 * CH, 1.7)),
)
PLANK_W, PLANK_T = 0.62, 0.06

GROUND = (0.8, 0.8, 0.84)
PAINT = (0.86, 0.84, 0.74)
TIMBER = (0.74, 0.58, 0.4)
RUBBER = (0.15, 0.15, 0.16)
RUST = (0.55, 0.34, 0.24)
FRAME = (0.78, 0.78, 0.8)
CAST = (0.42, 0.42, 0.44)


def v3(p) -> str:
    return "Vector3(" + ", ".join(f"{round(v, 4):g}" for v in p) + ")"


def colour(c, a=1.0) -> str:
    return "Color(" + ", ".join(f"{round(v, 4):g}" for v in (*c, a)) + ")"


class Scene:
    """Just enough of a text scene: ext resources, sub resources, nodes, mesh files."""

    def __init__(self, res: str = RES):
        self.base = res  # where `mesh` puts its files: `<base>/meshes/`
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
            raise SystemExit(f"two meshes would share {file_name}")
        self.files[file_name] = f'[gd_resource type="ArrayMesh" format=3]\n\n[resource]\n_surfaces = {mesh.surface()}\n'
        return self.res("ArrayMesh", f"{self.base}/meshes/{file_name}", f"mesh_{file_name.removesuffix('.tres')}")

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


# --- containers -------------------------------------------------------------------------


def corrugation(start: float, end: float, pitch=0.278, depth=0.036):
    """(position, outward offset) along a trapezoidal corrugated sheet."""
    out = []
    u = start
    while u < end - 1e-6:
        for du, off in ((0.0, 0.0), (0.035, depth), (0.139, depth), (0.174, 0.0)):
            if u + du <= end:
                out.append((u + du, off))
        u += pitch
    if out[-1][0] < end:
        out.append((end, 0.0))
    return out


def weathering(seed: int, length: float):
    """Vertex paint for a container: rust runs down the ribs, the foot is dirtier."""
    def paint(p, _n):
        x, y, z = p
        lift = 0.74 + 0.26 * smoothstep(0.0, 1.1, y)
        fade = 0.94 + 0.08 * fbm(x * 0.21 + seed * 3.1, z * 0.3, seed)
        c = (lift * fade, lift * fade, lift * fade)
        streak = fbm(x * 1.7 + z * 1.3 + seed * 11.0, y * 0.22, seed + 5)
        if streak > 0.56:
            c = sm.mix(c, RUST, min(0.75, (streak - 0.56) * 2.6))
        if y > CH - 0.3:
            c = sm.mix(c, RUST, 0.35 * noise(x * 2.3 + seed, z * 2.3, seed + 9))
        if abs(x) > length / 2 - 0.25:
            c = sm.mix(c, RUST, 0.2)
        return (*c, 1.0)
    return paint


def container_mesh(length: float, seed: int, open_doors: bool = False):
    """One box, lying along x, doors at +x, standing on y = 0 with its roof at CH.

    `open_doors`: both leaves swung right round against the sides, and the dark inside
    showing through the doorway (the truck's box, bound for the dock)."""
    hx, hz = length / 2, CW / 2
    post = 0.15
    m = sm.PaintMesh()
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.add(box((post, CH, post), (sx * (hx - post / 2), CH / 2, sz * (hz - post / 2))), (*FRAME, 1.0))
            for y in (0.06, CH - 0.06):
                m.add(box((0.19, 0.12, 0.17), (sx * (hx - 0.085), y, sz * (hz - 0.08))), (*CAST, 1.0))
    for sz in (-1, 1):
        m.add(box((length - 2 * post, 0.16, 0.1), (0, 0.08, sz * (hz - 0.05))), (*FRAME, 1.0))
        m.add(box((length - 2 * post, 0.1, 0.1), (0, CH - 0.05, sz * (hz - 0.05))), (*FRAME, 1.0))
    for sx in (-1, 1):
        m.add(box((0.1, 0.22, CW - 2 * post), (sx * (hx - 0.05), 0.11, 0)), (*FRAME, 1.0))
        m.add(box((0.1, 0.18, CW - 2 * post), (sx * (hx - 0.05), CH - 0.09, 0)), (*FRAME, 1.0))
    paint = weathering(seed, length)
    # The two long sides, corrugated.
    for sz in (-1, 1):
        prof = corrugation(-hx + post, hx - post)
        rows = [[(u, y, sz * (hz - 0.07 + off)) for u, off in prof] for y in (0.16, CH - 0.1)]
        m.mark()
        m.grid(rows, outward=(0, 0, sz), flat=True)
        m.paint(paint)
    # The blind end, corrugated across.
    prof = corrugation(-hz + post, hz - post)
    rows = [[(-(hx - 0.07 + off), y, u) for u, off in prof] for y in (0.22, CH - 0.18)]
    m.mark()
    m.grid(rows, outward=(-1, 0, 0), flat=True)
    m.paint(paint)
    # The doors: two leaves, four locking bars with their guides and handles.
    leaf_w = (CW - 2 * post) / 2
    if open_doors:
        _open_doors(m, paint, hx, hz, leaf_w)
    for side in ((-1, 1) if not open_doors else ()):
        zc = side * leaf_w / 2
        m.add(box((0.05, CH - 0.4, leaf_w - 0.02), (hx - 0.08, CH / 2, zc)))
        m.paint(paint)
        for y in (0.75, 1.55):
            m.add(box((0.02, 0.05, leaf_w - 0.16), (hx - 0.05, y, zc)))
            m.paint(paint)
        for bz in (zc - leaf_w * 0.22, zc + leaf_w * 0.22):
            m.add(cylinder(0.022, CH - 0.42, 8, center=(hx - 0.02, CH / 2, bz)), (*FRAME, 1.0))
            for y in (0.32, CH - 0.32):
                m.add(box((0.07, 0.1, 0.09), (hx - 0.03, y, bz)), (*CAST, 1.0))
            m.add(box((0.05, 0.05, 0.22), (hx + 0.01, 1.22, bz + side * 0.09)), (*CAST, 1.0))
    if not open_doors:
        m.add(box((0.012, 0.22, 0.34), (hx - 0.045, 1.95, -leaf_w / 2)), (0.9, 0.9, 0.86, 1.0))
    # The roof: its top is the walking surface, at CH.
    m.add(box((length - 0.16, 0.05, CW - 0.16), (0, CH - 0.025, 0)))
    m.paint(lambda p, n: (*sm.mix((0.86, 0.86, 0.88), RUST, 0.45 * fbm(p[0] * 0.6 + seed, p[2] * 0.9, seed + 2)),
                          1.0))
    return m


def _open_doors(m, paint, hx: float, hz: float, leaf_w: float):
    """Leaves folded back flat against the long sides, and the dark inside of the box."""
    for side in (-1, 1):
        z = side * (hz + 0.05)
        m.add(box((leaf_w - 0.02, CH - 0.4, 0.05), (hx - leaf_w / 2 - 0.02, CH / 2, z)))
        m.paint(paint)
        for bx in (hx - leaf_w * 0.28, hx - leaf_w * 0.72):
            m.add(cylinder(0.022, CH - 0.42, 8, center=(bx, CH / 2, z + side * 0.04)), (*FRAME, 1.0))
            m.add(box((0.22, 0.05, 0.05), (bx, 1.22, z + side * 0.08)), (*CAST, 1.0))
    inside = (0.05, 0.05, 0.06, 1.0)
    m.add(box((0.02, CH - 0.32, CW - 0.28), (hx - 0.9, CH / 2, 0)), inside)
    for sz in (-1, 1):
        m.add(box((0.9, CH - 0.32, 0.02), (hx - 0.45, CH / 2, sz * (hz - 0.16))), inside)
    m.add(box((0.9, 0.02, CW - 0.28), (hx - 0.45, CH - 0.17, 0)), inside)
    m.add(box((0.9, 0.03, CW - 0.28), (hx - 0.45, 0.18, 0)), (0.2, 0.16, 0.13, 1.0))


# --- the truck ----------------------------------------------------------------------------


def truck_mesh(length: float):
    """A tractor unit and a skeletal trailer for one box of `length` lying on it.

    The box sits centred on the origin with its floor at TRUCK_DECK; the cab is at -x, the
    trailer's tail (and the box's doors) at +x. Vertex colours are the whole colour."""
    hx = length / 2
    m = sm.PaintMesh()
    cab = (0.84, 0.82, 0.76, 1.0)
    dark = (0.12, 0.12, 0.13, 1.0)
    steel = (0.32, 0.32, 0.34, 1.0)
    x_cab = -hx - 1.7
    m.add(box((2.1, 2.3, 2.42), (x_cab, 2.35, 0), bevel=0.06),
          lambda p, n: (*sm.mix(cab[:3], RUST, 0.25 * fbm(p[0] * 1.3, p[1] * 0.8 + p[2], 91)), 1.0))
    m.add(box((0.04, 0.95, 2.1), (x_cab - 1.06, 2.85, 0)), (0.12, 0.15, 0.2, 1.0))
    for sz in (-1, 1):
        m.add(box((0.9, 0.7, 0.04), (x_cab - 0.4, 2.9, sz * 1.22)), (0.12, 0.15, 0.2, 1.0))
        m.add(box((0.06, 0.3, 0.06), (x_cab - 1.15, 2.8, sz * 1.32)), dark)
    m.add(box((0.3, 0.55, 2.42), (x_cab - 1.15, 1.25, 0)), steel)
    m.add(box((0.08, 0.5, 1.6), (x_cab - 1.07, 1.75, 0)), (0.5, 0.5, 0.5, 1.0))
    m.add(box((2.0, 0.5, 2.42), (x_cab, 1.0, 0)), (0.62, 0.3, 0.18, 1.0))
    # Chassis rails from the bumper to the tail, the fifth wheel, the tail bar and lamps.
    for sz in (-0.45, 0.45):
        m.add(box((length + 2.8, 0.3, 0.16), (-1.4, TRUCK_DECK - 0.22, sz)), steel)
    for k in range(int(length / 1.5) + 1):
        m.add(box((0.12, 0.12, CW - 0.1), (-hx + 0.3 + k * 1.5, TRUCK_DECK - 0.06, 0)), steel)
    m.add(box((1.2, 0.12, 1.2), (-hx + 0.4, TRUCK_DECK - 0.42, 0)), dark)
    m.add(box((0.1, 0.12, CW - 0.2), (hx - 0.05, 0.62, 0)), (0.7, 0.66, 0.6, 1.0))
    for sz in (-1, 1):
        m.add(box((0.05, 0.12, 0.3), (hx + 0.01, 0.95, sz * 0.95)), (0.75, 0.12, 0.08, 1.0))
    # Wheels: the steer axle, two drive axles under the box's front, two trailer axles.
    tyre = cylinder(0.52, 0.32, 14, axis="z", center=(0, 0.52, 0))
    hub = cylinder(0.24, 0.34, 10, axis="z", center=(0, 0.52, 0))
    for x in (x_cab - 0.3, -hx + 0.1, -hx + 1.4, hx - 2.8, hx - 1.6):
        for sz in (-1, 1):
            m.add(tyre, (*RUBBER, 1.0), offset=(x, 0, sz * 1.02))
            m.add(hub, (0.55, 0.55, 0.56, 1.0), offset=(x, 0, sz * 1.04))
    _truck_details(m, hx, x_cab, cab, dark, steel)
    return m


def _truck_details(m, hx: float, x_cab: float, cab, dark, steel):
    """What makes the tractor read as a truck and not a box: the roof fairing and the sun
    visor, a slatted grille, lamps, door seams and steps, mirrors on their arms, the fuel
    tank, the exhaust stack, mudguards; on the trailer the landing legs, side guards, mud
    flaps and the number plate."""
    front = x_cab - 1.05
    paint = lambda p, n: (*sm.mix(cab[:3], RUST, 0.25 * fbm(p[0] * 1.3, p[1] * 0.8 + p[2], 91)), 1.0)
    m.add(box((1.5, 0.55, 2.3), (x_cab + 0.25, 3.77, 0), bevel=0.05), paint)
    m.add(box((0.7, 0.5, 2.3), (0, 0, 0), bevel=0.04), paint, rotation=euler((0, 0, -38)),
          offset=(x_cab - 0.55, 3.66, 0))
    m.add(box((0.32, 0.05, 2.36), (front - 0.12, 3.42, 0)), dark)
    m.add(box((0.05, 0.62, 1.5), (front - 0.005, 1.78, 0)), (0.42, 0.42, 0.44, 1.0))
    for k in range(5):
        m.add(box((0.04, 0.05, 1.42), (front - 0.03, 1.55 + k * 0.115, 0)), dark)
    for sz in (-1, 1):
        m.add(box((0.05, 0.2, 0.42), (front - 0.3, 1.32, sz * 0.86)), (0.98, 0.94, 0.78, 1.0))
        m.add(box((0.05, 0.12, 0.16), (front - 0.3, 1.32, sz * 1.13)), (0.95, 0.55, 0.15, 1.0))
        m.add(box((0.04, 0.12, 0.2), (front - 0.01, 3.3, sz * 1.0)), (0.95, 0.6, 0.2, 1.0))
        side = sz * 1.215
        for x in (x_cab - 0.75, x_cab + 0.55):
            m.add(box((0.03, 1.5, 0.02), (x, 2.0, side)), dark)
        m.add(box((1.3, 0.03, 0.02), (x_cab - 0.1, 1.27, side)), dark)
        m.add(box((0.2, 0.05, 0.04), (x_cab + 0.35, 2.15, side + 0.02)), (0.6, 0.6, 0.62, 1.0))
        for k, y in enumerate((0.62, 0.98)):
            m.add(box((0.5, 0.05, 0.28 + 0.06 * k), (x_cab - 0.1, y, sz * (1.1 + 0.04 * k))), steel)
        m.add(box((0.5, 0.05, 0.05), (front - 0.1, 3.05, sz * 1.24)), dark)
        m.add(box((0.05, 0.05, 0.25), (front - 0.15, 3.05, sz * 1.25)), dark)
        # Mudguards over the steer wheels and the drive axles.
        m.add(box((1.2, 0.06, 0.42), (x_cab - 0.3, 1.12, sz * 1.02)), dark)
        m.add(box((2.4, 0.06, 0.42), (-hx + 0.75, 1.14, sz * 1.02)), dark)
        # The trailer: side guards between the axles, mud flaps behind the last wheels.
        g0, g1 = -hx + 2.0, hx - 3.4
        for gy in (0.55, 0.85):
            m.add(box((g1 - g0, 0.1, 0.05), ((g0 + g1) / 2, gy, sz * 1.15)), (0.85, 0.85, 0.82, 1.0))
        m.add(box((0.04, 0.55, 0.42), (hx - 0.95, 0.5, sz * 1.02)), dark)
    # The fuel tank under the door on the near side, the exhaust stack behind the cab.
    m.add(cylinder(0.28, 0.9, 14, axis="x", center=(-hx - 0.95, 0.72, 0.98)), (0.75, 0.76, 0.78, 1.0))
    m.add(cylinder(0.08, 2.4, 10, center=(x_cab + 1.15, 3.0, -1.0)), (0.55, 0.55, 0.57, 1.0))
    m.add(box((0.24, 0.9, 0.04), (x_cab + 1.15, 3.0, -0.88)), (0.7, 0.7, 0.72, 1.0))
    # Landing legs at the front of the trailer, wound up off the ground.
    for sz in (-0.8, 0.8):
        m.add(box((0.14, 0.9, 0.14), (-hx + 2.7, TRUCK_DECK - 0.75, sz)), dark)
        m.add(box((0.3, 0.06, 0.3), (-hx + 2.7, TRUCK_DECK - 1.22, sz)), dark)
    m.add(box((0.05, 0.16, 0.5), (hx + 0.03, 0.75, 0)), (0.95, 0.92, 0.5, 1.0))


def truck(s: Scene, parent: str, centre, materials: dict) -> str:
    """The truck as one body; its box is `Truck/Box`, the open doors toward +x."""
    body = s.node("Truck", parent, "StaticBody3D", groups=["camera_occluder"], position=v3(centre),
                  collision_layer="1", collision_mask="0")
    reach = L40 / 2 + 3.0
    s.node("CollisionShape3D", body, "CollisionShape3D", position=v3(((L40 / 2 - reach) / 2, (TRUCK_DECK + CH) / 2, 0)),
           shape=s.sub("BoxShape3D", "Shape_truck", size=v3((L40 / 2 + reach, TRUCK_DECK + CH, CW + 0.2))))
    s.node("Rig", body, "MeshInstance3D", mesh=materials["rig_mesh"], material_override=materials["rig"])
    s.node("Box", body, "MeshInstance3D", position=v3((0, TRUCK_DECK, 0)), mesh=materials["box_mesh"],
           material_override=materials["box"])
    return body


# --- tyres and planks -------------------------------------------------------------------


def tyre_mesh():
    """A truck tyre laid flat, its hole facing up."""
    prof = [(TYRE_HOLE, -0.13), (TYRE_HOLE, 0.13), (TYRE_HOLE + 0.06, 0.18), (TYRE_R - 0.03, 0.17),
            (TYRE_R, 0.08), (TYRE_R, -0.08), (TYRE_R - 0.03, -0.17), (TYRE_HOLE + 0.06, -0.18)]
    sides = 16
    rc = (TYRE_HOLE + TYRE_R) / 2
    rows, centers = [], []
    for k in range(sides + 1):
        a = k * math.tau / sides
        ca, sa = math.cos(a), math.sin(a)
        rows.append([(r * ca, y + TYRE_H / 2, r * sa) for r, y in prof])
        centers.append((rc * ca, TYRE_H / 2, rc * sa))
    m = sm.PaintMesh()
    m.grid(rows, wrap=True, centers=centers)
    m.paint(lambda p, n: (*sm.mix(RUBBER, (0.24, 0.22, 0.2), 0.5 * noise(p[0] * 6, p[2] * 6, 4)), 1.0))
    return m


def tyre_stack(count: int, seed: int):
    """`count` tyres one on another, each turned and nudged a little."""
    tyre = tyre_mesh()
    m = sm.PaintMesh()
    for k in range(count):
        j = count * 10 + k
        jx, jz = (rand(j, seed) - 0.5) * 0.06, (rand(j, seed + 1) - 0.5) * 0.06
        m.add(tyre, rotation=euler((0, rand(j, seed + 2) * 360, 0)), offset=(jx, k * TYRE_H, jz))
    return m


def flight(s: Scene, body: str, stacks: dict, counts, pitch: float, axis: str, material: str) -> list[str]:
    """Stacks standing in a line toward -axis from the body's origin; counts[0] is lowest."""
    paths = []
    n = len(counts)
    for i, count in enumerate(counts):
        along = (n - 1 - i) * pitch
        pos = (along, 0, 0) if axis == "x" else (0, 0, along)
        paths.append(s.node(f"Stack{i}", body, "MeshInstance3D", position=v3(pos), mesh=stacks[count],
                            material_override=material))
    return paths


def plank_mesh(length: float, seed: int):
    """Two boards side by side with cleats across, along +x; alpha weights the sway."""
    m = sm.PaintMesh()
    half = PLANK_W / 2
    board_w = half - 0.01
    for side in (-1, 1):
        zc = side * (board_w / 2 + 0.01)
        steps = max(2, int(length / 0.6))
        # A board is a long thin box; build it as segments so it can bend.
        for k in range(steps):
            x0, x1 = length * k / steps, length * (k + 1) / steps
            m.add(box((x1 - x0 + 0.002, PLANK_T, board_w), ((x0 + x1) / 2, PLANK_T / 2, zc)))
    for k in range(int(length / 0.9) + 1):
        x = min(length - 0.05, 0.05 + k * 0.9)
        m.add(box((0.07, 0.035, PLANK_W + 0.04), (x, -0.017, 0)))
    m._mark = 0  # paint every board and cleat, not only the last one added
    m.paint(lambda p, n: (*sm.mix(TIMBER, (0.4, 0.33, 0.27),
                                  0.55 * fbm(p[0] * 0.8 + seed * 5.0, p[2] * 9.0, seed)),
                          math.sin(math.pi * max(0.0, min(1.0, p[0] / length)))))
    return m


# --- the ground and its edges -----------------------------------------------------------


def ground_mesh():
    xs = [X_MIN - 0.6 + k * (X_MAX - X_MIN + 1.2) / 44 for k in range(45)]
    zs = [Z_MIN - 1.0 + k * (Z_MAX - Z_MIN + 1.8) / 36 for k in range(37)]
    rows, cols = [], []
    for z in zs:
        row = [(x, 0.0, z) for x in xs]
        rows.append(row)
        crow = []
        for x, _, _ in row:
            c = sm.mix(GROUND, (0.4, 0.4, 0.44), 0.6 * fbm(x * 0.18, z * 0.18, 21))
            oil = fbm(x * 0.5 + 3, z * 0.5, 23)
            if oil > 0.6:
                c = sm.mix(c, (0.2, 0.2, 0.24), (oil - 0.6) * 2.5)
            crow.append((*c, 1.0))
        cols.append(crow)
    return sm.PaintMesh().grid(rows, outward=(0, 1, 0), colors=cols)


def bay_paint():
    """Parking-bay lines on the apron and down the gaps, worn through in places."""
    m = sm.PaintMesh()
    y = 0.006

    def strip(x0, z0, x1, z1, w=0.1):
        dx, dz = x1 - x0, z1 - z0
        ln = math.hypot(dx, dz)
        nx, nz = -dz / ln * w / 2, dx / ln * w / 2
        quad = [(x0 + nx, y, z0 + nz), (x1 + nx, y, z1 + nz), (x1 - nx, y, z1 - nz), (x0 - nx, y, z0 - nz)]
        m.polygon(quad, (0, 1, 0))

    k = 0
    x = X_MIN + 1.4
    while x < X_MAX - 1.0:
        if abs(x - FLIGHT_A_X) > 0.8 and abs(x - GAP_X) > 0.9:
            strip(x, 9.1, x, 12.6)
        x += 2.6
        k += 1
    strip(X_MIN + 1.2, 12.6, X_MAX - 0.8, 12.6)
    # A hatched box where the way in meets the apron.
    for i in range(6):
        strip(GAP_X - 1.2 + i * 0.45, 16.4, GAP_X - 0.6 + i * 0.45, 15.2, 0.12)
    m.paint(lambda p, n: (*sm.mix(PAINT, GROUND, 0.75 * smoothstep(0.45, 0.8, fbm(p[0] * 0.9, p[2] * 0.9, 31))),
                          1.0))
    return m


def mast_mesh():
    m = sm.PaintMesh()
    m.add(cylinder(0.12, 9.6, 10, top=0.08, center=(0, 4.8, 0)), (0.36, 0.36, 0.38, 1.0))
    m.add(box((1.6, 0.12, 0.12), (0, 9.5, 0)), (0.3, 0.3, 0.32, 1.0))
    for x in (-0.6, 0.6):
        m.add(box((0.42, 0.26, 0.3), (x, 9.32, 0.1)), (0.26, 0.26, 0.28, 1.0))
        m.add(box((0.36, 0.02, 0.24), (x, 9.18, 0.12)), (1.0, 0.86, 0.6, 1.0))
    m.add(box((0.5, 0.3, 0.6), (0, 0.15, 0)), (0.5, 0.5, 0.5, 1.0))
    return m


def back_wall_mesh():
    """The back wall as precast concrete: panels between columns, a coping, rust and water
    run down from the top, a dirty foot, and three strands of wire on cranked brackets. In
    the wall body's frame: centred on it, 3.2 m high, its yard face toward +z."""
    m = sm.PaintMesh()
    length = X_MAX - X_MIN
    half, h = length / 2, 1.6
    pitch = length / 14

    def concrete(p, _n):
        x, y, _z = p
        c = sm.mix((0.8, 0.79, 0.76), (0.6, 0.6, 0.6), 0.6 * fbm(x * 0.35, y * 0.5, 211))
        run = fbm(x * 2.2, y * 0.18, 213) * smoothstep(-0.6, h, y)
        if run > 0.48:
            c = sm.mix(c, RUST if fbm(x * 0.3, 1.0, 215) > 0.5 else (0.36, 0.38, 0.36), min(0.6, (run - 0.48) * 2.4))
        return (*sm.mix(c, (0.3, 0.29, 0.28), 0.6 * (1.0 - smoothstep(-h, -h + 0.5, y))), 1.0)

    m.add(box((length, 2 * h - 0.1, 0.14), (0, -0.05, -0.04)), (0.18, 0.18, 0.19, 1.0))
    for k in range(14):
        x0 = -half + k * pitch + 0.03
        x1 = x0 + pitch - 0.06
        rows = [[(x0 + (x1 - x0) * i / 8, -h + 0.02 + (2 * h - 0.24) * j / 6, 0.1) for i in range(9)]
                for j in range(7)]
        m.mark()
        m.grid(rows, outward=(0, 0, 1))
        m.paint(concrete)
        m.add(box((x1 - x0, 2 * h - 0.22, 0.04), ((x0 + x1) / 2, -0.1, -0.12)), concrete)
    for k in range(15):
        x = -half + k * pitch
        m.add(box((0.32, 2 * h + 0.08, 0.3), (x, 0.04, 0.0)), concrete)
        # The wire bracket, cranked out over the yard side.
        m.add(box((0.06, 0.5, 0.06), (x, h + 0.33, 0.04)), (0.3, 0.3, 0.32, 1.0))
        m.add(box((0.06, 0.06, 0.55), (0, 0, 0)), (0.3, 0.3, 0.32, 1.0), rotation=euler((-40, 0, 0)),
              offset=(x, h + 0.7, -0.12))
    m.add(box((length + 0.1, 0.12, 0.34), (0, h + 0.02, 0.0)), (0.7, 0.69, 0.66, 1.0))
    for y, z in ((h + 0.32, 0.04), (h + 0.55, -0.08), (h + 0.78, -0.26)):
        pts = []
        for k in range(29):
            x = -half + k * length / 28
            sag = 0.04 * math.sin(math.pi * ((x + half) / pitch % 1.0))
            pts.append((x, y - sag, z))
        m.add(tube(pts, 0.012, 3), (0.25, 0.25, 0.27, 1.0))
    return m


def fence_frame_mesh():
    """Posts, a top rail and a bottom wire along the chain-link fences, in world space."""
    m = sm.PaintMesh()
    steel = lambda p, n: (*sm.mix((0.5, 0.52, 0.5), RUST, 0.35 * noise(p[0] * 2.0 + p[2] * 2.0, p[1], 221)), 1.0)
    runs = (((X_MIN, Z_MIN + 0.3), (X_MIN, Z_MAX)), ((X_MAX, Z_MIN + 0.3), (X_MAX, Z_MAX)),
            ((X_MIN, Z_MAX), (GAP_X - 0.85, Z_MAX)), ((GAP_X + 0.85, Z_MAX), (X_MAX, Z_MAX)))
    for (ax, az), (bx, bz) in runs:
        ln = math.hypot(bx - ax, bz - az)
        n = max(1, round(ln / 2.5))
        for k in range(n + 1):
            x, z = ax + (bx - ax) * k / n, az + (bz - az) * k / n
            m.add(cylinder(0.04, 2.1, 8, center=(x, 1.05, z)), steel)
            m.add(cylinder(0.06, 0.04, 8, center=(x, 2.12, z)), steel)
        for y, r in ((2.0, 0.025), (0.08, 0.008)):
            m.add(tube([(ax, y, az), (bx, y, bz)], r, 5), steel)
    return m


def far_stacks_mesh():
    """Past the back wall and the west fence, the rest of the terminal: rows of stacks of
    every colour, a shed with a ribbed roof, a reefer row with its gantry of plugs. Simple
    boxes; the fog does the rest."""
    m = sm.PaintMesh()
    palette = tuple(COLOURS.values()) + ((0.78, 0.78, 0.76), (0.24, 0.42, 0.33), (0.5, 0.5, 0.52),
                                         (0.86, 0.66, 0.2))

    def stack(x, z, yaw, length, tiers, seed):
        rot = euler((0, yaw, 0))
        part = sm.PaintMesh()
        for t in range(tiers):
            base = palette[int(rand(seed * 7 + t, 231) * (len(palette) - 0.01))]
            y = t * CH
            # One box a tier, its foot darker so the tiers read apart in the fog.
            part.add(box((length - 0.1, CH - 0.04, CW - 0.06), (0, y + CH / 2, 0)),
                     lambda p, n, base=base, y=y: (*sm.mix(base, (0.12, 0.12, 0.13), 0.5 if p[1] < y + 0.1 else 0.0),
                                                   1.0))
        m.add(part, rotation=rot, offset=(x, 0, z))

    seed = 0
    # Behind the back wall: blocks of stacks in rows along x, lanes between the blocks.
    for row, z in enumerate((-21.5, -24.2, -26.9, -33.0, -35.7, -38.4, -44.5, -47.2)):
        x = -58.0 + rand(row, 233) * 4.0
        while x < 46.0:
            seed += 1
            length = L40 if rand(seed, 235) > 0.4 else L20
            if rand(seed, 237) > 0.12:
                # The rows nearest the wall stay low, so the stacks climb away into the fog.
                stack(x + length / 2, z, 0.0, length, 1 + int(rand(seed, 239) * min(3.99, 1.5 + row * 0.5)), seed)
            x += length + (6.0 if rand(seed, 241) > 0.86 else 0.25)
    # West of the west fence: rows along z, the same way.
    for col, x in enumerate((-27.0, -29.7, -32.4, -38.5, -41.2, -43.9)):
        z = -18.0 + rand(col, 243) * 3.0
        while z < 30.0:
            seed += 1
            length = L40 if rand(seed, 245) > 0.5 else L20
            if rand(seed, 247) > 0.15:
                stack(x, z + length / 2, 90.0, length, 1 + int(rand(seed, 249) * min(3.99, 1.5 + col * 0.6)), seed)
            z += length + (5.0 if rand(seed, 251) > 0.85 else 0.25)
    # A long shed far behind the stacks, its roof ribbed, roller doors along its front.
    shed = lambda p, n: (*sm.mix((0.62, 0.64, 0.66), RUST, 0.3 * fbm(p[0] * 0.2, p[1] * 0.5, 253)), 1.0)
    m.add(box((60.0, 9.0, 18.0), (-8.0, 4.5, -62.0)), shed)
    for k in range(41):
        m.add(box((0.25, 0.25, 18.4), (-38.0 + k * 1.5, 9.1, -62.0)), (0.48, 0.5, 0.52, 1.0))
    for k in range(8):
        m.add(box((4.0, 5.0, 0.05), (-34.0 + k * 7.4, 2.5, -52.98)), (0.32, 0.36, 0.42, 1.0))
    # Floodlight towers over the stacks.
    for x, z in ((-44.0, -30.0), (-4.0, -30.0), (34.0, -30.0), (-36.0, 8.0)):
        m.add(cylinder(0.35, 28.0, 8, top=0.2, center=(x, 14.0, z)), (0.4, 0.4, 0.42, 1.0))
        m.add(box((3.2, 1.0, 0.5), (x, 28.2, z)), (0.3, 0.3, 0.32, 1.0))
        m.add(box((3.0, 0.8, 0.04), (x, 28.0, z + 0.27)), (1.0, 0.86, 0.6, 1.0))
    return m


def cabin_mesh():
    """The yard office: a portacabin on blocks, window grilles, a door, a stair of two steps."""
    m = sm.PaintMesh()
    w, d, h = 5.0, 2.4, 2.5
    m.add(box((w, h, d), (0, 0.2 + h / 2, 0), bevel=0.03),
          lambda p, n: (*sm.mix((0.92, 0.9, 0.84), RUST, 0.3 * fbm(p[0] * 0.9, p[1] * 0.5 + p[2], 81)), 1.0))
    m.add(box((w + 0.12, 0.12, d + 0.12), (0, h + 0.26, 0)), (0.55, 0.55, 0.58, 1.0))
    for x in (-2.2, 2.2):
        for z in (-0.9, 0.9):
            m.add(box((0.3, 0.2, 0.3), (x, 0.1, z)), (0.5, 0.5, 0.5, 1.0))
    for x in (-1.6, 0.2):
        m.add(box((1.1, 0.75, 0.04), (x, 1.65, d / 2 + 0.01)), (0.16, 0.2, 0.26, 1.0))
        for k in range(5):
            m.add(box((0.025, 0.8, 0.03), (x - 0.44 + k * 0.22, 1.65, d / 2 + 0.04)), (0.3, 0.3, 0.32, 1.0))
    m.add(box((0.85, 2.0, 0.05), (1.75, 1.2, d / 2 + 0.02)), (0.3, 0.45, 0.6, 1.0))
    m.add(box((0.24, 0.12, 0.04), (1.45, 1.75, d / 2 + 0.06)), (0.95, 0.95, 0.9, 1.0))
    m.add(box((1.0, 0.2, 0.5), (1.75, 0.1, d / 2 + 0.3)), (0.5, 0.5, 0.5, 1.0))
    m.add(box((0.5, 0.35, 0.4), (-2.9, 1.95, 0.3)), (0.85, 0.85, 0.82, 1.0))
    return m


def pallets():
    m = sm.PaintMesh()
    for k, (x, z, yaw, layers) in enumerate(((0, 0, 0, 3), (1.4, 0.2, 10, 1), (0.6, 1.2, 80, 2))):
        rot = euler((0, yaw, 0))
        part = sm.PaintMesh()
        for layer in range(layers):
            y = layer * 0.15
            for bz in (-0.45, 0, 0.45):
                part.add(box((1.2, 0.08, 0.1), (0, y + 0.04, bz)))
            for bx in range(7):
                part.add(box((0.12, 0.022, 1.0), (-0.54 + bx * 0.18, y + 0.09, 0)))
        # `paint` covers what was added since the last `add`, so reset the mark to cover it all.
        part._mark = 0
        part.paint(lambda p, n, k=k: (*sm.mix(TIMBER, (0.45, 0.4, 0.34), 0.5 + 0.4 * noise(p[0] * 3, p[2] * 3, k)), 1.0))
        m.add(part, rotation=rot, offset=(x, 0, z))
    return m


def flap_mesh():
    """The chain-link at the way in, cut and bent back: a dark hole and the bent sheet."""
    m = sm.PaintMesh()
    m.add(box((1.5, 1.7, 0.04), (0, 0.85, 0)), (0.07, 0.08, 0.1, 1.0))
    return m


# --- the scene --------------------------------------------------------------------------


def stacks():
    """Every stack as (name, centre, yaw, length, colours)."""
    out = []
    for r, row in enumerate(LAYOUT):
        for first, last, colours in row:
            x = (COLS[first] + COLS[last]) / 2
            length = L20 if first == last else L40
            name = f"R{r}C{first}" if first == last else f"R{r}C{first}{last}"
            out.append((name, (x, 0.0, ROWS[r]), 0.0, length, colours))
    for r, c, colours in CROSSWISE:
        out.append((f"Across_R{r}C{c}", (COLS[c], 0.0, ROWS[r]), 90.0, L20, colours))
    for i, (x, z, colours) in enumerate(LEFT_WALL):
        out.append((f"LeftWall{i}", (x, 0.0, z), 90.0, L40, colours))
    return out


def ramp(s: Scene, parent: str, name: str, low, high, width: float, axis: str):
    """A thin box whose top runs from `low` to `high` (the walked line of a flight)."""
    thick = 0.3
    dx, dy, dz = (high[0] - low[0], high[1] - low[1], high[2] - low[2])
    run = math.hypot(dx, dz)
    theta = math.atan2(dy, run)
    length = math.hypot(run, dy)
    mid = ((low[0] + high[0]) / 2, (low[1] + high[1]) / 2, (low[2] + high[2]) / 2)
    if axis == "z":  # climbs toward -z
        normal = (0.0, math.cos(theta), math.sin(theta))
        rot = (math.degrees(theta), 0, 0)
        size = (width, thick, length)
    else:  # climbs toward -x
        normal = (math.sin(theta), math.cos(theta), 0.0)
        rot = (0, 0, -math.degrees(theta))
        size = (length, thick, width)
    centre = (mid[0] - normal[0] * thick / 2, mid[1] - normal[1] * thick / 2, mid[2] - normal[2] * thick / 2)
    s.node(name, parent, "CollisionShape3D", position=v3(centre), rotation_degrees=v3(rot),
           shape=s.sub("BoxShape3D", f"Shape_{name}", size=v3(size)))


def build() -> Scene:
    s = Scene()
    location = s.res("Script", "res://scripts/world/location_root.gd", "location")
    navigation = s.res("Script", "res://scripts/world/location_navigation.gd", "navigation")
    ambience = s.res("Script", "res://scripts/world/ambience_player.gd", "ambience")
    tone = s.res("AudioStream", "res://assets/audio/room_tone_walkway.wav", "tone")
    exit_scene = s.res("PackedScene", "res://scenes/interaction/location_exit.tscn", "exit")
    look = s.res("PackedScene", "res://scenes/interaction/interactable.tscn", "look")
    sway = s.res("Shader", f"{RES}/plank_sway.gdshader", "sway")
    metal_tile = s.res("Texture2D", f"{ART}/textures/metal_tile.png", "metal_tile")
    ground_tile = s.res("Texture2D", f"{ART}/textures/ground_tile.png", "ground_tile")
    fence = s.res("Material", f"{ART}/materials/fence_panel.tres", "fence")

    env = s.sub("Environment", "YardEnvironment",
                background_mode="1", background_color=colour((0.239, 0.275, 0.361)),
                ambient_light_source="2", ambient_light_color=colour((0.66, 0.64, 0.74)),
                ambient_light_energy="0.8", tonemap_mode="2", tonemap_exposure="0.66",
                fog_enabled="true", fog_light_color=colour((0.32, 0.3, 0.38)), fog_density="0.006",
                adjustment_enabled="true", adjustment_saturation="1.02", adjustment_contrast="1.04")

    def painted(rid, base, *, texture=None, scale=0.58, world=False, cull=None, srgb=False):
        # `srgb`: the vertex colour carries the whole colour (rubber, timber, steel), so it is
        # read as sRGB like the palette it was picked from; the containers and the ground get
        # their hue from `base` and only grime from the vertices, and were tuned without it.
        props = {"resource_name": f'"{rid}"', "diffuse_mode": "3", "specular_mode": "2",
                 "vertex_color_use_as_albedo": "true", "albedo_color": colour(base), "roughness": "1.0"}
        if srgb:
            props["vertex_color_is_srgb"] = "true"
        if cull is not None:
            props["cull_mode"] = cull
        if texture is not None:
            props.update(albedo_texture=texture, uv1_scale=v3((scale, scale, scale)), uv1_triplanar="true")
            if world:
                props["uv1_world_triplanar"] = "true"
        props["texture_filter"] = "3"
        return s.sub("StandardMaterial3D", rid, **props)

    container_mats = {name: painted(f"container_{name}", c, texture=metal_tile) for name, c in COLOURS.items()}
    ground_mat = painted("asphalt", (0.7, 0.7, 0.74), texture=ground_tile, scale=0.25, world=True)
    paint_mat = painted("bay_paint", (1, 1, 1), srgb=True)
    rubber_mat = painted("rubber", (1, 1, 1), srgb=True)
    steel_mat = painted("mast_steel", (1, 1, 1), srgb=True)
    hole_mat = painted("gap_dark", (1, 1, 1), cull="2", srgb=True)
    crane_mat = s.sub("StandardMaterial3D", "crane", resource_name='"crane"', shading_mode="0",
                      albedo_color=colour((0.25, 0.25, 0.31)))
    port_crane = s.res("ArrayMesh", "res://scenes/locations/port/meshes/crane.tres", "port_crane")
    plaster = s.res("Texture2D", f"{ART}/textures/plaster_tile.png", "plaster_tile")
    wall_mat = painted("precast", (1, 1, 1), texture=plaster, scale=0.3, world=True, srgb=True)
    far_mat = painted("far_stacks", (1, 1, 1), texture=metal_tile, scale=0.4, world=True, srgb=True)

    root = s.node("ContainerYard", None, "Node3D", script=location, location_id='&"container_yard"')
    s.node("WorldEnvironment", root, "WorldEnvironment", environment=env)
    s.node("Sun", root, "DirectionalLight3D", rotation_degrees=v3((-28, 32, 0)),
           light_color=colour((1, 0.8, 0.62)), light_energy="0.32", shadow_enabled="true",
           directional_shadow_max_distance="70.0")
    s.node("Navigation", root, "NavigationRegion3D", script=navigation)
    s.node("Ambience", root, "AudioStreamPlayer", stream=tone, volume_db="-30.0", script=ambience,
           target_db="-26.0", pitch_scale="0.8")

    # The ground: one slab under the whole yard.
    s.node("YardGround", root, "StaticBody3D", collision_layer="1", collision_mask="0")
    gx, gz = (X_MIN + X_MAX) / 2, (Z_MIN + Z_MAX) / 2
    s.node("CollisionShape3D", "YardGround", "CollisionShape3D", position=v3((gx, -0.1, gz)),
           shape=s.sub("BoxShape3D", "Shape_ground", size=v3((X_MAX - X_MIN + 1.2, 0.2, Z_MAX - Z_MIN + 1.8))))
    s.node("Surface", "YardGround", "MeshInstance3D", mesh=s.mesh("Ground", ground_mesh()),
           material_override=ground_mat)
    s.node("BayPaint", "YardGround", "MeshInstance3D", mesh=s.mesh("BayPaint", bay_paint()),
           material_override=paint_mat, cast_shadow="0")
    # Past the edges the terminal goes on: the same asphalt to the fog, and stacks on it.
    s.node("Outskirts", root, "MeshInstance3D", position=v3((0, -0.05, 0)),
           mesh=s.sub("PlaneMesh", "Plane_outskirts", size="Vector2(320, 320)"), material_override=ground_mat,
           cast_shadow="0")
    s.node("FarStacks", root, "MeshInstance3D", mesh=s.mesh("FarStacks", far_stacks_mesh()), material_override=far_mat)

    # The containers, stack by stack; each stack is one body the camera can fade.
    meshes = {(L20, 0): s.mesh("Container20A", container_mesh(L20, 1)),
              (L20, 1): s.mesh("Container20B", container_mesh(L20, 2)),
              (L40, 0): s.mesh("Container40A", container_mesh(L40, 3)),
              (L40, 1): s.mesh("Container40B", container_mesh(L40, 4))}
    s.node("Containers", root, "Node3D")
    for i, (name, centre, yaw, length, colours) in enumerate(stacks()):
        body = s.node(name, "Containers", "StaticBody3D", groups=["camera_occluder"], position=v3(centre),
                      rotation_degrees=v3((0, yaw, 0)), collision_layer="1", collision_mask="0")
        height = CH * len(colours)
        s.node("CollisionShape3D", body, "CollisionShape3D", position=v3((0, height / 2, 0)),
               shape=s.sub("BoxShape3D", f"Shape_{name}", size=v3((length, height, CW))))
        for level, paint in enumerate(colours):
            j = i * 7 + level
            flip = 180.0 if rand(j, 41) > 0.5 else 0.0
            nudge = ((rand(j, 43) - 0.5) * 0.08 if level else 0.0, level * CH, (rand(j, 47) - 0.5) * 0.05 if level else 0.0)
            skew = (rand(j, 53) - 0.5) * 0.8 if level else 0.0
            s.node(f"Level{level}", body, "MeshInstance3D", position=v3(nudge),
                   rotation_degrees=v3((0, flip + skew, 0)),
                   mesh=meshes[(length, int(rand(j, 59) * 2))], material_override=container_mats[paint])

    # Tyre flights: real ramps under the stacks, so the keys can walk them.
    tyre_stacks = {k: s.mesh(f"TyreStack{k}", tyre_stack(k, 61)) for k in range(1, 8)}
    face_a = ROWS[5] + CW / 2
    s.node("TyreFlightA", root, "StaticBody3D", position=v3((FLIGHT_A_X, 0, face_a + TYRE_R + 0.03)),
           collision_layer="1", collision_mask="0")
    flight_a = flight(s, "TyreFlightA", tyre_stacks, range(1, 8), 1.0, "z", rubber_mat)
    ramp(s, "TyreFlightA", "Ramp", (0.0, 0.0, 6.0 + TYRE_R + 0.15), (0.0, CH + 0.02, -TYRE_R - 0.05), 1.0, "z")

    c4_west = COLS[4] - L20 / 2
    c4_east = COLS[4] + L20 / 2
    origin_b = c4_west + TYRE_R + 0.03
    s.node("TyreFlightB", root, "StaticBody3D", position=v3((origin_b, CH, FLIGHT_B_Z)), collision_layer="1",
           collision_mask="0")
    flight(s, "TyreFlightB", tyre_stacks, range(1, 7), 0.95, "x", rubber_mat)
    ramp(s, "TyreFlightB", "Ramp", (c4_east - 0.33 - origin_b, 0.0, 0.0), (-TYRE_R - 0.15, CH + 0.02, 0.0), 1.0, "x")

    # A loose heap of tyres by the apron fence, and a few lying about.
    heap = sm.PaintMesh()
    tyre = tyre_mesh()
    for k, (x, z, y, tilt) in enumerate(((0, 0, 0, 0), (0.9, 0.3, 0, 0), (0.4, 0.2, TYRE_H, 8),
                                         (0.2, -0.9, 0, 0), (1.1, -0.7, 0, 64), (0.5, -0.4, 0.6, 30))):
        heap.add(tyre, rotation=euler((tilt, k * 47.0, 0)), offset=(x, y, z))
    s.node("TyreHeap", root, "MeshInstance3D", position=v3((-9.5, 0, 15.4)), mesh=s.mesh("TyreHeap", heap),
           material_override=rubber_mat)

    # The yard office by the apron, and pallets beside it.
    cabin_mat = painted("cabin", (1, 1, 1), texture=metal_tile, scale=0.5, srgb=True)
    s.node("YardOffice", root, "StaticBody3D", groups=["camera_occluder"], position=v3((-16.4, 0, 14.6)),
           collision_layer="1", collision_mask="0")
    s.node("CollisionShape3D", "YardOffice", "CollisionShape3D", position=v3((0, 1.35, 0)),
           shape=s.sub("BoxShape3D", "Shape_office", size=v3((5.0, 2.7, 2.4))))
    s.node("Cabin", "YardOffice", "MeshInstance3D", mesh=s.mesh("YardOffice", cabin_mesh()),
           material_override=cabin_mat)
    s.node("Pallets", root, "MeshInstance3D", position=v3((-12.6, 0, 13.6)), mesh=s.mesh("Pallets", pallets()),
           material_override=paint_mat)

    # The truck on the apron, its box open at the tail: the way on to the port.
    rig = {"rig_mesh": s.mesh("Truck", truck_mesh(L40)), "rig": steel_mat,
           "box_mesh": s.mesh("Container40Open", container_mesh(L40, 5, open_doors=True)),
           "box": container_mats["blue"]}
    truck(s, root, (TRUCK_TAIL_X - L40 / 2, 0, TRUCK_Z), rig)

    # The planks: a fixed board to walk on, a mesh that sags and sways over it.
    s.node("Planks", root, "Node3D")
    for i, (name, a, b) in enumerate(PLANKS):
        dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        run = math.hypot(dx, dz)
        length = math.hypot(run, dy) + 0.5
        yaw = math.degrees(math.atan2(-dz, dx))
        pitch = math.degrees(math.atan2(dy, run))
        # Start a quarter metre before `a`, along the plank, so both ends rest on a roof.
        ux, uy, uz = dx / (length - 0.5), dy / (length - 0.5), dz / (length - 0.5)
        start = (a[0] - ux * 0.25, a[1] - uy * 0.25, a[2] - uz * 0.25)
        body = s.node(name, "Planks", "StaticBody3D", position=v3(start), rotation_degrees=v3((0, yaw, pitch)),
                      collision_layer="1", collision_mask="0")
        s.node("CollisionShape3D", body, "CollisionShape3D", position=v3((length / 2, PLANK_T / 2, 0)),
               shape=s.sub("BoxShape3D", f"Shape_plank_{name}", size=v3((length, PLANK_T, PLANK_W + 0.2))))
        mat = s.sub("ShaderMaterial", f"Mat_plank_{name}", shader=sway,
                    **{"shader_parameter/sag": f"{0.012 * length:.3f}",
                       "shader_parameter/swing": f"{0.006 * length:.3f}",
                       "shader_parameter/rate": f"{0.9 + 0.35 * rand(i, 71):.3f}",
                       "shader_parameter/phase": f"{rand(i, 73) * 6.28:.3f}"})
        s.node("Board", body, "MeshInstance3D", mesh=s.mesh(f"Plank{name}", plank_mesh(length, i + 3)),
               material_override=mat, extra_cull_margin="0.3")

    # The edges: a back wall, chain-link fences, the gap in the front one.
    s.node("Edges", root, "Node3D")
    edges = (
        ("BackWall", ((X_MIN + X_MAX) / 2, 1.6, Z_MIN), (X_MAX - X_MIN, 3.2, 0.3), None, True),
        ("FenceLeft", (X_MIN, 1.0, (Z_MIN + Z_MAX) / 2), (0.08, 2.0, Z_MAX - Z_MIN), fence, False),
        ("FenceRight", (X_MAX, 1.0, (Z_MIN + Z_MAX) / 2), (0.08, 2.0, Z_MAX - Z_MIN), fence, False),
        ("FenceFrontWest", ((X_MIN + GAP_X - 0.8) / 2, 1.0, Z_MAX), (GAP_X - 0.8 - X_MIN, 2.0, 0.08), fence, False),
        ("FenceFrontEast", ((GAP_X + 0.8 + X_MAX) / 2, 1.0, Z_MAX), (X_MAX - GAP_X - 0.8, 2.0, 0.08), fence, False),
    )
    for name, pos, size, mat, occludes in edges:
        body = s.node(name, "Edges", "StaticBody3D", groups=["camera_occluder"] if occludes else None,
                      position=v3(pos), collision_layer="1", collision_mask="0")
        s.node("CollisionShape3D", body, "CollisionShape3D", shape=s.sub("BoxShape3D", f"Shape_{name}", size=v3(size)))
        if name == "BackWall":
            s.node("MeshInstance3D", body, "MeshInstance3D", mesh=s.mesh("BackWall", back_wall_mesh()),
                   material_override=wall_mat)
        else:
            s.node("MeshInstance3D", body, "MeshInstance3D", mesh=s.sub("BoxMesh", f"Box_{name}", size=v3(size)),
                   material_override=mat)
    s.node("FenceFrame", "Edges", "MeshInstance3D", mesh=s.mesh("FenceFrame", fence_frame_mesh()),
           material_override=steel_mat)
    # The gap itself stays closed to the body: the exit is how you go through it.
    s.node("GapStop", "Edges", "StaticBody3D", position=v3((GAP_X, 1.0, Z_MAX + 0.15)), collision_layer="1",
           collision_mask="0")
    s.node("CollisionShape3D", "Edges/GapStop", "CollisionShape3D",
           shape=s.sub("BoxShape3D", "Shape_gap_stop", size=v3((1.8, 2.0, 0.1))))
    s.node("GapHole", "Edges", "MeshInstance3D", position=v3((GAP_X, 0, Z_MAX + 0.2)),
           mesh=s.mesh("GapHole", flap_mesh()), material_override=hole_mat, cast_shadow="0")
    s.node("GapFlap", "Edges", "MeshInstance3D", position=v3((GAP_X + 0.85, 1.05, Z_MAX - 0.3)),
           rotation_degrees=v3((-28, -34, 0)), mesh=s.sub("BoxMesh", "Box_gap_flap", size=v3((1.1, 1.4, 0.03))),
           material_override=fence)

    # Floodlight masts, and the crane beyond the wall.
    mast = s.mesh("Mast", mast_mesh())
    for i, (x, z) in enumerate(((18.9, 15.6), (-21.6, 15.4), (-21.6, -16.6))):
        holder = s.node(f"Mast{i}", root, "Node3D", position=v3((x, 0, z)), rotation_degrees=v3((0, 45 + i * 70, 0)))
        s.node("Pole", holder, "MeshInstance3D", mesh=mast, material_override=steel_mat)
        s.node("Light", holder, "OmniLight3D", position=v3((0, 8.6, 0.6)), light_color=colour((1.0, 0.74, 0.46)),
               light_energy="1.6", omni_range="22.0", omni_attenuation="0.8")
    # The quay cranes beyond the wall are the port's own crane (build_port.py), seen far off
    # against the evening as flat dark shapes.
    for i, (x, z, yaw) in enumerate(((-6.0, -76.0, 12.0), (30.0, -82.0, 8.0))):
        s.node(f"Crane{i}", root, "MeshInstance3D", position=v3((x, 0, z)), rotation_degrees=v3((0, yaw, 0)),
               mesh=port_crane, material_override=crane_mat, cast_shadow="0")

    s.node("SpawnPoints", root, "Node3D")
    s.node("FromPlayground", "SpawnPoints", "Marker3D", groups=["spawn_point"], position=v3(SPAWN))
    s.node("FromPort", "SpawnPoints", "Marker3D", groups=["spawn_point"],
           position=v3((TRUCK_TAIL_X + 1.6, 0, TRUCK_Z)))

    s.node("Interactables", root, "Node3D")
    s.node("BackToPlayground", "Interactables", instance=exit_scene, position=v3((GAP_X, 0.9, Z_MAX - 0.6)),
           interact_id='&"cy_back_to_playground"', prompt_key='"prompt.container_yard_out"', radius="1.4",
           outline_paths='PackedStringArray("../../Edges/GapFlap")',
           destination_scene='"res://scenes/locations/playground/playground.tscn"',
           destination_spawn='&"FromContainerYard"', destination_id='&"playground"')
    s.node("ToPort", "Interactables", instance=exit_scene, position=v3((TRUCK_TAIL_X + 0.8, 0.9, TRUCK_Z)),
           interact_id='&"cy_to_port"', prompt_key='"prompt.port"', radius="1.4",
           outline_paths='PackedStringArray("../../Truck/Box")',
           destination_scene='"res://scenes/locations/port/port.tscn"',
           destination_spawn='&"FromContainerYard"', destination_id='&"port"')
    s.node("TyreLook", "Interactables", instance=look, position=v3((FLIGHT_A_X + 1.1, 0.6, face_a + 6.2)),
           interact_id='&"cy_tyres_look"', inspection_id='&"cy_tyres"', radius="1.4",
           outline_paths="PackedStringArray(" + ", ".join(f'"../../{p}"' for p in flight_a) + ")")
    s.node("PlankLook", "Interactables", instance=look, position=v3((COLS[2], 1.0, ROWS[5])),
           interact_id='&"cy_plank_look"', inspection_id='&"cy_plank"', radius="1.6",
           outline_paths='PackedStringArray("../../Planks/LongDown/Board")')
    s.node("OrangeLook", "Interactables", instance=look, position=v3((COLS[4], 1.0, ROWS[1] + CW / 2 + 0.5)),
           interact_id='&"cy_orange_look"', inspection_id='&"cy_orange"', radius="1.4",
           outline_paths='PackedStringArray("../../Containers/R1C4/Level0")')
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
            print("container yard is stale; run python3 tools/build_container_yard.py:")
            for p in bad:
                print("  ", p.relative_to(ROOT))
            return 1
        print(f"container yard up to date ({len(files)} files)")
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
