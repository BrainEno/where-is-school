#!/usr/bin/env python3
"""Draw the project's application icon, deterministically, from a table of shapes.

The build needs an icon it can point a Windows export preset at, and this repository does
not keep binary sources it cannot rebuild: the same rule that makes
`tools/build_sample_models.py` write the sample meshes and `tools/subset_font.py` write the
font subset applies here. So the icon is **generated**, from this file, and the generated
files are committed so the engine can import them:

    assets/icon/icon.svg             the vector source, the same shapes as SVG
    assets/icon/app_icon.ico         what the Windows preset points at: 16-256 px entries
    assets/icon/app_icon_256.png     what the Linux package ships and the launcher names
    assets/icon/app_icon_512.png     the large copy for documentation and store pages

The drawing is original and project-owned (see `docs/ASSET_PROVENANCE.md`): a slate doorway
with light showing through the gap, in the classroom palette from
`assets/materials/classroom/`. There is no third-party icon, no font glyph and no traced
image anywhere in it — the shapes below are four rounded boxes and two rectangles.

Why a script instead of a designer's .ico: an `.ico` cannot be reviewed in a diff. A 40-line
shape table can be, and `--check` proves the committed pixels still match it.

Usage:

    python3 tools/build_app_icon.py            # rewrite assets/icon/ from the table
    python3 tools/build_app_icon.py --check    # fail if a committed file has drifted

`--check` compares *decoded pixels*, not compressed bytes: a different zlib build may
compress the same image to different bytes, and failing on that would teach everyone to
ignore the check. What it does compare exactly is every pixel of every size, and the SVG
text, both of which are pure functions of the table below.

It needs no engine, no network and no image library.
"""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = ROOT / "assets" / "icon"

# The sizes Windows asks for, in the order Godot's own icon writer emits them
# (`platform/windows/export/export_plugin.cpp`, `_process_icon`). 256 is stored as a zero
# width/height byte in the ICO directory, which is the format's way of saying "256".
SIZES = (16, 32, 48, 64, 128, 256)

# Vertical sub-samples per pixel. The horizontal coverage is computed exactly (a pixel's
# overlap with the shape's span on that row), so this is only about the curved edges;
# small sizes get more of them because that is where an edge is a whole pixel.
SAMPLES_SMALL = 4
SAMPLES_LARGE = 2
SMALL_SIZE = 128

# Palette anchors, taken from `assets/materials/classroom/` so the icon belongs to the same
# room as the rest of the art: board slate, plaster ivory, mustard light, honey wood.
SLATE = (0.125, 0.212, 0.180, 1.0)
IVORY = (0.886, 0.847, 0.745, 1.0)
LIGHT = (0.984, 0.965, 0.902, 1.0)
HONEY = (0.690, 0.502, 0.275, 1.0)


def _rgba(color: tuple[float, float, float, float]) -> tuple[int, int, int, int]:
    return tuple(max(0, min(255, round(component * 255))) for component in color[:3]) + (
        max(0, min(255, round(color[3] * 255))),
    )


# Every shape answers `span(y)`: the horizontal interval it covers on that row, or None.
# Keeping shapes as spans rather than as per-pixel tests is what makes a 512 px render take
# a second instead of a minute in plain Python.
def _rect(x: float, y: float, w: float, h: float):
    def span(py: float):
        return (x, x + w) if y <= py <= y + h else None

    return span


def _rounded_rect(x: float, y: float, w: float, h: float, radius: float):
    def span(py: float):
        if not (y <= py <= y + h):
            return None
        if y + radius <= py <= y + h - radius:
            return (x, x + w)
        # Inside a corner band: the row is inset by the circle's chord.
        centre = y + radius if py < y + radius else y + h - radius
        offset = abs(py - centre)
        if offset > radius:
            return None
        chord = (radius * radius - offset * offset) ** 0.5
        return (x + radius - chord, x + w - radius + chord)

    return span


def _arch(x: float, y: float, w: float, h: float):
    """A doorway: a rectangle with a semicircular top."""
    radius = w / 2.0
    centre_y = y + radius
    centre_x = x + radius

    def span(py: float):
        if not (y <= py <= y + h):
            return None
        if py >= centre_y:
            return (x, x + w)
        offset = centre_y - py
        if offset > radius:
            return None
        half = (radius * radius - offset * offset) ** 0.5
        return (centre_x - half, centre_x + half)

    return span


