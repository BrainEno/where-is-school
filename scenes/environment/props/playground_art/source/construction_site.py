"""The building under construction in the yard's south-west corner (glossary: 建造中的大楼).

Visual-only, like the rest of the art pass: no body, no shape, no navigation. The plot is
laid *outside* the playable ground, west of the yard edge (x < -23 m), so it never sits
between the follow camera (south-east of the player) and anything the player can reach.

What stands on it, read from the yard:

* a raw earth plot pushed out from the yard edge into the laid-flat sky;
* blue hoarding with a closed, barred gate and a blank name plate over it - the school
  before it has a name;
* in front of that gate, two or three hollow sand pyramids: near-white glare on the
  sand, the top cut open, cold water standing in the dark mouth;
* a yellow excavator behind the hoarding, its arm reaching over it to the smallest pile;
* the frame of the future ellipsoid building (椭球大楼): oval floor plates that widen and
  narrow with height, columns, rebar left standing on the top deck, two drain pipes down
  its face, and the ellipsoid it will become traced in rebar hoops round all of it. The
  timber deck on top carries a chalked six-pointed board with a few odd marbles on it.

Everything is primitive meshes (cylinders, boxes, prisms, tori) so the scene stays
small; shared shapes are emitted once and instanced by reference.
"""

from __future__ import annotations

import math

# Kept inside these bounds by construction; `tests/playground_art_slice_test.gd` checks
# every art piece against the camera's sight lines, and the yard is walkable to x = -22.5.
YARD_EDGE_X = -23.05
PLOT = {"x": (-35.25, YARD_EDGE_X), "z": (7.0, 19.6), "top": -0.015}

GATE_X = -26.6
GATE_Z = (11.4, 15.0)
HOARD_H = 2.2

# Ellipsoid of the finished building: centre, half-axes (x, z) and half-height.
TOWER = {"x": -31.6, "z": 11.6, "a": 3.2, "b": 4.1, "cy": 5.4, "c": 6.3}
FLOORS = [0.25 + 2.5 * k for k in range(6)]

# (name, x, z, corner radius, height); TOP is the open top's share of the base radius.
TOP = 0.3
PILES = [
    ("PileNorth", -24.7, 12.0, 1.35, 1.7),
    ("PileMiddle", -24.85, 14.4, 1.45, 2.0),
    ("PileSouth", -24.4, 16.9, 1.0, 1.2),
]


def _v3(values) -> str:
    return "Vector3(" + ", ".join(f"{round(v, 4):g}" for v in values) + ")"


class _Kit:
    """Shared shapes, so the same box or slab is one sub-resource however often it is placed."""

    def __init__(self, b):
        self.b = b
        self.cache: dict[tuple, str] = {}

    def shape(self, kind: str, **props) -> str:
        key = (kind, tuple(sorted(props.items())))
        if key not in self.cache:
            self.cache[key] = self.b.mesh(kind, **props)
        return self.cache[key]

    def box(self, size) -> str:
        return self.shape("BoxMesh", size=_v3(size))

    def cylinder(self, r, h, *, top=None, sides=12, caps=True) -> str:
        props = {"top_radius": f"{r if top is None else top:g}", "bottom_radius": f"{r:g}",
                 "height": f"{h:g}", "radial_segments": str(sides), "rings": "0"}
        if not caps:
            props.update(cap_top="false", cap_bottom="false")
        return self.shape("CylinderMesh", **props)

    def put(self, name, parent, mesh, mat, pos, rot=None, scale=None, shadow=False):
        props = {"position": _v3(pos)}
        if rot is not None:
            props["rotation_degrees"] = _v3(rot)
        if scale is not None:
            props["scale"] = _v3(scale)
        props["mesh"] = f'SubResource("{mesh}")'
        props["material_override"] = f'ExtResource("art_{mat}")'
        if not shadow:
            props["cast_shadow"] = "0"
        self.b.node(name, parent, "MeshInstance3D", **props)


