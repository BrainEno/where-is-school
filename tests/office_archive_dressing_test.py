#!/usr/bin/env python3
"""The postmodern offices and the Kafka archive (docs/OFFICE_ARCHIVE_ART.md) stay out of the way.

Round 2 of the environment-art experiment adds furniture with colliders to three optional
rooms and dresses the 03 staff office. Godot only runs in CI, so this reads the generated
scenes directly and checks what would break play first:

1. **Merged meshes face outward.** `dressing_geometry.Batch` boxes and lofts are wound so
   Godot's back-face culling keeps their outsides (a box's every face normal points away
   from its centre).
2. **The reading stance and the way to it stay clear.** In the archive, the vacant office
   and the principal's office, no collider footprint comes within the navigation agent's
   radius plus a margin of the observation stance, of the entry spawn, or of the straight
   walk between them.
3. **The staff office adds no collider.** Its dressing is visual; the desk, pedestals and
   chair keep the exact collision boxes the office tests were measured against.

Run it with ``python3 tests/office_archive_dressing_test.py``. Standard library only.
"""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from dressing_geometry import Batch, prism  # noqa: E402

CLEARANCE = .55   # agent radius (0.5, location_navigation.gd) plus a margin
SPAWN = (2.86, 2.18)
STANCES = {"archive": (1.04, -.39), "vacant_office": (1.09, -.34), "principal_office": (1.47, -.34)}
STAFF_SHAPES = {
    "Desk/Collision": "Vector3(2.6, 0.086, 1.04)",
    "Pedestal0/Collision": "Vector3(0.36, 0.768, 0.85)",
    "Pedestal1/Collision": "Vector3(0.36, 0.768, 0.85)",
    "Chair/Collision": "Vector3(0.49, 0.094, 0.5)",
}
failures: list[str] = []


def check(ok: bool, message: str) -> None:
    if not ok:
        failures.append(message)


def numbers(text: str) -> list[float]:
    return [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?(?:e-?\d+)?", text[text.index("(") + 1:])]


def nodes(path: Path):
    text = path.read_text(encoding="utf-8")
    shapes = dict(re.findall(r'\[sub_resource type="BoxShape3D" id="([^"]+)"\]\nsize = (Vector3\([^)]*\))', text))
    for block in re.split(r"\n(?=\[node )", text)[1:]:
        head, _, body = block.partition("\n")
        props = dict(re.findall(r"^([\w/]+) = (.*)$", body, re.M))
        name = re.search(r'name="([^"]+)"', head).group(1)
        parent = re.search(r'parent="([^"]+)"', head)
        kind = re.search(r'type="([^"]+)"', head)
        yield name, parent.group(1) if parent else None, kind.group(1) if kind else None, props, shapes


def footprints(path: Path):
    """World XZ corners of every box collider that reaches body height."""
    frames = {".": ((0.0, 0.0, 0.0), 0.0)}
    found = []
    for name, parent, kind, props, shapes in nodes(path):
        if parent is None:
            continue
        key = name if parent == "." else f"{parent}/{name}"
        origin, yaw = frames.get(parent, ((0.0, 0.0, 0.0), 0.0))
        pos = numbers(props.get("position", "Vector3(0, 0, 0)"))
        rot = numbers(props.get("rotation_degrees", "Vector3(0, 0, 0)"))
        a = math.radians(yaw)
        world = (origin[0] + pos[0] * math.cos(a) + pos[2] * math.sin(a), origin[1] + pos[1],
                 origin[2] - pos[0] * math.sin(a) + pos[2] * math.cos(a))
        frames[key] = (world, yaw + rot[1])
        if kind != "CollisionShape3D":
            continue
        ref = re.search(r'SubResource\("([^"]+)"\)', props.get("shape", ""))
        if not ref or ref.group(1) not in shapes:
            continue
        sx, sy, sz = numbers(shapes[ref.group(1)])
        if world[1] + sy / 2 < .2 or world[1] - sy / 2 > 1.8:
            continue
        b = math.radians(yaw + rot[1])
        corners = [(world[0] + u * math.cos(b) + v * math.sin(b), world[2] - u * math.sin(b) + v * math.cos(b))
                   for u, v in ((-sx / 2, -sz / 2), (sx / 2, -sz / 2), (sx / 2, sz / 2), (-sx / 2, sz / 2))]
        found.append((key, corners))
    return found


def _segment_distance(p, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    t = 0.0 if dx == dz == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / (dx * dx + dz * dz)))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dz)


def _inside(p, poly):
    sign = None
    for a, b in zip(poly, poly[1:] + poly[:1]):
        cross = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
        if sign is None:
            sign = cross > 0
        elif (cross > 0) != sign:
            return False
    return True


def distance_to_path(poly, a, b):
    """Distance in XZ between a convex footprint and the segment a-b."""
    if _inside(a, poly) or _inside(b, poly):
        return 0.0
    edges = list(zip(poly, poly[1:] + poly[:1]))
    best = min(_segment_distance(c, a, b) for c in poly)
    best = min(best, min(_segment_distance(p, e0, e1) for p in (a, b) for e0, e1 in edges))
    return best


def check_outward() -> None:
    batch = Batch()
    batch.box("x", (1, 2, 3), (.4, .2, .6), (10, 33, -20))
    for mesh in (batch.meshes["x"], prism(((-.2, 0), (.2, 0), (0, .5)), .1)):
        pts = mesh.points
        centre = tuple(sum(axis) / len(pts) for axis in zip(*pts))
        for i in range(0, len(mesh.indices), 3):
            tri = [pts[k] for k in mesh.indices[i:i + 3]]
            normal = mesh.normals[mesh.indices[i]]
            middle = tuple(sum(axis) / 3 for axis in zip(*tri))
            outward = sum(n * (m - c) for n, m, c in zip(normal, middle, centre))
            check(outward > 0, f"Merged face {i // 3} faces inward.")


def main() -> int:
    check_outward()
    for room, stance in STANCES.items():
        scene = ROOT / f"scenes/locations/{room}/{room}.tscn"
        for key, poly in footprints(scene):
            if key.startswith("Wall") or key.startswith("Door") or key == "Slab/Collision":
                continue
            gap = distance_to_path(poly, SPAWN, stance)
            check(gap >= CLEARANCE, f"{room}: '{key}' is {gap:.2f} m from the walk to the reading stance.")
    staff = (ROOT / "scenes/locations/staff_office/staff_office.tscn").read_text(encoding="utf-8")
    sizes = dict(re.findall(r'\[sub_resource type="BoxShape3D" id="([^"]+)"\]\nsize = (Vector3\([^)]*\))', staff))
    seen = {}
    for name, parent, kind, props, _ in nodes(ROOT / "scenes/locations/staff_office/staff_office.tscn"):
        if kind == "CollisionShape3D":
            key = name if parent == "." else f"{parent}/{name}"
            ref = re.search(r'SubResource\("([^"]+)"\)', props.get("shape", "")).group(1)
            seen[key] = sizes.get(ref)
            check(not key.startswith(("Postmodern", "WaitingRoom")), f"staff_office: '{key}' adds a collider.")
    for key, size in STAFF_SHAPES.items():
        check(seen.get(key) == size, f"staff_office: '{key}' changed from {size} to {seen.get(key)}.")
    for line in failures:
        print("FAIL:", line)
    print(("FAIL" if failures else "PASS") + ": office and archive dressing keep stances, routes and colliders.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
