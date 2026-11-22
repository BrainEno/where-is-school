#!/usr/bin/env python3
"""Boundary tests for the chair the protagonist stands up out of.

``tools/check_seat_clearance.py`` proves the *geometry* works: 0.65 m of travel puts every
part of the chair outside the body's capsule. This file proves the *chair itself* behaves,
by reading the script's contract and the scene that instances it - the two things that can
go wrong without the geometry notice.

The behaviour that matters and is easy to lose:

- the push is idempotent, because the position after the stand-up is a fact about the room
  rather than a sum of per-frame offsets, and something re-triggering it must not walk the
  chair across the floor;
- it always comes back to the same place, so re-sitting lands the chair where it started;
- it is reachable from the room by the node group the controller searches for, since the
  controller is on the player, in another scene.

Run with ``python3 tests/pushable_chair_test.py`` (CI does). No network, no Godot.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

## The scripts this change added or rewrote, relative to the repository root.
SCRIPTS = (
    "scripts/environment/pushable_chair.gd",
    "scripts/actors/character_limb_contact.gd",
    "scripts/actors/player/classroom_seat_motion.gd",
    "scripts/interaction/seated_chair_interactable.gd",
    "scenes/locations/classroom/classroom_chair_control.gd",
)

ROOT = Path(__file__).resolve().parent.parent
CHAIR_SCRIPT = ROOT / "scripts/environment/pushable_chair.gd"
DESK_SCENE = ROOT / "scenes/environment/props/classroom_desk.tscn"
CONTROLLER = ROOT / "scripts/actors/player/player_controller.gd"

FAILURES: list[str] = []
CHECKS = 0


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


def source() -> str:
    return CHAIR_SCRIPT.read_text(encoding="utf-8")


def test_the_slide_has_one_absolute_clock() -> None:
    """Samples may repeat and seek. Neither stop can accumulate frame-to-frame drift."""
    text = source()
    sample = text[text.index("func sample_slide(") : text.index("func snap_back(")]
    check("position = _home_position.lerp(_pushed_position," in sample,
          "a repeated sample must calculate the same position from the two stops")
    check("clampf(fraction, 0.0, 1.0)" in sample, "samples must stay between the stops")
    check("_home_position = position" in text, "retain the room's home placement")
    check("_pushed_position = position + basis.z * PUSH_BACK_DISTANCE" in text,
          "push the authored distance along the chair's back axis")
    check("Tween" not in text, "the prop must not start a second clock beside the body")
    home = text[text.index("func snap_home(") : text.index("func _set_solid(")]
    check("sample_slide(0.0)" in home and "_pushed = false" in home,
          "return to the exact home position and remember it")


def test_it_is_snappable() -> None:
    """A save that opens with the protagonist already standing must not replay the push."""
    text = source()
    check("func snap_back(" in text, "a resumed scene needs to arrive with the chair already out")
    check("_pushed = true" in text[text.index("func snap_back(") :],
          "snap_back must record that the chair is out, not just move it")


def test_the_room_can_find_it() -> None:
    """The controller finds the chair by group; the scene has to put it in that group."""
    scene = DESK_SCENE.read_text(encoding="utf-8")
    controller = CONTROLLER.read_text(encoding="utf-8")
    group = re.search(r'const SEATED_CHAIR_GROUP := &"([a-z_]+)"', controller)
    check(group is not None, "the controller must name the group it searches")
    if group is None:
        return
    check(
        f'groups=["{group.group(1)}"]' in scene,
        f"the chair must be in the '{group.group(1)}' group, or the controller finds nothing",
    )
    check(
        "pushable_chair.gd" in scene,
        "the chair node must carry the pushable_chair script",
    )


def test_the_chair_is_solid_only_when_it_is_empty() -> None:
    """A solid chair the protagonist is sitting *in* would trap him.

    The body overlaps the seat for the whole of the opening, so the collision has to be off
    while it is being sat in and on once it is out of the way. Getting this backwards is not a
    cosmetic bug: it is a player who cannot move, or one who is shoved out of the room.
    """
    text = source()
    check("func _set_solid(" in text, "the chair must be able to turn its collision on and off")
    check(
        "_set_solid(false)" in text[text.index("func _ready()") : text.index("func is_pushed_back")],
        "the chair must start open - the opening has the protagonist asleep in it",
    )
    begin = text[text.index("func start_slide(") : text.index("func sample_slide(")]
    check("_set_solid(false)" in begin, "unblock the capsule before either slide starts")
    end = text[text.index("func snap_back(") : text.index("func snap_home(")]
    check("sample_slide(1.0)" in end and "_set_solid(true)" in end,
          "only the pushed stop re-enables collision")
    check(end.index("sample_slide(1.0)") < end.index("_set_solid(true)"),
          "finish the slide before enabling collision")


def test_the_collision_is_on_a_layer_that_does_not_carve_the_room() -> None:
    """Layer 1 is the navmesh bake and the interaction rays; the chair needs neither.

    The numbers are read from the scripts rather than repeated, because this only works while
    all three agree: the bake must not see the layer, the body must, and the interaction rays
    must not.
    """
    chair = source()
    check("const SOLID_LAYER := 4" in chair, "the chair must collide on layer 3 (value 4)")
    # The room authors the sliding pair's bodies. The shared prop must not make
    # the other chairs collide and change the walk routes.
    prop = (ROOT / "scenes/environment/props/classroom_desk.tscn").read_text(encoding="utf-8")
    check(
        "CollisionObject3D" not in prop and 'type="StaticBody3D"' not in prop,
        "the shared desk prop must carry no chair collision",
    )
    room = (ROOT / "scenes/locations/classroom/classroom.tscn").read_text(encoding="utf-8")
    bodies = re.findall(
        r'^\[node name="Solid" type="StaticBody3D" parent="Furniture/(Desk[^/"]+)/Chair"[^\n]*\]'
        r'\ncollision_layer = (\d+)\ncollision_mask = (\d+)',
        room,
        re.M,
    )
    check(sorted(bodies) == [("DeskB2", "4", "0"), ("DeskQ", "4", "0")],
          "only the two desk mates' chairs should have a layer-3 Solid body")
    for desk, _, _ in bodies:
        check(room.count(f'parent="Furniture/{desk}/Chair/Solid"') == 1,
              f"{desk} needs exactly one chair collider")
    nav = (ROOT / "scripts/world/location_navigation.gd").read_text(encoding="utf-8")
    bake = int(re.search(r"geometry_collision_mask: int = (\d+)", nav).group(1))
    check(bake & 4 == 0, f"the navigation bake's mask ({bake}) must not include layer 3")
    player = (ROOT / "scenes/actors/player/player.tscn").read_text(encoding="utf-8")
    body_mask = int(re.search(r"^collision_mask = (\d+)", player, re.M).group(1))
    check(body_mask & 4 != 0, f"the player's mask ({body_mask}) must include layer 3")
    controller = (ROOT / "scripts/interaction/interaction_controller.gd").read_text(encoding="utf-8")
    occluder = int(re.search(r"occluder_mask: int = (\d+)", controller).group(1))
    check(occluder & 4 == 0, f"the interaction rays ({occluder}) must not include layer 3")


def test_the_new_scripts_do_not_shadow_built_in_properties() -> None:
    """`var name := ...` is a parse error, and no static gate in this repository says so.

    `gdparse` checks grammar, not the class hierarchy, so a local called `name` parses fine
    and then the engine refuses to load the script - which is exactly the shape of failure
    that made the capture jobs go red while every Python gate stayed green. `name` is the one
    built-in this codebase has actually tripped on; the check is scoped to it on purpose
    rather than to a guessed list of reserved words.
    """
    for relative in SCRIPTS:
        text = (ROOT / relative).read_text(encoding="utf-8")
        for number, line in enumerate(text.splitlines(), 1):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if re.match(r"(var|const)\s+name\s*[:=]", stripped):
                raise AssertionError(
                    f"{relative}:{number}: a local called `name` is `Node.name` and will not "
                    f"parse in the engine: {stripped}"
                )


def test_no_sub_resource_lost_its_properties() -> None:
    """Every `[sub_resource]` header must be followed by attributes, not another header.

    Inserting the chair's box into the classroom scene once put a new header between an
    existing shape and its `size`, which silently emptied the *floor* collider: the room stopped
    being 14 x 10 m and every walk route in it collapsed. The scene still loaded, so nothing
    but a check like this one says anything.
    """
    room = (ROOT / "scenes/locations/classroom/classroom.tscn").read_text(encoding="utf-8")
    lines = room.splitlines()
    for index, line in enumerate(lines):
        if not line.startswith("[sub_resource") or line.endswith("]"):
            continue
        # A header line ends in `]`; anything else means the parser is mid-declaration.
        raise AssertionError(f"unterminated sub_resource header at line {index + 1}: {line}")
    for index, line in enumerate(lines):
        if not line.startswith("[sub_resource"):
            continue
        following = lines[index + 1] if index + 1 < len(lines) else ""
        if following.startswith("[") or following == "":
            raise AssertionError(
                f"sub_resource at line {index + 1} has no attributes before the next header"
            )


def test_the_room_has_a_sit_interaction() -> None:
    """The chair offers sitting, and it reaches into the room without a hard player path."""
    room = (ROOT / "scenes/locations/classroom/classroom.tscn").read_text(encoding="utf-8")
    control = (ROOT / "scenes/locations/classroom/classroom_chair_control.gd").read_text(
        encoding="utf-8"
    )
    check('interact_id = &"chair_sit"' in room, "the classroom needs a chair_sit interactable")
    check("seated_chair_interactable.gd" in room, "it must use the offer-aware interactable")
    check(
        "ChairControl" in room,
        "the room needs a controller to wire the interactable to the protagonist",
    )
    check(
        "player_group" in control and "player_path" not in control,
        "the controller must find the body by group; the host, not the room, places the player",
    )
    check(
        "stage_handler" in control,
        "sitting has to run inside the director's beat, like every other staged moment",
    )


def test_the_hand_shares_the_motion_clock() -> None:
    """The two transfers share one sampler with their hand and foot constraints."""
    path = ROOT / "scripts/actors/player/classroom_seat_motion.gd"
    text = path.read_text(encoding="utf-8")
    for action in ("stand", "sit"):
        start = text.index(f"func sample_{action}(")
        body = text[start : text.index("\nfunc ", start + 1)]
        for operation in ("sample_action(", "sample_slide(", "_hold_chair(", "_plant("):
            check(operation in body, f"{action}: {operation} must be sampled on the transfer clock")
    check("hand.hold_at(chair.grip_point()" in text, "wrist follows the moving chair")


def test_the_distance_is_the_one_that_was_measured() -> None:
    """0.62 m is the geometric minimum; the constant has to keep its slack."""
    text = source()
    m = re.search(r"const PUSH_BACK_DISTANCE := ([0-9.]+)", text)
    check(m is not None, "PUSH_BACK_DISTANCE must exist")
    if m is None:
        return
    distance = float(m.group(1))
    check(
        distance >= 0.63,
        f"a {distance:g} m push does not clear the seat, which needs 0.63 m",
    )
    check(
        distance <= 0.80,
        f"a {distance:g} m push moves the chair further than the room is worth watching",
    )


def main() -> int:
    test_the_slide_has_one_absolute_clock()
    test_it_is_snappable()
    test_the_room_can_find_it()
    test_the_chair_is_solid_only_when_it_is_empty()
    test_the_collision_is_on_a_layer_that_does_not_carve_the_room()
    test_the_new_scripts_do_not_shadow_built_in_properties()
    test_no_sub_resource_lost_its_properties()
    test_the_room_has_a_sit_interaction()
    test_the_hand_shares_the_motion_clock()
    test_the_distance_is_the_one_that_was_measured()

    if FAILURES:
        for failure in FAILURES:
            print("PUSHABLE_CHAIR_TEST_FAILURE: " + failure)
        print("%d of %d check(s) failed." % (len(FAILURES), CHECKS))
        return 1
    print("PUSHABLE_CHAIR_TEST_OK: %d checks." % CHECKS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
