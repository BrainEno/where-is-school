#!/usr/bin/env python3
"""Check what is actually inside a build, not what the export preset promised.

An export preset is a wish list. The only way to know whether `tests/` really stayed out
of the build, whether the 10 MB source font stayed out, and whether the dialogue JSON was
packed at all, is to read the pack file back.

Usage (from the repository root, after an export):

    python3 tools/verify_build.py --exe build/windows/where-is-school.exe
    python3 tools/verify_build.py --pck build/windows/where-is-school.pck

`--exe` reads the pack embedded at the end of the executable, so it inspects the file that
would be handed to a player rather than a sibling the export happened to leave behind.

Two facts about a real Godot pack, learned by reading the engine (`core/io/pck_packer.cpp`,
`core/io/file_access_pack.cpp`, 4.7.2-stable) after the first export contradicted the
guesses this tool started with:

- **paths are stored without the `res://` prefix** — `PCKPacker::add_file` does
  `simplify_path().trim_prefix("res://")`. They are put back here, because every rule in
  this file is written the way the game refers to a file.
- **an imported resource is packed as a remap stub plus data under `.godot/exported/`**,
  not under its own path. So the font is `res://assets/fonts/NotoSansSC-Regular.ttf.import`
  pointing at `.godot/exported/<hash>/export-<name>`, and "is the font in the build" is a
  question about a directory, a stub and the size of the data behind them — not about one
  exact path.

The Godot 4 pack format used here:

    u32 magic 'GDPC' | u32 pack_version | u32 major, minor, patch | u32 flags | u64 file_base
    at file_base: u32 file_count, then per file:
        u32 path_len | path bytes (NUL-padded to 4) | u64 offset | u64 size | 16 byte md5
        | u32 flags (pack_version >= 2)

If Godot changes the format this tool fails loudly with the header it saw instead of
reporting a cheerful empty build.
"""

from __future__ import annotations

import argparse
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

MAGIC = b"GDPC"


def annotate(level: str, title: str, message: str) -> None:
    """Print a GitHub workflow command so the verdict is readable without the step log.

    The web UI shows annotations, but the REST *logs* endpoint redirects to object storage
    that a restricted client may not be allowed to read, which makes "the build failed the
    contents check" a dead end when the only consumer is an API.
    """
    print(f"::{level} title={title}::{message}")

# A release build has to carry the game and nothing else. Each of these is a directory that
# exists in the repository but must never reach a player's disk.
FORBIDDEN_PREFIXES = (
    "res://tests/",
    "res://tools/",
    "res://docs/",
    "res://art/",
    "res://.github/",
    # The narrative editor is an EditorPlugin. The game never loads it, and a player's
    # build has no business carrying the author's tooling.
    "res://addons/",
)

# Things whose absence means the build would start and immediately misbehave or crash.
# Imported resources (the font, the audio) appear as a `.import` stub plus data under
# `.godot/exported/`, so these are directory prefixes rather than exact paths.
REQUIRED_PREFIXES = (
    "res://scenes/main/main.tscn",
    "res://assets/ui/app_theme.tres",
    "res://data/dialogue/en/",
    "res://data/dialogue/zh-CN/",
    "res://data/inspections/en/",
    "res://assets/audio/",
    "res://assets/fonts/",
)

KiB = 1024
MiB = 1024 * 1024

# Every single file is checked against the budget of the kind of thing it is, because the
# kinds do not cost the same: a mesh, a texture, a font, a sound, a scene and a JSON chapter
# have different reasons to grow and different sizes when they are healthy. A single global
# "2 MiB per file" was either too generous for a JSON chapter or too strict for the one
# texture the game will eventually ship.
#
# Each entry is: warning threshold, hard limit, and why those two numbers. A warning is an
# annotation and does not fail the release; a hard limit does. `hard` is never above
# HARD_CEILING, so no category is looser than the old flat limit was.
@dataclass(frozen=True)
class Category:
    name: str
    warn: int
    hard: int
    why: str


# The ceiling that applies to every file whatever it is classified as: the old flat per-file
# budget, kept so this table can only tighten it, never relax it.
HARD_CEILING = 2 * MiB

