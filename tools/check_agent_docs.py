#!/usr/bin/env python3
"""Check agent discovery contracts and public GDScript coverage (issue #221).

Standard library only. Reuse godot_sidecars.tracked_files rather than adding another
Git/tree inventory. In a checkout only tracked .gd files count; stage new scripts before
checking. Plain fixture trees are also supported by that existing inventory helper.

The class scanner recognizes declaration headers, not GDScript syntax: it masks strings
and comments so examples do not become types. Existing gdparse/engine checks still own
syntax and runtime semantics. Markdown checks cover this repository's inline file links,
not external websites, heading anchors or the meaning of a module description.

    python3 tools/check_agent_docs.py --check
    python3 tools/check_agent_docs.py --list
    python3 tests/agent_docs_test.py
"""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import unquote, urlsplit

from godot_sidecars import tracked_files

ROOT = Path(__file__).resolve().parent.parent
MAX_AGENT_LINES = 150
INDEX = "docs/MODULE_INDEX.md"
PROTOCOL = "docs/AGENT_PROTOCOL.md"
TEMPLATE = ".github/pull_request_template.md"
ENTRY_DOCS = ("AGENTS.md", INDEX, PROTOCOL, "README.md", TEMPLATE)
INDEX_START = "<!-- class-name-index:start -->"
INDEX_END = "<!-- class-name-index:end -->"
REQUIRED_AGENT_LINKS = (
    INDEX, PROTOCOL, "docs/ASSET_PROVENANCE.md", "docs/ASSET_PIPELINE.md",
    "docs/MODEL_LIBRARY.md", "docs/CHARACTER_ART.md",
)
PR_SECTIONS = (
    "任务信息", "变更摘要", "文件范围", "验证结果", "人工验收清单",
    "回归与兼容性", "已知限制与未完成事项", "合并建议",
)
NON_CODE = re.compile(
    r'"""(?:\\.|[^\\])*?"""'
    r"|'''(?:\\.|[^\\])*?'''"
    r'|"(?:\\.|[^"\\\n])*"'
    r"|'(?:\\.|[^'\\\n])*'"
    r"|#[^\n]*",
    re.DOTALL,
)
CLASS_NAME = re.compile(r"^[ \t]*class_name[ \t]+([A-Za-z_][A-Za-z_0-9]*)\b", re.MULTILINE)
TYPE_ROW = re.compile(
    r"^\|\s*`(?P<name>[A-Za-z_][A-Za-z_0-9]*)`\s*\|\s*"
    r"\[`(?P<path>[^`]+)`\]\((?P<link>[^)]+)\)\s*\|(?P<summary>[^|]*)\|\s*$"
)
INLINE_LINK = re.compile(r"\[[^\]\n]+\]\(([^)\s]+)\)")


@dataclass(frozen=True)
class PublicType:
    name: str
    path: str
    line: int


@dataclass
class Audit:
    declarations: list[PublicType] = field(default_factory=list)
    indexed: int = 0
    agent_lines: int = 0
    errors: list[str] = field(default_factory=list)


def public_types(root: Path) -> list[PublicType]:
    """All tracked declaration headers; quoted/commented examples are not declarations."""
    result = []
    for relative in tracked_files(str(root)):
        if not relative.endswith(".gd"):
            continue
        try:
            text = (root / relative).read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError) as error:
            raise ValueError(f"{relative}: cannot read UTF-8 source ({type(error).__name__})") from error
        code = NON_CODE.sub(lambda match: re.sub(r"[^\n]", " ", match[0]), text)
        for match in CLASS_NAME.finditer(code):
            result.append(PublicType(match[1], relative, code.count("\n", 0, match.start()) + 1))
    return sorted(result, key=lambda entry: (entry.name, entry.path, entry.line))


def local_target(root: Path, relative: str, link: str) -> Path | None:
    """Resolve a local inline target. Remote URLs and heading-only links are out of scope."""
    url = urlsplit(link)
    if url.scheme or url.netloc or not url.path:
        return None
    target = ((root / relative).parent / unquote(url.path)).resolve()
    if not target.is_relative_to(root):
        raise ValueError(f"{relative}: local link leaves the repository: {link}")
    return target


