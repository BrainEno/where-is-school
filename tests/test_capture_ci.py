#!/usr/bin/env python3
"""Exercise the real capture wrapper without touching tracked screenshot evidence.

Default tests use deterministic stand-ins for Godot/Xvfb; --real-failures also
uses the installed Godot to provoke an actual bad import and a failing script.
The workflow's separate normal step runs the real graphical capture.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts/ci/run_playthrough_capture.sh"
REAL_FAILURES = "--real-failures" in sys.argv
if REAL_FAILURES:
    sys.argv.remove("--real-failures")

FAKE_GODOT = r'''#!/usr/bin/env bash
set -eu
if [[ " $* " == *" --editor "* ]]; then
  echo "simulated import"
  if [[ ${MODE} == import_fail ]]; then echo "deliberate import failure"; exit 31; fi
  if [[ ${MODE} == import_error_zero ]]; then echo "SCRIPT ERROR: deliberate import parse error"; fi
  exit 0
fi
mkdir -p "$CAPTURE_DIR"
printf partial > "$CAPTURE_DIR/partial.png"
if [[ ${MODE} == capture_fail ]]; then echo "deliberate capture failure"; exit 32; fi
for frame in 01_opening_line 04_prompt_schoolbag 05_inspection_text 06_chinese_world \
  10_conversation_chinese 13_corridor 14_street 17_residential 19_animal_conversation 20_estate_exit 21_playground 22_active_choices \
  23_active_result 24_active_choices_chinese 20_end_card; do
  if [[ ${MODE} == incomplete && $frame == 20_end_card ]]; then continue; fi
  printf simulated-frame > "$CAPTURE_DIR/$frame.png"
done
printf 'RESULT: fixture\n' > "$CAPTURE_DIR/PLAYTHROUGH.log"
printf '# fixture\n' > "$CAPTURE_DIR/PLAYTHROUGH.md"
if [[ ${MODE} == capture_error_zero ]]; then echo 'ERROR: deliberate capture error'; fi
if [[ ${MODE} != missing_marker ]]; then echo 'CAPTURE_RESULT: PASS'; fi
'''
FAKE_XVFB = r'''#!/usr/bin/env bash
shift 2
exec "$@"
'''


class CapturePipelineTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="capture-ci-test-")
        self.dir = Path(self.tmp.name)
        self.evidence = self.dir / "evidence"
        self.godot = self._write_exec("fake-godot", FAKE_GODOT)
        self.xvfb = self._write_exec("fake-xvfb", FAKE_XVFB)
        self.prior = self.dir / "existing-success.png"
        self.prior.write_bytes(b"prior reviewed evidence")

    def tearDown(self):
        self.tmp.cleanup()

    def _write_exec(self, name, text):
        path = self.dir / name
        path.write_text(text)
        path.chmod(0o755)
        return path

    def run_pipeline(self, mode, godot=None, xvfb=None):
        env = os.environ.copy()
        env.update(CAPTURE_PROJECT_DIR=str(ROOT), CAPTURE_EVIDENCE_DIR=str(self.evidence),
                   GODOT_BIN=str(godot or self.godot), XVFB_RUN_BIN=str(xvfb or self.xvfb),
                   MODE=mode, IMPORT_TIMEOUT="120", CAPTURE_TIMEOUT="120")
        process = subprocess.run([str(RUNNER)], env=env, text=True, capture_output=True, timeout=150)
        status = json.loads((self.evidence / "status.json").read_text())
        self.assertEqual(self.prior.read_bytes(), b"prior reviewed evidence")
        self.assertTrue((self.evidence / "import.log").exists())
        self.assertTrue((self.evidence / "capture.log").exists())
        return process, status

    def test_simulated_complete_success(self):
        process, status = self.run_pipeline("success")
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertEqual((status["result"], status["import"], status["capture"]),
                         ("success", "success", "success"))
        self.assertIn("PLAYTHROUGH_RESULT=SUCCESS", process.stdout)

    def test_deliberate_import_failure(self):
        process, status = self.run_pipeline("import_fail")
        self.assertNotEqual(process.returncode, 0)
        self.assertEqual((status["result"], status["import"], status["capture"]),
                         ("failure", "failure", "not_run"))
        self.assertIn("deliberate import failure", (self.evidence / "import.log").read_text())

    def test_deliberate_capture_failure_keeps_partial_frame(self):
        process, status = self.run_pipeline("capture_fail")
        self.assertNotEqual(process.returncode, 0)
        self.assertEqual((status["result"], status["import"], status["capture"]),
                         ("failure", "success", "failure"))
        self.assertEqual((self.evidence / "frames/partial.png").read_bytes(), b"partial")
        self.assertIn("deliberate capture failure", (self.evidence / "capture.log").read_text())

    def test_incomplete_or_unmarked_output_fails_even_with_zero_exit(self):
        for mode in ("incomplete", "missing_marker"):
            with self.subTest(mode=mode):
                self.evidence = self.dir / mode
                process, status = self.run_pipeline(mode)
                self.assertNotEqual(process.returncode, 0)
                self.assertEqual((status["result"], status["stage"]), ("failure", "incomplete"))
                self.assertTrue((self.evidence / "frames/partial.png").exists())

    def test_logged_errors_with_zero_exit_are_failures(self):
        for mode, stage in (("import_error_zero", "import"), ("capture_error_zero", "capture")):
            with self.subTest(mode=mode):
                self.evidence = self.dir / mode
                process, status = self.run_pipeline(mode)
                self.assertNotEqual(process.returncode, 0)
                self.assertEqual((status["result"], status["stage"]), ("failure", stage))

    def test_existing_evidence_not_overwritten(self):
        (self.evidence / "frames").mkdir(parents=True)
        prior = self.evidence / "frames/existing.png"
        prior.write_bytes(b"do not replace")
        env = os.environ.copy()
        env.update(CAPTURE_EVIDENCE_DIR=str(self.evidence), GODOT_BIN=str(self.godot),
                   XVFB_RUN_BIN=str(self.xvfb), MODE="success")
        result = subprocess.run([str(RUNNER)], env=env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(prior.read_bytes(), b"do not replace")

    @unittest.skipUnless(REAL_FAILURES, "requires the real Godot executable")
    def test_real_godot_deliberate_import_and_capture_failures(self):
        godot = shutil.which("godot")
        self.assertIsNotNone(godot, "--real-failures requires godot on PATH")
        broken = self.dir / "fail_capture.gd"
        broken.write_text('extends SceneTree\nfunc _initialize():\n\tprint("DELIBERATE_CAPTURE_FAILURE")\n\tquit(37)\n')
        # This wrapper calls the real engine but points import at a missing
        # project, or replaces capture with a tiny real script that exits 37.
        wrapper = self._write_exec("real-godot-fail", f'''#!/usr/bin/env bash
if [[ " $* " == *" --editor "* ]]; then
  if [[ $MODE == real_import_fail ]]; then
    exec "{godot}" --headless --editor --path "{self.dir}/missing-project" --quit
  fi
  exec "{godot}" "$@"
fi
exec "{godot}" --headless --path "{ROOT}" --script "{broken}"
''')
        process, status = self.run_pipeline("real_import_fail", wrapper)
        self.assertNotEqual(process.returncode, 0)
        self.assertEqual((status["import"], status["capture"]), ("failure", "not_run"))
        self.evidence = self.dir / "real-capture-evidence"
        process, status = self.run_pipeline("real_capture_fail", wrapper)
        self.assertNotEqual(process.returncode, 0, process.stdout + process.stderr)
        import_log = (self.evidence / "import.log").read_text()
        error_lines = "\n".join(line for line in import_log.splitlines()
                                if any(token in line for token in ("ERROR", "Parse Error", "SCRIPT ERROR")))
        self.assertEqual((status["import"], status["capture"]), ("success", "failure"),
                         f"Real import status: {status}; error lines: {error_lines[-2500:]}")
        self.assertIn("DELIBERATE_CAPTURE_FAILURE", (self.evidence / "capture.log").read_text())
        self.assertEqual(status["capture_exit"], 37)


if __name__ == "__main__":
    unittest.main(verbosity=2)