# The drawing, back to front. Each layer is (span function, colour). Every coordinate is a
# fraction of the icon's width, so one table renders every size.
def layers() -> list[tuple]:
    return [
        # The slate plate, inset so the icon has a little air at small sizes.
        (_rounded_rect(0.03, 0.03, 0.94, 0.94, 0.20), SLATE),
        # The doorway.
        (_arch(0.32, 0.30, 0.36, 0.50), IVORY),
        # The gap: light through the door, wide enough to survive a 16 px render
        # (0.09 x 16 = 1.4 px) and bright enough to read against the ivory leaf.
        (_rect(0.455, 0.34, 0.09, 0.46), LIGHT),
        # The threshold.
        (_rect(0.24, 0.80, 0.52, 0.06), HONEY),
    ]


def render(size: int) -> bytes:
    """RGBA bytes for one square image, composited back to front with exact x coverage."""
    strides = SAMPLES_SMALL if size <= SMALL_SIZE else SAMPLES_LARGE
    red = [0.0] * (size * size)
    green = [0.0] * (size * size)
    blue = [0.0] * (size * size)
    alpha = [0.0] * (size * size)

    for span, colour in layers():
        for row in range(size):
            base = row * size
            for sub in range(strides):
                py = (row + (sub + 0.5) / strides) / size
                interval = span(py)
                if interval is None:
                    continue
                start = max(0.0, interval[0] * size)
                end = min(float(size), interval[1] * size)
                if end <= start:
                    continue
                first = int(start)
                last = int(end)
                for column in range(first, last + (0 if end == last else 1)):
                    covered = min(end, column + 1) - max(start, column)
                    if covered <= 0.0:
                        continue
                    coverage = covered / strides
                    index = base + column
                    remaining = 1.0 - coverage
                    red[index] = red[index] * remaining + colour[0] * coverage
                    green[index] = green[index] * remaining + colour[1] * coverage
                    blue[index] = blue[index] * remaining + colour[2] * coverage
                    alpha[index] = alpha[index] * remaining + colour[3] * coverage

    pixels = bytearray()
    for index in range(size * size):
        if alpha[index] <= 0.0:
            pixels += b"\x00\x00\x00\x00"
            continue
        pixels += bytes(
            (
                min(255, round(red[index] / alpha[index] * 255)),
                min(255, round(green[index] / alpha[index] * 255)),
                min(255, round(blue[index] / alpha[index] * 255)),
                min(255, round(alpha[index] * 255)),
            )
        )
    return bytes(pixels)


def _chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def write_png(rgba: bytes, size: int) -> bytes:
    """A PNG with filter 0 scanlines, compressed at level 9 (small, still deterministic)."""
    stride = size * 4
    raw = b"".join(b"\x00" + rgba[row * stride : (row + 1) * stride] for row in range(size))
    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", header)
        + _chunk(b"IDAT", zlib.compress(raw, 9))
        + _chunk(b"IEND", b"")
    )


def read_png_pixels(blob: bytes) -> tuple[int, bytes]:
    """Decode the PNGs this file writes (8-bit RGBA, filter 0) back to pixels."""
    if not blob.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("not a PNG")
    offset = 8
    width = height = 0
    data = b""
    while offset < len(blob):
        (length,) = struct.unpack_from(">I", blob, offset)
        kind = blob[offset + 4 : offset + 8]
        payload = blob[offset + 8 : offset + 8 + length]
        offset += 12 + length
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", payload)
            if (depth, colour, interlace) != (8, 6, 0):
                raise ValueError("expected an 8-bit RGBA, non-interlaced PNG")
        elif kind == b"IDAT":
            data += payload
        elif kind == b"IEND":
            break
    raw = zlib.decompress(data)
    stride = width * 4
    pixels = bytearray()
    for row in range(height):
        line = raw[row * (stride + 1) : (row + 1) * (stride + 1)]
        if line[0] != 0:
            raise ValueError("expected filter 0 on every scanline, saw %d" % line[0])
        pixels += line[1:]
    return width, bytes(pixels)


def write_ico(images: dict[int, bytes]) -> bytes:
    """An ICO whose entries hold PNG data, the format Godot and Windows both accept."""
    entries = []
    offset = 6 + 16 * len(images)
    for size in sorted(images):
        png = images[size]
        entries.append(
            struct.pack(
                "<BBBBHHII",
                size if size < 256 else 0,
                size if size < 256 else 0,
                0,  # palette colours: none
                0,  # reserved
                1,  # colour planes
                32,  # bits per pixel
                len(png),
                offset,
            )
        )
        offset += len(png)
    header = struct.pack("<HHH", 0, 1, len(images))
    return header + b"".join(entries) + b"".join(images[size] for size in sorted(images))


