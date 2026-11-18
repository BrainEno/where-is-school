#!/usr/bin/env python3
"""Audit standalone GDScript test entry points (issue #216).

Every tracked tests/*_test.gd must extend SceneTree, declare an entry callback and
have a literal Godot --script invocation in a workflow run step, or in a tracked
repository-relative shell script called from one. Comments, path filters, echo,
heredoc data and --check-only do not register a test. Existing assertion helpers
are explicitly grandfathered; new tests use TestHarness.Checker.

This is a registration check, not a shell interpreter or proof of execution. It
supports the repository's run_check/measured/timeout/xvfb-run wrappers. Dynamic
paths, bash -c, composite actions and arbitrary workflow conditions are not
expanded. Keep at least one literal invocation for each standalone entry point.
The existing Godot CI still owns runtime verdicts, timeouts and resource errors.

Requires PyYAML from tools/requirements.txt; never loads unsafe YAML objects.
"""

from __future__ import annotations

import argparse
import re
import shlex
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path

import yaml

from check_agent_docs import NON_CODE
from godot_sidecars import tracked_files

ROOT = Path(__file__).resolve().parent.parent
LEGACY_EXPECT = "tests/legacy_expect.txt"
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z_0-9]*=")
EXTENDS = re.compile(r"^extends[ \t]+SceneTree[ \t]*$", re.MULTILINE)
ENTRY = re.compile(r"^func[ \t]+_(?:initialize|init)[ \t]*\(", re.MULTILINE)
EXPECT = re.compile(r"^[ \t]*(?:static[ \t]+)?func[ \t]+_expect[ \t]*\(", re.MULTILINE)


@dataclass
class Audit:
    tests: list[str] = field(default_factory=list)
    registrations: dict[str, set[str]] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)


def shell_commands(text: str) -> Iterator[tuple[int, list[str]]]:
    """Logical shell lines; skip comments and heredoc bodies, keep quoted tokens."""
    pending = ""
    start = 1
    heredocs: list[str] = []
    for line, raw in enumerate(text.splitlines(), 1):
        if heredocs:
            if raw.strip() == heredocs[0]:
                heredocs.pop(0)
            continue
        if not pending:
            start = line
        if raw.endswith("\\"):
            pending += raw[:-1] + " "
            continue
        logical, pending = pending + raw, ""
        lexer = shlex.shlex(logical, posix=True, punctuation_chars=";&|()<>")
        lexer.whitespace_split = True
        try:
            tokens = list(lexer)
        except ValueError:
            # Accumulate a multi-line quote as one command; its middle lines must
            # not masquerade as executable Godot commands.
            pending = logical + "\n"
            continue
        for index, token in enumerate(tokens[:-1]):
            if token == "<<":
                delimiter = tokens[index + 1]
                if delimiter == "-" and index + 2 < len(tokens):
                    delimiter = tokens[index + 2]
                heredocs.append(delimiter.removeprefix("-"))
        command: list[str] = []
        for token in tokens + [";"]:
            if token in (";", "&&", "||", "|", "&", "(", ")"):
                if command:
                    yield start, command
                    command = []
            else:
                command.append(token)


def executable(tokens: list[str]) -> list[str]:
    """Unwrap the small set of command prefixes used in our test workflows."""
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if ASSIGNMENT.match(token) or token in ("if", "then", "do", "!", "command", "exec"):
            index += 1
        elif token == "run_check":
            index += 3  # label, timeout, command...
        elif token == "measured":
            index += 2  # label, command...
        elif token in ("timeout", "xvfb-run", "env"):
            index += 1
            takes_value = {
                "timeout": {"-k", "--kill-after", "-s", "--signal"},
                "xvfb-run": {"-e", "--error-file", "-f", "--auth-file", "-n", "--server-num",
                             "-s", "--server-args", "-p", "--xauth-protocol"},
                "env": {"-u", "--unset", "-C", "--chdir"},
            }[token]
            while index < len(tokens) and tokens[index].startswith("-"):
                option = tokens[index]
                index += 2 if option in takes_value else 1
                if option == "--":
                    break
            if token == "timeout":
                index += 1  # duration
            elif token == "env":
                # Classroom capture supplies an optional array of env assignments.
                # Recognize that prefix, without claiming to evaluate its contents.
                while index < len(tokens) and (ASSIGNMENT.match(tokens[index]) or re.fullmatch(
                        r"\$\{[A-Za-z_][A-Za-z_0-9]*\[@\]\}", tokens[index])):
                    index += 1
        else:
            return tokens[index:]
    return []


def relative_path(root: Path, value: str) -> str | None:
    if "$" in value or "`" in value:
        return None
    path = (root / value.removeprefix("res://")).resolve()
    return path.relative_to(root).as_posix() if path.is_relative_to(root) else None


def disabled(mapping: dict) -> bool:
    condition = mapping.get("if", True)
    return condition is False or str(condition).replace(" ", "").lower() in ("false", "${{false}}")


