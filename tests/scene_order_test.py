#!/usr/bin/env python3
"""Both directions for `tools/check_scene_order.py` (issue #291).

- a child after its parent passes; a child before its parent fails, with both lines named;
- nested paths (`Interactables/Door`) are resolved the same way;
- a parent never declared in the file (a node inside an instanced sub-scene) is not reported;
- the command returns 1 on a bad tree and 0 on this repository.

Run with `python3 tests/scene_order_test.py`; no engine and no network.
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import check_scene_order as order  # noqa: E402

HEAD = '[gd_scene format=3]\n\n[node name="Room" type="Node3D"]\n\n'


class SceneOrderTest(unittest.TestCase):
    def test_child_after_parent_passes(self) -> None:
        text = HEAD + '[node name="Interactables" type="Node3D" parent="."]\n\n[node name="StudentTalk" parent="Interactables" instance=ExtResource("1")]\n'
        self.assertEqual(order.audit_text(text, "room.tscn"), [])

    def test_child_before_parent_fails(self) -> None:
        text = HEAD + '[node name="StudentTalk" parent="Interactables" instance=ExtResource("1")]\n\n[node name="Interactables" type="Node3D" parent="."]\n'
        problems = order.audit_text(text, "room.tscn")
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("'Interactables/StudentTalk' is declared before its parent 'Interactables'", problems[0])
        self.assertIn("room.tscn:5", problems[0])
        self.assertIn("line 7", problems[0])

    def test_nested_paths(self) -> None:
        text = HEAD + (
            '[node name="A" type="Node3D" parent="."]\n'
            '[node name="C" type="Node3D" parent="A/B"]\n'
            '[node name="B" type="Node3D" parent="A"]\n'
        )
        self.assertEqual(len(order.audit_text(text, "room.tscn")), 1)

    def test_parent_inside_an_instance_is_not_reported(self) -> None:
        text = HEAD + '[node name="Door" parent="." instance=ExtResource("2")]\n[node name="Glow" type="OmniLight3D" parent="Door/Frame"]\n'
        self.assertEqual(order.audit_text(text, "room.tscn"), [])

    def test_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad.tscn"
            bad.write_text(HEAD + '[node name="X" type="Node3D" parent="Late"]\n[node name="Late" type="Node3D" parent="."]\n')
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(order.main(["--check", "--root", tmp]), 1)
            self.assertIn("SCENE_ORDER=failure", out.getvalue())
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(order.main(["--check"]), 0, out.getvalue())


if __name__ == "__main__":
    unittest.main(verbosity=2)
