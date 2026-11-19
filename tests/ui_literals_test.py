#!/usr/bin/env python3
"""Boundary tests for ``tools/check_ui_literals.py`` (issue #229).

The check is a ratchet on hard-coded colour literals inside the interface. It cannot say
whether a literal *should* move, so it does not try - see its docstring. What it can do is
refuse a new one and refuse a stale allowlist line, and these tests pin both, on fixture
trees this file writes:

- a literal in a new `scripts/ui/` file is a finding, naming the file, the line and the fix;
- pure white, pure black and fully transparent are not findings (tween and modulate
  endpoints), and neither is a colour reached through a name;
- a baseline line whose literal is gone is a finding, so the list cannot stay loose;
- one allowed RGBA occurrence survives edits around it but does not allow another;
- the command returns 1 on a finding, 0 on a clean tree, and `--list` reports without
  failing;
- this repository is in sync both ways, which is the assertion that would have caught a
  stale entry the day the check landed.

Run it with ``python3 tests/ui_literals_test.py`` (CI does). No network needed.
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import check_ui_literals as literals  # noqa: E402  (the path has to be set up first)

FAILURES: list[str] = []
CHECKS: int = 0
TEMP = tempfile.TemporaryDirectory(prefix="ui_literals_")

ROOT = Path(__file__).resolve().parent.parent


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


def tree(files: dict[str, str]) -> Path:
    """A temporary repository root holding `files`, keyed by path under it."""
    root = Path(tempfile.mkdtemp(dir=TEMP.name))
    for relative, text in files.items():
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
    return root


def run_main(argv: list[str]) -> tuple[int, str]:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = literals.main(argv)
    return code, out.getvalue()


INK = 'const X := Color(0.4, 0.2, 0.2, 1.0)\n'
PANEL = "scripts/ui/panel.gd"
APPROVED = {(PANEL, (0.4, 0.2, 0.2, 1.0)): "its own one-off ink"}


# --- the finding -----------------------------------------------------------


def a_new_literal_is_refused() -> None:
    root = tree({"scripts/ui/panel.gd": "extends Control\n" + INK})
    code, output = run_main(["--root", str(root)])
    check(code == 1, "a new interface literal must exit 1")
    check("UI_LITERALS_FAILURE" in output, "the failure must be labelled")
    check("scripts/ui/panel.gd:2" in output, "the finding must name the file and line")
    check("Palette" in output, "the finding must name where the value belongs")


def an_out_of_tree_file_is_not_scanned() -> None:
    root = tree({"scripts/world/thing.gd": "extends Node3D\n" + INK})
    code, _ = run_main(["--root", str(root)])
    check(code == 0, "the check reads scripts/ui/, not the whole tree")


# --- what is not a finding -------------------------------------------------


def tween_endpoints_are_not_findings() -> None:
    body = (
        "extends Control\n"
        "const CLEAR := Color(1, 1, 1, 0)\n"
        "const CLEAR2 := Color(1.0, 1.0, 1.0, 0.0)\n"
        "const BLACK := Color(0.0, 0.0, 0.0, 1.0)\n"
        "const VIGNETTE := Color(0.0, 0.0, 0.0, 0.5)\n"
    )
    root = tree({"scripts/ui/panel.gd": body})
    code, _ = run_main(["--root", str(root)])
    check(code == 0, "pure white and pure black are tween endpoints, not palette entries")


def a_named_colour_is_not_a_finding() -> None:
    body = (
        "extends Control\n"
        "const A := Color(Palette.INK, 0.5)\n"
        "const B := Palette.ACCENT\n"
        "const C := Color(MenuStyle.ACCENT, 0.35)\n"
    )
    root = tree({"scripts/ui/panel.gd": body})
    code, _ = run_main(["--root", str(root)])
    check(code == 0, "a colour reached through a name is the fix, not a finding")


def a_comment_is_not_a_finding() -> None:
    root = tree({"scripts/ui/panel.gd": "extends Control\n# Color(0.4, 0.2, 0.2, 1.0)\n"})
    code, _ = run_main(["--root", str(root)])
    check(code == 0, "a literal in a comment is prose, not code")


# --- the ratchet -----------------------------------------------------------


def a_stale_baseline_line_is_refused() -> None:
    root = tree({"scripts/ui/panel.gd": "extends Control\n"})
    grown, stale = literals.findings(root, APPROVED)
    check(not grown, "a file with no literals must not be reported as growing")
    check(any("delete its line" in entry for entry in stale),
          "a baseline line left behind must say how to fix the ratchet")
    check(any(PANEL in entry and "Color(0.4, 0.2, 0.2, 1.0)" in entry for entry in stale),
          "the stale line must name the file and the exact old colour")


def an_allowed_literal_is_accepted() -> None:
    root = tree({"scripts/ui/panel.gd": "extends Control\n" + INK})
    grown, stale = literals.findings(root, APPROVED)
    check(not grown, "an allowlisted literal is accepted")
    check(not stale, "an allowlisted literal that still exists is not stale")


def the_baseline_is_per_occurrence_not_per_file() -> None:
    """A file with one allowed literal may not gain a second.

    This is the part worth pinning: if the ratchet were per file, an allowlisted file could
    grow without limit and the check would look like it was working while doing nothing.
    """
    body = "extends Control\n" + INK + "const Y := Color(0.1, 0.2, 0.3, 1.0)\n"
    root = tree({"scripts/ui/panel.gd": body})
    grown, stale = literals.findings(root, APPROVED)
    check(len(grown) == 1, f"a second literal in an allowlisted file must be refused, got {grown}")
    check(any("panel.gd:3" in entry for entry in grown), "the finding must name the new line")
    check(not stale, "the allowed line is still there, so it is not stale")



def multiline_numeric_literal_is_found_at_the_constructor() -> None:
    body = "extends Control\nconst INK = Color(\n\t4e-1, # warm base\n\t+0.2,\n\t.2,\n)\n"
    root = tree({PANEL: body})
    grown, stale = literals.findings(root, {})
    check(not stale and len(grown) == 1, "splitting a numeric constructor cannot hide it")
    check(f"{PANEL}:2: Color(0.4, 0.2, 0.2, 1.0)" in grown[0],
          "use the first line as location and report the default alpha")
    check(literals.findings(root, APPROVED) == ([], []), "equivalent formatting of the approved colour passes")


def unrelated_edits_do_not_move_an_allowance_to_another_colour() -> None:
    root = tree({PANEL: "extends Control\n# The following ink is local.\n\n" + INK})
    check(literals.findings(root, APPROVED) == ([], []), "adding lines cannot invalidate an unchanged RGBA")
    (root / PANEL).write_text("extends Control\n" + INK.replace("0.4", "0.6"), encoding="utf-8")
    grown, stale = literals.findings(root, APPROVED)
    check(len(grown) == 1 and len(stale) == 1, "replacing a literal at the same line is not allowlisted")
    check("Color(0.6, 0.2, 0.2, 1.0)" in grown[0], "show the unapproved value")
    check("Color(0.4, 0.2, 0.2, 1.0)" in stale[0], "show the retired value")


def alpha_is_part_of_the_reviewed_value() -> None:
    root = tree({PANEL: "extends Control\n" + INK.replace("1.0)", "0.6)")})
    grown, stale = literals.findings(root, APPROVED)
    check(len(grown) == 1 and len(stale) == 1, "an opacity change needs the same review as a tint change")


def two_equal_colours_on_the_same_line_still_count_twice() -> None:
    root = tree({PANEL: "extends Control\n" + INK.strip() + "; " + INK.replace("const X", "const Y")})
    grown, stale = literals.findings(root, APPROVED)
    check(len(grown) == 1 and not stale, "one allowance cannot cover a duplicate at the same location")
    check(f"{PANEL}:2:" in grown[0], "the report cannot lose the second match's line")


def an_exception_cannot_be_spent_in_a_different_file() -> None:
    moved = "scripts/ui/new_panel.gd"
    root = tree({moved: "extends Control\n" + INK})
    grown, stale = literals.findings(root, APPROVED)
    check(len(grown) == 1 and moved in grown[0], "exceptions do not transfer to new files")
    check(len(stale) == 1 and PANEL in stale[0], "removing the old source leaves a stale allowance")


def numeric_notation_does_not_create_a_new_exception() -> None:
    root = tree({PANEL: "extends Control\nconst PRIMARY = Color(0x1, 0b0, 0.0, 0.5_0)\n"})
    uses, remaining = literals.scan(root, {})
    check(not remaining and len(uses) == 1 and uses[0].color == (1, 0, 0, 0.5),
          "recognise base-prefixed integers and digit separators in channel arguments")


def only_code_is_scanned_and_quoted_arguments_are_not_empty() -> None:
    root = tree({PANEL: (
        "extends Control\n"
        '# Long string below includes "quotes" and # marks.\n'
        'const DOC = """\nColor(0.6, 0.4, 0.2)\n# Color(0.1, 0.2, 0.3)\n"""\n'
        r'const EXAMPLE = "\"Color(.4, .2, .2)\" # still literal"' + "\n"
        "const EXAMPLE_NAME = &'Color(0.4, 0.2, 0.2)'\n"
        'const COLOR_BY_NAME = Color("firebrick")\n'
        'const ALPHA = Color(0.4, 0.2, 0.2, "alpha".to_float())\n'
        'const COMPUTED = Color(0.4, 0.2, BLUE)\n'
    )})
    check(literals.findings(root, {}) == ([], []), "prose and computed channels are outside numeric RGB(A)")
    code, output = run_main(["--root", str(root), "--list"])
    check(code == 0 and "0 interface literal(s)" in output, "list and gate must use the same scanner")


