#!/usr/bin/env python3
"""Audit the Godot UID sidecars and declarations the repository tracks (issue #67).

Godot 4.4+ gives every resource a UID. A scene or resource file declares its own in its
header (``[gd_scene ... uid="uid://..."]``), an imported asset in its ``.import`` file, and a
file that has no header of its own - a script, a shader - in a one-line ``<file>.uid``
sidecar next to it. Other files refer to it by that UID first and by path second
(``[ext_resource ... uid="uid://..." path="res://..."]``).

Nothing in CI ever looked at those values. Issue #67 asks for an inventory measured on the
current tree rather than a number carried over from an older comment, and for "missing,
duplicate, stale" to be checked. This tool is the static half of that: it reads every
tracked file and reports.

What it reports, and how seriously:

**Errors** (``--check`` fails):

- *malformed*: a declaration that is not ``uid://`` followed by at least one letter or digit.
  The engine refuses such a value and the file loses its identity.
- *duplicate*: two files that declare the same UID once decoded. The engine keeps one of them
  in its cache; every reference to the other one silently loads the wrong file. Compared by
  the decoded number, not the text, because two different texts can decode to the same number
  (see *non-canonical*).
- *orphan*: a ``.uid`` sidecar whose file is gone (a script deleted or moved without it). It
  declares a UID for nothing.

**Findings** (reported, never fail on their own):

- *non-canonical*: a value the engine accepts but would never write. Godot writes UIDs in
  base 34 with the characters ``a``-``y`` and ``0``-``8`` (``core/io/resource_uid.cpp``), but
  its parser also takes ``z`` (read as 25, the same digit as ``0``) and ``9`` (read as 34, which
  carries), and a 13-character value past ``uid://d4n4ub6itg400`` wraps and is masked to 63
  bits instead of being refused. Hand-minted values do all three; they work, but they are
  read as a different number than they look like, the next editor save rewrites the text,
  and ``...z...`` and ``...0...`` are the same UID.
- *stale reference*: an ``ext_resource`` whose UID no tracked file declares (the engine falls
  back to the path and prints a warning on every load), or whose UID is declared by a
  different file than its ``path`` names (the engine loads the UID's file, not the path's).
- *missing sidecar*: a tracked script or shader with no ``.uid`` next to it. Not an error by
  design: issue #67 says only the sidecars the engine actually asks for belong in the
  repository, and which ones it asks for is measured by an import, not decided here. See
  ``--after-import``.

``--after-import`` is the measured half. Run after ``godot --headless --import`` on a clean
checkout, it reads ``git status`` and lists every ``.uid`` file the engine created (with the
value it chose, so it can be committed as the engine wrote it rather than re-minted) and
every tracked UID-bearing file the import rewrote. ``.github/workflows/engine-hygiene-audit.yml``
runs it.

Usage:

    python3 tools/godot_sidecars.py --check            # CI: fail on errors, print findings
    python3 tools/godot_sidecars.py --report           # Markdown inventory on stdout
    python3 tools/godot_sidecars.py --after-import     # after an engine import, in CI
    python3 tools/godot_sidecars.py --check --github   # also emit ::error/::warning lines

Standard library only, so it runs before anything is installed.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PREFIX = "uid://"
# `core/io/resource_uid.cpp`: the characters `id_to_text` writes, in digit order.
ALPHABET = "abcdefghijklmnopqrstuvwxy012345678"
BASE = len(ALPHABET)  # 34
# `char_count` in the engine: what a digit character is offset by when parsed.
CHAR_COUNT = ord("z") - ord("a")  # 25
MAX_ID = (1 << 63) - 1

# Files whose own header can declare a UID.
HEADER_SUFFIXES = (".tscn", ".tres")
# Files that get a `.uid` sidecar from the engine instead (they have no header).
SIDECAR_SUFFIXES = (".gd", ".gdshader", ".gdshaderinc")

HEADER_RE = re.compile(r'^\[gd_(?:scene|resource)\b[^\]]*?\buid="([^"]*)"')
EXT_RESOURCE_RE = re.compile(r"^\[ext_resource\b([^\]]*)\]")
ATTR_RE = re.compile(r'(\w+)="([^"]*)"')
IMPORT_UID_RE = re.compile(r'^uid="([^"]*)"\s*$')


# --- The engine's text form ------------------------------------------------


def decode(text: str) -> int | None:
    """The engine's `text_to_id`: the number it reads, or None when it refuses the text.

    Mirrored exactly, overflow included: the engine accumulates in an unsigned 64-bit
    integer (which wraps) and masks the result to 63 bits, so a 13-character value past
    `uid://d4n4ub6itg400` is not refused - it is read as some other number. Whether a text
    is the one the engine would have written for that number is `is_canonical()`'s question.
    """
    if not text.startswith(PREFIX) or text == PREFIX + "<invalid>":
        return None
    digits = text[len(PREFIX):]
    if not digits:
        # The engine reads an empty value as 0, a UID it never assigns; nothing in a
        # project should declare it.
        return None
    value = 0
    for char in digits:
        value *= BASE
        if "a" <= char <= "z":
            value += ord(char) - ord("a")
        elif "0" <= char <= "9":
            value += ord(char) - ord("0") + CHAR_COUNT
        else:
            return None
        value &= (1 << 64) - 1
    return value & MAX_ID


def encode(value: int) -> str:
    """The engine's `id_to_text`: the only form it ever writes."""
    if value < 0:
        return PREFIX + "<invalid>"
    digits = []
    while True:
        digits.append(ALPHABET[value % BASE])
        value //= BASE
        if value == 0:
            break
    return PREFIX + "".join(reversed(digits))


