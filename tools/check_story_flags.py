#!/usr/bin/env python3
"""Story-flag lifecycle check (issue #292).

`scripts/narrative/story_flags.gd` is the registry of story-flag names. Dialogue rewrites
left constants behind that nothing set or read any more, and content set flags that were
never declared; neither showed up anywhere, because nothing compared the registry with
the content. This check does:

1. every registry constant is used at least once - written or read by content, or named by
   game code (`StoryFlags.NAME` or the flag's string in `scripts/`, `scenes/`, `addons/`);
2. every flag content writes (a `set_flag` effect in `data/dialogue` or `data/inspections`,
   or an `arrival_flags` entry in `data/story/locations.json`) is declared in the registry;
3. every flag content writes has a reader - a content condition (`all_flags`, `not_flags`,
   `requires`, a check `modifier`), a location's `arrival_flags`/`arrival_flag` (the
   notebook's route and the arrival conversations read those back through the location
   catalog), or game code naming it - or is listed in `WRITE_ONLY`
   below with the reason it is kept;
4. `WRITE_ONLY` does not go stale: an entry that gained a reader, or that content no
   longer writes, is reported so the list is shortened instead of rotting;
5. the registry's `ALL_FLAGS` lists every constant exactly once.

Tests are not readers: a flag only a test looks at does nothing in the game. Game code is
matched by name, not parsed, so a script that only *writes* a flag also counts as naming
it; the check is about flags nothing in the game mentions, not a data-flow analysis.
Generated flags (`choice:`, `seen:`, `check:`, `voice:`, `voice_count:`) are made by the
helpers at the bottom of the registry and are out of scope.

Usage: `python3 tools/check_story_flags.py --check` (exit 1 on a finding). `--root`
points it at another tree; `tests/story_flags_test.py` uses that to prove each rule fails.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = "scripts/narrative/story_flags.gd"
CONTENT_DIRS = ("data/dialogue", "data/inspections")
LOCATIONS = "data/story/locations.json"
CODE_DIRS = ("scripts", "scenes", "addons")
CODE_SUFFIXES = (".gd", ".tscn", ".tres")

# Flags content writes on purpose although nothing reads them yet, and why. Every entry
# needs a reason; issue #277 tracks giving the recorded choices their echo.
WRITE_ONLY: dict[str, str] = {
    "asked_n_about_b": "prologue choice record; its echo is planned (#277)",
    "asked_n_about_textbook": "prologue choice record; its echo is planned (#277)",
    "asked_q_date": "prologue choice record; its echo is planned (#277)",
    "asked_q_identity": "prologue choice record; its echo is planned (#277)",
    "denied_exam_memory": "prologue choice record; its echo is planned (#277)",
    "stayed_silent": "prologue choice record; its echo is planned (#277)",
    "told_q_about_textbook": "prologue choice record; its echo is planned (#277)",
    "free_period_stayed": "the free-period stay/leave choice; its echo is planned (#277)",
    "free_period_leaving": "the free-period stay/leave choice; its echo is planned (#277)",
    "student_talked": "classroom conversation record; nothing branches on it yet (#277)",
    "playground_checked": "playground check outcome; a use for the yard's results is planned (#283)",
    "playground_shed_open": "playground check outcome; a use for the yard's results is planned (#283)",
    "playground_shed_looked": "playground check outcome; a use for the yard's results is planned (#283)",
    "playground_rota_read": "playground check outcome; a use for the yard's results is planned (#283)",
    "playground_rota_smudged": "playground check outcome; a use for the yard's results is planned (#283)",
    "playground_tag_found": "playground check outcome; a use for the yard's results is planned (#283)",
    "playground_ball_stuck": "playground check outcome; a use for the yard's results is planned (#283)",
}

CONST = re.compile(r'^const ([A-Z][A-Z0-9_]*): StringName = &"([^"]+)"', re.M)
ALL_FLAGS = re.compile(r"^const ALL_FLAGS: Array\[StringName\] = \[(.*?)^\]", re.M | re.S)


def is_generated(flag: str) -> bool:
    return ":" in flag


def read_registry(root: Path) -> tuple[dict[str, str], list[str] | None]:
    text = (root / REGISTRY).read_text(encoding="utf-8")
    consts = dict(CONST.findall(text))
    match = ALL_FLAGS.search(text)
    listed = None
    if match:
        body = re.sub(r"#[^\n]*", "", match.group(1))
        listed = [name.strip() for name in body.split(",") if name.strip()]
    return consts, listed


def walk_content(node, source: str, writes: dict, reads: dict) -> None:
    if isinstance(node, dict):
        if node.get("type") == "set_flag" and isinstance(node.get("flag"), str):
            writes[node["flag"]].add(source)
        for key in ("all_flags", "not_flags"):
            for flag in node.get(key) or []:
                if isinstance(flag, str):
                    reads[flag].add(source)
        requires = node.get("requires")
        if isinstance(requires, (dict, list)):
            for flag in requires:
                if isinstance(flag, str):
                    reads[flag].add(source)
        for modifier in node.get("modifiers") or []:
            if isinstance(modifier, dict) and isinstance(modifier.get("flag"), str):
                reads[modifier["flag"]].add(source)
        for value in node.values():
            walk_content(value, source, writes, reads)
    elif isinstance(node, list):
        for value in node:
            walk_content(value, source, writes, reads)


def read_content(root: Path) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    writes: dict[str, set[str]] = defaultdict(set)
    reads: dict[str, set[str]] = defaultdict(set)
    for folder in CONTENT_DIRS:
        for path in sorted((root / folder).rglob("*.json")):
            rel = path.relative_to(root).as_posix()
            walk_content(json.loads(path.read_text(encoding="utf-8")), rel, writes, reads)
    locations = root / LOCATIONS
    if locations.is_file():
        data = json.loads(locations.read_text(encoding="utf-8"))
        entries = data.get("locations", data) if isinstance(data, dict) else data
        values = entries.values() if isinstance(entries, dict) else entries
        for entry in values:
            if isinstance(entry, dict):
                # Arrival sets these, and the notebook's route reads them back to list the
                # places reached (`journal_route.gd`), so they are written and read here.
                for flag in entry.get("arrival_flags") or []:
                    writes[flag].add(LOCATIONS)
                    reads[flag].add(LOCATIONS)
                # Written by the arrival conversation; read to play that conversation once
                # (`location_flow.gd`) and by the notebook's route.
                if isinstance(entry.get("arrival_flag"), str) and entry["arrival_flag"]:
                    reads[entry["arrival_flag"]].add(LOCATIONS)
    return writes, reads


def read_code(root: Path) -> list[tuple[str, str]]:
    out = []
    for folder in CODE_DIRS:
        base = root / folder
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            rel = path.relative_to(root).as_posix()
            if path.suffix in CODE_SUFFIXES and rel != REGISTRY:
                out.append((rel, path.read_text(encoding="utf-8", errors="replace")))
    return out


MEMBER = re.compile(r"\bStoryFlags\.([A-Z][A-Z0-9_]*)\b")


def dangling_members(root: Path, consts: dict[str, str]) -> list[str]:
    """`StoryFlags.NAME` in any script, scene or test that names no constant.

    Godot reports these as a Parse Error, but only when the script runs; deleting a flag
    should fail here, before CI starts an engine. Tests count: a test that still names a
    deleted flag would stop compiling.
    """
    known = set(consts) | {"ALL_FLAGS"}
    found = []
    for folder in CODE_DIRS + ("tests",):
        base = root / folder
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if path.suffix not in CODE_SUFFIXES:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for match in MEMBER.finditer(text):
                if match.group(1) not in known:
                    line = text.count("\n", 0, match.start()) + 1
                    found.append(
                        f"{path.relative_to(root).as_posix()}:{line}: StoryFlags.{match.group(1)} "
                        f"is not declared in {REGISTRY}"
                    )
    return found


def code_names(code: list[tuple[str, str]], const: str | None, value: str) -> list[str]:
    by_value = re.compile(r"[\"']" + re.escape(value) + r"[\"']")
    by_name = re.compile(r"\bStoryFlags\." + const + r"\b") if const else None
    return [path for path, text in code if by_value.search(text) or (by_name and by_name.search(text))]


def audit(root: Path, write_only: dict[str, str] | None = None) -> list[str]:
    write_only = WRITE_ONLY if write_only is None else write_only
    consts, listed = read_registry(root)
    by_value = {value: name for name, value in consts.items()}
    writes, reads = read_content(root)
    code = read_code(root)
    problems: list[str] = []

    for name, value in sorted(consts.items()):
        if value not in writes and value not in reads and not code_names(code, name, value):
            problems.append(f"{REGISTRY}: {name} (\"{value}\") is never written or read by content or game code - delete it")

    for flag in sorted(writes):
        if is_generated(flag):
            continue
        where = sorted(writes[flag])[0]
        if flag not in by_value:
            problems.append(f"{where}: writes \"{flag}\", which {REGISTRY} does not declare")
        has_reader = bool(reads.get(flag)) or bool(code_names(code, by_value.get(flag), flag))
        if not has_reader and flag not in write_only:
            problems.append(f"{where}: writes \"{flag}\" and nothing in the game reads it - read it, or list it in WRITE_ONLY with a reason")
        if has_reader and flag in write_only:
            problems.append(f"WRITE_ONLY: \"{flag}\" now has a reader - remove it from the list")

    for flag, reason in sorted(write_only.items()):
        if not reason.strip():
            problems.append(f"WRITE_ONLY: \"{flag}\" has no reason")
        if flag not in writes:
            problems.append(f"WRITE_ONLY: \"{flag}\" is no longer written by content - remove it from the list")

    problems += dangling_members(root, consts)

    if listed is None:
        problems.append(f"{REGISTRY}: no ALL_FLAGS array")
    else:
        for name in sorted(set(consts) - set(listed)):
            problems.append(f"{REGISTRY}: ALL_FLAGS is missing {name}")
        for name in sorted(set(listed) - set(consts)):
            problems.append(f"{REGISTRY}: ALL_FLAGS lists {name}, which is not a flag constant")
        for name in sorted({n for n in listed if listed.count(n) > 1}):
            problems.append(f"{REGISTRY}: ALL_FLAGS lists {name} more than once")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--check", action="store_true", help="fail on any finding (the default behaviour)")
    parser.add_argument("--root", type=Path, default=ROOT, help="repository root to audit")
    args = parser.parse_args(argv)
    consts, _ = read_registry(args.root)
    problems = audit(args.root)
    for problem in problems:
        print(f"ERROR: {problem}")
    if problems:
        print(f"STORY_FLAGS=failure ({len(problems)} finding(s))")
        return 1
    print(f"STORY_FLAGS=success: {len(consts)} registered flag(s), {len(WRITE_ONLY)} write-only by decision")
    return 0


if __name__ == "__main__":
    sys.exit(main())
