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
  build with no files in it;
- a Windows executable's resource section is built here, so the icon and version checks can
  be shown to fail for the right reason: no icon, no version, a stale version, an icon group
  naming images that are not in the file;
- a release zip is built here too, so the package check is shown to catch a missing launcher,
  a launcher naming a missing icon, an executable without its execute bit, a stray ``docs/``
  or ``export.log``, and a folder or version that disagrees with the zip's own name.

Run it with ``python3 tests/verify_build_test.py`` (CI does). It needs no engine.
"""

from __future__ import annotations

import struct
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import export_presets  # noqa: E402  (the path has to be set up first)
import verify_build as vb  # noqa: E402
from release_pack_fixtures import embed, pack_files  # noqa: E402

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
    """A complete synthetic pack, including actual file data and its MD5s."""
    return pack_files([(name, bytes([index % 251 + 1]) * size)
                       for index, (name, size) in enumerate(entries)], version)


# --- cases ------------------------------------------------------------------


def test_classify() -> None:
    cases = {
        # The exporter's own names, which is what the build actually contains.
        "res://.godot/exported/abc/student_backpack.glb-5817e7e.scn": "model",
        "res://.godot/exported/abc/bench_playground.glb-0202f96.scn": "model",
        "res://.godot/exported/abc/Protagonist_Character.glb-2a3b4c.scn": "character-model",
        "res://.godot/exported/abc/protagonist.glb-2a3b4c.scn": "character-model",
        "res://.godot/exported/abc/new-Q.glb-2a3b4c.scn": "character-model",
        "res://.godot/exported/abc/teacher-n.glb-2a3b4c.scn": "character-model",
        "res://.godot/exported/abc/teacher_b.glb-2a3b4c.scn": "character-model",
        "res://.godot/exported/abc/unlisted_character.glb-2a3b4c.scn": "model",
        "res://.godot/exported/abc/NotoSansSC-Regular.ttf-4b8abad.fontdata": "font",
        "res://.godot/exported/abc/step.wav-aa11bb.sample": "audio",
        "res://.godot/exported/abc/wall.png-cc22dd.ctex": "texture",
        "res://scenes/locations/street/street.tscn": "scene",
        "res://assets/ui/app_theme.tres": "scene",
        # A sculpted mesh resource beside its scene is a model; the scene budget is
        # about .tscn bloat, and these ship with their own name and size to defend.
        "res://scenes/environment/fauna/green_animal_meshes/animal_body.tres": "model",
        "res://scenes/environment/characters/roof_collector_meshes/collector_head.tres": "model",
        "res://scenes/locations/port/meshes/ship_cargo.tres": "model",
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



def test_character_model_budgets() -> None:
    category = vb.BY_NAME["character-model"]
    check(category.warn == 1536 * vb.KiB, "the character-model warning threshold changed")
    check(category.hard == 4 * vb.MiB, "the character-model hard limit changed")

    # The V2 protagonist's imported PCK resource measured 2.59 MiB. It must warn,
    # not block a release, while remaining bounded by the explicit character cap.
    protagonist = "res://.godot/exported/abc/Protagonist_Character.glb-2a3b4c.scn"
    problems, warnings = vb.verify_budgets([(protagonist, int(2.59 * vb.MiB))])
    check(problems == [], f"a 2.59 MiB protagonist model was blocked: {problems}")
    expect_problem(warnings, "warning line", "a large character model did not warn")

    problems, warnings = vb.verify_budgets([(protagonist, category.hard)])
    check(problems == [], f"a character model exactly at 4 MiB failed: {problems}")
    check(bool(warnings), "a character model at the hard limit did not warn")

    problems, _warnings = vb.verify_budgets([(protagonist, category.hard + 1)])
    expect_problem(problems, "hard limit", "a character model over 4 MiB did not fail")

    ordinary = "res://.godot/exported/abc/unlisted_character.glb-2a3b4c.scn"
    problems, _warnings = vb.verify_budgets([(ordinary, int(2.59 * vb.MiB))])
    expect_problem(problems, "hard limit", "an unlisted model inherited the character exception")

    other = "res://project.binary"
    problems, _warnings = vb.verify_budgets([(other, 2 * vb.MiB + 1)])
    expect_problem(problems, "hard limit", "the generic file budget was accidentally raised")

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
    check(vb.MAX_PACK_BYTES == 50 * vb.MiB, "the approved 50 MiB pack limit changed")
    check(vb.BY_NAME["audio"].hard == 2 * vb.MiB, "the per-audio-file limit changed")
    check(vb.BY_NAME["other"].hard == 2 * vb.MiB, "the generic file limit changed")
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
        ("res://scenes/dev/", "res://scenes/dev/animation_retarget_test/protagonist_ual.res"),
        ("res://scripts/dev/", "res://scripts/dev/ual_preview.gdc"),
    ):
        problems = vb.verify_contents([(sample, 100)])
        expect_problem(problems, forbidden, f"{forbidden} files are accepted into the build")


def game_entries() -> list[tuple[str, int]]:
    """A minimal contents-valid pack, so unrelated missing files cannot mask a leak."""
    return [
        ("res://scenes/main/main.tscn", 100),
        ("res://assets/ui/app_theme.tres", 100),
        ("res://data/dialogue/en/prologue.json", 100),
        ("res://data/dialogue/zh-CN/prologue.json", 100),
        ("res://data/inspections/en/classroom.json", 100),
        ("res://data/story/notebook_comparisons.json", 100),
        ("res://assets/audio/bell_second.wav.import", 100),
        ("res://assets/fonts/NotoSansSC-Regular.ttf.import", 100),
    ]


def test_development_only_assets_outside_the_dev_directory() -> None:
    entries = game_entries()
    check(vb.verify_contents(entries) == [], "the clean pack fixture is not contents-valid")
    for path in (
        "res://assets/animations/UAL1_Standard.glb",
        "res://assets/animations/UAL1_Standard.tres",
        "res://assets/animations/protagonist_ual.res",
        "res://assets/animations/protagonist_ual.tres",
        "res://assets/previews/protagonist_ual_preview.tscn",
        "res://.godot/imported/UAL1_Standard.glb-1d128ad5a152cd2ff20b21584ce0da72.scn",
        "res://.godot/exported/abc/export-UAL1_Standard.glb-aabb.scn",
        "res://.godot/exported/abc/protagonist_ual.res-aabb.res",
        "res://.godot/exported/abc/export-protagonist_ual.res-aabb.res",
        "res://assets/animations/ual1_standard.glb.import",
        "res://assets/animations/PROTAGONIST_UAL.RES.remap",
    ):
        # Exercise the directory reader too: exported names are not the source paths.
        blob = make_pack([(name.removeprefix("res://"), size) for name, size in entries + [(path, 100)]])
        parsed, header = vb.load_blob(blob, embedded=False)
        problems, _ = vb.verify(parsed, header)
        expect_problem(problems, "development-only asset", f"{path} escaped the asset quarantine")

    for path in (
        "res://assets/characters/protagonist/protagonist_motion.tres",
        "res://scripts/actors/animation_retarget.gdc",
        "res://assets/animations/ual1_standards.glb",
    ):
        check(vb.verify_contents(entries + [(path, 100)]) == [], f"unrelated resource rejected: {path}")


def test_required_prefixes() -> None:
    problems = vb.verify_contents([])
    expect_problem(problems, "no files at all", "an empty pack is accepted")
    expect_problem(problems, "nothing under", "a pack with no game in it is accepted")
    expect_problem(problems, "font", "a pack with no font stub is accepted")
    comparison = "res://data/story/notebook_comparisons.json"
    entries = [(path, size) for path, size in game_entries() if path != comparison]
    expect_problem(vb.verify_contents(entries), comparison, "a pack with no notebook pairs is accepted")


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
    # Keep the decoy inside the pack boundary and use the real uint64(size),
    # GDPC footer. The old fixture omitted that locator and all actual payloads.
    pack = make_pack([("project.binary", 42)]) + b"GDPC" + bytes(12)
    blob = embed(pack, b"\x7fELF" + b"x" * 64)
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


# --- the fixtures the metadata and package checks are tested against ----------
#
# A test that only ever feeds the checker a good file proves that the checker agrees with
# itself. These fixtures build the things a real release is made of — a Windows executable
# with a resource section, an ELF header, a zip — and then break one thing at a time, which
# is the only way to know a check fires for the reason it claims to.
#
# The resource section is built here rather than read from a real export because the
# repository does not carry a 70 MB executable; the real export is what CI checks it
# against, and this is what keeps the reader honest between those runs.


def version_info(
    file_version: str = "0.1.0.0",
    product_version: str | None = None,
    strings: dict[str, str] | None = None,
) -> bytes:
    """A VS_VERSIONINFO resource, the way Godot's TemplateModifier lays one out."""

    def block(key: str, value: bytes, children: list[bytes], kind: int, value_length: int) -> bytes:
        payload = key.encode("utf-16-le") + b"\x00\x00"
        payload += b"\x00" * ((-(6 + len(payload))) % 4)
        payload += value
        payload += b"\x00" * ((-(6 + len(payload))) % 4)
        payload += b"".join(children)
        return struct.pack("<HHH", 6 + len(payload), value_length, kind) + payload

    def words(version: str) -> tuple[int, int]:
        parts = [int(part) for part in version.split(".")]
        return parts[0] << 16 | parts[1], parts[2] << 16 | parts[3]

    file_ms, file_ls = words(file_version)
    product_ms, product_ls = words(product_version or file_version)
    fixed = struct.pack(
        "<IIIIIIIIIIIII",
        0xFEEF04BD,
        0x00010000,
        file_ms,
        file_ls,
        product_ms,
        product_ls,
        0x3F,
        0,
        0x40004,
        1,
        0,
        0,
        0,
    )
    if strings is None:
        strings = {
            "CompanyName": "BrainEno",
            "FileDescription": "where-is-school - the vertical slice",
            "FileVersion": file_version,
            "ProductName": "where-is-school",
            "ProductVersion": product_version or file_version,
        }
    entries = [
        block(key, text.encode("utf-16-le") + b"\x00\x00", [], 1, len(text) + 1)
        for key, text in strings.items()
    ]
    table = block("040904B0", b"", entries, 1, 0)
    string_info = block("StringFileInfo", b"", [table], 1, 0)
    return block("VS_VERSION_INFO", fixed, [string_info], 0, len(fixed))


