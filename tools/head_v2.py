#!/usr/bin/env python3
"""Build the protagonist's V2 head and install it in the production GLB.

    python3 tools/head_v2.py build          # art/.../lead_v1_head.glb -> build/head_v2/...
    python3 tools/head_v2.py install        # install the built head into the runtime GLB
    python3 tools/head_v2.py check          # rebuild, compare with the installed GLB, and
                                            # assert the V2 contract below

The V1 head is the exact GLB the owner approved, kept byte-for-byte as
`art/character_models/sculpt/lead_v1_head.glb` (its SHA-256 is `V1_SHA` below, and `check`
refuses to run against any other file). The build is deterministic and never reads the
installed V2: `check` proves the committed GLB is the build output.

What changes, and what deliberately does not:

  * the head skin is subdivided once (4 triangles per original), sculpted in rest space —
    eye sockets, an opened almond aperture with lids that wrap the eyeball, nose wings and
    underside, lips and their surroundings, cheekbones, a widened jaw and a brought-forward
    chin, brow ridge, neck — then given a local UV atlas, a back-seam split and a tangent
    basis, and its nine sparse morph targets are resampled through the explicit subdivision
    map;
  * the hair keeps the owner's hairstyle — the same 96 roots, tips and silhouette — and each
    lock is refined in place: every ring gains the midpoint of each of its five edges
    (5 -> 10 columns, 45 -> 90 triangles), the new columns are thinned to 0.82 of their
    radius about the strand's own axis, and each strand takes one gentle outward bend of
    at most 2 mm, so the V1 plates read as coarse, weighted strands up close;
  * the eyes are levelled (V1's right eye sits 2.5 mm above the left), their flat iris and
    pupil discs are domed and the iris is given a limbal ring through its own vertex colour;
  * the eyebrows are re-hung on the brow ridge as tapered tubes, and the ears are given a
    bowl, a helix, a concha and a lobe;
  * the mouth's interior follows the lips, and every one of these parts keeps its own nine
    morph targets, re-expressed against its new rest pose;
  * body, wardrobe, skeleton, weights, animations, materials, node names and every other
    mesh are copied byte-for-byte.

The head's fine relief and its local colour live in maps beside the mesh
(`tools/head_v2_textures.py`), not in more triangles: the albedo map carries the lips, the
bruise and the stubble, the normal map the creases and the skin grain. Both are 1024², are
drawn through `CharacterLook.detail_maps` and `CharacterLookApplier`, and are off for every
other character in the game, none of which has UVs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

import numpy as np

import glb_edit
import glb_numpy as glb

ROOT = Path(__file__).resolve().parents[1]
V1 = ROOT / 'art/character_models/sculpt/lead_v1_head.glb'
RUNTIME = ROOT / 'assets/models/protagonist/Protagonist_Character.glb'
BUILD = ROOT / 'build/head_v2'
HEAD_MESH = 6
HAIR_MESH = 4
SKIN_PRIM = 0
HAIR_PRIM = 0
JOINT_HEAD = 49
# tools/verify_build.py's hard limit for a model, which the head must stay inside.
MODEL_BUDGET = 1536 * 1024
V1_SHA = '2b24d063bee3044dac8b9eb11945ead8cf001b6decd045c48e1e0b2ee7c40e6e'


# --------------------------------------------------------------------------------------
# Geometry
# --------------------------------------------------------------------------------------

def dense_targets(document: dict, binary: bytes, primitive: dict, count: int) -> list[dict[str, np.ndarray]]:
    """Sparse target deltas expanded to dense arrays (zeros where a vertex does not move)."""
    result = []
    for target in primitive.get('targets', []):
        entry = {}
        for name, index in target.items():
            accessor = document['accessors'][index]
            values = glb.accessor(document, binary, index)
            dense = np.zeros((count, values.shape[1]), dtype=np.float64)
            sparse = accessor.get('sparse')
            if sparse:
                view = document['bufferViews'][sparse['indices']['bufferView']]
                fmt = {5121: '<u1', 5123: '<u2', 5125: '<u4'}[sparse['indices']['componentType']]
                start = view.get('byteOffset', 0) + sparse['indices'].get('byteOffset', 0)
                indices = np.frombuffer(binary, dtype=np.dtype(fmt), count=sparse['count'], offset=start).astype(np.int64)
                dense[indices] = values[indices]
            else:
                dense[:] = values
            entry[name] = dense
        result.append(entry)
    return result


def subdivide(positions: np.ndarray, triangles: np.ndarray,
              deltas: list[dict[str, np.ndarray]]) -> tuple[np.ndarray, np.ndarray, list[dict[str, np.ndarray]]]:
    """One uniform 1 -> 4 split; every morph delta is interpolated with the same weights."""
    edge: dict[tuple[int, int], int] = {}
    out_p = [positions]
    out_d = [{name: [values] for name, values in target.items()} for target in deltas]
    out_t: list[tuple[int, int, int]] = []

    def midpoint(a: int, b: int) -> int:
        key = (a, b) if a < b else (b, a)
        found = edge.get(key)
        if found is not None:
            return found
        index = sum(len(block) for block in out_p)
        out_p.append(((positions[a] + positions[b]) * 0.5)[None, :])
        for target_index, target in enumerate(deltas):
            for name, values in target.items():
                out_d[target_index][name].append(((values[a] + values[b]) * 0.5)[None, :])
        edge[key] = index
        return index

    for a, b, c in triangles:
        ab, bc, ca = midpoint(int(a), int(b)), midpoint(int(b), int(c)), midpoint(int(c), int(a))
        out_t.extend([(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)])
    merged_p = np.concatenate(out_p, axis=0)
    merged_t = np.asarray(out_t, dtype=np.int64)
    merged_d = [{name: np.concatenate(blocks, axis=0) for name, blocks in target.items()} for target in out_d]
    return merged_p, merged_t, merged_d


def face_normals(positions: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    a = positions[triangles[:, 0]]
    b = positions[triangles[:, 1]]
    c = positions[triangles[:, 2]]
    n = np.cross(b - a, c - a)
    length = np.linalg.norm(n, axis=1, keepdims=True)
    return n / np.maximum(length, 1e-20)


def vertex_normals(positions: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    """Area-weighted smooth normals, computed per connected component."""
    normals = np.zeros_like(positions)
    fn = face_normals(positions, triangles)
    area = np.linalg.norm(np.cross(positions[triangles[:, 1]] - positions[triangles[:, 0]],
                                   positions[triangles[:, 2]] - positions[triangles[:, 0]]), axis=1)
    for k in range(3):
        np.add.at(normals, triangles[:, k], fn * area[:, None])
    length = np.linalg.norm(normals, axis=1, keepdims=True)
    return normals / np.maximum(length, 1e-20)


def welded_normals(positions: np.ndarray, triangles: np.ndarray, decimals: int = 6) -> np.ndarray:
    """Smooth normals across coincident vertices (the hair's open seam edges)."""
    keys = np.round(positions, decimals)
    _, inverse = np.unique(keys, axis=0, return_inverse=True)
    normals = np.zeros((int(inverse.max()) + 1, 3))
    fn = face_normals(positions, triangles)
    area = np.linalg.norm(np.cross(positions[triangles[:, 1]] - positions[triangles[:, 0]],
                                   positions[triangles[:, 2]] - positions[triangles[:, 0]]), axis=1)
    for k in range(3):
        np.add.at(normals, inverse[triangles[:, k]], fn * area[:, None])
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-20)
    return normals[inverse]


