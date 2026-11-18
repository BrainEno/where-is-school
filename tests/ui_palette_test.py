#!/usr/bin/env python3
"""Both directions for `tools/check_ui_palette.py` (issue #210).

The check exists because the same bone was typed out in eight files and two "ember" oranges
had drifted apart. It is tested with trees this test writes, so neither direction can rot
with the repository's current colours:

- one writer of a value passes; the same RGB in a second file fails, whatever the alpha;
- a colour reached through a name (`MenuStyle.ACCENT`, `Color(MenuStyle.ACCENT, 0.35)`) is
  never a duplicate - the check is about literals, not about how code reads the palette;
- pure white, pure black and `Color(0, 0, 0, 0)` are tween endpoints, not palette entries;
- a `#` comment does not count as a writer;
- `tests/` is out of scope on purpose: a test that pins a colour *should* be able to;
- pairs whose writers are all allowlisted are reported but do not fail, and a
  new pair *between* an allowlisted file and a file outside the allowlist still fails;
- the palette file itself may not load anything or name a UI class: it is the leaf that lets
  the dialogue and actor layers name a colour without importing the interface;
- the command returns 1 on a finding and 0 on this repository.

Run with `python3 tests/ui_palette_test.py`; no engine and no network.
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import check_ui_palette as palette  # noqa: E402

BONE = "Color(0.776, 0.733, 0.643, 1.0)"
BONE_TRANSLUCENT = "Color(0.776, 0.733, 0.643, 0.35)"


def write(root: Path, relative: str, text: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class UiPaletteTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def fail_messages(self) -> list[str]:
        duplicates, _leaks, _known = palette.findings(self.root)
        return duplicates

    # --- the two directions ---------------------------------------------------

    def test_one_writer_passes(self) -> None:
        write(self.root, palette.PALETTE_FILE, f"const ACCENT := {BONE}\n")
        self.assertEqual(self.fail_messages(), [])

    def test_a_second_file_fails(self) -> None:
        write(self.root, palette.PALETTE_FILE, f"const ACCENT := {BONE}\n")
        write(self.root, "scripts/ui/hud.gd", f"var c := {BONE}\n")
        messages = self.fail_messages()
        self.assertEqual(len(messages), 1, messages)
        self.assertIn("scripts/ui/hud.gd", messages[0])
        self.assertIn(palette.PALETTE_FILE, messages[0])

    def test_alpha_is_not_a_second_colour(self) -> None:
        write(self.root, palette.PALETTE_FILE, f"const ACCENT := {BONE}\n")
        write(self.root, "scripts/ui/hud.gd", f"var c := {BONE_TRANSLUCENT}\n")
        self.assertEqual(len(self.fail_messages()), 1)

    def test_named_colours_are_never_duplicates(self) -> None:
        write(self.root, palette.PALETTE_FILE, f"const ACCENT := {BONE}\n")
        write(self.root, "scripts/ui/a.gd",
              "var c := MenuStyle.ACCENT\nvar d := Color(MenuStyle.ACCENT, 0.35)\n")
        write(self.root, "scripts/ui/b.gd", "var e := Color(MenuStyle.SHEET, 0.96)\n")
        self.assertEqual(self.fail_messages(), [])

    def test_achromatic_and_comments_do_not_count(self) -> None:
        write(self.root, palette.PALETTE_FILE, f"const ACCENT := {BONE}\n")
        write(self.root, "scripts/ui/a.gd",
              "var a := Color(1.0, 1.0, 1.0, 0.0)\nvar b := Color(0, 0, 0, 0)\n"
              "var c := Color(1, 1, 1, 1)\n")
        write(self.root, "scripts/ui/b.gd", f"# was {BONE}\nvar nothing := 0\n")
        self.assertEqual(self.fail_messages(), [])

    def test_tests_are_out_of_scope(self) -> None:
        write(self.root, palette.PALETTE_FILE, f"const ACCENT := {BONE}\n")
        write(self.root, "tests/layout_test.gd", f"var expected := {BONE}\n")
        self.assertEqual(self.fail_messages(), [])

    # --- the allowlist --------------------------------------------------------

    def test_a_known_pair_is_reported_but_passes(self) -> None:
        allowed = "scripts/ui/check_overlay.gd"
        write(self.root, palette.PALETTE_FILE, f"const ACCENT := {BONE}\n")
        write(self.root, allowed, f"const PAPER := {BONE}\n")
        duplicates, _leaks, known = palette.findings(self.root)
        self.assertEqual(duplicates, [])
        self.assertEqual(len(known), 1, known)

    def test_an_allowlisted_file_does_not_license_a_third_writer(self) -> None:
        write(self.root, palette.PALETTE_FILE, f"const ACCENT := {BONE}\n")
        write(self.root, "scripts/ui/check_overlay.gd", f"const PAPER := {BONE}\n")
        write(self.root, "scripts/ui/hud.gd", f"var c := {BONE}\n")
        # The third writer is not allowlisted, so every pair involving it is a failure again.
        messages = self.fail_messages()
        self.assertTrue(messages, messages)
        self.assertTrue(all("scripts/ui/hud.gd" in m for m in messages), messages)

    def test_the_palette_must_stay_a_leaf(self) -> None:
        write(self.root, palette.PALETTE_FILE,
              "const ACCENT := Color(0.776, 0.733, 0.643, 1.0)\n"
              "const OTHER := preload(\"res://scripts/ui/hud.gd\")\n")
        problems = palette.palette_file_stays_a_leaf(self.root)
        self.assertTrue(any("must not load anything" in p for p in problems), problems)

        write(self.root, palette.PALETTE_FILE,
              "const ACCENT := Color(0.776, 0.733, 0.643, 1.0)\nconst INK := MenuStyle.INK\n")
        problems = palette.palette_file_stays_a_leaf(self.root)
        self.assertTrue(any("names MenuStyle" in p for p in problems), problems)

        # A comment naming the UI class is the file explaining itself, not a dependency.
        write(self.root, palette.PALETTE_FILE,
              "## MenuStyle re-exports these.\n"
              "const ACCENT := Color(0.776, 0.733, 0.643, 1.0)\n")
        self.assertEqual(palette.palette_file_stays_a_leaf(self.root), [])

    def test_a_missing_palette_file_is_reported(self) -> None:
        problems = palette.palette_file_stays_a_leaf(self.root)
        self.assertTrue(any("missing" in p for p in problems), problems)

    def test_the_allowlist_names_files_that_exist(self) -> None:
        """A stale allowlist entry would silently bless a file that was renamed."""
        root = Path(__file__).resolve().parent.parent
        for relative in sorted(palette.ALLOWLIST):
            self.assertTrue((root / relative).is_file(), f"allowlist names a missing file: {relative}")

    # --- the command ----------------------------------------------------------

    def test_command_line(self) -> None:
        write(self.root, palette.PALETTE_FILE, f"const ACCENT := {BONE}\n")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = palette.main(["--root", str(self.root)])
        self.assertEqual(code, 0, out.getvalue())

        write(self.root, palette.PALETTE_FILE, f"const ACCENT := {BONE}\n")
        write(self.root, "scripts/ui/hud.gd", f"var c := {BONE}\n")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = palette.main(["--root", str(self.root), "--list"])
        self.assertEqual(code, 1)
        self.assertIn("UI_PALETTE_FAILURE:", out.getvalue())

    def test_this_repository(self) -> None:
        root = Path(__file__).resolve().parent.parent
        duplicates, _leaks, known = palette.findings(root)
        self.assertEqual(duplicates, [], "the palette regressed in the repository itself")
        # The reading band was the last outstanding pair group; #231 merged and its shared
        # inks moved into the palette, so nothing is waiting on the allowlist any more.
        self.assertEqual(known, [], "an allowlisted pair came back: fold it into Palette")


if __name__ == "__main__":
    unittest.main(verbosity=2)