CATEGORIES = (
    Category(
        "model",
        384 * KiB,
        1536 * KiB,
        "the two sample meshes ship at 206 and 134 KiB packed; 384 KiB warns, 1.5 MiB means "
        "an untrimmed Blender export or a texture baked into a mesh",
    ),
    Category(
        "font",
        384 * KiB,
        1 * MiB,
        "the subset covering every character the game can print is 252 KiB; 1 MiB means the "
        "full 10 MiB source font, or a subset without its glyph range, got packed",
    ),
    Category(
        "texture",
        512 * KiB,
        2 * MiB,
        "no textures ship yet, and none is needed: 512 KiB is a 1024x1024 RGBA image, 2 MiB "
        "is the point where a photo is being used as a wall",
    ),
    Category(
        "audio",
        512 * KiB,
        2 * MiB,
        "the placeholder cues are a few KiB each; anything past half a megabyte is a music "
        "track or an uncompressed recording, not a footstep",
    ),
    Category(
        "scene",
        192 * KiB,
        1 * MiB,
        "the largest location scene packs well under 100 KiB; a 1 MiB .tscn has embedded "
        "resources in it, which belong in their own files",
    ),
    Category(
        "text",
        128 * KiB,
        512 * KiB,
        "the largest chapter of dialogue or inspections is about 10 KiB; 128 KiB warns and "
        "512 KiB fails, which is a whole corpus in one file or a stray export under data/",
    ),
    Category(
        "other",
        256 * KiB,
        HARD_CEILING,
        "project settings, pack stubs and imported banners; anything here over 256 KiB is "
        "something nobody classified yet, which is exactly what wants looking at",
    ),
)

# The whole pack. The baseline is 1.37 MiB of 256 files, so the hard limit leaves room for
# roughly eleven more times the content the game has today — several more locations with
# furniture, textures and sound — while 8 MiB is an early signal that a release doubled.
# The number the old check used (16 MiB) is kept as the hard limit: nothing is loosened, and
# the warning is new.
PACK_WARN_BYTES = 8 * MiB
MAX_PACK_BYTES = 16 * MiB

BY_NAME = {category.name: category for category in CATEGORIES}


class PackError(Exception):
    pass


class _Cursor:
    """A bounds-checked little-endian reader over the pack bytes."""

    def __init__(self, blob: bytes, offset: int) -> None:
        self.blob = blob
        self.offset = offset

    def read(self, size: int) -> bytes:
        if self.offset + size > len(self.blob):
            raise PackError(
                f"read of {size} byte(s) at 0x{self.offset:x} runs past the end "
                f"({len(self.blob)} bytes)"
            )
        chunk = self.blob[self.offset : self.offset + size]
        self.offset += size
        return chunk

    def u32(self) -> int:
        return struct.unpack("<I", self.read(4))[0]

    def u64(self) -> int:
        return struct.unpack("<Q", self.read(8))[0]

    def skip(self, size: int) -> None:
        self.read(size)


# Byte layout, from the engine's own readers and writers
# (`core/io/pck_packer.cpp`, `core/io/file_access_pack.cpp`, tags 4.7.2-stable):
#
#   u32 magic 'GDPC' | u32 format | u32 major | u32 minor | u32 patch | u32 pack_flags
#   u64 file_base                     offsets in the directory are relative to this
#   -- format 3 and 4 only --
#   u64 dir_offset                    where the directory starts, relative to the magic
#   16 x u32 reserved                 (64 bytes)
#   -- directory, at dir_offset --
#   u32 file_count | per entry:
#       u32 path_length (already padded) | path bytes
#       u64 offset (relative to file_base) | u64 size | 16 byte md5 | u32 flags
#
# This was written from the v2/v3 layout and failed on the real export, which is v4: v4
# moved the directory and stores its offset instead of leaving it after the data. Format 2
# keeps the directory directly after the header's reserved words, and is handled so an old
# pack still verifies.
SUPPORTED_FORMATS = (2, 3, 4)
RESERVED_WORDS = 16


def _read_directory(blob: bytes, directory_offset: int) -> list[tuple[str, int]]:
    cursor = _Cursor(blob, directory_offset)
    count = cursor.u32()
    if count > 20000:
        raise PackError(f"the directory at 0x{directory_offset:x} claims {count} files")
    entries: list[tuple[str, int]] = []
    for index in range(count):
        path_length = cursor.u32()
        if path_length == 0 or path_length > 4096:
            raise PackError(f"entry {index} has an implausible path length ({path_length})")
        raw = cursor.read(path_length)
        cursor.u64()  # data offset, relative to file_base
        size = cursor.u64()
        cursor.skip(16)  # the entry's md5
        cursor.u32()  # per-file flags: encrypted / removal / delta
        stored = raw.rstrip(b"\x00").decode("utf-8", "replace")
        # The packer strips the prefix, so a stored path is never empty and never absolute.
        if not stored or stored.startswith("/"):
            raise PackError(f"entry {index} is not a usable path ({stored[:40]!r})")
        entries.append(("res://" + stored, size))
    return entries


