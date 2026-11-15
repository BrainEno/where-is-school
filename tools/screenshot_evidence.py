#!/usr/bin/env python3
"""Say which committed screenshots are evidence of the current game, and which are history.

Issue #186. `docs/screenshots/` kept a frame of the opening that read "Oh - you're up..."
long after the authored line had become "Enjoy your nap, did you?", drawn in a dialogue
box the game no longer has. Nothing was wrong with any single file: CI stopped writing
frames back to Git (#88), so the folder simply stopped moving while the game kept going.
An agent - or a reviewer - who took those frames as the state of the game would rewrite a
line that had already been rewritten, or "fix" a panel that no longer exists.

The cure is not to delete the past but to label it. `docs/screenshots/MANIFEST.json` lists
every frame directly in `docs/screenshots/` and says, per frame:

- ``status: "current"`` - evidence of the game as it is. It must say where it came from
  (``captured.commit``, ``captured.run_id``, ``captured.workflow``), carry the SHA-256 of
  its bytes (so a re-encoded or retouched frame is caught - pixels are not edited by
  hand), declare its size (checked against the image header), and, when it shows a line of
  dialogue, name it: ``shows.source`` / ``conversation`` / ``node`` and the ``text`` that
  was on screen. **That text is compared with the authored file.** Change the opening line
  and this check fails until the frame is captured again or relabelled as history: a frame
  can no longer quietly go out of date.
- ``status: "historical"`` - kept for comparison, not as evidence. It must say why
  (``reason``) and may name the current frame that replaced it (``superseded_by``).

Subfolders belong to their own reviews (``collections``: the folder and the document that
owns it); this tool only checks that each one is declared and that its document exists.

It also checks every Markdown file in the repository for references to a frame under
``docs/screenshots/`` that does not exist (a renamed or retired frame leaves those behind),
and warns when a document cites a historical frame as if it were current (a citation on a
line that itself says "historical" / "历史" is citing history on purpose).

A current dialogue frame also records ``ui_fingerprint``: a hash of the files that draw
the reading band (`UI_FINGERPRINT_FILES`, computed exactly like
`tests/evidence_contract.gd`). When the panel changes after the frame was taken, that is a
warning - the words are still right, the picture of the band may not be. ``--strict`` makes
it an error.

Usage:

    python3 tools/screenshot_evidence.py --check            # CI: fail on any error
    python3 tools/screenshot_evidence.py --check --strict   # warnings fail too
    python3 tools/screenshot_evidence.py --report           # one line per frame

`tools/fetch_dialogue_evidence.py` writes current entries from a relay run with
`apply_relay()`. Standard library only: no engine, no network, no packages.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCREENSHOTS = "docs/screenshots"
MANIFEST_NAME = "MANIFEST.json"
FORMAT_VERSION = 1
IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp")
STATUSES = ("current", "historical")
# Same list, same order as `UI_FINGERPRINT_FILES` in tests/evidence_contract.gd.
UI_FINGERPRINT_FILES = (
    "scenes/ui/dialogue_panel.tscn",
    "scripts/ui/dialogue_panel.gd",
)
SHA_RE = re.compile(r"^[0-9a-f]{7,40}$")
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
# `docs/screenshots/<file>` anywhere in a Markdown file; stops at characters a path here
# never contains. Globs and placeholders are skipped by the caller.
REFERENCE_RE = re.compile(r"docs/screenshots/([A-Za-z0-9_./-]+\.(?:png|jpe?g|webp))")
# `](file.png)` inside a Markdown file that lives in docs/screenshots itself.
RELATIVE_RE = re.compile(r"\]\(([A-Za-z0-9_./-]+\.(?:png|jpe?g|webp))\)")
# Documents in docs/screenshots that index frames by design; citing history there is fine.
INDEX_DOCUMENTS = ("PLAYTHROUGH.md", "README.md", "README.zh-CN.md")
# A citation on a line that uses one of these words already says it is showing the past.
HISTORY_WORDS = ("historical", "历史")


@dataclass
class Result:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    rows: list[tuple[str, str, str, str]] = field(default_factory=list)

    def ok(self, strict: bool = False) -> bool:
        return not self.errors and not (strict and self.warnings)


# --- small readers -------------------------------------------------------------------


def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def image_size(path: Path) -> tuple[int, int] | None:
    """Width and height from a PNG IHDR or a JPEG SOF marker; None for anything else."""
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24 and data[12:16] == b"IHDR":
        width, height = struct.unpack(">II", data[16:24])
        return int(width), int(height)
    if data[:2] == b"\xff\xd8":
        index = 2
        while index + 4 <= len(data):
            if data[index] != 0xFF:
                index += 1
                continue
            marker = data[index + 1]
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
                index += 2
                continue
            length = struct.unpack(">H", data[index + 2 : index + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                if index + 9 > len(data):
                    return None
                height, width = struct.unpack(">HH", data[index + 5 : index + 9])
                return int(width), int(height)
            index += 2 + length
    return None


def ui_fingerprint(root: Path) -> str:
    joined = ""
    for relative in UI_FINGERPRINT_FILES:
        path = root / relative
        digest = sha256_of(path) if path.is_file() else "missing"
        joined += f"{relative}\n{digest}\n"
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()[:16]


def authored_node(root: Path, source: str, conversation: str, node: str) -> tuple[str | None, str]:
    """(text, error). `node` may be empty or "@start" for the conversation's start node."""
    path = root / source
    if not path.is_file():
        return None, f"{source} does not exist"
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return None, f"{source} is not readable JSON ({error})"
    conversations = document.get("conversations") if isinstance(document, dict) else None
    if not isinstance(conversations, dict) or conversation not in conversations:
        return None, f"{source} has no conversation '{conversation}'"
    graph = conversations[conversation]
    wanted = node if node and node != "@start" else str(graph.get("start", ""))
    for entry in graph.get("nodes", []) if isinstance(graph, dict) else []:
        if isinstance(entry, dict) and str(entry.get("id", "")) == wanted:
            return str(entry.get("text", "")), ""
    return None, f"'{conversation}' in {source} has no node '{wanted}'"


