#!/usr/bin/env python3
"""Paints the front yard (前操场) and the school gate (校门) between it and the street.

    python3 scenes/environment/props/stage_art/source/paint_front_yard.py [names ...]

The owner's correction for this pass: out of the teaching block there should be no road,
only a dirt playground on both sides, a few dead dry trees, the big sliding retractable
gate (伸缩门) with a one-person side door (小门) beside it, and a card reader (刷卡机) just
inside that door. The street begins past the door.

The ground is painted the way the street's earth is (`paint_street_ditch.py`): noise built
as a photograph would be, then printed onto one ramp and dithered onto a small palette, so
the yard and the ditch bank come out of the same press. The yard's ramp is warmer: dry
loess under the dusk, not the street's wet mauve. Everything that tiles is filtered in the
frequency domain, so it wraps by construction. Nothing is downloaded, traced,
photographed or made by an image model. Fixed seeds 3161-3166.

Sizes are kept in step with `build_stage_art.py`, which places them:

* `yard_dirt.png`   - plan, a 4 x 4 m tile (world triplanar): packed dirt, scuffed, gritty.
* `yard_path.png`   - plan, 2.4 x 6 m, tiling along v: the trodden line from the door to
  the gate, paler and smoother, ragged at both edges (alpha cut).
* `wall_tiles.png`  - a 1.2 x 1.2 m tile of the wall's white facing tiles, grimed from
  the ground up, one or two cracked or replaced (world triplanar).
* `dry_grass.png`   - one tuft of dead grass, cut out, for crossed cards.
* `card_reader.png` - the reader's face: the card mark, a one-line screen, the lamp.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import paint_street_ditch as ditch  # noqa: E402
from paint_street_ditch import fbm, print_plate, smooth, stamp, wrap_noise  # noqa: E402

# Dry loess at dusk: dark clod, raw dirt, dust, the near-white of trodden chalky ground.
YARD_RAMP = [
    (0.00, (40, 33, 33)),
    (0.24, (86, 72, 66)),
    (0.48, (138, 118, 98)),
    (0.70, (180, 160, 132)),
    (0.87, (212, 196, 168)),
    (1.00, (234, 224, 202)),
]

DIRT_M, DIRT_PX_M = 4.0, 128.0
PATH_M, PATH_PX_M = (2.4, 6.0), 96.0
TILE_M, TILE_PX_M = 1.2, 200.0


def ramp(lum: np.ndarray, tint: np.ndarray | None = None) -> np.ndarray:
    keys = np.array([k for k, _ in YARD_RAMP])
    cols = np.array([c for _, c in YARD_RAMP], np.float64)
    lum = np.clip(lum, 0.0, 1.0)
    rgb = np.stack([np.interp(lum, keys, cols[:, i]) for i in range(3)], axis=-1)
    if tint is not None:
        rgb = rgb + tint
    return np.clip(rgb, 0, 255)


def scuffs(lum: np.ndarray, rng: np.random.Generator, count: int, px_m: float, along: float | None = None,
           strength: float = 0.07) -> None:
    """Shoe scuffs: short soft strokes, darker at one end where the heel dug in. `along`
    (radians) turns them all roughly one way, as on a path; None scatters them."""
    h, w = lum.shape
    for _ in range(count):
        y, x = rng.uniform(0, h), rng.uniform(0, w)
        a = (along if along is not None else rng.uniform(0, np.pi)) + rng.normal(0, 0.35)
        length = rng.uniform(0.12, 0.3) * px_m
        width = rng.uniform(0.03, 0.06) * px_m
        r = int(length) + 3
        ys = np.arange(int(y) - r, int(y) + r) % h
        xs = np.arange(int(x) - r, int(x) + r) % w
        gy, gx = np.meshgrid(np.arange(int(y) - r, int(y) + r) - y, np.arange(int(x) - r, int(x) + r) - x, indexing="ij")
        t = gx * np.cos(a) + gy * np.sin(a)
        n = -gx * np.sin(a) + gy * np.cos(a)
        mask = smooth(length / 2, length / 2 - 2, np.abs(t)) * smooth(width, width * 0.3, np.abs(n))
        heel = 0.6 + 0.4 * np.clip(t / (length / 2) + 0.5, 0, 1)
        sign = -1.0 if rng.random() < 0.7 else 0.6  # most dig in; some polish the ground
        patch = lum[np.ix_(ys, xs)]
        lum[np.ix_(ys, xs)] = patch + sign * strength * mask * heel


def leaves(lum: np.ndarray, tint: np.ndarray, rng: np.random.Generator, count: int, px_m: float) -> None:
    """Dead leaves: small dark ellipses with a pale midrib, rust-tinted."""
    h, w = lum.shape
    for _ in range(count):
        y, x = rng.uniform(0, h), rng.uniform(0, w)
        a = rng.uniform(0, np.pi)
        ln, wd = rng.uniform(0.035, 0.07) * px_m, rng.uniform(0.012, 0.025) * px_m
        r = int(ln) + 2
        ys = np.arange(int(y) - r, int(y) + r) % h
        xs = np.arange(int(x) - r, int(x) + r) % w
        gy, gx = np.meshgrid(np.arange(int(y) - r, int(y) + r) - y, np.arange(int(x) - r, int(x) + r) - x, indexing="ij")
        t = gx * np.cos(a) + gy * np.sin(a)
        n = -gx * np.sin(a) + gy * np.cos(a)
        d = np.hypot(t / max(ln, 1), n / max(wd, 1))
        mask = smooth(1.05, 0.75, d)
        v = rng.uniform(0.18, 0.34)
        lum[np.ix_(ys, xs)] = lum[np.ix_(ys, xs)] * (1 - mask) + v * mask
        lum[np.ix_(ys, xs)] += 0.12 * mask * smooth(0.9, 0.2, np.abs(n))
        tint[np.ix_(ys, xs, [0])] += (14 * mask)[..., None]
        tint[np.ix_(ys, xs, [2])] -= (8 * mask)[..., None]


def yard_dirt() -> Image.Image:
    """Packed dirt (plan, 4 x 4 m, tiles both ways).

    Trodden flat and pale where feet go; looser and darker in between, with grit and
    pebbles. Rain has left shallow dark pans that dried with a hairline crack or two. Shoe
    scuffs everywhere; a few dead leaves blown flat."""
    rng = np.random.default_rng(3161)
    n = int(DIRT_M * DIRT_PX_M)
    big = fbm(n, n, rng, 34.0)
    mid = fbm(n, n, rng, 11.0, 3)
    fine = wrap_noise(n, n, rng, 1.0)
    grit = wrap_noise(n, n, rng, 0.6)
    packed = smooth(-0.2, 0.7, big + 0.35 * mid)
    lum = 0.56 + 0.035 * big + 0.04 * mid + (0.05 - 0.03 * packed) * fine + 0.03 * grit * (1 - packed)
    lum += 0.06 * packed
    # dried pans: darker, a little smoother, ringed paler where the silt settled
    pan_field = fbm(n, n, rng, 26.0, 3)
    pan = smooth(0.85, 1.25, pan_field)
    rim = smooth(0.62, 0.82, pan_field) * smooth(1.0, 0.82, pan_field)
    lum += -0.07 * pan + 0.04 * rim
    edges = ditch.cells(n, n, rng, 70)
    yy, xx = np.mgrid[0:n, 0:n]
    wy = (yy + 3.0 * wrap_noise(n, n, rng, 7.0)).astype(int) % n
    wx = (xx + 3.0 * wrap_noise(n, n, rng, 7.0)).astype(int) % n
    edges = edges[wy, wx] + 0.25 * wrap_noise(n, n, rng, 1.2)
    lum -= 0.22 * smooth(1.1, 0.0, edges) * pan
    # pebbles and clods, mostly in the loose ground
    loose = 1.0 - packed
    stamp(lum, rng, 900, (0.6, 1.4), (0.3, 0.7), shadow=0.08, region=loose)
    stamp(lum, rng, 160, (1.4, 2.8), (0.48, 0.82), shadow=0.14, region=loose)
    stamp(lum, rng, 140, (0.8, 1.6), (0.72, 0.9), shadow=0.05)
    scuffs(lum, rng, 260, DIRT_PX_M)
    tint = np.zeros((n, n, 3))
    tint[..., 0] += 5 * packed - 3 * pan
    tint[..., 2] += 4 * pan
    leaves(lum, tint, rng, 70, DIRT_PX_M)
    return print_plate(ramp(lum, tint), 22)


def yard_path() -> Image.Image:
    """The trodden line from the teaching block's door to the side door (plan, 2.4 x 6 m,
    tiling along v). Paler and nearly smooth down the middle, scuffed all one way, the
    loose dirt pushed out to its edges; the edges ragged (alpha cut)."""
    rng = np.random.default_rng(3162)
    w, h = int(PATH_M[0] * PATH_PX_M), int(PATH_M[1] * PATH_PX_M)
    u = (np.arange(w)[None, :] / PATH_PX_M) - PATH_M[0] / 2
    big = fbm(h, w, rng, 40.0)
    fine = wrap_noise(h, w, rng, 0.9)
    half = 0.78 + 0.22 * wrap_noise(h, 1, rng, 50.0)[:, :1] + 0.06 * wrap_noise(h, 1, rng, 8.0)[:, :1]
    centre = 0.12 * wrap_noise(h, 1, rng, 90.0)[:, :1]
    d = np.abs(u - centre)
    core = smooth(half, half * 0.35, d)
    lum = 0.62 + 0.06 * big + 0.025 * fine + 0.1 * core
    # the loose dirt pushed out to the edges: a darker, grittier band
    shoulder = smooth(half * 0.55, half * 0.9, d) * smooth(half * 1.25, half * 0.95, d)
    lum -= 0.1 * shoulder
    stamp(lum, rng, 260, (0.6, 1.3), (0.34, 0.6), shadow=0.07, region=shoulder + 0.15)
    stamp(lum, rng, 60, (0.7, 1.2), (0.78, 0.92), shadow=0.04)
    scuffs(lum, rng, 340, PATH_PX_M, along=np.pi / 2, strength=0.06)
    rough = 0.1 * fbm(h, w, rng, 5.0, 3)
    alpha = smooth(0.06, -0.06, d - half * 1.12 + rough)
    crumbs = (fbm(h, w, rng, 2.5, 2) > 1.0 - 0.8 * smooth(half * 1.5, half, d)).astype(np.float64)
    alpha = np.maximum(alpha, crumbs * smooth(half * 1.5, half * 1.1, d))
    tint = np.zeros((h, w, 3))
    tint[..., 0] += 4 * core
    return print_plate(ramp(lum, tint), 18, alpha)


def wall_tiles() -> Image.Image:
    """The wall's facing (a 1.2 m tile, eight 0.15 m tiles a side). White glazed squares,
    not quite white: each one a shade off its neighbours, grout greyer, grime rising from
    the ground and run down from the coping, one tile cracked and one replaced whiter."""
    rng = np.random.default_rng(3163)
    n = int(TILE_M * TILE_PX_M)
    k = 8
    cell = n / k
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    gx, gy = (xx % cell) / cell, (yy % cell) / cell
    ix, iy = (xx // cell).astype(int), (yy // cell).astype(int)
    shade = rng.normal(0, 0.025, (k, k))
    shade[2, 5] = 0.07  # the replacement, whiter than the rest
    grout = np.minimum(np.minimum(gx, 1 - gx), np.minimum(gy, 1 - gy)) * cell
    joint = smooth(2.2, 0.8, grout)
    lum = 0.86 + shade[iy, ix] + 0.02 * wrap_noise(n, n, rng, 1.0)
    # the glaze's bevel: a light top-left edge, a dark lower-right
    lum += 0.04 * smooth(4.0, 1.5, np.minimum(gx, gy) * cell) - 0.05 * smooth(4.0, 1.5, np.minimum(1 - gx, 1 - gy) * cell)
    lum = lum * (1 - joint) + 0.52 * joint
    # grime: a soft tide line that wanders, and streaks down from above
    grime = smooth(0.2, 0.9, fbm(n, n, rng, 30.0, 3)) * 0.12
    streak = smooth(0.4, 1.6, wrap_noise(n, n, rng, 26.0, 1.4)) * 0.09
    lum -= grime + streak
    # one crack across a tile
    cy, cx = 5, 1
    t = np.linspace(0, 1, 200)
    py = (cy + 0.15 + 0.7 * t) * cell + 3 * np.sin(t * 9)
    px = (cx + 0.2 + 0.6 * t + 0.1 * np.sin(t * 5)) * cell
    img = np.zeros((n, n))
    img[np.clip(py.astype(int), 0, n - 1), np.clip(px.astype(int), 0, n - 1)] = 1
    crack = smooth(0.0, 0.4, np.maximum(img, np.roll(img, 1, 1)))
    lum -= 0.35 * crack
    tint = np.zeros((n, n, 3))
    tint[..., 2] += 6 * (1 - joint)  # a cold glaze against the warm dirt
    tint[..., 0] += 10 * (grime + streak)
    return print_plate(ramp(lum, tint), 16)


def dry_grass() -> Image.Image:
    """One tuft of dead grass, front view, cut out: straw blades bent over, a few broken."""
    rng = np.random.default_rng(3164)
    w, h = 128, 128
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for _ in range(46):
        x0 = w / 2 + rng.normal(0, 13)
        lean = rng.normal(0, 0.55)
        height = rng.uniform(0.45, 0.95) * h
        broken = rng.random() < 0.2
        pts = []
        steps = 9
        for i in range(steps + 1):
            t = i / steps
            if broken and t > 0.6:
                break
            droop = lean * t * t * height * 0.55
            pts.append((x0 + droop + lean * t * 8, h - 2 - height * t * (1 - 0.25 * abs(lean) * t)))
        tone = rng.uniform(0.0, 1.0)
        col = tuple(int(a + (b - a) * tone) for a, b in zip((118, 98, 70), (214, 192, 146))) + (255,)
        for i in range(len(pts) - 1):
            width = max(1, int(round(3.2 * (1 - i / steps))))
            draw.line([pts[i], pts[i + 1]], fill=col, width=width)
    # a darker heart at the base, where the old growth is
    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(base).ellipse((w / 2 - 22, h - 14, w / 2 + 22, h + 6), fill=(70, 58, 46, 255))
    img = Image.alpha_composite(base, img)
    rgb = np.asarray(img.convert("RGB"), np.float64)
    alpha = np.asarray(img)[..., 3] / 255.0
    return print_plate(rgb, 10, alpha)


def card_reader() -> Image.Image:
    """The reader's face, 96 x 128 px for 0.12 x 0.16 m: a dark glossy panel with the card
    mark (a card and three arcs), a one-line screen above it, the lamp below, and the
    paler wear round the mark where cards are pressed."""
    w, h = 96, 128
    img = Image.new("RGB", (w, h), (34, 36, 44))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((3, 3, w - 4, h - 4), radius=8, outline=(70, 74, 86), width=2)
    # the screen: dim green, one line of blocks
    draw.rectangle((14, 12, w - 14, 30), fill=(48, 78, 62))
    for i in range(6):
        draw.rectangle((19 + i * 10, 18, 25 + i * 10, 24), fill=(118, 170, 132))
    # wear round the mark
    draw.ellipse((14, 42, w - 14, 104), fill=(52, 54, 64))
    # the card and its arcs
    draw.rounded_rectangle((30, 64, 58, 82), radius=3, outline=(208, 210, 214), width=3)
    for i, r in enumerate((10, 16, 22)):
        draw.arc((56 - r, 60 - r, 56 + r, 60 + r), 300, 360, fill=(208, 210, 214), width=3)
    # the lamp: red, the way it is when nobody has swiped
    draw.ellipse((w / 2 - 6, 110, w / 2 + 6, 122), fill=(212, 64, 54))
    draw.ellipse((w / 2 - 2, 112, w / 2 + 2, 116), fill=(250, 160, 140))
    return img


TEXTURES = {
    "yard_dirt.png": yard_dirt,
    "yard_path.png": yard_path,
    "wall_tiles.png": wall_tiles,
    "dry_grass.png": dry_grass,
    "card_reader.png": card_reader,
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("names", nargs="*", help="only these textures (file names)")
    args = parser.parse_args()
    for name, painter in TEXTURES.items():
        if not args.names or name in args.names:
            ditch.save(painter(), name)


if __name__ == "__main__":
    main()
