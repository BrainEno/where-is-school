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

# A release build has to carry the game and nothing else. Each of these is a directory that
# exists in the repository but must never reach a player's disk.
FORBIDDEN_PREFIXES = (
    "res://tests/",
    "res://tools/",
    "res://docs/",
    "res://art/",
    "res://.github/",
)

# Things whose absence means the build would start and immediately misbehave or crash.
REQUIRED_PREFIXES = (
    "res://scenes/main/main.tscn",
    "res://assets/ui/app_theme.tres",
    "res://data/dialogue/en/",
    "res://data/dialogue/zh-CN/",
    "res://data/inspections/en/",
    "res://assets/audio/",
)

MAX_FONT_BYTES = 1024 * 1024
MAX_PACK_BYTES = 16 * 1024 * 1024


class PackError(Exception):
    pass


def read_pack(blob: bytes, base: int) -> tuple[list[tuple[str, int]], dict[str, int]]:
    """Return (path, size) entries and the header, from a pack starting at `base`."""
    if blob[base : base + 4] != MAGIC:
        raise PackError(f"no 'GDPC' magic at offset {base}")
    if base + 32 > len(blob):
        raise PackError("the pack header is truncated")
    pack_version, major, minor, patch, _flags, file_base = struct.unpack_from(
        "<IIIIIQ", blob, base + 4
    )
    if pack_version < 1:
        raise PackError(f"unknown pack version {pack_version}")
    if base + file_base + 4 > len(blob):
        raise PackError(
            f"the directory offset points outside the file ({file_base} past {len(blob) - base} bytes)"
        )
    count = struct.unpack_from("<I", blob, base + file_base)[0]
    cursor = base + file_base + 4
    entries: list[tuple[str, int]] = []
    for _ in range(count):
        (path_length,) = struct.unpack_from("<I", blob, cursor)
        cursor += 4
        raw = blob[cursor : cursor + path_length]
        cursor += (path_length + 3) & ~3
        offset, size = struct.unpack_from("<QQ", blob, cursor)
        cursor += 16 + 16  # offset + size, then the entry's md5
        if pack_version >= 2:
            cursor += 4  # flags
        if cursor > len(blob):
            raise PackError("the pack directory runs past the end of the file")
        entries.append((raw.rstrip(b"\x00").decode("utf-8", "replace"), size))
        del offset
    return entries, {
        "version": pack_version,
        "engine": f"{major}.{minor}.{patch}",
        "base": file_base,
    }


def load(path: Path, embedded: bool) -> tuple[list[tuple[str, int]], dict[str, int]]:
    blob = path.read_bytes()
    start = 0
    if embedded:
        # The pack is appended to the executable; take the last magic so an executable
        # that happens to contain the bytes earlier still resolves to the real pack.
        start = blob.rfind(MAGIC)
        while start != -1 and start + 24 > len(blob):
            start = blob.rfind(MAGIC, 0, start)
        if start == -1:
            raise PackError(
                "no 'GDPC' magic found in this file. Either the export did not embed the "
                "pack (binary_format/embed_pck), or the export failed and left a bare "
                "template executable."
            )
    return read_pack(blob, start)


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

    font = sizes.get("res://assets/fonts/NotoSansSC-Regular.ttf")
    if font is None:
        problems.append("the bundled font is not in the build")
    elif font > MAX_FONT_BYTES:
        problems.append(
            f"the bundled font is {font / 1048576:.2f} MiB — the subset is ~330 KiB, so "
            "this is the unsplit source font (tools/subset_font.py)"
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
        return 1

    try:
        entries, header = load(path, embedded=arguments.exe is not None)
    except PackError as error:
        print(f"FAIL: {path}: {error}", file=sys.stderr)
        return 1

    entries.sort(key=lambda entry: entry[1], reverse=True)
    total = sum(size for _, size in entries)
    print(f"{path}: {len(entries)} file(s), {total / 1048576:.2f} MiB packed")
    print(f"pack format {header['version']}, written by Godot {header['engine']}")
    if arguments.exe is not None:
        exe_size = path.stat().st_size / 1048576
        print(f"executable: {exe_size:.1f} MiB (pack included)")
        if not 10 <= exe_size <= 150:
            print(f"FAIL: {exe_size:.1f} MiB is not a plausible size for this build", file=sys.stderr)
            return 1

    print(f"\nlargest {arguments.largest} entries:")
    for name, size in entries[: arguments.largest]:
        print(f"  {size / 1024:8.0f} KiB  {name}")

    if arguments.list:
        print("\nall entries:")
        for name, size in sorted(entries):
            print(f"  {size:9d}  {name}")

    problems = verify(entries, header)
    if problems:
        print("", file=sys.stderr)
        for problem in problems:
            print(f"FAIL: {problem}", file=sys.stderr)
        return 1
    print("\nPASS: the build carries the game and nothing else")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
