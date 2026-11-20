"""Visual-only construction site, beyond the playable schoolyard's south-west edge.

The curves and recesses in the shell, sand and machinery are baked by site_meshes.
Existing yard bounds, camera, navigation and collision are not part of this pass.
"""

from __future__ import annotations

import math

import site_meshes

# The yard is walkable to x = -22.5. Nothing here stands between it and the camera.
YARD_EDGE_X = -23.05
PLOT = {"x": (-35.25, YARD_EDGE_X), "z": (7.0, 19.6), "top": -0.015}
GATE_X = -26.6
GATE_Z = (11.4, 15.0)
HOARD_H = 2.2

TOWER = {"x": -31.6, "z": 11.6, "a": 3.2, "b": 4.1, "cy": 5.4, "c": 6.3}
CAST_JOINTS = (2.75, 5.25, 7.75)
DECK = 10.25
PILES = (
    ("PileNorth", -24.7, 12.0, 1.28, 1.7, 0.91),
    ("PileMiddle", -24.85, 14.4, 1.37, 2.0, 0.86),
    ("PileSouth", -24.4, 16.9, 0.96, 1.2, 1.03),
)


def _v3(values) -> str:
    return "Vector3(" + ", ".join(f"{round(v, 4):g}" for v in values) + ")"


class _Kit:
    """Share repeated shapes and materials; imported shapes are also instanced."""

    def __init__(self, b):
        self.b = b
        self.cache: dict[tuple, str] = {}

    def shape(self, kind: str, **props) -> str:
        key = (kind, tuple(sorted(props.items())))
        if key not in self.cache:
            self.cache[key] = self.b.mesh(kind, **props)
        return self.cache[key]

    def cylinder(self, r, h, *, sides=12) -> str:
        return self.shape("CylinderMesh", top_radius=f"{r:g}", bottom_radius=f"{r:g}",
                          height=f"{h:.5f}", radial_segments=str(sides), rings="0")

    def put(self, name, parent, mesh, mat, pos, rot=None, scale=None, *, shadow=False, imported=False):
        props = {"position": _v3(pos)}
        if rot is not None:
            props["rotation_degrees"] = _v3(rot)
        if scale is not None:
            props["scale"] = _v3(scale)
        if imported:
            self.b.imported_meshes.add(mesh)
            props["mesh"] = f'ExtResource("mesh_{mesh}")'
        else:
            props["mesh"] = f'SubResource("{mesh}")'
        props["material_override"] = f'ExtResource("art_{mat}")'
        if not shadow:
            props["cast_shadow"] = "0"
        self.b.node(name, parent, "MeshInstance3D", **props)

    def box(self, name, p, size, mat, pos, rot=None, *, shadow=False):
        self.put(name, p, self.shape("BoxMesh", size=_v3(size)), mat, pos, rot, shadow=shadow)

    def case(self, name, p, size, mat, pos, rot=None, *, shadow=False):
        self.put(name, p, "site_beveled_case", mat, pos, rot, size, shadow=shadow, imported=True)

    def pipe(self, name, p, start, end, radius, mat, *, shadow=False):
        # CylinderMesh points along +Y. Godot's YXZ Euler order pitches it, then yaws it.
        dx, dy, dz = (b - a for a, b in zip(start, end))
        length = math.dist(start, end)
        pitch = math.degrees(math.atan2(math.hypot(dx, dz), dy))
        yaw = math.degrees(math.atan2(dx, dz))
        self.put(name, p, self.cylinder(radius, length), mat,
                 tuple((a + b) / 2 for a, b in zip(start, end)), (pitch, yaw, 0), shadow=shadow)


def _plot(k: _Kit, p: str) -> None:
    (x0, x1), (z0, z1), y = PLOT["x"], PLOT["z"], PLOT["top"]
    k.box("Plot", p, (x1 - x0, 0.5, z1 - z0), "site_earth", ((x0 + x1) / 2, y - 0.25, (z0 + z1) / 2))
    k.case("MachineBed", p, (5.1, 0.024, 2.95), "site_compacted", (-30.1, y + 0.003, 16.97), (0, -5, 0))
    # A little grading spoil at the edge, not a second playable platform in the sky.
    k.case("Spoil", p, (2.4, 0.45, 1.6), "site_compacted", (-35.5, y - 0.12, 9.4), (0, -18, -10))
    k.case("SpoilSmall", p, (1.2, 0.28, 0.9), "site_compacted", (-35.6, y - 0.17, 17.2), (0, 21, 9))