def _plot(k: _Kit, p: str) -> None:
    (x0, x1), (z0, z1), top = PLOT["x"], PLOT["z"], PLOT["top"]
    k.put("Plot", p, k.box((x1 - x0, 0.5, z1 - z0)), "site_earth",
          ((x0 + x1) / 2, top - 0.25, (z0 + z1) / 2))
    # A spill of the plot's earth onto nothing: two loose clods past its west edge.
    k.put("Spoil", p, k.cylinder(1.1, 0.5, top=0.25, sides=7), "sand_wet", (-35.6, top - 0.1, 9.4), (0, 20, 0))
    k.put("SpoilSmall", p, k.cylinder(0.6, 0.3, top=0.1, sides=6), "sand_wet", (-35.9, top - 0.2, 17.2))


def _hoarding(k: _Kit, p: str) -> None:
    y = PLOT["top"]
    post = k.box((0.1, HOARD_H + 0.15, 0.12))
    runs = [  # (name, centre x, centre z, length, along_z)
        ("HoardEastNorth", GATE_X, (7.3 + GATE_Z[0] - 0.12) / 2, GATE_Z[0] - 0.12 - 7.3, True),
        ("HoardEastSouth", GATE_X, (GATE_Z[1] + 0.12 + 19.5) / 2, 19.5 - GATE_Z[1] - 0.12, True),
        ("HoardNorth", (GATE_X - 35.2) / 2, 7.3, 35.2 + GATE_X, False),
        # The south run stops short: the last panel is down, the west side never began.
        ("HoardSouth", (GATE_X - 30.2) / 2, 19.5, 30.2 + GATE_X, False),
    ]
    count = 0
    for name, cx, cz, length, along_z in runs:
        size = (0.08, HOARD_H, length) if along_z else (length, HOARD_H, 0.08)
        band = (0.1, 0.24, length) if along_z else (length, 0.24, 0.1)
        k.put(name, p, k.box(size), "hoarding", (cx, y + HOARD_H / 2, cz), shadow=True)
        k.put(name + "Band", p, k.box(band), "pale", (cx, y + HOARD_H - 0.2, cz))
        steps = max(1, round(length / 2.0))
        for i in range(steps + 1):
            t = -length / 2 + length * i / steps
            # Posts stand on the yard side (east run) or the inside (north and south runs).
            where = (cx + 0.09, y + (HOARD_H + 0.15) / 2, cz + t) if along_z else \
                    (cx + t, y + (HOARD_H + 0.15) / 2, cz + (0.09 if name == "HoardNorth" else -0.09))
            k.put(f"Post_{count}", p, post, "metal_ink", where)
            count += 1
    k.put("FallenPanel", p, k.box((2.0, 0.08, HOARD_H)), "hoarding", (-31.5, y + 0.06, 18.3), (0, -12, 4))

    # The closed gate: two barred leaves meeting in the middle, chained, under a blank plate.
    z0, z1 = GATE_Z
    mid, leaf = (z0 + z1) / 2, (z1 - z0) / 2 - 0.04
    gate_post = k.box((0.24, 2.9, 0.24))
    k.put("GatePostNorth", p, gate_post, "metal_ink", (GATE_X, y + 1.45, z0))
    k.put("GatePostSouth", p, gate_post, "metal_ink", (GATE_X, y + 1.45, z1))
    for name, zc in (("GateLeafNorth", (z0 + mid) / 2), ("GateLeafSouth", (mid + z1) / 2)):
        k.put(name, p, k.box((0.05, 2.05, leaf)), "fence_panel_tall", (GATE_X, y + 1.08, zc))
        k.put(name + "Rail", p, k.box((0.07, 0.08, leaf)), "metal_ink", (GATE_X, y + 2.1, zc))
    k.put("GateStiles", p, k.box((0.08, 2.1, 0.1)), "metal_ink", (GATE_X, y + 1.1, mid))
    k.put("GateChain", p, k.box((0.1, 0.34, 0.22)), "metal_ink", (GATE_X + 0.06, y + 1.12, mid), (0, 0, 8))
    k.put("GateLock", p, k.box((0.07, 0.15, 0.11)), "brass", (GATE_X + 0.12, y + 0.92, mid), shadow=True)
    k.put("GateLintel", p, k.box((0.18, 0.18, z1 - z0 + 0.4)), "metal_ink", (GATE_X, y + 2.95, mid))
    # The name plate is blank. Whatever the school will be called is not up yet.
    k.put("NamePlate", p, k.box((0.06, 0.5, 2.3)), "pale", (GATE_X + 0.04, y + 3.35, mid))
    k.put("NamePlateRim", p, k.box((0.05, 0.58, 2.4)), "metal_ink", (GATE_X - 0.01, y + 3.35, mid))


