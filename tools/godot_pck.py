"""Read the complete, unencrypted PCK shipped by this project's release exports.

The layout and relative-base rules follow Godot 4.7.2-stable's
core/io/file_access_pack.cpp and editor/export/editor_export_platform.cpp.
A directory listing is not proof that its payload exists: ranges and MD5s are
checked before returning the familiar (path, size) inventory to verify_build.
This is an integrity check, not a signature or an authenticity claim.
"""

from __future__ import annotations

import hashlib
import struct
import unicodedata
from dataclasses import dataclass

MAGIC = b"GDPC"
SUPPORTED_FORMATS = (2, 3, 4)
RESERVED_WORDS = 16
MAX_FILES = 20_000
MAX_PATH_BYTES = 4096
PACK_DIR_ENCRYPTED = 1
PACK_REL_FILEBASE = 2
PACK_SPARSE_BUNDLE = 4


class PackError(Exception):
    """A pack cannot be verified; callers must report a failed build."""


class _Cursor:
    def __init__(self, blob: bytes, offset: int, end: int) -> None:
        if not 0 <= offset <= end <= len(blob):
            raise PackError(f"invalid read boundary [{offset}, {end}) for {len(blob)} bytes")
        self.blob = blob
        self.offset = offset
        self.end = end

    def read(self, size: int) -> bytes:
        if size < 0 or size > self.end - self.offset:
            raise PackError(
                f"read of {size} byte(s) at 0x{self.offset:x} runs past the pack boundary "
                f"(0x{self.end:x})"
            )
        chunk = self.blob[self.offset:self.offset + size]
        self.offset += size
        return chunk

    def u32(self) -> int:
        return struct.unpack("<I", self.read(4))[0]

    def u64(self) -> int:
        return struct.unpack("<Q", self.read(8))[0]


@dataclass(frozen=True)
class _Entry:
    path: str
    offset: int
    size: int
    digest: bytes


def _path(raw: bytes, index: int) -> str:
    # Only trailing alignment NULs are legal. Godot would otherwise resolve a
    # different string from the one a Python prefix check is looking at.
    name = raw.rstrip(b"\0")
    if not name or b"\0" in name:
        raise PackError(f"entry {index} has an empty path or an embedded NUL")
    try:
        text = name.decode("utf-8", "strict")
    except UnicodeDecodeError as error:
        raise PackError(f"entry {index} has an invalid UTF-8 path") from error
    parts = text.split("/")
    if (
        "\\" in text or ":" in text
        or any(part in ("", ".", "..") for part in parts)
        or any(ord(char) < 32 or ord(char) == 127 for char in text)
    ):
        raise PackError(f"entry {index} is not a canonical relative resource path: {text!r}")
    return text


def _directory(blob: bytes, start: int, end: int) -> tuple[list[_Entry], int]:
    cursor = _Cursor(blob, start, end)
    count = cursor.u32()
    if count > MAX_FILES:
        raise PackError(f"the directory at 0x{start:x} claims {count} files (limit {MAX_FILES})")
    entries: list[_Entry] = []
    names: set[str] = set()
    for index in range(count):
        length = cursor.u32()
        if not 0 < length <= MAX_PATH_BYTES or length % 4:
            raise PackError(f"entry {index} has an invalid padded path length ({length})")
        path = _path(cursor.read(length), index)
        identity = unicodedata.normalize("NFC", path)
        if identity in names:
            raise PackError(f"entry {index} repeats a resource path: {path!r}")
        names.add(identity)
        offset = cursor.u64()
        size = cursor.u64()
        digest = cursor.read(16)
        flags = cursor.u32()
        if flags:
            raise PackError(
                f"entry {index} ({path!r}) has unsupported file flags 0x{flags:x}; "
                "a complete release must not contain encrypted, removal or delta entries"
            )
        entries.append(_Entry(path, offset, size, digest))
    return entries, cursor.offset


