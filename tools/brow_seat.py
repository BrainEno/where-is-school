"""Millimetre measurement for eyebrow audits (issue #385).

The review report and the model contracts share these helpers:

    from brow_seat import mirror_residuals, arch_profile, surface_gap

- mirror_residuals: per-vertex distance to the nearest mirrored counterpart on
  the other brow, in metres. A healthy hand-built pair reads ~1 mm; a tilted
  pair reads in the high single digits.
- arch_profile: the brow band's centre height per third (inner/mid/outer) per
  side, so an L-R height gap can be attributed to one band instead of guessed.
- surface_gap: distance from each brow vertex to the nearest point on any skin
  triangle. Direction-free on purpose: a brow's tail wraps around the temple,
  where a ray along the face axis grazes past the local surface and overstates
  the distance.

Symmetrizing is deliberately not in here. The owners' standard for #385 keeps
authored brow asymmetry (Q carries a Brow_Asymmetric morph; N's pair is
hand-built within a millimetre), so a skew is measured, attributed and put to
the owner rather than flattened by one key.
"""
from __future__ import annotations

import numpy as np


def surface_gap(skin: np.ndarray, triangles: np.ndarray, points: np.ndarray) -> np.ndarray:
    """Distance from each point to the nearest point on any skin triangle.

    Direction-free on purpose: a brow's tail wraps around the temple, where a
    ray along the face axis grazes past the local surface and overstates the
    distance. The nearest-point distance is what "rides the ridge" means.
    """
    v0, v1, v2 = skin[triangles[:, 0]], skin[triangles[:, 1]], skin[triangles[:, 2]]
    e1, e2 = v1 - v0, v2 - v0
    uu, vv, ww = (e1 * e1).sum(axis=1), (e2 * e2).sum(axis=1), (e1 * e2).sum(axis=1)
    denom = uu * vv - ww * ww
    denom = np.where(np.abs(denom) < 1e-18, 1e-18, denom)
    out = np.empty(len(points))
    for index, point in enumerate(points):
        w = point - v0
        wu, wv = (w * e1).sum(axis=1), (w * e2).sum(axis=1)
        s = np.clip((vv * wu - ww * wv) / denom, 0.0, 1.0)
        t = np.clip((uu * wv - ww * wu) / denom, 0.0, 1.0)
        over = s + t > 1.0
        if over.any():
            s = np.where(over, np.clip(s, 0.0, 1.0), s)
            t = np.where(over, np.clip(t, 0.0, 1.0 - s), t)
        closest = v0 + s[:, None] * e1 + t[:, None] * e2
        out[index] = np.linalg.norm(closest - point, axis=1).min()
    return out


def mirror(points: np.ndarray) -> np.ndarray:
    out = points.copy()
    out[:, 0] *= -1.0
    return out


def residuals(points: np.ndarray, against: np.ndarray) -> np.ndarray:
    """Per-point distance to the nearest point of `against`."""
    return np.linalg.norm(points[:, None, :] - against[None, :, :], axis=2).min(axis=1)


def mirror_residuals(positions: np.ndarray) -> np.ndarray:
    left, right = positions[positions[:, 0] < 0], positions[positions[:, 0] > 0]
    if not len(left) or not len(right):
        raise ValueError("brow positions are one-sided; mirror residuals are undefined")
    return field_residuals(left, right)


def field_residuals(left: np.ndarray, right: np.ndarray) -> np.ndarray:
    """Per-vertex distance to the nearest mirrored counterpart on the other side."""
    return np.concatenate([
        residuals(left, mirror(right)),
        residuals(right, mirror(left)),
    ])


def arch_profile(positions: np.ndarray, bands=(("inner", 0.0, 1 / 3), ("mid", 1 / 3, 2 / 3), ("outer", 2 / 3, 1.01))) -> dict:
    """Each side's centre-line height per third of the brow, in the vertex's own units."""
    out = {}
    for name, points in (("L", positions[positions[:, 0] < 0]), ("R", positions[positions[:, 0] > 0])):
        xs = np.abs(points[:, 0])
        lo, hi = float(xs.min()), float(xs.max())
        for label, a, b in bands:
            sel = points[(xs >= lo + (hi - lo) * a) & (xs < lo + (hi - lo) * b)]
            out[(name, label)] = float(sel[:, 1].mean()) if len(sel) else float("nan")
    return out