def group_icon(sizes: tuple[int, ...] = (16, 32, 48, 256), ids: list[int] | None = None) -> bytes:
    ids = ids if ids is not None else list(range(1, len(sizes) + 1))
    out = struct.pack("<HHH", 0, 1, len(sizes))
    for size, ident in zip(sizes, ids):
        out += struct.pack(
            "<BBBBHHIH",
            size if size < 256 else 0,
            size if size < 256 else 0,
            0,
            0,
            1,
            32,
            64,
            ident,
        )
    return out


def resource_section(resources: dict[int, dict[int, bytes]], base: int = 0x1000) -> bytes:
    """A resource directory: type -> name -> one language -> data entry."""
    types = sorted(resources)
    root_size = 16 + 8 * len(types)
    type_offsets: dict[int, int] = {}
    offset = root_size
    for kind in types:
        type_offsets[kind] = offset
        offset += 16 + 8 * len(resources[kind])
    name_offsets: dict[tuple[int, int], int] = {}
    for kind in types:
        for name in sorted(resources[kind]):
            name_offsets[(kind, name)] = offset
            offset += 16 + 8
    entry_offset = offset
    by_name = [(kind, name) for kind in types for name in sorted(resources[kind])]
    offset += 16 * len(by_name)
    data_offset = offset
    blobs: dict[tuple[int, int], tuple[int, int]] = {}
    for kind, name in by_name:
        payload = resources[kind][name]
        blobs[(kind, name)] = (data_offset, len(payload))
        data_offset += len(payload) + ((-len(payload)) % 4)

    out = bytearray(data_offset)

    def directory(at: int, entries: list[tuple[int, int]]) -> None:
        struct.pack_into("<IIHHHH", out, at, 0, 0, 0, 0, 0, len(entries))
        for index, (ident, child) in enumerate(entries):
            struct.pack_into("<II", out, at + 16 + 8 * index, ident, child)

    directory(0, [(kind, type_offsets[kind] | 0x80000000) for kind in types])
    for kind in types:
        directory(
            type_offsets[kind],
            [(name, name_offsets[(kind, name)] | 0x80000000) for name in sorted(resources[kind])],
        )
    for index, (kind, name) in enumerate(by_name):
        directory(name_offsets[(kind, name)], [(0x409, entry_offset + 16 * index)])
        struct.pack_into(
            "<IIII", out, entry_offset + 16 * index, base + blobs[(kind, name)][0], blobs[(kind, name)][1], 0, 0
        )
    for (kind, name), (at, length) in blobs.items():
        out[at : at + length] = resources[kind][name]
    return bytes(out)