def _sand(k: _Kit, p: str) -> None:
    y = PLOT["top"]
    for name, x, z, r, h in PILES:
        k.b.node(name, p, position=_v3((x, y, z)))
        q = f"{p}/{name}"
        # Wet, dark sand at the foot; the pyramid above it is all glare.
        collar = 0.22
        k.put("Collar", q, k.cylinder(r * 1.12, collar, top=r * (1 - (1 - TOP) * collar / h) * 1.02, sides=4), "sand_wet",
              (0, collar / 2, 0), shadow=True)
        k.put("Body", q, k.cylinder(r, h, top=r * TOP, sides=4), "sand_glare", (0, h / 2, 0), shadow=True)
        # Hollow: the top is cut off and open. From the follow camera, which looks down at
        # about 53 degrees, the cut reads as a dark mouth with cold water standing in it.
        k.put("Mouth", q, k.cylinder(r * TOP * 0.86, 0.02, sides=4), "metal_ink", (0, h + 0.006, 0))
        k.put("Water", q, k.cylinder(r * TOP * 0.62, 0.02, sides=4), "cold_water", (0, h + 0.014, 0))
    # A lone work lamp on the hoarding throws the glare on them.
    k.put("LampPole", p, k.box((0.1, 4.4, 0.1)), "metal_ink", (GATE_X - 0.25, y + 2.2, 9.7))
    k.put("LampHead", p, k.box((0.22, 0.42, 0.8)), "metal_ink", (GATE_X - 0.05, y + 4.35, 9.7), (0, 0, -28))
    k.put("LampFace", p, k.box((0.03, 0.34, 0.7)), "lane_light", (GATE_X + 0.07, y + 4.3, 9.7), (0, 0, -28))


