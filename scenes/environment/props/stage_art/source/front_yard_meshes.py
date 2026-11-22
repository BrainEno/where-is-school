"""Shaped meshes for the front yard and the school gate, written as text ArrayMeshes.

    python3 scenes/environment/props/stage_art/source/build_stage_art.py   # writes these too

Built with the construction site's mesh kit (`playground_art/source/site_mesh.py`), so they
rebuild without the engine and land as small `.tres` files under `stage_art/meshes/`:

* `dead_tree_<v>_trunk/_bark/_twig.tres` - three dead trees, no leaf on them: a trunk
  with a lean and a crook, limbs that fork four or five times into thin twigs, a few limbs
  broken off short. Split in three: the trunk alone is what an inspection outlines (and
  what the pointer finds it by), the limbs carry the ink outline, the twigs do not. Every tree stays inside `TREE_BOUNDS` around its
  foot, which is the fader box `tools/build_outdoor_locations.py` puts round it.
* `retractable_gate_<n>.tres` - the closed lattice of the parking-lot sliding gate
  (伸缩门): uprights on wheels, scissor bars crossing between them in two tiers, short
  rails top and bottom. `n` is the opening it closes, in centimetres. The head unit and the
  track are ordinary boxes, placed by `build_stage_art.py`.
* `side_door_frame.tres` / `side_door_bars.tres` - the side door (小门): a box-section
  frame round a 1.1 x 2.2 m opening, and the leaf of upright bars with a kick plate and
  a lock box. Two meshes, because an exit's outline is both.
* `yard_railing_<n>.tres` - the low railing (栏杆) between the front yard and the sports
  ground beyond it, `n` centimetres long: posts, two rails, pickets.
"""

from __future__ import annotations

import math
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "playground_art" / "source"))

from site_mesh import Mesh, add, cylinder, mul, norm, tube  # noqa: E402

MESH_DIR = HERE.parent / "meshes"
RES = "res://scenes/environment/props/stage_art/meshes"

# Half-width and height a tree may fill around its foot (metres). The fader volume in
# tools/build_outdoor_locations.py (FRONT_YARD_TREE_BOX) is the same box.
TREE_BOUNDS = (2.6, 7.0)
TWIG_RADIUS = 0.032

GATE_HEIGHT = 1.62
GATE_PITCH = 0.42


def _rotate_towards(direction, axis, angle):
    """`direction` turned by `angle` radians about `axis` (Rodrigues)."""
    k = norm(axis)
    c, s = math.cos(angle), math.sin(angle)
    d = direction
    kxd = (k[1] * d[2] - k[2] * d[1], k[2] * d[0] - k[0] * d[2], k[0] * d[1] - k[1] * d[0])
    kd = k[0] * d[0] + k[1] * d[1] + k[2] * d[2]
    return norm(tuple(d[i] * c + kxd[i] * s + k[i] * kd * (1 - c) for i in range(3)))


def _perpendicular(d, rng):
    a = (0.0, 1.0, 0.0) if abs(d[1]) < 0.9 else (1.0, 0.0, 0.0)
    p = norm((d[1] * a[2] - d[2] * a[1], d[2] * a[0] - d[0] * a[2], d[0] * a[1] - d[1] * a[0]))
    return _rotate_towards(p, d, rng.uniform(0, math.tau))


def _clamp_reach(start, direction, length):
    """Shorten a limb so its end stays inside the tree's box."""
    r, top = TREE_BOUNDS
    for _ in range(12):
        end = add(start, mul(direction, length))
        if math.hypot(end[0], end[2]) <= r - 0.15 and 0.3 <= end[1] <= top - 0.1:
            return length
        length *= 0.8
    return length