def make_pe(resources: dict[int, dict[int, bytes]] | None = None, rva: int = 0x1000) -> bytes:
    """A minimal PE32+ whose only section is `.rsrc`."""
    blob = bytearray(0x400)
    blob[0:2] = b"MZ"
    struct.pack_into("<I", blob, 0x3C, 0x80)
    blob[0x80:0x84] = b"PE\x00\x00"
    struct.pack_into("<HHIIIHH", blob, 0x84, 0x8664, 1, 0, 0, 0, 240, 0x22)
    optional = 0x98
    struct.pack_into("<H", blob, optional, 0x20B)
    section = resource_section(resources or {}, base=rva)
    struct.pack_into("<II", blob, optional + 112 + 16, rva, len(section) if section else 0)
    table = optional + 240
    struct.pack_into("<8sIIII", blob, table, b".rsrc", len(section), rva, len(section), 0x400)
    return bytes(blob) + section


def make_elf(elf_class: int = 2, machine: int = 0x3E, kind: int = 2) -> bytes:
    header = bytearray(64)
    header[0:4] = b"\x7fELF"
    header[4] = elf_class
    header[5] = 1
    header[6] = 1
    struct.pack_into("<H", header, 16, kind)
    struct.pack_into("<H", header, 18, machine)
    return bytes(header)


def complete_resources() -> dict[int, dict[int, bytes]]:
    return {
        vb.RT_ICON: {1: b"\x01" * 64, 2: b"\x02" * 128, 3: b"\x03" * 256, 4: b"\x04" * 512},
        vb.RT_GROUP_ICON: {1: group_icon()},
        vb.RT_VERSION: {1: version_info()},
    }


def make_package(
    directory: Path,
    stem: str,
    files: dict[str, bytes],
    folder: str | None = None,
    modes: dict[str, int] | None = None,
) -> Path:
    import zipfile

    path = directory / f"{stem}.zip"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, payload in files.items():
            info = zipfile.ZipInfo(f"{folder or stem}/{name}")
            info.external_attr = (modes or {}).get(name, 0o644) << 16
            archive.writestr(info, payload)
    return path


LICENCES = {
    "licences/COPYRIGHT.md": b"# Copyright\n",
    "licences/NotoSansSC-OFL.txt": b"OFL\n",
    "licences/NotoSerifSC-OFL.txt": b"OFL\n",
}
DESKTOP = b"""[Desktop Entry]
Type=Application
Name=where-is-school
Exec=sh -c 'cd "$(dirname "$1")" && exec ./where-is-school' sh %k
Icon=where-is-school
Categories=Game;AdventureGame;
"""
PNG_256 = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 256, 256) + b"\x08\x06\x00\x00\x00"


