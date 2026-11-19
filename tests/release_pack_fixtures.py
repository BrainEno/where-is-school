"""Small complete PCK fixtures, independent of the production byte reader.

These are synthetic files with real payloads/hashes, never playable exports.
The v2 directory precedes data; v3/v4 place it after data, as the official
Godot 4.7.2 writer does. Tests can mutate individual fields without omitting
the very bytes the integrity check is supposed to prove exist.
"""

from __future__ import annotations

import hashlib
import struct
from collections.abc import Sequence


def pack_files(
    files: Sequence[tuple[str | bytes, bytes]], version: int = 4,
    *, flags: int = 2, embedded_base: int = 0,
) -> bytes:
    names = [name.encode("utf-8") if isinstance(name, str) else name for name, _ in files]
    names = [name + bytes((-len(name)) % 4) for name in names]
    directory_size = 4 + sum(4 + len(name) + 8 + 8 + 16 + 4 for name in names)
    header_size = 104 if version >= 3 else 96
    prefix_size = header_size if version >= 3 else header_size + directory_size
    file_base = prefix_size + (-prefix_size) % 32
    data = bytearray()
    rows = bytearray(struct.pack("<I", len(files)))
    for name, (_source, payload) in zip(names, files):
        rows.extend(struct.pack("<I", len(name)))
        rows.extend(name)
        rows.extend(struct.pack("<QQ", len(data), len(payload)))
        rows.extend(hashlib.md5(payload, usedforsecurity=False).digest())
        rows.extend(struct.pack("<I", 0))
        data.extend(payload)
        data.extend(bytes((-len(data)) % 32))
    relative = version >= 3 or bool(flags & 2)
    stored_base = file_base + (0 if relative else embedded_base)
    header = b"GDPC" + struct.pack("<IIIIIQ", version, 4, 7, 2, flags, stored_base)
    if version >= 3:
        header += struct.pack("<Q", file_base + len(data))
    header += bytes(64)
    if version >= 3:
        return header + bytes(file_base - header_size) + data + rows
    return header + rows + bytes(file_base - prefix_size) + data


def embed(pack: bytes, prefix: bytes = b"\x7fELF" + bytes(60)) -> bytes:
    # The unsigned exporter locates the pack with uint64(size), GDPC at EOF.
    # Padding belongs to the pack's bounded region, not to the footer.
    padding = bytes((-(len(pack) + 12)) % 8)
    return prefix + pack + padding + struct.pack("<Q", len(pack) + len(padding)) + b"GDPC"


def fields(blob: bytes, index: int = 0) -> dict[str, int]:
    """Locations of a directory row's fields, for one-field-at-a-time corruption."""
    version = struct.unpack_from("<I", blob, 4)[0]
    directory = struct.unpack_from("<Q", blob, 32)[0] if version >= 3 else 96
    cursor = directory + 4
    for _ in range(index):
        length = struct.unpack_from("<I", blob, cursor)[0]
        cursor += 4 + length + 36
    length = struct.unpack_from("<I", blob, cursor)[0]
    row = cursor + 4 + length
    return {
        "directory": directory,
        "length": cursor,
        "name": cursor + 4,
        "offset": row,
        "size": row + 8,
        "digest": row + 16,
        "flags": row + 32,
    }
