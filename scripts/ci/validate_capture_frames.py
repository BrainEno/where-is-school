#!/usr/bin/env python3
"""Fail closed on missing, truncated, corrupt or wrong-sized capture frames.

Uses only the Python standard library. Godot's PNGs are non-interlaced. Checking
chunk CRCs and the complete decompressed scanlines avoids accepting a nonempty
partial file as evidence; it does not claim to judge the content of an image.
"""
from pathlib import Path
import struct
import sys
import zlib

SIGNATURE = b"\x89PNG\r\n\x1a\n"


def validate(path: Path):
    data = path.read_bytes()
    if not data.startswith(SIGNATURE):
        raise ValueError("not a PNG")
    position = len(SIGNATURE)
    image_data = bytearray()
    dimensions = None
    ended = False
    while position < len(data):
        if position + 12 > len(data):
            raise ValueError("truncated PNG chunk")
        length = struct.unpack_from(">I", data, position)[0]
        kind = data[position + 4:position + 8]
        end = position + 12 + length
        if end > len(data):
            raise ValueError("truncated PNG chunk payload")
        payload = data[position + 8:position + 8 + length]
        crc = struct.unpack_from(">I", data, position + 8 + length)[0]
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != crc:
            raise ValueError("PNG chunk CRC mismatch")
        if kind == b"IHDR":
            if dimensions is not None or length != 13 or position != len(SIGNATURE):
                raise ValueError("invalid IHDR")
            dimensions = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            if dimensions is None:
                raise ValueError("PNG data before IHDR")
            image_data.extend(payload)
        elif kind == b"IEND":
            ended = True
            if length != 0 or end != len(data):
                raise ValueError("invalid PNG end")
            break
        position = end
    if not ended or dimensions is None or not image_data:
        raise ValueError("missing PNG data or end")
    width, height, bit_depth, color_type, compression, filtering, interlace = dimensions
    if (width, height) != (1600, 900):
        raise ValueError(f"unexpected size {width}x{height}, expected 1600x900")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color_type)
    valid_depths = {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8),
                    4: (8, 16), 6: (8, 16)}
    if channels is None or bit_depth not in valid_depths[color_type] or compression or filtering or interlace:
        raise ValueError("unsupported PNG layout")
    row_bytes = (width * channels * bit_depth + 7) // 8
    expected = (row_bytes + 1) * height
    decoder = zlib.decompressobj()
    decoded = decoder.decompress(bytes(image_data), expected + 1)
    if len(decoded) != expected or not decoder.eof or decoder.unused_data:
        raise ValueError("incomplete PNG scanlines")
    if any(decoded[row * (row_bytes + 1)] > 4 for row in range(height)):
        raise ValueError("invalid PNG scanline filter")


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: validate_capture_frames.py DIR FRAME [FRAME ...]")
    root = Path(sys.argv[1])
    errors = []
    for name in sys.argv[2:]:
        path = root / f"{name}.png"
        try:
            validate(path)
            print(f"OK {path.name}")
        except (OSError, ValueError, zlib.error, struct.error) as exc:
            errors.append(f"{path.name}: {exc}")
    for error in errors:
        print(f"INVALID {error}", file=sys.stderr)
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