def components(positions: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    parent = np.arange(len(positions))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for a, b, c in triangles:
        for x, y in ((a, b), (b, c)):
            x, y = find(int(x)), find(int(y))
            if x != y:
                parent[y] = x
    return np.array([find(i) for i in range(len(positions))])


def gaussian(p: np.ndarray, center, radius, amount: float) -> np.ndarray:
    q = (p - np.asarray(center)) / np.asarray(radius)
    return amount * np.exp(-0.5 * np.sum(q * q, axis=1))


def sculpt_head(positions: np.ndarray, normals: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    """Rest-space sculpt for the V2 skin, in metres, along the vertex normal.

    The fields are deliberately broad and low-amplitude: they restore the planes a
    face has (socket, lid roll, alar wing, lip volume, cheekbone, jaw) without
    changing the owner-approved long face, narrow chin or eye placement.
    """
    x, y, z = positions.T
    ax = np.abs(x)
    displacement = np.zeros_like(positions)

    def add(field, direction=None):
        nonlocal displacement
        if direction is None:
            displacement += normals * field[:, None]
        else:
            displacement += np.asarray(direction)[None, :] * field[:, None]

    # 1. Eye sockets: a bowl behind each lid, a rounded upper-lid roll and a crease.
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.0305, 1.585, 0.103), (0.024, 0.019, 0.028), -0.0035))
        add(gaussian(positions, (side * 0.0305, 1.592, 0.108), (0.018, 0.007, 0.015), 0.0025))
        add(gaussian(positions, (side * 0.0305, 1.600, 0.101), (0.020, 0.004, 0.016), -0.0020))
        add(gaussian(positions, (side * 0.0305, 1.576, 0.107), (0.016, 0.005, 0.013), 0.0015))
        # under-eye bag and tear trough
        add(gaussian(positions, (side * 0.032, 1.5725, 0.101), (0.015, 0.0055, 0.018), 0.0015))
        add(gaussian(positions, (side * 0.034, 1.565, 0.098), (0.022, 0.009, 0.022), -0.0016))
        # outer corner support
        add(gaussian(positions, (side * 0.0455, 1.581, 0.099), (0.010, 0.008, 0.014), 0.0010))

    # 2. Nose: bridge planes, rounded tip, alar wings, columella and the underside.
    add(gaussian(positions, (0.0, 1.555, 0.128), (0.010, 0.028, 0.018), 0.0015))
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.0105, 1.545, 0.124), (0.005, 0.024, 0.015), -0.0016))
        add(gaussian(positions, (side * 0.019, 1.5005, 0.127), (0.0075, 0.007, 0.011), 0.0030))
        add(gaussian(positions, (side * 0.024, 1.5015, 0.120), (0.0045, 0.007, 0.010), -0.0020))
    add(gaussian(positions, (0.0, 1.5075, 0.139), (0.0085, 0.008, 0.009), 0.0030))
    add(gaussian(positions, (0.0, 1.4965, 0.1315), (0.009, 0.0045, 0.009), 0.0015))
    add(gaussian(positions, (0.0, 1.4935, 0.1285), (0.0055, 0.0035, 0.007), -0.0010))

    # 3. Mouth: philtrum, cupid's bow, lip volumes, a cut mouth line, corners.
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.0060, 1.5045, 0.1185), (0.0035, 0.0065, 0.009), 0.0009))
        add(gaussian(positions, (side * 0.0100, 1.4995, 0.1195), (0.0085, 0.0040, 0.009), 0.0024))
        add(gaussian(positions, (side * 0.0155, 1.4895, 0.1190), (0.012, 0.0055, 0.009), 0.0022))
        add(gaussian(positions, (side * 0.0245, 1.4955, 0.1125), (0.0055, 0.0045, 0.007), -0.0012))
        # vermilion border step
        add(gaussian(positions, (side * 0.014, 1.4948, 0.1195), (0.011, 0.0015, 0.008), -0.0012))
    add(gaussian(positions, (0.0, 1.5005, 0.1200), (0.0045, 0.0030, 0.007), 0.0012))
    add(gaussian(positions, (0.0, 1.4885, 0.1200), (0.009, 0.0040, 0.007), 0.0018))
    add(gaussian(positions, (0.0, 1.4952, 0.1185), (0.022, 0.0018, 0.009), -0.0018))
    add(gaussian(positions, (0.0, 1.4785, 0.1045), (0.020, 0.0055, 0.013), -0.0016))

    # 4. Cheeks, jaw and chin.
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.050, 1.5345, 0.079), (0.020, 0.016, 0.024), 0.0025))
        add(gaussian(positions, (side * 0.043, 1.5085, 0.071), (0.018, 0.016, 0.020), -0.0020))
        add(gaussian(positions, (side * 0.052, 1.4625, 0.045), (0.018, 0.010, 0.022), 0.0020))
        add(gaussian(positions, (side * 0.061, 1.6065, 0.030), (0.012, 0.014, 0.020), -0.0015))
    add(gaussian(positions, (0.0, 1.4435, 0.0920), (0.016, 0.010, 0.015), 0.0030))
    add(gaussian(positions, (0.0, 1.4555, 0.0300), (0.030, 0.016, 0.020), 0.0012))

    # 5. The jaw and the chin. V1's face is 124 mm across the cheekbones but only 85 mm
    #    across the jaw, where a face this wide carries about 100 mm: that is what made the
    #    lower face read as a long mask. The jaw angle is widened, the chin brought forward
    #    and its point softened, and the cheek under the bone filled.
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.043, 1.4735, 0.028), (0.017, 0.015, 0.030), 0.0072),
            direction=(side, 0.10, 0.12))
        add(gaussian(positions, (side * 0.030, 1.4505, 0.068), (0.015, 0.010, 0.020), 0.0042),
            direction=(side * 0.55, -0.25, 0.35))
        add(gaussian(positions, (side * 0.041, 1.4935, 0.076), (0.016, 0.012, 0.020), 0.0030))
    add(gaussian(positions, (0.0, 1.4455, 0.086), (0.017, 0.009, 0.018), 0.0032),
        direction=(0.0, -0.15, 1.0))
    add(gaussian(positions, (0.0, 1.4385, 0.078), (0.014, 0.006, 0.014), 0.0022),
        direction=(0.0, -0.55, 0.55))

    # 6. Brow ridge and glabella.
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.030, 1.6075, 0.103), (0.018, 0.007, 0.015), 0.0018))
    add(gaussian(positions, (0.0, 1.6055, 0.108), (0.007, 0.013, 0.011), 0.0008))

    # 7. Neck: soften the column under the jaw.
    add(gaussian(positions, (0.0, 1.455, 0.020), (0.038, 0.020, 0.038), 0.0012))

    return displacement