def tracked_files(root: Path, folder: str) -> list[str] | None:
    """Paths under `folder` that Git tracks, relative to `root`; None outside a checkout."""
    try:
        completed = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--", folder],
            check=True,
            capture_output=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    if not (root / ".git").exists():
        return None
    return [item for item in completed.stdout.decode("utf-8").split("\0") if item]


def listed_folder(root: Path) -> tuple[list[str], list[str]]:
    """(top-level image files, subfolders) of docs/screenshots: tracked ones in a checkout,
    everything on disk otherwise (tests build plain folders)."""
    base = root / SCREENSHOTS
    tracked = tracked_files(root, SCREENSHOTS)
    images: set[str] = set()
    folders: set[str] = set()
    if tracked is not None:
        for item in tracked:
            rest = item[len(SCREENSHOTS) + 1 :]
            if "/" in rest:
                folders.add(rest.split("/", 1)[0])
            elif rest.lower().endswith(IMAGE_SUFFIXES):
                images.add(rest)
        # A frame added in this working tree but not yet committed is still a frame the
        # next commit will carry; count it too, so `--check` before `git add` is honest.
        for entry in base.iterdir() if base.is_dir() else []:
            if entry.is_file() and entry.name.lower().endswith(IMAGE_SUFFIXES):
                ignored = subprocess.run(
                    ["git", "-C", str(root), "check-ignore", "-q", str(entry)],
                    capture_output=True,
                ).returncode == 0
                if not ignored:
                    images.add(entry.name)
        # Deleted in the working tree but still tracked: the next commit will not carry it.
        images = {name for name in images if (base / name).is_file()}
        folders = {name for name in folders if (base / name).is_dir()}
    elif base.is_dir():
        for entry in base.iterdir():
            if entry.is_dir():
                folders.add(entry.name)
            elif entry.name.lower().endswith(IMAGE_SUFFIXES):
                images.add(entry.name)
    return sorted(images), sorted(folders)


def markdown_files(root: Path) -> list[str]:
    tracked = tracked_files(root, ".")
    if tracked is not None:
        names = [item for item in tracked if item.endswith(".md")]
        return sorted({*names, *(str(p.relative_to(root)) for p in (root / SCREENSHOTS).glob("*.md"))})
    found = []
    for directory, _dirs, files in os.walk(root):
        if "/." in directory.replace(os.sep, "/") + "/":
            continue
        for name in files:
            if name.endswith(".md"):
                found.append(str((Path(directory) / name).relative_to(root)))
    return sorted(found)


