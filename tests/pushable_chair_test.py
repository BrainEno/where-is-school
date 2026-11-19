#!/usr/bin/env python3
"""Boundary tests for the chair the protagonist stands up out of.

``tools/check_seat_clearance.py`` proves the *geometry* works: 0.70 m of travel puts every
part of the chair outside the body's capsule. This file proves the *chair itself* behaves,
by reading the script's contract and the scene that instances it - the two things that can
go wrong without the geometry notice.

The behaviour that matters and is easy to lose:

- the push is idempotent, because the position after the stand-up is a fact about the room
  rather than a frame of an animation, and something re-triggering it must not walk the
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


def test_the_push_is_idempotent() -> None:
    """Push twice, and the chair must not travel twice as far."""
    text = source()
    body = text[text.index("func push_back(") : text.index("func pull_home(")]
    check("if _pushed:" in body, "push_back must refuse to push an already-pushed chair")
    check(
        "return null" in body,
        "push_back must say it did nothing rather than starting a second slide",
    )


def test_the_chair_comes_home() -> None:
    """Re-sitting has to put the chair back under the body it came out from."""
    text = source()
    check("func pull_home(" in text, "the chair must be able to come back")
    body = text[text.index("func pull_home(") :]
    check("_home_position" in body, "pull_home must target the position the room gave the chair")


def test_both_ends_are_remembered_not_derived() -> None:
    """The two stops are recorded, so a moved or re-run slide cannot drift the chair."""
    text = source()
    check("_home_position = position" in text, "the chair must record where the room put it")
    check(
        "_pushed_position = position + Vector3(0.0, 0.0, PUSH_BACK_DISTANCE)" in text,
        "the pushed position must be the home position plus the push distance, along one axis",
    )


def test_slides_do_not_stack() -> None:
    """A second slide has to kill the first, or the two fight over the position."""
    text = source()
    body = text[text.index("func _slide_to(") :]
    check("_kill_slide()" in body, "starting a slide must stop the one already running")


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
    push = text[text.index("func push_back(") : text.index("func pull_home(")]
    check("_set_solid(true)" in push, "pushing the chair back must make it solid")
    check(
        push.index("_slide_to(") < push.index("_set_solid(true)"),
        "the collision must come on when the chair *arrives*: turning it on while the body is "
        "still folded over the seat puts a solid box inside the protagonist",
    )
    pull = text[text.index("func pull_home(") :]
    check(
        pull.index("_set_solid(false)") < pull.index("_slide_to("),
        "pulling the chair home must open it *before* it moves, not after",
    )


def test_the_collision_is_on_a_layer_that_does_not_carve_the_room() -> None:
    """Layer 1 is the navmesh bake and the interaction rays; the chair needs neither.

    The numbers are read from the scripts rather than repeated, because this only works while
    all three agree: the bake must not see the layer, the body must, and the interaction rays
    must not.
    """
    chair = source()
    check("const SOLID_LAYER := 4" in chair, "the chair must collide on layer 3 (value 4)")
    scene = (ROOT / "scenes/environment/props/classroom_desk.tscn").read_text(encoding="utf-8")
    check(
        re.search(r'name="Solid".*?collision_layer = 4', scene, re.S) is not None,
        "the chair's Solid body must be authored on layer 3",
    )
    nav = (ROOT / "scripts/world/location_navigation.gd").read_text(encoding="utf-8")
    bake = int(re.search(r"geometry_collision_mask: int = (\d+)", nav).group(1))
    check(bake & 4 == 0, f"the navigation bake's mask ({bake}) must not include layer 3")
    player = (ROOT / "scenes/actors/player/player.tscn").read_text(encoding="utf-8")
    body_mask = int(re.search(r"^collision_mask = (\d+)", player, re.M).group(1))
    check(body_mask & 4 != 0, f"the player's mask ({body_mask}) must include layer 3")
    controller = (ROOT / "scripts/interaction/interaction_controller.gd").read_text(encoding="utf-8")
    occluder = int(re.search(r"occluder_mask: int = (\d+)", controller).group(1))
    check(occluder & 4 == 0, f"the interaction rays ({occluder}) must not include layer 3")


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


def test_the_hand_does_the_pushing() -> None:
    """The arm reaches the chair before it moves, and lets go after.

    A chair that slides with no hand on it is the thing this was built to avoid looking like.
    """
    controller = (ROOT / "scripts/actors/player/player_controller.gd").read_text(encoding="utf-8")
    push = controller[controller.index("func _push_seat_back(") :]
    push = push[: push.index("func _pull_seat_home(")]
    check("_reach_for_chair()" in push, "the stand-up must reach for the chair")
    check("_release_chair" in push, "and let go of it once it stops")
    check(
        push.index("_reach_for_chair()") < push.index("push_back"),
        "the hand has to be on the chair *before* it starts moving",
    )


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
    test_the_push_is_idempotent()
    test_the_chair_comes_home()
    test_both_ends_are_remembered_not_derived()
    test_slides_do_not_stack()
    test_it_is_snappable()
    test_the_room_can_find_it()
    test_the_chair_is_solid_only_when_it_is_empty()
    test_the_collision_is_on_a_layer_that_does_not_carve_the_room()
    test_the_room_has_a_sit_interaction()
    test_the_hand_does_the_pushing()
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