def _excavator(k: _Kit, p: str) -> None:
    y = PLOT["top"]
    k.b.node("Excavator", p, position=_v3((-29.7, y, 17.0)))
    q = f"{p}/Excavator"
    track = k.box((3.0, 0.7, 0.55))
    k.put("TrackNorth", q, track, "metal_ink", (0, 0.35, -0.95), shadow=True)
    k.put("TrackSouth", q, track, "metal_ink", (0, 0.35, 0.95), shadow=True)
    k.put("Undercarriage", q, k.box((1.6, 0.35, 1.3)), "metal_ink", (0, 0.65, 0))
    k.put("House", q, k.box((2.4, 0.95, 2.1)), "frame_yellow", (-0.25, 1.3, 0), shadow=True)
    k.put("Counterweight", q, k.cylinder(1.0, 0.85, sides=10), "frame_yellow", (-1.3, 1.26, 0), scale=(0.45, 1, 1.0))
    k.put("Hood", q, k.box((1.1, 0.34, 1.0)), "frame_yellow", (-0.85, 1.94, -0.45))
    k.put("Exhaust", q, k.cylinder(0.05, 0.55, sides=8), "metal_ink", (-0.9, 2.35, -0.78))
    k.put("Cab", q, k.box((1.0, 1.15, 0.95)), "frame_yellow", (0.45, 2.35, 0.55), shadow=True)
    k.put("CabFront", q, k.box((0.04, 0.78, 0.8)), "glass", (0.96, 2.45, 0.55))
    k.put("CabSide", q, k.box((0.8, 0.7, 0.04)), "glass", (0.42, 2.47, 1.03))
    # Boom up over the hoarding, stick down towards the smallest pile.
    pivot, boom_len, boom_deg = (0.75, 1.65), 3.6, 38.0
    stick_len, stick_deg = 2.3, -62.0
    bx, by = pivot[0] + math.cos(math.radians(boom_deg)) * boom_len, pivot[1] + math.sin(math.radians(boom_deg)) * boom_len
    k.put("Boom", q, k.box((boom_len, 0.4, 0.34)), "frame_yellow",
          ((pivot[0] + bx) / 2, (pivot[1] + by) / 2, -0.35), (0, 0, boom_deg), shadow=True)
    sx = bx + math.cos(math.radians(stick_deg)) * stick_len
    sy = by + math.sin(math.radians(stick_deg)) * stick_len
    k.put("Stick", q, k.box((stick_len, 0.3, 0.28)), "frame_yellow", ((bx + sx) / 2, (by + sy) / 2, -0.35),
          (0, 0, stick_deg), shadow=True)
    k.put("Knuckle", q, k.cylinder(0.2, 0.42, sides=10), "metal_ink", (bx, by, -0.35), (90, 0, 0))
    # The lift ram runs from the house front to the middle of the boom's underside.
    ram_a = (pivot[0] + 0.3, pivot[1] - 0.3)
    ram_b = (pivot[0] + math.cos(math.radians(boom_deg)) * boom_len * 0.55,
             pivot[1] + math.sin(math.radians(boom_deg)) * boom_len * 0.55 - 0.12)
    ram_deg = math.degrees(math.atan2(ram_b[1] - ram_a[1], ram_b[0] - ram_a[0]))
    k.put("Ram", q, k.cylinder(0.06, math.dist(ram_a, ram_b), sides=6), "exit_steel",
          ((ram_a[0] + ram_b[0]) / 2, (ram_a[1] + ram_b[1]) / 2, -0.35), (0, 0, ram_deg - 90))
    k.put("Bucket", q, k.shape("PrismMesh", left_to_right="0.0", size=_v3((0.75, 0.7, 0.8))), "metal_ink",
          (sx + 0.1, sy - 0.25, -0.35), (0, 0, 155), shadow=True)


def _ellipse_point(f: float, angle: float, grow: float = 0.0):
    t = TOWER
    return (t["x"] + (t["a"] * f + grow) * math.cos(angle), t["z"] + (t["b"] * f + grow) * math.sin(angle))


def _profile(y: float) -> float:
    t = TOWER
    return math.sqrt(max(0.0, 1.0 - ((y - t["cy"]) / t["c"]) ** 2))


