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

# No single file in a build of this game has any business being this big. The unsplit font
# (10 MiB) and a packed screenshot (~380 KiB each, 65 of them) are the two things that
# would. Sizes are read from the directory, so this catches them even when they land under
# a `.godot/exported/` hash instead of the path they came from.
MAX_ENTRY_BYTES = 2 * 1024 * 1024
MAX_PACK_BYTES = 16 * 1024 * 1024


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


def verify(entries: list[tuple[str, int]], header: dict[str, int]) -> list[str]:
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

    oversized = [(name, size) for name, size in entries if size > MAX_ENTRY_BYTES]
    for name, size in oversized[:5]:
        problems.append(
            f"{name} is {size / 1048576:.2f} MiB, over the {MAX_ENTRY_BYTES / 1048576:.0f} MiB "
            "per-file budget: the unsplit font, a packed screenshot, or an untrimmed asset"
        )

    total = sum(size for _, size in entries)
    if total > MAX_PACK_BYTES:
        problems.append(
            f"the pack is {total / 1048576:.1f} MiB, over the {MAX_PACK_BYTES / 1048576:.0f} "
            "MiB budget: something large got packed (screenshots? models? an untrimmed asset?)"
        )
    del header
    return problems


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

    problems = verify(entries, header)
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
    annotate(
        "notice",
        "build contents",
        f"{len(entries)} file(s), {total / 1048576:.2f} MiB packed; largest: "
        + ", ".join(f"{name.rsplit('/', 1)[-1]} {size / 1024:.0f} KiB" for name, size in entries[:3]),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