def is_canonical(text: str) -> bool:
    value = decode(text)
    return value is not None and encode(value) == text


# --- Reading the tree --------------------------------------------------------


@dataclass
class Declaration:
    """One file saying "this is my UID"."""

    owner: str  # the resource the UID names, relative to the root
    source: str  # the file the text was read from (the owner, its .import or its .uid)
    text: str
    value: int | None


@dataclass
class Reference:
    """One `ext_resource` naming another resource by UID and path."""

    source: str
    text: str
    path: str  # res:// stripped


@dataclass
class Inventory:
    declarations: list[Declaration] = field(default_factory=list)
    references: list[Reference] = field(default_factory=list)
    sidecar_candidates: list[str] = field(default_factory=list)
    orphans: list[str] = field(default_factory=list)


def tracked_files(root: str) -> list[str]:
    """Tracked files, relative and with `/`. Outside git, every file under the root
    except `.godot/` and `.git/` (the tests build such trees)."""
    try:
        out = subprocess.run(
            ["git", "-C", root, "ls-files", "-z"],
            check=True, capture_output=True,
        ).stdout
        files = [name for name in out.decode("utf-8").split("\0") if name]
        if files:
            return sorted(files)
    except (OSError, subprocess.CalledProcessError):
        pass
    found = []
    for directory, subdirs, names in os.walk(root):
        subdirs[:] = [d for d in subdirs if d not in (".git", ".godot")]
        for name in names:
            found.append(os.path.relpath(os.path.join(directory, name), root).replace(os.sep, "/"))
    return sorted(found)


def _read_text(root: str, rel: str) -> str:
    try:
        with open(os.path.join(root, rel), encoding="utf-8") as handle:
            return handle.read()
    except (OSError, UnicodeDecodeError):
        return ""


def read_inventory(root: str, files: list[str] | None = None) -> Inventory:
    files = tracked_files(root) if files is None else files
    present = set(files)
    inventory = Inventory()
    for rel in files:
        if rel.endswith(".uid"):
            owner = rel[: -len(".uid")]
            text = _read_text(root, rel).strip()
            inventory.declarations.append(Declaration(owner, rel, text, decode(text)))
            if owner not in present and not os.path.exists(os.path.join(root, owner)):
                inventory.orphans.append(rel)
        elif rel.endswith(".import"):
            owner = rel[: -len(".import")]
            for line in _read_text(root, rel).splitlines():
                match = IMPORT_UID_RE.match(line.strip())
                if match:
                    text = match.group(1)
                    inventory.declarations.append(Declaration(owner, rel, text, decode(text)))
                    break
        elif rel.endswith(HEADER_SUFFIXES):
            _read_resource(root, rel, inventory)
        if rel.endswith(SIDECAR_SUFFIXES):
            inventory.sidecar_candidates.append(rel)
    return inventory


