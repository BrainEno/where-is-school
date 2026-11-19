#!/usr/bin/env python3
"""Ratchet fixed-frame awaits in tests with a visibly accelerated clock (#207).

Engine.time_scale changes the clock, not the runner's frame rate. A check that
measures a tween or reveal should wait on its state with TestHarness.wait_until,
not on an arbitrary number of frames. An input-propagation wait can be safe;
this tool does not decide that from the text of an assertion.

Recognises direct numeric Engine.time_scale assignments and the repository's
fixed await spellings in source order. A dynamic assignment ends that lexical
window, since its value is unknown. This is not a call-graph or a timing proof.
Counts include helper bodies, not just call sites. Keep the per-file counts
frozen or lower; an existing entry must not let a test add another wait.

    python3 tools/check_flaky_waits.py
    python3 tools/check_flaky_waits.py --list
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from gdscript_source import DECIMAL, mask_non_code, numbered_matches

ROOT = Path(__file__).resolve().parent.parent

# Use one ordered match stream: a scale change and an await can share a line.
# An equality test is not an assignment. Don't read `4.0 / divisor` as `4.0`.
EVENT = re.compile(
    rf"(?P<clock>\bEngine[ \t]*\.[ \t]*time_scale[ \t]*=(?!=)[ \t]*"
    rf"(?:(?P<rate>{DECIMAL})(?=[ \t]*(?:[;\r\n]|\Z)))?)"
    r"|\bawait[ \t]+(?:"
    r"(?:self\s*\.\s*)?_(?:physics_)?frames\s*\(\s*\+?[0-9](?:_?[0-9])*\s*,?\s*\)"
    r"|(?:(?:self|tree|get_tree\s*\(\s*\))\s*\.\s*)?(?:process_frame|physics_frame)\b(?![ \t]*[.(])"
    r")"
)

# Counts of legacy waits, not per-file exemptions. No line numbers: unrelated
# edits may move a wait without increasing the debt. Equal-count replacements
# require review; this static guard detects increases, not intent.
BASELINE: dict[str, int] = {
    "tests/automatic_interaction_test.gd": 46,
    "tests/capture_dialogue_ui.gd": 9,
    "tests/destination_cue_lifecycle_test.gd": 10,
    "tests/dialogue_playback_test.gd": 35,
    "tests/dialogue_pointer_test.gd": 28,
    "tests/interaction_hover_test.gd": 18,
    "tests/interaction_occlusion_test.gd": 47,
    "tests/interaction_visibility_sweep_test.gd": 4,
    "tests/language_switch_test.gd": 14,
    "tests/location_transition_test.gd": 17,
    "tests/navigation_sync_stress_test.gd": 5,
    "tests/navigation_test.gd": 22,
    "tests/opening_line_evidence_test.gd": 5,
    "tests/pointer_target_switch_test.gd": 20,
    "tests/reading_progress_test.gd": 7,
    "tests/step_up_test.gd": 4,
}


def fixed_waits(path: Path) -> list[int]:
    code = mask_non_code(path.read_text(encoding="utf-8-sig"))
    accelerated = False
    found: list[int] = []
    for line, match in numbered_matches(EVENT, code):
        if match["clock"] is not None:
            rate = match["rate"]
            accelerated = rate is not None and float(rate) > 1.0
        elif accelerated:
            found.append(line)
    return found


def scan(root: Path) -> dict[str, list[int]]:
    found: dict[str, list[int]] = {}
    for path in sorted((root / "tests").rglob("*.gd")):
        relative = path.relative_to(root)
        if ".godot" in relative.parts:
            continue
        waits = fixed_waits(path)
        if waits:
            found[relative.as_posix()] = waits
    return found


def compare(
    observed: dict[str, list[int]], baseline: dict[str, int]
) -> tuple[list[str], list[str]]:
    grown: list[str] = []
    stale: list[str] = []
    for path in sorted(observed.keys() | baseline.keys()):
        waits = observed.get(path, [])
        actual, limit = len(waits), baseline.get(path, 0)
        if actual > limit:
            where = ", ".join(map(str, waits))
            grown.append(
                f"{path}: {actual} fixed waits while Engine.time_scale is above 1.0 "
                f"(baseline {limit}; line {where}) - use TestHarness.wait_until(condition, limit_seconds) "
                "instead of adding fixed frames (issue #207)"
            )
        elif actual < limit:
            action = "delete its line from BASELINE" if not actual else f"lower BASELINE from {limit} to {actual}"
            stale.append(f"{path}: now has {actual} fixed waits; {action} to keep the lower count")
    return grown, stale


def findings(root: Path, baseline: dict[str, int] | None = None) -> tuple[list[str], list[str]]:
    return compare(scan(root), BASELINE if baseline is None else baseline)


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=root)
    parser.add_argument("--list", action="store_true", help="report all recognised wait sites")
    args = parser.parse_args(argv)
    observed = scan(args.root)
    total = sum(map(len, observed.values()))
    if args.list:
        for path, waits in observed.items():
            print(f"{path}: {', '.join(map(str, waits))}")
        print(f"{total} fixed wait(s) under an accelerated clock")
        return 0
    baseline = BASELINE if args.root.resolve() == ROOT else {}
    grown, stale = compare(observed, baseline)
    if grown or stale:
        for problem in grown + stale:
            print("FLAKY_WAITS_FAILURE: " + problem)
        return 1
    print(f"FLAKY_WAITS_OK: {total} legacy waits across {len(observed)} file(s); no new waits")
    return 0


if __name__ == "__main__":
    sys.exit(main())
