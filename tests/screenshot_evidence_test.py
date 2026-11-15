#!/usr/bin/env python3
"""Tests for ``tools/screenshot_evidence.py`` and ``tools/dialogue_evidence_relay.py`` (#186).

The checker exists because a frame went out of date without anything failing, so the
first thing tested is that it fails: in folders this file builds, with a manifest, a
dialogue file, the two files that draw the reading band, and tiny images whose bytes are
known.

- a current frame whose line is still the authored one passes; rewrite the line and the
  same manifest fails, naming the frame, the old text and the new one;
- every way a current frame can stop being evidence fails: a node or conversation that is
  gone, a changed byte (SHA-256), a size that is not the file's, no run, a source outside
  its locale folder;
- the folder and the manifest must agree: an unlisted frame, a listed file that is not
  there, a frame listed twice, an undeclared subfolder, a collection without its document;
- history must say why, and may only point at a current successor;
- a changed reading band is a warning, and an error under ``--strict``;
- Markdown that names a missing frame fails; citing history outside the index documents
  warns;
- the image readers, and the band fingerprint against the list in
  `tests/evidence_contract.gd` (the two languages must hash the same files in the same
  order, or a frame recorded by the game would never match the checker);
- the relay: parts survive being shuffled, a missing part or a changed byte is refused,
  `pack` refuses a frame without its record or of the wrong size, `frames.json` travels
  first, and `apply_relay` records current frames and retires the PNGs they replace;
- the repository itself passes.

Run it with ``python3 tests/screenshot_evidence_test.py`` (CI does). Standard library only.
"""

from __future__ import annotations

import base64
import copy
import hashlib
import json
import random
import re
import struct
import sys
import tempfile
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

import dialogue_evidence_relay as relay  # noqa: E402
import screenshot_evidence as evidence  # noqa: E402

FAILURES: list[str] = []
CHECKS = 0

LINE_EN = "A line the opening starts with."
LINE_ZH = "开场的第一句。"


