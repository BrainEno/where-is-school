#!/usr/bin/env python3
"""Check that the protagonist's seat does not intersect the chair it sits in.

The protagonist wakes seated in a classroom chair and stands up out of it. Both of those
are geometry, and both were wrong in the same way: the body was placed at the chair's
centre, so the capsule's axis sat 0.07 m from every part of the seat and the seat, both
posts, the rail and the back were all *inside* the body. Nothing caught it because nothing
compared the two files - the spawn marker lives in one scene and the chair in another, and
"is the chair under the person" was something only a screenshot could answer.

This check answers it from the files. It reads:

  - the spawn marker (`PlayerStart`) and the desk it belongs to, from the location scene;
  - the chair's part sizes and offsets, from the prop scene;
  - the body's collision capsule, from the character scene.

and asserts the get-up geometry: a body seated at the spawn would intersect the chair, and
a body that has stepped `SEATED_CLEARANCE` forward from it would not. That second half is
the one that matters - it is the contract `PlayerController._apply_get_up_travel` keeps.

## What it does not do

It does not run the game and does not know about navmesh, physics layers or whether the
chair is even reachable. It compares boxes to a capsule, which is exactly the question that
went unanswered. It also only checks the one spawn the classroom's opening uses; a marker an
author adds later for a different chair is out of scope until it is named here.

    python3 tools/check_seat_clearance.py
    python3 tools/check_seat_clearance.py --verbose   #每段间隙

Standard library only.
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

LOCATION_SCENE = "scenes/locations/classroom/classroom.tscn"
DESK_SCENE = "scenes/environment/props/classroom_desk.tscn"
CHARACTER_SCENE = "scenes/actors/player/player.tscn"
CONTROLLER = "scripts/actors/player/player_controller.gd"

SPAWN = "PlayerStart"
DESK = "DeskB2"

# The one number the check needs the controller to agree on.
CLEARANCE_CONST = "SEATED_CLEARANCE"


# --- a very small .tscn reader --------------------------------------------


def _blocks(text: str) -> list[dict]:
    """Split a .tscn into `[node]` blocks of {header, props}."""
    out: list[dict] = []
    current: dict | None = None
    for line in text.splitlines():
        if line.startswith("[node "):
            current = {"header": line, "props": {}}
            out.append(current)
        elif line.startswith("[") and not line.startswith("[node "):
            current = None
        elif current is not None and "=" in line and not line.startswith("["):
            key, _, value = line.partition("=")
            current["props"][key.strip()] = value.strip()
    return out


def _name(block: dict) -> str:
    m = re.search(r'name="([^"]+)"', block["header"])
    return m.group(1) if m else ""


def _parent(block: dict) -> str:
    m = re.search(r'parent="([^"]+)"', block["header"])
    return m.group(1) if m else ""


def _is_ext_instance(block: dict) -> bool:
    return "instance=" in block["header"]


def _vector(text: str | None) -> tuple[float, float, float]:
    if text is None:
        return (0.0, 0.0, 0.0)
    # Drop the constructor name first: `Vector3(-1.6, 0, 1.95)` would otherwise yield the
    # `3` from `Vector3` as its first component.
    body = text.split("(", 1)[1] if "(" in text else text
    nums = re.findall(r"-?[0-9]*\.?[0-9]+", body)
    vals = [float(n) for n in nums[:3]]
    while len(vals) < 3:
        vals.append(0.0)
    return (vals[0], vals[1], vals[2])


def _sub_resources(text: str) -> dict[str, dict[str, str]]:
    """`[sub_resource ...]` blocks keyed by their id, with their properties."""
    out: dict[str, dict[str, str]] = {}
    current_id: str | None = None
    for line in text.splitlines():
        m = re.match(r'\[sub_resource [^]]*id="([^"]+)"', line)
        if m:
            current_id = m.group(1)
            out[current_id] = {}
            continue
        if line.startswith("["):
            current_id = None
            continue
        if current_id and "=" in line:
            key, _, value = line.partition("=")
            out[current_id][key.strip()] = value.strip()
    return out


# --- the three pieces ------------------------------------------------------


def spawn_position(root: Path) -> tuple[float, float, float]:
    text = (root / LOCATION_SCENE).read_text(encoding="utf-8")
    for block in _blocks(text):
        if _name(block) == SPAWN:
            return _vector(block["props"].get("position"))
    raise SystemExit(f"check_seat_clearance: no {SPAWN} in {LOCATION_SCENE}")


def desk_position(root: Path) -> tuple[float, float, float]:
    text = (root / LOCATION_SCENE).read_text(encoding="utf-8")
    for block in _blocks(text):
        if _name(block) == DESK and _is_ext_instance(block):
            return _vector(block["props"].get("position"))
    raise SystemExit(f"check_seat_clearance: no {DESK} instance in {LOCATION_SCENE}")


def chair_boxes(root: Path) -> list[tuple[str, tuple[float, float, float], tuple[float, float, float]]]:
    """Every mesh under the chair: (name, world offset from the desk, size)."""
    text = (root / DESK_SCENE).read_text(encoding="utf-8")
    subs = _sub_resources(text)
    chair_offset = (0.0, 0.0, 0.0)
    for block in _blocks(text):
        if _name(block) == "Chair":
            chair_offset = _vector(block["props"].get("position"))
            break
    boxes: list[tuple[str, tuple[float, float, float], tuple[float, float, float]]] = []
    for block in _blocks(text):
        parent = _parent(block)
        if parent != "Chair" and not parent.startswith("Chair/"):
            continue
        mesh_id = block["props"].get("mesh", "")
        m = re.search(r'SubResource\("([^"]+)"\)', mesh_id)
        if not m:
            continue
        size = _vector(subs.get(m.group(1), {}).get("size"))
        pos = _vector(block["props"].get("position"))
        offset = (
            chair_offset[0] + pos[0],
            chair_offset[1] + pos[1],
            chair_offset[2] + pos[2],
        )
        boxes.append((_name(block), offset, size))
    return boxes


def body_capsule(root: Path) -> tuple[float, float, float]:
    """(radius, height, centre y) of the protagonist's collision capsule."""
    text = (root / CHARACTER_SCENE).read_text(encoding="utf-8")
    subs = _sub_resources(text)
    for block in _blocks(text):
        if _name(block) != "CollisionShape3D" or _parent(block) != ".":
            continue
        m = re.search(r'SubResource\("([^"]+)"\)', block["props"].get("shape", ""))
        if not m:
            continue
        data = subs.get(m.group(1), {})
        radius = float(data.get("radius", 0.0))
        height = float(data.get("height", 0.0))
        centre = _vector(block["props"].get("position"))
        return (radius, height, centre[1])
    raise SystemExit(f"check_seat_clearance: no root capsule in {CHARACTER_SCENE}")


