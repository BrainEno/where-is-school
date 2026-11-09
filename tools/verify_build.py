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


class _Cursor:
    """A bounds-checked big-endian reader over the pack bytes."""

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


def _read_directory(
    blob: bytes, base: int, directory_offset: int, count: int, has_flags: bool
) -> list[tuple[str, int]]:
    cursor = _Cursor(blob, directory_offset)
    entries: list[tuple[str, int]] = []
    for index in range(count):
        path_length = cursor.u32()
        if path_length == 0 or path_length > 4096:
            raise PackError(f"entry {index} has an implausible path length ({path_length})")
        raw = cursor.read(path_length)
        cursor.skip((4 - path_length % 4) % 4)
        cursor.u64()  # offset into the pack data
        size = cursor.u64()
        cursor.skip(16)  # the entry's md5
        if has_flags:
            cursor.u32()
        path = raw.rstrip(b"\x00").decode("utf-8", "replace")
        if not path.startswith("res://"):
            raise PackError(f"entry {index} is not a res:// path ({path[:40]!r})")
        entries.append((path, size))
    return entries


def read_pack(blob: bytes, base: int) -> tuple[list[tuple[str, int]], dict[str, int]]:
    """Return (path, size) entries and the header, from a pack starting at `base`.

    Two things about the layout are not documented in one place and differ between an
    embedded pack (appended to an executable) and a standalone one: whether `file_base` is
    relative to the pack magic or absolute in the file, and whether the directory entries
    carry the trailing `flags` word. Rather than assume, every combination is tried and the
    first one that parses into a directory of `res://` paths wins. A structure that parses
    into nonsense is rejected, so a wrong guess cannot masquerade as a short file list.
    """
    if blob[base : base + 4] != MAGIC:
        raise PackError(
            f"no 'GDPC' magic at offset {base}; the bytes there are {blob[base : base + 32].hex()}"
        )
    if base + 32 > len(blob):
        raise PackError(f"the pack header is truncated ({len(blob) - base} bytes from the magic)")
    pack_version, major, minor, patch, flags, file_base = struct.unpack_from(
        "<IIIIIQ", blob, base + 4
    )
    if pack_version < 1:
        raise PackError(
            f"unknown pack version {pack_version}; header begins {blob[base : base + 32].hex()}"
        )
    header = {
        "version": pack_version,
        "engine": f"{major}.{minor}.{patch}",
        "base": file_base,
    }

    problems: list[str] = []
    for directory_base in (base + file_base, file_base):
        if directory_base + 4 > len(blob):
            problems.append(f"directory at 0x{directory_base:x} is past the end of the file")
            continue
        count = struct.unpack_from("<I", blob, directory_base)[0]
        if count > 20000:
            problems.append(f"directory at 0x{directory_base:x} claims {count} files")
            continue
        for has_flags in (pack_version >= 2, not pack_version >= 2):
            try:
                entries = _read_directory(blob, base, directory_base + 4, count, has_flags)
            except PackError as error:
                problems.append(
                    f"directory at 0x{directory_base:x}, flags={'yes' if has_flags else 'no'}: {error}"
                )
                continue
            header["base"] = directory_base - base
            return entries, header
    raise PackError(
        "could not read the pack directory. Header "
        f"{blob[base : base + 32].hex()}. Tried: " + "; ".join(problems)
    )


def load(path: Path, embedded: bool) -> tuple[list[tuple[str, int]], dict[str, int]]:
    blob = path.read_bytes()
    if not embedded:
        return read_pack(blob, 0)

    # The pack is appended to the executable, so the magic is somewhere near the end — but
    # "near the end" is not "the last occurrence": an executable can end with bytes that
    # happen to spell GDPC (the first CI run of this tool found one four bytes from the end
    # of the file and reported a truncated header). Every occurrence is therefore tried,
    # newest first, and the first one that parses into a directory of res:// paths wins.
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