def _read_resource(root: str, rel: str, inventory: Inventory) -> None:
    lines = _read_text(root, rel).splitlines()
    if not lines:
        return
    header = HEADER_RE.match(lines[0])
    if header:
        text = header.group(1)
        inventory.declarations.append(Declaration(rel, rel, text, decode(text)))
    for line in lines[1:]:
        if line.startswith("[") and not line.startswith("[ext_resource"):
            # External resources come first in a text resource; the first other section
            # ends them, and nothing after it is a reference with a UID.
            if line.startswith(("[sub_resource", "[node", "[resource", "[connection")):
                break
            continue
        match = EXT_RESOURCE_RE.match(line)
        if not match:
            continue
        attrs = dict(ATTR_RE.findall(match.group(1)))
        uid = attrs.get("uid", "")
        if not uid:
            continue
        path = attrs.get("path", "")
        if path.startswith("res://"):
            path = path[len("res://"):]
        inventory.references.append(Reference(rel, uid, path))


# --- Findings ---------------------------------------------------------------


@dataclass
class Audit:
    malformed: list[Declaration] = field(default_factory=list)
    duplicates: dict[int, list[Declaration]] = field(default_factory=dict)
    orphans: list[str] = field(default_factory=list)
    non_canonical: list[Declaration] = field(default_factory=list)
    unknown_references: list[Reference] = field(default_factory=list)
    mismatched_references: list[tuple[Reference, Declaration]] = field(default_factory=list)
    missing_sidecars: list[str] = field(default_factory=list)
    declared: int = 0
    referenced: int = 0
    candidates: int = 0

    @property
    def errors(self) -> int:
        return len(self.malformed) + len(self.duplicates) + len(self.orphans)


def audit(inventory: Inventory) -> Audit:
    result = Audit(
        declared=len(inventory.declarations),
        referenced=len(inventory.references),
        candidates=len(inventory.sidecar_candidates),
        orphans=sorted(inventory.orphans),
    )
    by_value: dict[int, list[Declaration]] = {}
    for declaration in inventory.declarations:
        if declaration.value is None:
            result.malformed.append(declaration)
            continue
        by_value.setdefault(declaration.value, []).append(declaration)
        if not is_canonical(declaration.text):
            result.non_canonical.append(declaration)
    for value, owners in by_value.items():
        # The same owner declared twice (a scene header and a stray sidecar with the same
        # value) is one identity, not a collision; two owners is a collision.
        if len({d.owner for d in owners}) > 1:
            result.duplicates[value] = sorted(owners, key=lambda d: d.source)
    owner_of = {value: owners[0] for value, owners in by_value.items()}
    for reference in inventory.references:
        value = decode(reference.text)
        declaration = owner_of.get(value) if value is not None else None
        if declaration is None:
            result.unknown_references.append(reference)
        elif reference.path and declaration.owner != reference.path:
            result.mismatched_references.append((reference, declaration))
    has_sidecar = {d.owner for d in inventory.declarations if d.source.endswith(".uid")}
    result.missing_sidecars = sorted(
        rel for rel in inventory.sidecar_candidates if rel not in has_sidecar
    )
    result.non_canonical.sort(key=lambda d: d.source)
    return result


# --- After an engine import -------------------------------------------------


@dataclass
class Rewrite:
    """One tracked UID-bearing file the import changed, and how."""

    path: str
    uid_before: str  # "" when the committed file declared none
    uid_after: str
    changed_keys: list[str] = field(default_factory=list)  # "[section] key", sorted

    @property
    def uid_changed(self) -> bool:
        return self.uid_before != self.uid_after

    def describe(self) -> str:
        if self.uid_changed:
            uid = "uid %s -> %s" % (self.uid_before or "(none)", self.uid_after or "(none)")
        else:
            uid = "uid kept"
        keys = ", ".join(self.changed_keys) if self.changed_keys else "no key changed"
        return "%s: %s; %s" % (self.path, uid, keys)


@dataclass
class ImportDelta:
    created: list[tuple[str, str]] = field(default_factory=list)  # (sidecar, value)
    rewritten: list[Rewrite] = field(default_factory=list)
    still_missing: list[str] = field(default_factory=list)


UID_BEARING = (".uid", ".import") + HEADER_SUFFIXES


def git_status(root: str) -> list[tuple[str, str]]:
    """`(code, path)` for every changed or untracked path, `.godot/` excluded."""
    out = subprocess.run(
        ["git", "-C", root, "status", "--porcelain=v1", "--untracked-files=all", "-z"],
        check=True, capture_output=True,
    ).stdout.decode("utf-8")
    entries = []
    for item in out.split("\0"):
        if len(item) < 4:
            continue
        code, path = item[:2], item[3:]
        if path.startswith(".godot/"):
            continue
        entries.append((code, path))
    return entries


