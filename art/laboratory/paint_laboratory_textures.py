#!/usr/bin/env python3
"""Paints the laboratory's surface fields, deterministically, and writes their sidecars.

The laboratory keeps its own painted surfaces rather than borrowing the classroom's: the
classroom is warm plaster and ochre wood under a low sun, and this room is cold, chalky and
lit from above. Each field is generated here from a fixed seed so the bytes under
`assets/materials/laboratory/textures/` can be regenerated, reviewed as a diff, and checked
by CI instead of being an opaque binary nobody can reproduce.

    python3 art/laboratory/paint_laboratory_textures.py            # write
    python3 art/laboratory/paint_laboratory_textures.py --check    # verify byte for byte

Design rules behind the four fields:

- **Seamless.** Every field tiles: the lattice fields wrap, the grout grid divides the
  canvas, and the streak columns wrap. The materials sample them world-triplanar, so a
  seam would repeat across every wall in the room.
- **Quiet.** These are large, low-contrast planes; the room's hierarchy comes from object
  colour and the lamps, not from texture drama. Nothing here is dirt, grime or damage:
  the laboratory is a working room that is kept clean, and the uncanny part of the scene
  is the cabling, not the surfaces.
- **Standard library only.** No Pillow, no numpy: the PNG is written here and the fields
  are computed in plain Python, so the bytes do not depend on a numerical library's
  version.

Output:

    assets/materials/laboratory/textures/wall_plaster.png   1024 x 1024  cold chalky plaster
    assets/materials/laboratory/textures/floor_concrete.png 1024 x 1024  sealed concrete floor
    assets/materials/laboratory/textures/tile_glaze.png      512 x  512  glazed wall tile, 4 x 4
    assets/materials/laboratory/textures/bench_top.png       512 x  512  dark resin bench top
    (plus one `.import` sidecar per texture, matching the classroom's lossless setup)
"""

from __future__ import annotations

import argparse
import hashlib
import io
import math
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEXTURE_DIR = os.path.join(ROOT, "assets", "materials", "laboratory", "textures")


# --- PNG ---------------------------------------------------------------------


# --- deterministic fields ----------------------------------------------------


def _hash(x: int, y: int, seed: int) -> float:
    """A stable 0..1 value for a lattice point. Plain integer maths, masked to 32 bits."""
    n = (x * 0x1F1F1F1F + y * 0x8DA6B343 + seed * 0x9E3779B1) & 0xFFFFFFFF
    n ^= n >> 15
    n = (n * 0x2C1B3C6D) & 0xFFFFFFFF
    n ^= n >> 12
    n = (n * 0x297A2D39) & 0xFFFFFFFF
    n ^= n >> 15
    return n / 4294967295.0


def _smooth(t: float) -> float:
    return t * t * (3.0 - 2.0 * t)


def _lattice(width: int, height: int, cells: int, seed: int) -> list[list[float]]:
    """A seamless value-noise field on a `cells` x `cells` wrapping lattice."""
    step = width / cells
    rows: list[list[float]] = []
    for y in range(height):
        gy = y / step
        y0 = int(gy) % cells
        y1 = (y0 + 1) % cells
        fy = _smooth(gy - int(gy))
        top = [_hash(x0, y0, seed) for x0 in range(cells)]
        bottom = [_hash(x0, y1, seed) for x0 in range(cells)]
        top.append(top[0])
        bottom.append(bottom[0])
        row: list[float] = []
        for x in range(width):
            gx = x / step
            x0 = int(gx)
            fx = _smooth(gx - x0)
            a = top[x0] + (top[x0 + 1] - top[x0]) * fx
            b = bottom[x0] + (bottom[x0 + 1] - bottom[x0]) * fx
            row.append(a + (b - a) * fy)
        rows.append(row)
    return rows


def _mix(a: tuple[float, float, float], b: tuple[float, float, float], t: float):
    t = max(0.0, min(1.0, t))
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


## The fields are posterized to this many levels per channel before they are written. It is
## the project's surface language (flat painted planes, not photographic gradients), and it
## is also what keeps a 1024 px field a few hundred kilobytes instead of a megabyte: the
## remaining bands compress, per-pixel grain does not.
QUANTIZE = 18