def load_manifest(root: Path) -> tuple[dict | None, str]:
    path = root / SCREENSHOTS / MANIFEST_NAME
    if not path.is_file():
        return None, f"{SCREENSHOTS}/{MANIFEST_NAME} does not exist"
    try:
        return json.loads(path.read_text(encoding="utf-8")), ""
    except (OSError, json.JSONDecodeError) as error:
        return None, f"{SCREENSHOTS}/{MANIFEST_NAME} is not valid JSON ({error})"


# --- the check -----------------------------------------------------------------------


def _check_frame(root: Path, frame: dict, by_file: dict[str, dict], result: Result) -> None:
    name = str(frame.get("file", ""))
    status = frame.get("status")
    label = f"{SCREENSHOTS}/{name}"
    path = root / SCREENSHOTS / name
    verdict = "ok"
    if not path.is_file():
        result.errors.append(f"{label}: listed in the manifest but the file does not exist")
        result.rows.append((name, str(status), "-", "missing"))
        return
    captured = frame.get("captured") if isinstance(frame.get("captured"), dict) else {}
    commit = str(captured.get("commit", ""))
    if commit and not SHA_RE.match(commit):
        result.errors.append(f"{label}: captured.commit '{commit}' is not a commit SHA")
    size = frame.get("size")
    if size is not None:
        actual = image_size(path)
        if not (isinstance(size, list) and len(size) == 2 and all(isinstance(v, int) for v in size)):
            result.errors.append(f"{label}: size must be [width, height], not {size!r}")
        elif actual is None:
            result.errors.append(f"{label}: the image header could not be read to check its size")
        elif list(actual) != size:
            result.errors.append(f"{label}: the manifest says {size[0]}x{size[1]}, the file is {actual[0]}x{actual[1]}")
    shows = frame.get("shows") if isinstance(frame.get("shows"), dict) else None
    excerpt = ""
    if shows is not None and shows.get("kind") == "dialogue":
        excerpt = str(shows.get("text", ""))[:40]

    if status == "current":
        if not commit:
            result.errors.append(f"{label}: a current frame must name captured.commit")
        if not isinstance(captured.get("run_id"), int) or captured.get("run_id", 0) <= 0:
            result.errors.append(f"{label}: a current frame must name the CI run that took it (captured.run_id)")
        if not str(captured.get("workflow", "")):
            result.errors.append(f"{label}: a current frame must name its workflow (captured.workflow)")
        if size is None:
            result.errors.append(f"{label}: a current frame must declare its size")
        digest = str(frame.get("sha256", ""))
        if not HEX64_RE.match(digest):
            result.errors.append(f"{label}: a current frame must carry the SHA-256 of its bytes")
        elif digest != sha256_of(path):
            result.errors.append(
                f"{label}: the file is not the one the manifest recorded (SHA-256 differs); "
                "frames are captured, not edited - capture it again"
            )
            verdict = "altered"
        if shows is not None and shows.get("kind") == "dialogue":
            source = str(shows.get("source", ""))
            locale = str(shows.get("locale", ""))
            if locale and f"/{locale}/" not in f"/{source}":
                result.errors.append(f"{label}: shows.source '{source}' is not in the '{locale}' folder")
            text, problem = authored_node(
                root, source, str(shows.get("conversation", "")), str(shows.get("node", ""))
            )
            if text is None:
                result.errors.append(f"{label}: {problem}")
                verdict = "unbound"
            elif text != str(shows.get("text", "")):
                result.errors.append(
                    f"{label}: stale - the frame shows \"{shows.get('text', '')}\" but "
                    f"{source} now says \"{text}\" ({shows.get('conversation')}/{shows.get('node')}). "
                    "Capture it again (Playthrough capture dispatched with relay_dialogue_evidence=true) or mark it historical."
                )
                verdict = "stale"
            recorded = str(frame.get("ui_fingerprint", ""))
            if not recorded:
                result.errors.append(f"{label}: a current dialogue frame must record ui_fingerprint")
            elif recorded != ui_fingerprint(root):
                result.warnings.append(
                    f"{label}: the reading band changed after this frame was taken "
                    f"(ui_fingerprint {recorded} -> {ui_fingerprint(root)}); the words still match"
                )
                if verdict == "ok":
                    verdict = "band changed"
        elif shows is not None:
            result.errors.append(f"{label}: shows.kind '{shows.get('kind')}' is not one this check can verify")
    elif status == "historical":
        if not str(frame.get("reason", "")).strip():
            result.errors.append(f"{label}: a historical frame must say why it is kept (reason)")
        successor = frame.get("superseded_by")
        if successor is not None:
            target = by_file.get(str(successor))
            if target is None:
                result.errors.append(f"{label}: superseded_by '{successor}' is not in the manifest")
            elif target.get("status") != "current":
                result.errors.append(f"{label}: superseded_by '{successor}' is not a current frame")
        verdict = "historical"
        if shows is not None and shows.get("kind") == "dialogue":
            text, _problem = authored_node(
                root, str(shows.get("source", "")), str(shows.get("conversation", "")), str(shows.get("node", ""))
            )
            if text is not None and text != str(shows.get("text", "")):
                result.notes.append(f"{label}: historical, and its line has since changed to \"{text}\"")
    else:
        result.errors.append(f"{label}: status must be one of {', '.join(STATUSES)}, not {status!r}")
        verdict = "invalid"
    result.rows.append((name, str(status), commit[:7] or "-", f"{verdict}  {excerpt}".rstrip()))


