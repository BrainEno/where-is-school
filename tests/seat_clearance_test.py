#!/usr/bin/env python3
"""Boundary tests for ``tools/check_seat_clearance.py``.

The check exists because the protagonist woke up *inside* a classroom chair - the spawn
marker sat at the chair's centre, so the seat, both posts, the rail and the back were all
within the body's capsule - and the stand-up then straightened the legs while the hip
barely moved. No test noticed, because no test compared the spawn to the furniture.

These tests pin the four things that make the check worth running, each on a fixture tree
this file writes:

- a body standing up *through* the chair's back is a failure, even though it ends in clear
  air: the endpoint is fine, the path is not;
- a body that does not step clear at all is a failure;
- a spawn that is no longer inside the chair is a failure, so moving the spawn cannot
  silently retire the check;
- this repository passes, both directions, which is the assertion that would have caught
  the original bug.

Run it with ``python3 tests/seat_clearance_test.py`` (CI does). No network needed.
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import check_seat_clearance as seat  # noqa: E402  (the path has to be set up first)

FAILURES: list[str] = []
CHECKS: int = 0

ROOT = Path(__file__).resolve().parent.parent


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


# --- fixtures --------------------------------------------------------------
#
# The same three files the real check reads, reduced to what it needs: a spawn marker, a
# desk instance, a chair with a seat and a thin back, and a capsule. The geometry is the
# classroom's, so a fixture failure means the same thing as a real one.

SPAWN_Z = 1.95
DESK_Z = 1.30


def location_scene(spawn_z: float = SPAWN_Z) -> str:
    return f"""\
[gd_scene format=3]

[node name="Classroom" type="Node3D"]

[node name="Furniture" type="Node3D" parent="."]

[node name="DeskB2" parent="Furniture" instance=ExtResource("1_desk")]
position = Vector3(-1.6, 0, {DESK_Z})

[node name="SpawnPoints" type="Node3D" parent="."]

[node name="PlayerStart" type="Marker3D" parent="SpawnPoints"]
position = Vector3(-1.6, 0, {spawn_z})
"""


DESK_SCENE = """\
[gd_scene format=3]

[sub_resource type="BoxMesh" id="seat"]
size = Vector3(0.46, 0.05, 0.42)

[sub_resource type="BoxMesh" id="back"]
size = Vector3(0.46, 0.34, 0.05)

[node name="ClassroomDesk" type="Node3D"]

[node name="Chair" type="Node3D" parent="."]
position = Vector3(0, 0, 0.58)

[node name="Seat" type="MeshInstance3D" parent="Chair"]
position = Vector3(0, 0.45, 0)
mesh = SubResource("seat")

[node name="Back" type="MeshInstance3D" parent="Chair"]
position = Vector3(0, 0.66, 0.2)
mesh = SubResource("back")
"""

CHARACTER_SCENE = """\
[gd_scene format=3]

[sub_resource type="CapsuleShape3D" id="body"]
radius = 0.35
height = 1.8

[node name="Player" type="CharacterBody3D"]

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
position = Vector3(0, 0.9, 0)
shape = SubResource("body")
"""


def controller(clearance: float, facing: tuple[float, float, float] = (0.0, 0.0, -1.0)) -> str:
    fx, fy, fz = facing
    return f"""\
extends CharacterBody3D

const SEATED_CLEARANCE := {clearance}