def expect(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


def has(messages: list[str], *needles: str) -> bool:
    return any(all(needle in message for needle in needles) for message in messages)


# --- fixtures ------------------------------------------------------------------------


def png_bytes(width: int, height: int, shade: int = 0) -> bytes:
    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes([shade]) * width for _ in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


def jpeg_bytes(width: int, height: int, filler: bytes = b"") -> bytes:
    """Enough of a baseline JPEG for a header reader: SOI, an APP0, SOF0, EOI."""
    app0 = b"\xff\xe0" + struct.pack(">H", 16) + b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
    sof = b"\xff\xc0" + struct.pack(">HBHHB", 11, 8, height, width, 1) + b"\x01\x11\x00"
    return b"\xff\xd8" + app0 + sof + filler + b"\xff\xd9"


def dialogue_file(text: str) -> dict:
    return {
        "format_version": 1,
        "conversations": {
            "q_wake": {
                "start": "q_1",
                "nodes": [
                    {"id": "q_1", "speaker": "q", "text": text, "next": "p_2"},
                    {"id": "p_2", "speaker": "protagonist", "text": "Second."},
                ],
            }
        },
    }


class Fixture:
    def __init__(self) -> None:
        self._dir = tempfile.TemporaryDirectory()
        self.root = Path(self._dir.name)
        self.shots = self.root / evidence.SCREENSHOTS
        self.shots.mkdir(parents=True)
        for relative, body in (
            ("scenes/ui/dialogue_panel.tscn", "[gd_scene format=3]\n"),
            ("scripts/ui/dialogue_panel.gd", "extends Control\n"),
        ):
            (self.root / relative).parent.mkdir(parents=True, exist_ok=True)
            (self.root / relative).write_text(body, encoding="utf-8")
        self.write_line("en", LINE_EN)
        self.write_line("zh-CN", LINE_ZH)
        (self.shots / "now-en.png").write_bytes(png_bytes(8, 4))
        (self.shots / "now-zh.jpg").write_bytes(jpeg_bytes(16, 9))
        (self.shots / "old.png").write_bytes(png_bytes(4, 4, 200))
        self.manifest = {
            "format_version": 1,
            "collections": [],
            "frames": [
                self.current("now-en.png", [8, 4], "en", LINE_EN),
                self.current("now-zh.jpg", [16, 9], "zh-CN", LINE_ZH),
                {
                    "file": "old.png",
                    "status": "historical",
                    "reason": "taken before the band changed",
                    "superseded_by": "now-en.png",
                    "captured": {"commit": "359ed4a"},
                },
            ],
        }
        self.save()

    def current(self, name: str, size: list[int], locale: str, text: str) -> dict:
        return {
            "file": name,
            "status": "current",
            "captured": {"commit": "a" * 40, "run_id": 42, "workflow": "Dialogue evidence relay"},
            "size": size,
            "sha256": hashlib.sha256((self.shots / name).read_bytes()).hexdigest(),
            "ui_fingerprint": evidence.ui_fingerprint(self.root),
            "shows": {
                "kind": "dialogue",
                "locale": locale,
                "source": f"data/dialogue/{locale}/prologue.json",
                "conversation": "q_wake",
                "node": "q_1",
                "text": text,
            },
        }

    def write_line(self, locale: str, text: str) -> None:
        path = self.root / "data" / "dialogue" / locale / "prologue.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(dialogue_file(text), ensure_ascii=False), encoding="utf-8")

    def frame(self, name: str) -> dict:
        return next(frame for frame in self.manifest["frames"] if frame["file"] == name)

    def save(self) -> None:
        evidence.write_manifest(self.root, self.manifest)

    def check(self) -> evidence.Result:
        self.save()
        return evidence.check(self.root)

    def close(self) -> None:
        self._dir.cleanup()


def with_fixture(test):
    def run() -> None:
        fixture = Fixture()
        try:
            test(fixture)
        finally:
            fixture.close()

    run.__name__ = test.__name__
    return run


# --- the check -----------------------------------------------------------------------


@with_fixture
def a_true_manifest_passes(fx: Fixture) -> None:
    result = fx.check()
    expect(result.ok(strict=True), f"a manifest that matches everything failed: {result.errors + result.warnings}")
    expect(len(result.rows) == 3, f"three frames should be reported, got {len(result.rows)}")


@with_fixture
def a_rewritten_line_makes_the_frame_stale(fx: Fixture) -> None:
    fx.write_line("en", "A different first line.")
    result = fx.check()
    expect(not result.ok(), "the frame of a rewritten line still passed")
    expect(
        has(result.errors, "now-en.png", "stale", LINE_EN, "A different first line."),
        f"the stale error should name the frame, the old and the new text: {result.errors}",
    )
    expect(not has(result.errors, "now-zh.jpg"), "the untouched Chinese frame was reported too")


@with_fixture
def a_missing_node_or_conversation_fails(fx: Fixture) -> None:
    fx.frame("now-en.png")["shows"]["node"] = "q_gone"
    result = fx.check()
    expect(has(result.errors, "now-en.png", "no node 'q_gone'"), f"a missing node was not reported: {result.errors}")
    fx.frame("now-en.png")["shows"]["node"] = "q_1"
    fx.frame("now-en.png")["shows"]["conversation"] = "q_elsewhere"
    result = fx.check()
    expect(has(result.errors, "no conversation 'q_elsewhere'"), f"a missing conversation passed: {result.errors}")


@with_fixture
def the_start_marker_follows_the_conversation(fx: Fixture) -> None:
    fx.frame("now-en.png")["shows"]["node"] = "@start"
    expect(fx.check().ok(), "@start did not resolve to the conversation's start node")
    document = dialogue_file(LINE_EN)
    document["conversations"]["q_wake"]["start"] = "p_2"
    (fx.root / "data/dialogue/en/prologue.json").write_text(json.dumps(document), encoding="utf-8")
    expect(has(fx.check().errors, "now-en.png", "stale"), "moving the start node did not make an @start frame stale")


@with_fixture
def a_changed_byte_is_caught(fx: Fixture) -> None:
    (fx.shots / "now-en.png").write_bytes(png_bytes(8, 4, shade=9))
    result = fx.check()
    expect(has(result.errors, "now-en.png", "SHA-256"), f"a retouched frame passed: {result.errors}")


@with_fixture
def a_wrong_size_is_caught(fx: Fixture) -> None:
    fx.frame("now-zh.jpg")["size"] = [1600, 900]
    result = fx.check()
    expect(has(result.errors, "now-zh.jpg", "1600x900", "16x9"), f"a wrong size passed: {result.errors}")
    fx.frame("now-zh.jpg")["size"] = "16x9"
    expect(has(fx.check().errors, "size must be [width, height]"), "a malformed size passed")


@with_fixture
def a_current_frame_must_say_where_it_came_from(fx: Fixture) -> None:
    frame = fx.frame("now-en.png")
    del frame["captured"]["run_id"]
    frame["captured"]["workflow"] = ""
    del frame["sha256"]
    result = fx.check()
    for needle in ("captured.run_id", "captured.workflow", "SHA-256 of its bytes"):
        expect(has(result.errors, "now-en.png", needle), f"a current frame without {needle} passed: {result.errors}")
    frame["captured"]["commit"] = "not-a-sha"
    expect(has(fx.check().errors, "'not-a-sha' is not a commit SHA"), "a malformed commit passed")


@with_fixture
def the_source_must_be_in_its_locale(fx: Fixture) -> None:
    fx.frame("now-zh.jpg")["shows"]["source"] = "data/dialogue/en/prologue.json"
    result = fx.check()
    expect(has(result.errors, "now-zh.jpg", "not in the 'zh-CN' folder"), f"a cross-locale source passed: {result.errors}")


@with_fixture
def folder_and_manifest_must_agree(fx: Fixture) -> None:
    (fx.shots / "stray.png").write_bytes(png_bytes(2, 2))
    fx.manifest["frames"].append({"file": "gone.png", "status": "historical", "reason": "x"})
    fx.manifest["frames"].append(copy.deepcopy(fx.frame("old.png")))
    result = fx.check()
    expect(has(result.errors, "stray.png", "not in MANIFEST.json"), f"an unlisted frame passed: {result.errors}")
    expect(has(result.errors, "gone.png", "does not exist"), f"a listed missing file passed: {result.errors}")
    expect(has(result.errors, "old.png", "listed twice"), f"a duplicate entry passed: {result.errors}")
    expect(any(row[0] == "gone.png" and "missing" in row[3] for row in result.rows), "the report hid the missing file")


@with_fixture
def subfolders_must_be_declared_collections(fx: Fixture) -> None:
    (fx.shots / "review").mkdir()
    result = fx.check()
    expect(has(result.errors, "review/", "no collection"), f"an undeclared subfolder passed: {result.errors}")
    fx.manifest["collections"] = [{"path": "review", "owner": "docs/screenshots/review/README.md"}]
    expect(has(fx.check().errors, "owner document"), "a collection without its document passed")
    (fx.shots / "review" / "README.md").write_text("# Review\n", encoding="utf-8")
    expect(fx.check().ok(), f"a declared, documented collection failed: {fx.check().errors}")
    fx.manifest["frames"].append({"file": "review/a.png", "status": "historical", "reason": "x"})
    expect(has(fx.check().errors, "subfolders are collections"), "a frame inside a collection was accepted")


@with_fixture
def history_must_say_why(fx: Fixture) -> None:
    old = fx.frame("old.png")
    old["reason"] = "  "
    expect(has(fx.check().errors, "old.png", "must say why"), "a historical frame without a reason passed")
    old["reason"] = "kept for comparison"
    old["superseded_by"] = "nowhere.png"
    expect(has(fx.check().errors, "'nowhere.png' is not in the manifest"), "a missing successor passed")
    old["superseded_by"] = "old.png"
    expect(has(fx.check().errors, "is not a current frame"), "a historical successor passed")
    old["status"] = "maybe"
    expect(has(fx.check().errors, "status must be one of"), "an unknown status passed")


@with_fixture
def history_may_keep_an_old_line(fx: Fixture) -> None:
    old = fx.frame("old.png")
    old["shows"] = {
        "kind": "dialogue",
        "locale": "en",
        "source": "data/dialogue/en/prologue.json",
        "conversation": "q_wake",
        "node": "q_1",
        "text": "An older draft of the line.",
    }
    result = fx.check()
    expect(result.ok(), f"history that shows an old line failed: {result.errors}")
    expect(has(result.notes, "old.png", LINE_EN), "the note should say what the line is now")


@with_fixture
def a_changed_band_warns_and_strict_fails(fx: Fixture) -> None:
    (fx.root / "scripts/ui/dialogue_panel.gd").write_text("extends Control\n# moved\n", encoding="utf-8")
    result = fx.check()
    expect(result.ok(strict=False), f"a changed band failed without --strict: {result.errors}")
    expect(has(result.warnings, "now-en.png", "reading band changed"), f"a changed band did not warn: {result.warnings}")
    expect(not result.ok(strict=True), "a changed band passed under --strict")
    del fx.frame("now-en.png")["ui_fingerprint"]
    expect(has(fx.check().errors, "must record ui_fingerprint"), "a dialogue frame without a fingerprint passed")


@with_fixture
def markdown_references_are_checked(fx: Fixture) -> None:
    docs = fx.root / "docs"
    (docs / "NOTES.md").write_text(
        "See docs/screenshots/now-en.png and docs/screenshots/vanished.png.\n"
        "The old one: docs/screenshots/old.png. Globs are skipped: docs/screenshots/ui-*.png\n"
        "Before the fix, the historical frame docs/screenshots/old.png showed it.\n",
        encoding="utf-8",
    )
    (fx.shots / "PLAYTHROUGH.md").write_text("![old](old.png)\n![gone](gone-too.png)\n", encoding="utf-8")
    result = fx.check()
    expect(has(result.errors, "docs/NOTES.md:1", "vanished.png"), f"a reference to a missing frame passed: {result.errors}")
    expect(has(result.errors, "PLAYTHROUGH.md:2", "gone-too.png"), f"a relative reference was not checked: {result.errors}")
    expect(has(result.warnings, "docs/NOTES.md:2", "old.png", "historical"), f"citing history did not warn: {result.warnings}")
    expect(not has(result.warnings, "PLAYTHROUGH.md"), "the index document was warned for listing history")
    expect(not has(result.warnings, "docs/NOTES.md:3"), "a citation that says 'historical' was still warned")
    expect(not has(result.errors, "ui-*"), "a glob was treated as a reference")


@with_fixture
def a_broken_manifest_is_reported(fx: Fixture) -> None:
    (fx.shots / evidence.MANIFEST_NAME).write_text("{ not json", encoding="utf-8")
    expect(has(evidence.check(fx.root).errors, "not valid JSON"), "a broken manifest passed")
    fx.manifest["format_version"] = 2
    expect(has(fx.check().errors, "format_version"), "an unknown format version passed")
    (fx.shots / evidence.MANIFEST_NAME).unlink()
    expect(has(evidence.check(fx.root).errors, "does not exist"), "a missing manifest passed")


def image_readers() -> None:
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "f"
        path.write_bytes(png_bytes(1600, 1))
        expect(evidence.image_size(path) == (1600, 1), "the PNG reader got the size wrong")
        path.write_bytes(jpeg_bytes(1920, 1080))
        expect(evidence.image_size(path) == (1920, 1080), "the JPEG reader got the size wrong")
        path.write_bytes(b"GIF89a....")
        expect(evidence.image_size(path) is None, "an unknown format was given a size")


def fingerprint_matches_the_game() -> None:
    source = (REPO / "tests" / "evidence_contract.gd").read_text(encoding="utf-8")
    block = re.search(r"UI_FINGERPRINT_FILES: Array\[String\] = \[(.*?)\]", source, re.S)
    listed = tuple(re.findall(r'"([^"]+)"', block.group(1))) if block else ()
    expect(listed == evidence.UI_FINGERPRINT_FILES, f"the GDScript and Python band file lists differ: {listed}")
    expect("%s\\n%s\\n" in source and ".sha256_text().substr(0, 16)" in source, "the GDScript fingerprint format changed")
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        (root / "scenes/ui").mkdir(parents=True)
        (root / "scenes/ui/dialogue_panel.tscn").write_bytes(b"scene")
        joined = (
            "scenes/ui/dialogue_panel.tscn\n" + hashlib.sha256(b"scene").hexdigest() + "\n"
            "scripts/ui/dialogue_panel.gd\nmissing\n"
        )
        expected = hashlib.sha256(joined.encode()).hexdigest()[:16]
        expect(evidence.ui_fingerprint(root) == expected, "the fingerprint is not path, digest, newline, hashed again")


# --- the relay -----------------------------------------------------------------------


def as_annotations(lines: list[str]) -> list[dict]:
    notes = []
    for line in lines:
        name, part, data = line.split(" ", 2)
        notes.append({"title": f"relay {name} {part}", "message": data})
    return notes


def parts_survive_shuffling_and_refuse_damage() -> None:
    payload = bytes(random.Random(186).randrange(256) for _ in range(9000))
    lines = relay.split_parts("frame.jpg", payload, part_size=100)
    expect(len(lines) == -(-len(base64.b64encode(payload)) // 100), "the part count is not ceil(base64 / size)")
    shuffled = as_annotations(lines)
    random.Random(7).shuffle(shuffled)
    shuffled.append({"title": "something else", "message": "ignored"})
    files, problems = relay.reassemble(shuffled)
    expect(not problems and files.get("frame.jpg") == payload, f"shuffled parts did not reassemble: {problems}")
    files, problems = relay.reassemble(as_annotations(lines[:3] + lines[4:]))
    expect("frame.jpg" not in files and has(problems, "frame.jpg", "missing", "first: 4"), f"a lost part passed: {problems}")


def pack_and_verify_round_trip() -> None:
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        frames = root / "frames"
        frames.mkdir()
        log = root / "capture.log"
        records = []
        for stem, size in (("01_opening_line", (40, 20)), ("ui-dialogue-1280x720-zh", (32, 18))):
            (frames / f"{stem}.jpg").write_bytes(jpeg_bytes(*size, filler=bytes(range(256)) * 20))
            records.append(
                {"frame": f"{stem}.png", "size": list(size), "godot": "4.7.2", "ui_fingerprint": "abc",
                 "shows": {"kind": "dialogue", "locale": "en", "text": "x"}}
            )
        log.write_text(
            "noise\n" + "\n".join(f"CAPTURE prefix EVIDENCE {json.dumps(r)}" for r in records) + "\n",
            encoding="utf-8",
        )
        wanted = ("01_opening_line", "ui-dialogue-1280x720-zh")
        problems, shards = relay.pack(
            [log], frames, root / "out", wanted=wanted, commit="c" * 40, run_id=7, part_size=200, per_job=5
        )
        expect(not problems, f"a complete capture did not pack: {problems}")
        queue = (root / "out" / "queue.txt").read_text(encoding="ascii").splitlines()
        expect(queue[0].startswith(f"{relay.INDEX_FILE} 1/"), "frames.json does not travel first")
        expect(shards == list(range(-(-len(queue) // 5))), f"the shard list does not cover the queue: {shards}")
        files, problems = relay.reassemble(as_annotations(queue))
        index, more = relay.verify(files)
        expect(not problems and not more and index is not None, f"a full relay did not verify: {problems + more}")
        expect(index["commit"] == "c" * 40 and index["run_id"] == 7, "the index lost the commit or the run")
        damaged = dict(files)
        damaged["01_opening_line.jpg"] = damaged["01_opening_line.jpg"][:-1] + b"\x00"
        _index, more = relay.verify(damaged)
        expect(has(more, "01_opening_line.jpg", "SHA-256"), f"a damaged frame verified: {more}")
        del damaged[relay.INDEX_FILE]
        expect(has(relay.verify(damaged)[1], "frames.json was not relayed"), "a relay without its index verified")

        problems, _ = relay.pack([log], frames, root / "o2", wanted=(*wanted, "ui-dialogue-1920x1080-en"))
        expect(has(problems, "ui-dialogue-1920x1080-en", "no EVIDENCE record"), f"a frame without a record packed: {problems}")
        (frames / "01_opening_line.jpg").write_bytes(jpeg_bytes(41, 20))
        problems, _ = relay.pack([log], frames, root / "o3", wanted=wanted)
        expect(has(problems, "01_opening_line", "(41, 20)"), f"a frame of the wrong size packed: {problems}")
        expect(not (root / "o3").exists(), "pack wrote output despite problems")


def apply_relay_records_and_retires() -> None:
    manifest = {
        "format_version": 1,
        "frames": [
            {"file": "ui-dialogue-1600x900-en.png", "status": "historical", "reason": "old", "caption": "Kept caption"},
            {"file": "01_opening_line.png", "status": "historical", "reason": "old"},
        ],
    }
    record = {"frame": "01_opening_line", "size": [1600, 900], "godot": "4.7.2", "ui_fingerprint": "f",
              "shows": {"kind": "dialogue", "locale": "en", "text": "t"}}
    record_ui = dict(record, frame="ui-dialogue-1600x900-en.png")
    changes = evidence.apply_relay(
        manifest, [record, record_ui], run_id=9, commit="d" * 40, workflow="Dialogue evidence relay",
        files={"01_opening_line.jpg": "1" * 64, "ui-dialogue-1600x900-en.jpg": "2" * 64},
        retire={"01_opening_line.png": "01_opening_line.jpg", "ui-dialogue-1600x900-en.png": "ui-dialogue-1600x900-en.jpg"},
    )
    names = [frame["file"] for frame in manifest["frames"]]
    expect(names == ["01_opening_line.jpg", "ui-dialogue-1600x900-en.jpg"], f"unexpected frames after apply: {names}")
    first = manifest["frames"][0]
    expect(first["status"] == "current" and first["captured"]["run_id"] == 9, "the relayed frame is not current")
    expect(first["sha256"] == "1" * 64 and first["size"] == [1600, 900], "the relayed frame lost its hash or size")
    expect(has(changes, "retired 01_opening_line.png"), f"the replaced PNG was not retired: {changes}")


def the_repository_passes() -> None:
    result = evidence.check(REPO)
    expect(result.ok(), "the repository's own screenshots fail the check:\n  " + "\n  ".join(result.errors))


TESTS = [
    a_true_manifest_passes,
    a_rewritten_line_makes_the_frame_stale,
    a_missing_node_or_conversation_fails,
    the_start_marker_follows_the_conversation,
    a_changed_byte_is_caught,
    a_wrong_size_is_caught,
    a_current_frame_must_say_where_it_came_from,
    the_source_must_be_in_its_locale,
    folder_and_manifest_must_agree,
    subfolders_must_be_declared_collections,
    history_must_say_why,
    history_may_keep_an_old_line,
    a_changed_band_warns_and_strict_fails,
    markdown_references_are_checked,
    a_broken_manifest_is_reported,
    image_readers,
    fingerprint_matches_the_game,
    parts_survive_shuffling_and_refuse_damage,
    pack_and_verify_round_trip,
    apply_relay_records_and_retires,
    the_repository_passes,
]


def main() -> int:
    for test in TESTS:
        before = len(FAILURES)
        try:
            test()
        except Exception as error:  # noqa: BLE001 - a crash is a failure with a name
            FAILURES.append(f"{test.__name__} raised {type(error).__name__}: {error}")
        status = "ok" if len(FAILURES) == before else "FAIL"
        print(f"{status:4}  {test.__name__}")
    if FAILURES:
        print(f"\n{len(FAILURES)} failure(s) in {CHECKS} check(s):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print(f"\nscreenshot evidence: {CHECKS} check(s) passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