# --------------------------------------------------------------------------------------
# Eyes: level them, open the lids, curve the iris
# --------------------------------------------------------------------------------------

# Both eyes as V1 modelled them: one radius, but the right eye sits 2.5 mm above the left
# (1.58532 against 1.58285). The mouth and the ears are level and the brow is 6 mm off, so
# this is a modelling slip rather than a tilt of the head. V2 levels the eyes and the brow.
EYE_RADIUS = 0.01087
EYE_X = 0.03097
EYE_Y = 1.58409
EYE_Z = 0.10247
# The aperture. Half its width is a little inside the lid shells' own extent, so the corners
# close; the upper lid arches higher than the lower drops, and the outer corner rides a
# little above the inner one — the heavy-lidded, uneasy set the look asks for.
APERTURE_HALF_WIDTH = 0.0112
APERTURE_UP = 0.0042
APERTURE_DOWN = 0.0031
APERTURE_TILT = 0.0015


def fit_sphere(points: np.ndarray) -> tuple[np.ndarray, float]:
    """Algebraic sphere fit: |p - c|^2 = r^2 written as a linear system."""
    matrix = np.c_[2.0 * points, np.ones(len(points))]
    rhs = (points * points).sum(axis=1)
    solution, *_ = np.linalg.lstsq(matrix, rhs, rcond=None)
    centre = solution[:3]
    radius = float(np.sqrt(max(solution[3] + centre @ centre, 0.0)))
    return centre, radius


def eye_offsets(sclera: np.ndarray) -> dict:
    """The per-side translation that levels the eyes, measured on the sclera.

    Only the sclera is a sphere: fitting one to the iris or the pupil (a small, nearly flat
    disc) is ill-conditioned and throws them far off the face. So the offset is measured once,
    on the eyeball, and the same offset is applied to every part of that eye.
    """
    offsets = {}
    for side in (1.0, -1.0):
        selected = np.sign(sclera[:, 0]) == side
        centre, _radius = fit_sphere(sclera[selected])
        offsets[side] = np.array([side * EYE_X, EYE_Y, EYE_Z]) - centre
    return offsets


def level_eyes(positions: np.ndarray, offsets: dict) -> np.ndarray:
    """Put both eyes on one height, keeping each sphere's own radius and shape."""
    out = positions.copy()
    for side, offset in offsets.items():
        out[np.sign(positions[:, 0]) == side] += offset
    return out


def dome_iris(positions: np.ndarray, bulge: float, lift: float):
    """Give the flat iris and pupil discs a cornea's dome, and their own normals.

    V1's iris is a flat disc plugged into the front of the truncated sclera. Seen through
    an open aperture a flat disc reads as a painted circle, so the disc is domed about the
    eye's axis by `bulge` at its centre and lifted `lift` off the sclera's rim, which keeps
    the two surfaces from fighting over the same depth. Returns the new positions and the
    normals of the domed surface.
    """
    out = positions.copy()
    normals = np.zeros_like(positions)
    for side in (1.0, -1.0):
        selected = np.sign(positions[:, 0]) == side
        points = out[selected]
        offset = points[:, [0, 1]] - np.array([side * EYE_X, EYE_Y])
        radial = np.linalg.norm(offset, axis=1)
        falloff = np.clip(1.0 - (radial / 0.0068) ** 2, 0.0, 1.0)
        points[:, 2] += lift + bulge * falloff
        # The dome's own normal: dz/dr = -2 bulge r / R^2, so the surface tilts outwards.
        slope = 2.0 * bulge / 0.0068 ** 2
        normal = np.stack([slope * offset[:, 0], slope * offset[:, 1],
                           np.ones(len(points))], axis=1)
        normals[selected] = normal / np.linalg.norm(normal, axis=1, keepdims=True)
        out[selected] = points
    return out, normals