def _tower(k: _Kit, p: str) -> None:
    t, y0 = TOWER, PLOT["top"]
    k.b.node("EllipsoidFrame", p)
    q = f"{p}/EllipsoidFrame"
    slab = k.cylinder(1.0, 0.24, sides=28)
    column = k.box((0.22, 2.28, 0.22))
    poured = 4  # floors 0..3 are concrete; floor 4 is timber formwork; floor 5 is not built
    k.put("Core", q, k.cylinder(1.0, FLOORS[poured], sides=12), "slab",
          (t["x"], y0 + FLOORS[poured] / 2, t["z"]), scale=(t["a"] * 0.14, 1, t["b"] * 0.14), shadow=True)
    for i, y in enumerate(FLOORS[: poured + 1]):
        f = _profile(y)
        mat = "slab" if i < poured else "container_deck"
        k.put(f"Floor_{i}", q, slab, mat, (t["x"], y0 + y, t["z"]), scale=(t["a"] * f, 1, t["b"] * f), shadow=True)
        if i == poured:
            break
        # Columns stand inside the narrower of the two plates they join.
        ring = min(f, _profile(FLOORS[i + 1])) * 0.82
        for j in range(8):
            cx, cz = _ellipse_point(ring, j * math.tau / 8 + math.pi / 8)
            k.put(f"Column_{i}_{j}", q, column, "slab", (cx, y0 + y + 1.25, cz), shadow=True)
    # Rebar left standing on the top deck, where the next storey should go.
    bar = k.box((0.05, 1.3, 0.05))
    top_y, ring = FLOORS[poured], _profile(FLOORS[poured]) * 0.82
    for j in range(8):
        cx, cz = _ellipse_point(ring, j * math.tau / 8 + math.pi / 8)
        k.put(f"Rebar_{j}", q, bar, "metal_ink", (cx, y0 + top_y + 0.75, cz), (0, 0, 4 * (j % 3 - 1)))
    # The ellipsoid it will become: two rebar meridians and three latitude hoops, drawn
    # round the frame at full size. Torus tubes are thin before scaling, so they stay wire.
    hoop = k.shape("TorusMesh", inner_radius="0.985", outer_radius="1.0", rings="40", ring_segments="4")
    k.put("MeridianX", q, hoop, "metal_ink", (t["x"], y0 + t["cy"], t["z"]), (90, 0, 0),
          (t["a"] + 0.3, 1, t["c"]))
    k.put("MeridianZ", q, hoop, "metal_ink", (t["x"], y0 + t["cy"], t["z"]), (90, 90, 0),
          (t["b"] + 0.3, 1, t["c"]))
    for i, y in enumerate((t["cy"], FLOORS[poured] + 1.4, t["cy"] + t["c"] * 0.92)):
        f = _profile(y)
        k.put(f"Latitude_{i}", q, hoop, "metal_ink", (t["x"], y0 + y, t["z"]), None,
              (t["a"] * f + 0.3, 1, t["b"] * f + 0.3))
    # Two drain pipes down the face turned to the yard; every flush shakes the frame.
    for i, angle in enumerate((math.radians(38), math.radians(58))):
        px, pz = _ellipse_point(1.0, angle, 0.2)
        k.put(f"DrainPipe_{i}", q, k.cylinder(0.08, FLOORS[poured] + 0.4, sides=8), "exit_steel",
              (px, y0 + (FLOORS[poured] + 0.4) / 2, pz), shadow=True)
        for j, y in enumerate(FLOORS[1:poured]):
            ex, ez = _ellipse_point(_profile(y), angle)
            dx, dz = px - ex, pz - ez
            reach = math.hypot(dx, dz)
            k.put(f"DrainBracket_{i}_{j}", q, k.box((reach, 0.06, 0.06)), "metal_ink",
                  ((px + ex) / 2, y0 + y + 0.3, (pz + ez) / 2), (0, -math.degrees(math.atan2(dz, dx)), 0))
    # The board on the top deck: a chalked six-pointed star and marbles that match nothing.
    deck_y = y0 + FLOORS[poured] + 0.125
    side, tall = 2.3, 2.3 * math.sqrt(3) / 2
    star = k.shape("PrismMesh", size=_v3((side, tall, 0.012)))
    for i, yaw in enumerate((0, 180)):
        # A prism is centred on its bounding box; shift each triangle so the centroids meet.
        shift = tall / 6 * (-1 if yaw == 0 else 1)
        k.put(f"Board_{i}", q, star, "pale", (t["x"], deck_y + 0.008 + 0.002 * i, t["z"] + shift), (-90, yaw, 0))
    marble = k.shape("SphereMesh", radius="0.07", height="0.14", radial_segments="8", rings="4")
    for i, mat in enumerate(("ball", "hoop_rim", "door_green", "container", "fire_door", "brass")):
        angle = i * math.tau / 6 + 0.3 * (i % 2)
        k.put(f"Marble_{i}", q, marble, mat,
              (t["x"] + 0.78 * math.cos(angle), deck_y + 0.08, t["z"] + 0.78 * math.sin(angle)))


def build(b, art: str) -> None:
    """Adds `<art>/ConstructionSite` to the yard art pass."""
    b.node("ConstructionSite", art)
    p = f"{art}/ConstructionSite"
    k = _Kit(b)
    _plot(k, p)
    _hoarding(k, p)
    _sand(k, p)
    _excavator(k, p)
    _tower(k, p)