def facing_default(root: Path) -> tuple[float, float, float]:
    """The controller's opening facing: the direction a seated body looks.

    Only the default matters. A body that has walked somewhere else stands up from
    wherever it is, and this check is about the one seat the opening places it in.
    """
    text = (root / CONTROLLER).read_text(encoding="utf-8")
    m = re.search(
        r"var _facing_direction: Vector3 = Vector3\(([^)]*)\)", text
    )
    if not m:
        raise SystemExit(
            f"check_seat_clearance: {CONTROLLER} no longer seeds _facing_direction"
        )
    return _vector("Vector3(" + m.group(1) + ")")


def clearance_from_controller(root: Path) -> float:
    text = (root / CONTROLLER).read_text(encoding="utf-8")
    m = re.search(rf"^const {CLEARANCE_CONST} := ([0-9.]+)", text, re.MULTILINE)
    if not m:
        raise SystemExit(
            f"check_seat_clearance: {CONTROLLER} no longer defines {CLEARANCE_CONST}"
        )
    return float(m.group(1))


# --- the geometry ----------------------------------------------------------


def capsule_intersects_box(
    axis_xy: tuple[float, float],
    capsule: tuple[float, float, float],
    box_centre: tuple[float, float, float],
    box_size: tuple[float, float, float],
) -> bool:
    """Does a vertical capsule at `axis_xy` overlap an axis-aligned box?

    The capsule is treated as its bounding cylinder: same radius, same height. That
    over-estimates the very top and bottom caps, which is the safe direction for a check
    whose job is to notice a body standing inside furniture.
    """
    radius, height, centre_y = capsule
    half = height * 0.5
    cyl_low, cyl_high = centre_y - half, centre_y + half

    box_low_y = box_centre[1] - box_size[1] * 0.5
    box_high_y = box_centre[1] + box_size[1] * 0.5
    if cyl_high <= box_low_y or cyl_low >= box_high_y:
        return False

    # Horizontal: closest point on the box's footprint to the capsule axis.
    dx = max(abs(axis_xy[0] - box_centre[0]) - box_size[0] * 0.5, 0.0)
    dz = max(abs(axis_xy[1] - box_centre[2]) - box_size[2] * 0.5, 0.0)
    return math.hypot(dx, dz) < radius


def horizontal_gap(
    axis_xy: tuple[float, float],
    capsule: tuple[float, float, float],
    box_centre: tuple[float, float, float],
    box_size: tuple[float, float, float],
) -> float:
    """How much clear air between the capsule's surface and the box (>0 = clear)."""
    radius = capsule[0]
    dx = max(abs(axis_xy[0] - box_centre[0]) - box_size[0] * 0.5, 0.0)
    dz = max(abs(axis_xy[1] - box_centre[2]) - box_size[2] * 0.5, 0.0)
    return math.hypot(dx, dz) - radius