def report_names_unapproved_and_kept_occurrences_consistently() -> None:
    root = tree({PANEL: "extends Control\n" + INK})
    row, = literals.scan(root, APPROVED)[0]
    check(row.reason == APPROVED[(PANEL, row.color)], "the kept occurrence must retain its review reason")
    code, output = run_main(["--root", str(root), "--list"])
    check(code == 0 and "[NEW]" in output, "a fixture without its own baseline lists an unapproved colour")
    code, output = run_main(["--root", str(root)])
    check(code == 1 and f"{PANEL}:2:" in output, "the gate finds the same occurrence as the list")


# --- the command -----------------------------------------------------------


def list_does_not_fail() -> None:
    root = tree({"scripts/ui/panel.gd": "extends Control\n" + INK})
    code, output = run_main(["--root", str(root), "--list"])
    check(code == 0, "--list must not fail on a new literal; it is a report")
    check("interface literal(s)" in output, "the listing must end with a count")


def clean_tree_says_so() -> None:
    root = tree({"scripts/ui/panel.gd": "extends Control\nconst A := Palette.INK\n"})
    code, output = run_main(["--root", str(root)])
    check(code == 0, "a clean tree must exit 0")
    check("UI_LITERALS_OK" in output, "a clean tree must say so")


# --- the repository this landed in ----------------------------------------