def _hoarding(k: _Kit, p: str) -> None:
    y = PLOT["top"]
    runs = (
        ("HoardEastNorth", (GATE_X, 7.3), (GATE_X, GATE_Z[0] - 0.12)),
        ("HoardEastSouth", (GATE_X, GATE_Z[1] + 0.12), (GATE_X, 19.5)),
        ("HoardNorth", (-35.2, 7.3), (GATE_X, 7.3)),
        ("HoardSouth", (-30.2, 19.5), (GATE_X, 19.5)),
    )
    for name, (x0, z0), (x1, z1) in runs:
        along_z = x0 == x1
        turn = (0, 90, 0) if along_z else ((0, 180, 0) if name == "HoardNorth" else None)
        bays = max(1, round(math.dist((x0, z0), (x1, z1)) / 1.85))
        width = math.dist((x0, z0), (x1, z1)) / bays
        outward_x = 1.0 if along_z else 0.0
        outward_z = 0.0 if along_z else (-1.0 if name == "HoardNorth" else 1.0)

        def where(t, height, offset=0.0):
            return (x0 + (x1 - x0) * t + outward_x * offset, y + height,
                    z0 + (z1 - z0) * t + outward_z * offset)

        for i in range(bays):
            t = (i + 0.5) / bays
            mat = "hoarding" if i % 3 else "hoard_fold"
            k.put(f"{name}Panel{i}", p, "site_panel", mat, where(t, HOARD_H / 2), turn,
                  (width - 0.027, HOARD_H, 1.0), shadow=True, imported=True)
            k.box(f"{name}Coping{i}", p, (width - 0.018, 0.14, 0.112), "pale",
                  where(t, HOARD_H - 0.064), turn)
        for i in range(bays + 1):
            k.box(f"{name}Post{i}", p, (0.111, HOARD_H + 0.09, 0.132), "site_steel",
                  where(i / bays, (HOARD_H + 0.09) / 2, 0.068), turn)

    # The last panel fell inward. Its folded face and pale cap still match the uprights.
    k.b.node("FallenPanel", p, position=_v3((-31.48, y + 0.09, 18.30)), rotation_degrees=_v3((0, -12, 3)))
    down = f"{p}/FallenPanel"
    k.put("Sheet", down, "site_panel", "hoarding", (0, 0, 0), (-90, 0, 0), (2.0, HOARD_H, 1.0),
          imported=True)
    k.box("Coping", down, (1.99, 0.13, 0.14), "pale", (0, 0.012, -HOARD_H / 2 + 0.06))

    # Two closed leaves: actual bars, hinge sleeves and a linked chain. The sign stays blank.
    z0, z1 = GATE_Z
    mid, leaf = (z0 + z1) / 2, (z1 - z0) / 2 - 0.17
    for name, z, sign in (("North", z0, 1), ("South", z1, -1)):
        k.box("GatePost" + name, p, (0.22, 2.94, 0.25), "site_steel", (GATE_X, y + 1.47, z))
        k.box("GateShoe" + name, p, (0.39, 0.18, 0.39), "slab", (GATE_X, y + 0.09, z))
        center = z + sign * (0.14 + leaf / 2)
        k.put("GateLeaf" + name, p, "site_gate_leaf", "site_steel", (GATE_X, y, center),
              scale=(1.0, 1.0, leaf), shadow=True, imported=True)
        for i, h in enumerate((0.37, 1.96)):
            k.put(f"GateHinge{name}{i}", p, k.cylinder(0.048, 0.18), "exit_steel",
                  (GATE_X + 0.061, y + h, z + sign * 0.126))
    link = k.shape("TorusMesh", inner_radius="0.039", outer_radius="0.053", rings="12", ring_segments="6")
    for i in range(7):
        dz = (i - 3) * 0.066
        k.put(f"GateChain{i}", p, link, "exit_steel", (GATE_X + 0.084, y + 1.07 + 1.3 * dz * dz, mid + dz),
              (0, 0, 86 if i % 2 else 11), (0.84, 1.0, 1.06))
    k.put("LockShackle", p, link, "exit_steel", (GATE_X + 0.11, y + 1.006, mid + 0.03),
          (0, 0, 90), (1.0, 1.0, 0.91))
    k.case("GateLock", p, (0.075, 0.13, 0.119), "brass", (GATE_X + 0.11, y + 0.93, mid + 0.03))
    k.box("GateLintel", p, (0.19, 0.17, z1 - z0 + 0.39), "site_steel", (GATE_X, y + 2.88, mid))
    k.box("NamePlateRim", p, (0.1, 0.48, 2.42), "site_steel", (GATE_X, y + 3.15, mid))
    k.box("NamePlate", p, (0.053, 0.393, 2.30), "pale", (GATE_X + 0.054, y + 3.15, mid))
    for i, dz in enumerate((-1.05, 1.05)):
        k.put(f"NamePlateBolt{i}", p, k.cylinder(0.024, 0.014), "exit_steel",
              (GATE_X + 0.084, y + 3.15, mid + dz), (0, 0, 90))

    k.box("LampFoot", p, (0.34, 0.13, 0.34), "slab", (GATE_X - 0.25, y + 0.065, 9.7))
    k.box("LampPole", p, (0.092, 4.25, 0.098), "site_steel", (GATE_X - 0.25, y + 2.125, 9.7))
    k.pipe("LampBrace", p, (GATE_X - 0.25, y + 3.96, 9.7), (GATE_X + 0.02, y + 4.21, 9.7), 0.046, "site_steel")
    k.case("LampHead", p, (0.21, 0.31, 0.56), "site_steel", (GATE_X + 0.01, y + 4.26, 9.7), (0, 0, -26))
    k.box("LampFace", p, (0.028, 0.21, 0.43), "lane_light", (GATE_X + 0.11, y + 4.21, 9.7), (0, 0, -26))