def read_pack(blob: bytes, base: int) -> tuple[list[tuple[str, int]], dict[str, int]]:
    """Return (path, size) entries and the header, from a pack starting at `base`."""
    if blob[base : base + 4] != MAGIC:
        raise PackError(
            f"no 'GDPC' magic at offset {base}; the bytes there are {blob[base : base + 32].hex()}"
        )
    if base + 32 > len(blob):
        raise PackError(f"the pack header is truncated ({len(blob) - base} bytes from the magic)")
    version, major, minor, patch, pack_flags = struct.unpack_from("<IIIII", blob, base + 4)
    if version not in SUPPORTED_FORMATS:
        raise PackError(
            f"unsupported pack format {version}; header begins {blob[base : base + 32].hex()}"
        )
    file_base = struct.unpack_from("<Q", blob, base + 24)[0]
    header = {
        "version": version,
        "engine": f"{major}.{minor}.{patch}",
        "file_base": file_base,
        "relative_offsets": bool(pack_flags & 0x2),
    }
    if version >= 3:
        directory_offset = struct.unpack_from("<Q", blob, base + 32)[0] + base
    else:
        directory_offset = base + 32 + RESERVED_WORDS * 4
    return _read_directory(blob, directory_offset), header


def load(path: Path, embedded: bool) -> tuple[list[tuple[str, int]], dict[str, int]]:
    blob = path.read_bytes()
    if not embedded:
        return read_pack(blob, 0)

    # The pack is appended to the executable, so the magic is somewhere near the end — but
    # "near the end" is not "the last occurrence": the exported executable ends with bytes
    # that spell GDPC, and taking the last one reported a truncated header. Every occurrence
    # is tried, newest first, and the first that parses into a directory of res:// paths
    # wins; a candidate that parses into real paths is not a coincidence.
    starts: list[int] = []
    index = blob.rfind(MAGIC)
    while index != -1 and len(starts) < 64:
        starts.append(index)
        index = blob.rfind(MAGIC, 0, index)
    if not starts:
        raise PackError(
            "no 'GDPC' magic found in this file. Either the export did not embed the "
            "pack (binary_format/embed_pck), or the export failed and left a bare "
            "template executable."
        )
    problems: list[str] = []
    for start in starts:
        try:
            return read_pack(blob, start)
        except PackError as error:
            problems.append(f"0x{start:x}: {error}")
    raise PackError(
        f"no readable pack among {len(starts)} candidate('GDPC') offset(s): "
        + "; ".join(problems[:4])
    )


# Extensions that name the thing itself. An imported resource is packed as
# `.godot/exported/<hash>/<source name>-<hash>.<ext>`, so the source's extension survives in
# the stored name and can be used to classify it — that is what `classify` reads.
_MODEL_SUFFIXES = (".glb", ".gltf", ".blend", ".obj", ".fbx")
_AUDIO_SUFFIXES = (".wav", ".ogg", ".mp3", ".opus", ".flac", ".m4a")
_TEXTURE_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp", ".svg", ".exr", ".hdr", ".bmp", ".tga")
_FONT_SUFFIXES = (".ttf", ".otf", ".fontdata", ".woff", ".woff2")
_SCENE_SUFFIXES = (".tscn", ".scn", ".scene", ".tres", ".res")
_TEXT_SUFFIXES = (".json", ".csv", ".txt", ".md")


def classify(path: str) -> Category:
    """Which budget a packed file is measured against.

    The extensions of the *source* resource are looked for anywhere in the stored name,
    because an imported file keeps its original name inside `.godot/exported/`. Order
    matters: `student_backpack.glb-5817e7e.scn` is a model, not a scene.
    """
    lowered = path.lower()
    stored = lowered.rsplit("/", 1)[-1]
    if any(suffix in stored for suffix in _MODEL_SUFFIXES):
        return BY_NAME["model"]
    if any(suffix in stored for suffix in _FONT_SUFFIXES):
        return BY_NAME["font"]
    if any(suffix in stored for suffix in _AUDIO_SUFFIXES):
        return BY_NAME["audio"]
    if any(suffix in stored for suffix in _TEXTURE_SUFFIXES):
        return BY_NAME["texture"]
    if stored.startswith("data/") or "/data/" in lowered:
        if any(stored.endswith(suffix) for suffix in _TEXT_SUFFIXES):
            return BY_NAME["text"]
    if any(stored.endswith(suffix) for suffix in _SCENE_SUFFIXES):
        return BY_NAME["scene"]
    if any(stored.endswith(suffix) for suffix in _TEXT_SUFFIXES):
        return BY_NAME["text"]
    return BY_NAME["other"]