def dead_tree(seed: int, height: float = 4.2, lean: float = 6.0):
    """A dead deciduous tree, foot at the origin. Returns (trunk, limbs, twigs) meshes."""
    rng = random.Random(seed)
    trunk, bark, twigs = Mesh(), Mesh(), Mesh()

    def limb(start, direction, length, radius, depth):
        length = _clamp_reach(start, direction, length)
        steps = max(3, int(length / 0.28) + 2)
        path, radii = [start], [radius]
        d = direction
        p = start
        bend_axis = _perpendicular(d, rng)
        for i in range(1, steps + 1):
            # wander a little, and droop as the wood thins
            d = _rotate_towards(d, bend_axis, rng.gauss(0, 0.16))
            d = norm(add(d, (0, -0.05 * depth / 4.0, 0)))
            if rng.random() < 0.3:
                bend_axis = _perpendicular(d, rng)
            p = add(p, mul(d, length / steps))
            path.append(p)
            radii.append(max(TWIG_RADIUS * 0.25, radius * (1 - 0.72 * i / steps)))
        thin = radius < TWIG_RADIUS
        target = twigs if thin else (trunk if depth == 0 else bark)
        target.merge(tube(path, radii, sides=4 if thin else (7 if depth < 2 else 5), caps=True))
        if depth >= 5 or radius < 0.006:
            return
        # side limbs along the upper part, then one or two leaders from the end
        count = rng.randint(3, 4) if depth < 2 else rng.randint(2, 4)
        for c in range(count):
            t = rng.uniform(0.3 if depth else 0.55, 0.92) if c < count - 1 else 1.0
            idx = min(len(path) - 1, max(1, int(round(t * (len(path) - 1)))))
            base_d = norm(tuple(path[idx][k] - path[idx - 1][k] for k in range(3)))
            spread = rng.uniform(0.38, 0.75) if depth > 0 else rng.uniform(0.3, 0.55)
            child_d = _rotate_towards(base_d, _perpendicular(base_d, rng), spread)
            # keep the crown rising: dead trees here are poplars and ashes, not oaks
            child_d = norm(add(child_d, (0, 0.25 if depth < 2 else 0.05, 0)))
            scale = rng.uniform(0.55, 0.78)
            child_r = radii[idx] * rng.uniform(0.55, 0.72)
            if depth >= 1 and rng.random() < 0.12 and child_r > 0.03:
                # a limb broken off short: thick, stopped, a pale cap where it snapped
                stub = [path[idx], add(path[idx], mul(child_d, rng.uniform(0.18, 0.4)))]
                bark.merge(tube(stub, [child_r, child_r * 0.85], sides=6))
                continue
            limb(path[idx], child_d, length * scale, child_r, depth + 1)

    up = norm((math.sin(math.radians(lean)), 1.0, math.sin(math.radians(lean * 0.4))))
    # The trunk: a flared foot, then up with a crook, and the crown from about two metres.
    trunk_r = rng.uniform(0.15, 0.19)
    foot = tube([(0, -0.05, 0), (0, 0.18, 0), (0, 0.42, 0)], [trunk_r * 1.55, trunk_r * 1.12, trunk_r], sides=8)
    trunk.merge(foot)
    limb((0, 0.4, 0), up, height * 0.55, trunk_r, 0)
    return trunk, bark, twigs


TREES = {
    "a": {"seed": 1601, "height": 5.2, "lean": 5.0},
    "b": {"seed": 1607, "height": 4.4, "lean": -9.0},
    "c": {"seed": 1613, "height": 5.6, "lean": 3.0},
}


def retractable_gate(length: float) -> Mesh:
    """The lattice of a closed sliding gate, from x 0 (the fixed end) to x `length`.

    Foot of the uprights at y 0, the gate's plane at z 0."""
    m = Mesh()
    n = max(2, int(round(length / GATE_PITCH)))
    pitch = length / n
    h = GATE_HEIGHT
    bar = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for i in range(n + 1):
        x = i * pitch
        # the upright, a box tube on its wheel; every fourth one stouter (a pivot post)
        w = 0.024 if i % 4 else 0.032
        m.merge(tube([(x, 0.11, 0), (x, h, 0)], (w, w), section=bar))
        m.merge(cylinder(0.052, 0.04, 8, center=(x, 0.055, 0), axis="z"))
        # a small cap, and the decorative spike the cheaper models carry
        m.merge(tube([(x, h, 0), (x, h + 0.06, 0)], (w * 1.3, w * 1.3), section=bar))
    for i in range(n):
        x0, x1 = i * pitch, (i + 1) * pitch
        # the scissors: two tiers of crossing flat bars, one pair either face of the uprights
        for (y0, y1) in ((0.24, 0.92), (0.92, 1.56)):
            for a, b in (((x0, y0), (x1, y1)), ((x0, y1), (x1, y0))):
                face = 0.03 if a[1] < b[1] else -0.03
                m.merge(tube([(a[0], a[1], face), (b[0], b[1], face)], (0.018, 0.005), section=bar, caps=False))
        # short top and bottom rails, the ones that fold up with the lattice
        for y in (h - 0.03, 0.2):
            m.merge(tube([(x0, y, 0), (x1, y, 0)], (0.014, 0.014), section=bar, caps=False))
    return m


DOOR_W, DOOR_H = 1.1, 2.2