def _sand(k: _Kit, p: str) -> None:
    y = PLOT["top"]
    for name, x, z, r, h, stretch in PILES:
        k.b.node(name, p, position=_v3((x, y, z)), scale=_v3((r, h, r * stretch)))
        q = f"{p}/{name}"
        k.case("SpilledSand", q, (2.03, 0.073, 2.03), "sand_wet", (-0.035, 0.016, 0.02), (0, -2, 0))
        k.put("Body", q, "site_sand_body", "sand_glare", (0, 0, 0), shadow=True, imported=True)
        k.put("Basin", q, "site_sand_basin", "sand_wet", (0, 0, 0), imported=True)
        # Slightly overfill the section below the rim: the soil occludes the disk's edge.
        k.put("Water", q, k.cylinder(0.246, 0.018, sides=28), "cold_water", (-0.049, 0.82, 0.033))
        k.box("WaterGlint", q, (0.213, 0.004, 0.017), "water_glint", (-0.064, 0.831, 0.062), (0, 7, 0))


def _excavator(k: _Kit, p: str) -> None:
    k.b.node("Excavator", p, position=_v3((-29.7, PLOT["top"], 17.0)))
    q = f"{p}/Excavator"
    for id_, z, side in (("North", -0.95, -1), ("South", 0.95, 1)):
        k.put("Track" + id_, q, "site_track_belt", "site_steel", (0, 0, z), shadow=True, imported=True)
        for i, x in enumerate((-1.12, -0.59, 0, 0.59, 1.12)):
            r = 0.236 if i in (0, 4) else 0.195
            k.put(f"Roller{id_}{i}", q, k.cylinder(r, 0.088), "hoard_fold",
                  (x, 0.335, z + side * 0.257), (90, 0, 0))
            k.put(f"Hub{id_}{i}", q, k.cylinder(r * 0.47, 0.038), "exit_steel",
                  (x, 0.335, z + side * 0.307), (90, 0, 0))
    k.box("Undercarriage", q, (1.55, 0.32, 1.64), "site_steel", (0.0, 0.62, 0))
    k.put("SlewRing", q, k.cylinder(0.66, 0.24, sides=24), "site_steel", (-0.14, 0.9, 0))
    k.case("House", q, (2.54, 0.69, 2.14), "site_yellow", (-0.24, 1.30, 0), shadow=True)
    k.case("Counterweight", q, (0.83, 0.62, 2.04), "site_yellow", (-1.2, 1.37, -0.05))
    k.case("ServiceHood", q, (1.20, 0.66, 1.06), "site_yellow", (-0.82, 1.80, -0.44))
    k.box("ServiceVent", q, (0.58, 0.25, 0.053), "site_steel", (-0.88, 1.84, -0.953))
    for i in range(4):
        k.box(f"VentLouver{i}", q, (0.47, 0.026, 0.047), "exit_steel", (-0.88, 1.75 + i * 0.061, -0.981))
    k.pipe("Exhaust", q, (-1.13, 2.08, -0.70), (-1.13, 2.42, -0.70), 0.057, "site_steel")
    k.pipe("ExhaustTip", q, (-1.13, 2.41, -0.70), (-1.24, 2.49, -0.70), 0.058, "site_steel")

    # Glazing has frames and a broad reflection, not a black box painted onto the cab.
    # The windscreen is a dark opaque insert at this distance; there is no cab interior.
    k.case("Cab", q, (1.05, 1.33, 0.98), "site_steel", (0.38, 2.17, 0.52), shadow=True)
    k.case("CabRoof", q, (1.12, 0.145, 1.044), "site_yellow", (0.37, 2.85, 0.52))
    k.box("CabDoor", q, (0.86, 0.37, 0.048), "site_yellow", (0.37, 1.77, 1.006))
    k.box("SideGlass", q, (0.81, 0.665, 0.037), "site_glass", (0.37, 2.36, 1.011))
    k.box("FrontGlass", q, (0.038, 0.67, 0.815), "site_glass", (0.91, 2.36, 0.52))
    k.box("WindowMullion", q, (0.063, 0.69, 0.038), "site_steel", (0.55, 2.36, 1.04), (0, 0, -4))
    k.box("GlassSky", q, (0.68, 0.05, 0.006), "exit_steel", (0.37, 2.61, 1.034), (0, 0, 2))
    k.box("CabHandle", q, (0.175, 0.032, 0.027), "exit_steel", (0.24, 1.924, 1.042))
    k.box("Step", q, (0.68, 0.086, 0.33), "site_steel", (0.39, 1.01, 1.05))

    # The boom reaches the smallest sand pile from behind the hoarding.
    pivot, boom_len, boom_deg = (0.75, 1.65), 3.6, 38.0
    stick_len, stick_deg = 2.3, -62.0
    bx = pivot[0] + math.cos(math.radians(boom_deg)) * boom_len
    by = pivot[1] + math.sin(math.radians(boom_deg)) * boom_len
    sx = bx + math.cos(math.radians(stick_deg)) * stick_len
    sy = by + math.sin(math.radians(stick_deg)) * stick_len
    arm_z = -0.35
    k.case("Boom", q, (boom_len + 0.16, 0.46, 0.37), "site_yellow",
           ((pivot[0] + bx) / 2, (pivot[1] + by) / 2, arm_z), (0, 0, boom_deg), shadow=True)
    k.case("Stick", q, (stick_len + 0.1, 0.32, 0.30), "site_yellow",
           ((bx + sx) / 2, (by + sy) / 2, arm_z), (0, 0, stick_deg), shadow=True)
    for name, x, y, r in (("Saddle", *pivot, 0.22), ("Knuckle", bx, by, 0.187), ("BucketPin", sx, sy, 0.11)):
        k.put(name, q, k.cylinder(r, 0.44), "site_steel", (x, y, arm_z), (90, 0, 0))
        k.put(name + "End", q, k.cylinder(r * 0.59, 0.053), "exit_steel", (x, y, arm_z + 0.23), (90, 0, 0))
    for name, start, stop in (
        ("LiftRam", (1.18, 1.34, -0.08), (2.34, 2.72, -0.08)),
        ("StickRam", (2.98, 3.46, -0.51), (4.09, 2.98, -0.51)),
    ):
        shoulder = tuple(a + (b - a) * 0.65 for a, b in zip(start, stop))
        k.pipe(name + "Barrel", q, start, shoulder, 0.084, "site_steel")
        k.pipe(name + "Piston", q, shoulder, stop, 0.042, "exit_steel")
    k.b.node("Bucket", q, position=_v3((sx - 0.025, sy - 0.29, arm_z)), rotation_degrees=_v3((0, 0, -10)))
    scoop = f"{q}/Bucket"
    k.put("Scoop", scoop, "site_bucket", "site_steel", (0, 0, 0), shadow=True, imported=True)
    for i in range(4):
        k.case(f"Tooth{i}", scoop, (0.205, 0.086, 0.104), "exit_steel", (0.369, -0.206, (i - 1.5) * 0.174))