def _byte(value: float) -> int:
    stepped = round(max(0.0, min(1.0, value)) * QUANTIZE) / QUANTIZE
    return max(0, min(255, int(stepped * 255.0 + 0.5)))


# --- the four fields ---------------------------------------------------------


def wall_plaster(size: int = 1024) -> list[bytes]:
    """Cold chalky plaster: broad planes, faint vertical trowel streaks, no stains."""
    dark = (0.712, 0.718, 0.724)
    light = (0.792, 0.796, 0.802)
    # A 4-cell lattice put half-metre clouds on every wall: at triplanar scale that is the one
    # pattern the eye finds first, and plaster does not have it. The field is finer now, and
    # quieter, so what reads is the trowel streak rather than the noise behind it.
    broad = _lattice(size, size, 16, seed=7)
    # One streak field per column, wrapping, so the trowel marks run up the wall as a
    # painter would leave them and never seam where the texture repeats.
    columns = []
    for x in range(size):
        column_seed = _hash(x, 0, 11)
        # The trowel leaves a light catch, not a stain: the streaks are faint and, on
        # average, one step brighter than the plane they cross.
        columns.append(0.004 + (column_seed - 0.5) * 0.016)
    rows: list[bytes] = []
    for y in range(size):
        broad_row = broad[y]
        # A slow vertical drift keeps the streak length finite without a visible band.
        drift = 0.006 * math.sin(2.0 * math.pi * (y / size) * 3.0)
        out = bytearray()
        for x in range(size):
            # What is left of the field: a quiet unevenness under the streaks. At the scale the
            # walls are seen at, anything stronger than this reads as a stain on the plaster.
            value = 0.5 + 0.16 * (broad_row[x] - 0.5) + columns[x] * 0.6 + drift
            colour = _mix(dark, light, value)
            out += bytes((_byte(colour[0]), _byte(colour[1]), _byte(colour[2])))
        rows.append(bytes(out))
    return rows


def floor_concrete(size: int = 1024) -> list[bytes]:
    """Sealed concrete: cool, fine-grained, one colour with a slow mottle."""
    dark = (0.478, 0.494, 0.510)
    light = (0.590, 0.604, 0.616)
    coarse = _lattice(size, size, 4, seed=23)
    fine = _lattice(size, size, 48, seed=29)
    rows: list[bytes] = []
    for y in range(size):
        coarse_row = coarse[y]
        fine_row = fine[y]
        out = bytearray()
        for x in range(size):
            grit = _hash(x, y, 41)
            # A sealed floor is a calm field: the broad mottle carries it, and the fine
            # grain is only enough to stop the plane looking like flat paint.
            value = (
                0.42
                + 0.32 * coarse_row[x]
                + 0.09 * fine_row[x]
                + 0.02 * grit
            )
            colour = _mix(dark, light, value)
            out += bytes((_byte(colour[0]), _byte(colour[1]), _byte(colour[2])))
        rows.append(bytes(out))
    return rows


