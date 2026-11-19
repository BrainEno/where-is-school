#!/usr/bin/env python3
"""Both directions for `tools/check_commit_messages.py` (issue #222).

- conventional English subjects pass; a missing scope, an unknown type, a Chinese summary,
  a trailing period and a vague summary each fail;
- in a real range, GitHub's merge commits are exempt and an authored commit is not
  (a throwaway repository this test creates).

Run with `python3 tests/commit_messages_test.py`; needs `git`, no network.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import check_commit_messages as commits  # noqa: E402


class CommitMessagesTest(unittest.TestCase):
    def test_good_subjects(self) -> None:
        for subject in (
            "fix(ci): fail a check whose scene dropped a node",
            "docs(agent-protocol): require landed commits for acceptance",
            "test(story-flags): cover the registry lifecycle",
        ):
            self.assertEqual(commits.problems_for(subject), [], subject)

    def test_bad_subjects(self) -> None:
        cases = {
            "docs: a glossary, issue templates and CODEOWNERS": "scope is required",
            "art(q): the redrawn portrait replaces the old one": "type 'art'",
            "feat(prologue): 序章美术迁移 (#203)": "not English",
            "fix(ci): count dropped nodes.": "period",
            "chore(repo): update files": "too vague",
            "[功能]：序章美术迁移": "scope is required",
            "Fix(CI): shout": "scope is required",
        }
        for subject, fragment in cases.items():
            found = commits.problems_for(subject)
            self.assertTrue(any(fragment in p for p in found), f"{subject!r}: {found}")

    def test_range_exempts_merge_commits_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            def git(*args: str) -> str:
                return subprocess.run(
                    ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args],
                    cwd=tmp, check=True, capture_output=True, text=True,
                ).stdout.strip()

            git("init", "-q", "-b", "main")
            git("commit", "-q", "--allow-empty", "-m", "chore(repo): start")
            base = git("rev-parse", "HEAD")
            git("checkout", "-q", "-b", "topic")
            git("commit", "-q", "--allow-empty", "-m", "fix(ci): a good one")
            git("checkout", "-q", "main")
            git("commit", "-q", "--allow-empty", "-m", "docs(readme): on main")
            git("merge", "-q", "--no-ff", "topic", "-m", "Merge pull request #1 from someone/topic")
            count, findings = commits.audit_range(f"{base}..HEAD", Path(tmp))
            self.assertEqual((count, findings), (3, []))
            git("commit", "-q", "--allow-empty", "-m", "更新文件")
            count, findings = commits.audit_range(f"{base}..HEAD", Path(tmp))
            self.assertEqual(count, 4)
            self.assertEqual(len(findings), 1, findings)
            self.assertEqual(commits.main(["--range", f"{base}..HEAD", "--root", tmp]), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
