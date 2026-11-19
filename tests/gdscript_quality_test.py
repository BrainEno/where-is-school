#!/usr/bin/env python3
"""Exercise the real gdlint rules and Git delta, without a Godot import cache."""

from __future__ import annotations

import contextlib
import io
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import check_gdscript_quality as quality

SCRIPT = "scripts/sample.gd"
GOOD = "extends Node\n\nfunc describe_state() -> String:\n\treturn \"good\"\n"
BAD = GOOD.replace("describe_state", "describeState")
LOAD_A = 'const A = preload("res://something.gd")\n'
LOAD_B = 'const B = preload("res://something.gd")\n'
LOAD_C = 'const C = preload("res://something.gd")\n'


def long_script(lines: int) -> str:
    return GOOD + "# Existing responsibility.\n" * (lines - len(GOOD.splitlines()))


class QualityTest(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory(prefix="gdscript_quality_")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.git("init", "--quiet")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Quality test fixture")
        shutil.copyfile(ROOT / "gdlintrc", self.root / "gdlintrc")

    def git(self, *args: str) -> str:
        result = subprocess.run(
            ["git", "-C", str(self.root), *args], capture_output=True, text=True, check=True
        )
        return result.stdout.strip()

    def write(self, path: str, text: str) -> None:
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def commit(self, message: str = "fixture base") -> str:
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", message)
        return self.git("rev-parse", "HEAD")

    def invoke(self, *args: str) -> tuple[int, str, str]:
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            code = quality.main(["--root", str(self.root), *args])
        return code, output.getvalue(), errors.getvalue()

    def test_clean_worktree_delta_does_not_lint_unstaged_new_files(self) -> None:
        base = self.commit()
        self.write(SCRIPT, BAD)
        self.write("tests/not_production.gd", BAD)
        self.git("add", "tests/not_production.gd")
        report = quality.audit(self.root, base)
        self.assertEqual(report.files, 0)
        self.assertEqual(report.findings, [])
        self.git("add", SCRIPT)
        code, output, errors = self.invoke("--base", base)
        self.assertEqual((code, errors), (1, ""))
        self.assertIn(f"{SCRIPT}:3:6: function-name:", output)
        self.assertNotIn("tests/not_production.gd", output)

    def test_existing_issues_are_not_charged_again_after_lines_move(self) -> None:
        self.write(SCRIPT, BAD + LOAD_A + LOAD_B)
        base = self.commit()
        self.write(SCRIPT, "## Added context\n\n" + BAD + LOAD_B + LOAD_A)
        report = quality.audit(self.root, base)
        self.assertEqual(report.files, 1)
        self.assertEqual(report.findings, [])
        self.write(SCRIPT, GOOD + LOAD_A + LOAD_B + LOAD_C)
        # Fixing one kind of problem cannot buy an allowance for a different rule.
        report = quality.audit(self.root, base)
        self.assertEqual([item.rule for item in report.findings], ["duplicated-load"])
        self.assertIn("res://something.gd", report.findings[0].detail)

    def test_replacing_invalid_name_with_another_is_new_debt(self) -> None:
        self.write(SCRIPT, BAD)
        base = self.commit()
        self.write(SCRIPT, BAD.replace("describeState", "summarizeState"))
        names = [item.detail for item in quality.audit(self.root, base).findings]
        self.assertEqual(len(names), 1)
        self.assertIn("summarizeState", names[0])

    def test_naming_rules_keep_their_own_allowance(self) -> None:
        base = self.commit()
        self.write(SCRIPT, "class_name not_upper_camel\nextends Node\n"
                   "signal WidgetReadied\nconst mixedCase = 1\n"
                   "func _ready() -> void:\n\tvar readyCount = 0\n\tprint(readyCount)\n")
        self.git("add", SCRIPT)
        findings = quality.audit(self.root, base).findings
        self.assertEqual({finding.rule for finding in findings}, {
            "class-name", "signal-name", "constant-name", "function-variable-name",
        })
        self.assertTrue(all(finding.line > 0 and finding.column > 0 for finding in findings))

    def test_new_file_size_has_exact_boundary(self) -> None:
        base = self.commit()
        self.write(SCRIPT, long_script(600))
        self.git("add", SCRIPT)
        self.assertEqual(quality.audit(self.root, base).findings, [])
        self.write(SCRIPT, long_script(601))
        finding, = quality.audit(self.root, base).findings
        self.assertEqual((finding.path, finding.line, finding.rule), (SCRIPT, 601, "max-file-lines"))
        self.assertIn("601 lines (base 0, limit 600)", finding.detail)

    def test_existing_large_file_can_shrink_and_growth_is_reported(self) -> None:
        self.write(SCRIPT, long_script(650))
        base = self.commit()
        for lines in (650, 620, 600, 599):
            with self.subTest(lines=lines):
                self.write(SCRIPT, long_script(lines).replace('return "good"', 'return "edited"'))
                self.assertEqual(quality.audit(self.root, base).findings, [])
        self.write(SCRIPT, long_script(651))
        finding, = quality.audit(self.root, base).findings
        self.assertIn("651 lines (base 650, limit 600)", finding.detail)
        self.assertEqual(finding.rule, "max-file-lines")
        self.assertTrue(finding.advisory)
        code, output, errors = self.invoke("--base", base)
        self.assertEqual((code, errors), (0, ""))
        self.assertIn("GDSCRIPT_QUALITY_WARNING:", output)
        self.assertNotIn("GDSCRIPT_QUALITY_FAILURE:", output)

    def test_refactoring_under_the_ceiling_retires_the_allowance(self) -> None:
        self.write(SCRIPT, long_script(645))
        before = self.commit()
        self.write(SCRIPT, long_script(599))
        reduced = self.commit("split the script below the limit")
        self.write(SCRIPT, long_script(601))
        self.assertEqual(quality.audit(self.root, before).findings, [])
        finding, = quality.audit(self.root, reduced).findings
        self.assertIn("base 599", finding.detail)
        self.assertFalse(finding.advisory)

    def test_rename_keeps_debt_but_copy_does_not(self) -> None:
        self.write(SCRIPT, long_script(630) + LOAD_A + LOAD_B)
        base = self.commit()
        renamed = "scenes/location with a space.gd"
        (self.root / "scenes").mkdir()
        self.git("mv", SCRIPT, renamed)
        self.assertEqual(quality.changed_scripts(self.root, base), [quality.ScriptChange(renamed, SCRIPT)])
        self.assertEqual(quality.audit(self.root, base).findings, [])
        self.commit("move script")
        copy = "addons/copy.gd"
        self.write(copy, (self.root / renamed).read_text(encoding="utf-8"))
        self.git("add", copy)
        results = quality.audit(self.root, base).findings
        # Git can choose either identical path as the rename. Exactly the second
        # copy must pay for both the size and duplicate load, whatever path it chose.
        self.assertEqual(sorted(item.rule for item in results), ["duplicated-load", "max-file-lines"])
        self.assertEqual(len({item.path for item in results}), 1)

    def test_move_into_runtime_cannot_import_an_out_of_scope_allowance(self) -> None:
        self.write("tests/temporary.gd", BAD)
        base = self.commit()
        (self.root / "scripts").mkdir()
        self.git("mv", "tests/temporary.gd", SCRIPT)
        finding, = quality.audit(self.root, base).findings
        self.assertEqual((finding.path, finding.rule), (SCRIPT, "function-name"))

    def test_deleting_a_file_leaves_no_exception_to_maintain(self) -> None:
        self.write(SCRIPT, BAD)
        base = self.commit()
        self.git("rm", "--quiet", SCRIPT)
        self.assertEqual(quality.audit(self.root, base).files, 0)
        self.assertEqual(quality.audit(self.root, None).findings, [])

    def test_source_directive_cannot_hide_a_finding(self) -> None:
        base = self.commit()
        for directive in ("# gdlint: disable=function-name", "# gdlint: ignore=function-name"):
            with self.subTest(directive=directive):
                self.write(SCRIPT, BAD.replace("func", directive + "\nfunc", 1))
                self.git("add", SCRIPT)
                self.assertEqual([item.rule for item in quality.audit(self.root, base).findings],
                                 ["function-name"])

    def test_non_scope_style_rules_are_not_accidentally_enabled(self) -> None:
        base = self.commit()
        self.write(SCRIPT, "extends Node\nfunc format_value(data: String) -> String:\n"
                   "\treturn \"" + "a" * 140 + "\"\n")
        self.git("add", SCRIPT)
        self.assertEqual(quality.audit(self.root, base).findings, [])

    def test_inventory_shows_debt_without_enforcing_it(self) -> None:
        self.write(SCRIPT, BAD)
        base = self.commit()
        code, output, errors = self.invoke("--inventory")
        self.assertEqual((code, errors), (0, ""))
        self.assertIn("function-name", output)
        self.assertIn("1 finding(s) in 1 tracked scripts", output)
        self.assertEqual(self.invoke("--base", base),
                         (0, "GDSCRIPT_QUALITY_OK: no blocking findings across 0 changed scripts\n", ""))

    def test_invalid_base_and_invalid_source_cannot_pass(self) -> None:
        base = self.commit()
        code, output, errors = self.invoke("--base", "refs/heads/absent")
        self.assertEqual((code, output), (2, ""))
        self.assertIn("git rev-parse failed", errors)
        self.write(SCRIPT, "extends Node\nfunc broken(:\n")
        self.git("add", SCRIPT)
        code, output, errors = self.invoke("--base", base)
        self.assertEqual((code, output), (2, ""))
        self.assertIn(f"{SCRIPT}:2:", errors)
        self.assertIn("cannot parse GDScript", errors)

    def test_bad_policy_and_unsafe_yaml_are_rejected(self) -> None:
        base = self.commit()
        for invalid in ("max-file-lines: true", "max-file-lines: 0", "fiel-lines: 600",
                        "disable: [max-file-lines]", "disable: [unknown-rule]",
                        "function-name: '['", "!!python/object/apply:builtins.print ['should never execute']"):
            with self.subTest(invalid=invalid):
                self.write("gdlintrc", invalid + "\n")
                code, output, errors = self.invoke("--base", base)
                self.assertEqual((code, output), (2, ""))
                self.assertIn("gdlintrc", errors)

    def test_wrong_worktree_root_is_not_a_zero_script_pass(self) -> None:
        self.write(SCRIPT, BAD)
        base = self.commit()
        code, output, errors = self.invoke("--root", str(self.root / "scripts"), "--base", base)
        self.assertEqual((code, output), (2, ""))
        self.assertIn("top of the Git worktree", errors)

    def test_unmerged_script_cannot_be_omitted_from_the_delta(self) -> None:
        self.write(SCRIPT, GOOD)
        base = self.commit()
        blob = self.git("rev-parse", f"HEAD:{SCRIPT}")
        entries = f"0 {'0' * len(blob)}\t{SCRIPT}\n100644 {blob} 2\t{SCRIPT}\n"
        subprocess.run(["git", "-C", str(self.root), "update-index", "--index-info"],
                       input=entries, check=True, text=True, capture_output=True)
        self.assertIn(SCRIPT, self.git("ls-files", "--unmerged"))
        code, output, errors = self.invoke("--base", base)
        self.assertEqual((code, output), (2, ""))
        self.assertIn("Resolve unmerged GDScript", errors)

    def test_symlink_is_not_used_as_source(self) -> None:
        self.write(SCRIPT, GOOD)
        self.write("other.gd", BAD)
        base = self.commit()
        path = self.root / SCRIPT
        path.unlink()
        path.symlink_to("../other.gd")
        code, output, errors = self.invoke("--base", base)
        self.assertEqual((code, output), (2, ""))
        self.assertIn("expected a regular tracked file", errors)


if __name__ == "__main__":
    unittest.main()