def this_repository_is_in_sync() -> None:
    grown, stale = literals.findings(ROOT)
    check(not grown, f"this repository must not hold an unreviewed literal: {grown}")
    check(not stale, f"this repository's baseline must not hold stale lines: {stale}")


def this_repository_lists_its_literals() -> None:
    code, output = run_main(["--root", str(ROOT), "--list"])
    check(code == 0, "--list must not fail on this repository")
    check("interface literal(s)" in output, "the listing must end with a count")


def main() -> int:
    a_new_literal_is_refused()
    an_out_of_tree_file_is_not_scanned()
    tween_endpoints_are_not_findings()
    a_named_colour_is_not_a_finding()
    a_comment_is_not_a_finding()
    a_stale_baseline_line_is_refused()
    an_allowed_literal_is_accepted()
    the_baseline_is_per_occurrence_not_per_file()
    multiline_numeric_literal_is_found_at_the_constructor()
    unrelated_edits_do_not_move_an_allowance_to_another_colour()
    alpha_is_part_of_the_reviewed_value()
    two_equal_colours_on_the_same_line_still_count_twice()
    an_exception_cannot_be_spent_in_a_different_file()
    numeric_notation_does_not_create_a_new_exception()
    only_code_is_scanned_and_quoted_arguments_are_not_empty()
    report_names_unapproved_and_kept_occurrences_consistently()
    list_does_not_fail()
    clean_tree_says_so()
    this_repository_is_in_sync()
    this_repository_lists_its_literals()

    if FAILURES:
        for failure in FAILURES:
            print("UI_LITERALS_TEST_FAILURE: " + failure)
        print("%d of %d check(s) failed." % (len(FAILURES), CHECKS))
        return 1
    print("UI_LITERALS_TEST_OK: %d checks." % CHECKS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
