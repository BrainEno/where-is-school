"""Final B/Q-only rest-space brushes, layered over the integrated head studies.

These strokes leave the established scale, paint, hair indices and rig alone.
Coordinates are in metres with +Z towards the face.
"""
from __future__ import annotations

import numpy as np

from forms import LANDMARKS, bump, ease, hairline, oval, shell_relief, unit_rows


def q_cropped_fringe(azimuth):
    """A close-cropped fringe with an off-centre break and short temples."""
    a = np.arctan2(np.sin(azimuth), np.cos(azimuth))
    hem = hairline('q', a)
    # Short, slightly irregular fringe rather than a glossy cap or spikes.
    # The cut sits lower at the front and stays clear of both ears.
    front = ease(.51, .92, np.cos(a))
    ends = .014 * np.sin(20. * a + .5) + .008 * np.cos(31. * a - .9)
    hem += front * (.076 + .053 * bump(a, .35, .22) - .057 * bump(a, -.32, .12) + ends)
    hem -= .069 * bump(abs(a), 1.02, .177)
    return hem


def q_cropped_relief(rest, a, t):
    """Sweep the short crown forward into the fringe without layering plates."""
    depth, drift = shell_relief('q', rest, a, t)
    x, y, z = np.moveaxis(rest, -1, 0)
    front = ease(.038, .107, z)
    body = ease(.15, .47, t) * ease(1., .91, t)
    trace = x - .56 * (z - .074) + .22 * (y - 1.73)
    part = bump(trace, -.025, .011)
    lobe = .0030 * bump(trace, .020, .026)
    crest = .0016 * np.cos(188. * trace + .4) * ease(-.054, -.032, trace) * ease(.056, .024, trace)
    # Take bulk out of the forward ridge rather than raising the crown. The
    # tapered relief preserves enough clearance over the forehead.
    depth += body * (front * (lobe + crest - .0032 * part - .0036) - .0024 * (1. - front))
    depth = np.maximum(depth, .0019)
    drift += .0037 * front * body
    return depth, drift


def seat_q_orbit(p):
    """Move each eye with both its lid islands, keeping their relative fit."""
    q = p.copy()
    q[:, 1] += np.where(p[:, 0] < 0., .0014, .0007)
    q[:, 2] -= .0017
    return q


def q_cheek_and_mouth(p):
    """Keep the round cheeks and the uneven corner of his conversational smile."""
    x, y, z = p.T
    ax = abs(x)
    front = ease(.067, .100, z)
    q = p.copy()
    cheek = oval(ax, y, .049, 1.614, .034, .029)
    corner = oval(ax, y, .022, 1.575, .021, .018)
    chin = oval(x, y, 0., 1.546, .038, .023) * ease(1.533, 1.545, y)
    # The static cheek/temple blends into the outer lid shoulder. Stay off the
    # centre of the aperture, where added flesh would occlude the pupils.
    socket = oval(ax, y, .048, 1.668, .017, .017) * (1. - oval(ax, y, .033, 1.661, .016, .012))
    q[:, 2] += front * (.0021 * cheek + .0010 * corner - .0012 * chin) + .0031 * socket * ease(.079, .098, z)
    # A slight bias at rest; the existing Smirk key supplies the full lift.
    q[:, 1] += front * (.0006 + .0013 * ease(.010, -.018, x)) * corner
    return q


def q_brows(p):
    """One small lift, one soft tail; don't lay two identical bars over the eyes."""
    q = p.copy()
    x, y, _ = p.T
    arch = oval(abs(x), y, .032, 1.694, .033, .023)
    q[:, 1] += arch * np.where(x < 0., .0023, -.0008)
    q[:, 1] -= .0014 * ease(.040, .058, abs(x))
    return q


def b_chignon(p, peak):
    """A flatter temple, slanting side part and compact knot at the nape."""
    x, y, z = p.T
    _, _, ey, ze, _ = LANDMARKS['b']
    q = p.copy()
    root = np.array([0., ey + .012, ze - .066])
    radial = unit_rows(p - root)
    # The highest tips keep their height; taper the relief at the embedded hem.
    mid = ease(1.550, 1.593, y) * ease(peak, peak - .014, y)
    temple = ease(.028, .070, abs(x))
    fore = ease(ze - .104, ze - .030, z)
    flow = x + .028 - .30 * (z - .113) + .18 * (y - 1.605)
    part = bump(flow, 0., .0085) * fore
    sweep = oval(x, y, .027, 1.609, .072, .052) * fore
    q += radial * (mid * (-.0039 * temple - .0037 * part + .0022 * sweep))[:, None]
    q[:, 0] += .0021 * mid * sweep
    # Lift the lower rim into the side part on the high side; the temples
    # still feed into the original sweep under the spectacles' arms.
    hem = oval(x, y, .028, 1.586, .085, .025) * ease(.123, .165, z)
    q[:, 1] += .0044 * hem
    # Follow the existing twist into the head rather than pulling the bun away.
    knot = ease(.043, -.011, z) * ease(1.560, 1.494, y)
    q[:, 0] -= .060 * (x - .008) * knot
    q[:, 2] += .0038 * knot
    return q


def b_cheek_and_mouth(p):
    """Retain the teacher's age planes without over-cutting the hollow cheeks."""
    x, y, z = p.T
    ax = abs(x)
    q = p.copy()
    front = ease(.121, .168, z)
    hollow = oval(ax, y, .051, 1.476, .031, .034)
    chin = oval(x, y, .002, 1.420, .036, .019)
    tip = oval(x, y, .001, 1.482, .017, .017)
    mouth = oval(ax, y, .022, 1.447, .020, .014)
    q[:, 2] += front * (.0033 * hollow - .0019 * chin - .0020 * tip + .0011 * mouth)
    q[:, 1] += front * mouth * (.0016 * ease(-.017, .019, x) - .0008)
    return q


def b_brows_and_folds(p):
    """Lower the high arch, especially the long outer half above the frames."""
    x, y, _ = p.T
    q = p.copy()
    brow = ease(1.542, 1.553, y)
    q[:, 1] -= .36 * np.maximum(0., y - 1.546) * brow
    q[:, 1] += .0014 * brow * ease(-.017, .023, x)
    # Soften the marked outer folds without deleting them.
    q[:, 2] -= .00022 * (1. - ease(1.530, 1.540, y))
    return q