var _facing_direction: Vector3 = Vector3({fx}, {fy}, {fz})
"""


def tree(files: dict[str, str]) -> Path:
    root = Path(tempfile.mkdtemp(prefix="seat_clearance_"))
    for relative, text in files.items():
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
    return root


def fixture(
    clearance: float = 0.70,
    facing: tuple[float, float, float] = (0.0, 0.0, -1.0),
    spawn_z: float = SPAWN_Z,
) -> Path:
    return tree(
        {
            seat.LOCATION_SCENE: location_scene(spawn_z),
            seat.DESK_SCENE: DESK_SCENE,
            seat.CHARACTER_SCENE: CHARACTER_SCENE,
            seat.CONTROLLER: controller(clearance, facing),
        }
    )


def problems(root: Path) -> list[str]:
    found, _gaps = seat.findings(root)
    return found


def run_main(argv: list[str]) -> tuple[int, str]:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = seat.main(argv)
    return code, out.getvalue()


# --- the failure the eye sees ---------------------------------------------


def walking_through_the_back_fails() -> None:
    """Facing the chair's back steps *into* it, then out the far side into clear air.

    The endpoint is clear, so an endpoint-only check would pass. This is the regression the
    per-part path rule exists for.
    """
    root = fixture(facing=(0.0, 0.0, 1.0))
    found = problems(root)
    check(bool(found), "stepping into the chair's back must be a failure")
    check(
        any("Back" in entry and "deeper" in entry for entry in found),
        f"the failure must name the back and say it is getting deeper, got {found}",
    )


def not_stepping_clear_at_all_fails() -> None:
    root = fixture(clearance=0.0)
    found = problems(root)
    check(bool(found), "a zero stand-up must be a failure")
    check(
        any("never steps clear" in entry for entry in found),
        f"the failure must say the body never steps clear, got {found}",
    )


def stopping_one_centimetre_short_fails() -> None:
    """0.62 m leaves the capsule 1 cm inside the seat's front edge.

    That is the value an earlier, hand-derived constant used, and it is the reason the
    check measures rather than trusts a comment.
    """
    root = fixture(clearance=0.62)
    check(bool(problems(root)), "a stand-up that stops 1 cm short must be a failure")


def a_spawn_outside_the_chair_fails() -> None:
    """Moving the spawn away from the chair must not quietly disable the check."""
    root = fixture(spawn_z=20.0)
    found = problems(root)
    check(bool(found), "a spawn that is not seated in the chair must be a failure")
    check(
        any("does not overlap" in entry for entry in found),
        f"the failure must say the spawn is not in the chair, got {found}",
    )


def a_missing_clearance_constant_fails() -> None:
    root = tree(
        {
            seat.LOCATION_SCENE: location_scene(),
            seat.DESK_SCENE: DESK_SCENE,
            seat.CHARACTER_SCENE: CHARACTER_SCENE,
            seat.CONTROLLER: "extends CharacterBody3D\n\nvar _facing_direction: Vector3 = Vector3(0, 0, -1)\n",
        }
    )
    try:
        seat.findings(root)
    except SystemExit:
        check(True, "")
    else:
        check(False, "a controller with no clearance constant must stop the check")


# --- the command -----------------------------------------------------------


def a_passing_fixture_says_so() -> None:
    root = fixture()
    code, output = run_main(["--root", str(root)])
    check(code == 0, "a correct fixture must exit 0")
    check("SEAT_CLEARANCE_OK" in output, "a correct fixture must say so")


def a_failing_fixture_exits_one() -> None:
    root = fixture(facing=(0.0, 0.0, 1.0))
    code, output = run_main(["--root", str(root)])
    check(code == 1, "a failing fixture must exit 1")
    check("SEAT_CLEARANCE_FAILURE" in output, "the failure must be labelled")


def verbose_lists_every_part() -> None:
    root = fixture()
    code, output = run_main(["--root", str(root), "--verbose"])
    check(code == 0, "--verbose must not fail")
    check("Seat" in output and "Back" in output, "every part must be listed")


# --- the repository this landed in ----------------------------------------


def this_repository_stands_up_out_of_its_chair() -> None:
    """Both directions: no finding, and the geometry the docs claim actually holds."""
    found = problems(ROOT)
    check(not found, f"this repository must pass the seat check, got {found}")

    gaps = seat.findings(ROOT)[1]
    check(bool(gaps), "the real chair must have parts to measure")
    worst_name, worst_gap = min(gaps, key=lambda pair: pair[1])
    check(
        worst_gap > 0.0,
        f"after the stand-up the body is still inside the chair's {worst_name} "
        f"by {worst_gap:.3f} m",
    )


def this_repository_really_is_seated() -> None:
    """The opening must still place the protagonist in the chair, not beside it."""
    spawn = seat.spawn_position(ROOT)
    desk = seat.desk_position(ROOT)
    capsule = seat.body_capsule(ROOT)
    boxes = seat.chair_boxes(ROOT)
    placed = [
        (name, (desk[0] + off[0], desk[1] + off[1], desk[2] + off[2]), size)
        for name, off, size in boxes
    ]
    hits = [
        name
        for name, centre, size in placed
        if seat.capsule_intersects_box((spawn[0], spawn[2]), capsule, centre, size)
    ]
    check(bool(hits), "the protagonist must wake seated in the chair, or nothing is tested")


def main() -> int:
    walking_through_the_back_fails()
    not_stepping_clear_at_all_fails()
    stopping_one_centimetre_short_fails()
    a_spawn_outside_the_chair_fails()
    a_missing_clearance_constant_fails()
    a_passing_fixture_says_so()
    a_failing_fixture_exits_one()
    verbose_lists_every_part()
    this_repository_stands_up_out_of_its_chair()
    this_repository_really_is_seated()

    if FAILURES:
        for failure in FAILURES:
            print("SEAT_CLEARANCE_TEST_FAILURE: " + failure)
        print("%d of %d check(s) failed." % (len(FAILURES), CHECKS))
        return 1
    print("SEAT_CLEARANCE_TEST_OK: %d checks." % CHECKS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
