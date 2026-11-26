#!/usr/bin/env python3
"""Measure a character's eyebrows the way issue #385 asks: as numbers, in millimetres.

    python3 tools/character_review/brow_report.py                 # all three characters
    python3 tools/character_review/brow_report.py lead q n        # any subset

Three questions per character, all on the zero-morph rest pose of the committed
runtime GLB:

* **mirror** — for every brow vertex, the distance to its nearest mirrored
  counterpart on the other side. A modelling slip shows up as a p95 far above the
  mean; an intentional expression asymmetry lives in the morph deltas, not here.
* **gap** — the distance from each brow vertex to the nearest point on the head
  skin's surface (point-triangle distance, no direction). The brow tubes must ride
  the brow ridge: the seated ring's centre is ~0.5 mm off the skin and its section
  spans another ±2 mm, so a healthy tube reads 1-3 mm; the V1 protagonist's
  7-10 mm float is the reference defect, and a brow hidden inside the skull reads
  the same way from underneath.
* **arch** — each side's centre-line height at the inner, middle and outer third,
  so a whole-tube droop on one side (the V1-style "one brow lower") is visible in
  one line.

Ray casting is Möller-Trumbore over the head skin's triangles; the forward axis is
per character (+Z for the protagonist and Q, -Z for teacher N), detected from the
skin's own midline profile, not assumed.

The report prints numbers; it does not pass or fail them. The pass/fail bands live
in the tests that pin each character's contract (tests/head_v2_test.py for the
protagonist, tests/character_sculpt_test.py for Q and N).
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import brow_seat  # noqa: E402
from glb_io import accessor, decode  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]

# (label, GLB, mesh name, brow prim index, head-skin mesh name)
CHARACTERS = {
    "lead": ("assets/models/protagonist/Protagonist_Character.glb", "Protagonist_Head", 1, "Protagonist_Head", 0),
    "q": ("assets/models/q/new-Q.glb", "Q_Head", 1, "Q_Head", 0),
    "n": ("assets/models/teacher-n/teacher-n.glb", None, None, "ST_Head_Skin", 0),
}


def mesh_named(doc, name):
    return next(i for i, mesh in enumerate(doc["meshes"]) if (mesh.get("name") or "") == name)


def load(path, mesh_name, prim_index):
    doc, blob = decode((ROOT.parent / path).read_bytes())
    mesh = doc["meshes"][mesh_named(doc, mesh_name)]
    prim = mesh["primitives"][prim_index]
    positions = np.asarray(accessor(doc, blob, prim["attributes"]["POSITION"]), float)
    return doc, blob, mesh, prim, positions


def forward_axis(skin):
    """+1 or -1: which way the face points, from the skin's own midline profile.

    The nose tip is the midline's most extreme point near the head's vertical
    middle; the band is taken relative to the skin's own height so it works for
    each character regardless of where their face sits in the file.
    """
    mid = (skin[:, 1].min() + skin[:, 1].max()) / 2.0
    band = skin[(np.abs(skin[:, 0]) < 0.006) & (np.abs(skin[:, 1] - mid) < 0.06)]
    if not len(band):
        raise ValueError("no midline vertices near the head's vertical middle; check the mesh")
    tip = band[np.argmax(np.abs(band[:, 2]))]
    return 1.0 if tip[2] > 0 else -1.0


def ray_cast(skin, triangles, origin, direction):
    """Distance along `direction` to the nearest skin triangle hit, or nan."""
    v0, v1, v2 = skin[triangles[:, 0]], skin[triangles[:, 1]], skin[triangles[:, 2]]
    e1, e2 = v1 - v0, v2 - v0
    p = np.cross(direction, e2)
    det = (e1 * p).sum(axis=1)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    tvec = origin - v0
    u = (tvec * p).sum(axis=1) * inv
    q = np.cross(tvec, e1)
    v = (q * e2).sum(axis=1) * inv
    t = (e2 * q).sum(axis=1) * inv
    hit = ok & (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1 + 1e-9) & (t > 1e-9)
    return float(t[hit].min()) if hit.any() else np.nan


def mirror(points):
    out = points.copy()
    out[:, 0] *= -1.0
    return out


def residuals(points, against):
    """Per-point distance to the nearest point of `against`."""
    return np.linalg.norm(points[:, None, :] - against[None, :, :], axis=2).min(axis=1)


def report(label):
    path, brow_mesh, brow_prim, skin_mesh, skin_prim = CHARACTERS[label]
    if brow_mesh is None:  # teacher N: two authored brow meshes, read together
        doc, blob, _, _, _ = load(path, skin_mesh, skin_prim)
        nm = mesh_named(doc, "ST_Eyebrow_L")
        rm = mesh_named(doc, "ST_Eyebrow_R")
        brow = np.concatenate([
            np.asarray(accessor(doc, blob, doc["meshes"][nm]["primitives"][0]["attributes"]["POSITION"]), float),
            np.asarray(accessor(doc, blob, doc["meshes"][rm]["primitives"][0]["attributes"]["POSITION"]), float),
        ])
        prim = doc["meshes"][mesh_named(doc, skin_mesh)]["primitives"][skin_prim]
    else:
        doc, blob, mesh, prim, brow = load(path, brow_mesh, brow_prim)
        sm = mesh_named(doc, skin_mesh)
        prim = doc["meshes"][sm]["primitives"][skin_prim]
    skin = np.asarray(accessor(doc, blob, prim["attributes"]["POSITION"]), float)
    triangles = np.asarray(accessor(doc, blob, prim["indices"]), dtype=np.int64).reshape(-1, 3)
    forward = forward_axis(skin)

    left, right = brow[brow[:, 0] < 0], brow[brow[:, 0] > 0]
    mirrored = brow_seat.mirror_residuals(brow) * 1000

    gap = brow_seat.surface_gap(skin, triangles, brow) * 1000

    centre_y = {}
    for name, points in (("L", left), ("R", right)):
        xs = np.abs(points[:, 0])
        lo, hi = xs.min(), xs.max()
        for band, (a, b) in (("inner", (0.0, 1 / 3)), ("mid", (1 / 3, 2 / 3)), ("outer", (2 / 3, 1.01))):
            sel = points[(xs >= lo + (hi - lo) * a) & (xs < lo + (hi - lo) * b)]
            centre_y[(name, band)] = float(sel[:, 1].mean() * 1000) if len(sel) else float("nan")

    print(label + f": forward {'+Z' if forward > 0 else '-Z'}, {len(brow)} brow vertices, {len(triangles)} skin triangles")
    print(f"  mirror residual  mean {mirrored.mean():.2f}mm  p95 {np.percentile(mirrored, 95):.2f}mm  max {mirrored.max():.2f}mm")
    print(f"  gap to skin:     mean {gap.mean():.2f}mm  max {gap.max():.2f}mm")
    arch = "  ".join(f"{band} L{centre_y[('L', band)]:.1f} R{centre_y[('R', band)]:.1f}" for band in ("inner", "mid", "outer"))
    print(f"  arch centre height (mm): {arch}")
    print("  arch L-R gap (mm): " + "  ".join(
        f"{band} {centre_y[('L', band)] - centre_y[('R', band)]:+.1f}" for band in ("inner", "mid", "outer")))
    return mirrored, gap


def main(argv):
    labels = argv or list(CHARACTERS)
    unknown = [label for label in labels if label not in CHARACTERS]
    if unknown:
        print(f"unknown character(s) {unknown}; pick from {sorted(CHARACTERS)}", file=sys.stderr)
        return 2
    for label in labels:
        report(label)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