def _check_payloads(
    blob: bytes, entries: list[_Entry], file_base: int, header_end: int,
    directory_start: int, directory_end: int, end: int,
) -> None:
    spans: list[tuple[int, int, str, bytes]] = []
    for entry in entries:
        start = file_base + entry.offset
        if start < header_end or start > end or entry.size > end - start:
            raise PackError(
                f"{entry.path!r}: data range [0x{start:x}, 0x{start + entry.size:x}) "
                f"is outside the payload boundary [0x{header_end:x}, 0x{end:x})"
            )
        stop = start + entry.size
        if entry.size and start < directory_end and stop > directory_start:
            raise PackError(f"{entry.path!r}: data overlaps the pack directory")
        actual = hashlib.md5(memoryview(blob)[start:stop], usedforsecurity=False).digest()
        if actual != entry.digest:
            raise PackError(f"{entry.path!r}: MD5 mismatch; the packed data is damaged or missing")
        if entry.size:
            spans.append((start, stop, entry.path, entry.digest))
    # Exact shared ranges with the same hash are safe (deduplicating packers may
    # use them); a partially overlapping pair is not a complete-file allocation.
    spans.sort()
    previous: tuple[int, int, str, bytes] | None = None
    for span in spans:
        if previous is not None and span[0] < previous[1]:
            if (span[0], span[1], span[3]) != (previous[0], previous[1], previous[3]):
                raise PackError(f"{span[2]!r}: data partially overlaps {previous[2]!r}")
        previous = span


def read_pack(
    blob: bytes, base: int, *, end: int | None = None,
) -> tuple[list[tuple[str, int]], dict]:
    """Read one v2/v3/v4 pack, bounded to [base, end), with verified contents.

    v2's file base is absolute unless PACK_REL_FILEBASE is set; v3/v4's is
    always relative to the magic, even when that flag is absent. The directory
    offset in v3/v4 is relative too. Embedded callers exclude the footer from end.
    """
    limit = len(blob) if end is None else end
    cursor = _Cursor(blob, base, limit)
    if cursor.read(4) != MAGIC:
        raise PackError(f"no 'GDPC' magic at offset {base}")
    version = cursor.u32()
    if version not in SUPPORTED_FORMATS:
        raise PackError(f"unsupported pack format {version}")
    major, minor, patch = cursor.u32(), cursor.u32(), cursor.u32()
    flags = cursor.u32()
    unknown = flags & ~(PACK_DIR_ENCRYPTED | PACK_REL_FILEBASE | PACK_SPARSE_BUNDLE)
    if unknown or flags & (PACK_DIR_ENCRYPTED | PACK_SPARSE_BUNDLE):
        raise PackError(
            f"unsupported pack flags 0x{flags:x}; encrypted or sparse bundles "
            "are not complete, inspectable release packs"
        )
    stored_base = cursor.u64()
    relative = version >= 3 or bool(flags & PACK_REL_FILEBASE)
    file_base = stored_base + (base if relative else 0)
    if version >= 3:
        directory_start = base + cursor.u64()
        cursor.read(RESERVED_WORDS * 4)
    else:
        cursor.read(RESERVED_WORDS * 4)
        directory_start = cursor.offset
    header_end = cursor.offset
    if file_base > limit:
        raise PackError(f"file base 0x{file_base:x} runs past the pack boundary 0x{limit:x}")
    if directory_start < header_end or directory_start > limit - 4:
        raise PackError(f"directory offset 0x{directory_start:x} is outside the pack directory boundary")
    entries, directory_end = _directory(blob, directory_start, limit)
    _check_payloads(blob, entries, file_base, header_end, directory_start, directory_end, limit)
    return [("res://" + entry.path, entry.size) for entry in entries], {
        "version": version,
        "engine": f"{major}.{minor}.{patch}",
        "file_base": stored_base,
        "relative_offsets": relative,
    }


def load_blob(blob: bytes, embedded: bool) -> tuple[list[tuple[str, int]], dict]:
    """Read a standalone PCK, or the footer of our unsigned self-contained export.

    The release presets are unsigned and Godot writes uint64(size), GDPC at EOF.
    Follow that locator once, never search for a nicer-looking header inside file
    data after a refusal. Signed/rewrapped executables need a separate locator;
    accepting arbitrary GDPC byte matches would not verify what Godot opens.
    """
    if not embedded:
        return read_pack(blob, 0)
    if len(blob) < 12 or blob[-4:] != MAGIC:
        raise PackError(
            "no Godot embedded pack footer at end of file; the export may be a bare "
            "template, not embed its pack, or use an unsupported signed/wrapped layout"
        )
    footer = len(blob) - 12
    size = struct.unpack_from("<Q", blob, footer)[0]
    if size == 0 or size > footer:
        raise PackError(f"embedded pack footer declares an invalid size ({size} bytes)")
    return read_pack(blob, footer - size, end=footer)
