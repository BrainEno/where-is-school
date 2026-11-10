#!/usr/bin/env python3
"""Boundary tests for ``tools/verify_build.py``.

The build check is the only thing standing between a release and a pack full of screenshots,
so it is tested the same way as the game: with the edges, not with the middle.

- every kind of packed file lands in the category it should, including the hashed names the
  exporter writes under ``.godot/exported/``;
- the warning and hard limits are tested on both sides of their value, because "off by one"
  is exactly the mistake a budget check makes;
- the whole-pack budget is tested at its limit and one byte over;
- the forbidden-folder and required-folder checks still fire;
- the pack reader is tested against packs this file builds, including an embedded pack with
  a decoy ``GDPC`` after it — the case that made the first version of the reader report a
  build with no files in it.

Run it with ``python3 tests/verify_build_test.py`` (CI does). It needs no engine.
"""

from __future__ import annotations

import struct
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import verify_build as vb  # noqa: E402  (the path has to be set up first)

FAILURES: list[str] = []
CHECKS: int = 0


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


def expect_problem(problems: list[str], needle: str, message: str) -> None:
    check(any(needle in problem for problem in problems), f"{message} (got {problems})")


# --- the pack writer the reader is tested against ----------------------------


def make_pack(entries: list[tuple[str, int]], version: int = 4) -> bytes:
    """A pack with a valid header and directory, in the layout the reader reads.

    The data section is omitted: the reader only reads the directory, and a test that had to
    write 16 MiB of padding to check a size limit would be a slow test that checks the same
    thing.
    """
    directory = struct.pack("<I", len(entries))
    for name, size in entries:
        raw = name.encode("utf-8")
        padded = raw + b"\x00" * ((-len(raw)) % 4)
        directory += struct.pack("<I", len(padded)) + padded
        directory += struct.pack("<QQ", 0, size)
        directory += b"\x00" * 16  # md5
        directory += struct.pack("<I", 0)  # flags
    if version >= 3:
        header_length = 40
        header = (
            b"GDPC"
            + struct.pack("<IIIII", version, 4, 7, 2, 0)
            + struct.pack("<Q", 0)
            + struct.pack("<Q", header_length)
        )
    else:
        header = (
            b"GDPC"
            + struct.pack("<IIIII", 2, 4, 7, 2, 0)
            + struct.pack("<Q", 0)
            + b"\x00" * 64
        )
    return header + directory


# --- cases ------------------------------------------------------------------


def test_classify() -> None:
    cases = {
        # The exporter's own names, which is what the build actually contains.
        "res://.godot/exported/abc/student_backpack.glb-5817e7e.scn": "model",
        "res://.godot/exported/abc/bench_playground.glb-0202f96.scn": "model",
        "res://.godot/exported/abc/NotoSansSC-Regular.ttf-4b8abad.fontdata": "font",
        "res://.godot/exported/abc/step.wav-aa11bb.sample": "audio",
        "res://.godot/exported/abc/wall.png-cc22dd.ctex": "texture",
        "res://scenes/locations/street/street.tscn": "scene",
        "res://assets/ui/app_theme.tres": "scene",
        "res://data/dialogue/zh-CN/street.json": "text",
        "res://data/inspections/en/classroom.json": "text",
        "res://project.binary": "other",
        "res://.godot/exported/abc/something-11.xyz": "other",
    }
    for path, expected in cases.items():
        got = vb.classify(path).name
        check(got == expected, f"classify({path}) is {got}, expected {expected}")


def test_budget_table() -> None:
    for category in vb.CATEGORIES:
        check(
            category.warn <= category.hard,
            f"{category.name}: the warning line ({category.warn}) is above the hard limit",
        )
        check(
            category.hard <= vb.HARD_CEILING,
            f"{category.name}: the hard limit is looser than the {vb.HARD_CEILING} ceiling",
        )
        check(bool(category.why.strip()), f"{category.name}: no reason is recorded")


def test_entry_boundaries() -> None:
    category = vb.BY_NAME["text"]
    name = "res://data/dialogue/en/prologue.json"

    problems, warnings = vb.verify_budgets([(name, category.warn)])
    check(problems == [] and warnings == [], "a file exactly at the warning line warns")

    problems, warnings = vb.verify_budgets([(name, category.warn + 1)])
    check(problems == [], "a file just past the warning line fails the build")
    check(len(warnings) == 1, "a file just past the warning line does not warn")
    check("text" in warnings[0], "the warning does not name the category it broke")

    problems, warnings = vb.verify_budgets([(name, category.hard)])
    check(problems == [], "a file exactly at the hard limit fails the build")
    check(len(warnings) == 1, "a file exactly at the hard limit should still warn")

    problems, warnings = vb.verify_budgets([(name, category.hard + 1)])
    expect_problem(problems, "hard limit", "a file past the hard limit does not fail")


def test_every_category_has_a_ceiling() -> None:
    # The same boundary, once per category: the check is only worth having if no category
    # can quietly accept a file the old flat limit would have rejected.
    for category in vb.CATEGORIES:
        problems, _warnings = vb.verify_budgets([("res://thing.bin", vb.HARD_CEILING + 1)])
        check(
            any("hard limit" in problem or "ceiling" in problem for problem in problems),
            f"{category.name}: a file over the ceiling was accepted",
        )