def workflow_runs(root: Path, inventory: set[str]) -> Iterator[tuple[str, str]]:
    """Only run steps in workflow jobs, never comments, env values or path filters."""
    for relative in sorted(inventory):
        if Path(relative).parent != Path(".github/workflows") or Path(relative).suffix not in (".yml", ".yaml"):
            continue
        document = yaml.safe_load((root / relative).read_text(encoding="utf-8"))
        if not isinstance(document, dict) or not isinstance(document.get("jobs"), dict):
            raise ValueError(f"{relative}: expected a workflow jobs mapping")
        for name, job in document["jobs"].items():
            if not isinstance(job, dict) or disabled(job):
                continue
            steps = job.get("steps", [])
            if not isinstance(steps, list):
                raise ValueError(f"{relative}:{name}: expected a steps sequence")
            for index, step in enumerate(steps, 1):
                if isinstance(step, dict) and not disabled(step) and isinstance(step.get("run"), str):
                    yield f"{relative}:{name}:step-{index}", step["run"]


def check(root: Path) -> Audit:
    root = root.resolve()
    inventory = set(tracked_files(str(root)))
    audit = Audit(tests=sorted(path for path in inventory
                              if Path(path).parent == Path("tests") and path.endswith("_test.gd")))
    legacy: set[str] = set()
    try:
        for line in (root / LEGACY_EXPECT).read_text(encoding="utf-8").splitlines():
            path = line.split("#", 1)[0].strip()
            if path:
                if path in legacy:
                    audit.errors.append(f"{LEGACY_EXPECT}: duplicate entry {path}")
                legacy.add(path)
    except OSError as error:
        audit.errors.append(f"{LEGACY_EXPECT}: cannot read allowlist ({type(error).__name__})")
    helpers = set()
    for relative in audit.tests:
        try:
            text = (root / relative).read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError) as error:
            audit.errors.append(f"{relative}: cannot read source ({type(error).__name__})")
            continue
        code = NON_CODE.sub(lambda match: re.sub(r"[^\n]", " ", match[0]), text)
        if not EXTENDS.search(code) or not ENTRY.search(code):
            audit.errors.append(f"{relative}: standalone tests must extend SceneTree and declare _initialize/_init; "
                                "rename preload-only helpers to *_support.gd")
        if EXPECT.search(code):
            helpers.add(relative)
            if relative not in legacy:
                audit.errors.append(f"{relative}: new _expect helper; use TestHarness.Checker instead")
    for stale in sorted(legacy - helpers):
        audit.errors.append(f"{LEGACY_EXPECT}: stale entry {stale}; shrink, do not grow this allowlist")

    visited: set[str] = set()

    def scan(text: str, origin: str) -> None:
        for line, tokens in shell_commands(text):
            command = executable(tokens)
            if not command:
                continue
            program = command[0]
            if Path(program).name in ("godot", "godot4") or program in (
                    "${godot}", "$godot", "${GODOT_BIN}", "$GODOT_BIN"):
                arguments = command[1:]
                if "--" in arguments:
                    arguments = arguments[:arguments.index("--")]
                if "--check-only" in arguments:
                    continue
                for index, argument in enumerate(arguments):
                    target = ""
                    if argument in ("--script", "-s") and index + 1 < len(arguments):
                        target = arguments[index + 1]
                    elif argument.startswith("--script="):
                        target = argument.split("=", 1)[1]
                    relative = relative_path(root, target) if target else None
                    if relative and Path(relative).parent == Path("tests") and relative.endswith("_test.gd"):
                        if relative not in inventory:
                            audit.errors.append(f"{origin}:{line}: stale/untracked test invocation {relative}")
                        audit.registrations.setdefault(relative, set()).add(f"{origin}:{line}")
            else:
                target = program
                if program in ("bash", "sh", "source", "."):
                    arguments = command[1:]
                    # A shell -c string is not a literal repository script.
                    if any(argument.startswith("-") and "c" in argument for argument in arguments[:1]):
                        continue
                    target = next((argument for argument in arguments if not argument.startswith("-")), "")
                relative = relative_path(root, target) if target else None
                if relative and relative.endswith(".sh") and relative in inventory and relative not in visited:
                    visited.add(relative)
                    scan((root / relative).read_text(encoding="utf-8"), relative)

    try:
        runs = list(workflow_runs(root, inventory))
        if not runs:
            audit.errors.append("No workflow run steps found")
        for origin, text in runs:
            scan(text, origin)
    except (OSError, ValueError, yaml.YAMLError) as error:
        audit.errors.append(f"Cannot read workflow registration: {error}")
    if not audit.tests:
        audit.errors.append("No tracked tests/*_test.gd entry points found")
    for relative in audit.tests:
        if relative not in audit.registrations:
            audit.errors.append(f"{relative}: no literal Godot --script invocation reachable from CI")
    return audit


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check registrations (default)")
    parser.add_argument("--list", action="store_true", help="also list registration locations")
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    audit = check(args.root)
    if args.list:
        for test in audit.tests:
            print(test + "\t" + ", ".join(sorted(audit.registrations.get(test, set()))))
    print(f"Test registration: {len(audit.tests)} standalone test(s), "
          f"{len(set(audit.tests) & audit.registrations.keys())} registered")
    for error in audit.errors:
        print(f"ERROR: {error}")
    print("TEST_REGISTRATION=" + ("failure" if audit.errors else "success"))
    return int(bool(audit.errors))


if __name__ == "__main__":
    raise SystemExit(main())
