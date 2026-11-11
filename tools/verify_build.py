#!/usr/bin/env python3
"""Check what is actually inside a build, not what the export preset promised.

An export preset is a wish list. The only way to know whether `tests/` really stayed out
of the build, whether the 10 MB source font stayed out, and whether the dialogue JSON was
packed at all, is to read the pack file back.

Usage (from the repository root, after an export):

    python3 tools/verify_build.py --exe build/windows/where-is-school.exe
    python3 tools/verify_build.py --pck build/windows/where-is-school.pck
    python3 tools/verify_build.py --package dist/where-is-school-0.1.0-windows.zip --expect-version 0.1.0
    python3 tools/verify_build.py --preset export_presets.cfg --expect-version 0.1.0

`--package` is what a release is checked with: it reads the zip a player downloads, checks
its layout and naming, then reads the executable out of it and checks that too — the icon
and version resources Windows will show, the ELF header Linux needs, and the pack inside
either. `--preset` is the cheap pre-flight: the same claims, read from the preset file,
before an export that takes twenty minutes. Neither replaces the other; the preset says what
should have happened and the file says what did.

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
import zipfile
from dataclasses import dataclass, field
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
    # Development-only preview scenes. They are useful to look at and are not part of the
    # game; the export preset excludes them and this list keeps that honest, the same way
    # it does for addons/.
    "res://scenes/dev/",
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


def load_blob(blob: bytes, embedded: bool) -> tuple[list[tuple[str, int]], dict[str, int]]:
    """Read a pack from bytes, so a caller can hand over an executable from inside a zip."""
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


def load(path: Path, embedded: bool) -> tuple[list[tuple[str, int]], dict[str, int]]:
    return load_blob(path.read_bytes(), embedded)


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


# ---------------------------------------------------------------------------------------
# The executable's own metadata: what Explorer and a file manager will show
# ---------------------------------------------------------------------------------------
#
# "The preset has an icon path" is not the same claim as "the executable carries an icon".
# Godot patches the Windows template's resource section during the export (natively since
# 4.x, `platform/windows/export/template_modifier.cpp`: no `rcedit`, no Wine), and everything
# it writes can be read back out of the finished file. So this section reads the PE resource
# directory — RT_ICON, RT_GROUP_ICON, RT_VERSION — and checks the resource, not the wish.
#
# Linux has no such thing: an ELF has no icon and no version resource, and the launcher file
# plays that role. So the Linux check is about the package: the desktop entry, the icon next
# to it, and an executable the file manager is allowed to run.

PE_SIGNATURE = b"PE\x00\x00"
ELF_MAGIC = b"\x7fELF"
RT_ICON = 3
RT_GROUP_ICON = 14
RT_VERSION = 16
VS_FIXEDFILEINFO_SIGNATURE = 0xFEEF04BD
# A resource directory entry's high bit means "this field is an offset, not an id".
RESOURCE_OFFSET_FLAG = 0x80000000
# What a version resource has to say about the product, beyond the numbers.
VERSION_STRINGS = ("FileVersion", "ProductVersion", "ProductName", "CompanyName", "FileDescription")


class PeError(Exception):
    """An executable whose resource section cannot be read."""


@dataclass
class Section:
    virtual_address: int
    virtual_size: int
    raw_size: int
    raw_pointer: int


def _pe_sections(blob: bytes) -> list[Section]:
    if len(blob) < 0x40 or blob[:2] != b"MZ":
        raise PeError("no MZ header: not a Windows executable")
    (pe_offset,) = struct.unpack_from("<I", blob, 0x3C)
    if blob[pe_offset : pe_offset + 4] != PE_SIGNATURE:
        raise PeError(f"no PE signature at 0x{pe_offset:x}")
    (section_count,) = struct.unpack_from("<H", blob, pe_offset + 6)
    (optional_size,) = struct.unpack_from("<H", blob, pe_offset + 20)
    sections = []
    table = pe_offset + 24 + optional_size
    for index in range(section_count):
        entry = table + 40 * index
        if entry + 40 > len(blob):
            raise PeError(f"section header {index} runs past the end of the file")
        virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from("<IIII", blob, entry + 8)
        sections.append(Section(virtual_address, virtual_size, raw_size, raw_pointer))
    if not sections:
        raise PeError("no sections: not a linked executable")
    return sections


def _offset_for_rva(sections: list[Section], rva: int) -> int:
    for section in sections:
        span = max(section.virtual_size, section.raw_size)
        if section.virtual_address <= rva < section.virtual_address + span:
            return section.raw_pointer + (rva - section.virtual_address)
    raise PeError(f"address 0x{rva:x} is in no section")


def _resource_name(blob: bytes, base: int, offset: int) -> str:
    (length,) = struct.unpack_from("<H", blob, base + offset)
    return blob[base + offset + 2 : base + offset + 2 + 2 * length].decode("utf-16-le", "replace")


def _walk_resources(
    blob: bytes, base: int, offset: int, chain: tuple, found: list[tuple[tuple, int, int]]
) -> None:
    if len(chain) > 3:
        # Deeper than type/name/language: nothing in a Windows resource section goes there.
        return
    header = base + offset
    _characteristics, _stamp, _major, _minor, named, ids = struct.unpack_from("<IIHHHH", blob, header)
    for index in range(named + ids):
        name_field, data_field = struct.unpack_from("<II", blob, header + 16 + 8 * index)
        name: object = _resource_name(blob, base, name_field & ~RESOURCE_OFFSET_FLAG) if name_field & RESOURCE_OFFSET_FLAG else name_field
        if data_field & RESOURCE_OFFSET_FLAG:
            _walk_resources(blob, base, data_field & ~RESOURCE_OFFSET_FLAG, chain + (name,), found)
        else:
            data_rva, size = struct.unpack_from("<II", blob, base + data_field)
            found.append((chain + (name,), data_rva, size))


def read_pe_resources(blob: bytes) -> dict[int, dict[object, bytes]]:
    """`{type id: {name id: bytes}}` for every resource in a Windows executable."""
    sections = _pe_sections(blob)
    (pe_offset,) = struct.unpack_from("<I", blob, 0x3C)
    (optional_size,) = struct.unpack_from("<H", blob, pe_offset + 20)
    optional = pe_offset + 24
    (magic,) = struct.unpack_from("<H", blob, optional)
    directories = optional + (96 if magic == 0x10B else 112 if magic == 0x20B else 0)
    if not directories:
        raise PeError(f"unknown optional header magic 0x{magic:x}")
    resource_rva, resource_size = struct.unpack_from("<II", blob, directories + 16)
    if not resource_rva or not resource_size:
        raise PeError("the executable has no resource directory")
    base = _offset_for_rva(sections, resource_rva)
    found: list[tuple[tuple, int, int]] = []
    _walk_resources(blob, base, 0, (), found)
    resources: dict[int, dict[object, bytes]] = {}
    for chain, rva, size in found:
        if len(chain) != 3:
            continue
        kind, name, _language = chain
        if not isinstance(kind, int):
            continue
        offset = _offset_for_rva(sections, rva)
        resources.setdefault(kind, {})[name] = blob[offset : offset + size]
    return resources


def _version_block(blob: bytes, offset: int) -> dict:
    """One VS_VERSIONINFO-ish block: length, key, value and children."""
    length, value_length, kind = struct.unpack_from("<HHH", blob, offset)
    position = offset + 6
    end_of_key = position
    while end_of_key + 2 <= len(blob) and blob[end_of_key : end_of_key + 2] != b"\x00\x00":
        end_of_key += 2
    key = blob[position:end_of_key].decode("utf-16-le", "replace")
    # Alignment is relative to the block's own start, not to the file's.
    position = end_of_key + 2 + ((-(end_of_key + 2 - offset)) % 4)
    if kind == 1:
        value = blob[position : position + 2 * value_length]
        position += 2 * value_length
    elif value_length:
        value = blob[position : position + value_length]
        position += value_length
    else:
        value = b""
    position += (-(position - offset)) % 4
    limit = min(offset + length, len(blob))
    children = []
    while position + 6 <= limit:
        (child_length,) = struct.unpack_from("<H", blob, position)
        if child_length == 0:
            break
        children.append(_version_block(blob, position))
        position = (position + child_length + 3) & ~3
    return {"key": key, "value": value, "children": children}


def read_version_info(payload: bytes) -> tuple[dict[str, str], dict[str, int]]:
    """The `StringFileInfo` strings and the `VS_FIXEDFILEINFO` numbers of a version resource."""
    root = _version_block(payload, 0)
    if root["key"] != "VS_VERSION_INFO":
        raise PeError(f'the version resource starts with {root["key"]!r}, not "VS_VERSION_INFO"')
    strings: dict[str, str] = {}
    for child in root["children"]:
        if child["key"] != "StringFileInfo":
            continue
        for table in child["children"]:
            for entry in table["children"]:
                strings[entry["key"]] = entry["value"].decode("utf-16-le", "replace").rstrip("\x00")
    fixed: dict[str, int] = {}
    value = root["value"]
    if len(value) >= 24:
        signature, _structure = struct.unpack_from("<II", value, 0)
        file_ms, file_ls, product_ms, product_ls = struct.unpack_from("<IIII", value, 8)
        fixed = {
            "signature": signature,
            "file_ms": file_ms,
            "file_ls": file_ls,
            "product_ms": product_ms,
            "product_ls": product_ls,
        }
    return strings, fixed


def resource_version_of(version: str) -> tuple[str, str]:
    """`("0.1.0-rc.1")` -> the four-part resource form `("0.1.0.0", "0.1.0")`.

    A version resource holds four integers, so the prerelease tail of a tag cannot survive
    into it; the package name carries the full string and the executable carries the numbers.
    """
    core = version.split("-", 1)[0]
    parts = core.split(".")
    if len(parts) != 3:
        raise ValueError(f"{version!r} is not MAJOR.MINOR.PATCH")
    for part in parts:
        if not part.isdigit() or int(part) > 65535:
            raise ValueError(f"{version!r} does not fit in a version resource")
    return ".".join(parts + ["0"]), ".".join(parts)


def _pack_words(number: int) -> tuple[int, int]:
    return (number >> 16) & 0xFFFF, number & 0xFFFF


def verify_windows_metadata(blob: bytes, expect_version: str | None) -> tuple[list[str], list[str]]:
    """Check the icon and version resources of a finished Windows executable."""
    problems: list[str] = []
    notes: list[str] = []
    try:
        resources = read_pe_resources(blob)
    except PeError as error:
        return [f"{error}"], notes

    groups = resources.get(RT_GROUP_ICON) or {}
    icons = resources.get(RT_ICON) or {}
    if not groups:
        problems.append(
            "the executable has no icon resource (RT_GROUP_ICON), so it would show the "
            "engine's default icon; application/modify_resources and application/icon "
            "have to be set for the export to patch it in"
        )
    else:
        group = next(iter(groups.values()))
        if len(group) < 6:
            problems.append("the icon group is too short to be an icon directory")
        else:
            reserved, kind, count = struct.unpack_from("<HHH", group, 0)
            if (reserved, kind) != (0, 1):
                problems.append(f"the icon group is not an icon directory (reserved {reserved}, type {kind})")
            else:
                sizes, named = [], []
                for index in range(min(count, (len(group) - 6) // 14)):
                    width, _height, _colours, _res, _planes, _bits, _length, ident = struct.unpack_from(
                        "<BBBBHHIH", group, 6 + 14 * index
                    )
                    sizes.append(width or 256)
                    named.append(ident)
                notes.append("icon " + "/".join(str(size) for size in sorted(sizes)) + " px")
                if len(sizes) < 2:
                    problems.append(
                        f"the executable carries a single {sizes[0] if sizes else 0} px icon; "
                        "Windows wants small and large sizes in one file"
                    )
                if sizes and max(sizes) < 48:
                    problems.append(
                        f"the largest icon is {max(sizes)} px; a taskbar and an alt-tab entry need 48 or more"
                    )
                missing = [ident for ident in named if ident not in icons]
                if missing:
                    problems.append(
                        f"the icon group names image(s) {missing[:4]} that are not in the file "
                        f"(RT_ICON holds {sorted(icons)[:8]})"
                    )

    versions = resources.get(RT_VERSION) or {}
    if not versions:
        problems.append(
            "the executable has no version resource (RT_VERSION): Explorer would show no "
            "version and no publisher"
        )
    else:
        payload = next(iter(versions.values()))
        try:
            strings, fixed = read_version_info(payload)
        except (PeError, struct.error) as error:
            problems.append(f"the version resource cannot be read: {error}")
            strings, fixed = {}, {}
        if strings:
            missing = [key for key in VERSION_STRINGS if not strings.get(key, "").strip()]
            if missing:
                problems.append("the version resource leaves " + ", ".join(missing) + " empty")
            notes.append(
                f'version {strings.get("FileVersion", "?")}, '
                f'{strings.get("ProductName", "?")} by {strings.get("CompanyName", "?")}'
            )
        if fixed:
            if fixed.get("signature") != VS_FIXEDFILEINFO_SIGNATURE:
                problems.append(
                    f'the fixed version block has signature 0x{fixed.get("signature", 0):08X}, '
                    f"expected 0x{VS_FIXEDFILEINFO_SIGNATURE:08X}"
                )
            if fixed.get("file_ms") != fixed.get("product_ms") or fixed.get("file_ls") != fixed.get("product_ls"):
                problems.append(
                    "the file version and the product version differ in the executable; a "
                    "release build should carry the same version in both"
                )
            if expect_version:
                try:
                    expected, _core = resource_version_of(expect_version)
                except ValueError as error:
                    problems.append(str(error))
                else:
                    want = [int(part) for part in expected.split(".")]
                    have = _pack_words(fixed.get("file_ms", 0)) + _pack_words(fixed.get("file_ls", 0))
                    if tuple(want) != have:
                        problems.append(
                            f"the executable says version {'.'.join(str(part) for part in have)}, "
                            f"the release is {expected}"
                        )
                    if strings and strings.get("FileVersion", "") != expected:
                        problems.append(
                            f'the version resource string FileVersion is {strings.get("FileVersion")!r}, '
                            f"expected {expected!r}"
                        )
    return problems, notes


def verify_linux_executable(blob: bytes) -> tuple[list[str], list[str]]:
    """The Linux half of the same question, which is mostly about being the right thing at all."""
    problems: list[str] = []
    notes: list[str] = []
    if len(blob) < 64 or not blob.startswith(ELF_MAGIC):
        return ["the file players run is not an ELF binary"], notes
    elf_class, elf_data = blob[4], blob[5]
    (kind,) = struct.unpack_from("<H", blob, 16)
    (machine,) = struct.unpack_from("<H", blob, 18)
    if (elf_class, elf_data) != (2, 1):
        problems.append(f"the ELF is class {elf_class}, data {elf_data}; a release is 64-bit little-endian")
    if machine != 0x3E:
        problems.append(f"the ELF targets machine 0x{machine:x}, not x86-64 (0x3e)")
    if kind not in (2, 3):
        problems.append(f"the ELF is type {kind}; expected an executable or a position-independent one")
    machine_name = {0x3E: "x86-64", 0x03: "x86", 0xB7: "arm64", 0x28: "arm", 0xF3: "riscv"}.get(machine, "unknown")
    notes.append(
        f"ELF {'64-bit' if elf_class == 2 else '32-bit'} type {kind}, machine 0x{machine:02x} ({machine_name})"
    )
    return problems, notes


# ---------------------------------------------------------------------------------------
# The package: what a player receives
# ---------------------------------------------------------------------------------------

# Directories that must never appear in a package, whatever platform it is for. The pack
# check already keeps them out of the data; this keeps them out of the archive around it,
# which is where a stray `export.log` or a copied `docs/` folder actually lands.
PACKAGE_FORBIDDEN_PREFIXES = (
    "tests/",
    "tools/",
    "docs/",
    "art/",
    "addons/",
    ".github/",
    "scenes/dev/",
    "scripts/dev/",
)
PACKAGE_FORBIDDEN_NAMES = (
    ".DS_Store",
    "Thumbs.db",
    ".gitignore",
    ".gitattributes",
)
PACKAGE_FORBIDDEN_SUFFIXES = (".log", ".pdb", ".tmp", ".import", ".pck", ".md5", ".uid")

# What each platform's package must contain, relative to the folder inside the zip. `{stem}`
# is the executable's name on that platform. Godot emits `where-is-school.exe` on Windows and
# `where-is-school.x86_64` on Linux; both are copied in under a name a player can type.
PACKAGE_REQUIRED = {
    "windows": ("where-is-school.exe", "HOW-TO-RUN.txt", "licences/COPYRIGHT.md", "licences/NotoSansSC-OFL.txt"),
    "linux": (
        "where-is-school",
        "where-is-school.desktop",
        "where-is-school.png",
        "README.txt",
        "HOW-TO-RUN.txt",
        "licences/COPYRIGHT.md",
        "licences/NotoSansSC-OFL.txt",
    ),
}
PACKAGE_EXECUTABLE = {"windows": "where-is-school.exe", "linux": "where-is-school"}
PACKAGE_SUFFIX = {"windows": "-windows", "linux": "-linux"}


@dataclass
class Package:
    """A built archive, read into memory, with what the checks found wrong with it."""

    path: Path
    platform: str
    folder: str
    version: str
    executable: str | None = None
    blob: bytes = b""
    problems: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


def inspect_package(path: Path, expect_version: str | None) -> Package:
    """Open a release archive and check its layout, naming and executable."""
    package = Package(path=path, platform="", folder="", version="")
    try:
        archive = zipfile.ZipFile(path)
    except (OSError, zipfile.BadZipFile) as error:
        package.problems.append(f"{path.name} is not a readable zip: {error}")
        return package

    with archive:
        infos = {info.filename: info for info in archive.infolist()}
        names = list(infos)
        if not names:
            package.problems.append(f"{path.name} is empty")
            return package

        tops = {name.split("/", 1)[0] for name in names}
        if len(tops) != 1:
            package.problems.append(
                f"{path.name} has {len(tops)} top-level entries ({sorted(tops)[:4]}); a package "
                "is one folder, so that unzipping it cannot scatter files"
            )
            return package
        folder = tops.pop()
        package.folder = folder
        if any(not name.startswith(folder + "/") for name in names):
            package.problems.append(f"{path.name} has entries outside its {folder}/ folder")
        if any(name.startswith("/") or ".." in name.split("/") for name in names):
            package.problems.append(f"{path.name} contains an absolute or escaping path")

        # `where-is-school-0.1.0-rc.1-linux.zip` -> version `0.1.0-rc.1`, platform `linux`.
        stem = path.name[: -len(".zip")] if path.name.endswith(".zip") else path.name
        platform = next((name for name, suffix in PACKAGE_SUFFIX.items() if stem.endswith(suffix)), "")
        if not platform:
            package.problems.append(
                f"{path.name} does not end with one of {sorted(PACKAGE_SUFFIX.values())}; "
                "a download has to say which platform it is for"
            )
            return package
        package.platform = platform
        version = stem[len("where-is-school-") : -len(PACKAGE_SUFFIX[platform])] if stem.startswith("where-is-school-") else ""
        package.version = version
        if not version:
            package.problems.append(f"{path.name} does not carry a version in its name")
        elif expect_version and version != expect_version:
            package.problems.append(f"{path.name} is version {version!r}, the build is {expect_version!r}")
        if folder != stem:
            package.problems.append(
                f"the folder inside {path.name} is {folder!r}; it should be {stem!r} so the "
                "two never disagree about the version"
            )

        relative = [name[len(folder) + 1 :] for name in names if name.startswith(folder + "/")]
        present = {name for name in relative if name and not name.endswith("/")}
        for required in PACKAGE_REQUIRED[platform]:
            if required not in present:
                package.problems.append(f"{path.name} is missing {required}")

        for name in sorted(present):
            if name.startswith(PACKAGE_FORBIDDEN_PREFIXES):
                package.problems.append(f"{path.name} carries {name}, which is not part of a release")
            elif name.rsplit("/", 1)[-1] in PACKAGE_FORBIDDEN_NAMES:
                package.problems.append(f"{path.name} carries {name}, a leftover from a working tree")
            elif name.endswith(PACKAGE_FORBIDDEN_SUFFIXES):
                package.problems.append(f"{path.name} carries {name}, which is build output or a log")

        executable = PACKAGE_EXECUTABLE[platform]
        package.executable = executable
        if executable not in present:
            return package
        package.blob = archive.read(f"{folder}/{executable}")
        package.notes.append(f"{executable}: {_human(len(package.blob))}")

        if platform == "windows":
            problems, notes = verify_windows_metadata(package.blob, expect_version or version or None)
            package.problems.extend(problems)
            package.notes.extend(notes)
        else:
            problems, notes = verify_linux_executable(package.blob)
            package.problems.extend(problems)
            package.notes.extend(notes)
            info = infos[f"{folder}/{executable}"]
            mode = (info.external_attr >> 16) & 0o777
            if not mode & 0o111:
                package.problems.append(
                    f"{executable} is stored with mode {mode:o} in the zip; without the "
                    "executable bit the extracted game cannot be run"
                )
            launcher_problems, launcher_notes = _check_desktop_entry(archive, f"{folder}/", present)
            package.problems.extend(launcher_problems)
            package.notes.extend(launcher_notes)
    return package


def _check_desktop_entry(
    archive: zipfile.ZipFile, prefix: str, present: set[str]
) -> tuple[list[str], list[str]]:
    """The launcher and the icon it names, which is the Linux half of "the exe has an icon"."""
    problems: list[str] = []
    notes: list[str] = []
    try:
        text = archive.read(prefix + "where-is-school.desktop").decode("utf-8", "replace")
    except KeyError:
        return problems, notes
    fields = {}
    for line in text.splitlines():
        key, separator, value = line.partition("=")
        if separator and not key.startswith("#"):
            fields[key.strip()] = value.strip()
    for key in ("Type", "Name", "Exec", "Icon", "Categories"):
        if not fields.get(key):
            problems.append(f"where-is-school.desktop has no {key}= line")
    if fields.get("Type") != "Application":
        problems.append(f"where-is-school.desktop is type {fields.get('Type')!r}, not Application")
    icon = fields.get("Icon", "")
    if icon and f"{icon}.png" not in present:
        problems.append(
            f"where-is-school.desktop names icon {icon!r}, but the package has no {icon}.png "
            "next to it, so a menu entry would show a blank square"
        )
    if icon:
        try:
            png = archive.read(prefix + f"{icon}.png")
        except KeyError:
            png = b""
        width = height = 0
        if png[:8] == b"\x89PNG\r\n\x1a\n" and len(png) > 24:
            width, height = struct.unpack_from(">II", png, 16)
        if width < 128 or height < 128:
            problems.append(f"{icon}.png is {width}x{height}; a menu icon should be at least 128 px")
        else:
            notes.append(f"icon {width}x{height} px")
    if "where-is-school" not in fields.get("Exec", ""):
        problems.append(f"where-is-school.desktop runs {fields.get('Exec')!r}, not the game")
    notes.append(f"launcher {fields.get('Name', '?')}, {fields.get('Categories', '?')}")
    return problems, notes


# ---------------------------------------------------------------------------------------
# The preset: the cheap check, before the expensive export
# ---------------------------------------------------------------------------------------


def verify_presets(path: Path, expect_version: str | None) -> tuple[list[str], list[str]]:
    """What the preset file claims, checked before twenty minutes of exporting.

    This is not a substitute for reading the finished executable — it is the reason a broken
    preset fails in seconds instead of after an export, and it is why the two checks exist
    side by side: the preset says what should happen, the resource section says what did.
    """
    from export_presets import PresetError, read

    problems: list[str] = []
    notes: list[str] = []
    try:
        presets = read(path)
    except PresetError as error:
        return [f"{error}"], notes

    windows = presets.get("Windows Desktop")
    if not windows:
        problems.append("export_presets.cfg has no 'Windows Desktop' preset")
    else:
        options = windows.options
        if options.get("application/modify_resources") != "true":
            problems.append(
                "the Windows preset has application/modify_resources off, so the export would "
                "not write an icon or a version into the executable at all"
            )
        icon = options.get("application/icon", "")
        if not icon:
            problems.append("the Windows preset has no application/icon")
        else:
            relative = icon[len("res://") :] if icon.startswith("res://") else icon
            if not (path.parent / relative).is_file():
                problems.append(f"the Windows preset's icon {icon} does not exist")
            elif not relative.lower().endswith((".ico", ".png", ".svg", ".webp")):
                problems.append(f"the Windows preset's icon {icon} is not an image Godot can convert")
            else:
                notes.append(f"icon {relative}")
        if options.get("binary_format/embed_pck") != "true":
            problems.append(
                "the Windows preset does not embed the pack, so the zip would need a .pck next to the exe"
            )
        for key in ("application/product_name", "application/company_name", "application/file_description", "application/copyright"):
            if not options.get(key, "").strip():
                problems.append(f"the Windows preset leaves {key} empty, so the version resource would too")
        for key in ("application/file_version", "application/product_version"):
            value = options.get(key, "")
            if not value:
                problems.append(f"the Windows preset leaves {key} empty")
            elif expect_version:
                try:
                    expected, _core = resource_version_of(expect_version)
                except ValueError as error:
                    problems.append(str(error))
                    break
                if value != expected:
                    problems.append(f"the Windows preset says {key}={value!r}, the build is {expected!r}")
        if not problems:
            notes.append(f"Windows: version {options.get('application/file_version')}, metadata on")

    linux = presets.get("Linux")
    if not linux:
        problems.append("export_presets.cfg has no 'Linux' preset, so there is no Linux build to publish")
    else:
        if linux.options.get("binary_format/embed_pck") != "true":
            problems.append("the Linux preset does not embed the pack")
        architecture = linux.options.get("binary_format/architecture", "")
        if architecture != "x86_64":
            problems.append(f"the Linux preset builds for {architecture!r}, not x86_64")
        if not linux.export_path:
            problems.append("the Linux preset has no export_path")
        else:
            notes.append(f"Linux: {linux.export_path}, {architecture}, pack embedded")

    for preset in (windows, linux):
        if not preset:
            continue
        excluded = preset.exclude_filter
        for where in ("tests/", "tools/", "docs/", "art/"):
            if where.rstrip("/") not in excluded:
                problems.append(f"the {preset.name} preset does not exclude {where} from the pack")
    return problems, notes

def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--exe", type=Path, help="executable with the pack embedded")
    source.add_argument("--pck", type=Path, help="standalone pack file")
    source.add_argument("--package", type=Path, help="a release zip: layout, executable and pack")
    source.add_argument("--preset", type=Path, help="export_presets.cfg, checked without exporting")
    parser.add_argument(
        "--expect-version",
        help="the version this build claims to be, 0.1.0 or 0.1.0-rc.1; the executable gets "
        "the four-part form of it and the package name keeps the whole string",
    )
    parser.add_argument("--list", action="store_true", help="print every packed path")
    parser.add_argument("--largest", type=int, default=8, help="how many big files to show")
    arguments = parser.parse_args(argv)

    # The cheap check first: a preset that says the wrong thing costs a second, and an
    # export costs twenty minutes.
    if arguments.preset is not None:
        problems, notes = verify_presets(arguments.preset, arguments.expect_version)
        for note in notes:
            print(f"  {note}")
        for problem in problems:
            print(f"FAIL: {problem}", file=sys.stderr)
            annotate("error", "export preset", problem)
        if problems:
            return 1
        print("PASS: the presets describe the build this workflow expects")
        annotate("notice", "export presets", "; ".join(notes) or "presets checked")
        return 0

    metadata_problems: list[str] = []
    metadata_notes: list[str] = []
    blob = b""

    if arguments.package is not None:
        if not arguments.package.is_file():
            print(f"FAIL: {arguments.package} does not exist", file=sys.stderr)
            annotate("error", "package missing", f"{arguments.package} does not exist")
            return 1
        package = inspect_package(arguments.package, arguments.expect_version)
        print(f"{arguments.package.name}: {package.platform or 'unknown platform'} package")
        for note in package.notes:
            print(f"  {note}")
        for problem in package.problems:
            print(f"FAIL: {problem}", file=sys.stderr)
            annotate("error", "package layout", problem)
        if package.problems:
            return 1
        blob = package.blob
        path = arguments.package
        # `inspect_package` has already checked this executable's icon, version or ELF
        # header; the notes it printed above are the record of that.
        label = f"{arguments.package.name}: {package.executable}"
    else:
        path: Path = arguments.exe or arguments.pck
        if not path.is_file():
            print(f"FAIL: {path} does not exist", file=sys.stderr)
            annotate("error", "build missing", f"{path} does not exist")
            return 1
        blob = path.read_bytes()
        label = str(path)

    try:
        entries, header = load_blob(blob, embedded=arguments.pck is None)
    except PackError as error:
        print(f"FAIL: {path}: {error}", file=sys.stderr)
        annotate("error", "build unreadable", f"{path.name}: {error}")
        return 1

    # The metadata check answers "what will Explorer or a file manager show", which the pack
    # cannot answer. A package has already been through it in `inspect_package`; a bare
    # executable gets the same treatment here so that a local run is not weaker than CI.
    if arguments.package is None and (arguments.exe is not None):
        if blob.startswith(ELF_MAGIC):
            metadata_problems, metadata_notes = verify_linux_executable(blob)
        else:
            metadata_problems, metadata_notes = verify_windows_metadata(blob, arguments.expect_version)
        for note in metadata_notes:
            print(f"  {note}")
        for problem in metadata_problems:
            print(f"FAIL: {problem}", file=sys.stderr)
            annotate("error", "build metadata", problem)
        if metadata_problems:
            return 1

    entries.sort(key=lambda entry: entry[1], reverse=True)
    total = sum(size for _, size in entries)
    print(f"{label}: {len(entries)} file(s), {total / 1048576:.2f} MiB packed")
    print(f"pack format {header['version']}, written by Godot {header['engine']}")
    if arguments.pck is None:
        exe_size = len(blob) / 1048576
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
