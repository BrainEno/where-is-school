#!/usr/bin/env python3
"""Catch player-visible draft markers in the source JSON (issue #346).

Ordinary checks accept only recorded, unchanged debt at the same field. Tagged
releases use --release, which accepts no draft markers, even recorded ones.
The checker does not rewrite text or print it into CI logs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
ALLOWLIST = "tools/content_placeholder_allowlist.json"
MARKER = re.compile(r"待做|(?<![a-z0-9_])(?:TODO|TBD|WIP|FIXME)(?![a-z0-9_])", re.I | re.ASCII)
# Text keys, not flags, branch destinations, speaker IDs or locale lookup keys.
TEXT_FIELDS = frozenset({
    "text", "title", "description", "prompt", "name", "label", "caption", "subtitle", "hint", "message",
})
Field = tuple[str, str]  # repository-relative filename, structured field path


class AuditError(ValueError):
    """Unreadable or ambiguous input must not yield a passing result."""


@dataclass(frozen=True)
class Finding:
    field: Field
    marker: str
    digest: str


@dataclass(frozen=True)
class Allowance:
    digest: str
    issue: int


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise AuditError("duplicate JSON object key")
        result[key] = value
    return result


def read_json(root: Path, relative: str) -> object:
    path = root / relative
    if path.is_symlink() or not path.resolve().is_relative_to(root):
        raise AuditError(f"{relative}: expected a file inside the checkout, not a symlink")
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique_object)
    except (OSError, ValueError) as exc:
        raise AuditError(f"{relative}: {exc}") from exc


def item_id(value: object) -> str:
    if isinstance(value, dict):
        for key in ("id", "entry_id"):
            item = value.get(key)
            if isinstance(item, str) and item:
                return item
    return ""


def field_path(parts: tuple[str, ...]) -> str:
    return "/" + "/".join(part.replace("~", "~0").replace("/", "~1") for part in parts)


def text_fields(
    node: object, parts: tuple[str, ...] = (), *, locale_table: bool = False
) -> Iterator[tuple[str, str]]:
    if isinstance(node, dict):
        for key, value in node.items():
            path = parts + (key,)
            if isinstance(value, str):
                if key in TEXT_FIELDS or key.endswith("_text") or (locale_table and parts == ("strings",)):
                    yield field_path(path), value
            else:
                # A map key (e.g. a conversation id) named 'text' is not itself a text field.
                yield from text_fields(value, path, locale_table=locale_table)
    elif isinstance(node, list):
        ids = [item_id(value) for value in node]
        counts = Counter(ids)
        for i, (value, identity) in enumerate(zip(node, ids)):
            # Existing nodes, choices and notebook effects keep their anchors when
            # unrelated records are inserted before them. Anonymous arrays use indices.
            selector = "@" + identity if identity and counts[identity] == 1 else str(i)
            yield from text_fields(value, parts + (selector,), locale_table=locale_table)


def scan(root: Path) -> tuple[int, list[Finding]]:
    data = root / "data"
    paths = sorted(data.rglob("*.json"))
    if not paths or data.is_symlink():
        raise AuditError("expected source JSON files in the checkout's data/ directory")
    findings: list[Finding] = []
    for path in paths:
        relative = path.relative_to(root).as_posix()
        document = read_json(root, relative)
        if not isinstance(document, (dict, list)):
            raise AuditError(f"{relative}: expected a JSON object or array")
        for pointer, text in text_fields(document, locale_table=relative.startswith("data/locale/")):
            match = MARKER.search(text)
            if match:
                findings.append(Finding((relative, pointer), match.group().upper(), hashlib.sha256(text.encode()).hexdigest()))
    return len(paths), findings


def read_allowlist(root: Path) -> dict[Field, Allowance]:
    document = read_json(root, ALLOWLIST)
    if (not isinstance(document, dict) or type(document.get("format_version")) is not int
            or document["format_version"] != 1 or not isinstance(document.get("groups"), list)):
        raise AuditError(f"{ALLOWLIST}: expected format_version 1 and a groups array")
    allowances: dict[Field, Allowance] = {}
    for group in document["groups"]:
        if not isinstance(group, dict):
            raise AuditError(f"{ALLOWLIST}: expected a group object")
        issue, reason, files = group.get("issue"), group.get("reason"), group.get("files")
        if (type(issue) is not int or issue < 1 or not isinstance(reason, str) or not reason.strip()
                or not isinstance(files, dict) or not files):
            raise AuditError(f"{ALLOWLIST}: each group needs an issue number, a reason and exact fields")
        for relative, entries in files.items():
            path = PurePosixPath(relative)
            if (not relative.startswith("data/") or path.suffix != ".json" or path.as_posix() != relative
                    or ".." in path.parts or not isinstance(entries, dict) or not entries):
                raise AuditError(f"{ALLOWLIST}: invalid file entry {relative!r} in issue #{issue}")
            for pointer, digest in entries.items():
                field = relative, pointer
                if (not pointer.startswith("/") or not isinstance(digest, str)
                        or re.fullmatch(r"[0-9a-f]{64}", digest) is None or field in allowances):
                    raise AuditError(f"{ALLOWLIST}: invalid or duplicate field {format_field(field)}")
                allowances[field] = Allowance(digest, issue)
    return allowances


def format_field(field: Field) -> str:
    # Keep each diagnostic on one line; never print the placeholder's contents.
    return "#".join(field).replace("\n", "\\n").replace("\r", "\\r")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=ROOT, help="checkout or test fixture to audit")
    parser.add_argument("--release", action="store_true", help="reject all placeholders, including known debt")
    args = parser.parse_args(argv)
    try:
        root = args.root.resolve()
        files, findings = scan(root)
        allowances = {} if args.release else read_allowlist(root)
    except (ValueError, OSError, RecursionError) as exc:
        print(f"CONTENT_PLACEHOLDERS_ERROR: {exc}", file=sys.stderr)
        return 2

    new = 0
    for finding in findings:
        allowance = allowances.get(finding.field)
        if allowance is not None and allowance.digest == finding.digest:
            continue
        new += 1
        if args.release:
            reason = "not allowed in a release"
        elif allowance is None:
            reason = "not recorded as existing debt"
        else:
            reason = f"recorded text changed (issue #{allowance.issue})"
        print(f"CONTENT_PLACEHOLDER: {format_field(finding.field)} [{finding.marker}]; {reason}")

    stale = allowances.keys() - {finding.field for finding in findings}
    for field in sorted(stale):
        print(f"CONTENT_PLACEHOLDER_STALE: {format_field(field)}; remove obsolete allowance (issue #{allowances[field].issue})")
    if args.release and new:
        affected = len({finding.field[0] for finding in findings})
        print(
            f"CONTENT_PLACEHOLDERS_RELEASE_BLOCKED: {new} placeholder field(s) "
            f"in {affected} of {files} JSON files; author text required"
        )
        return 1
    if new or stale:
        print(f"CONTENT_PLACEHOLDERS_FAILED: {new} new or changed field(s), {len(stale)} stale allowance(s)")
        return 1
    print(f"CONTENT_PLACEHOLDERS_OK: {files} JSON files checked; {len(findings)} recorded placeholder field(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