NOTES = b"""where-is-school

Linux: ./where-is-school (experimental; desktop/Steam Deck playtesting unverified).

Licences
--------
licences/COPYRIGHT.md          the project's notice
licences/NotoSansSC-OFL.txt    Noto Sans SC (SIL Open Font License)
licences/NotoSerifSC-OFL.txt   Noto Serif SC (SIL Open Font License)
"""


def windows_files() -> dict[str, bytes]:
    return {"where-is-school.exe": make_pe(complete_resources()), "HOW-TO-RUN.txt": NOTES}


def linux_files() -> dict[str, bytes]:
    return {
        "where-is-school": make_elf(),
        "where-is-school.desktop": DESKTOP,
        "where-is-school.png": PNG_256,
        "README.txt": NOTES,
        "HOW-TO-RUN.txt": NOTES,
    }


def make_macho(universal: bool = True, thin_cpu: int = 0x01000007) -> bytes:
    """A minimal Mach-O: a universal fat wrapper by default, else one thin slice.

    The verifier reads the fat table's cputypes and a thin header's cputype, so the
    slices themselves only need the magic and the machine type the table points at.
    """
    thin = struct.pack("<II", 0xFEEDFACF, thin_cpu)
    if not universal:
        return thin
    x86 = struct.pack("<II", 0xFEEDFACF, 0x01000007)
    arm = struct.pack("<II", 0xFEEDFACF, 0x0100000C)
    header = struct.pack(">II", 0xCAFEBABE, 2)
    offset = 40
    for cpu, slice_bytes in ((0x01000007, x86), (0x0100000C, arm)):
        header += struct.pack(">iiIII", cpu, 0, offset, len(slice_bytes), 12)
        offset += len(slice_bytes)
    return header.ljust(40, b"\0") + x86 + arm


def make_plist(version: str = "0.1.0") -> bytes:
    import plistlib

    return plistlib.dumps(
        {
            "CFBundleIdentifier": "io.github.braineno.whereisschool",
            "CFBundleExecutable": "where-is-school",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": version,
            "LSMinimumSystemVersion": "11.00",
        }
    )


def make_icns(chunk: bytes = b"ic08") -> bytes:
    """An ICNS with one PNG chunk; `chunk` names the pixel size the verifier reads."""
    payload = chunk + struct.pack(">I", len(PNG_256) + 8) + PNG_256
    return b"icns" + struct.pack(">I", len(payload) + 8) + payload


MACOS_NOTES = b"""where-is-school

macOS: unzip and open where-is-school.app (right-click it the first time).

Licences
--------
licences/COPYRIGHT.md          the project's notice
licences/NotoSansSC-OFL.txt    Noto Sans SC (SIL Open Font License)
licences/NotoSerifSC-OFL.txt   Noto Serif SC (SIL Open Font License)
"""


def macos_files() -> dict[str, bytes]:
    return {
        "where-is-school.app/Contents/Info.plist": make_plist(),
        "where-is-school.app/Contents/MacOS/where-is-school": make_macho(),
        "where-is-school.app/Contents/Resources/where-is-school.pck": pack_files(
            [("res://data/story/notebook_comparisons.json", b"{}")]
        ),
        "where-is-school.app/Contents/Resources/icon.icns": make_icns(),
        "HOW-TO-RUN.txt": MACOS_NOTES,
    }


def test_windows_metadata_accepts_a_complete_executable() -> None:
    problems, notes = vb.verify_windows_metadata(make_pe(complete_resources()), "0.1.0")
    check(problems == [], f"a complete executable was rejected: {problems}")
    check(any("256" in note for note in notes), f"the icon sizes were not reported: {notes}")
    check(any("0.1.0.0" in note for note in notes), f"the version was not reported: {notes}")


def test_windows_metadata_needs_an_icon() -> None:
    resources = complete_resources()
    del resources[vb.RT_GROUP_ICON]
    problems, _ = vb.verify_windows_metadata(make_pe(resources), "0.1.0")
    expect_problem(problems, "no icon resource", "an executable with no icon passed")


def test_windows_metadata_needs_a_version() -> None:
    resources = complete_resources()
    del resources[vb.RT_VERSION]
    problems, _ = vb.verify_windows_metadata(make_pe(resources), "0.1.0")
    expect_problem(problems, "no version resource", "an executable with no version passed")


def test_windows_metadata_catches_a_stale_version() -> None:
    problems, _ = vb.verify_windows_metadata(make_pe(complete_resources()), "0.2.0")
    expect_problem(problems, "the executable says version 0.1.0.0", "the stamped version is not compared")


def test_windows_metadata_catches_a_group_icon_without_images() -> None:
    resources = complete_resources()
    # A group that names four images while only one is in the file: the shape a half-applied
    # icon change takes, and the reason the group is not trusted on its own.
    resources[vb.RT_GROUP_ICON] = {1: group_icon((16, 32, 48, 256), ids=[1, 2, 3, 9])}
    problems, _ = vb.verify_windows_metadata(make_pe(resources), "0.1.0")
    expect_problem(problems, "not in the file", "a dangling icon id was accepted")