def read_ico_entries(blob: bytes) -> dict[int, bytes]:
    """Split an ICO back into `{size: png bytes}`."""
    reserved, kind, count = struct.unpack_from("<HHH", blob, 0)
    if (reserved, kind) != (0, 1):
        raise ValueError("not an icon file (reserved=%d type=%d)" % (reserved, kind))
    entries = {}
    for index in range(count):
        width, _height, _colours, _reserved, _planes, _bpp, length, offset = struct.unpack_from(
            "<BBBBHHII", blob, 6 + 16 * index
        )
        entries[width or 256] = blob[offset : offset + length]
    return entries


def _svg() -> str:
    """The same shape table as SVG, for whoever edits the mark next."""
    def colour(value) -> str:
        return "#%02X%02X%02X" % _rgba(value)[:3]

    radius = 0.20 * 100
    doorway_radius = 0.18 * 100
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!-- Generated by tools/build_app_icon.py from its shape table. Edit the table, not this
     file: `python3 tools/build_app_icon.py --check` fails when the two disagree. -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="512" height="512">
  <title>where-is-school</title>
  <desc>A slate doorway with light showing through the gap.</desc>
  <rect x="3" y="3" width="94" height="94" rx="{radius:g}" ry="{radius:g}" fill="{colour(SLATE)}"/>
  <path d="M32 80 V48 A{doorway_radius:g} {doorway_radius:g} 0 0 1 68 48 V80 Z" fill="{colour(IVORY)}"/>
  <rect x="44" y="24" width="12" height="56" fill="{colour(LIGHT)}"/>
  <rect x="26" y="80" width="48" height="6" fill="{colour(HONEY)}"/>
</svg>
"""


def build() -> dict[str, bytes]:
    """Every file this tool owns, by name."""
    images = {size: write_png(render(size), size) for size in SIZES + (512,)}
    return {
        "icon.svg": _svg().encode("utf-8"),
        "app_icon.ico": write_ico({size: images[size] for size in SIZES}),
        "app_icon_256.png": images[256],
        "app_icon_512.png": images[512],
    }


def check() -> int:
    """Compare committed files with a fresh render, pixel by pixel."""
    problems: list[str] = []
    fresh = build()

    for name, expected in fresh.items():
        path = OUT / name
        if not path.is_file():
            problems.append("%s is missing" % path.relative_to(ROOT))
            continue
        committed = path.read_bytes()
        if name.endswith(".svg"):
            if committed != expected:
                problems.append(
                    "%s differs from the shape table; re-run tools/build_app_icon.py"
                    % path.relative_to(ROOT)
                )
            continue
        sizes = SIZES if name.endswith(".ico") else (int(name.split("_")[-1].split(".")[0]),)
        try:
            if name.endswith(".ico"):
                have = {size: read_png_pixels(blob) for size, blob in read_ico_entries(committed).items()}
                want = {size: read_png_pixels(blob) for size, blob in read_ico_entries(expected).items()}
            else:
                have = {sizes[0]: read_png_pixels(committed)}
                want = {sizes[0]: read_png_pixels(expected)}
        except ValueError as error:
            problems.append("%s cannot be read back: %s" % (path.relative_to(ROOT), error))
            continue
        if sorted(have) != sorted(want):
            problems.append(
                "%s carries sizes %s, the table renders %s"
                % (path.relative_to(ROOT), sorted(have), sorted(want))
            )
            continue
        for size in sorted(want):
            if have[size] != want[size]:
                problems.append(
                    "%s: the %d px image is not what the shape table draws"
                    % (path.relative_to(ROOT), size)
                )

    if problems:
        for problem in problems:
            print("APP_ICON_PROBLEM: " + problem)
        return 1
    print(
        "APP_ICON_OK: %d file(s) match the shape table (%s px, svg)."
        % (len(fresh), "/".join(str(size) for size in SIZES))
    )
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="fail if a committed icon file has drifted from the table")
    options = parser.parse_args(argv)

    if options.check:
        return check()

    OUT.mkdir(parents=True, exist_ok=True)
    for name, payload in build().items():
        path = OUT / name
        path.write_bytes(payload)
        print("wrote %s (%d bytes)" % (path.relative_to(ROOT), len(payload)))
    print("Commit the result: the export presets point at these files.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