def test_pack_totals() -> None:
    chunk = vb.BY_NAME["other"].warn  # exactly at the warning line of its category
    count = vb.MAX_PACK_BYTES // chunk
    entries = [(f"res://.godot/exported/x/file{i}.bin", chunk) for i in range(count)]
    total = sum(size for _, size in entries)
    check(total <= vb.MAX_PACK_BYTES, "the fixture is larger than the pack budget")

    problems, _warnings = vb.verify_budgets(entries)
    check(problems == [], f"a pack at its budget fails the build: {problems}")

    over = entries + [("res://.godot/exported/x/one-more.bin", vb.MAX_PACK_BYTES - total + 1)]
    problems, _warnings = vb.verify_budgets(over)
    expect_problem(problems, "over the", "a pack one byte over its budget does not fail")

    # Spread over files small enough to pass their own category check: this is about the
    # pack total, so nothing in it may fail for a per-file reason.
    pieces = 20
    chunk_size = vb.PACK_WARN_BYTES // pieces + 1
    big = [(f"res://.godot/exported/x/part{i}.bin", chunk_size) for i in range(pieces)]
    problems, warnings = vb.verify_budgets(big)
    check(problems == [], "a pack past the warning line fails the build")
    expect_problem(warnings, "warning line", "a pack past the warning line does not warn")


def test_forbidden_prefixes() -> None:
    for forbidden, sample in (
        ("res://tests/", "res://tests/some_test.gd"),
        ("res://docs/", "res://docs/ARCHITECTURE.md"),
        ("res://art/", "res://art/source/bench.blend"),
        ("res://tools/", "res://tools/verify_build.py"),
        ("res://.github/", "res://.github/workflows/godot-ci.yml"),
        ("res://addons/", "res://addons/narrative_editor/plugin.cfg"),
    ):
        problems = vb.verify_contents([(sample, 100)])
        expect_problem(problems, forbidden, f"{forbidden} files are accepted into the build")


def test_required_prefixes() -> None:
    problems = vb.verify_contents([])
    expect_problem(problems, "no files at all", "an empty pack is accepted")
    expect_problem(problems, "nothing under", "a pack with no game in it is accepted")
    expect_problem(problems, "font", "a pack with no font stub is accepted")


def test_pack_parser() -> None:
    entries = [("scenes/main/main.tscn", 1234), ("data/dialogue/en/prologue.json", 5678)]
    for version in (2, 3, 4):
        blob = make_pack(entries, version=version)
        parsed, header = vb.read_pack(blob, 0)
        check(header["version"] == version, f"v{version}: the header version was misread")
        check(
            [name for name, _size in parsed]
            == ["res://scenes/main/main.tscn", "res://data/dialogue/en/prologue.json"],
            f"v{version}: the paths were not restored with their res:// prefix ({parsed})",
        )
        check(
            [size for _name, size in parsed] == [1234, 5678],
            f"v{version}: the sizes were misread ({parsed})",
        )


def test_pack_parser_rejects_garbage() -> None:
    for blob, why in (
        (b"not a pack at all", "a file with no magic"),
        (b"GDPC" + struct.pack("<IIIII", 4, 4, 7, 2, 0), "a pack with no header body"),
        (b"GDPC" + struct.pack("<IIIII", 99, 4, 7, 2, 0) + b"\x00" * 64, "an unknown format"),
    ):
        try:
            vb.read_pack(blob, 0)
        except vb.PackError:
            continue
        check(False, f"{why} was read as a pack")


def test_embedded_pack_with_decoy() -> None:
    # The exported executable ends with bytes that spell GDPC, and the first version of the
    # reader took the last one and reported a truncated header. The decoy here is that case.
    blob = b"\x7fELF" + b"x" * 64 + make_pack([("project.binary", 42)]) + b"GDPC" + b"\x00" * 12
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "game.exe"
        path.write_bytes(blob)
        try:
            entries, _header = vb.load(path, embedded=True)
        except vb.PackError as error:
            check(False, f"the embedded pack was not found behind the decoy: {error}")
            return
    check(entries == [("res://project.binary", 42)], f"the wrong pack was read: {entries}")


def test_category_totals() -> None:
    entries = [
        ("res://.godot/exported/a/bench.glb-h.scn", 200 * vb.KiB),
        ("res://.godot/exported/a/chair.glb-h.scn", 100 * vb.KiB),
        ("res://data/dialogue/en/street.json", 10 * vb.KiB),
    ]
    totals = vb.category_totals(entries)
    check(totals["model"]["count"] == 2, "the model count is wrong")
    check(totals["model"]["bytes"] == 300 * vb.KiB, "the model total is wrong")
    check(
        totals["model"]["largest"][1] == 200 * vb.KiB,
        "the largest model is not reported",
    )
    check(totals["text"]["count"] == 1, "the text count is wrong")
    check(totals["audio"]["count"] == 0, "an absent category is not empty")


def main() -> int:
    for name, function in sorted(globals().items()):
        if name.startswith("test_") and callable(function):
            function()
    if FAILURES:
        for failure in FAILURES:
            print(f"FAIL: {failure}", file=sys.stderr)
        print(f"::error title=build check tests::{len(FAILURES)} of {CHECKS} check(s) failed", file=sys.stderr)
        return 1
    print(f"PASS: {CHECKS} check(s): the build check's categories, limits and pack reader.")
    print(f"::notice title=build check tests::{CHECKS} boundary check(s) passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