def _declared_uid(rel: str, text: str) -> str:
    """The UID a file's own text declares, or "" (sidecar, `.import` or resource header)."""
    if rel.endswith(".uid"):
        return text.strip()
    for line in text.splitlines():
        match = IMPORT_UID_RE.match(line) if rel.endswith(".import") else HEADER_RE.match(line)
        if match:
            return match.group(1)
    return ""


def _keyed_lines(text: str) -> dict[str, str]:
    """`"[section] key"` -> value for an INI-like Godot file (`.import`, `.tscn` header).

    A key repeated in one section keeps its last value; lines that are not `key=value`
    (headers of `.tscn` nodes, blank lines) only change the section.
    """
    section = ""
    lines: dict[str, str] = {}
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            section = stripped.split()[0].strip("[]")
            continue
        key, sep, value = stripped.partition("=")
        if sep and key and " " not in key:
            lines["[%s] %s" % (section, key)] = value
    return lines


def committed_text(root: str, rel: str) -> str:
    """`rel` as HEAD has it, or "" when it is not in HEAD."""
    result = subprocess.run(
        ["git", "-C", root, "show", "HEAD:" + rel], capture_output=True, check=False
    )
    return result.stdout.decode("utf-8", errors="replace") if result.returncode == 0 else ""


def describe_rewrite(rel: str, before: str, after: str) -> Rewrite:
    """What changed between the committed and the imported text of one file."""
    old, new = _keyed_lines(before), _keyed_lines(after)
    changed = sorted(key for key in set(old) | set(new) if old.get(key) != new.get(key))
    return Rewrite(rel, _declared_uid(rel, before), _declared_uid(rel, after), changed)


def import_delta(root: str, status: list[tuple[str, str]]) -> ImportDelta:
    delta = ImportDelta()
    created_owners = set()
    for code, path in sorted(status, key=lambda entry: entry[1]):
        if code == "??" and path.endswith(".uid"):
            delta.created.append((path, _read_text(root, path).strip()))
            created_owners.add(path[: -len(".uid")])
        elif code != "??" and path.endswith(UID_BEARING):
            delta.rewritten.append(
                describe_rewrite(path, committed_text(root, path), _read_text(root, path))
            )
    inventory = read_inventory(root)
    before = audit(inventory).missing_sidecars
    delta.still_missing = [rel for rel in before if rel not in created_owners]
    return delta


# --- Output -----------------------------------------------------------------


def _github(kind: str, title: str, message: str) -> str:
    message = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    return "::%s title=%s::%s" % (kind, title, message)


def format_check(result: Audit, github: bool) -> list[str]:
    lines = [
        "UID declarations: %d; ext_resource UID references: %d; scripts/shaders: %d"
        % (result.declared, result.referenced, result.candidates)
    ]
    for declaration in result.malformed:
        line = "MALFORMED %s: %r is not a UID the engine accepts" % (declaration.source, declaration.text)
        lines.append(line)
        if github:
            lines.append(_github("error", "UID malformed", line))
    for value, owners in sorted(result.duplicates.items()):
        line = "DUPLICATE %s is declared by %s" % (
            encode(value), ", ".join("%s (%s)" % (d.source, d.text) for d in owners)
        )
        lines.append(line)
        if github:
            lines.append(_github("error", "UID duplicate", line))
    for orphan in result.orphans:
        line = "ORPHAN %s: its file %s is not in the tree" % (orphan, orphan[: -len(".uid")])
        lines.append(line)
        if github:
            lines.append(_github("error", "UID orphan", line))
    lines.append(
        "findings: %d non-canonical value(s), %d reference(s) to an undeclared UID, "
        "%d reference(s) whose UID names another file, %d script/shader file(s) without a sidecar"
        % (
            len(result.non_canonical), len(result.unknown_references),
            len(result.mismatched_references), len(result.missing_sidecars),
        )
    )
    for declaration in result.non_canonical:
        lines.append("  non-canonical %s: %s (the engine writes %s)" % (
            declaration.source, declaration.text, encode(declaration.value or 0)
        ))
    for reference in result.unknown_references:
        lines.append("  undeclared %s -> %s (%s)" % (reference.source, reference.text, reference.path))
    for reference, declaration in result.mismatched_references:
        lines.append("  mismatched %s -> %s names %s, but %s declares it" % (
            reference.source, reference.text, reference.path, declaration.source
        ))
    for rel in result.missing_sidecars:
        lines.append("  no sidecar %s" % rel)
    if github and (result.unknown_references or result.mismatched_references):
        lines.append(_github(
            "warning", "UID references",
            "%d undeclared, %d pointing at another file (see the step log)"
            % (len(result.unknown_references), len(result.mismatched_references)),
        ))
    lines.append("UID_AUDIT=%s" % ("failure" if result.errors else "success"))
    return lines