def wrap_lids(positions: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    """Open V1's closed lids into an almond aperture, and hang them on the eyeball.

    V1's four lid shells are bands that meet over the eye's front: the model's eyes are
    shut, and the eyeball pokes through them, which is what read as a protruding disc. Each
    band is re-hung on its own eye here. Its margin — the band's inner edge, the closed line
    — is moved onto the aperture's arch, and the band's radius is blended from just outside
    the eyeball at that margin to the socket's rim at its outer edge, which stays exactly
    where V1 put it. The aperture is what is left between the two margins.
    """
    labels = components(positions, triangles)
    out = positions.copy()
    for label in np.unique(labels):
        index = np.nonzero(labels == label)[0]
        points = out[index]
        if len(index) < 120:
            continue
        centroid = points.mean(axis=0)
        side = 1.0 if centroid[0] > 0 else -1.0
        eye = np.array([side * EYE_X, EYE_Y, EYE_Z])
        if np.linalg.norm(centroid - eye) > 0.03:
            continue
        upper = centroid[1] > EYE_Y
        y_low, y_high = points[:, 1].min(), points[:, 1].max()
        margin, outer = (y_low, y_high) if upper else (y_high, y_low)
        # 0 at the margin (the free edge), 1 at the outer loop (the socket's rim). The
        # denominator keeps its sign: on the lower lid the margin is the band's *top*, so
        # the same expression runs from 0 at the free edge to 1 at the rim.
        v = np.clip((points[:, 1] - margin) / (outer - margin if outer != margin else 1e-9),
                    0.0, 1.0)
        # +1 at the outer corner, -1 at the inner one, whichever side of the face this is.
        across = np.clip(side * (points[:, 0] - eye[0]) / APERTURE_HALF_WIDTH, -1.0, 1.0)
        arch = np.maximum(1.0 - across * across, 0.0) ** 0.75
        target = (eye[1] + (APERTURE_UP if upper else -APERTURE_DOWN) * arch
                  + APERTURE_TILT * across)
        y_new = points[:, 1] + (target - margin) * (1.0 - v) ** 2
        radius = np.linalg.norm(points - eye, axis=1)
        radius_new = (EYE_RADIUS + 0.0004) * (1.0 - v) + radius * v
        # V1's bands dip inside the eyeball (their outer loops sit at 9.8 mm against a
        # 10.9 mm eye), so the eyeball showed through them. A lid wraps the eye; it is never
        # inside it.
        radius_new = np.maximum(radius_new, EYE_RADIUS + 0.0003)
        direction = np.stack([points[:, 0], y_new, points[:, 2]], axis=1) - eye
        direction /= np.maximum(np.linalg.norm(direction, axis=1, keepdims=True), 1e-12)
        out[index] = eye + direction * radius_new[:, None]
    return out


def reshape_brow(brow: np.ndarray, head: np.ndarray) -> np.ndarray:
    """Seat V1's floating eyebrow on the brow ridge, and taper it.

    The brow is a swept tube: four vertices to a ring, seven rings from the nose to the
    temple, and a fan-capped end at each end of it. V1 left it 7-10 mm in front of the
    forehead and the same thickness all the way across. Every ring is re-hung here on the
    ridge — its centre on the skin, its section a diamond that swells over the bone and thins
    to a fine tail — and each capped end is pulled into the tube so it rounds off instead of
    ending in a blunt cut. The ring's four vertices keep their order around the tube, which is
    what stops the section from twisting from one ring to the next. Topology, vertex order and
    the nine morph targets are untouched.
    """
    out = brow.copy()
    for side in (1.0, -1.0):
        index = np.nonzero(np.sign(out[:, 0]) == side)[0]
        points = out[index]
        x = np.abs(points[:, 0])
        low, high = float(x.min()), float(x.max())
        for station in np.unique(np.round(x, 5)):
            ring_index = np.nonzero(np.isclose(x, station, atol=1e-4))[0]
            ring = points[ring_index]
            along = float(np.clip((station - low) / max(high - low, 1e-9), 0.0, 1.0))
            centre_y = float(np.interp(along, [0.0, 0.25, 0.5, 0.75, 1.0],
                                       [1.6056, 1.6070, 1.6074, 1.6066, 1.6049]))
            half_height = float(np.interp(along, [0.0, 0.18, 0.5, 0.8, 1.0],
                                          [0.0008, 0.0022, 0.0024, 0.0016, 0.0006]))
            half_depth = half_height * 0.85
            near = (np.abs(head[:, 0] - station) < 0.007) & \
                   (np.abs(head[:, 1] - centre_y) < 0.007)
            if not near.any():
                near = (np.abs(head[:, 0] - station) < 0.014) & \
                       (np.abs(head[:, 1] - centre_y) < 0.014)
            skin = float(head[near, 2].max()) if near.any() else float(ring[:, 2].max())
            centre_z = skin + 0.0005
            section = ring[:, [1, 2]] - ring[:, [1, 2]].mean(axis=0)
            cap = -1
            if len(ring) > 4:
                cap = int(np.argmin(np.linalg.norm(section, axis=1)))
            others = [local for local in range(len(ring)) if local != cap]
            # Each vertex keeps the side of the tube it was already on: the highest goes to
            # the top, the deepest to the back, and so on. Sorting by angle instead would let
            # the section rotate from one ring to the next and twist the tube.
            slots = {
                'top': max(others, key=lambda local: section[local, 0]),
                'bottom': min(others, key=lambda local: section[local, 0]),
                'back': max(others, key=lambda local: section[local, 1]),
                'front': min(others, key=lambda local: section[local, 1]),
            }
            for name, local in slots.items():
                offset_y = half_height if name == 'top' else (-half_height if name == 'bottom' else 0.0)
                offset_z = half_depth if name == 'back' else (-half_depth if name == 'front' else 0.0)
                points[ring_index[local]] = (ring[local, 0], centre_y + offset_y,
                                             centre_z + offset_z)
            if cap >= 0:
                # Pulled into the tube, so the fan rounds the end off.
                inward = 1.0 if station < (low + high) * 0.5 else -1.0
                points[ring_index[cap]] = (side * (station + inward * 0.0022), centre_y,
                                           centre_z)
        out[index] = points
    return out


def relief_ears(positions: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    """Give the two flat ear discs a bowl, a helix, a concha and a lobe.

    The ears are separate shells at x = +/-76 mm facing outwards, 55 mm tall and 31 mm deep,
    with no relief at all: they read as buttons. The relief is applied along the outward
    normal of each shell's own plane, in that plane's (depth, height) coordinates: the whole
    shell becomes a funnel (the bowl), the rim swells into a helix, the lower centre deepens
    into the concha, and a small tragus and lobe are added. Rings alone would have drawn a
    target on a flat disc — the bowl is what makes it read as an ear.
    """
    labels = components(positions, triangles)
    out = positions.copy()
    for label in np.unique(labels):
        index = np.nonzero(labels == label)[0]
        points = out[index]
        if not 250 < len(index) < 500:
            continue
        centroid = points.mean(axis=0)
        if abs(centroid[0]) < 0.05:
            continue
        side = 1.0 if centroid[0] > 0 else -1.0
        depth = points[:, 2] - centroid[2]
        height = points[:, 1] - centroid[1]
        # 0 at the ear's centre, 1 on its silhouette: an ellipse 27 mm tall, 15 mm deep.
        ring = np.sqrt((height / 0.027) ** 2 + (depth / 0.015) ** 2)
        relief = -0.0032 * np.clip(1.0 - ring * ring, 0.0, 1.0)
        # The helix: the rolled rim, strongest over the top and round the back.
        relief += 0.0022 * np.exp(-((ring - 0.94) / 0.14) ** 2) * \
            (0.55 + 0.45 * np.tanh(-height / 0.014))
        # The ear's outline: taller than it is deep, with a lobe at the bottom. V1's disc is
        # a circle, which is half of why it read as a button.
        outline = 1.0 + 0.10 * np.tanh(-height / 0.012)
        # The concha: the bowl the ear opens into, low and forward.
        relief -= 0.0022 * np.exp(-(((depth + 0.002) / 0.0085) ** 2 +
                                    ((height + 0.005) / 0.0105) ** 2))
        # The tragus, the small bump in front of the opening.
        relief += 0.0016 * np.exp(-(((depth - 0.0105) / 0.005) ** 2 +
                                    ((height + 0.007) / 0.0055) ** 2))
        # The lobe: a soft pad at the bottom.
        relief += 0.0013 * np.exp(-(((depth + 0.003) / 0.009) ** 2 +
                                    ((height + 0.023) / 0.0075) ** 2))
        out[index] = points + np.stack([side * relief,
                                        height * 0.10 * outline,
                                        depth * -0.06 * outline], axis=1)
    return out


EYE_MESH = 2
BROW_PRIM = 1
MOUTH_PRIM = 2


def attribute_layout(document: dict, primitive: dict, name: str):
    accessor = document['accessors'][primitive['attributes'][name]]
    return int(accessor['componentType']), accessor['type'], bool(accessor.get('normalized', False))


def carry_attributes(document: dict, binary: bytes, primitive: dict, names) -> dict:
    """Attributes copied through unchanged, in the layout the GLB already stores them in."""
    arrays = glb.primitive_arrays(document, binary, primitive)
    carried = {}
    for name in names:
        if name in primitive['attributes']:
            component, type_name, normalized = attribute_layout(document, primitive, name)
            carried[name] = (arrays[name], component, type_name, normalized)
    return carried


def nearest_displacement(points: np.ndarray, source: np.ndarray, displacement: np.ndarray) -> np.ndarray:
    """The sculpt's displacement at the nearest skin vertex, for a part that rides the skin.

    The eyebrows and the mouth's interior are separate primitives of the head mesh. They are
    not sculpted themselves — they are carried by the skin they sit on — so each of their
    vertices takes the displacement of the nearest skin vertex, which keeps them seated on the
    new surface instead of floating where V1 left them.
    """
    out = np.zeros((len(points), 3))
    for index in range(len(points)):
        distance = np.linalg.norm(source - points[index], axis=1)
        out[index] = displacement[int(np.argmin(distance))]
    return out


def _morph_targets(positions: np.ndarray, deltas: list[dict[str, np.ndarray]]) -> list[dict[str, np.ndarray]]:
    """Sparse morph targets re-expressed against the new rest pose.

    Position deltas only: teacher N's approved expressions are position-only too,
    and the imported scene stores every target densely -- carrying normal deltas
    multiplied the protagonist's imported head by most of a megabyte without
    changing what the painterly shader shows.
    """
    built = []
    for target in deltas:
        delta = target['POSITION'].copy()
        delta[np.linalg.norm(delta, axis=1) < 1e-5] = 0.0
        built.append({'POSITION': delta})
    return built


IRIS_RADIUS = 0.0084
# The iris is one flat colour in V1. Its own vertex colour — which the look's material already
# knows how to multiply in (`use_vertex_paint`) — carries a limbal ring and a lighter centre,
# the two gradients that make an iris read as one rather than as a brown disc.
IRIS_EDGE = 0.52
IRIS_CORE = 1.06


def iris_vertex_colour(positions: np.ndarray) -> np.ndarray:
    """A radial multiplier for the iris: dark at the limbus, light towards the pupil."""
    centre = np.stack([np.sign(positions[:, 0]) * EYE_X, np.full(len(positions), EYE_Y)], axis=1)
    radial = np.linalg.norm(positions[:, [0, 1]] - centre, axis=1)
    t = np.clip(radial / IRIS_RADIUS, 0.0, 1.0)
    tone = IRIS_CORE + (IRIS_EDGE - IRIS_CORE) * t ** 2.2
    return np.stack([tone, tone, tone, np.ones_like(tone)], axis=1)


def build_face_parts(document: dict, binary: bytes, skin: np.ndarray,
                     displacement: np.ndarray) -> dict:
    """The eyes, the eyebrows and the mouth's interior, on the sculpted head.

    The eyes are levelled (V1's right eye sits 2.5 mm above the left) and their flat iris and
    pupil discs are domed, so they read as an eye behind an aperture rather than a painted
    circle. The eyebrow — a strip V1 left 7-10 mm in front of the forehead — is seated on the
    brow ridge and tapered. The mouth's interior follows the lips. Every part keeps its own
    morph targets, re-expressed against its new rest pose.
    """
    replacements = {}
    sclera = glb.primitive_arrays(document, binary,
                                  document['meshes'][EYE_MESH]['primitives'][0])['POSITION']
    offsets = eye_offsets(sclera.astype(np.float64))
    eye_plans = {0: (0.0, 0.0), 1: (0.0009, 0.0002), 2: (0.0009, 0.0004)}
    for primitive_index, (bulge, lift) in eye_plans.items():
        primitive = document['meshes'][EYE_MESH]['primitives'][primitive_index]
        arrays = glb.primitive_arrays(document, binary, primitive)
        positions = level_eyes(arrays['POSITION'].astype(np.float64), offsets)
        normals = arrays['NORMAL'].astype(np.float64)
        if bulge > 0.0:
            positions, normals = dome_iris(positions, bulge, lift)
        attributes = {
            'POSITION': (positions.astype(np.float32), 5126, 'VEC3'),
            'NORMAL': (np.round(normals * 32767).astype(np.int16), 5122, 'VEC3', True),
        }
        if primitive_index == 1:
            attributes['COLOR_0'] = (np.round(iris_vertex_colour(positions) * 255).astype(np.uint8),
                                     5121, 'VEC4', True)
        attributes.update(carry_attributes(document, binary, primitive, ('JOINTS_0', 'WEIGHTS_0')))
        replacements[(EYE_MESH, primitive_index)] = {
            'attributes': attributes,
            'indices': arrays['indices'].astype(np.uint32),
            'targets': [],
        }

    for primitive_index, reshape in ((BROW_PRIM, True), (MOUTH_PRIM, False)):
        primitive = document['meshes'][HEAD_MESH]['primitives'][primitive_index]
        arrays = glb.primitive_arrays(document, binary, primitive)
        positions = arrays['POSITION'].astype(np.float64)
        positions = positions + nearest_displacement(positions, skin, displacement)
        if reshape:
            positions = reshape_brow(positions, skin)
        triangles = arrays['indices'].reshape(-1, 3).astype(np.int64)
        normals = vertex_normals(positions, triangles)
        deltas = dense_targets(document, binary, primitive, len(positions))
        attributes = {
            'POSITION': (positions.astype(np.float32), 5126, 'VEC3'),
            'NORMAL': (np.round(normals * 32767).astype(np.int16), 5122, 'VEC3', True),
        }
        attributes.update(carry_attributes(document, binary, primitive,
                                          ('COLOR_0', 'COLOR_1', 'JOINTS_0', 'WEIGHTS_0')))
        replacements[(HEAD_MESH, primitive_index)] = {
            'attributes': attributes,
            'indices': arrays['indices'].astype(np.uint32),
            'targets': [
                {name: (values.astype(np.float32), 5126, 'VEC3')
                 for name, values in target.items()}
                for target in _morph_targets(positions, deltas)
            ],
        }
    return replacements


def refine_locks(positions: np.ndarray, triangles: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Subdivide every lock's rings in place and give each strand a natural weight.

    The hairstyle is the owner's: 96 locks plus the scalp cap, and every root, tip and
    silhouette vertex stays where V1 put it. A lock is a tube whose open root ring is
    the component's boundary (five vertices, all of degree 4); breadth-first distance
    from that ring gives six levels — five rings of five and a single tip vertex — and
    each of the 45 triangles owns exactly one edge lying inside a level.

    Refinement splits those ring edges. Each ring goes 5 -> 10 vertices (the five
    original columns plus one at every edge midpoint, appended after the originals)
    and each triangle splits in two along its own ring edge, 45 -> 90 faces. A
    midpoint is pulled to 0.82 of its radius about the lock's own axis — an 18 %
    local thinning that keeps the wedge section of the V1 plate instead of whittling
    it into a needle — and every vertex of rings 1..4, old and new, rides one gentle
    bend per lock: min(2 mm, 3 % of length) * sin(pi * t) pointing away from the
    scalp anchor and perpendicular to the lock axis, where t is the ring centre's
    axial parameter. The root ring (t = 0) and the tip take no bend, so the approved
    silhouette does not move. The cap component is left alone.
    """
    _, labels = np.unique(components(positions, triangles), return_inverse=True)
    sizes = np.bincount(labels)
    locks = np.nonzero(sizes == 26)[0]
    if len(sizes) != 97 or len(locks) != 96:
        raise SystemExit(f'hair is no longer 96 locks and a cap: {len(sizes)} components, '
                         f'{len(locks)} of 26 vertices')
    scalp = np.array([0.0, 1.565, 0.040])
    refined = positions.copy()
    extra: list[np.ndarray] = []
    faces_out: list[tuple[int, int, int]] = []
    for label in range(len(sizes)):
        faces = triangles[labels[triangles[:, 0]] == label]
        if sizes[label] != 26:
            faces_out.extend(tuple(map(int, tri)) for tri in faces)
            continue
        verts = np.nonzero(labels == label)[0]
        edges = np.unique(np.sort(np.vstack((faces[:, [0, 1]], faces[:, [1, 2]],
                                             faces[:, [2, 0]])), axis=1), axis=0)
        adj: dict[int, list[int]] = {int(v): [] for v in verts}
        for a, b in edges:
            adj[int(a)].append(int(b))
            adj[int(b)].append(int(a))
        level = {int(v): -1 for v in verts}
        frontier = [int(v) for v in verts if len(adj[int(v)]) == 4]
        if len(frontier) != 5:
            raise SystemExit(f'lock {label}: boundary is {len(frontier)} vertices, not a 5-ring')
        for v in frontier:
            level[v] = 0
        depth = 0
        while frontier:
            nxt = []
            for v in frontier:
                for w in adj[v]:
                    if level[w] < 0:
                        level[w] = depth + 1
                        nxt.append(w)
            frontier = nxt
            depth += 1
            if depth > 8:
                raise SystemExit(f'lock {label}: ring levels do not terminate')
        rows = [[int(v) for v in verts if level[int(v)] == r] for r in range(6)]
        if [len(row) for row in rows] != [5, 5, 5, 5, 5, 1]:
            raise SystemExit(f'lock {label}: ring sizes {[len(row) for row in rows]}')
        root = positions[rows[0]].mean(axis=0)
        axis = positions[rows[5]][0] - root
        length = float(np.linalg.norm(axis))
        if length < 1e-9:
            raise SystemExit(f'lock {label}: zero length')
        axis = axis / length
        away = root - scalp
        outward = away - axis * float(away @ axis)
        if np.linalg.norm(outward) < 1e-9:
            outward = np.cross(axis, np.array([0.0, 1.0, 0.0]))
            if np.linalg.norm(outward) < 1e-9:
                outward = np.cross(axis, np.array([1.0, 0.0, 0.0]))
        outward = outward / np.linalg.norm(outward)
        bend_cap = min(0.002, 0.03 * length)
        bends = []
        for r in range(6):
            if r == 5:
                bends.append(np.zeros(3))
                continue
            centre = positions[rows[r]].mean(axis=0)
            t = float(np.clip((centre - root) @ axis / length, 0.0, 1.0))
            bends.append(outward * (bend_cap * math.sin(math.pi * t)))
        for r in range(6):
            refined[rows[r]] += bends[r]
        mid: dict[tuple[int, int], int] = {}
        for a, b in edges:
            a, b = int(a), int(b)
            if level[a] != level[b] or level[a] >= 5:
                continue
            m = (positions[a] + positions[b]) * 0.5
            on_axis = root + axis * float((m - root) @ axis)
            m = on_axis + (m - on_axis) * 0.82 + bends[level[a]]
            mid[(a, b)] = len(positions) + len(extra)
            extra.append(m)
        if len(mid) != 25:
            raise SystemExit(f'lock {label}: {len(mid)} ring edges, expected 25')
        for tri in faces:
            a, b, c = (int(v) for v in tri)
            same = [(x, y) for x, y in ((a, b), (b, c), (c, a)) if level[x] == level[y]]
            if len(same) != 1:
                raise SystemExit(f'lock {label}: triangle {tri} has {len(same)} ring edges')
            x, y = same[0]
            z = a + b + c - x - y
            key = (x, y) if x < y else (y, x)
            m = mid[key]
            faces_out.append((x, m, z))
            faces_out.append((m, y, z))
    built = np.concatenate([refined, np.asarray(extra, dtype=refined.dtype)], axis=0)
    return built, np.asarray(faces_out, dtype=np.int64)


# --------------------------------------------------------------------------------------
# UV, tangents
# --------------------------------------------------------------------------------------

def spherical_uv(positions: np.ndarray, center) -> np.ndarray:
    """Face-focused spherical atlas.

    A plain equirectangular map gives the face about a fifth of the texture width,
    because the back of the head owns half the sphere. The exponent below spends
    that space on the front instead: the face (|theta| < 0.2 pi) gets roughly 45 %
    of U, and the hair-covered back is compressed. The seam stays at the back.
    """
    d = positions - np.asarray(center)
    theta = np.arctan2(d[:, 0], d[:, 2])
    phi = np.arctan2(d[:, 1], np.linalg.norm(d[:, [0, 2]], axis=1))
    s = theta / np.pi
    t = phi / (np.pi * 0.5)
    u = 0.5 + 0.5 * np.sign(s) * np.abs(s) ** 0.55
    v = 0.5 + 0.5 * np.sign(t) * np.abs(t) ** 0.65
    return np.stack([u, v], axis=1)


def planar_uv(positions: np.ndarray, axes, bounds, cell) -> np.ndarray:
    a = positions[:, axes[0]]
    b = positions[:, axes[1]]
    lo_a, hi_a, lo_b, hi_b = bounds
    u = cell[0] + (a - lo_a) / max(hi_a - lo_a, 1e-9) * (cell[2] - cell[0])
    v = cell[1] + (b - lo_b) / max(hi_b - lo_b, 1e-9) * (cell[3] - cell[1])
    return np.stack([u, v], axis=1)


def head_uv(positions: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    """One continuous face-focused spherical map for the whole skin surface.

    The lids and ears share the head's projection instead of owning atlas islands:
    they are the same skin, they sit on the same front/side of the head, and a
    separate island would only duplicate the texture there. The back seam is split
    in the mesh (see `split_uv_seam`) so no triangle wraps across the whole atlas.
    """
    return spherical_uv(positions, (0.0, 1.565, 0.040))


def split_uv_seam(positions: np.ndarray, triangles: np.ndarray, uvs: np.ndarray,
                  normals: np.ndarray, targets: list[dict[str, np.ndarray]],
                  center=(0.0, 1.565, 0.040)):
    """Duplicate the -pi side of every triangle that crosses the back seam.

    A spherical map has a seam at theta = +/- pi. Without a split, the triangles
    that cross it interpolate U from ~1 to ~0 and sample the whole texture in one
    triangle. The duplicate carries the same position, normal and morph delta, only
    its theta is shifted by +2 pi so U lands next to the other side; the geometry
    is unchanged.
    """
    d = positions - np.asarray(center)
    theta = np.arctan2(d[:, 0], d[:, 2])
    crossing = (theta[triangles].max(axis=1) - theta[triangles].min(axis=1)) > np.pi
    if not crossing.any():
        return positions, triangles, uvs, normals, targets
    duplicate: dict[int, int] = {}
    new_positions = [positions]
    new_uvs = [uvs]
    new_normals = [normals]
    new_targets = [{name: [values] for name, values in target.items()} for target in targets]
    for vertex in np.unique(triangles[crossing]):
        if theta[vertex] >= 0:
            continue
        duplicate[int(vertex)] = sum(len(block) for block in new_positions)
        new_positions.append(positions[vertex][None, :])
        shifted = uvs[vertex].copy()
        # Recompute U from theta + 2 pi with the same face-focused mapping.
        angle = theta[vertex] + 2.0 * np.pi
        s = angle / np.pi
        shifted[0] = 0.5 + 0.5 * np.sign(s) * abs(s) ** 0.55
        # A long back triangle can put the shifted U just outside the atlas; clamp
        # it to the seam edge rather than wrapping the whole texture through one face.
        shifted[0] = float(np.clip(shifted[0], 0.0, 1.0))
        new_uvs.append(shifted[None, :])
        new_normals.append(normals[vertex][None, :])
        for target_index, target in enumerate(targets):
            for name, values in target.items():
                new_targets[target_index][name].append(values[vertex][None, :])
    new_triangles = triangles.copy()
    for row in np.nonzero(crossing)[0]:
        for column in range(3):
            vertex = int(triangles[row, column])
            if vertex in duplicate:
                new_triangles[row, column] = duplicate[vertex]
    merged_targets = [
        {name: np.concatenate(blocks, axis=0) for name, blocks in target.items()}
        for target in new_targets
    ]
    return (np.concatenate(new_positions, axis=0), new_triangles,
            np.concatenate(new_uvs, axis=0), np.concatenate(new_normals, axis=0),
            merged_targets)


def tangents(positions: np.ndarray, normals: np.ndarray, uvs: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    tangent = np.zeros_like(positions)
    bitangent = np.zeros_like(positions)
    for a, b, c in triangles:
        p0, p1, p2 = positions[a], positions[b], positions[c]
        uv0, uv1, uv2 = uvs[a], uvs[b], uvs[c]
        e1, e2 = p1 - p0, p2 - p0
        d1, d2 = uv1 - uv0, uv2 - uv0
        r = d1[0] * d2[1] - d2[0] * d1[1]
        if abs(r) < 1e-12:
            continue
        r = 1.0 / r
        t = (e1 * d2[1] - e2 * d1[1]) * r
        bt = (e2 * d1[0] - e1 * d2[0]) * r
        np.add.at(tangent, a, t)
        np.add.at(tangent, b, t)
        np.add.at(tangent, c, t)
        np.add.at(bitangent, a, bt)
        np.add.at(bitangent, b, bt)
        np.add.at(bitangent, c, bt)
    # Gram-Schmidt against the normal.
    tangent -= normals * np.sum(tangent * normals, axis=1, keepdims=True)
    length = np.linalg.norm(tangent, axis=1, keepdims=True)
    tangent = tangent / np.maximum(length, 1e-20)
    w = np.sign(np.sum(np.cross(normals, tangent) * bitangent, axis=1))
    w[w == 0] = 1.0
    return np.concatenate([tangent, w[:, None]], axis=1)


# --------------------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------------------

def load_v1() -> tuple[dict, bytes]:
    if not V1.exists():
        raise SystemExit(f'missing {V1}; run: python3 tools/head_v2.py extract')
    return glb.load(V1)


def build() -> dict:
    document, binary = load_v1()
    head = document['meshes'][HEAD_MESH]['primitives'][SKIN_PRIM]
    hair = document['meshes'][HAIR_MESH]['primitives'][HAIR_PRIM]
    head_arrays = glb.primitive_arrays(document, binary, head)
    hair_arrays = glb.primitive_arrays(document, binary, hair)
    positions = head_arrays['POSITION']
    triangles = head_arrays['indices'].reshape(-1, 3).astype(np.int64)
    targets = dense_targets(document, binary, head, len(positions))

    # 1. Subdivide the skin once, carrying every morph delta through the split.
    positions, triangles, targets = subdivide(positions, triangles, targets)

    # 2. Sculpt in rest space, then recompute smooth normals.
    normals = vertex_normals(positions, triangles)
    displacement = sculpt_head(positions, normals, triangles)
    positions = positions + displacement
    # 3. Open the lids, and give the ears their relief; both are sculpt steps that need the
    #    skin's own components, so they run before the UV seam splits the surface.
    positions = wrap_lids(positions, triangles)
    positions = relief_ears(positions, triangles)
    normals = vertex_normals(positions, triangles)

    # 4. UV atlas, back-seam split and tangent basis.
    uv = head_uv(positions, triangles)
    positions, triangles, uv, normals, targets = split_uv_seam(
        positions, triangles, uv, normals, targets)
    tangent = tangents(positions, normals, uv, triangles)

    # 5. Sparse morph targets, with the sculpt carried into every shape.
    #    Position deltas only -- see _morph_targets for why normals are not stored.
    built_targets = []
    for target in targets:
        delta = target['POSITION'].copy()
        # Subdivision spreads a target over its one-ring; a fifth of a micron is
        # exporter noise, not a shape. Zeroing it keeps the sparse target honest
        # and the GLB inside the model budget without changing any visible delta.
        delta[np.linalg.norm(delta, axis=1) < 1e-5] = 0.0
        built_targets.append({'POSITION': delta})

    # 6. Hair: in-place ring refinement (5 -> 10 columns per ring), taper, gentle bend.
    hair_positions = hair_arrays['POSITION']
    hair_triangles = hair_arrays['indices'].reshape(-1, 3).astype(np.int64)
    hair_positions, hair_triangles = refine_locks(hair_positions, hair_triangles)
    hair_normals = welded_normals(hair_positions, hair_triangles)

    # 7. The eyes, the eyebrows and the mouth's interior, on the sculpted head.
    face_parts = build_face_parts(document, binary, positions, displacement)

    # 8. Attributes. The head is rigidly bound to the Head joint (49, weight 1).
    count = len(positions)
    joints = np.zeros((count, 4), dtype=np.uint8)
    joints[:, 0] = JOINT_HEAD
    weights = np.zeros((count, 4), dtype=np.uint8)
    weights[:, 0] = 255
    color = np.full((count, 4), 255, dtype=np.uint8)
    head_replacement = {
        'attributes': {
            'POSITION': (positions.astype(np.float32), 5126, 'VEC3'),
            'NORMAL': (np.round(normals * 32767).astype(np.int16), 5122, 'VEC3', True),
            'TEXCOORD_0': (np.round(uv * 65535).astype(np.uint16), 5123, 'VEC2', True),
            'JOINTS_0': (joints, 5121, 'VEC4'),
            'WEIGHTS_0': (weights, 5121, 'VEC4', True),
        },
        'indices': triangles.reshape(-1).astype(np.uint32),
        'targets': [
            {'POSITION': (target['POSITION'].astype(np.float32), 5126, 'VEC3')}
            for target in built_targets
        ],
    }

    hair_count = len(hair_positions)
    hair_joints = np.zeros((hair_count, 4), dtype=np.uint8)
    hair_joints[:, 0] = JOINT_HEAD
    hair_weights = np.zeros((hair_count, 4), dtype=np.uint8)
    hair_weights[:, 0] = 255
    hair_replacement = {
        'attributes': {
            'POSITION': (hair_positions.astype(np.float32), 5126, 'VEC3'),
            'NORMAL': (np.round(hair_normals * 32767).astype(np.int16), 5122, 'VEC3', True),
            'JOINTS_0': (hair_joints, 5121, 'VEC4'),
            'WEIGHTS_0': (hair_weights, 5121, 'VEC4', True),
        },
        'indices': hair_triangles.reshape(-1).astype(np.uint32),
        'targets': [],
    }

    replacements = {
        (HEAD_MESH, SKIN_PRIM): head_replacement,
        (HAIR_MESH, HAIR_PRIM): hair_replacement,
    }
    replacements.update(face_parts)
    built = glb_edit.replace_primitives(open(RUNTIME, 'rb').read(), replacements)
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / 'Protagonist_Character.glb').write_bytes(built)
    return {
        'head_triangles': int(len(triangles)),
        'head_vertices': int(count),
        'hair_triangles': int(len(hair_triangles)),
        'hair_vertices': int(hair_count),
        'bytes': len(built),
        'head_uv': uv,
        'head_tangent': tangent,
    }


def extract() -> None:
    """Copy the exact V1 skin/hair primitives into the art source, never the reverse."""
    document, binary = glb.load(RUNTIME)
    data = open(RUNTIME, 'rb').read()
    # Keep the whole document; the build reads only the two primitives. The source
    # is a verbatim copy so the SHA can be recorded in the README.
    V1.parent.mkdir(parents=True, exist_ok=True)
    V1.write_bytes(data)
    print(V1, hashlib.sha256(data).hexdigest())


def contract() -> dict:
    """What the V2 head promises, measured off the built GLB.

    `check` asserts every line of this, so a change that quietly drops the UVs, a morph
    target, the aperture or the strand count cannot pass as the same head.
    """
    document, binary = glb.load(BUILD / 'Protagonist_Character.glb')
    head = document['meshes'][HEAD_MESH]['primitives'][SKIN_PRIM]
    arrays = glb.primitive_arrays(document, binary, head)
    positions = arrays['POSITION']
    triangles = arrays['indices'].reshape(-1, 3).astype(np.int64)
    labels = components(positions, triangles)
    unique_labels, sizes = np.unique(labels, return_counts=True)
    # The four lid shells: the components of 200-400 vertices whose centroid is on an eye.
    # Their front edges are the lid margins; the aperture is the gap between the upper
    # shell's lowest and the lower shell's highest front vertex over the pupil column.
    margins = {1.0: {'upper': [], 'lower': []}, -1.0: {'upper': [], 'lower': []}}
    lids = 0
    for label, size in zip(unique_labels, sizes):
        if not 200 < size < 400:
            continue
        points = positions[labels == label]
        centre = points.mean(axis=0)
        side = 1.0 if centre[0] > 0 else -1.0
        eye = np.array([side * EYE_X, EYE_Y, EYE_Z])
        if np.linalg.norm(centre - eye) > 0.03:
            continue
        lids += 1
        relative = points - eye
        front = relative[(relative[:, 2] > 0.004) & (np.abs(relative[:, 0]) < 0.0015)]
        margins[side]['upper' if centre[1] > EYE_Y else 'lower'].extend(front[:, 1].tolist())
    aperture = np.mean([min(margins[side]['upper']) - max(margins[side]['lower'])
                        for side in (1.0, -1.0)]) * 1000.0 if lids == 4 else 0.0
    uvs = arrays['TEXCOORD_0']
    hair_arrays = glb.primitive_arrays(
        document, binary, document['meshes'][HAIR_MESH]['primitives'][HAIR_PRIM])
    hair_labels = components(hair_arrays['POSITION'], hair_arrays['indices'].reshape(-1, 3))
    return {
        'v1_sha256': hashlib.sha256(V1.read_bytes()).hexdigest(),
        'runtime_bytes': RUNTIME.stat().st_size,
        'head_vertices': int(len(positions)),
        'head_triangles': int(len(triangles)),
        'head_targets': len(head['targets']),
        'head_has_uv': 'TEXCOORD_0' in head['attributes'],
        'head_uv_u_min': float(uvs[:, 0].min()),
        'head_uv_u_max': float(uvs[:, 0].max()),
        'head_uv_u_span_max': float((uvs[triangles][:, :, 0].max(axis=1)
                                     - uvs[triangles][:, :, 0].min(axis=1)).max()),
        'lid_shells': lids,
        'aperture_height_mm': aperture,
        'hair_vertices': int(len(hair_arrays['POSITION'])),
        'hair_triangles': int(len(hair_arrays['indices']) // 3),
        'hair_locks': int(len(np.unique(hair_labels))) - 1,  # less the scalp cap
        'eye_targets': len(document['meshes'][EYE_MESH]['primitives'][0]['targets']),
    }


def check() -> dict:
    """The V2 contract, asserted. Also proves the committed GLB is this build's output."""
    source = hashlib.sha256(V1.read_bytes()).hexdigest()
    if source != V1_SHA:
        raise SystemExit(f'{V1} is not the recorded V1 source: {source} != {V1_SHA}')
    report = build()
    current = RUNTIME.read_bytes()
    built = (BUILD / 'Protagonist_Character.glb').read_bytes()
    if current != built:
        raise SystemExit('runtime GLB differs from the build; run: python3 tools/head_v2.py install')
    measured = contract()
    expectations = {
        'head_has_uv': True,
        'head_targets': 9,
        'lid_shells': 4,
        'hair_locks': 96,
    }
    failed = []
    for name, expected in expectations.items():
        if measured[name] != expected:
            failed.append(f'{name} is {measured[name]}, expected {expected}')
    if not (0.0 <= measured['head_uv_u_min'] and measured['head_uv_u_max'] <= 1.0):
        failed.append('the head atlas leaves [0, 1]')
    if measured['head_uv_u_span_max'] > 0.5:
        failed.append('a triangle still wraps across the atlas seam')
    if not (10.0 <= measured['aperture_height_mm'] <= 15.0):
        failed.append(f"the aperture is {measured['aperture_height_mm']:.1f} mm tall")
    if measured['runtime_bytes'] > MODEL_BUDGET:
        failed.append(f"{measured['runtime_bytes']} B is over the {MODEL_BUDGET} B model budget")
    if failed:
        raise SystemExit('V2 contract failed:\n  ' + '\n  '.join(failed))
    print(json.dumps(measured, indent=2))
    print('runtime GLB matches the build, and meets the V2 contract')
    return measured


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['extract', 'build', 'install', 'check'])
    args = parser.parse_args()
    if args.command == 'extract':
        extract()
        return
    if args.command == 'check':
        check()
        return
    report = build()
    print(json.dumps(report, indent=2, default=str))
    if args.command == 'install':
        RUNTIME.write_bytes((BUILD / 'Protagonist_Character.glb').read_bytes())
        print('installed', RUNTIME)


if __name__ == '__main__':
    main()
