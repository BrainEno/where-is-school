#!/usr/bin/env python3
"""Prepare the 01 wall's paint from the owner's original photograph (not in Git).

Requires Pillow, numpy and scipy. Run from any directory:
    python3 art/teaching_block/graffiti/prepare_wall_graffiti.py IMG_1689.jpeg

Only the transparent paint and its Godot outline mesh go into the game. The mesh
is cut from the paint's coverage so the normal depth-tested interaction outline
traces the drawing rather than the edge of an invisible rectangular card.
"""
from __future__ import annotations

import argparse
import base64
from pathlib import Path
import struct

import numpy as np
from PIL import Image, ImageOps
from scipy import ndimage as nd

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "assets/materials/corridor/graffiti"
INK = (36, 42, 57)
HEIGHT_M = 1.50
TILE_PX = 8


def extract_paint(source: Path) -> Image.Image:
    with Image.open(source) as photo:
        grey = ImageOps.exif_transpose(photo).convert("L")
    # Drop the photograph's paper edge, not the marks at the page margins.
    grey = grey.crop((16, 7, grey.width - 12, grey.height - 6))
    grey = grey.resize((856, 992), Image.Resampling.LANCZOS)
    value = np.asarray(grey, dtype=np.float32) / 255
    paper = nd.gaussian_filter(nd.maximum_filter(value, size=33), 8)
    contrast = 1 - value / np.maximum(paper, .05)
    stroke = np.clip((contrast - .20) / .37, 0, 1)
    labels, _ = nd.label(stroke > .18, structure=np.ones((3, 3)))
    stroke[(labels == 0) | (np.bincount(labels.ravel())[labels] < 9)] = 0
    stroke = np.pad(stroke, 20)

    # Widen the hand-drawn line a little, then break up the mist around its edge.
    distance = nd.distance_transform_edt(stroke < .33)
    grain = np.random.default_rng(1689).random(stroke.shape, dtype=np.float32)
    cloud = nd.gaussian_filter(grain, 1.15)
    core = nd.gaussian_filter(nd.maximum_filter(stroke, size=5), .95)
    mist = np.exp(-.5 * (distance / 3.6) ** 2)
    mist[distance > 10] = 0
    mist *= .10 + .20 * (grain > .78) + .11 * (cloud > .56)
    tooth = .85 + .13 * grain - .18 * (cloud <= .38)
    alpha = 1 - (1 - .98 * core * tooth) * (1 - mist)

    # A mark that ran off the photograph fades out, rather than ending on a paper edge.
    x, y = np.arange(grey.width), np.arange(grey.height)
    edge = np.minimum.outer(np.minimum(y, y[::-1]), np.minimum(x, x[::-1]))
    alpha *= np.pad(np.minimum(1.0, (edge + 6) / 17), 20, mode="edge")
    alpha[alpha < .024] = 0
    paint = Image.new("RGBA", (alpha.shape[1], alpha.shape[0]), INK)
    paint.putalpha(Image.fromarray((np.rint(alpha * 63) * 4).astype(np.uint8)))
    return paint


def coverage_rects(alpha: np.ndarray) -> list[tuple[int, int, int, int]]:
    """Coalesce occupied tiles into rectangles; holes stay holes, even in the outline."""
    h, w = alpha.shape
    tile = TILE_PX
    covered = alpha.reshape(h // tile, tile, w // tile, tile).any(axis=(1, 3))
    active: dict[tuple[int, int], int] = {}
    rects = []
    for y, row in enumerate(covered):
        edges = np.flatnonzero(np.diff(np.r_[False, row, False])).tolist()
        spans = list(zip(edges[::2], edges[1::2]))
        rects.extend((x0, start, x1, y) for (x0, x1), start in active.items()
                     if (x0, x1) not in spans)
        active = {span: active.get(span, y) for span in spans}
    rects.extend((x0, start, x1, len(covered)) for (x0, x1), start in active.items())
    return rects


def packed(data: bytes) -> str:
    return f'PackedByteArray("{base64.b64encode(data).decode(encoding="ascii")}")'


def ink_mesh(alpha: np.ndarray) -> str:
    """Single +Z facing Godot ArrayMesh v2 surface with float32 position and UV streams."""
    h, w = alpha.shape
    width = HEIGHT_M * w / h
    points: dict[tuple[int, int], int] = {}
    indices = []
    for x0, y0, x1, y1 in coverage_rects(alpha):
        a, b, c, d = (points.setdefault(p, len(points)) for p in
                      ((x0, y0), (x1, y0), (x1, y1), (x0, y1)))
        # Clockwise as seen from outside (+Z).
        indices.extend((a, b, c, a, c, d))
    if not 3 <= len(points) < 65536:
        raise ValueError("Expected a nonempty paint mask fitting 16-bit indices")
    uv = [(x * TILE_PX / w, y * TILE_PX / h) for x, y in points]
    xy = [((u - .5) * width, (.5 - v) * HEIGHT_M) for u, v in uv]
    xs, ys = zip(*xy)
    aabb = (min(xs), min(ys), 0, max(xs) - min(xs), max(ys) - min(ys), 0)
    positions = b"".join(struct.pack("<fff", x, y, 0) for x, y in xy)
    # Octahedrally encoded +Z normal and +X tangent, with -Y as the UV bitangent.
    normals = struct.pack("<HHHH", 32767, 32767, 65535, 16383) * len(points)
    attributes = b"".join(struct.pack("<ff", u, v) for u, v in uv)
    fmt = (1 << 35) | (1 << 12) | 16 | 4 | 2 | 1  # v2, index, UV, tangent, normal, vertex
    return (
        '[gd_resource type="ArrayMesh" format=3]\n\n[resource]\n_surfaces = [{\n'
        f'"aabb": AABB({", ".join(f"{v:.6f}" for v in aabb)}),\n'
        f'"attribute_data": {packed(attributes)},\n'
        f'"format": {fmt},\n'
        f'"index_count": {len(indices)},\n'
        f'"index_data": {packed(struct.pack(f"<{len(indices)}H", *indices))},\n'
        f'"primitive": 3,\n"vertex_count": {len(points)},\n'
        f'"vertex_data": {packed(positions + normals)}\n'
        '}]\n'
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="the owner's unmodified photograph")
    parser.add_argument("--output", type=Path, default=OUT)
    args = parser.parse_args()
    paint = extract_paint(args.source)
    mesh = ink_mesh(np.asarray(paint.getchannel("A")))
    args.output.mkdir(parents=True, exist_ok=True)
    paint.save(args.output / "wall_graffiti.png", optimize=True)
    (args.output / "wall_graffiti_ink.tres").write_text(mesh, encoding="utf-8")


if __name__ == "__main__":
    main()