def _check_references(root: Path, by_file: dict[str, dict], result: Result) -> None:
    for relative in markdown_files(root):
        path = root / relative
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        in_folder = str(Path(relative).parent).replace(os.sep, "/") == SCREENSHOTS
        found: list[tuple[int, str, bool]] = []
        for number, line in enumerate(text.splitlines(), start=1):
            # A line that itself says the frame is historical is citing it as history.
            labelled = any(word in line.lower() for word in HISTORY_WORDS)
            for match in REFERENCE_RE.finditer(line):
                found.append((number, match.group(1), labelled))
            if in_folder:
                for match in RELATIVE_RE.finditer(line):
                    if "://" not in match.group(1):
                        found.append((number, match.group(1), labelled))
        for number, target, labelled in found:
            if "*" in target or "<" in target:
                continue
            if not (root / SCREENSHOTS / target).is_file():
                result.errors.append(f"{relative}:{number}: refers to {SCREENSHOTS}/{target}, which does not exist")
                continue
            frame = by_file.get(target)
            if (
                frame is not None
                and frame.get("status") == "historical"
                and not labelled
                and not (in_folder and Path(relative).name in INDEX_DOCUMENTS)
            ):
                result.warnings.append(
                    f"{relative}:{number}: cites {target}, which the manifest marks historical "
                    f"({str(frame.get('reason', '')).strip()[:80]})"
                )


def check(root: Path = ROOT) -> Result:
    result = Result()
    manifest, problem = load_manifest(root)
    if manifest is None:
        result.errors.append(problem)
        return result
    if not isinstance(manifest, dict) or manifest.get("format_version") != FORMAT_VERSION:
        result.errors.append(f"{SCREENSHOTS}/{MANIFEST_NAME}: format_version must be {FORMAT_VERSION}")
        return result
    frames = manifest.get("frames")
    collections = manifest.get("collections", [])
    if not isinstance(frames, list) or not isinstance(collections, list):
        result.errors.append(f"{SCREENSHOTS}/{MANIFEST_NAME}: 'frames' and 'collections' must be lists")
        return result

    by_file: dict[str, dict] = {}
    for frame in frames:
        if not isinstance(frame, dict) or not str(frame.get("file", "")):
            result.errors.append(f"{SCREENSHOTS}/{MANIFEST_NAME}: every frame needs a 'file'")
            continue
        name = str(frame["file"])
        if "/" in name or "\\" in name:
            result.errors.append(f"{SCREENSHOTS}/{name}: frames live directly in {SCREENSHOTS}; subfolders are collections")
            continue
        if name in by_file:
            result.errors.append(f"{SCREENSHOTS}/{name}: listed twice in the manifest")
            continue
        by_file[name] = frame

    images, folders = listed_folder(root)
    for name in images:
        if name not in by_file:
            result.errors.append(
                f"{SCREENSHOTS}/{name}: not in {MANIFEST_NAME}; say whether it is current evidence or history"
            )
    declared = {}
    for entry in collections:
        if not isinstance(entry, dict) or not str(entry.get("path", "")):
            result.errors.append(f"{SCREENSHOTS}/{MANIFEST_NAME}: every collection needs a 'path'")
            continue
        declared[str(entry["path"])] = entry
        owner = str(entry.get("owner", ""))
        if not owner or not (root / owner).is_file():
            result.errors.append(f"{SCREENSHOTS}/{entry['path']}/: its owner document '{owner}' does not exist")
        if not (root / SCREENSHOTS / str(entry["path"])).is_dir():
            result.errors.append(f"{SCREENSHOTS}/{entry['path']}/: declared as a collection but missing")
    for folder in folders:
        if folder not in declared:
            result.errors.append(f"{SCREENSHOTS}/{folder}/: a subfolder no collection in {MANIFEST_NAME} declares")

    for name in sorted(by_file):
        _check_frame(root, by_file[name], by_file, result)
    _check_references(root, by_file, result)
    return result


