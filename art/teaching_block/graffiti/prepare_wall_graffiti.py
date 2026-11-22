#!/usr/bin/env python3
"""Prepare the 01 wall's paint from the owner's original photograph (not in Git).

Requires Pillow, numpy and scipy. Run from any directory:
    python3 art/teaching_block/graffiti/prepare_wall_graffiti.py IMG_1689.jpeg

Write the transparent pigment, its depth-tested contour mesh, and the albedo and
normal maps of the rose plaster beneath it. The source photograph stays private.
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
TILE_PX = 3
PLASTER_PX = 512  # Internal field: shared with the paint's sampled pores.
PLASTER_OUTPUT_PX = 256
NORMAL_OUTPUT_PX = 128
PAINT_OUTPUT_SIZE = (336, 387)
PLASTER_REPEAT_M = 2.0  # Reciprocal of rose_plaster.tres's local triplanar scale.
ROSE = (185, 116, 108)  # The 01 entrance's municipal_rose, before its outdoor lighting.


def plaster_finish() -> tuple[Image.Image, Image.Image, np.ndarray]:
    """Make a seamless trowelled coat, normal map and pore field from the same height."""
    rng = np.random.default_rng(4101)
    shape = (PLASTER_PX, PLASTER_PX)

    def field(sigma: float | tuple[float, float]) -> np.ndarray:
        smooth = nd.gaussian_filter(rng.standard_normal(shape, dtype=np.float32), sigma, mode="wrap")
        return np.clip(smooth / smooth.std(), -2.8, 2.8)

    # The broad unevenness is from a trowel, not a dirt wash. Small clustered
    # pits and grains carry most of the texture up close, then mip away at a distance.
    trowel = field((14.0, 26.0))
    aggregate = field((2.6, 4.5))
    grit = field(.85)
    pitting = nd.gaussian_filter((rng.random(shape) < .072).astype(np.float32), .9, mode="wrap")
    pores = np.clip((pitting - .036) / .235, 0, 1)
    height = .12 * trowel + .28 * aggregate + .20 * grit - .65 * pores
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * .5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * .5
    normal = np.stack((-2.1 * dx, 2.1 * dy, np.ones_like(height)), axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    relief = Image.fromarray(np.rint((normal * .5 + .5) * 255).astype(np.uint8))
    value = 3.2 * trowel + 4.3 * aggregate + 3.9 * grit - 15.0 * pores
    # A little warm and cool variation in the same rose palette, not multicolour noise.
    colour = np.asarray(ROSE, dtype=np.float32) + value[..., None]
    colour += aggregate[..., None] * np.array((.8, -.2, -.6), dtype=np.float32)
    albedo = Image.fromarray(np.clip(np.rint(colour), 0, 255).astype(np.uint8))
    return albedo, relief, pores


def pigment_pores(pores: np.ndarray, shape: tuple[int, int]) -> np.ndarray:
    # Paint and Plaster share an XY centre. On the exterior (+Z) the material
    # projects (x, -y) in mesh-local metres, with wrapping and linear filtering.
    h, w = shape
    step = HEIGHT_M / h * PLASTER_PX / PLASTER_REPEAT_M
    x = (np.arange(w) + .5 - w * .5) * step - .5
    y = (np.arange(h) + .5 - h * .5) * step - .5
    return nd.map_coordinates(pores, np.broadcast_arrays(y[:, None], x[None, :]),
                              order=1, mode="grid-wrap", prefilter=False)


def extract_paint(source: Path, pores: np.ndarray) -> Image.Image:
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

    # A rounded spray footprint adds weight without squaring off the drawn corners.
    yy, xx = np.ogrid[-4:5, -4:5]
    core = nd.gaussian_filter(nd.maximum_filter(stroke, footprint=xx * xx + yy * yy <= 17), 1.05)
    distance = nd.distance_transform_edt(core < .28)
    grain = np.random.default_rng(1689).random(stroke.shape, dtype=np.float32)
    cloud = nd.gaussian_filter(grain, 5.0)
    wisps = np.clip((cloud - .5) / cloud.std(), -2.5, 2.5)

    # Soft overlapping clouds carry small loose droplets. Vary both spread and
    # density along the line so there is no uniform Gaussian outline around it.
    spread = np.clip(5.6 + .95 * wisps, 3.7, 7.8)
    mist = np.exp(-.5 * (distance / spread) ** 2)
    mist *= np.clip((19.0 - distance) / 5.0, 0, 1)
    drops = nd.gaussian_filter((grain > .935 - .03 * wisps).astype(np.float32), .48)
    mist *= np.clip(.145 + .044 * wisps, .045, .255) + .36 * drops

    # Let the same tiny cavities in the plaster interrupt the deposited colour.
    tooth = .90 + .08 * grain - .32 * pigment_pores(pores, stroke.shape)
    alpha = 1 - (1 - core * tooth) * (1 - mist)

    # A mark that ran off the photograph fades out, rather than ending on a paper edge.
    x, y = np.arange(grey.width), np.arange(grey.height)
    edge = np.minimum.outer(np.minimum(y, y[::-1]), np.minimum(x, x[::-1]))
    alpha *= np.pad(np.minimum(1.0, (edge + 6) / 17), 20, mode="edge")
    alpha[alpha < .024] = 0
    # Resize coverage alone so transparent RGB stays the same ink colour, then
    # quantize to 32 levels: WebP can pack the alpha without a noisy colour halo.
    coverage = Image.fromarray(np.rint(alpha * 255).astype(np.uint8))
    coverage = coverage.resize(PAINT_OUTPUT_SIZE, Image.Resampling.LANCZOS)
    coverage = coverage.point(lambda value: min(255, round(value / 8) * 8))
    paint = Image.new("RGBA", PAINT_OUTPUT_SIZE, INK)
    paint.putalpha(coverage)
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
    albedo, normal, pores = plaster_finish()
    # Keep the pore field at full precision for alignment; only downsample the
    # final two maps, since their fine grain is already filtered at viewing scale.
    albedo = albedo.resize((PLASTER_OUTPUT_PX, PLASTER_OUTPUT_PX), Image.Resampling.LANCZOS)
    normal = normal.resize((NORMAL_OUTPUT_PX, NORMAL_OUTPUT_PX), Image.Resampling.LANCZOS)
    paint = extract_paint(args.source, pores)
    mesh = ink_mesh(np.asarray(paint.getchannel("A")))
    args.output.mkdir(parents=True, exist_ok=True)
    paint.save(args.output / "wall_graffiti.png", optimize=True)
    albedo.save(args.output / "rose_plaster.png", optimize=True)
    normal.save(args.output / "rose_plaster_normal.png", optimize=True)
    (args.output / "wall_graffiti_ink.tres").write_text(mesh, encoding="utf-8")


if __name__ == "__main__":
    main()