def verify(
    entries: list[tuple[str, int]], header: dict[str, int]
) -> tuple[list[str], list[str]]:
    """Return (problems, warnings) for the whole build.

    Two separate questions, kept separate: what is in the pack (contents) and how big it is
    (budgets). A contents problem is always a failure; a budget problem is a failure at the
    hard limit and an annotation at the warning line. The tests call the two halves directly,
    which is how the boundary cases stay testable without building a whole fake game.
    """
    problems = verify_contents(entries)
    budget_problems, warnings = verify_budgets(entries)
    problems.extend(budget_problems)
    del header
    return problems, warnings


def verify_contents(entries: list[tuple[str, int]]) -> list[str]:
    """Directories that must not ship, directories that must, and the font stub."""
    problems: list[str] = []
    paths = [path for path, _ in entries]
    sizes = dict(entries)

    if not entries:
        problems.append("the pack contains no files at all")

    for prefix in FORBIDDEN_PREFIXES:
        leaked = [path for path in paths if path.startswith(prefix)]
        if leaked:
            problems.append(
                f"{len(leaked)} file(s) under {prefix} reached the build, "
                f"first: {leaked[0]}"
            )

    for prefix in REQUIRED_PREFIXES:
        if not any(path.startswith(prefix) for path in paths):
            problems.append(f"nothing under {prefix} is in the build")

    font_stub = sizes.get("res://assets/fonts/NotoSansSC-Regular.ttf.import")
    if font_stub is None:
        problems.append(
            "the bundled font is not in the build (no "
            "res://assets/fonts/NotoSansSC-Regular.ttf.import stub)"
        )
    return problems


def verify_budgets(entries: list[tuple[str, int]]) -> tuple[list[str], list[str]]:
    """Per-file category budgets and the pack total: (problems, warnings)."""
    problems: list[str] = []
    warnings: list[str] = []

    for name, size in entries:
        category = classify(name)
        if size > category.hard:
            problems.append(
                f"{name} is {_human(size)}, over the {_human(category.hard)} hard limit for "
                f"{category.name} files: {category.why}"
            )
            continue
        if size > HARD_CEILING:
            # Unreachable while every category hard limit is at or under the ceiling, and
            # kept so that stays true.
            problems.append(
                f"{name} is {_human(size)}, over the {_human(HARD_CEILING)} ceiling for any "
                "single file"
            )
            continue
        if size > category.warn:
            warnings.append(
                f"{name} is {_human(size)}, past the {_human(category.warn)} warning line for "
                f"{category.name} files (hard limit {_human(category.hard)}): {category.why}"
            )

    total = sum(size for _, size in entries)
    if total > MAX_PACK_BYTES:
        problems.append(
            f"the pack is {total / 1048576:.1f} MiB, over the {MAX_PACK_BYTES / 1048576:.0f} "
            "MiB budget: something large got packed (screenshots? models? an untrimmed asset?)"
        )
    elif total > PACK_WARN_BYTES:
        warnings.append(
            f"the pack is {total / 1048576:.1f} MiB, past the {PACK_WARN_BYTES / 1048576:.0f} "
            "MiB warning line; the last release was 1.4 MiB, so something new is heavy"
        )
    return problems, warnings


def _human(size: int) -> str:
    if size >= MiB:
        return f"{size / MiB:.2f} MiB"
    return f"{size / KiB:.0f} KiB"