def test_windows_metadata_catches_a_small_only_icon() -> None:
    resources = {
        vb.RT_ICON: {1: b"\x01" * 64},
        vb.RT_GROUP_ICON: {1: group_icon((16,), ids=[1])},
        vb.RT_VERSION: {1: version_info()},
    }
    problems, _ = vb.verify_windows_metadata(make_pe(resources), None)
    expect_problem(problems, "single 16 px icon", "a one-size icon passed")


def test_windows_metadata_catches_missing_product_strings() -> None:
    resources = complete_resources()
    resources[vb.RT_VERSION] = {1: version_info(strings={"FileVersion": "0.1.0.0", "ProductVersion": "0.1.0.0"})}
    problems, _ = vb.verify_windows_metadata(make_pe(resources), "0.1.0")
    expect_problem(problems, "ProductName", "an empty product name passed")


def test_version_reader_reads_strings_and_numbers() -> None:
    strings, fixed = vb.read_version_info(version_info("1.2.3.4", "1.2.3.5"))
    check(strings["FileVersion"] == "1.2.3.4", f"FileVersion read as {strings.get('FileVersion')}")
    check(strings["ProductName"] == "where-is-school", "ProductName was not read")
    check(fixed["signature"] == 0xFEEF04BD, "the fixed signature was not read")
    check(fixed["file_ms"] == 0x00010002 and fixed["file_ls"] == 0x00030004, "the file version words are wrong")
    check(fixed["product_ms"] == 0x00010002 and fixed["product_ls"] == 0x00030005, "the product version words are wrong")


def test_resource_version_forms() -> None:
    check(vb.resource_version_of("0.1.0") == ("0.1.0.0", "0.1.0"), "0.1.0 does not become 0.1.0.0")
    check(vb.resource_version_of("0.1.0-rc.1") == ("0.1.0.0", "0.1.0"), "a prerelease tail survives into the resource")
    check(vb.resource_version_of("12.34.56") == ("12.34.56.0", "12.34.56"), "a large version is mangled")
    for bad in ("0.1", "0.1.0.0.0", "0.1.x", "70000.0.0"):
        try:
            vb.resource_version_of(bad)
        except ValueError:
            check(True, "unused")
        else:
            check(False, f"{bad!r} was accepted as a version")


def test_not_a_pe_is_reported_not_crashed() -> None:
    problems, _ = vb.verify_windows_metadata(b"\x00" * 1024, None)
    check(bool(problems), "garbage was accepted as a Windows executable")


def test_elf_checks() -> None:
    problems, notes = vb.verify_linux_executable(make_elf())
    check(problems == [], f"a valid ELF was rejected: {problems}")
    check(any("x86" in note for note in notes), f"the ELF was not described: {notes}")
    problems, _ = vb.verify_linux_executable(make_elf(elf_class=1))
    expect_problem(problems, "64-bit", "a 32-bit ELF passed")
    problems, _ = vb.verify_linux_executable(make_elf(machine=0x28))
    expect_problem(problems, "x86-64", "an ARM ELF passed")
    problems, _ = vb.verify_linux_executable(b"not an elf at all")
    expect_problem(problems, "not an ELF", "garbage passed as an ELF")


def test_package_accepts_a_windows_zip() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = windows_files()
        files.update(LICENCES)
        path = make_package(Path(directory), "where-is-school-0.1.0-windows", files)
        package = vb.inspect_package(path, "0.1.0")
        check(package.problems == [], f"a good Windows package was rejected: {package.problems}")
        check(package.platform == "windows", "the platform was not detected")
        check(package.version == "0.1.0", f"the version was read as {package.version!r}")
        check(package.blob == files["where-is-school.exe"], "the executable was not read out of the zip")


def test_package_accepts_a_linux_zip() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = linux_files()
        files.update(LICENCES)
        path = make_package(
            Path(directory), "where-is-school-0.1.0-rc.1-linux", files, modes={"where-is-school": 0o755}
        )
        package = vb.inspect_package(path, "0.1.0-rc.1")
        check(package.problems == [], f"a good Linux package was rejected: {package.problems}")
        check(package.platform == "linux", "the platform was not detected")
        check(package.version == "0.1.0-rc.1", f"the version was read as {package.version!r}")


def test_package_accepts_a_macos_zip() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = macos_files()
        files.update(LICENCES)
        path = make_package(
            Path(directory),
            "where-is-school-0.1.0-macos",
            files,
            modes={"where-is-school.app/Contents/MacOS/where-is-school": 0o755},
        )
        package = vb.inspect_package(path, "0.1.0")
        check(package.problems == [], f"a good macOS package was rejected: {package.problems}")
        check(package.platform == "macos", "the platform was not detected")
        check(package.version == "0.1.0", f"the version was read as {package.version!r}")
        check(package.blob_is_pack, "the pack was not handed to the caller as the build to read")
        check(
            package.blob == files["where-is-school.app/Contents/Resources/where-is-school.pck"],
            "the pack read out of the bundle is not the pack that shipped",
        )
        check(any("universal" in note for note in package.notes), f"the binary was not described: {package.notes}")


def test_package_catches_a_thin_macos_binary() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = macos_files()
        files.update(LICENCES)
        files["where-is-school.app/Contents/MacOS/where-is-school"] = make_macho(universal=False)
        path = make_package(
            Path(directory),
            "where-is-school-0.1.0-macos",
            files,
            modes={"where-is-school.app/Contents/MacOS/where-is-school": 0o755},
        )
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(
            package.problems,
            "thin Mach-O",
            "an Intel-only binary passed the universal promise",
        )