def format_report(result: Audit) -> list[str]:
    lines = [
        "# UID inventory",
        "",
        "| What | Count |",
        "|---|---:|",
        "| UID declarations (headers, `.import`, `.uid`) | %d |" % result.declared,
        "| `ext_resource` UID references | %d |" % result.referenced,
        "| Tracked scripts and shaders | %d |" % result.candidates,
        "| ... without a `.uid` sidecar | %d |" % len(result.missing_sidecars),
        "| Malformed / duplicate / orphan (errors) | %d / %d / %d |" % (
            len(result.malformed), len(result.duplicates), len(result.orphans)
        ),
        "| Non-canonical values | %d |" % len(result.non_canonical),
        "| References to an undeclared UID | %d |" % len(result.unknown_references),
        "| References whose UID names another file | %d |" % len(result.mismatched_references),
        "",
    ]
    if result.missing_sidecars:
        lines += ["## Without a sidecar", ""] + ["- `%s`" % rel for rel in result.missing_sidecars] + [""]
    if result.non_canonical:
        lines += ["## Non-canonical values", ""]
        lines += [
            "- `%s`: `%s` (engine form `%s`)" % (d.source, d.text, encode(d.value or 0))
            for d in result.non_canonical
        ]
        lines.append("")
    return lines


def chunked_notices(title: str, items: list[str], limit: int = 2400) -> list[str]:
    """`items` as as few notice annotations as fit, each under `limit` characters.

    A runner keeps only about ten notices from one step, so one notice per file would lose
    most of a 50-file list; an annotation holds about 4 KB, so they are packed instead, and
    numbered `i/n` so a reader knows when they have all of them.
    """
    if not items:
        return []
    chunks: list[list[str]] = [[]]
    size = 0
    for item in items:
        if chunks[-1] and size + len(item) + 2 > limit:
            chunks.append([])
            size = 0
        chunks[-1].append(item)
        size += len(item) + 2
    return [
        _github("notice", "%s %d/%d" % (title, index + 1, len(chunks)), "; ".join(chunk))
        for index, chunk in enumerate(chunks)
    ]


def format_delta(delta: ImportDelta, github: bool) -> list[str]:
    lines = [
        "after the import: %d sidecar(s) created by the engine, %d tracked UID file(s) "
        "rewritten, %d script/shader file(s) still without one"
        % (len(delta.created), len(delta.rewritten), len(delta.still_missing))
    ]
    lines += ["CREATED %s %s" % (path, value) for path, value in delta.created]
    lines += ["REWRITTEN %s" % rewrite.describe() for rewrite in delta.rewritten]
    lines += ["NOT REQUESTED %s" % path for path in delta.still_missing]
    if github:
        uid_changes = [rewrite for rewrite in delta.rewritten if rewrite.uid_changed]
        lines.append(_github(
            "notice", "UID sidecars after import",
            "%d created, %d rewritten (%d with a new uid), %d not requested by the engine"
            % (
                len(delta.created), len(delta.rewritten), len(uid_changes),
                len(delta.still_missing),
            ),
        ))
        lines += chunked_notices(
            "engine sidecars", ["%s=%s" % (path, value) for path, value in delta.created]
        )
        lines += chunked_notices(
            "import rewrote", [rewrite.describe() for rewrite in delta.rewritten]
        )
        lines += chunked_notices("sidecar not requested", delta.still_missing)
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="fail on malformed, duplicate or orphan UIDs")
    mode.add_argument("--report", action="store_true", help="print the inventory as Markdown")
    mode.add_argument("--after-import", action="store_true", help="list what an engine import changed")
    parser.add_argument("--github", action="store_true", help="also print GitHub annotations")
    parser.add_argument("--root", default=ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    if args.after_import:
        delta = import_delta(args.root, git_status(args.root))
        print("\n".join(format_delta(delta, args.github)))
        return 0
    result = audit(read_inventory(args.root))
    if args.report:
        print("\n".join(format_report(result)))
        return 0
    print("\n".join(format_check(result, args.github)))
    return 1 if result.errors else 0


if __name__ == "__main__":
    sys.exit(main())
