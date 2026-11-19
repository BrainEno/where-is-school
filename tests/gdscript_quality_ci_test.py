#!/usr/bin/env python3
"""Run the actual Test tooling gate against local shallow checkouts.

The fixtures use a file:// Git remote. No network, runtime assets or engine
installation is needed to prove that a PR cannot pass by comparing with itself.
"""

from __future__ import annotations

import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CHECK = "Gate new GDScript quality debt"
SCRIPT = "scripts/fixture.gd"
GOOD = "extends Node\nfunc leave_room() -> void:\n\tprint(\"ready\")\n"
BAD = GOOD.replace("leave_room", "leaveRoom")


def run(root: Path, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=root, env=env, capture_output=True, text=True, timeout=30)


def git(root: Path, *args: str) -> str:
    result = run(root, "git", *args)
    result.check_returncode()
    return result.stdout.strip()


class QualityCITest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        workflow = yaml.safe_load((ROOT / ".github/workflows/test-tooling.yml").read_text(encoding="utf-8"))
        cls.step, = [step for step in workflow["jobs"]["tooling"]["steps"] if step.get("name") == CHECK]

    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory(prefix="quality_ci_")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name) / "upstream"
        self.root.mkdir()
        git(self.root, "init", "--quiet")
        git(self.root, "config", "user.email", "test@example.invalid")
        git(self.root, "config", "user.name", "Quality CI fixture")
        shutil.copyfile(ROOT / "gdlintrc", self.root / "gdlintrc")
        (self.root / "tools").mkdir()
        shutil.copyfile(ROOT / "tools/check_gdscript_quality.py", self.root / "tools/check_gdscript_quality.py")
        self.write_script(GOOD)
        self.base = self.commit("base")

    def write_script(self, text: str) -> None:
        path = self.root / SCRIPT
        path.parent.mkdir(exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def commit(self, message: str) -> str:
        git(self.root, "add", "--all")
        git(self.root, "commit", "--quiet", "-m", message)
        return git(self.root, "rev-parse", "HEAD")

    def shallow_checkout(self) -> Path:
        work = self.root.parent / "checkout"
        git(self.root.parent, "clone", "--quiet", "--no-tags", "--depth=1", self.root.as_uri(), str(work))
        self.assertEqual(git(work, "rev-parse", "--is-shallow-repository"), "true")
        self.assertEqual(git(work, "rev-list", "--count", "HEAD"), "1")
        self.assertNotEqual(run(work, "git", "cat-file", "-e", self.base).returncode, 0)
        # Simulate only the venv executable installed by the preceding Actions step.
        shim = work / ".venv/bin/python"
        shim.parent.mkdir(parents=True)
        shim.write_text(f"#!/usr/bin/env bash\nexec {shlex.quote(sys.executable)} \"$@\"\n", encoding="utf-8")
        shim.chmod(0o755)
        return work

    def invoke(self, work: Path, event: str, base: str) -> subprocess.CompletedProcess[str]:
        env = {**os.environ, "GITHUB_EVENT_NAME": event, "QUALITY_BASE": base}
        return run(work, "bash", "-c", self.step["run"], env=env)

    def test_pr_entry_fetches_exact_base_and_fails_on_three_new_rules(self) -> None:
        self.assertIn("github.event.pull_request.base.sha", self.step["env"]["QUALITY_BASE"])
        self.write_script(BAD + 'const A = preload("res://fixture.gd")\n'
                          'const B = preload("res://fixture.gd")\n' + "# over limit\n" * 600)
        self.commit("deliberate violations")
        work = self.shallow_checkout()
        result = self.invoke(work, "pull_request", self.base)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("3 new finding(s) across 1 checked scripts", result.stdout)
        for rule in ("function-name", "duplicated-load", "max-file-lines"):
            with self.subTest(rule=rule):
                self.assertIn(rule, result.stdout)
        self.assertEqual(git(work, "cat-file", "-t", self.base), "commit")
        self.assertEqual(git(work, "rev-list", "--count", "HEAD"), "1")

    def test_push_without_remote_still_uses_already_present_base(self) -> None:
        self.assertIn("github.event.before", self.step["env"]["QUALITY_BASE"])
        self.write_script(GOOD.replace('"ready"', '"done"'))
        self.commit("legitimate change")
        work = self.shallow_checkout()
        git(work, "fetch", "--quiet", "--no-tags", "--depth=1", "origin", self.base)
        git(work, "remote", "remove", "origin")
        result = self.invoke(work, "push", self.base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("no blocking findings across 1 changed scripts", result.stdout)

    def test_legacy_growth_warns_without_blocking_parallel_maintenance(self) -> None:
        large = GOOD + "# Existing size debt.\n" * 610
        self.write_script(large)
        self.base = self.commit("oversized existing file")
        self.write_script(large + "# A maintenance change.\n")
        self.commit("parallel maintenance")
        work = self.shallow_checkout()
        result = self.invoke(work, "pull_request", self.base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("GDSCRIPT_QUALITY_WARNING:", result.stdout)
        self.assertIn("max-file-lines: 614 lines (base 613, limit 600)", result.stdout)
        # The advisory applies only to size; it cannot mask a new naming issue.
        (work / SCRIPT).write_text(large.replace("leave_room", "leaveRoom") + "# Added.\n", encoding="utf-8")
        result = self.invoke(work, "pull_request", self.base)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("GDSCRIPT_QUALITY_WARNING:", result.stdout)
        self.assertIn("function-name:", result.stdout)
        self.assertIn("1 new finding(s)", result.stdout)

    def test_broken_event_wiring_is_not_an_inventory_pass(self) -> None:
        self.write_script(BAD)
        self.commit("violation")
        work = self.shallow_checkout()
        for invalid in ("", "0" * 40, "HEAD^", "not-a-commit"):
            with self.subTest(invalid=invalid):
                result = self.invoke(work, "pull_request", invalid)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn("actual GDScript quality comparison base", result.stderr)
                self.assertNotIn("INVENTORY", result.stdout)
        missing = self.invoke(work, "pull_request", "f" * 40)
        self.assertNotEqual(missing.returncode, 0)
        self.assertNotIn("GDSCRIPT_QUALITY_OK", missing.stdout)

    def test_manual_dispatch_reports_legacy_without_claiming_an_incremental_pass(self) -> None:
        self.write_script(BAD)
        self.commit("legacy issue")
        work = self.shallow_checkout()
        git(work, "remote", "remove", "origin")
        result = self.invoke(work, "workflow_dispatch", "")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("GDSCRIPT_QUALITY_INVENTORY: 1 finding(s)", result.stdout)
        self.assertIn("function-name", result.stdout)
        self.assertNotIn("GDSCRIPT_QUALITY_OK", result.stdout)


if __name__ == "__main__":
    unittest.main()