def tile_glaze(size: int = 512, tiles: int = 4) -> list[bytes]:
    """Glazed wall tile: four by four, soft grout, a slight sheen at each tile's top edge."""
    glaze = (0.792, 0.812, 0.800)
    shade = (0.734, 0.756, 0.748)
    grout = (0.596, 0.612, 0.604)
    cell = size // tiles
    grout_width = max(2, size // 128)
    rows: list[bytes] = []
    for y in range(size):
        ty = y % cell
        out = bytearray()
        for x in range(size):
            tx = x % cell
            in_grout = tx < grout_width or ty < grout_width
            if in_grout:
                colour = grout
            else:
                # Top of each tile catches the tube light; the bottom sits a little darker.
                bevel = 1.0 - min(1.0, (ty - grout_width) / max(1.0, cell * 0.35))
                colour = _mix(shade, glaze, 0.35 + 0.65 * bevel)
            out += bytes((_byte(colour[0]), _byte(colour[1]), _byte(colour[2])))
        rows.append(bytes(out))
    return rows


def bench_top(size: int = 512) -> list[bytes]:
    """Dark phenolic resin: near-black, even, with the palest mineral speckle in it."""
    base = (0.208, 0.235, 0.243)
    speck = (0.352, 0.382, 0.386)
    coarse = _lattice(size, size, 2, seed=53)
    rows: list[bytes] = []
    for y in range(size):
        coarse_row = coarse[y]
        out = bytearray()
        for x in range(size):
            value = 0.15 + 0.5 * coarse_row[x]
            colour = _mix(base, (0.250, 0.278, 0.284), value)
            grit = _hash(x, y, 59)
            if grit > 0.988:
                colour = _mix(colour, speck, (grit - 0.988) / 0.012 * 0.8)
            out += bytes((_byte(colour[0]), _byte(colour[1]), _byte(colour[2])))
        rows.append(bytes(out))
    return rows


FIELDS = {
    "wall_plaster": (1024, wall_plaster),
    "floor_concrete": (1024, floor_concrete),
    "tile_glaze": (512, tile_glaze),
    "bench_top": (512, bench_top),
}


# --- import sidecars ---------------------------------------------------------


def uid_for(res_path: str) -> str:
    """A stable `uid://` in Godot 4.7.2's 34-character alphabet (no z/9)."""
    value = int.from_bytes(hashlib.sha256(res_path.encode()).digest()[:8], "little") & ((1 << 63) - 1)
    alphabet = "abcdefghijklmnopqrstuvwxy012345678"
    text = ""
    while True:
        text = alphabet[value % len(alphabet)] + text
        value //= len(alphabet)
        if value == 0:
            break
    return "uid://" + text


def import_sidecar(res_path: str) -> str:
    digest = hashlib.md5(res_path.encode()).hexdigest()
    name = res_path.rsplit("/", 1)[-1]
    dest = f"res://.godot/imported/{name}-{digest}.ctex"
    # Lossless with mipmaps and the 3D-usage detector switched off, exactly like the
    # classroom's fields: a detector hit would re-import as VRAM-compressed and rewrite this
    # sidecar on the first editor run, which is the churn checked sidecars exist to stop.
    return f"""[remap]

importer="texture"
type="CompressedTexture2D"
uid="{uid_for(res_path)}"
path="{dest}"
metadata={{
"vram_texture": false
}}

[deps]

source_file="{res_path}"
dest_files=["{dest}"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Paint the laboratory's surface fields.")
    parser.add_argument(
        "--check",
        action="store_true",
        help="compare the generated bytes with the files on disk instead of writing them",
    )
    args = parser.parse_args()

    written: list[str] = []
    stale: list[str] = []
    for name, (size, painter) in FIELDS.items():
        png_path = os.path.join(TEXTURE_DIR, name + ".png")
        res_path = "res://assets/materials/laboratory/textures/" + name + ".png"
        sidecar_path = png_path + ".import"
        # The painter is the only source of these bytes; generating into memory first keeps
        # `--check` honest even when the file on disk was edited by hand.
        payload = _png_bytes(size, size, painter(size))
        if args.check:
            current = b""
            if os.path.exists(png_path):
                with open(png_path, "rb") as handle:
                    current = handle.read()
            if current != payload:
                stale.append(png_path)
            sidecar = import_sidecar(res_path)
            disk = ""
            if os.path.exists(sidecar_path):
                with open(sidecar_path, "r", encoding="utf-8") as handle:
                    disk = handle.read()
            if disk != sidecar:
                stale.append(sidecar_path)
        else:
            os.makedirs(TEXTURE_DIR, exist_ok=True)
            with open(png_path, "wb") as handle:
                handle.write(payload)
            with open(sidecar_path, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(import_sidecar(res_path))
            written.append(os.path.relpath(png_path, ROOT))
        print("%s: %d x %d, %d bytes" % (os.path.relpath(png_path, ROOT), size, size, len(payload)))

    if args.check:
        if stale:
            for path in stale:
                print("STALE: %s" % os.path.relpath(path, ROOT), file=sys.stderr)
            return 1
        print("laboratory textures match the painter")
        return 0
    print("wrote %d files" % len(written))
    return 0


def _png_bytes(width: int, height: int, rows: list[bytes]) -> bytes:
    """The PNG bytes for one field: one filter-0 scanline per row, deflated."""
    buffer = io.BytesIO()

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    raw = b"".join(b"\x00" + row for row in rows)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    buffer.write(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    return buffer.getvalue()


if __name__ == "__main__":
    sys.exit(main())
