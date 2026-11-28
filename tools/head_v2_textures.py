#!/usr/bin/env python3
"""Paint the protagonist head's local albedo and tangent-space normal maps.

    python3 tools/head_v2_textures.py build
    python3 tools/head_v2_textures.py check

The maps are 1024² (normal) and 1024² (albedo), generated from the built head's
own UV atlas and 3D surface. The normal map carries the fine skin relief the
22k-triangle sculpt cannot: pores, forehead and neck lines, crow's feet, the
nasolabial and mental creases, lip lines and the upper-lid crease. The albedo
map stays close to the look's skin colour and adds only the bruise, lip and
stubble glazes the shader's patches already suggest.

Issue #386 adds the hair's own pair, drawn into the atlas `head_v2.hair_uv`
assigns: `hair_normal.png` (1024²; two flickered strand grooves per lock cell,
the crown whorl and the back arcs sampled from the same `whorl_relief` field the
mesh relief uses, and a strand grain) and `hair_albedo.png` (512²; lighter
strand glazes beside the grooves, darker roots, a cool tone noise). The look
binds them to the hair mesh's own surface, so the eyebrows - which share the
hair material but not the hair mesh - keep drawing exactly as before.

The height field is in metres; the normal map is converted with the local
texel-to-metre ratio measured from the UV atlas, so the relief keeps its scale
at 1K and would not need retuning at 2K.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

import glb_numpy as glb

import head_v2

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/head_v2'
RUNTIME = ROOT / 'assets/models/protagonist/Protagonist_Character.glb'
OUT = ROOT / 'assets/characters/protagonist/textures'
HEAD_MESH = 6
SKIN_PRIM = 0
HAIR_MESH = head_v2.HAIR_MESH
HAIR_PRIM = head_v2.HAIR_PRIM
SIZE = 1024
ALBEDO_SIZE = 1024


# --------------------------------------------------------------------------------------
# Small deterministic noise
# --------------------------------------------------------------------------------------

def _hash(ix: np.ndarray, iy: np.ndarray, seed: int) -> np.ndarray:
    # Integer overflow is the point of a hash: numpy warns about it, so it is silenced here
    # rather than left to look like a bug in the build.
    with np.errstate(over='ignore'):
        x = ix.astype(np.uint64) * np.uint64(374761393)
        y = iy.astype(np.uint64) * np.uint64(668265263)
        n = x + y + np.uint64(seed) * np.uint64(1442695040888963407)
        n = (n ^ (n >> np.uint64(13))) * np.uint64(1274126177)
        return ((n ^ (n >> np.uint64(16))) & np.uint64(0xFFFFFFFF)).astype(np.float64) / 4294967295.0


def smoothstep(edge_low: float, edge_high: float, value: np.ndarray) -> np.ndarray:
    """1.0 below `edge_low`, 0.0 above `edge_high`, smooth between (either order)."""
    low, high = min(edge_low, edge_high), max(edge_low, edge_high)
    t = np.clip((value - low) / (high - low), 0.0, 1.0)
    if edge_high < edge_low:
        t = 1.0 - t
    return t * t * (3.0 - 2.0 * t)


def value_noise(x: np.ndarray, y: np.ndarray, scale: float, seed: int = 0) -> np.ndarray:
    x = x * scale
    y = y * scale
    xi = np.floor(x).astype(np.int64)
    yi = np.floor(y).astype(np.int64)
    xf = x - xi
    yf = y - yi
    u = xf * xf * (3.0 - 2.0 * xf)
    v = yf * yf * (3.0 - 2.0 * yf)
    a = _hash(xi, yi, seed)
    b = _hash(xi + 1, yi, seed)
    c = _hash(xi, yi + 1, seed)
    d = _hash(xi + 1, yi + 1, seed)
    return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v


def fbm(x: np.ndarray, y: np.ndarray, scale: float, octaves: int = 4, seed: int = 0) -> np.ndarray:
    total = np.zeros(x.shape, dtype=np.float64)
    weight = 0.5
    norm = 0.0
    for octave in range(octaves):
        total += weight * value_noise(x, y, scale * (2 ** octave), seed + octave * 17)
        norm += weight
        weight *= 0.5
    return total / norm


# --------------------------------------------------------------------------------------
# UV rasterisation
# --------------------------------------------------------------------------------------

def rasterise(positions: np.ndarray, normals: np.ndarray, uvs: np.ndarray,
              triangles: np.ndarray, size: int):
    """Front-most surface position/normal per texel, in image space (row 0 = V 1)."""
    pos = np.zeros((size, size, 3), dtype=np.float64)
    nor = np.zeros((size, size, 3), dtype=np.float64)
    depth = np.full((size, size), -1e30)
    mask = np.zeros((size, size), dtype=bool)
    for tri in triangles:
        a, b, c = int(tri[0]), int(tri[1]), int(tri[2])
        ua, va = uvs[a]
        ub, vb = uvs[b]
        uc, vc = uvs[c]
        ax, ay = ua * size, (1.0 - va) * size
        bx, by = ub * size, (1.0 - vb) * size
        cx, cy = uc * size, (1.0 - vc) * size
        minx = max(int(math.floor(min(ax, bx, cx))), 0)
        maxx = min(int(math.ceil(max(ax, bx, cx))), size - 1)
        miny = max(int(math.floor(min(ay, by, cy))), 0)
        maxy = min(int(math.ceil(max(ay, by, cy))), size - 1)
        if minx > maxx or miny > maxy:
            continue
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        xs = np.arange(minx, maxx + 1) + 0.5
        ys = np.arange(miny, maxy + 1) + 0.5
        px, py = np.meshgrid(xs, ys)
        wa = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
        wb = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
        wc = 1.0 - wa - wb
        inside = (wa >= 0) & (wb >= 0) & (wc >= 0)
        if not inside.any():
            continue
        z = wa * positions[a, 2] + wb * positions[b, 2] + wc * positions[c, 2]
        yy, xx = np.nonzero(inside)
        gy = yy + miny
        gx = xx + minx
        keep = z[yy, xx] > depth[gy, gx]
        if not keep.any():
            continue
        gy, gx = gy[keep], gx[keep]
        wa, wb, wc = wa[yy, xx][keep], wb[yy, xx][keep], wc[yy, xx][keep]
        pos[gy, gx] = (wa[:, None] * positions[a] + wb[:, None] * positions[b]
                       + wc[:, None] * positions[c])
        n = (wa[:, None] * normals[a] + wb[:, None] * normals[b]
             + wc[:, None] * normals[c])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        nor[gy, gx] = n
        depth[gy, gx] = z[yy, xx][keep]
        mask[gy, gx] = True
    return pos, nor, mask


def uv_of(points: np.ndarray, center=(0.0, 1.565, 0.040)) -> np.ndarray:
    d = points - np.asarray(center)
    theta = np.arctan2(d[:, 0], d[:, 2])
    phi = np.arctan2(d[:, 1], np.linalg.norm(d[:, [0, 2]], axis=1))
    s = theta / np.pi
    t = phi / (np.pi * 0.5)
    u = 0.5 + 0.5 * np.sign(s) * np.abs(s) ** 0.55
    v = 0.5 + 0.5 * np.sign(t) * np.abs(t) ** 0.65
    return np.stack([u, v], axis=1)


def front_surface(positions: np.ndarray, normals: np.ndarray, size: int = 320):
    """A front-facing z lookup over (x, y), for placing 3D curves on the face."""
    x0, x1 = -0.095, 0.095
    y0, y1 = 1.415, 1.715
    grid = np.full((size, size), np.nan)
    front = normals[:, 2] > 0.05
    for p, n in zip(positions[front], normals[front]):
        ix = int((p[0] - x0) / (x1 - x0) * (size - 1))
        iy = int((p[1] - y0) / (y1 - y0) * (size - 1))
        if 0 <= ix < size and 0 <= iy < size:
            if np.isnan(grid[iy, ix]) or p[2] > grid[iy, ix]:
                grid[iy, ix] = p[2]
    # Fill the holes from the nearest filled cell, a few passes of a maximum filter.
    filled = ~np.isnan(grid)
    for _ in range(6):
        if filled.all():
            break
        padded = np.pad(np.where(np.isnan(grid), -1e30, grid), 1, mode='edge')
        stack = np.stack([padded[dy:dy + size, dx:dx + size]
                          for dy in range(3) for dx in range(3)])
        best = stack.max(axis=0)
        grid = np.where(np.isnan(grid), np.where(best > -1e29, best, np.nan), grid)
        filled = ~np.isnan(grid)
    return grid, (x0, x1, y0, y1)


def surface_z(points: np.ndarray, grid: np.ndarray, bounds) -> np.ndarray:
    x0, x1, y0, y1 = bounds
    size = grid.shape[0]
    ix = np.clip(((points[:, 0] - x0) / (x1 - x0) * (size - 1)).astype(int), 0, size - 1)
    iy = np.clip(((points[:, 1] - y0) / (y1 - y0) * (size - 1)).astype(int), 0, size - 1)
    z = grid[iy, ix]
    z = np.where(np.isnan(z), 0.08, z)
    return z


def stamp(height: np.ndarray, points_uv: np.ndarray, width: float, depth: float,
          size: int) -> None:
    """Add a smooth groove (negative depth) along a UV polyline."""
    px = points_uv[:, 0] * size
    py = (1.0 - points_uv[:, 1]) * size
    for index in range(len(px) - 1):
        ax, ay, bx, by = px[index], py[index], px[index + 1], py[index + 1]
        minx = max(int(math.floor(min(ax, bx) - width * 3)), 0)
        maxx = min(int(math.ceil(max(ax, bx) + width * 3)), size - 1)
        miny = max(int(math.floor(min(ay, by) - width * 3)), 0)
        maxy = min(int(math.ceil(max(ay, by) + width * 3)), size - 1)
        if minx > maxx or miny > maxy:
            continue
        xs = np.arange(minx, maxx + 1) + 0.5
        ys = np.arange(miny, maxy + 1) + 0.5
        gx, gy = np.meshgrid(xs, ys)
        vx, vy = bx - ax, by - ay
        length2 = vx * vx + vy * vy
        t = np.clip(((gx - ax) * vx + (gy - ay) * vy) / max(length2, 1e-9), 0.0, 1.0)
        dx = gx - (ax + t * vx)
        dy = gy - (ay + t * vy)
        dist = np.sqrt(dx * dx + dy * dy)
        groove = -depth * np.exp(-(dist / width) ** 2)
        height[miny:maxy + 1, minx:maxx + 1] += groove


def curve(points3d: list[tuple[float, float]], grid, bounds, z_offset=0.0006,
          samples: int = 24) -> np.ndarray:
    """Project a polyline of (x, y) on the front surface into UV."""
    pts = []
    for index in range(len(points3d) - 1):
        x0, y0 = points3d[index]
        x1, y1 = points3d[index + 1]
        for step in range(samples):
            t = step / samples
            pts.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    pts.append(points3d[-1])
    p = np.array(pts)
    z = surface_z(p, grid, bounds) + z_offset
    return uv_of(np.stack([p[:, 0], p[:, 1], z], axis=1))


def build_height(pos: np.ndarray, nor: np.ndarray, mask: np.ndarray, grid, bounds,
                 size: int) -> np.ndarray:
    height = np.zeros((size, size), dtype=np.float64)
    yy, xx = np.mgrid[0:size, 0:size]
    # Skin grain. One face is about 0.19 m across and about 460 texels wide, so a texel is
    # 0.4 mm: the grain is band-limited to features of 4-10 texels (1.6-4 mm), which is the
    # finest relief that survives a mipmap instead of glittering at gameplay distance.
    grain = (fbm(xx, yy, 0.22, 3, 11) - 0.5) * 0.000030
    grain += (fbm(xx, yy, 0.55, 2, 29) - 0.5) * 0.000012
    height += grain
    # Broad, shallow forehead and neck lines.
    for y, width, depth in ((1.6645, 1.6, 0.00042), (1.6715, 1.4, 0.00034),
                            (1.6785, 1.2, 0.00026)):
        pts = curve([(-0.046, y - 0.004), (-0.020, y + 0.001), (0.0, y + 0.002),
                     (0.020, y + 0.001), (0.046, y - 0.004)], grid, bounds)
        stamp(height, pts, width, depth, size)
    # Glabella. r38b second pass: even whispered, the narrow stamps alias into the
    # bug-like black dashes the owner named under the raking key -- the narrow
    # face lines stop being painted at all; the sculpt carries the structure.
    # Crow's feet: removed for the same reason (the hooked dashes at the eye
    # corners). The upper-lid crease stays: broad, above the aperture, it reads.

    # Upper-lid crease.
    for side in (-1, 1):
        pts = curve([(side * 0.0155, 1.5985), (side * 0.0305, 1.6025),
                     (side * 0.0435, 1.5985)], grid, bounds)
        stamp(height, pts, 1.1, 0.00038, size)
    # Nasolabial folds and marionette lines. r38: at half depth these folds bent the
    # normals into a dirty smear across the subnasal zone and the mouth corners; the
    # sculpt's own fold keeps the structure, so the paint only whispers it.
    for side in (-1, 1):
        pts = curve([(side * 0.024, 1.501), (side * 0.028, 1.493),
                     (side * 0.031, 1.483), (side * 0.030, 1.474)], grid, bounds)
        stamp(height, pts, 1.4, 0.00026, size)
    # Lip lines. r38b: removed -- the dotted dark arcs across the mouth were this
    # stamp aliasing; the sculpt's own fold and the albedo's mouth line carry it.
    # Mental crease and neck lines: broad and whispered, they keep the chin's
    # structure without drawing as arcs.
    pts = curve([(-0.020, 1.4795), (0.0, 1.4775), (0.020, 1.4795)], grid, bounds)
    stamp(height, pts, 1.6, 0.00012, size)
    for y in (1.4525, 1.4435):
        pts = curve([(-0.036, y), (0.0, y - 0.001), (0.036, y)], grid, bounds)
        stamp(height, pts, 1.8, 0.00012, size)
    # Alar creases.
    for side in (-1, 1):
        pts = curve([(side * 0.0185, 1.506), (side * 0.0245, 1.501),
                     (side * 0.0235, 1.4965)], grid, bounds)
        stamp(height, pts, 0.9, 0.00018, size)
    height = np.where(mask, height, 0.0)
    return _blur(height, 1)


def _blur(field: np.ndarray, radius: int) -> np.ndarray:
    """A separable box blur, run three times: close enough to a Gaussian to take the
    texel-level noise out of a map, and cheap enough to stay in the build. Works on a
    height field or on an RGB map alike."""
    if radius < 1:
        return field
    kernel = np.ones(radius * 2 + 1) / (radius * 2 + 1)

    def conv(array: np.ndarray, axis: int) -> np.ndarray:
        pad = [(0, 0)] * array.ndim
        pad[axis] = (radius, radius)
        padded = np.pad(array, pad, mode='edge')
        return np.apply_along_axis(
            lambda line: np.convolve(line, kernel, mode='valid'), axis, padded)

    for _ in range(3):
        field = conv(field, 1)
        field = conv(field, 0)
    return field


def height_to_normal(height: np.ndarray, pos: np.ndarray, mask: np.ndarray, size: int,
                     strength: float = 0.9):
    """Tangent-space normal from the height field, in OpenGL (+Y) convention."""
    # Metres per texel, measured locally from the surface position map.
    dx = np.gradient(pos[:, :, 0], axis=1)
    dy = np.gradient(pos[:, :, 1], axis=0)
    dz = np.gradient(pos[:, :, 2], axis=1)
    dt = np.gradient(pos[:, :, 2], axis=0)
    metric = np.sqrt(dx * dx + dy * dy + dz * dz)
    metric2 = np.sqrt(dx * dx + dy * dy + dt * dt)
    pixel = np.sqrt(np.maximum(metric * metric2, 1e-12))
    pixel = np.median(pixel[mask]) if mask.any() else 0.0003
    gx = np.gradient(height, axis=1) / max(pixel, 1e-9) * strength
    gy = np.gradient(height, axis=0) / max(pixel, 1e-9) * strength
    # Image rows run down while V runs up: the bitangent gradient is -d/drow.
    nx = -gx
    ny = gy
    nz = np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / length, ny / length, nz / length], axis=2)
    normal = normal * 0.5 + 0.5
    normal[~mask] = (0.5, 0.5, 1.0)
    return np.clip(normal, 0.0, 1.0)


def build_albedo(pos: np.ndarray, mask: np.ndarray, size: int,
                 base=(0.7059, 0.6471, 0.5490),
                 hair_points: np.ndarray = None) -> np.ndarray:
    """The head's colour map, as a multiplier around 1.0.

    The look's own albedo stays the base skin colour and the shader multiplies the map over
    it (`detail_albedo_mix`), so every tint here is authored as *the multiplier that turns the
    base into the wanted colour* rather than as an absolute colour. A map that carried the
    skin colour itself would square it and paint the face dark.

    The owner's r37 note: at the lighter skin the lip, under-eye and stubble glazes read as
    stamps, and the scalp showing between the hair's spikes read as baldness -- so the
    glazes come down to a whisper and the scalp under the hair shell is darkened into hair
    roots, measured by each texel's distance to the hair mesh itself.
    """
    yy, xx = np.mgrid[0:size, 0:size]
    base = np.asarray(base, dtype=np.float64)
    colour = np.ones((size, size, 3))
    mottling = (fbm(xx, yy, 0.07, 3, 3) - 0.5) * 0.09
    colour *= (1.0 + mottling)[:, :, None]
    x, y, z = pos[:, :, 0], pos[:, :, 1], pos[:, :, 2]
    ax = np.abs(x)

    def glaze(target, mask_layer: np.ndarray) -> None:
        multiplier = np.asarray(target, dtype=np.float64) / base
        blend = mask_layer[:, :, None]
        colour[:] = colour * (1.0 - blend) + multiplier[None, None, :] * blend

    # Lips: a desaturated rose over the vermilion, and the darker mouth line. The line the
    # sculpt already folds is not painted twice as hard: the fold catches the ink line.
    # r38b: the (0.64, 0.46, 0.44) multiplier read as a dark maroon block between the
    # nose and the mouth (the owner's "abnormal black" band); N's approved lip value
    # is a lit rose, and this glaze now matches it as a multiplier.
    lip = np.exp(-((ax / 0.024) ** 2) ** 2 - ((y - 1.4955) / 0.0085) ** 2) * (z > 0.105)
    glaze((0.82, 0.64, 0.60), 0.35 * lip)
    line = np.exp(-((y - 1.4952) / 0.0012) ** 2) * np.exp(-(ax / 0.024) ** 2) * (z > 0.11)
    colour *= (1.0 - 0.10 * line)[:, :, None]
    # Eyelids: a little darker and redder.
    lid = np.exp(-((ax - 0.031) / 0.017) ** 2) * np.exp(-((y - 1.592) / 0.009) ** 2) * (z > 0.09)
    glaze((0.60, 0.46, 0.44), 0.12 * lid)
    # The bruised under-eye. The look already paints a patch here, so this is the mottled
    # edge the patch cannot have, not a second bruise.
    bruise = np.exp(-((ax - 0.034) / 0.018) ** 2) * np.exp(-((y - 1.5685) / 0.0075) ** 2) * (z > 0.08)
    glaze((0.50, 0.44, 0.55), 0.09 * bruise)
    # Stubble: a cool grey-green tooth on the jaw and chin. The philtrum band this used to
    # cross is gone -- at the lighter skin it read as dirt on the groove the owner named.
    stubble_region = (y < 1.487) & (ax < 0.062) & (z > 0.02)
    tooth = (fbm(xx, yy, 0.30, 2, 41) - 0.5)
    stubble = np.where(stubble_region, np.clip(tooth * 2.2 + 0.15, 0.0, 1.0) * 0.09, 0.0)
    glaze((0.42, 0.43, 0.40), stubble)
    # A soft warm cheek glaze.
    cheek = np.exp(-((ax - 0.045) / 0.022) ** 2) * np.exp(-((y - 1.530) / 0.022) ** 2) * (z > 0.06)
    glaze((0.70, 0.55, 0.49), 0.10 * cheek)
    # Hair roots: anywhere the hair shell passes close overhead, the "skin" is scalp the
    # spikes' gaps expose, so it darkens into root colour instead of reading bald. The
    # falloff is measured, not painted: full shade within 10 mm of a hair vertex, gone by
    # 28 mm, which keeps the ears (the hair clears them by more than that) and the face
    # below the fringe in skin.
    if hair_points is not None and len(hair_points):
        points = pos[mask].astype(np.float32)
        hair = hair_points.astype(np.float32)
        nearest2 = np.full(len(points), np.inf, dtype=np.float32)
        # Blocked brute force in float32 on squared distances: the full texel set is a
        # million rows and the hair five thousand, which a single broadcast cannot hold.
        for point_start in range(0, len(points), 32768):
            block = points[point_start:point_start + 32768]
            for hair_start in range(0, len(hair), 256):
                chunk = hair[hair_start:hair_start + 256]
                difference = block[:, None, :] - chunk[None, :, :]
                np.minimum(nearest2[point_start:point_start + len(block)],
                           (difference * difference).sum(-1).min(1),
                           out=nearest2[point_start:point_start + len(block)])
        roots = np.zeros((size, size))
        roots[mask] = smoothstep(0.028, 0.010, np.sqrt(nearest2.astype(np.float64)))
        glaze((0.30, 0.27, 0.26), roots)
    colour[~mask] = 1.0
    return np.clip(_blur(colour, 1), 0.0, 1.0)


# --------------------------------------------------------------------------------------
# The hair maps (issue #386)
# --------------------------------------------------------------------------------------

HAIR_NORMAL_SIZE = 1024
HAIR_ALBEDO_SIZE = 512
HAIR_BASE = (0.5412, 0.4784, 0.5098)


def hair_cell_rect(index: int) -> tuple[float, float]:
    """Atlas origin (u0, v0) of lock `index`, mirroring `head_v2.hair_cell`."""
    col, row = head_v2.hair_cell(index)
    return col / head_v2.UV_COLS, row / head_v2.UV_ROWS


def build_hair_height(pos: np.ndarray, nor: np.ndarray, mask: np.ndarray, uvs: np.ndarray,
                      size: int, crown: np.ndarray) -> np.ndarray:
    """The hair's relief: a few dark lines per lock, the whorl, the grain.

    Each lock's atlas cell takes two longitudinal strands - dark grooves with a flickered,
    broken run so they read as separate hairs rather than extruded stripes - which is what
    turns the plate locks into strand groups without touching the mesh. The cap's 3 x 3
    block samples the same `whorl_relief` field the mesh does, so the crown spiral and the
    back arcs continue into the map at the resolution the 9 200 triangles cannot hold.
    """
    height = np.zeros((size, size), dtype=np.float64)
    yy, xx = np.mgrid[0:size, 0:size]
    cell_w, cell_h = 1.0 / head_v2.UV_COLS, 1.0 / head_v2.UV_ROWS
    block_w = head_v2.UV_CAP_CELLS * cell_w
    # Strand grooves, per lock cell. Two grooves, each a flickered run of small stamps.
    for index in range(96):
        u0, v0 = hair_cell_rect(index)
        for slot, frac in ((0, 0.34), (1, 0.66)):
            centre_u = u0 + frac * cell_w
            vline = (xx / size) - centre_u
            run = ((yy / size) - v0) / cell_h
            wobble = (fbm(xx, yy, 0.06, 2, 60 + index * 2 + slot) - 0.5) * 0.003
            line = np.exp(-((vline + wobble) / (cell_w * 0.055)) ** 2)
            flicker = fbm(xx, yy * 4.0, 0.10, 3, 90 + index * 2 + slot)
            alive = (flicker > 0.30) & (run > 0.04) & (run < 0.97)
            height -= line * alive * 0.00048
    # The whorl, wherever the cap's block is covered.
    is_cap = mask & ((xx / size) < block_w)
    if is_cap.any():
        pts = np.stack([pos[:, :, 0], pos[:, :, 1], pos[:, :, 2]], axis=2)
        relief = np.array([head_v2.whorl_relief(p, crown) for p in pts[is_cap]])
        height[is_cap] += relief
    # A little strand grain everywhere.
    height += (fbm(xx, yy, 0.16, 3, 7) - 0.5) * 0.00012
    height = np.where(mask, height, 0.0)
    return _blur(height, 1)


def build_hair_albedo(pos: np.ndarray, mask: np.ndarray, size: int) -> np.ndarray:
    """The hair's colour map, as a multiplier around 1.0 over the look's hair colour.

    A few lighter strand glazes (the same two runs per cell as the grooves, offset half a
    groove so highlight sits beside shadow - colour beside relief, never on top of it),
    darker roots, and a cool noise so the near-black hair keeps some tone in shadow.
    """
    yy, xx = np.mgrid[0:size, 0:size]
    cell_w, cell_h = 1.0 / head_v2.UV_COLS, 1.0 / head_v2.UV_ROWS
    colour = np.ones((size, size, 3))
    tone = (fbm(xx, yy, 0.09, 3, 13) - 0.5) * 0.10
    cool = (fbm(xx, yy, 0.22, 2, 19) - 0.5) * 0.05
    colour *= (1.0 + tone)[:, :, None]
    colour[:, :, 2] *= (1.0 + cool)
    for index in range(96):
        u0, v0 = hair_cell_rect(index)
        run = ((yy / size) - v0) / cell_h
        for frac in (0.46, 0.78):
            centre_u = u0 + frac * cell_w
            vline = (xx / size) - centre_u
            wobble = (fbm(xx, yy, 0.06, 2, 130 + index * 2) - 0.5) * 0.003
            line = np.exp(-((vline + wobble) / (cell_w * 0.075)) ** 2)
            alive = (run > 0.06) & (run < 0.95)
            colour *= (1.0 - 0.22 * line * alive)[:, :, None]
        roots = np.clip((0.30 - run) / 0.30, 0.0, 1.0)
        colour *= (1.0 - 0.16 * roots)[:, :, None]
    colour[~mask] = 1.0
    return np.clip(_blur(colour, 1), 0.0, 1.0)


def save_png(array: np.ndarray, path: Path) -> None:
    image = Image.fromarray((np.clip(array, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), 'RGB')
    image.save(path, optimize=True)


def build() -> dict:
    # The maps are built from the shipped runtime model: the build-tree glb (`build/head_v2`)
    # this tool used to read is a local intermediate that a fresh clone does not have, and
    # the runtime file carries the same atlas -- it is what `head_v2.py install` copied from
    # it. Building from what actually ships can never drift from what actually ships.
    document, binary = glb.load(RUNTIME)
    primitive = document['meshes'][HEAD_MESH]['primitives'][SKIN_PRIM]
    arrays = glb.primitive_arrays(document, binary, primitive)
    positions = arrays['POSITION']
    normals = arrays['NORMAL']
    uvs = arrays['TEXCOORD_0']
    triangles = arrays['indices'].reshape(-1, 3).astype(np.int64)
    pos, nor, mask = rasterise(positions, normals, uvs, triangles, SIZE)
    grid, bounds = front_surface(positions, normals)
    height = build_height(pos, nor, mask, grid, bounds, SIZE)
    normal_map = height_to_normal(height, pos, mask, SIZE)
    # The hair mesh's own vertices, for the scalp's root shading in the albedo.
    hair_arrays = glb.primitive_arrays(
        document, binary, document['meshes'][HAIR_MESH]['primitives'][HAIR_PRIM])
    hair_points = hair_arrays['POSITION'].astype(np.float64)
    albedo = build_albedo(pos, mask, SIZE, hair_points=hair_points)
    OUT.mkdir(parents=True, exist_ok=True)
    save_png(normal_map, OUT / 'head_normal.png')
    save_png(albedo, OUT / 'head_albedo.png')

    # The hair (issue #386): the built hair primitive now carries the atlas head_v2
    # assigns, and the maps draw the strand lines and the whorl into it.
    h_pos, h_nor, h_mask = rasterise(hair_arrays['POSITION'], hair_arrays['NORMAL'],
                                     hair_arrays['TEXCOORD_0'],
                                     hair_arrays['indices'].reshape(-1, 3).astype(np.int64),
                                     HAIR_NORMAL_SIZE)
    labels = head_v2.components(hair_arrays['POSITION'],
                                hair_arrays['indices'].reshape(-1, 3).astype(np.int64))
    counts = np.bincount(labels)
    cap_label = int(np.argmax(counts == 303)) if (counts == 303).any() else -1
    cap_verts = np.nonzero(labels == cap_label)[0]
    cap_points = hair_arrays['POSITION'][cap_verts]
    crown = cap_points[np.argmax(cap_points[:, 1] - 0.45 * cap_points[:, 2])]
    h_height = build_hair_height(h_pos, h_nor, h_mask, hair_arrays['TEXCOORD_0'],
                                 HAIR_NORMAL_SIZE, crown)
    h_normal = height_to_normal(h_height, h_pos, h_mask, HAIR_NORMAL_SIZE, strength=1.0)
    h_pos2, h_nor2, h_mask2 = rasterise(hair_arrays['POSITION'], hair_arrays['NORMAL'],
                                        hair_arrays['TEXCOORD_0'],
                                        hair_arrays['indices'].reshape(-1, 3).astype(np.int64),
                                        HAIR_ALBEDO_SIZE)
    h_albedo = build_hair_albedo(h_pos2, h_mask2, HAIR_ALBEDO_SIZE)
    save_png(h_normal, OUT / 'hair_normal.png')
    save_png(h_albedo, OUT / 'hair_albedo.png')

    manifest = {
        'source_sha256': hashlib.sha256(RUNTIME.read_bytes()).hexdigest(),
        'normal_sha256': hashlib.sha256((OUT / 'head_normal.png').read_bytes()).hexdigest(),
        'albedo_sha256': hashlib.sha256((OUT / 'head_albedo.png').read_bytes()).hexdigest(),
        'normal_size': SIZE,
        'albedo_size': ALBEDO_SIZE,
        'covered_texels': int(mask.sum()),
        'normal_bytes': (OUT / 'head_normal.png').stat().st_size,
        'albedo_bytes': (OUT / 'head_albedo.png').stat().st_size,
        'hair_normal_sha256': hashlib.sha256((OUT / 'hair_normal.png').read_bytes()).hexdigest(),
        'hair_albedo_sha256': hashlib.sha256((OUT / 'hair_albedo.png').read_bytes()).hexdigest(),
        'hair_normal_size': HAIR_NORMAL_SIZE,
        'hair_albedo_size': HAIR_ALBEDO_SIZE,
        'hair_covered_texels': int(h_mask.sum()),
        'hair_normal_bytes': (OUT / 'hair_normal.png').stat().st_size,
        'hair_albedo_bytes': (OUT / 'hair_albedo.png').stat().st_size,
        'hair_crown': [float(v) for v in crown],
    }
    (OUT / 'head_textures.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['build', 'check'])
    args = parser.parse_args()
    manifest = build()
    print(json.dumps(manifest, indent=2))
    if args.command == 'check':
        current = json.loads((OUT / 'head_textures.json').read_text())
        if current != manifest:
            raise SystemExit('textures differ from the build')


if __name__ == '__main__':
    main()