def side_door_frame() -> Mesh:
    """The frame round the side door's opening, in the door's plane (x along the wall,
    y up, foot at y 0, centred on x 0); 6 cm box section."""
    m = Mesh()
    sq = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    w, h, t = DOOR_W / 2, DOOR_H, 0.03
    m.merge(tube([(-w, 0, 0), (-w, h, 0)], (t, t * 1.6), section=sq))
    m.merge(tube([(w, 0, 0), (w, h, 0)], (t, t * 1.6), section=sq))
    m.merge(tube([(-w - t, h, 0), (w + t, h, 0)], (t, t * 1.6), section=sq))
    return m


def side_door_bars() -> Mesh:
    """The leaf: a light frame, upright bars at 11 cm, a mid rail, a kick plate, the lock."""
    m = Mesh()
    sq = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    w, h = DOOR_W / 2 - 0.05, DOOR_H - 0.06
    for x in (-w, w):
        m.merge(tube([(x, 0.03, 0), (x, h, 0)], (0.02, 0.02), section=sq))
    for y in (0.03, 0.42, 1.05, h):
        m.merge(tube([(-w, y, 0), (w, y, 0)], (0.02, 0.02), section=sq, caps=False))
    n = int((2 * w) / 0.11)
    for i in range(1, n):
        x = -w + i * (2 * w / n)
        m.merge(tube([(x, 0.42, 0), (x, h, 0)], (0.008, 0.008), sides=6, caps=False))
    # the kick plate, solid steel to the mid rail
    m.merge(tube([(-w, 0.225, 0), (w, 0.225, 0)], (0.195, 0.006), section=sq))
    # the lock box and the handle, on the side away from the hinges
    m.merge(tube([(w - 0.09, 1.0, 0), (w - 0.09, 1.16, 0)], (0.05, 0.035), section=sq))
    m.merge(tube([(w - 0.17, 1.05, 0.06), (w - 0.06, 1.05, 0.06)], (0.012, 0.012), sides=6))
    m.merge(tube([(w - 0.17, 1.05, -0.06), (w - 0.06, 1.05, -0.06)], (0.012, 0.012), sides=6))
    return m


def yard_railing(length: float) -> Mesh:
    """A low railing along x from 0 to `length`, foot at y 0: posts every ~2 m, top and
    bottom rails, pickets at 15 cm with a little pointed head."""
    m = Mesh()
    sq = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    h = 1.2
    posts = max(2, int(round(length / 2.0)))
    for i in range(posts + 1):
        x = i * length / posts
        m.merge(tube([(x, 0, 0), (x, h + 0.06, 0)], (0.035, 0.035), section=sq))
    for y in (0.12, h - 0.05):
        m.merge(tube([(0, y, 0), (length, y, 0)], (0.02, 0.015), section=sq, caps=False))
    n = int(length / 0.15)
    for i in range(1, n):
        x = i * length / n
        m.merge(tube([(x, 0.12, 0), (x, h + 0.02, 0)], (0.009, 0.009), sides=4, caps=False))
        m.merge(tube([(x, h + 0.02, 0), (x, h + 0.1, 0)], (0.016, 0.001), sides=4))
    return m


def surface_tres(mesh: Mesh) -> str:
    return f'[gd_resource type="ArrayMesh" format=3]\n\n[resource]\n_surfaces = {mesh.surface()}\n'


def write_all(gate_lengths, railing_lengths=()) -> dict[str, str]:
    """Writes every mesh; returns name -> res:// path."""
    MESH_DIR.mkdir(parents=True, exist_ok=True)
    out = {}

    def save(name, mesh):
        path = MESH_DIR / f"{name}.tres"
        path.write_text(surface_tres(mesh))
        out[name] = f"{RES}/{name}.tres"

    for key, spec in TREES.items():
        trunk, bark, twigs = dead_tree(**spec)
        save(f"dead_tree_{key}_trunk", trunk)
        save(f"dead_tree_{key}_bark", bark)
        save(f"dead_tree_{key}_twig", twigs)
    for length in gate_lengths:
        save(f"retractable_gate_{int(round(length * 100))}", retractable_gate(length))
    save("side_door_frame", side_door_frame())
    save("side_door_bars", side_door_bars())
    for length in railing_lengths:
        save(f"yard_railing_{int(round(length * 100))}", yard_railing(length))
    return out


if __name__ == "__main__":
    for name, path in write_all([5.6], [26.3]).items():
        size = (MESH_DIR / f"{name}.tres").stat().st_size
        print(f"{name:28s} {size / 1024:7.1f} KiB")