def test_package_catches_a_macos_plist_version_mismatch() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = macos_files()
        files.update(LICENCES)
        files["where-is-school.app/Contents/Info.plist"] = make_plist("0.2.0")
        path = make_package(Path(directory), "where-is-school-0.1.0-macos", files)
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(
            package.problems,
            "CFBundleShortVersionString",
            "a bundle claiming another version passed",
        )


def test_package_catches_a_missing_macos_pack() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = macos_files()
        files.update(LICENCES)
        del files["where-is-school.app/Contents/Resources/where-is-school.pck"]
        path = make_package(Path(directory), "where-is-school-0.1.0-macos", files)
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(package.problems, "missing where-is-school.app/Contents/Resources/where-is-school.pck", "a bundle without the pack passed")


def test_package_catches_a_small_macos_icon() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = macos_files()
        files.update(LICENCES)
        files["where-is-school.app/Contents/Resources/icon.icns"] = make_icns(b"icp5")
        path = make_package(Path(directory), "where-is-school-0.1.0-macos", files)
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(
            package.problems,
            "largest .icns image is 32 px",
            "a Dock icon too small to read passed",
        )


def test_package_catches_a_macos_binary_without_the_executable_bit() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = macos_files()
        files.update(LICENCES)
        path = make_package(Path(directory), "where-is-school-0.1.0-macos", files)
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(
            package.problems,
            "without the executable bit",
            "a bundle whose game cannot be launched passed",
        )


def test_package_catches_a_macos_bundle_carrying_a_stray_pck() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = macos_files()
        files.update(LICENCES)
        files["where-is-school.pck"] = b"GDPC a leftover pack next to the app"
        path = make_package(Path(directory), "where-is-school-0.1.0-macos", files)
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(
            package.problems,
            "build output or a log",
            "a stray .pck beside the bundle passed",
        )


def test_package_catches_a_missing_launcher() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = linux_files()
        files.update(LICENCES)
        del files["where-is-school.desktop"]
        path = make_package(Path(directory), "where-is-school-0.1.0-linux", files, modes={"where-is-school": 0o755})
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(package.problems, "missing where-is-school.desktop", "a package without a launcher passed")


def test_package_catches_a_desktop_entry_naming_a_missing_icon() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = linux_files()
        files.update(LICENCES)
        files["where-is-school.desktop"] = DESKTOP.replace(b"Icon=where-is-school", b"Icon=some-other-name")
        path = make_package(Path(directory), "where-is-school-0.1.0-linux", files, modes={"where-is-school": 0o755})
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(package.problems, "some-other-name", "a launcher pointing at no icon passed")


def test_package_catches_run_notes_that_never_mention_the_licences() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = linux_files()
        files.update(LICENCES)
        files["HOW-TO-RUN.txt"] = b"where-is-school\n\nRun it\n------\nDouble-click it.\n"
        path = make_package(Path(directory), "where-is-school-0.1.0-linux", files, modes={"where-is-school": 0o755})
        package = vb.inspect_package(path, "0.1.0")
        # README.txt is in agreement, so the failure has to name the notes that are not.
        expect_problem(package.problems, "HOW-TO-RUN.txt has no Licences section", "silent licences passed")


def test_package_catches_run_notes_that_name_a_different_file() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = windows_files()
        files.update(LICENCES)
        files["HOW-TO-RUN.txt"] = NOTES.replace(b"NotoSerifSC-OFL.txt", b"OFL.txt")
        path = make_package(Path(directory), "where-is-school-0.1.0-windows", files)
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(package.problems, "does not name NotoSerifSC-OFL.txt", "a wrong file name passed")


def test_package_catches_a_missing_executable_bit() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = linux_files()
        files.update(LICENCES)
        path = make_package(Path(directory), "where-is-school-0.1.0-linux", files)
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(package.problems, "executable bit", "a non-executable Linux build passed")


def test_package_catches_development_files() -> None:
    for extra in ("tests/verify_build_test.py", "tools/verify_build.py", "docs/RELEASE.md", "export.log"):
        with tempfile.TemporaryDirectory() as directory:
            files = windows_files()
            files.update(LICENCES)
            files[extra] = b"junk"
            path = make_package(Path(directory), "where-is-school-0.1.0-windows", files)
            package = vb.inspect_package(path, "0.1.0")
            check(bool(package.problems), f"{extra} in a package was accepted")


def test_package_catches_relocated_development_only_assets() -> None:
    for platform, factory in (("windows", windows_files), ("linux", linux_files)):
        for extra in (
            "UAL1_Standard.glb",
            "assets/animations/protagonist_ual.res",
            "assets/animations/protagonist_ual.tres",
            ".godot/exported/abc/export-UAL1_Standard.glb-aabb.scn",
            "assets/animations/PROTAGONIST_UAL.RES",
        ):
            with tempfile.TemporaryDirectory() as directory:
                files = factory()
                files.update(LICENCES)
                files[extra] = b"synthetic asset fixture, not third-party content"
                path = make_package(
                    Path(directory), f"where-is-school-0.1.0-{platform}", files,
                    modes={"where-is-school": 0o755},
                )
                package = vb.inspect_package(path, "0.1.0")
                expect_problem(
                    package.problems, "development-only asset",
                    f"{extra} in a {platform} archive escaped the asset quarantine",
                )


