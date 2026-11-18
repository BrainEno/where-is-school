#!/usr/bin/env python3
"""Positive and negative fixtures for the #216 registration gate; no Godot needed."""

from __future__ import annotations

import contextlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import check_test_registration as registration

ENTRY = "extends SceneTree\nfunc _initialize() -> void:\n\tprint(\"PASS: fixture\")\n\tquit(0)\n"
CALL = "godot --headless --path . --script res://tests/alpha_test.gd"


def workflow(command: str) -> str:
    return ("name: Fixture\non: [pull_request]\njobs:\n  check:\n    runs-on: ubuntu-latest\n"
            "    steps:\n      - run: |\n" + "".join("          " + line + "\n"
                                                               for line in command.splitlines()))


class RegistrationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.write("tests/alpha_test.gd", ENTRY)
        self.write(registration.LEGACY_EXPECT, "# No old _expect helpers in this fixture.\n")
        self.write(".github/workflows/check.yml", workflow(CALL))

    def write(self, relative: str, text: str) -> None:
        target = self.root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def audit(self, command: str | None = None) -> registration.Audit:
        if command is not None:
            self.write(".github/workflows/check.yml", workflow(command))
        return registration.check(self.root)

    def test_direct_and_wrapper_invocations(self) -> None:
        for command in (
            CALL, CALL.replace("--script ", "--script="), CALL.replace("--script", "-s"),
            "run_check alpha 60 " + CALL, "measured alpha " + CALL,
            "timeout --signal TERM --kill-after 2s 60s " + CALL,
            "timeout 60 xvfb-run -a --server-args='-screen 0 1600x900x24' " + CALL,
            "env -u DISPLAY FOO=yes " + CALL,
            'xvfb-run -a env "${extra[@]}" FOO=yes ' + CALL,
            "FOO=yes command " + CALL,
            CALL.replace("godot", '"${GODOT_BIN}"', 1),
            CALL.replace("--script ", "--script \\\n  "),
            "true && " + CALL + " || status=1",
            CALL + " -- --check-only",  # a test argument, not an engine option
        ):
            with self.subTest(command=command):
                audit = self.audit(command)
                self.assertEqual(audit.errors, [])
                self.assertIn("tests/alpha_test.gd", audit.registrations)

    def test_comments_filters_echo_and_compile_only_do_not_register(self) -> None:
        for command in (
            "# " + CALL, "echo '" + CALL + "'", "echo " + CALL,
            "timeout 60 echo " + CALL, "env FOO=1 echo " + CALL,
            CALL.replace("--script", "--check-only --script"),
            "python3 - <<'PY'\n" + CALL + "\nPY\necho finished",
            "cat <<-EOF\n" + CALL + "\nEOF\necho finished",
            'EXAMPLE="line one\n' + CALL + '\nline three"',
            'echo "example\n' + CALL + '\nnot a command"',
            "bash -c '" + CALL + "'",   # deliberately unsupported indirection
        ):
            with self.subTest(command=command):
                audit = self.audit(command)
                self.assertNotIn("tests/alpha_test.gd", audit.registrations)
                self.assertTrue(any("no literal Godot" in error for error in audit.errors))
        self.write(".github/workflows/check.yml", workflow("echo finished") +
                   "    env:\n      EXAMPLE: '" + CALL + "'\n")
        self.assertTrue(self.audit().errors)

    def test_heredoc_then_real_command(self) -> None:
        audit = self.audit("cat <<'EOF'\ngodot --script res://tests/phantom_test.gd\nEOF\n" + CALL)
        self.assertEqual(audit.errors, [])
        self.assertEqual(set(audit.registrations), {"tests/alpha_test.gd"})

    def test_reachable_repository_shell_scripts(self) -> None:
        self.write("tests/first.sh", "bash tests/second.sh\n")
        self.write("tests/second.sh", CALL + "\nsource tests/first.sh\n")  # a cycle must terminate
        self.assertEqual(self.audit("bash -e tests/first.sh").errors, [])
        self.assertEqual(self.audit("./tests/second.sh").errors, [])
        self.assertEqual(self.audit("source tests/second.sh").errors, [])
        self.assertEqual(self.audit("env FOO=1 bash tests/second.sh").errors, [])
        self.assertTrue(self.audit("echo bash tests/second.sh").errors)
        self.assertTrue(self.audit('bash "${DYNAMIC_SCRIPT}"').errors)

    def test_unreachable_shell_file_and_paths_are_not_registration(self) -> None:
        self.write("tests/not_called.sh", CALL + "\n")
        self.write(".github/workflows/check.yml",
                   "on:\n  pull_request:\n    paths: [tests/alpha_test.gd, tests/not_called.sh]\n"
                   "jobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo done\n")
        self.assertTrue(self.audit().errors)

    def test_support_helpers_are_not_standalone_tests(self) -> None:
        self.write("tests/helpers_support.gd", "extends Node\nfunc run() -> void:\n\tpass\n")
        self.assertEqual(self.audit().tests, ["tests/alpha_test.gd"])
        self.assertEqual(self.audit().errors, [])
        self.write("tests/wrong_test.gd", "extends Node\nfunc run() -> void:\n\tpass\n")
        audit = self.audit(CALL + "\ngodot --script res://tests/wrong_test.gd")
        self.assertTrue(any("*_support.gd" in error for error in audit.errors))

    def test_requires_real_toplevel_declarations(self) -> None:
        for text in (
            'extends Node\n# extends SceneTree\nfunc _initialize():\n\tpass\n',
            'extends Node\nvar example = """\nextends SceneTree\nfunc _initialize():\n"""\n',
            'extends SceneTree\n# func _initialize():\n',
            'extends RefCounted\nclass Example:\n\textends SceneTree\n\tfunc _initialize():\n\t\tpass\n',
        ):
            with self.subTest(text=text):
                self.write("tests/alpha_test.gd", text)
                self.assertTrue(any("must extend SceneTree" in error for error in self.audit().errors))
        self.write("tests/alpha_test.gd", ENTRY.replace("_initialize", "_init"))
        self.assertEqual(self.audit().errors, [])
        self.write("tests/alpha_test.gd", "\ufeff" + ENTRY.replace("\n", "\r\n"))
        self.assertEqual(self.audit().errors, [])

    def test_assertion_allowlist_must_not_silently_grow_or_go_stale(self) -> None:
        self.write("tests/alpha_test.gd", ENTRY + "\nfunc _expect(ok: bool):\n\tpass\n")
        self.assertTrue(any("new _expect" in error for error in self.audit().errors))
        self.write(registration.LEGACY_EXPECT, "tests/alpha_test.gd\n")
        self.assertEqual(self.audit().errors, [])
        self.write(registration.LEGACY_EXPECT, "tests/alpha_test.gd\ntests/alpha_test.gd\n")
        self.assertTrue(any("duplicate entry" in error for error in self.audit().errors))
        self.write(registration.LEGACY_EXPECT, "tests/absent_test.gd\n")
        self.assertTrue(any("stale entry" in error for error in self.audit().errors))
        self.write(registration.LEGACY_EXPECT, "")
        for helper in ("static func _expect(ok: bool):\n\tpass\n",
                       "class Local:\n\tfunc _expect(ok: bool):\n\t\tpass\n"):
            self.write("tests/alpha_test.gd", ENTRY + "\n" + helper)
            self.assertTrue(any("new _expect" in error for error in self.audit().errors))
        self.write("tests/alpha_test.gd", ENTRY + '\n# func _expect():\nvar note = "func _expect():"\n')
        self.assertEqual(self.audit().errors, [])

    def test_missing_or_untracked_test_references_fail(self) -> None:
        self.assertTrue(any("stale/untracked" in error for error in
                            self.audit(CALL + "\ngodot --script res://tests/gone_test.gd").errors))
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        self.write("tests/untracked_test.gd", ENTRY)
        audit = self.audit(CALL + "\ngodot --script res://tests/untracked_test.gd")
        self.assertTrue(any("stale/untracked" in error for error in audit.errors))
        self.assertNotIn("tests/untracked_test.gd", audit.tests)

    def test_disabled_job_or_step_does_not_count(self) -> None:
        for replacement in ("  check:\n    if: false", "  check:\n    if: '${{ false }}'"):
            self.write(".github/workflows/check.yml", workflow(CALL).replace("  check:", replacement))
            self.assertTrue(self.audit().errors)
        self.write(".github/workflows/check.yml", workflow(CALL).replace(
            "      - run:", "      - if: false\n        run:"))
        self.assertTrue(self.audit().errors)

    def test_yaml_aliases_and_yaml_extension(self) -> None:
        self.write(".github/workflows/check.yml", "name: Definitions\njobs: {}\n")
        self.write(".github/workflows/other.yaml", "name: Alias\non: [pull_request]\n"
                   "jobs:\n  check:\n    steps:\n      - &test\n        run: '" + CALL + "'\n      - *test\n")
        self.assertEqual(self.audit().errors, [])

    def test_nested_yaml_is_not_an_executable_workflow(self) -> None:
        self.write(".github/workflows/check.yml", workflow("echo no registration"))
        self.write(".github/workflows/examples/unused.yml", workflow(CALL))
        self.assertTrue(any("no literal Godot" in error for error in self.audit().errors))

    def test_missing_files_and_invalid_yaml_fail_closed(self) -> None:
        (self.root / registration.LEGACY_EXPECT).unlink()
        self.assertTrue(any("cannot read allowlist" in error for error in self.audit().errors))
        self.write(registration.LEGACY_EXPECT, "")
        for text in ("jobs: [", "jobs: !!python/object/apply:os.system ['false']", "name: no jobs",
                     "jobs:\n  check:\n    steps: not-a-sequence\n"):
            self.write(".github/workflows/check.yml", text)
            self.assertTrue(any("Cannot read workflow" in error for error in self.audit().errors))
        (self.root / "tests/alpha_test.gd").unlink()
        self.assertTrue(any("No tracked tests" in error for error in self.audit(CALL).errors))

    def test_non_utf8_source_is_reported_as_a_failure(self) -> None:
        (self.root / "tests/alpha_test.gd").write_bytes(b"\xff\xfeinvalid source")
        self.assertTrue(any("cannot read source" in error for error in self.audit().errors))

    def test_cli_exit_status_and_registration_locations(self) -> None:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            result = registration.main(["--root", str(self.root), "--list"])
        self.assertEqual(result, 0)
        self.assertIn("TEST_REGISTRATION=success", out.getvalue())
        self.assertIn(".github/workflows/check.yml:check:step-1", out.getvalue())
        self.audit("echo unregistered")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(registration.main(["--root", str(self.root)]), 1)

    def test_repository_registrations(self) -> None:
        self.assertEqual(registration.check(registration.ROOT).errors, [])


if __name__ == "__main__":
    unittest.main()
