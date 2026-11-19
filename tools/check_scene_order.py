#!/usr/bin/env python3
"""No `.tscn` node is declared before its parent (issue #291).

Godot builds a scene in file order. A node whose `parent=` names a node declared *later*
in the file is dropped when the scene is instantiated, with only a WARNING
("Parent path ... has vanished when instantiating") - PR #272 lost the classroom's
`StudentTalk` interactable that way, and CI stayed green. `tools/ci_run_check.sh` now
fails a check whose log carries that warning; this is the static half, which needs no
engine and covers scenes no check instantiates.

A parent that is never declared in the file is not reported: it can be a node inside an
instanced sub-scene (editable children), which this file does not list.

Usage: `python3 tools/check_scene_order.py --check` (exit 1 on a finding); `--root` points
it at another tree (`tests/scene_order_test.py`).
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NODE = re.compile(r'^\[node name="([^"]+)"(?:[^\]]*?\sparent="([^"]*)")?', re.M)


def scene_files(root: Path) -> list[Path]:
    try:
        out = subprocess.run(["git", "ls-files", "*.tscn"], cwd=root, capture_output=True, text=True, check=True).stdout
        files = [root / line for line in out.splitlines() if line]
        if files:
            return files
    except (OSError, subprocess.CalledProcessError):
        pass
    return sorted(root.rglob("*.tscn"))


def audit_text(text: str, label: str) -> list[str]:
    nodes = []  # (path, parent, line)
    for match in NODE.finditer(text):
        name, parent = match.group(1), match.group(2)
        line = text.count("\n", 0, match.start()) + 1
        if parent is None:
            path = "."
        elif parent == ".":
            path = name
        else:
            path = f"{parent}/{name}"
        nodes.append((path, parent, line))
    first = {}
    for index, (path, _parent, _line) in enumerate(nodes):
        first.setdefault(path, index)
    problems = []
    for index, (path, parent, line) in enumerate(nodes):
        if parent in (None, "."):
            continue
        where = first.get(parent)
        if where is not None and where > index:
            problems.append(
                f"{label}:{line}: node '{path}' is declared before its parent '{parent}' "
                f"(line {nodes[where][2]}); Godot drops it when the scene is instantiated"
            )
    return problems


def audit(root: Path) -> tuple[int, list[str]]:
    files = scene_files(root)
    problems: list[str] = []
    for path in files:
        if not path.is_file():
            continue
        problems += audit_text(path.read_text(encoding="utf-8", errors="replace"), path.relative_to(root).as_posix())
    return len(files), problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--check", action="store_true", help="fail on any finding (the default behaviour)")
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args(argv)
    count, problems = audit(args.root)
    for problem in problems:
        print(f"ERROR: {problem}")
    if problems:
        print(f"SCENE_ORDER=failure ({len(problems)} finding(s))")
        return 1
    print(f"SCENE_ORDER=success: {count} scene(s), every node after its parent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
