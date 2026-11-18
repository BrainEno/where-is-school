#!/usr/bin/env python3
"""Boundary tests for ``tools/check_flaky_waits.py`` (issue #207).

The check freezes one unambiguous fact: a test whose clock is accelerated must not wait a
fixed number of frames. It cannot tell a racy wait from a safe one, so it does not try -
see its docstring. What it can do is refuse to let the pattern grow, and these tests pin
both halves of that bargain, with test trees this file writes:

- a fixed wait under ``Engine.time_scale = 4.0`` in a file that is not in the baseline is
  a finding, and the message names the file, the line and the helper to use instead;
- the same wait is *not* a finding before the first assignment, after ``= 1.0`` restores
  the clock, or when the file only ever slows the clock down (``0.5``) - the flag follows
  the assignments rather than assuming the whole file is accelerated;
- all four spellings are caught: ``_frames(n)``, ``_physics_frames(n)``,
  ``await process_frame`` and ``await physics_frame``;
- a baseline entry whose file no longer holds such a wait is a finding too, so the ratchet
  cannot quietly stay loose after a conversion;
- the baseline itself is in sync with this repository - both directions - which is the
  assertion that would have caught a stale entry when this check landed;
- the command returns 1 on a finding, 0 on a clean tree, and ``--list`` reports the waits
  without failing.

Run it with ``python3 tests/check_flaky_waits_test.py`` (CI does). No network needed.
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import check_flaky_waits as waits  # noqa: E402  (the path has to be set up first)

FAILURES: list[str] = []
CHECKS: int = 0

ROOT = Path(__file__).resolve().parent.parent


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


def test_file(body: str) -> str:
    """A minimal headless test script around `body`."""
    return (
        "extends SceneTree\n"
        "\n"
        "\n"
        "func _initialize() -> void:\n"
        "\t_run()\n"
        "\n"
        "\n"
        "func _run() -> void:\n" + body
    )


def tree(files: dict[str, str]) -> Path:
    """A temporary repository root holding `files`, keyed by path under it."""
    root = Path(tempfile.mkdtemp(prefix="flaky_waits_"))
    for relative, text in files.items():
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
    return root


def run_main(argv: list[str]) -> tuple[int, str]:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = waits.main(argv)
    return code, out.getvalue()


def accelerated(body: str) -> str:
    return test_file("\tEngine.time_scale = 4.0\n" + body)


# --- the finding -----------------------------------------------------------


def a_new_fixed_wait_is_refused() -> None:
    root = tree({"tests/new_test.gd": accelerated("\tawait _frames(2)\n")})
    code, output = run_main(["--root", str(root)])
    check(code == 1, "a new fixed wait under an accelerated clock must exit 1")
    check("FLAKY_WAITS_FAILURE" in output, "the failure must be labelled")
    check("tests/new_test.gd" in output, "the finding must name the file")
    expected = accelerated("\tawait _frames(2)\n").split("\n").index("\tawait _frames(2)") + 1
    check(f"line {expected}" in output, "the finding must name the line the wait is on")
    check("TestHarness.wait_until" in output, "the finding must name the helper to use")


def every_spelling_is_caught() -> None:
    spellings = {
        "frames": "\tawait _frames(2)\n",
        "physics_frames": "\tawait _physics_frames(4)\n",
        "process_frame": "\tawait process_frame\n",
        "physics_frame": "\tawait physics_frame\n",
    }
    for name, line in spellings.items():
        root = tree({"tests/new_test.gd": accelerated(line)})
        code, _ = run_main(["--root", str(root)])
        check(code == 1, f"`{name}` under an accelerated clock must be a finding")


def an_accelerated_file_may_still_wait_on_a_condition() -> None:
    root = tree({
        "tests/harness_test.gd": accelerated(
            "\tif not await Harness.wait_until(func() -> bool: return _done, 2.0):\n"
            "\t\treturn\n"
        )
    })
    code, output = run_main(["--root", str(root)])
    check(code == 0, "waiting on a condition is the fix, not a finding")
    check("FLAKY_WAITS_OK" in output, "a clean tree must say so")


# --- the boundaries where a fixed wait is fine -----------------------------


def a_wait_before_the_acceleration_is_fine() -> None:
    body = test_file(
        "\tawait _frames(2)\n"
        "\tEngine.time_scale = 4.0\n"
        "\tawait Harness.wait_until(func() -> bool: return true, 1.0)\n"
    )
    root = tree({"tests/new_test.gd": body})
    code, _ = run_main(["--root", str(root)])
    check(code == 0, "a fixed wait on a real clock is not what this check refuses")


def restoring_the_clock_ends_the_window() -> None:
    body = test_file(
        "\tEngine.time_scale = 4.0\n"
        "\tEngine.time_scale = 1.0\n"
        "\tawait _frames(2)\n"
    )
    root = tree({"tests/new_test.gd": body})
    code, _ = run_main(["--root", str(root)])
    check(code == 0, "a wait after the clock is restored runs on real time again")


def slowing_the_clock_is_not_acceleration() -> None:
    body = test_file("\tEngine.time_scale = 0.5\n\tawait _frames(2)\n")
    root = tree({"tests/new_test.gd": body})
    code, _ = run_main(["--root", str(root)])
    check(code == 0, "only a clock faster than real time is the race")


def a_test_outside_the_window_is_not_scanned() -> None:
    root = tree({"scripts/not_a_test.gd": "extends Node\n## Engine.time_scale = 4.0\n"})
    code, output = run_main(["--root", str(root)])
    check(code == 0, "the check reads tests/, and a comment is not an assignment")


# --- the ratchet -----------------------------------------------------------


def a_stale_baseline_entry_is_refused() -> None:
    root = tree({"tests/converted_test.gd": accelerated("\tpass\n")})
    grown, stale = waits.findings(root, {"tests/converted_test.gd"})
    check(not grown, "a converted file must not be reported as growing")
    check(any("delete its line from BASELINE" in entry for entry in stale),
          "a baseline entry left behind must say how to fix the ratchet")
    check(any("tests/converted_test.gd" in entry for entry in stale),
          "the stale entry must name the file")


def a_baseline_file_does_not_grow() -> None:
    """An accepted file keeping its waits passes.

    The baseline is per file, not per line, so a file already on the list is accepted as it
    stands. That is the documented limit of the ratchet: it stops the pattern spreading to
    new files, and converting an accepted file is tracked by the issue rather than by this
    check. Pinning the limit here keeps it honest instead of implied.
    """
    root = tree({"tests/known_test.gd": accelerated("\tawait _frames(2)\n")})
    grown, stale = waits.findings(root, {"tests/known_test.gd"})
    check(not grown, "an accepted file is accepted")
    check(not stale, "an accepted file that still waits is not stale")


# --- the repository this landed in ----------------------------------------


def this_repository_is_in_sync() -> None:
    """Both directions: no stray growth, and no baseline line that has gone stale.

    This is the assertion that would have caught a stale entry the day this check landed.
    """
    grown, stale = waits.findings(ROOT)
    check(not grown, f"this repository must not hold an unreviewed fixed wait: {grown}")
    check(not stale, f"this repository's baseline must not hold stale entries: {stale}")


def this_repository_lists_its_waits() -> None:
    code, output = run_main(["--root", str(ROOT), "--list"])
    check(code == 0, "--list must not fail")
    check("fixed wait(s) under an accelerated clock" in output,
          "the listing must end with a count")


def main() -> int:
    a_new_fixed_wait_is_refused()
    every_spelling_is_caught()
    an_accelerated_file_may_still_wait_on_a_condition()
    a_wait_before_the_acceleration_is_fine()
    restoring_the_clock_ends_the_window()
    slowing_the_clock_is_not_acceleration()
    a_test_outside_the_window_is_not_scanned()
    a_stale_baseline_entry_is_refused()
    a_baseline_file_does_not_grow()
    this_repository_is_in_sync()
    this_repository_lists_its_waits()

    if FAILURES:
        for failure in FAILURES:
            print("FLAKY_WAITS_TEST_FAILURE: " + failure)
        print("%d of %d check(s) failed." % (len(FAILURES), CHECKS))
        return 1
    print("FLAKY_WAITS_TEST_OK: %d checks." % CHECKS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