def test_package_catches_a_version_that_disagrees_with_the_executable() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = windows_files()
        files.update(LICENCES)
        path = make_package(Path(directory), "where-is-school-0.2.0-windows", files)
        package = vb.inspect_package(path, "0.2.0")
        expect_problem(package.problems, "the executable says version 0.1.0.0", "the zip name and the exe disagree")


def test_package_catches_a_version_that_disagrees_with_the_build() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = windows_files()
        files.update(LICENCES)
        path = make_package(Path(directory), "where-is-school-0.2.0-windows", files)
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(package.problems, "is version '0.2.0'", "the workflow's version is not compared")


def test_package_catches_a_folder_that_disagrees_with_the_zip() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = windows_files()
        files.update(LICENCES)
        path = make_package(
            Path(directory), "where-is-school-0.1.0-windows", files, folder="where-is-school-0.0.9-windows"
        )
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(package.problems, "the folder inside", "a mislabelled folder passed")


def test_package_catches_an_unknown_platform_name() -> None:
    with tempfile.TemporaryDirectory() as directory:
        files = windows_files()
        files.update(LICENCES)
        path = make_package(Path(directory), "where-is-school-0.1.0", files)
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(package.problems, "does not end with", "a platform-less package name passed")


def test_package_rejects_rubbish() -> None:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "where-is-school-0.1.0-windows.zip"
        path.write_bytes(b"not a zip")
        package = vb.inspect_package(path, "0.1.0")
        expect_problem(package.problems, "not a readable zip", "a corrupt zip passed")


def test_preset_checks() -> None:
    def preset_text(modify_resources: str = "true", icon: str = "res://assets/icon/app_icon.ico") -> str:
        return (
            "[preset.0]\n\nname=\"Windows Desktop\"\nplatform=\"Windows Desktop\"\n"
            'exclude_filter="tests/*, tools/*, docs/*, art/*, scenes/dev/*, scripts/dev/*, .github/*, addons/*, scripts/story_editor/*"\n'
            'export_path="build/windows/where-is-school.exe"\n\n'
            "[preset.0.options]\n\n"
            'binary_format/embed_pck="true"\n'
            f'application/modify_resources={modify_resources}\n'
            f'application/icon="{icon}"\n'
            'application/company_name="BrainEno"\n'
            'application/product_name="where-is-school"\n'
            'application/file_description="where-is-school - the vertical slice"\n'
            'application/copyright="Copyright (c) 2026 BrainEno."\n'
            'application/file_version="0.1.0.0"\n'
            'application/product_version="0.1.0.0"\n\n'
            "[preset.1]\n\nname=\"Linux\"\nplatform=\"Linux\"\n"
            'exclude_filter="tests/*, tools/*, docs/*, art/*, scenes/dev/*, scripts/dev/*, .github/*, addons/*, scripts/story_editor/*"\n'
            'export_path="build/linux/where-is-school.x86_64"\n\n'
            "[preset.1.options]\n\n"
            'binary_format/embed_pck="true"\n'
            'binary_format/architecture="x86_64"\n\n'
            "[preset.2]\n\nname=\"macOS\"\nplatform=\"macOS\"\n"
            'exclude_filter="tests/*, tools/*, docs/*, art/*, scenes/dev/*, scripts/dev/*, .github/*, addons/*, scripts/story_editor/*"\n'
            'export_path="build/macos/where-is-school.zip"\n\n'
            "[preset.2.options]\n\n"
            'binary_format/architecture="universal"\n'
            'codesign/codesign=1\n'
            'application/bundle_identifier="io.github.braineno.whereisschool"\n'
            'application/short_version="0.1.0"\n'
            'application/version="0.1.0"\n'
            'application/copyright="Copyright (c) 2026 BrainEno."\n'
            'application/icon="res://assets/icon/app_icon.icns"\n'
        )

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "assets" / "icon").mkdir(parents=True)
        (root / "assets" / "icon" / "app_icon.ico").write_bytes(b"icon")
        (root / "assets" / "icon" / "app_icon.icns").write_bytes(b"icns")
        config = root / "export_presets.cfg"
        config.write_text(preset_text())

        problems, notes = vb.verify_presets(config, "0.1.0")
        check(problems == [], f"a good preset file was rejected: {problems}")
        check(any("metadata on" in note for note in notes), f"the Windows preset was not described: {notes}")
        check(any("macOS" in note for note in notes), f"the macOS preset was not described: {notes}")

        config.write_text(preset_text().replace('binary_format/architecture="universal"', 'binary_format/architecture="x86_64"'))
        problems, _ = vb.verify_presets(config, "0.1.0")
        expect_problem(problems, "not universal", "an Intel-only macOS preset passed")

        config.write_text(preset_text().replace("codesign/codesign=1", "codesign/codesign=0"))
        problems, _ = vb.verify_presets(config, "0.1.0")
        expect_problem(problems, "ad-hoc signer", "a macOS preset without the built-in signer passed")

        config.write_text(preset_text().replace("app_icon.icns", "app_icon.ico"))
        problems, _ = vb.verify_presets(config, "0.1.0")
        expect_problem(problems, "not an .icns", "a macOS preset pointing at the Windows icon passed")

        config.write_text(preset_text().replace(".zip", ".dmg"))
        problems, _ = vb.verify_presets(config, "0.1.0")
        expect_problem(problems, "needs macOS tools", "a DMG-producing preset passed")

        config.write_text(preset_text(modify_resources="false"))
        problems, _ = vb.verify_presets(config, "0.1.0")
        expect_problem(problems, "modify_resources", "a preset with resources off passed")

        config.write_text(preset_text(icon="res://assets/icon/missing.ico"))
        problems, _ = vb.verify_presets(config, "0.1.0")
        expect_problem(problems, "does not exist", "a preset naming a missing icon passed")

        config.write_text(preset_text())
        problems, _ = vb.verify_presets(config, "0.2.0")
        expect_problem(problems, "the build is", "a preset for another version passed")

        config.write_text(preset_text().replace('name="Linux"', 'name="Linux Server"'))
        problems, _ = vb.verify_presets(config, "0.1.0")
        expect_problem(problems, "no 'Linux' preset", "a preset file without Linux passed")

        config.write_text(preset_text().replace("scenes/dev/*, ", ""))
        problems, _ = vb.verify_presets(config, "0.1.0")
        expect_problem(
            problems,
            "does not exclude scenes/dev/",
            "a preset that would ship the development-only third-party assets passed",
        )

        # Only a whole, rooted directory wildcard proves this boundary. A substring,
        # another directory's name or a .tscn-only filter must not pass. Break just one
        # platform at a time: a correct Windows preset cannot conceal a broken Linux one.
        import re

        for preset_index, preset_name in enumerate(("Windows Desktop", "Linux", "macOS")):
            for where in ("tests/", "tools/", "docs/", "art/", "scenes/dev/", "scripts/dev/", ".github/", "addons/",
                          "scripts/story_editor/"):
                for replacement in ("", where + "*.tscn", "unrelated/" + where + "*"):
                    sections = re.split(r"(?=\[preset\.\d+\])", preset_text())
                    # The split leaves a leading empty chunk: chunk i+1 is preset i.
                    sections[preset_index + 1] = sections[preset_index + 1].replace(
                        where + "*", replacement, 1
                    )
                    config.write_text("".join(sections))
                    problems, _ = vb.verify_presets(config, "0.1.0")
                    expect_problem(
                        problems, f"the {preset_name} preset does not exclude {where}",
                        f"{preset_name}: {replacement!r} counted as excluding {where}",
                    )

        config.write_text(preset_text().replace("tests/*, tools/*", " res://tests/* , res://tools/* "))
        problems, _ = vb.verify_presets(config, "0.1.0")
        check(problems == [], f"rooted filters with surrounding whitespace were rejected: {problems}")