def findings(root: Path) -> tuple[list[str], list[tuple[str, float]]]:
    """Contradictions, and the per-part gaps at the end of the stand-up."""
    spawn = spawn_position(root)
    desk = desk_position(root)
    capsule = body_capsule(root)
    clearance = clearance_from_controller(root)
    boxes = chair_boxes(root)

    problems: list[str] = []

    # The chair's parts are authored relative to the desk, so the whole prop is placed once.
    placed = [
        (name, (desk[0] + off[0], desk[1] + off[1], desk[2] + off[2]), size)
        for name, off, size in boxes
    ]
    if not placed:
        problems.append(
            f"{DESK_SCENE}: no meshes were found under the chair, so this check is blind"
        )
        return problems, []

    # 1. Standing up must actually change something. A clearance of 0 would make the whole
    #    get-up a pose change on the spot, which is what put the body inside the chair.
    if clearance <= 0.0:
        problems.append(
            f"{CONTROLLER}: {CLEARANCE_CONST} is {clearance:g}, so the body never steps "
            "clear of the seat it woke in"
        )

    # 2. The classroom spawn has to be a seat, i.e. the body really did wake in the chair.
    #    Without this, moving the spawn (or the desk) silently retires the whole check.
    seated_hits = [
        name
        for name, centre, size in placed
        if capsule_intersects_box((spawn[0], spawn[2]), capsule, centre, size)
    ]
    if not seated_hits:
        problems.append(
            f"{LOCATION_SCENE}: {SPAWN} at {spawn[0]:.2f},{spawn[2]:.2f} does not overlap "
            f"any part of {DESK}'s chair, so the opening no longer seats the protagonist "
            "at this desk - the clearance check has nothing to hold"
        )

    # 3. Step the way the controller actually steps: along the body's facing.
    #
    #    This used to try all four directions and keep the best, which hid the real bug -
    #    the controller walked the body *backwards* into the chair's back, and the scoring
    #    passed the check anyway because the opposite direction happened to be clear. The
    #    direction is read from the controller's own default facing, so the two cannot
    #    disagree about which way the stand-up goes.
    facing = facing_default(root)
    if abs(facing[2]) >= abs(facing[0]):
        step = (0.0, math.copysign(clearance, facing[2] if facing[2] else 1.0))
    else:
        step = (math.copysign(clearance, facing[0]), 0.0)
    stood = (spawn[0] + step[0], spawn[2] + step[1])

    best = [
        (name, horizontal_gap(stood, capsule, centre, size))
        for name, centre, size in placed
    ]
    worst = min(gap for _n, gap in best)
    if worst <= 0.0:
        culprit = min(best, key=lambda pair: pair[1])[0]
        problems.append(
            f"{CONTROLLER}: after the {clearance:.2f} m stand-up along the body's facing "
            f"the capsule still intersects the chair's {culprit} by {-worst:.3f} m - the "
            "body stands up inside the seat"
        )

    # 3b. The body *starts* inside the chair - that is what sitting is - so "never overlap"
    #     is the wrong rule. The rule that works is per part: while the body rises, no part
    #     of the chair may be entered *more deeply* than it already was.
    #
    #     This is what separates standing up from walking through the furniture. Going
    #     forward (the way the body looks) every part's gap improves from the first sample:
    #     the back starts 0.245 m inside and shrinks away. Going backwards, into the back,
    #     the back's gap gets *worse* first - 0.245 m, then 0.350 m at its deepest - because
    #     the body is climbing into the thickest part of it. A whole-body "worst gap"
    #     reading misses that, because the seat is always the worst part and it improves
    #     either way; the dip only shows per part.
    samples = 24
    previous: dict[str, float] | None = None
    for step_index in range(samples + 1):
        fraction = step_index / samples
        along = (spawn[0] + step[0] * fraction, spawn[2] + step[1] * fraction)
        current = {
            name: horizontal_gap(along, capsule, centre, size)
            for name, centre, size in placed
        }
        if previous is not None:
            for name, gap in current.items():
                if gap < previous[name] - 0.002:
                    problems.append(
                        f"{CONTROLLER}: at {fraction * 100:.0f}% through the stand-up the "
                        f"capsule is {abs(gap):.3f} m inside the chair's {name} and getting "
                        "deeper - the body moves into the furniture before it leaves it"
                    )
                    break
        previous = current

    # 4. Standing up through the *back* is the failure the eye notices first, because the
    #    back is at chest height - and it is the one the wrong facing caused. It is reported
    #    on its own so a reader sees that, not just "some part overlaps".
    for name, gap in best:
        if name == "Back" and gap <= 0.0:
            problems.append(
                f"{LOCATION_SCENE}: the stand-up ends inside the chair's back ({gap:+.3f} m)"
                " - the body steps against its facing, into the back"
            )

    return problems, best


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--root", type=Path, default=root)
    parser.add_argument("--verbose", action="store_true", help="print every part's clearance")
    args = parser.parse_args(argv)

    problems, gaps = findings(args.root)
    if args.verbose:
        for name, gap in gaps:
            print(f"  after the stand-up: {name:<9} {gap:+.3f} m")
    if problems:
        for problem in problems:
            print("SEAT_CLEARANCE_FAILURE: " + problem)
        return 1
    capsule = body_capsule(args.root)
    print(
        "SEAT_CLEARANCE_OK: the protagonist wakes inside the chair and the "
        f"{clearance_from_controller(args.root):.2f} m stand-up clears every part of it "
        f"({len(gaps)} parts checked against a {capsule[0]:.2f} m capsule)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
