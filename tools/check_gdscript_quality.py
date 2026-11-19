#!/usr/bin/env python3
"""Check new GDScript size, naming and duplicate-load debt (issues #229/#223).

Use the existing gdlint rules from gdlintrc, on tracked scripts in scripts/,
scenes/ and addons/. Compare with a specific Git base, not a refreshed snapshot
of exceptions in the proposed commit. A new file or first crossing of the cap
fails; growth of files already past the cap is visible without blocking work
on them. A naming or duplicate-load violation that moves within a file is not
new, but another copy is.

    python3 tools/check_gdscript_quality.py --base origin/main
    python3 tools/check_gdscript_quality.py --inventory

The inventory is a report, not a gate on historical debt. Requires the pinned
Python tooling environment in tools/README.md; no engine/import cache needed.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from types import MappingProxyType

import yaml
from gdtoolkit.linter import DEFAULT_CONFIG, basic_checks, format_checks, name_checks
from gdtoolkit.linter.problem import Problem
from gdtoolkit.parser import parser as gdparser
from lark.exceptions import UnexpectedInput
from lark.indenter import DedentError

ROOT = Path(__file__).resolve().parent.parent
SCRIPT_ROOTS = ("scripts/", "scenes/", "addons/")
SIZE_RULE = "max-file-lines"
CONFIG_NAME = "gdlintrc"


class AuditError(Exception):
    """The requested comparison could not be performed; never a green result."""


@dataclass(frozen=True)
class ScriptChange:
    path: str
    previous: str | None


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    column: int
    rule: str
    detail: str
    advisory: bool = False

    def __str__(self) -> str:
        path = self.path.replace("\n", "\\n").replace("\r", "\\r")
        return f"{path}:{self.line}:{self.column}: {self.rule}: {self.detail}"


@dataclass
class Report:
    files: int
    findings: list[Finding]


def read_config(root: Path) -> MappingProxyType:
    path = root / CONFIG_NAME
    try:
        settings = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, yaml.YAMLError) as exc:
        raise AuditError(f"Cannot read {CONFIG_NAME}: {exc}") from exc
    if not isinstance(settings, dict) or settings.keys() - DEFAULT_CONFIG.keys():
        raise AuditError(f"{CONFIG_NAME} must be a mapping of known gdlint settings")
    config = {**DEFAULT_CONFIG, **settings}
    if type(config[SIZE_RULE]) is not int or config[SIZE_RULE] < 1:
        raise AuditError(f"{CONFIG_NAME}: {SIZE_RULE} must be a positive integer")
    disabled = config["disable"]
    if not isinstance(disabled, list) or any(
        not isinstance(rule, str) or rule not in DEFAULT_CONFIG for rule in disabled
    ):
        raise AuditError(f"{CONFIG_NAME}: disable must list known gdlint rules")
    if SIZE_RULE in disabled:
        raise AuditError(f"{CONFIG_NAME}: the size ceiling must stay enabled")
    for key, default in DEFAULT_CONFIG.items():
        if isinstance(default, str):
            try:
                re.compile(config[key])
            except (TypeError, re.error) as exc:
                raise AuditError(f"{CONFIG_NAME}: {key} is not a valid naming pattern") from exc
    return MappingProxyType(config)


def _git(root: Path, *args: str) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), *args], check=True, capture_output=True
        )
        return result.stdout.decode("utf-8-sig")
    except subprocess.CalledProcessError as exc:
        reason = exc.stderr.decode("utf-8", errors="replace").strip()
        raise AuditError(f"git {args[0]} failed: {reason}") from exc
    except (OSError, UnicodeError) as exc:
        raise AuditError(f"git {args[0]} could not read repository data: {exc}") from exc


def resolve_base(root: Path, ref: str) -> str:
    return _git(root, "rev-parse", "--verify", "--end-of-options", ref + "^{commit}").strip()


def in_scope(path: str) -> bool:
    return path.startswith(SCRIPT_ROOTS) and path.endswith(".gd")


def changed_scripts(root: Path, base: str) -> list[ScriptChange]:
    # NUL framing preserves spaces, quotes and tabs in both sides of a rename.
    # Do not use pathspecs here: a move *from* tests/ to scripts/ is new production code.
    diff = _git(root, "diff", "--name-status", "-z", "--find-renames", "--no-ext-diff",
                "--diff-filter=ACMRT", base, "--")
    fields = iter(diff.rstrip("\0").split("\0")) if diff else iter(())
    changes: list[ScriptChange] = []
    for status in fields:
        path = next(fields)
        previous = None
        if status.startswith(("R", "C")):
            old, path = path, next(fields)
            # Copying does not transfer an exception to a second place.
            if status.startswith("R") and in_scope(old):
                previous = old
        elif status.startswith("M"):
            previous = path
        # A file-type change (e.g. a symlink replaced by a script) gets no old allowance.
        if in_scope(path):
            changes.append(ScriptChange(path, previous))
    return sorted(changes, key=lambda change: change.path)


def tracked_scripts(root: Path) -> list[ScriptChange]:
    paths = set(_git(root, "ls-files", "-z", "--", *SCRIPT_ROOTS).split("\0"))
    return [ScriptChange(path, None) for path in sorted(paths) if in_scope(path)]


def read_script(root: Path, relative: str) -> str:
    path = root / relative
    if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
        raise AuditError(f"{relative}: expected a regular tracked file in the repository")
    try:
        return path.read_text(encoding="utf-8-sig")
    except (OSError, ValueError) as exc:
        raise AuditError(f"{relative}: could not read GDScript: {exc}") from exc


def lint(source: str, label: str, config: MappingProxyType) -> list[Problem]:
    try:
        tree = gdparser.parse(source, gather_metadata=True)
    except (UnexpectedInput, DedentError) as exc:
        line = getattr(exc, "line", "?")
        column = getattr(exc, "column", "?")
        raise AuditError(f"{label}:{line}:{column}: cannot parse GDScript ({type(exc).__name__})") from exc
    # These are the pinned gdlint checkers, without its CLI's per-file suppression
    # directives. The comparison base owns legacy exceptions, not a source comment.
    return (
        format_checks.lint(source, config)
        + name_checks.lint(tree, config)
        + basic_checks.lint(tree, config)
    )


def check_script(
    path: str, source: str, previous: str | None, config: MappingProxyType
) -> list[Finding]:
    new = lint(source, path, config)
    old = [] if previous is None else lint(previous, f"{path} (base)", config)
    allowances = Counter((problem.name, problem.description) for problem in old)
    old_lines = len(previous.splitlines()) if previous is not None else 0
    problems: list[Finding] = []
    for problem in sorted(new, key=lambda item: (item.line, item.column, item.name)):
        detail = problem.description
        advisory = False
        if problem.name == SIZE_RULE:
            limit = config[SIZE_RULE]
            lines = len(source.splitlines())
            if lines <= old_lines:
                continue
            advisory = old_lines > limit
            detail = f"{lines} lines (base {old_lines}, limit {limit}); split the responsibility"
            if advisory:
                detail += " (existing oversized script grew; report only)"
        else:
            key = (problem.name, detail)
            if allowances[key] > 0:
                allowances[key] -= 1
                continue
        problems.append(Finding(path, problem.line, max(1, problem.column), problem.name, detail, advisory))
    return problems


def audit(root: Path, base_ref: str | None) -> Report:
    top = _git(root, "rev-parse", "--show-toplevel").rstrip("\n")
    if Path(top).resolve() != root.resolve():
        raise AuditError("--root must be the top of the Git worktree")
    unmerged = _git(root, "ls-files", "--unmerged", "-z", "--", *SCRIPT_ROOTS)
    if any(in_scope(record.partition("\t")[2]) for record in unmerged.split("\0")):
        raise AuditError("Resolve unmerged GDScript entries before running the quality gate")
    config = read_config(root)
    base = resolve_base(root, base_ref) if base_ref is not None else None
    changes = changed_scripts(root, base) if base else tracked_scripts(root)
    findings: list[Finding] = []
    for change in changes:
        source = read_script(root, change.path)
        previous = None
        if change.previous:
            previous = _git(root, "show", f"{base}:{change.previous}").replace("\r\n", "\n")
        if source != previous:
            findings.extend(check_script(change.path, source, previous, config))
    return Report(len(changes), findings)


def main(argv: list[str] | None = None) -> int:
    command = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    command.add_argument("--root", type=Path, default=ROOT)
    mode = command.add_mutually_exclusive_group(required=True)
    mode.add_argument("--base", help="Git commit to grant legacy allowances from")
    mode.add_argument("--inventory", action="store_true", help="report all current debt without gating it")
    args = command.parse_args(argv)
    try:
        report = audit(args.root, args.base)
    except AuditError as exc:
        print(f"GDSCRIPT_QUALITY_ERROR: {exc}", file=sys.stderr)
        return 2
    if args.inventory:
        for finding in report.findings:
            print(finding)
        print(f"GDSCRIPT_QUALITY_INVENTORY: {len(report.findings)} finding(s) in {report.files} tracked scripts")
        return 0
    blockers = 0
    for finding in report.findings:
        if finding.advisory:
            print(f"GDSCRIPT_QUALITY_WARNING: {finding}")
        else:
            blockers += 1
            print(f"GDSCRIPT_QUALITY_FAILURE: {finding}")
    if blockers:
        print(f"{blockers} new finding(s) across {report.files} checked scripts")
        return 1
    print(f"GDSCRIPT_QUALITY_OK: no blocking findings across {report.files} changed scripts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