def test_preset_writer_keeps_the_rest_of_the_file() -> None:
    text = (
        "[preset.0]\n\n"
        'name="Windows Desktop"\n'
        'platform="Windows Desktop"\n\n'
        "[preset.0.options]\n\n"
        'binary_format/embed_pck="true"\n'
        'application/file_version=""\n\n'
        "[preset.1]\n\n"
        'name="Linux"\n'
        'platform="Linux"\n\n'
        "[preset.1.options]\n\n"
        'binary_format/embed_pck="true"\n'
    )
    written = export_presets.set_option(text, "Windows Desktop", "application/file_version", "0.1.0.0")
    check('application/file_version="0.1.0.0"' in written, "the option was not written")
    check(written.count("application/file_version=") == 1, "the option was written twice")
    check(
        written.replace('application/file_version="0.1.0.0"', 'application/file_version=""') == text,
        "writing one option changed another line",
    )
    appended = export_presets.set_option(text, "Linux", "binary_format/architecture", "x86_64")
    check('binary_format/architecture="x86_64"' in appended, "a missing option was not added")
    presets = export_presets.parse(appended)
    check(presets["Linux"].options["binary_format/architecture"] == "x86_64", "the added option does not parse")
    check(presets["Windows Desktop"].export_path == "", "an absent field did not default to empty")
    try:
        export_presets.set_option(text, "Windows", "a", "b")
    except export_presets.PresetError:
        check(True, "unused")
    else:
        check(False, "writing to an unknown preset was allowed")


def main() -> int:
    for name, function in sorted(globals().items()):
        if name.startswith("test_") and callable(function):
            function()
    if FAILURES:
        for failure in FAILURES:
            print(f"FAIL: {failure}", file=sys.stderr)
        print(f"::error title=build check tests::{len(FAILURES)} of {CHECKS} check(s) failed", file=sys.stderr)
        return 1
    print(
        f"PASS: {CHECKS} check(s): the build check's categories, limits, pack reader, "
        "executable metadata, package layout and preset pre-flight."
    )
    print(f"::notice title=build check tests::{CHECKS} boundary check(s) passed", flush=True)
    # The existing CI entry point must execute the new negative cases too, rather
    # than leaving an unregistered test next to a green legacy suite.
    return subprocess.run(
        [sys.executable, str(Path(__file__).with_name("release_integrity_test.py"))],
        check=False,
    ).returncode


if __name__ == "__main__":
    raise SystemExit(main())
