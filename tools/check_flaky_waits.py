#!/usr/bin/env python3
"""Keep the wait-for-a-condition loop in one place (issue #207).

`Engine.time_scale = 4.0` speeds up the *clock*. It does not make the machine faster. A
test that scales time and then waits a fixed number of frames - `await _frames(2)` - is
asking for "two frames of whatever the machine felt like delivering". When the assertion
that follows is about something the engine advances per frame (a tween's opacity, a
label's revealed text, a skip counter), the test is racing the frame rate. It passes on a
quiet CI box and fails on a busy one, and the failure names the feature rather than the
race. That is issue #207: `destination_cue_lifecycle` reported "a floor click drew no
mark" for months while the mark was fine.

The fix is a deadline, not a frame count: poll the condition, give up after a real-time
limit, and report the last observed state. #205 wrote that loop by hand in
`destination_cue_lifecycle_test.gd`. Six files then had their own copy, in two shapes that
disagree at the deadline. `TestHarness.wait_until` now holds the single copy.

## What this check can and cannot decide

It cannot tell a racy wait from a safe one. `dialogue_playback_test.gd` waits two frames
after a key press so the input can propagate, then asserts that a setting changed - safe,
and unrelated to the clock. `reading_progress_test.gd` waits two frames at
`time_scale = 4` for a reveal to finish, then asserts on the revealed text - the race from
#207. Both read as `await _frames(2)` followed by an `_expect`. Any rule that separated
them would be guessing at what the assertion measures, and a linting gate that guesses
cries wolf until people route around it.

So this check does not judge semantics. It freezes the **structural** fact that is
unambiguous and is the actual reason the fix spread: whether an accelerated test holds a
fixed-frame wait at all. The 16 files below do, today. None of them may gain another one,
and none may be added to this list. A test that needs to wait for a condition uses
`TestHarness.wait_until`, which cannot come true late or early because it has no frame
count in it.

That makes the gate a ratchet, not a cleanup: it stops the pattern growing while the
existing 17 are converted file by file. When a file's last fixed wait inside an
accelerated region is replaced, delete its line here; the check then holds the new, lower
count. The list only ever shrinks.

    python3 tools/check_flaky_waits.py            # CI: fail if the baseline grew
    python3 tools/check_flaky_waits.py --list     # every fixed wait, with its line

Standard library only, and it reads only GDScript.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# `Engine.time_scale = 4.0` / `= 1.0`. Anything above 1.0 speeds the clock up.
TIME_SCALE = re.compile(r"Engine\.time_scale\s*=\s*(?P<value>[0-9]*\.?[0-9]+)")

# A wait whose length is a frame count rather than a condition. Both the local helpers the
# tests define (`_frames(2)`, `_physics_frames(4)`) and the raw engine signals, so a file
# cannot sidestep the rule by inlining the loop.
FIXED_WAIT = re.compile(
    r"\b_frames\(\s*\d+\s*\)"
    r"|\b_physics_frames\(\s*\d+\s*\)"
    r"|await\s+process_frame\b"
    r"|await\s+physics_frame\b"
)

# The files that hold both an accelerated clock and a fixed wait, measured on the tree this
# check was introduced against. Every line is an outstanding #207 conversion, not a licence
# to add more; see the module docstring.
BASELINE = {
    "tests/automatic_interaction_test.gd",
    "tests/capture_dialogue_ui.gd",
    "tests/destination_cue_lifecycle_test.gd",
    "tests/dialogue_playback_test.gd",
    "tests/dialogue_pointer_test.gd",
    "tests/interaction_hover_test.gd",
    "tests/interaction_occlusion_test.gd",
    "tests/interaction_visibility_sweep_test.gd",
    "tests/language_switch_test.gd",
    "tests/location_transition_test.gd",
    "tests/navigation_sync_stress_test.gd",
    "tests/navigation_test.gd",
    "tests/opening_line_evidence_test.gd",
    "tests/pointer_target_switch_test.gd",
    "tests/reading_progress_test.gd",
    "tests/step_up_test.gd",
}


def gdscript_files(root: Path) -> list[Path]:
    """Every `.gd` under `tests/`, read from the working tree.

    `git ls-files` is deliberately not used: this must also run on a bare tree and on the
    fixture trees the test builds.
    """
    base = root / "tests"
    if not base.is_dir():
        return []
    return sorted(
        path for path in base.rglob("*.gd") if ".godot" not in path.parts
    )


def fixed_waits(path: Path) -> list[int]:
    """Line numbers of fixed waits that run while the clock is accelerated.

    The flag follows the assignments down the file, which is how the tests use it: one
    `Engine.time_scale = 4.0` near the top covers the cases below it, and the `= 1.0` that
    restores the clock ends the window. A wait before the first assignment is not counted,
    because at that point the clock is still real.
    """
    accelerated = False
    found: list[int] = []
    text = path.read_text(encoding="utf-8-sig")
    for number, line in enumerate(text.splitlines(), 1):
        code = line.split("#", 1)[0]
        scale = TIME_SCALE.search(code)
        if scale:
            accelerated = float(scale["value"]) > 1.0
            continue
        if accelerated and FIXED_WAIT.search(code):
            found.append(number)
    return found


def findings(
    root: Path, baseline: set[str] | None = None
) -> tuple[list[str], list[str]]:
    """Files that gained a fixed wait, and the baseline entries that no longer apply.

    `baseline` is a parameter rather than a closed-over constant so a caller can ask the
    question of another tree - the tests use empty and single-entry baselines on fixture
    trees, where this repository's 16 entries would all read as stale.
    """
    allowed = BASELINE if baseline is None else baseline
    grown: list[str] = []
    stale: list[str] = []
    present: set[str] = set()
    for path in gdscript_files(root):
        relative = path.relative_to(root).as_posix()
        waits = fixed_waits(path)
        if not waits:
            continue
        present.add(relative)
        if relative not in allowed:
            places = ", ".join(str(number) for number in waits)
            grown.append(
                f"{relative}: waits a fixed number of frames while Engine.time_scale is "
                f"above 1.0 (line {places}) - poll the condition with "
                "`TestHarness.wait_until(condition, limit_seconds)` instead of counting "
                "frames, or the assertion races the frame rate (issue #207)"
            )
    for entry in sorted(allowed - present):
        stale.append(
            f"{entry}: is in the baseline but holds no fixed wait under an accelerated "
            "clock any more - delete its line from BASELINE so the ratchet keeps the "
            "lower count"
        )
    return grown, stale


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--root", type=Path, default=root)
    parser.add_argument(
        "--list", action="store_true", help="print every fixed wait with its file and line"
    )
    args = parser.parse_args(argv)

    if args.list:
        total = 0
        for path in gdscript_files(args.root):
            waits = fixed_waits(path)
            if waits:
                relative = path.relative_to(args.root).as_posix()
                total += len(waits)
                print(f"{relative}: {', '.join(str(number) for number in waits)}")
        print(f"{total} fixed wait(s) under an accelerated clock")
        return 0

    # A fixture tree carries its own baseline; this repository's 16 entries would all be
    # stale there. Only the default root is held to the real one.
    baseline = None if args.root.resolve() == ROOT.resolve() else set()
    grown, stale = findings(args.root, baseline)
    if grown or stale:
        for problem in grown + stale:
            print("FLAKY_WAITS_FAILURE: " + problem)
        return 1
    print(
        "FLAKY_WAITS_OK: no test outside the baseline waits a fixed number of frames "
        f"while Engine.time_scale is accelerated; {len(BASELINE)} file(s) still hold "
        "such a wait and are listed in BASELINE for conversion."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
