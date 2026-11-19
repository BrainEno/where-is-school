#!/usr/bin/env python3
"""Commit subjects follow `docs/AGENT_PROTOCOL.md` §3 (issue #222).

Every authored commit in a range must read `<type>(<scope>): <summary>` in English: one of
the listed lowercase types, a required lowercase kebab-case scope, an ASCII summary with no
trailing period. Merge commits are exempt - GitHub writes `Merge pull request #N from ...`
itself, and a branch refreshed from `main` gets `Merge branch ...` - because §3 governs what
an author writes, and the repository merges pull requests with merge commits, so the
Chinese PR title (§2) never becomes a commit subject. A squash merge would make it one,
which is why §3 says to rewrite the squash title in this form.

    python3 tools/check_commit_messages.py --range origin/main..HEAD
    python3 tools/check_commit_messages.py --subject "fix(ci): count dropped nodes"
    python3 tests/commit_messages_test.py

Exit 1 on any finding.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TYPES = ("feat", "fix", "refactor", "test", "build", "ci", "docs", "perf", "chore")
SUBJECT = re.compile(r"^(?P<type>[a-z]+)\((?P<scope>[a-z0-9]+(?:-[a-z0-9]+)*)\): (?P<summary>\S.*)$")
VAGUE = {"update files", "fix stuff", "changes", "agent work", "wip", "update"}


def problems_for(subject: str) -> list[str]:
    match = SUBJECT.fullmatch(subject)
    if match is None:
        return ["not `<type>(<scope>): <summary>` (the scope is required, lowercase kebab-case)"]
    found = []
    if match["type"] not in TYPES:
        found.append(f"type '{match['type']}' is not one of {', '.join(TYPES)}")
    summary = match["summary"]
    if not summary.isascii():
        found.append("the summary is not English (non-ASCII characters)")
    if summary.endswith("."):
        found.append("the summary ends with a period")
    if summary.strip().lower() in VAGUE:
        found.append(f"'{summary}' is too vague to describe the change")
    return found


def commits(range_spec: str, root: Path) -> list[tuple[str, int, str]]:
    out = subprocess.run(
        ["git", "log", "--format=%H%x00%P%x00%s", range_spec],
        cwd=root, capture_output=True, text=True, check=True,
    ).stdout
    result = []
    for line in out.splitlines():
        sha, parents, subject = line.split("\x00", 2)
        result.append((sha, len(parents.split()), subject))
    return result


def audit_range(range_spec: str, root: Path = ROOT) -> tuple[int, list[str]]:
    listed = commits(range_spec, root)
    findings = []
    for sha, parents, subject in listed:
        if parents > 1 and subject.startswith("Merge "):
            continue
        for problem in problems_for(subject):
            findings.append(f"{sha[:9]} \"{subject}\": {problem}")
    return len(listed), findings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--range", help="a git revision range, e.g. origin/main..HEAD")
    group.add_argument("--subject", help="check one subject line")
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args(argv)
    if args.subject is not None:
        count, findings = 1, [f"\"{args.subject}\": {p}" for p in problems_for(args.subject)]
    else:
        count, findings = audit_range(args.range, args.root)
    for finding in findings:
        print(f"ERROR: {finding}")
    if findings:
        print(f"COMMIT_MESSAGES=failure ({len(findings)} finding(s); see docs/AGENT_PROTOCOL.md §3)")
        return 1
    print(f"COMMIT_MESSAGES=success: {count} commit(s) checked")
    return 0


if __name__ == "__main__":
    sys.exit(main())
