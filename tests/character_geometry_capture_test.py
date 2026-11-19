#!/usr/bin/env python3
"""Test capture orchestration/cache restoration with explicitly synthetic fixtures.

These fixture PNGs never render a character and are NOT game or Godot evidence. Real
rendering remains the separate Xvfb workflow on its exact code head.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MODELS = {"n": "assets/models/teacher-n/teacher-n.glb",
          "student": "assets/models/protagonist/protagonist.glb"}


def write(path: Path, text: str, executable: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    if executable:
        path.chmod(0o755)


class GeometryCaptureOrchestrationTest(unittest.TestCase):
    def fixture(self, folder: Path, fail: str = "") -> subprocess.CompletedProcess:
        baseline = folder / "baseline"
        shots = folder / "docs/screenshots/character_integration"
        shots.mkdir(parents=True, exist_ok=True)
        for variant in ("baseline", "after"):
            Image.new("RGB", (40, 40), "red").save(shots / f"n_stale__{variant}.png")
        for label, relative in MODELS.items():
            write(folder / relative, "fixture-head-" + label)
            write(folder / (relative + ".import"), f'path="res://.godot/imported/{label}.scn"\n')
            write(baseline / (label + ".glb"), "fixture-base-" + label)
            write(baseline / (label + ".tres"), "fixture-base-look-" + label)
        write(folder / "assets/characters/teacher_n/teacher_n_look.tres", "fixture-head-look-n")
        write(folder / "assets/characters/classroom_student/student_look.tres", "fixture-head-look-student")
        # The exact values identify synthetic test revisions, never a real evidence run.
        write(baseline / "base-sha.txt", "fixture-base-revision\n")
        tools = folder / "bin"
        write(tools / "git", '#!/bin/sh\nprintf "%s\\n" "fixture-head-revision"\n', True)
        write(tools / "xvfb-run", '#!/bin/sh\nwhile [ "${1#-}" != "$1" ]; do shift; done\nexec "$@"\n', True)
        write(tools / "fixture-engine", f"#!{sys.executable}\n" + r'''
# Intentionally synthetic: checks file/process sequencing, not glTF or rendering.
import os, sys
from pathlib import Path
from PIL import Image
if '--version' in sys.argv:
    print('fixture-not-godot')
    raise SystemExit(0)
base = Path('assets/models/teacher-n/teacher-n.glb').read_text().startswith('fixture-base')
if '--import' in sys.argv:
    if base and os.environ.get('FIXTURE_FAIL') == 'baseline-import':
        print('ERROR: synthetic baseline import failure')
        raise SystemExit(6)
    for label, path in [('n', 'assets/models/teacher-n/teacher-n.glb'),
                        ('student', 'assets/models/protagonist/protagonist.glb')]:
        for suffix in ['scn', 'md5']:
            target = Path(f'.godot/imported/{label}.{suffix}')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('fixture-cache-' + Path(path).read_text())
    raise SystemExit(0)
variant = next(a.split('=', 1)[1] for a in sys.argv if a.startswith('--variants='))
group = next(a.split('=', 1)[1] for a in sys.argv if a.startswith('--group='))
if variant == 'baseline' and os.environ.get('FIXTURE_FAIL') == 'baseline-capture':
    print('ARTNOTE: RESULT: FAILURE')
    raise SystemExit(7)
folder = Path('docs/screenshots/character_integration')
folder.mkdir(parents=True, exist_ok=True)
for kind in ['face', 'hands']:
    # Large flat colours make pixel order testable; these are not character screenshots.
    image = Image.new('RGB', (40, 40), '#336699' if base else '#bb7733')
    image.save(folder / f'{group}_{kind}__{variant}.png')
    print(f'ARTSHEET: {group}_{kind}__{variant}.jpg synthetic-fixture-not-evidence')
(folder / f'CHARACTER_INTEGRATION_{group}.log').write_text('synthetic fixture only\n')
print('ARTNOTE: RESULT: SUCCESS')
''', True)
        env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                   GODOT_BIN=str(tools / "fixture-engine"), EVIDENCE_PYTHON=sys.executable,
                   FIXTURE_FAIL=fail)
        return subprocess.run(["bash", str(ROOT / "tools/capture_character_geometry.sh"),
                               "n", "face,hands", str(baseline)], cwd=folder, env=env,
                              text=True, capture_output=True, timeout=30)

    def assert_restored(self, folder: Path) -> None:
        for label, relative in MODELS.items():
            self.assertEqual((folder / relative).read_text(), "fixture-head-" + label)
            for suffix in ("scn", "md5"):
                self.assertEqual((folder / f".godot/imported/{label}.{suffix}").read_text(),
                                 "fixture-cache-fixture-head-" + label)
            self.assertEqual((folder / (relative + ".import")).read_text(),
                             f'path="res://.godot/imported/{label}.scn"\n')

    def test_actual_base_inputs_and_panel_order_are_recorded_and_head_cache_restored(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            result = self.fixture(folder)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assert_restored(folder)
            shots = folder / "docs/screenshots/character_integration"
            manifest = json.loads((shots / "geometry_comparison_n.json").read_text())
            self.assertTrue(manifest["status"].startswith("complete;"))
            self.assertEqual(len(manifest["rendered_sheets"]), 2)
            for label in MODELS:
                entry = manifest["models"][label]
                self.assertEqual(entry["baseline_sha256"], hashlib.sha256(("fixture-base-" + label).encode()).hexdigest())
                self.assertEqual(entry["head_sha256"], hashlib.sha256(("fixture-head-" + label).encode()).hexdigest())
            with Image.open(shots / "n_hands__geometry_base_after.png") as image:
                self.assertEqual(image.getpixel((20, 40)), (0x33, 0x66, 0x99))
                self.assertEqual(image.getpixel((64, 40)), (0xbb, 0x77, 0x33))
            log = (folder / "capture.log").read_text()
            self.assertEqual(log.count("ARTSHEET: "), 2)

    def test_failed_baseline_import_does_not_report_a_comparison_or_leave_old_meshes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            result = self.fixture(folder, "baseline-import")
            self.assertNotEqual(result.returncode, 0)
            self.assert_restored(folder)
            self.assertNotIn("ARTSHEET: ", (folder / "capture.log").read_text())

    def test_failed_baseline_capture_restores_head_bytes_and_import_cache(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            result = self.fixture(folder, "baseline-capture")
            self.assertNotEqual(result.returncode, 0)
            self.assert_restored(folder)
            self.assertNotIn("ARTSHEET: ", (folder / "capture.log").read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