def check(root: Path) -> Audit:
    root = root.resolve()
    audit = Audit()
    documents = {}
    for relative in ENTRY_DOCS:
        try:
            documents[relative] = (root / relative).read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            audit.errors.append(f"{relative}: cannot read document ({type(error).__name__})")
            documents[relative] = ""
    agents = documents["AGENTS.md"]
    audit.agent_lines = len(agents.splitlines())
    if audit.agent_lines > MAX_AGENT_LINES:
        audit.errors.append(f"AGENTS.md: {audit.agent_lines} lines exceeds {MAX_AGENT_LINES}")
    if (root / "AGENT.md").exists():
        audit.errors.append("AGENT.md: removed in #221; point tools at AGENTS.md instead of duplicating the entry")

    entry_targets: set[Path] = set()
    for relative, text in documents.items():
        for link in INLINE_LINK.findall(text):
            try:
                target = local_target(root, relative, link)
            except ValueError as error:
                audit.errors.append(str(error))
                continue
            if target is None:
                continue
            if relative == "AGENTS.md":
                entry_targets.add(target)
            if not target.is_file():
                audit.errors.append(f"{relative}: broken local file link: {link}")
    for required in REQUIRED_AGENT_LINKS:
        if root / required not in entry_targets:
            audit.errors.append(f"AGENTS.md: missing mandatory discovery link to {required}")

    template = documents[TEMPLATE]
    headings = re.findall(r"^## (\d+\. .+)$", template, re.MULTILINE)
    expected = [f"{number}. {name}" for number, name in enumerate(PR_SECTIONS, 1)]
    if headings != expected:
        audit.errors.append(f"{TEMPLATE}: keep all eight numbered PR sections in their required order")
    for required in ("### 已检索", "检索关键词与实际命令", "已有模块、调用点与相关测试", "复用决定与理由"):
        if required not in template:
            audit.errors.append(f"{TEMPLATE}: missing search-evidence field: {required}")

    try:
        audit.declarations = public_types(root)
    except ValueError as error:
        audit.errors.append(str(error))
    actual: dict[str, PublicType] = {}
    for entry in audit.declarations:
        if entry.name in actual:
            first = actual[entry.name]
            audit.errors.append(f"duplicate class_name {entry.name}: {first.path} and {entry.path}")
        actual[entry.name] = entry

    index = documents[INDEX]
    rows: dict[str, tuple[str, str]] = {}
    if index.count(INDEX_START) != 1 or index.count(INDEX_END) != 1:
        audit.errors.append(f"{INDEX}: require exactly one start/end class-name-index marker pair")
    elif index.index(INDEX_START) >= index.index(INDEX_END):
        audit.errors.append(f"{INDEX}: class-name-index markers are reversed")
    else:
        table = index.split(INDEX_START, 1)[1].split(INDEX_END, 1)[0]
        for line in table.splitlines():
            match = TYPE_ROW.fullmatch(line)
            if match is None:
                if line.startswith("|") and not line.startswith(("| Public type |", "|---")):
                    audit.errors.append(f"{INDEX}: malformed public-type row: {line}")
                continue
            name, path, link = match["name"], match["path"], match["link"]
            audit.indexed += 1
            if name in rows:
                audit.errors.append(f"{INDEX}: duplicate index row for {name}")
            rows[name] = (path, link)
            if not match["summary"].strip():
                audit.errors.append(f"{INDEX}: {name} needs a responsibility/reuse description")
            try:
                target = local_target(root, INDEX, link)
                if target != root / path:
                    audit.errors.append(f"{INDEX}: {name} link does not point to its source path {path}")
            except ValueError as error:
                audit.errors.append(str(error))
    for name, entry in actual.items():
        if name not in rows:
            audit.errors.append(f"{INDEX}: missing {name} -> {entry.path}")
        elif rows[name][0] != entry.path:
            audit.errors.append(f"{INDEX}: {name} source is {entry.path}, not {rows[name][0]}")
    for name, (path, _link) in rows.items():
        if name not in actual:
            audit.errors.append(f"{INDEX}: stale type {name} -> {path} (no tracked declaration)")
    return audit


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check", dest="mode", action="store_const", const="check", default="check",
                       help="check entry/index/template contracts (default)")
    modes.add_argument("--list", dest="mode", action="store_const", const="list",
                       help="list measured public declarations without checking documentation")
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.mode == "list":
        try:
            for entry in public_types(args.root):
                print(f"{entry.name}\t{entry.path}:{entry.line}")
        except ValueError as error:
            print(f"ERROR: {error}")
            return 1
        return 0
    audit = check(args.root)
    print(f"Agent docs: AGENTS.md={audit.agent_lines}/{MAX_AGENT_LINES} lines; "
          f"public types={len(audit.declarations)}; indexed={audit.indexed}")
    for error in audit.errors:
        print(f"ERROR: {error}")
    print("AGENT_DOCS=" + ("failure" if audit.errors else "success"))
    return 1 if audit.errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