def category_totals(entries: list[tuple[str, int]]) -> dict[str, dict]:
    """Per-category count, total size, largest file and budget state.

    This is the part that answers "where did the build grow": one line per kind of asset,
    with the biggest file of that kind next to it, instead of a flat list of 256 paths.
    """
    totals: dict[str, dict] = {
        category.name: {"count": 0, "bytes": 0, "largest": ("", 0)} for category in CATEGORIES
    }
    for name, size in entries:
        bucket = totals[classify(name).name]
        bucket["count"] += 1
        bucket["bytes"] += size
        if size > bucket["largest"][1]:
            bucket["largest"] = (name, size)
    return totals


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--exe", type=Path, help="executable with the pack embedded")
    source.add_argument("--pck", type=Path, help="standalone pack file")
    parser.add_argument("--list", action="store_true", help="print every packed path")
    parser.add_argument("--largest", type=int, default=8, help="how many big files to show")
    arguments = parser.parse_args(argv)

    path: Path = arguments.exe or arguments.pck
    if not path.is_file():
        print(f"FAIL: {path} does not exist", file=sys.stderr)
        annotate("error", "build missing", f"{path} does not exist")
        return 1

    try:
        entries, header = load(path, embedded=arguments.exe is not None)
    except PackError as error:
        print(f"FAIL: {path}: {error}", file=sys.stderr)
        annotate("error", "build unreadable", f"{path.name}: {error}")
        return 1

    entries.sort(key=lambda entry: entry[1], reverse=True)
    total = sum(size for _, size in entries)
    print(f"{path}: {len(entries)} file(s), {total / 1048576:.2f} MiB packed")
    print(f"pack format {header['version']}, written by Godot {header['engine']}")
    if arguments.exe is not None:
        exe_size = path.stat().st_size / 1048576
        print(f"executable: {exe_size:.1f} MiB (pack included)")
        if not 10 <= exe_size <= 150:
            message = f"{exe_size:.1f} MiB is not a plausible size for this build"
            print(f"FAIL: {message}", file=sys.stderr)
            annotate("error", "build size", message)
            return 1

    print(f"\nlargest {arguments.largest} entries:")
    for name, size in entries[: arguments.largest]:
        print(f"  {size / 1024:8.0f} KiB  {name}")

    # The per-category view, which is where a build's growth is actually visible: a pack
    # that doubled is either one heavy kind of asset or a little of everything, and this
    # line says which without anyone reading the full listing.
    totals = category_totals(entries)
    print("\nby category (warn / hard):")
    for category in CATEGORIES:
        bucket = totals[category.name]
        if not bucket["count"]:
            continue
        state = "over" if bucket["bytes"] > category.hard else "ok"
        print(
            f"  {category.name:8s} {bucket['count']:4d} file(s) {_human(bucket['bytes']):>9s}  "
            f"[{_human(category.warn)} / {_human(category.hard)}]  {state}"
            f"  largest: {bucket['largest'][0].rsplit('/', 1)[-1]} "
            f"{_human(bucket['largest'][1])}"
        )
    annotate(
        "notice",
        "bytes by category",
        ", ".join(
            f"{category.name} {_human(totals[category.name]['bytes'])}"
            for category in CATEGORIES
            if totals[category.name]["count"]
        ),
    )

    prefixes: dict[str, int] = {}
    for name, _ in entries:
        top = "/".join(name.split("/")[:3])
        prefixes[top] = prefixes.get(top, 0) + 1
    print("\nby directory:")
    for name, count in sorted(prefixes.items()):
        print(f"  {count:5d}  {name}")
    annotate(
        "notice",
        "packed directories",
        ", ".join(f"{name} ({count})" for name, count in sorted(prefixes.items())),
    )

    # `.godot/` is the one directory whose purpose is not obvious from its name: it holds the
    # exporter's converted copies of imported resources, addressed by hash. Breaking it down
    # by extension answers "what is all this" without making anyone read a full listing.
    imported: dict[str, int] = {}
    for name, _ in entries:
        if name.startswith("res://.godot/"):
            suffix = name.rsplit(".", 1)[-1] if "." in name else "(none)"
            imported[suffix] = imported.get(suffix, 0) + 1
    if imported:
        annotate(
            "notice",
            "imported data",
            ", ".join(f".{suffix} {count}" for suffix, count in sorted(imported.items())),
        )

    if arguments.list:
        print("\nall entries:")
        for name, size in sorted(entries):
            print(f"  {size:9d}  {name}")

    problems, warnings = verify(entries, header)
    for warning in warnings:
        print(f"WARN: {warning}", file=sys.stderr)
        # Warnings do not fail the release: they are what a release should say about itself
        # while it is still affordable to fix. The annotation makes them visible without
        # anyone opening the step log.
        annotate("warning", "build budget", warning)
    if problems:
        print("", file=sys.stderr)
        for problem in problems:
            print(f"FAIL: {problem}", file=sys.stderr)
            # The step log is not always reachable from the API (the logs endpoint is a
            # redirect to storage that a restricted client may not be able to read), so the
            # verdict has to be legible from the annotations alone.
            annotate("error", "build contents", problem)
        if any("nothing under" in problem for problem in problems):
            # "The game is not in it" is only actionable next to what *is* in it.
            sample = ", ".join(path for path, _ in entries[:25])
            annotate("error", "packed paths (first 25)", sample)
        return 1
    print("\nPASS: the build carries the game and nothing else")
    if warnings:
        print(f"PASS with {len(warnings)} warning(s): inside every hard limit, worth a look")
    annotate(
        "notice",
        "build contents",
        f"{len(entries)} file(s), {total / 1048576:.2f} MiB packed; largest: "
        + ", ".join(f"{name.rsplit('/', 1)[-1]} {size / 1024:.0f} KiB" for name, size in entries[:3]),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
