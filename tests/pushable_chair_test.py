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


def test_the_distance_is_the_one_that_was_measured() -> None:
    """0.62 m is the geometric minimum; the constant has to keep its slack."""
    text = source()
    m = re.search(r"const PUSH_BACK_DISTANCE := ([0-9.]+)", text)
    check(m is not None, "PUSH_BACK_DISTANCE must exist")
    if m is None:
        return
    distance = float(m.group(1))
    check(
        distance >= 0.65,
        f"a {distance:g} m push is at or below the 0.63 m minimum, leaving no slack",
    )


def main() -> int:
    test_the_push_is_idempotent()
    test_the_chair_comes_home()
    test_both_ends_are_remembered_not_derived()
    test_slides_do_not_stack()
    test_it_is_snappable()
    test_the_room_can_find_it()
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