# --- writing current entries from a relay run ----------------------------------------


def apply_relay(
    manifest: dict,
    records: list[dict],
    *,
    run_id: int,
    commit: str,
    workflow: str,
    files: dict[str, str],
    retire: dict[str, str] | None = None,
) -> list[str]:
    """Make each relayed frame a current entry and return what changed.

    `records` are the `EVIDENCE` records the capture printed; `files` maps a record's frame
    name to the file now in docs/screenshots and its SHA-256 (``"name.jpg": sha``). `retire`
    maps an old file name to the new one that replaces it; such an entry is removed when the
    old file is gone, so the manifest never lists a file the tree no longer has.
    """
    frames = manifest.setdefault("frames", [])
    by_file = {str(frame.get("file")): frame for frame in frames if isinstance(frame, dict)}
    changes: list[str] = []
    for record in records:
        frame_name = str(record.get("frame", ""))
        stem = frame_name.rsplit(".", 1)[0] if "." in frame_name else frame_name
        target = next((name for name in files if name.rsplit(".", 1)[0] == stem), None)
        if target is None:
            continue
        entry = by_file.get(target)
        if entry is None:
            entry = {"file": target}
            frames.append(entry)
            by_file[target] = entry
            changes.append(f"added {target}")
        else:
            changes.append(f"refreshed {target}")
        caption = entry.get("caption")
        entry.clear()
        entry.update(
            {
                "file": target,
                "status": "current",
                **({"caption": caption} if caption else {}),
                "captured": {
                    "commit": commit,
                    "run_id": run_id,
                    "workflow": workflow,
                    "godot": str(record.get("godot", "")),
                },
                "size": list(record.get("size", [])),
                "sha256": files[target],
                "ui_fingerprint": str(record.get("ui_fingerprint", "")),
                "shows": dict(record.get("shows", {})),
            }
        )
    for old, new in (retire or {}).items():
        if old in by_file and old != new:
            frames.remove(by_file.pop(old))
            changes.append(f"retired {old} (replaced by {new})")
    frames.sort(key=lambda frame: str(frame.get("file", "")))
    return changes


def write_manifest(root: Path, manifest: dict) -> None:
    path = root / SCREENSHOTS / MANIFEST_NAME
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


# --- command line --------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="fail on any error (CI)")
    mode.add_argument("--report", action="store_true", help="print one line per frame")
    parser.add_argument("--strict", action="store_true", help="treat warnings as errors")
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    result = check(args.root)
    if args.report:
        width = max((len(row[0]) for row in result.rows), default=10)
        print(f"{'frame'.ljust(width)}  {'status':<10}  commit   verdict")
        for name, status, commit, verdict in result.rows:
            print(f"{name.ljust(width)}  {status:<10}  {commit:<7}  {verdict}")
        current = sum(1 for row in result.rows if row[1] == "current")
        print(f"\n{len(result.rows)} frame(s): {current} current, {len(result.rows) - current} historical or invalid")
    for note in result.notes:
        print(f"note: {note}")
    for warning in result.warnings:
        print(f"warning: {warning}")
        if os.environ.get("GITHUB_ACTIONS") == "true":
            print(f"::warning title=screenshot evidence::{warning}")
    for error in result.errors:
        print(f"error: {error}", file=sys.stderr)
        if os.environ.get("GITHUB_ACTIONS") == "true":
            print(f"::error title=screenshot evidence::{error}")
    if result.ok(args.strict):
        print(f"screenshot evidence: {len(result.rows)} frame(s) accounted for, {len(result.warnings)} warning(s)")
        return 0
    print(
        f"screenshot evidence: {len(result.errors)} error(s), {len(result.warnings)} warning(s)",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
