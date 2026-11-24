"""Q's eye proportions under docs/CHARACTER_MODEL_STANDARD.md section 1.

Q's eyes are small and set wide: each sclera is about 25 mm across and the inner gap is
almost twice an eye width. The fix is a smooth warp about each eye centre, applied
identically to the eyeballs and to the surrounding skin (lids included), so the lids
open with the eye and no piece detaches. The warp is a pure function of position, so
any two points that meet keep meeting after it.

Hair is untouched: the hair shell is fitted to the skull before this polish step.
"""
from __future__ import annotations

import numpy as np

from refine_bq import seat_q_orbit

# Widen factors for x (across) and y (height), a full-weight core radius, and the radius
# where the warp dies out. Measured on the approved basis: eye width 0.025 m, centres at
# x = +/-0.034 m. Targets: eye width / face width 0.18-0.22; inner gap / eye width 0.85-1.15.
KX, KY = 1.44, 1.08
R_CORE, R_FADE = .015, .030


def eye_centres(sclera):
    """Centres of the two eyes after the approved seat, from the sclera points."""
    seated = seat_q_orbit(sclera)
    return {sign: seated[np.sign(seated[:, 0]) == sign].mean(axis=0)
            for sign in (-1., 1.)}


def warp(points, centres):
    """Widen each eye about its centre in x and y; z is never changed."""
    out = points.copy()
    for centre in centres.values():
        d = points[:, :2] - centre[:2]
        r = np.hypot(d[:, 0], d[:, 1])
        t = np.clip((r - R_CORE) / (R_FADE - R_CORE), 0., 1.)
        w = np.where(t < 1., .5 + .5 * np.cos(np.pi * t), 0.)
        w = np.where(r <= R_CORE, 1., w)
        out[:, 0] += d[:, 0] * (KX - 1.) * w
        out[:, 1] += d[:, 1] * (KY - 1.) * w
    return out
