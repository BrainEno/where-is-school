"""Final local rest-space strokes for N and the seated student.

As in forms.py, the fields work in metres with +Z toward the face. Move
fitted features with their backing mesh, not with the classroom pose.
"""
from __future__ import annotations

import numpy as np

from forms import bump, ease, oval, unit_rows


def n_bob(p):
    """A tipped part and a tucked ear-side hem, leaving the crown alone."""
    x, y, z = p.T
    q = p.copy()
    below_crown = ease(1.632, 1.595, y)
    fore = ease(.018, .079, z)
    # Make the edge turn down onto the temples rather than jutting forward
    # like a visor. One side of the part falls more softly into the brow.
    fringe = fore * ease(1.626, 1.576, y) * ease(1.533, 1.568, y)
    part = x + .22*(y - 1.597) - .18*(z - .070)
    q[:, 2] -= fringe*(.0032 + .0018*bump(part, .027, .018))
    q[:, 1] += fringe*(.0046*bump(part, .021, .034) - .0077*bump(part, -.034, .028))

    tuck = oval(x, y, .075, 1.514, .047, .074)*ease(-.065, .021, z)
    q[:, 2] -= .0110*tuck
    q[:, 1] += .0082*tuck
    q[:, 0] -= np.sign(x)*.0042*tuck
    # Turn the lower plane toward the jaw, including the darker and lighter
    # lock surfaces. A shared field keeps their joins in the same place.
    hem = ease(1.511, 1.441, y)*ease(.043, .074, abs(x))*below_crown
    q[:, 0] -= np.sign(x)*.0038*hem
    q[:, 1] += .0029*hem
    return q


def n_face(p):
    """Open the lids a little and soften the hard centre of the narrow face."""
    x, y, z = p.T
    ax = abs(x)
    q = p.copy()
    eye = np.where(x < 0., 1.5323, 1.5298)
    dy = y - eye
    faceward = ease(.039, .081, z)
    # Includes the whole aperture, the lash and the six eyeball surfaces.
    # The off-centre origins retain the original difference between eyes.
    orbit = oval(ax, dy, .0315, 0., .028, .024)*ease(.053, .076, z)
    q[:, 1] += orbit*(.45*dy + .00025)
    bridge = oval(x, y, -.002, 1.514, .016, .041)
    nasal_plane = oval(abs(x + .002), y, .008, 1.523, .008, .023)
    cheek = oval(ax, y, .047, 1.494, .027, .040)
    lip = oval(x, y, 0., 1.448, .035, .014)
    q[:, 2] += faceward*(-.0043*bridge + .0018*nasal_plane + .0025*cheek - .0016*lip)
    chin = oval(x, y, 0., 1.433, .048, .020)*faceward*ease(1.419, 1.433, y)
    q[:, 1] += .0017*chin
    return q


def n_brow(p):
    x, y, z = p.T
    q = p.copy()
    u = ease(.010, .061, abs(x))
    q[:, 1] -= .0024*np.sin(u*np.pi)**1.5 + .0011*u
    return q


def student_crop(p):
    """Fold the student's forelock back into its short side-swept crown."""
    x, y, z = p.T
    ax = abs(x)
    q = p.copy()
    fore = ease(.033, .102, z)
    fringe = fore*ease(1.591, 1.648, y)*ease(1.743, 1.703, y)
    flow = x + .23*(z - .072) - .20*(y - 1.671)
    part = bump(flow, -.026, .013)
    # One unbroken sweep rather than five equal teeth. Keep the asymmetric
    # part but leave more face beneath the heavier side of the fringe.
    q[:, 2] -= fringe*(.0070 + .0030*bump(flow, -.018, .048) + .0013*part)
    tip = fore*ease(1.715, 1.64, y)
    q[:, 1] += tip*(.0100*bump(flow, -.026, .045) - .0020*bump(flow, .045, .030))
    q[:, 0] += .0045*tip*bump(flow, -.034, .046)
    # Keep the side alongside the ear compact, without moving that ear or
    # leaving a second, separate rim below the cropped cap.
    temple = ease(.065, .100, ax)*ease(1.687, 1.570, y)*ease(-.062, .035, z)
    q[:, 0] -= np.sign(x)*.0046*temple
    q[:, 1] += .0062*temple
    q[:, 2] -= .0036*temple
    return q


def student_hair_clearance(p, depth):
    """Seat the front of the cap just off the scalp, with a returning hem."""
    x, y, z = p.T
    q = p.copy()
    # Feather the fit across one asymmetric sweep, not along the boundaries
    # of the individual locks. Let the underside of the cap stay buried.
    line = 1.628 + .010*np.tanh((x+.007)/.031) - .006*bump(x, -.043, .030)
    line += .0075*ease(.057, .088, abs(x))
    room = .0032 - .014*ease(line+.009, line-.012, y)
    weight = ease(.034, .064, z)*ease(.092, .078, abs(x))
    missing = room - (z - depth)
    q[:, 2] += weight*np.maximum(missing, 0.)
    return q


def student_nape(p):
    """Turn the short nape under the cap instead of leaving a second bulge."""
    x, y, z = p.T
    q = p.copy()
    back = ease(-.033, -.103, z)
    q[:, 2] += .0060*back*(.40 + .60*ease(1.546, 1.650, y))
    q[:, 1] += .0060*back*ease(1.625, 1.505, y)
    return q


def student_lock(p, side_lock):
    """Tuck the separate painted streaks into the cap instead of hanging tips."""
    x, y, z = p.T
    radial = unit_rows(p-np.array([0., 1.617, -.018]))
    q = p.copy()
    if side_lock:
        q -= radial*(.0032 + .0016*ease(1.633, 1.585, y))[:, None]
        q[:, 2] -= .0027*ease(1.641, 1.596, y)
        q[:, 1] += .0030*ease(1.638, 1.593, y)
    else:
        q -= radial*(.0036 + .0026*ease(1.682, 1.638, y))[:, None]
        q[:, 1] += .0053*ease(1.711, 1.636, y)
    return q


def student_face(p):
    """Keep his cut-out eyes seated; roll the cheek into a quiet lower face."""
    x, y, z = p.T
    ax = abs(x)
    q = p.copy()
    orbit_y = np.where(x < 0., 1.5811, 1.5797)
    safe = 1. - ease(1.25, .86, ((ax-.044)/.028)**2 + ((y-orbit_y)/.017)**2)
    faceward = ease(.048, .092, z)*safe
    pad = oval(ax, y, .058, 1.546, .033, .025)
    jaw = oval(ax, y, .064, 1.473, .038, .046)*ease(1.429, 1.455, y)
    q[:, 0] -= np.sign(x)*.0046*jaw*ease(.011, .079, z)
    lips = .0027*oval(x, y, 0., 1.4835, .025, .011)
    lips += .0016*oval(x, y, -.002, 1.494, .027, .010)
    lips -= .0011*oval(x, y, .001, 1.489, .023, .004)
    q[:, 2] += faceward*(-.0027*pad + .0018*jaw + lips)
    q[:, 1] -= .0015*faceward*oval(ax, y, .019, 1.490, .012, .009)
    return q


def student_brow(p):
    x, y, z = p.T
    q = p.copy()
    outer = ease(.031, .068, abs(x))
    q[:, 1] -= .0010*bump(abs(x), .034, .017) + outer*np.where(x < 0., .0012, .0028)
    return q