def _radii(y):
    t = TOWER
    f = math.sqrt(max(0.0, 1.0 - ((y - t["cy"]) / t["c"]) ** 2))
    return t["a"] * f, t["b"] * f


def _tower(k: _Kit, p: str) -> None:
    k.b.node("EllipsoidBuilding", p, position=_v3((TOWER["x"], PLOT["top"], TOWER["z"])))
    q = f"{p}/EllipsoidBuilding"
    # The placed storeys are enclosed on every side. The unfinished work is on top,
    # not a transparent body or a set of hoops showing internal slabs through the facade.
    k.put("CastShell", q, "site_cast_shell", "slab", (0, 0, 0), shadow=True, imported=True)
    a, b = _radii(DECK)
    k.put("FormworkRim", q, k.cylinder(1.0, 0.22, sides=64), "container_deck", (0, DECK + 0.015, 0),
          scale=(a + 0.042, 1, b + 0.05), shadow=True)
    deck_y = DECK + 0.125
    for i in range(-4, 5):
        z = i * b / 5.2
        span = 2 * a * math.sqrt(1 - (z / b) ** 2)
        k.box(f"DeckJoint{i + 4}", q, (span, 0.008, 0.021), "site_steel", (0, deck_y + 0.004, z))
    for i in range(8):
        t = (i + 0.2) * math.tau / 8
        for j in range(2):
            h = 0.82 + 0.16 * ((i + j) % 3) - 0.18 * j
            k.put(f"Rebar{i}_{j}", q, k.cylinder(0.022, h, sides=8), "site_steel",
                  (0.83 * a * math.cos(t + 0.043 * j), deck_y + h / 2, 0.83 * b * math.sin(t + 0.043 * j)),
                  (0, 0, 2 - 5 * j))

    for i, angle in enumerate((-0.16, 0.57)):
        def point(y, stand_off):
            px, pz = _radii(y)
            return (px + stand_off) * math.cos(angle), y, (pz + stand_off) * math.sin(angle)

        # The pipe follows the batter of the concrete, with sleeves at the bends.
        heights = (0.31, 1.02, 3.2, 5.4, 7.65, 9.65, DECK - 0.02)
        for j, (lo, hi) in enumerate(zip(heights, heights[1:])):
            k.pipe(f"DrainPipe{i}_{j}", q, point(lo, 0.205), point(hi, 0.205), 0.072, "exit_steel")
        for j, y in enumerate(heights[1:-1]):
            k.pipe(f"DrainSleeve{i}_{j}", q, point(y - 0.089, 0.205), point(y + 0.089, 0.205), 0.094, "site_steel")
            k.pipe(f"DrainStay{i}_{j}", q, point(y, -0.115), point(y, 0.205), 0.039, "site_steel")

    # Chalk outlines and six marbles stay on the timber deck, seen only from above.
    for i, turn in enumerate((0, math.pi)):
        tips = [(1.17 * math.cos(turn + j * math.tau / 3), deck_y + 0.013,
                 1.17 * math.sin(turn + j * math.tau / 3)) for j in range(3)]
        for j, start in enumerate(tips):
            k.pipe(f"ChalkLine{i}_{j}", q, start, tips[(j + 1) % 3], 0.014, "pale")
    marble = k.shape("SphereMesh", radius="0.07", height="0.14", radial_segments="12", rings="6")
    for i, mat in enumerate(("ball", "hoop_rim", "door_green", "container", "fire_door", "brass")):
        angle = i * math.tau / 6 + 0.3 * (i % 2)
        k.put(f"Marble_{i}", q, marble, mat, (0.68 * math.cos(angle), deck_y + 0.073, 0.68 * math.sin(angle)))


def write_assets(art_dir, res_prefix) -> None:
    site_meshes.write_assets(art_dir, res_prefix, _radii, DECK, CAST_JOINTS)


def build(b, art: str) -> None:
    b.node("ConstructionSite", art)
    p = f"{art}/ConstructionSite"
    k = _Kit(b)
    _plot(k, p)
    _hoarding(k, p)
    _sand(k, p)
    _excavator(k, p)
    _tower(k, p)
