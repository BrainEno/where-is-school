#!/usr/bin/env python3
"""Both directions for `tools/check_story_flags.py` (issue #292).

Each rule is proved to fail on a tree this test writes, and the clean tree to pass, so the
check cannot rot with the repository's own flags:

- a registry constant nothing writes, reads or names is refused;
- a flag content writes but the registry does not declare is refused;
- a written flag nothing reads is refused unless `WRITE_ONLY` lists it with a reason;
- a `WRITE_ONLY` entry that gained a reader, that content no longer writes, or that has
  no reason is refused;
- `ALL_FLAGS` missing a constant, or listing one twice, is refused;
- a test naming a flag is not a reader; game code naming it (by constant or by string) is;
- a location's `arrival_flags` is both written and read (the notebook's route);
- generated flags (`check:...`) are out of scope;
- the command returns 0 on this repository.

Run with `python3 tests/story_flags_test.py`; no engine and no network.
"""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import check_story_flags as flags  # noqa: E402


def registry(consts: dict[str, str], listed: list[str] | None = None) -> str:
    lines = ["class_name StoryFlags", "extends RefCounted", ""]
    for name, value in consts.items():
        lines += [f"## bool: {value}.", f'const {name}: StringName = &"{value}"']
    names = list(consts) if listed is None else listed
    lines += ["", "const ALL_FLAGS: Array[StringName] = ["] + [f"\t{n}," for n in names] + ["]", ""]
    return "\n".join(lines)


class Tree:
    """A minimal repository: a registry, one dialogue file, a location file, one script."""

    def __init__(self, base: Path) -> None:
        self.base = base
        self.consts = {"MET_Q": "met_q", "SAW_DOOR": "saw_door"}
        self.listed: list[str] | None = None
        # met_q is written by a dialogue and read by a condition; saw_door is read by code.
        self.nodes: list[dict] = [
            {"id": "a", "effects": [{"type": "set_flag", "flag": "met_q", "value": True}]},
            {"id": "b", "conditions": {"all_flags": ["met_q"], "not_flags": ["check:c:n"]}},
        ]
        self.locations: dict = {"classroom": {"start": True}}
        self.script = "func _ready() -> void:\n\tprint(GameState.has_flag(StoryFlags.SAW_DOOR))\n"
        self.test_script = ""

    def write(self) -> Path:
        files = {
            flags.REGISTRY: registry(self.consts, self.listed),
            "data/dialogue/en/room.json": json.dumps({"conversations": [{"id": "c", "nodes": self.nodes}]}),
            "data/inspections/en/room.json": json.dumps({"inspections": []}),
            flags.LOCATIONS: json.dumps({"format_version": 1, "locations": self.locations}),
            "scripts/world/door.gd": self.script,
            "tests/door_test.gd": self.test_script,
        }
        for rel, text in files.items():
            path = self.base / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        return self.base

    def audit(self, write_only: dict[str, str] | None = None) -> list[str]:
        return flags.audit(self.write(), {} if write_only is None else write_only)


class StoryFlagsTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tree = Tree(Path(self._tmp.name))

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def assertFinding(self, problems: list[str], fragment: str) -> None:
        self.assertTrue(any(fragment in p for p in problems), f"no finding with {fragment!r} in {problems}")

    def test_clean_tree_passes(self) -> None:
        self.assertEqual(self.tree.audit(), [])

    def test_unused_constant_fails(self) -> None:
        self.tree.consts["NOTED_B_LATE"] = "noted_b_late"
        self.assertFinding(self.tree.audit(), "NOTED_B_LATE")

    def test_a_test_is_not_a_user(self) -> None:
        self.tree.consts["NOTED_B_LATE"] = "noted_b_late"
        self.tree.test_script = "func t() -> void:\n\tassert(StoryFlags.NOTED_B_LATE)\n"
        self.assertFinding(self.tree.audit(), "NOTED_B_LATE")

    def test_code_naming_by_string_is_a_user(self) -> None:
        self.tree.consts["NOTED_B_LATE"] = "noted_b_late"
        self.tree.script += 'func _x() -> void:\n\tGameState.set_flag(&"noted_b_late", true)\n'
        self.assertEqual(self.tree.audit(), [])

    def test_undeclared_written_flag_fails(self) -> None:
        self.tree.nodes.append({"id": "d", "effects": [{"type": "set_flag", "flag": "shed_open", "value": True}]})
        problems = self.tree.audit({"shed_open": "outcome kept for later"})
        self.assertFinding(problems, 'writes "shed_open", which')

    def test_unread_written_flag_fails_unless_write_only(self) -> None:
        self.tree.consts["SHED_OPEN"] = "shed_open"
        self.tree.nodes.append({"id": "d", "effects": [{"type": "set_flag", "flag": "shed_open", "value": True}]})
        self.assertFinding(self.tree.audit(), "nothing in the game reads it")
        self.assertEqual(self.tree.audit({"shed_open": "outcome kept for later"}), [])

    def test_write_only_entry_with_a_reader_fails(self) -> None:
        self.assertFinding(self.tree.audit({"met_q": "kept"}), "now has a reader")

    def test_write_only_entry_no_longer_written_fails(self) -> None:
        self.assertFinding(self.tree.audit({"gone_flag": "kept"}), "no longer written")

    def test_write_only_entry_needs_a_reason(self) -> None:
        self.tree.consts["SHED_OPEN"] = "shed_open"
        self.tree.nodes.append({"id": "d", "effects": [{"type": "set_flag", "flag": "shed_open", "value": True}]})
        self.assertFinding(self.tree.audit({"shed_open": " "}), "has no reason")

    def test_all_flags_must_be_complete_and_unique(self) -> None:
        self.tree.listed = ["MET_Q"]
        self.assertFinding(self.tree.audit(), "ALL_FLAGS is missing SAW_DOOR")
        self.tree.listed = ["MET_Q", "SAW_DOOR", "MET_Q"]
        self.assertFinding(self.tree.audit(), "more than once")

    def test_arrival_flags_are_written_and_read(self) -> None:
        self.tree.consts["LEFT_CLASSROOM"] = "left_classroom"
        self.tree.locations["corridor"] = {"arrival_flags": ["left_classroom"]}
        self.assertEqual(self.tree.audit(), [])
        self.tree.locations["corridor"] = {"arrival_flags": ["left_school"]}
        self.assertFinding(self.tree.audit(), 'writes "left_school", which')

    def test_generated_flags_are_out_of_scope(self) -> None:
        self.tree.nodes.append({"id": "e", "effects": [{"type": "set_flag", "flag": "seen:door", "value": True}]})
        self.assertEqual(self.tree.audit(), [])

    def test_command_passes_on_this_repository(self) -> None:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = flags.main(["--check"])
        self.assertEqual(code, 0, out.getvalue())
        self.assertIn("STORY_FLAGS=success", out.getvalue())

    def test_command_fails_on_a_bad_tree(self) -> None:
        self.tree.consts["NOTED_B_LATE"] = "noted_b_late"
        root = self.tree.write()
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = flags.main(["--check", "--root", str(root)])
        self.assertEqual(code, 1)
        self.assertIn("STORY_FLAGS=failure", out.getvalue())


if __name__ == "__main__":
    unittest.main(verbosity=2)
