#!/usr/bin/env python3
"""Fail when docs/ loses its centralized status index or a local link rots.

Issue #209 asked for the same kind of contract the screenshot folder already has: every
document appears in an index, carries an explicit state, and local links still resolve.
This tool does not try to understand prose or verify a document's claims. It checks the
machine-readable parts of ``docs/README.md`` and ``docs/adr/README.md``:

* every tracked ``docs/**/*.md`` file is listed exactly once;
* every index row has an allowed status, owner, ISO date and supersession note;
* archived documents have a visible status/owner/date/superseded-by header;
* every ADR file is in the ADR index and its row agrees with the file's status word;
* every local inline Markdown link in ``docs/`` points to an existing repository file.

The Markdown link parser and Git inventory are reused from ``check_agent_docs.py`` and
``godot_sidecars.py``; standard library only, no Godot and no network.

    python3 tools/check_docs_index.py --check
    python3 tests/docs_index_test.py
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import date
from pathlib import Path

from check_agent_docs import INLINE_LINK, local_target
from godot_sidecars import tracked_files

ROOT = Path(__file__).resolve().parent.parent
DOCS_INDEX = "docs/README.md"
ADR_INDEX = "docs/adr/README.md"
DOCS_MARKERS = ("<!-- docs-index:start -->", "<!-- docs-index:end -->")
ADR_MARKERS = ("<!-- adr-index:start -->", "<!-- adr-index:end -->")
ALLOWED_STATUSES = {
    "现行", "阅读副本", "历史记录", "历史/归档",
    "提案/待所有者", "实验", "证据/记录", "目录/索引",
}
ALLOWED_ADR_STATUSES = {"已接受", "提案", "待所有者"}
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ADR_FILE_RE = re.compile(r"^docs/adr/\d{4}-.+\.md$")
STATUS_HEADER_FIELDS = ("**状态：**", "**最后核对：**", "**负责人：**", "**取代者：**")


def _read(root: Path, relative: str) -> str:
    try:
        return (root / relative).read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise ValueError(f"{relative}: cannot read UTF-8 document ({type(error).__name__})") from error


def _between_markers(text: str, markers: tuple[str, str], relative: str, errors: list[str]) -> str:
    start, end = markers
    if text.count(start) != 1 or text.count(end) != 1:
        errors.append(f"{relative}: require exactly one {start} / {end} marker pair")
        return ""
    begin = text.index(start) + len(start)
    finish = text.index(end)
    if finish < begin:
        errors.append(f"{relative}: index markers are out of order")
        return ""
    return text[begin:finish]


def _cells(line: str) -> list[str]:
    parts = line.strip().split("|")
    if len(parts) < 3 or parts[0].strip() or parts[-1].strip():
        return []
    return [cell.strip() for cell in parts[1:-1]]


def _resolve(root: Path, source: str, link: str, errors: list[str]) -> str | None:
    try:
        target = local_target(root, source, link)
    except ValueError as error:
        errors.append(str(error))
        return None
    if target is None:
        return None
    if not target.is_file():
        errors.append(f"{source}: broken local file link: {link}")
        return None
    return target.relative_to(root).as_posix()


def _valid_date(value: str) -> bool:
    if not DATE_RE.fullmatch(value):
        return False
    try:
        parsed = date.fromisoformat(value)
    except ValueError:
        return False
    return parsed <= date.today()


def _docs_files(root: Path) -> list[str]:
    return sorted(
        name for name in tracked_files(str(root))
        if name.startswith("docs/") and name.endswith(".md")
    )


def check_index(root: Path, errors: list[str]) -> dict[str, str]:
    """Parse the central index; return path -> status."""
    text = _read(root, DOCS_INDEX)
    section = _between_markers(text, DOCS_MARKERS, DOCS_INDEX, errors)
    rows: dict[str, str] = {}
    for line in section.splitlines():
        if not line.strip().startswith("|"):
            continue
        if re.fullmatch(r"\|[\s:\-|]+\|", line.strip()):
            continue
        cells = _cells(line)
        if not cells:
            errors.append(f"{DOCS_INDEX}: malformed index row: {line.strip()}")
            continue
        if cells[0].startswith("文档"):
            continue
        if len(cells) != 6:
            errors.append(f"{DOCS_INDEX}: index row needs six columns: {line.strip()}")
            continue
        link = INLINE_LINK.search(cells[0])
        if link is None:
            errors.append(f"{DOCS_INDEX}: first column needs a local file link: {cells[0]}")
            continue
        path = _resolve(root, DOCS_INDEX, link.group(1), errors)
        if path is None:
            continue
        if not path.startswith("docs/"):
            errors.append(f"{DOCS_INDEX}: indexed path is outside docs/: {path}")
            continue
        if path in rows:
            errors.append(f"{DOCS_INDEX}: duplicate index row for {path}")
            continue
        status, owner, checked, note = cells[2], cells[3], cells[4], cells[5]
        if status not in ALLOWED_STATUSES:
            errors.append(f"{DOCS_INDEX}: unknown status '{status}' for {path}")
        if not owner or owner in {"—", "-", "TBD"}:
            errors.append(f"{DOCS_INDEX}: {path} needs a role owner")
        if not _valid_date(checked):
            errors.append(f"{DOCS_INDEX}: {path} needs a non-future ISO last-verified date")
        if not note or note in {"—", "-", "TBD"}:
            errors.append(f"{DOCS_INDEX}: {path} needs a supersession/current-source note")
        if path.startswith("docs/archive/") and status != "历史/归档":
            errors.append(f"{DOCS_INDEX}: {path} must be marked 历史/归档")
        rows[path] = status
    return rows


def check_adr_index(root: Path, errors: list[str]) -> set[str]:
    text = _read(root, ADR_INDEX)
    section = _between_markers(text, ADR_MARKERS, ADR_INDEX, errors)
    indexed: set[str] = set()
    for line in section.splitlines():
        if not line.strip().startswith("|"):
            continue
        if re.fullmatch(r"\|[\s:\-|]+\|", line.strip()):
            continue
        cells = _cells(line)
        if not cells:
            errors.append(f"{ADR_INDEX}: malformed ADR row: {line.strip()}")
            continue
        if cells[0].startswith("编号"):
            continue
        if len(cells) != 4:
            errors.append(f"{ADR_INDEX}: ADR row needs four columns: {line.strip()}")
            continue
        link = INLINE_LINK.search(cells[0])
        if link is None:
            errors.append(f"{ADR_INDEX}: first column needs a local ADR link: {cells[0]}")
            continue
        path = _resolve(root, ADR_INDEX, link.group(1), errors)
        if path is None:
            continue
        if not ADR_FILE_RE.fullmatch(path):
            errors.append(f"{ADR_INDEX}: not an ADR file: {path}")
            continue
        if path in indexed:
            errors.append(f"{ADR_INDEX}: duplicate ADR row for {path}")
            continue
        indexed.add(path)
        status, checked = cells[1], cells[2]
        if status not in ALLOWED_ADR_STATUSES:
            errors.append(f"{ADR_INDEX}: unknown ADR status '{status}' for {path}")
        if not _valid_date(checked):
            errors.append(f"{ADR_INDEX}: {path} needs a non-future ISO last-verified date")
        header = "\n".join(_read(root, path).splitlines()[:12]).lower()
        expected = "accepted" if status == "已接受" else "proposed"
        if expected not in header:
            errors.append(f"{ADR_INDEX}: {path} header does not contain '{expected}'")
    for path in _docs_files(root):
        if ADR_FILE_RE.fullmatch(path) and path not in indexed:
            errors.append(f"{ADR_INDEX}: missing ADR row for {path}")
    return indexed


def check_status_headers(root: Path, errors: list[str]) -> None:
    required = [DOCS_INDEX]
    required.extend(
        path for path in _docs_files(root)
        if path.startswith("docs/archive/") and path.endswith(".md")
    )
    for path in required:
        header = "\n".join(_read(root, path).splitlines()[:14])
        for field in STATUS_HEADER_FIELDS:
            if field not in header:
                errors.append(f"{path}: missing status-header field {field}")
        if path.startswith("docs/archive/") and "历史/归档" not in header:
            errors.append(f"{path}: archived file must say 历史/归档 in its header")


def check_local_links(root: Path, errors: list[str]) -> None:
    for path in _docs_files(root):
        text = _read(root, path)
        for link in INLINE_LINK.findall(text):
            _resolve(root, path, link, errors)


def check(root: Path) -> list[str]:
    root = root.resolve()
    errors: list[str] = []
    try:
        rows = check_index(root, errors)
        check_adr_index(root, errors)
        check_status_headers(root, errors)
        check_local_links(root, errors)
        actual = set(_docs_files(root))
        for path in actual - set(rows):
            errors.append(f"{DOCS_INDEX}: unindexed document {path}")
        for path in set(rows) - actual:
            errors.append(f"{DOCS_INDEX}: stale index row {path}")
    except ValueError as error:
        errors.append(str(error))
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check docs index and local links (default)")
    parser.add_argument("--root", default=str(ROOT), help="repository root")
    args = parser.parse_args(argv)
    errors = check(Path(args.root))
    if errors:
        for error in errors:
            print(f"DOCS_INDEX: {error}")
        print("DOCS_INDEX=failure")
        return 1
    print("DOCS_INDEX=success")
    return 0


if __name__ == "__main__":
    sys.exit(main())
