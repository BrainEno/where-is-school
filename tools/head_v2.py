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
  * the hair keeps the owner's hairstyle — the same 96 locks and scalp cap, so every
    count and contract holds — and each lock is refined in place: every ring gains the
    midpoint of each of its five edges (5 -> 10 columns, 45 -> 90 triangles), the new
    columns are thinned to 0.82 of their radius about the strand's own axis;
  * the r40 mop then re-plants every lock (`barber_locks`): a dense, symmetric band
    layout from crown to nape with the face window excluded, chunky 4.6-6.4 mm roots,
    region-cut lengths (a fringe over the forehead that stops above the brows, 30-46 mm
    on top, 18-28 mm at the nape), gravity-led flow, per-lock rhythm and twist, the
    cap padded 1.2-3.0 mm for body — the whole mop clamped to the skull field and the
    pinned envelope. The crown whorl relief (`whorl_cap`, boundary pinned) runs last;
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
    #    r38: the bowl and the crease read as black pools under the classroom key
    #    (N·L crosses the shadow edge on the whole concavity), so the pits are a
    #    third shallower; the rolls and supports keep the lid planes.
    #    r40: every crease also has to stay *broader* than the ink hull's offset
    #    (3.3 mm at review distance) -- a fold tighter than the offset makes the
    #    hull's far wall poke through the near one and the ink draws the fold as a
    #    black dash (the owner's r39 "bug-like lines at the eye corners").
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.0305, 1.585, 0.103), (0.024, 0.019, 0.028), -0.0024))
        add(gaussian(positions, (side * 0.0305, 1.592, 0.108), (0.018, 0.007, 0.015), 0.0025))
        add(gaussian(positions, (side * 0.0305, 1.600, 0.101), (0.020, 0.008, 0.016), -0.0010))
        add(gaussian(positions, (side * 0.0305, 1.576, 0.107), (0.016, 0.005, 0.013), 0.0015))
        # under-eye bag and tear trough
        add(gaussian(positions, (side * 0.032, 1.5725, 0.101), (0.015, 0.0055, 0.018), 0.0015))
        add(gaussian(positions, (side * 0.034, 1.565, 0.098), (0.022, 0.013, 0.022), -0.0008))
        # outer corner support
        add(gaussian(positions, (side * 0.0455, 1.581, 0.099), (0.010, 0.008, 0.014), 0.0010))

    # 2. Nose: bridge planes, rounded tip, alar wings, columella and the underside.
    #    r40: the side walls and the alar pit widened past the hull offset -- the
    #    old 4.5-5 mm sigmas drew the nose sides and the nostril wings in ink.
    add(gaussian(positions, (0.0, 1.555, 0.128), (0.010, 0.028, 0.018), 0.0015))
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.0105, 1.545, 0.124), (0.009, 0.024, 0.018), -0.0009))
        add(gaussian(positions, (side * 0.019, 1.5005, 0.127), (0.0075, 0.007, 0.011), 0.0030))
        add(gaussian(positions, (side * 0.024, 1.5015, 0.120), (0.008, 0.009, 0.013), -0.0010))
    add(gaussian(positions, (0.0, 1.5075, 0.139), (0.0085, 0.008, 0.009), 0.0030))
    add(gaussian(positions, (0.0, 1.4965, 0.1315), (0.009, 0.0045, 0.009), 0.0015))
    add(gaussian(positions, (0.0, 1.4935, 0.1285), (0.009, 0.006, 0.010), -0.0007))

    # 3. Mouth: philtrum, cupid's bow, lip volumes, a cut mouth line, corners.
    #    r38: the cut line and the corners read as holes around the mouth; halved.
    #    r40: the cut, the vermilion step and the corners were 1.8-4.5 mm knife
    #    creases -- tighter than the hull offset, so the ink drew the whole mouth
    #    zone black. They are now broader folds; the lip seam itself (the walls
    #    genuinely meet) still catches a crisp ink line, which is the wanted one.
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.0060, 1.5045, 0.1185), (0.0035, 0.0065, 0.009), 0.0009))
        add(gaussian(positions, (side * 0.0100, 1.4995, 0.1195), (0.0085, 0.0040, 0.009), 0.0024))
        add(gaussian(positions, (side * 0.0155, 1.4895, 0.1190), (0.012, 0.0055, 0.009), 0.0022))
        add(gaussian(positions, (side * 0.0245, 1.4955, 0.1125), (0.008, 0.007, 0.011), -0.0007))
        # vermilion border step
        add(gaussian(positions, (side * 0.014, 1.4948, 0.1195), (0.011, 0.004, 0.008), -0.0006))
    add(gaussian(positions, (0.0, 1.5005, 0.1200), (0.0045, 0.0030, 0.007), 0.0012))
    add(gaussian(positions, (0.0, 1.4885, 0.1200), (0.009, 0.0040, 0.007), 0.0018))
    add(gaussian(positions, (0.0, 1.4952, 0.1185), (0.024, 0.005, 0.010), -0.0010))
    add(gaussian(positions, (0.0, 1.4785, 0.1045), (0.022, 0.010, 0.015), -0.0009))

    # 4. Cheeks, jaw and chin.
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.050, 1.5345, 0.079), (0.020, 0.016, 0.024), 0.0025))
        add(gaussian(positions, (side * 0.043, 1.5085, 0.071), (0.018, 0.016, 0.020), -0.0014))
        add(gaussian(positions, (side * 0.052, 1.4625, 0.045), (0.018, 0.010, 0.022), 0.0020))
        add(gaussian(positions, (side * 0.061, 1.6065, 0.030), (0.012, 0.014, 0.020), -0.0010))
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


def surface_z(x: float, y: float, head: np.ndarray, triangles: np.ndarray) -> float | None:
    """Height of the skin sheet directly over (x, y), from the triangle soup.

    The brow rides the face's front sheet, so when the head's back sheet shares the
    same (x, y) footprint the front (larger-z) sheet wins. Outside the footprint the
    nearest projected edge answers, which is what the brow tail needs as it runs off
    the temple.
    """
    v0, v1, v2 = head[triangles[:, 0]], head[triangles[:, 1]], head[triangles[:, 2]]
    point = np.array([x, y])

    def closer(best: tuple, distance: np.ndarray, z: np.ndarray) -> tuple:
        order = np.lexsort((-z, distance))
        candidate = (float(distance[order[0]]), float(z[order[0]]))
        if candidate[0] < best[0] - 1e-12 or (candidate[0] <= best[0] + 1e-12
                                              and candidate[1] > (best[1] if best[1] is not None else -np.inf)):
            return candidate
        return best

    best = (np.inf, None)
    for a, b in ((v0, v1), (v1, v2), (v2, v0)):
        edge = (b - a)[:, :2]
        t = np.clip(((point - a[:, :2]) * edge).sum(axis=1)
                    / np.maximum((edge * edge).sum(axis=1), 1e-18), 0.0, 1.0)
        closest = a[:, :2] + t[:, None] * edge
        best = closer(best, np.linalg.norm(closest - point, axis=1), a[:, 2] + t * (b[:, 2] - a[:, 2]))

    # A triangle whose xy projection contains the point is an exact answer; among
    # stacked sheets (face and skull back) the front one is the skin to ride.
    top = -np.inf
    for a, b, c in ((v0, v1, v2),):
        signs = np.stack([
            (point[0] - a[:, 0]) * (b[:, 1] - a[:, 1]) - (point[1] - a[:, 1]) * (b[:, 0] - a[:, 0]),
            (point[0] - b[:, 0]) * (c[:, 1] - b[:, 1]) - (point[1] - b[:, 1]) * (c[:, 0] - b[:, 0]),
            (point[0] - c[:, 0]) * (a[:, 1] - c[:, 1]) - (point[1] - c[:, 1]) * (a[:, 0] - c[:, 0]),
        ])
        inside = (signs >= -1e-12).all(axis=0) | (signs <= 1e-12).all(axis=0)
        for index in np.nonzero(inside)[0]:
            xa, ya = a[index, :2]
            xb, yb = b[index, :2]
            xc, yc = c[index, :2]
            det = (yb - yc) * (xa - xc) + (xc - xb) * (ya - yc)
            if abs(det) < 1e-15:
                continue
            wa = ((yb - yc) * (x - xc) + (xc - xb) * (y - yc)) / det
            wb = ((yc - ya) * (x - xc) + (xa - xc) * (y - yc)) / det
            wc = 1.0 - wa - wb
            if min(wa, wb, wc) >= -1e-9:
                top = max(top, wa * a[index, 2] + wb * b[index, 2] + wc * c[index, 2])
    if top > -np.inf:
        return float(top)
    return best[1]


def reshape_brow(brow: np.ndarray, head: np.ndarray,
                 triangles: np.ndarray | None = None,
                 brow_original: np.ndarray | None = None) -> np.ndarray:
    """Seat V1's floating eyebrow on the brow ridge, and taper it.

    The brow is a swept tube: four vertices to a ring, seven rings from the nose to the
    temple, and a fan-capped end at each end of it. V1 left it 7-10 mm in front of the
    forehead and the same thickness all the way across. Every ring is re-hung here on the
    ridge — its centre on the skin, its section a diamond that swells over the bone and thins
    to a fine tail — and each capped end is pulled into the tube so it rounds off instead of
    ending in a blunt cut. The ring's four vertices keep their order around the tube, which is
    what stops the section from twisting from one ring to the next. Topology, vertex order and
    the nine morph targets are untouched.

    `brow_original` is the same ring stack *before* the sculpt's displacement was carried
    onto it. The slot assignment (which vertex rides top, front, back) reads that -- a
    ring's own V1 section -- so a sculpt change cannot flip a ring's section and twist
    the tube (measured on the r40 build: one mid ring swapped front/back, a 7 mm jump
    and a 5 mm mirror residual).
    """
    out = brow.copy()
    # The two sides' station grids are merged into one symmetric grid (V1's grids sit
    # up to 0.2 mm apart, and with per-side grids the same ring on each side could be
    # decomposed differently -- one side's vertices slot-reset, the other's kept --
    # which showed up as a 5 mm mirror residual). Each merged station gathers the
    # vertices of both sides within its tolerance; every vertex keeps its own x.
    raw_stations = np.unique(np.round(np.abs(out[:, 0]), 5))
    station_groups: list[list[float]] = []
    for value in raw_stations:
        if station_groups and value - station_groups[-1][-1] < 0.0008:
            station_groups[-1].append(float(value))
        else:
            station_groups.append([float(value)])
    stations_common = [float(np.mean(g)) for g in station_groups]
    for side in (1.0, -1.0):
        index = np.nonzero(np.sign(out[:, 0]) == side)[0]
        points = out[index]
        x = np.abs(points[:, 0])
        low, high = float(x.min()), float(x.max())
        for station in stations_common:
            ring_index = np.nonzero(np.isclose(x, station, atol=9e-4))[0]
            ring = points[ring_index]
            along = float(np.clip((station - low) / max(high - low, 1e-9), 0.0, 1.0))
            centre_y = float(np.interp(along, [0.0, 0.25, 0.5, 0.75, 1.0],
                                       [1.6056, 1.6070, 1.6074, 1.6066, 1.6049]))
            # r38b: the 2.2-2.4 mm diamond read as a knife slash (the owner's "the
            # brows are slivers"), and its 0.6 mm tail vanished under its own ink
            # hull, leaving the dash-dot lines at the eye corners. The section is
            # half again as tall, and the tail keeps body to the end.
            half_height = float(np.interp(along, [0.0, 0.18, 0.5, 0.8, 1.0],
                                          [0.0016, 0.0032, 0.0036, 0.0028, 0.0016]))
            half_depth = half_height * 1.0
            # r40: seat on the ridge's own top, not on one row's answer. The r40
            # sculpt widened the folds past the ink-hull offset, and a single-row
            # height probe then landed on whichever triangle the row happened to
            # win -- measurably different triangles on the two sides (7 mm apart in
            # z at station 32 mm), which is a brow tilt the owner already rejected
            # once (issue #385). Probing a small window across the ridge and taking
            # the highest sheet seats both brows on the same, symmetric ridge top.
            if triangles is not None:
                samples = [surface_z(station, centre_y + dy, head, triangles)
                           for dy in (-0.002, -0.001, 0.0, 0.001, 0.002)]
                skin = max((s for s in samples if s is not None), default=None)
            else:
                skin = None
            if skin is None:
                # No triangle soup (direct callers in tests): fall back to the
                # nearest skin vertices around the station.
                near = (np.abs(head[:, 0] - station) < 0.007) & \
                       (np.abs(head[:, 1] - centre_y) < 0.007)
                if not near.any():
                    near = (np.abs(head[:, 0] - station) < 0.014) & \
                           (np.abs(head[:, 1] - centre_y) < 0.014)
                skin = float(head[near, 2].max()) if near.any() else float(ring[:, 2].max())
            # r40: seated at 0.45 mm (was 0.5) -- the widened folds drop the skin a
            # little under the tube, and the seat rides it back down.
            centre_z = skin + 0.00045
            reference = brow_original if brow_original is not None else brow
            ref_ring = reference[ring_index]
            section = ref_ring[:, [1, 2]] - ref_ring[:, [1, 2]].mean(axis=0)
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
            # Ring stations can carry more vertices than the four slots plus the cap
            # (a fan whose end shares a station with the last full ring). Any vertex
            # the slots did not place keeps V1's floating position - at the inner end
            # of one brow that was a 3.9 mm droop off the tube, the last residue of
            # V1's 7-10 mm float, and the reason one brow read lower than the other.
            # Pull such stragglers into the tube's centre: their station, its profile
            # height and its skin seating, no offset.
            placed = set(slots.values()) | ({cap} if cap >= 0 else set())
            for local in range(len(ring)):
                if local not in placed:
                    points[ring_index[local]] = (ring[local, 0], centre_y, centre_z)
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
                     displacement: np.ndarray,
                     skin_triangles: np.ndarray | None = None) -> dict:
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
        raw_positions = arrays['POSITION'].astype(np.float64)
        positions = raw_positions + nearest_displacement(raw_positions, skin, displacement)
        if reshape:
            positions = reshape_brow(positions, skin, skin_triangles,
                                     brow_original=raw_positions)
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
# V3 hair (issue #386): roots into the mass, strand rhythm, the fall, the crown whorl
# --------------------------------------------------------------------------------------

# The V2 hair envelope, pinned. Every V3 displacement is clamped inside it, so the
# approved silhouette - the tips, the cap edge, the model height the tests measure -
# cannot drift even where the reshaping bends a shaft.
HAIR_BBOX_MIN = np.array([-0.1085, 1.5175, -0.1198])
HAIR_BBOX_MAX = np.array([0.1575, 1.7669, 0.1817])
# The r40 mop envelope, pinned from the built mop: the re-barbered hair lives close
# to the skull -- no strand reaches further than ~55 mm from the scalp centre -- so
# the mop's own envelope is much tighter than the V1 plates' one above.
MOP_BBOX_MIN = np.array([-0.1085, 1.5175, -0.0946])
MOP_BBOX_MAX = np.array([0.1075, 1.7175, 0.1616])
SCALP = np.array([0.0, 1.565, 0.040])
# Root burial: how far a root ring dives back along its own lock axis (the skull clamp
# keeps every vertex 1.2 mm off the skin, so the burial never pierces the head).
BURIAL = 0.008
SKIN_MARGIN = 0.0012
# The taper envelope, normalised to the root ring. V2 measured (1.0, 1.14, 1.04, 0.88,
# 0.55) - a mid-shaft bulge that reads as a cone with a pinched tip. V3 falls cleanly
# from the buried root to the untouched tip.
TAPER = (1.0, 0.94, 0.82, 0.66, 0.55)
# The hair atlas: 11 x 12 cells. The cap owns the 3 x 3 block at columns 0..2; the 96
# locks fill columns 3..10 of all 12 rows, exactly 96 cells. A lock's root sits at the
# cell's low-V edge and its tip at the high-V edge.
UV_COLS, UV_ROWS, UV_CAP_CELLS = 11, 12, 3


def hair_cell(index: int) -> tuple[int, int]:
    """The atlas cell of lock `index`: columns 3..10, all 12 rows."""
    col = UV_CAP_CELLS + (index % (UV_COLS - UV_CAP_CELLS))
    row = index // (UV_COLS - UV_CAP_CELLS)
    if row >= UV_ROWS:
        raise SystemExit(f'lock cell {index} does not fit the {UV_COLS}x{UV_ROWS} atlas')
    return col, row


def _hash_units(label: int, salt: int, count: int) -> list[float]:
    """Deterministic 0..1 units per lock - the de-clone parameters. No randomness: the
    same lock reshapes the same way on every build."""
    h = 0xcbf29ce484222325
    for x in (label, salt, 0x386):
        h ^= x & 0xFFFFFFFFFFFFFFFF
        h = (h * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    out = []
    for _ in range(count):
        h ^= h >> 33
        h = (h * 0xff51afd7ed558ccd) & 0xFFFFFFFFFFFFFFFF
        h ^= h >> 33
        h = (h * 0xc4ceb9fe1a85ec53) & 0xFFFFFFFFFFFFFFFF
        h ^= h >> 33
        out.append((h >> 11) / float(1 << 53))
    return out


def _fade(value: float) -> float:
    value = min(max(value, 0.0), 1.0)
    return value * value * (3.0 - 2.0 * value)


def _hair_components(positions: np.ndarray, triangles: np.ndarray):
    """Ring levels of every 51-vertex lock, plus the cap's label and open boundary.

    A refined lock's only open boundary is its root ring (ten vertices on single-face
    edges); breadth-first distance from that ring walks the five rings and the tip. The
    cap is the one 303-vertex component; its boundary is the hairline. The lock entries
    carry their own edge list so the UV pass can walk each ring in order.
    """
    labels = components(positions, triangles)
    unique, sizes = np.unique(labels, return_counts=True)
    locks = []
    cap_label = None
    cap_boundary = None
    for label, size in zip(unique, sizes):
        verts = np.nonzero(labels == label)[0]
        faces = triangles[labels[triangles[:, 0]] == label]
        edges = np.sort(np.vstack((faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]])), axis=1)
        uniq_edges, counts = np.unique(edges, axis=0, return_counts=True)
        boundary = np.unique(uniq_edges[counts == 1])
        if size == 303:
            if cap_label is not None:
                raise SystemExit('hair has more than one cap-sized component')
            cap_label = int(label)
            cap_boundary = boundary
            continue
        if size != 51:
            raise SystemExit(f'hair component of {size} vertices is not a refined lock')
        adj: dict[int, list[int]] = {}
        for a, b in uniq_edges:
            adj.setdefault(int(a), []).append(int(b))
            adj.setdefault(int(b), []).append(int(a))
        level = {int(v): -1 for v in verts}
        for v in boundary:
            level[int(v)] = 0
        frontier = [int(v) for v in boundary]
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
        levels = []
        for k in range(6):
            ring = np.array([v for v in verts if level[int(v)] == k])
            expected = 1 if k == 5 else 10
            if len(ring) != expected:
                raise SystemExit(f'lock {label}: level {k} holds {len(ring)} vertices, not {expected}')
            levels.append(ring)
        locks.append({'label': int(label), 'levels': levels,
                      'tip': int(levels[5][0]), 'edges': uniq_edges})
    if len(locks) != 96 or cap_label is None:
        raise SystemExit(f'hair is {len(locks)} locks, not 96 (cap {cap_label})')
    return locks, cap_label, cap_boundary, labels


def _skull_field(skin: np.ndarray) -> np.ndarray:
    """Outermost skin radius per (angle, height) bin, dilated one bin - the burial
    clamp's "how far out is the head here". The bins (4 deg, 4 mm) are finer than the
    hair's own spacing, as in `character_hair`."""
    grid = np.zeros((90, 90))
    pts = skin[skin[:, 1] > 1.50]
    if len(pts):
        radius = np.hypot(pts[:, 0], pts[:, 2] - SCALP[2])
        ai = np.clip(((np.degrees(np.arctan2(pts[:, 0], -(pts[:, 2] - SCALP[2]))) + 180.0)
                      / 4.0).astype(int), 0, 89)
        yi = np.clip(((pts[:, 1] - 1.50) / 0.004).astype(int), 0, 89)
        np.maximum.at(grid, (ai, yi), radius)
        dilated = grid.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                dilated = np.maximum(dilated, np.roll(np.roll(grid, dy, 0), dx, 1))
        return dilated
    return grid


def _skull_radius(field: np.ndarray, x: float, y: float, z: float) -> float:
    angle = np.degrees(np.arctan2(x, -(z - SCALP[2])))
    ai = int(np.clip((angle + 180.0) / 4.0, 0, 89))
    yi = int(np.clip((y - 1.50) / 0.004, 0, 89))
    return float(field[ai, yi])


def _lock_frame(root: np.ndarray, axis: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """A stable perpendicular frame for a lock: e1 from the scalp direction, e2 = axis
    cross e1. Twists, creases and the UV azimuth all read against this frame."""
    away = root - SCALP
    e1 = away - axis * float(away @ axis)
    if np.linalg.norm(e1) < 1e-6:
        e1 = np.cross(axis, np.array([0.0, -1.0, 0.0]))
        if np.linalg.norm(e1) < 1e-6:
            e1 = np.cross(axis, np.array([1.0, 0.0, 0.0]))
    e1 = e1 / np.linalg.norm(e1)
    return e1, np.cross(axis, e1)


def barber_locks(positions: np.ndarray, triangles: np.ndarray, skin: np.ndarray,
                 skin_triangles: np.ndarray | None = None) -> np.ndarray:
    """The r40 redesign: re-barber the 96 locks into a designed mop.

    The owner asked for the whole hairstyle to be re-thought, not the spikes
    trimmed: the V1 plates' tips reached 140-180 mm from the scalp centre and
    read as fragmented needles. The lock *topology* is the owner's and stays --
    96 refined locks (ten-vertex rings) plus the scalp cap, so every count, the
    atlas and the contracts hold -- but every lock is *re-planted*:

    1. **A dense, symmetric layout.** Seven polar bands from the crown to the
       nape (12-104 deg), azimuths spread uniformly with hashed jitter; the
       face window (|azimuth| < 45-60 deg by band) is excluded, so roots tile
       the skull the way a haircut does, not the way V1's plates happened to
       sit.
    2. **Chunky strands.** Root radii 4.6-6.4 mm (the old plates were ~2 mm
       needles), a clean taper, per-lock rhythm and a 0.12 rad twist: the mop
       reads as strands, not blades.
    3. **Region-cut lengths.** A forward fringe over the forehead that stops
       above the brows, 30-46 mm on top, 30-44 mm over the temples, 18-28 mm
       at the nape and sideburns -- every tip asserted inside its region's
       bound, so the cut works from the front, the sides and the back.
    4. **The cap pads** a smooth 1.5 mm outward (faded at the hairline) so
       the mop has body between the roots.

    Everything is clamped to the skull field (+1.2 mm) and to the mop envelope,
    and the whole pass is a pure function of the mesh plus the sculpted skin.
    """


    locks, cap_label, cap_boundary, labels = _hair_components(positions, triangles)
    out = positions.copy()
    field = _skull_field(skin)
    if skin_triangles is None:
        skin_triangles = triangles

    # -- the layout ------------------------------------------------------------
    # Bands: (theta_lo, theta_hi, count, front_window_deg). Azimuth 0 = front (+Z);
    # a band with a window plants its locks on the two side/back arcs only.
    bands = [
        (12.0, 24.0, 8, 0.0),
        (24.0, 38.0, 14, 0.0),
        (38.0, 52.0, 18, 0.0),
        (52.0, 64.0, 20, 0.0),
        (64.0, 76.0, 14, 30.0),
        (76.0, 92.0, 12, 25.0),
        (92.0, 104.0, 10, 30.0),
    ]
    slots: list[tuple[float, float]] = []  # (theta, azimuth) degrees
    for t_lo, _t_hi, count, window in bands:
        if window > 0.0:
            per_arc = count // 2
            span = 180.0 - window
            for k in range(per_arc):
                a = window + span * (k + 0.5) / per_arc
                slots.append((t_lo, a))
                slots.append((t_lo, -a))
            if count % 2:
                slots.append((t_lo, 180.0))
        else:
            step = 360.0 / count
            for k in range(count):
                slots.append((t_lo, -180.0 + step * (k + 0.5)))
    if len(slots) != 96:
        raise SystemExit(f'the mop layout holds {len(slots)} slots, not 96')

    # Order the locks by their own root's (theta, azimuth) and zip with the sorted
    # slots, so each lock moves the shortest way and the layout stays symmetric.
    roots = np.array([positions[entry['levels'][0]].mean(axis=0) for entry in locks])
    rel = roots - SCALP
    r_len = np.linalg.norm(rel, axis=1)
    th0 = np.degrees(np.arccos(np.clip(rel[:, 1] / np.maximum(r_len, 1e-9), -1.0, 1.0)))
    az0 = np.degrees(np.arctan2(rel[:, 0], rel[:, 2]))
    order = np.lexsort((az0, th0))
    slots.sort(key=lambda s: (s[0], s[1]))

    skin_pts = skin[skin[:, 1] > 1.47]
    tri_pts = skin_triangles

    def surface_radius(direction: np.ndarray) -> float:
        """Where the scalp ray leaves the skin: a real ray cast against the skin's
        triangles, so a root sits on the surface whatever the point spacing does.
        Falls back to the widest point within six degrees of the ray."""
        v0 = tri_pts[skin_triangles[:, 0]]
        v1 = tri_pts[skin_triangles[:, 1]]
        v2 = tri_pts[skin_triangles[:, 2]]
        e1 = v1 - v0
        e2 = v2 - v0
        pvec = np.cross(direction, e2)
        det = np.einsum('ij,ij->i', e1, pvec)
        ok = np.abs(det) > 1e-14
        inv = np.zeros_like(det)
        inv[ok] = 1.0 / det[ok]
        tvec = SCALP - v0
        u = np.einsum('ij,ij->i', tvec, pvec) * inv
        qvec = np.cross(tvec, e1)
        v = qvec @ direction * inv
        t = np.einsum('ij,ij->i', e2, qvec) * inv
        hit = ok & (u >= 0.0) & (v >= 0.0) & (u + v <= 1.0) & (t > 0.0) & (t < 0.30)
        if hit.any():
            return float(t[hit].min())
        d = skin_pts - SCALP
        r = np.linalg.norm(d, axis=1)
        cos = (d @ direction) / np.maximum(r, 1e-9)
        near = cos > math.cos(math.radians(6.0))
        return float(r[near].max()) if near.any() else float(r.max())

    # tip height bounds per region: the fringe stays above the brows (1.615), the
    # sides above the ear line, the back above the nape hairline (1.5175).
    TIP_FLOOR = {'fringe': 1.618, 'top': 1.560, 'side': 1.572, 'back': 1.520}

    for slot, li in zip(slots, order):
        entry = locks[int(li)]
        theta, azimuth = slot
        u = _hash_units(int(li), 0x40, 10)
        # -- region rules ------------------------------------------------------
        a = abs(azimuth)
        if theta <= 52.0 and a < 50.0:
            kind = 'fringe'
        elif theta <= 52.0:
            kind = 'top'
        elif a > 125.0:
            kind = 'back'
        else:
            kind = 'side'
        # r40 second pass: the first mop's temple locks (30-44 mm, droop 0.38)
        # hung to the cheek line and read as a burnt curtain over the ears.
        length = {'fringe': 0.024 + 0.012 * u[0], 'top': 0.030 + 0.016 * u[1],
                  'side': 0.022 + 0.012 * u[2], 'back': 0.018 + 0.010 * u[3]}[kind]
        droop = {'fringe': 0.20, 'top': 0.12, 'side': 0.30, 'back': 0.26}[kind]
        # r40 second pass: chunkier strands -- the first mop's 4.6-6.4 mm roots
        # were the same size as the ink hull's offset, so the temple tubes read
        # as ink slabs, not hair.
        r_root = 0.0060 + 0.0024 * u[4]

        th = math.radians(theta)
        az = math.radians(azimuth)
        d_hat = np.array([math.sin(th) * math.sin(az), math.cos(th), math.sin(th) * math.cos(az)])
        r_skin = surface_radius(d_hat)
        # The root sits just above the cap's own 1.5 mm pad, and the root ring is
        # buried 3 mm back along the flow -- the clamp parks it at skin + 1.2 mm,
        # *under* the pad, so the tube's open mouth is inside the cap's volume.
        # Floating it (the first mop) left a see-through slit per lock, and the
        # crown read as ninety-six dark cups.
        root = SCALP + d_hat * (r_skin + 0.0025)
        # -- flow: outward-down on top, gravity-led at the sides and back -------
        if kind == 'fringe':
            flow = d_hat * 0.85 + np.array([0.0, -0.30, 0.45])
        elif kind == 'top':
            # r40: the top locks comb OUTWARD from the crown, like hair from a
            # whorl -- vertical strands open wells between them that read as
            # dark hexagonal cups from any raised camera (measured on two r40
            # renders; r39's plates hid them by lying flat).
            out_dir = np.array([d_hat[0], 0.0, d_hat[2]])
            n = float(np.linalg.norm(out_dir))
            out_dir = out_dir / n if n > 1e-6 else np.array([0.0, 0.0, 1.0])
            flow = d_hat * 0.55 + out_dir * 0.55 + np.array([0.0, -0.30, 0.0])
        elif kind == 'side':
            flow = d_hat * 0.45 + np.array([0.0, -0.85, 0.0])
        else:
            flow = d_hat * 0.55 + np.array([0.0, -0.75, 0.0])
        flow = flow / np.linalg.norm(flow)
        gravity = np.array([0.0, -1.0, 0.0])

        # -- the tube ----------------------------------------------------------
        taper = [1.0, 0.90, 0.78, 0.66, 0.54]
        stations = [0.0, 0.22, 0.44, 0.66, 0.86, 1.0]
        centre = [root + flow * (length * t) + gravity * (droop * length * t * t)
                  for t in stations]
        if kind == 'top':
            # Knit the pelt: the second ring sits at an absolute 8 mm so the
            # swollen rings of neighbouring locks meet at the same height and
            # close the gaps between the combed strands.
            centre[1] = root + flow * 0.008
        floor = TIP_FLOOR[kind]
        if centre[-1][1] < floor:
            centre[-1][1] = floor
        if centre[4][1] < floor + 0.003:
            centre[4][1] = floor + 0.003
        axis = centre[-1] - centre[0]
        axis = axis / max(float(np.linalg.norm(axis)), 1e-9)
        e1, e2 = _lock_frame(root, flow)
        twist = (u[5] - 0.5) * 0.24
        yaw = (u[6] - 0.5) * 0.5
        e1 = e1 * math.cos(yaw) + np.cross(flow, e1) * math.sin(yaw)
        e1 = e1 / max(float(np.linalg.norm(e1)), 1e-9)
        e2 = np.cross(flow, e1)

        # original ring angles, so each ring keeps its own cycle order (the atlas
        # walks rings by edge order and the strands must not corkscrew)
        old_root = positions[entry['levels'][0]].mean(axis=0)
        old_axis = positions[entry['tip']] - old_root
        old_axis = old_axis / max(float(np.linalg.norm(old_axis)), 1e-9)
        oe1, oe2 = _lock_frame(old_root, old_axis)

        verts = np.concatenate([np.asarray(r) for r in entry['levels'][:5]]
                               + [np.array([entry['tip']])])
        ring_angles = []
        for ring in entry['levels'][:5]:
            rel_r = positions[ring] - old_root
            along = rel_r @ old_axis
            radial = rel_r - np.outer(along, old_axis)
            ring_angles.append([math.atan2(float(p @ oe2), float(p @ oe1)) for p in radial])

        for k, ring in enumerate(entry['levels'][:5]):
            t = stations[k]
            ring_centre = centre[k]
            rr = r_root * taper[k] * (1.0 + 0.07 * math.sin(math.tau * (t * 0.8 + u[7])))
            if k == 0:
                # Slim and buried: a fat root ring on the skull spans past the
                # neighbouring roots (12-18 mm spacing), and the clamped,
                # interpenetrating rims tiled the crown with dark hexagonal cups.
                ring_centre = ring_centre - flow * 0.003
            if k == 1:
                # The roots-touch swell rides one station up, clear of the cap.
                rr *= 1.45
            for j, vid in enumerate(np.asarray(ring)):
                ang = ring_angles[k][j] + twist * math.sin(math.pi * t)
                jitter = 1.0 + (u[8] - 0.5) * 0.10 if k > 0 else 1.0
                out[vid] = ring_centre + (math.cos(ang) * e1 + math.sin(ang) * e2) * (rr * jitter)
        out[entry['tip']] = centre[-1]

        # clamp: outside the skull, inside the mop envelope; and no vertex hangs
        # into the face column -- the space in front of the brow line, over the
        # eyes and temples, where a drooping side strand would float (measured
        # on the r40 build: four temple locks reached z 0.12 over the eye line)
        for vid in verts:
            p = out[vid]
            if p[1] < 1.615 and p[2] > 0.105 and abs(float(p[0])) < 0.075:
                p = np.array([p[0], p[1], 0.105])
            r_head = math.hypot(float(p[0]), float(p[2] - SCALP[2]))
            r_min = _skull_radius(field, float(p[0]), float(p[1]), float(p[2])) + SKIN_MARGIN
            if r_head < r_min and r_head > 1e-9:
                scale = r_min / r_head
                p = np.array([p[0] * scale, p[1], SCALP[2] + (p[2] - SCALP[2]) * scale])
            out[vid] = np.clip(p, MOP_BBOX_MIN, MOP_BBOX_MAX)

    # -- the cap pads ----------------------------------------------------------
    cap_verts = np.nonzero(labels == cap_label)[0]
    boundary_set = set(int(v) for v in cap_boundary)
    interior = np.array([v for v in cap_verts if int(v) not in boundary_set])
    outward = positions[interior] - SCALP
    outward = outward / np.maximum(np.linalg.norm(outward, axis=1, keepdims=True), 1e-9)
    distance = np.linalg.norm(positions[interior][:, None, :] - positions[cap_boundary][None, :, :],
                              axis=2).min(axis=1)
    edge = np.clip(distance / 0.012, 0.0, 1.0)
    edge = edge * edge * (3.0 - 2.0 * edge)
    # One smooth 1.5 mm pad with the hairline fade -- a per-vertex hashed pad made
    # the cap a noise surface, and its chaotic normals shaded as blotches under the
    # key (measured on the first r40 render). Body without bumps.
    pad = np.full(len(interior), 0.0015)
    moved = positions[interior] + outward * (pad * edge)[:, None]
    out[interior] = np.clip(moved, MOP_BBOX_MIN, MOP_BBOX_MAX)
    return out



def reshape_locks(positions: np.ndarray, triangles: np.ndarray, skin: np.ndarray) -> np.ndarray:
    """The issue #386 pass over the refined locks: roots, rhythm, fall, twist, creases.

    Tips are pinned and everything is clamped to the pinned envelope, so the approved
    silhouette does not move; everything between root and tip is re-shaped:

    1. **Roots enter the mass.** The root ring dives back along its own axis (8 mm, then
       the skull clamp) and widens - 1.28-1.56x along the fall of the hairline - until
       neighbouring roots touch; ring 1 follows at 45 % of both, so the shaft emerges
       from the cap's volume instead of being planted on its edge.
    2. **No more cone clones.** The measured profile (1.0, 1.14, 1.04, 0.88, 0.55) is
       remapped onto a clean fall; each lock takes its own width (0.86-1.12x), a
       wide-thin rhythm along the shaft, a gravity-consistent bow (5-11 mm, yawed per
       lock, zero at tip and root) with a gentle S wobble, and a cross-section twist of
       at most 0.15 rad.
    3. **A few creases, not grooves everywhere.** Locks wider than 22 mm (the plates)
       take one inward crease down rings 2-3, splitting the plate into strands.

    Pure function of the mesh plus the sculpted skin; vertex count and topology do not
    change, so the skin weights stay valid and the V2 contract's counts hold.
    """
    locks, _cap, _cap_boundary, _labels = _hair_components(positions, triangles)
    field = _skull_field(skin)
    out = positions.copy()
    gravity = np.array([0.0, -1.0, 0.0])
    taper_t = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
    for entry in locks:
        label = entry['label']
        levels = entry['levels']
        verts = np.concatenate(levels + [np.array([entry['tip']])])
        rows = np.arange(len(verts))
        level_of = np.minimum(rows // 10, 5)
        root = positions[levels[0]].mean(axis=0)
        tip = positions[entry['tip']]
        axis = tip - root
        length = float(np.linalg.norm(axis))
        if length < 1e-9:
            raise SystemExit(f'lock {label}: zero length')
        axis = axis / length
        rel = positions[verts] - root
        along = rel @ axis
        t = np.clip(along / length, 0.0, 1.0)
        radial = rel - np.outer(along, axis)
        radius = np.linalg.norm(radial, axis=1)
        ring_r = np.array([float(np.median(radius[rows[(rows // 10) == k]]))
                           for k in range(5)])
        ring_r = ring_r / max(ring_r[0], 1e-9)
        rmax = float(radius.max())

        u = _hash_units(label, 0, 8)
        width = 0.86 + 0.26 * u[0]
        widen = 1.28 + 0.28 * u[1]
        bend_amp = (0.005 + 0.006 * u[2]) * min(1.0, length / 0.10)
        yaw = (u[3] - 0.5) * 1.2
        twist = (u[4] - 0.5) * 0.30
        phase = u[5] * math.tau
        s_amp = (u[6] - 0.5) * 0.0044
        crease_at = u[7] * math.tau
        e1, e2 = _lock_frame(root, axis)
        g_perp = gravity - axis * float(gravity @ axis)
        if np.linalg.norm(g_perp) < 0.25:
            g_perp = e1
        g_perp = g_perp / np.linalg.norm(g_perp)
        side = np.cross(axis, g_perp)
        bend_dir = g_perp * math.cos(yaw) + side * math.sin(yaw)

        moved = positions[verts].copy()
        for i in rows:
            ring = int(level_of[i])
            if ring == 5:
                continue  # the tip is pinned: the silhouette's extremes do not move
            ti = float(t[i])
            rad = radial[i]
            r = float(radius[i])
            phi = math.atan2(float(rad @ e2), float(rad @ e1)) if r > 1e-9 else 0.0
            if ring == 0:
                # widen the root ring in its own plane, then dive back along the axis
                r *= widen
            else:
                ratio = float(np.interp(ti, taper_t, [1.0] + [TAPER[k] / max(ring_r[k], 1e-6)
                                                              for k in (1, 2, 3, 4)] + [1.0]))
                rhythm = 1.0 + 0.16 * math.sin(math.tau * (ti * 0.85 + phase))
                r *= ratio * width * rhythm
                if ring == 1:
                    r *= 1.0 + (widen - 1.0) * 0.45
                if rmax > 0.022 and ring in (2, 3) and r > 0.5 * rmax:
                    delta = abs((phi - crease_at + math.pi) % math.tau - math.pi)
                    if delta < 0.42:
                        r *= 0.72  # one crease: the plate reads as two strands
                if r > 1e-9:
                    phi += twist * math.sin(math.pi * ti)
                moved[i] = root + axis * float(along[i]) \
                    + (math.cos(phi) * e1 + math.sin(phi) * e2) * r
                moved[i] += bend_dir * (bend_amp * math.sin(math.pi * ti)) \
                    + side * (s_amp * math.sin(math.tau * ti))
                if ring == 1:
                    moved[i] -= axis * (BURIAL * 0.35)
                continue
            moved[i] = root + axis * float(along[i]) \
                + (math.cos(phi) * e1 + math.sin(phi) * e2) * r
            moved[i] -= axis * BURIAL
        for i in rows:
            if level_of[i] == 5:
                continue
            p = moved[i]
            r_head = math.hypot(float(p[0]), float(p[2] - SCALP[2]))
            r_min = _skull_radius(field, float(p[0]), float(p[1]), float(p[2])) + SKIN_MARGIN
            if r_head < r_min and r_head > 1e-9:
                scale = r_min / r_head
                p = np.array([p[0] * scale, p[1], SCALP[2] + (p[2] - SCALP[2]) * scale])
            moved[i] = np.clip(p, HAIR_BBOX_MIN, HAIR_BBOX_MAX)
        out[verts] = moved
    return out


def whorl_relief(point: np.ndarray, crown: np.ndarray) -> float:
    """The crown whorl and the back flow, as a signed relief in metres.

    Shared by the mesh pass (`whorl_cap`) and the normal-map painter, so the geometry
    and the map draw the same flow: a spiral of about 1.5 turns around the crown and,
    behind it, concentric arcs running from the whorl down towards the nape.
    """
    d = point - crown
    rho = float(np.linalg.norm(d))
    axis_c = crown - SCALP
    axis_c = axis_c / max(float(np.linalg.norm(axis_c)), 1e-9)
    e1 = np.array([0.0, 0.0, 1.0])
    e1 = e1 - axis_c * float(e1 @ axis_c)
    if float(np.linalg.norm(e1)) < 1e-6:
        e1 = np.array([1.0, 0.0, 0.0])
    e1 = e1 / np.linalg.norm(e1)
    e2 = np.cross(axis_c, e1)
    phi = math.atan2(float(d @ e2), float(d @ e1))
    spiral = math.sin(1.5 * phi + rho * 230.0)
    arcs = math.sin(rho * 300.0)
    back_w = min(max((0.012 - float(point[2])) / 0.050, 0.0), 1.0)
    spiral_f = 1.0 - min(max((rho - 0.045) / 0.030, 0.0), 1.0)
    arcs_f = 1.0 - min(max((rho - 0.060) / 0.045, 0.0), 1.0)
    return 0.0013 * spiral * max(1.0 - back_w, 0.35) * spiral_f \
        + 0.0010 * arcs * back_w * arcs_f


def whorl_cap(positions: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    """Relief the crown whorl and the back flow into the scalp cap.

    The cap's boundary - the hairline the owner authored - is pinned vertex for vertex;
    its interior takes the shared `whorl_relief` field along the vertex's own outward
    direction, faded to nothing within 18 mm of the boundary so no ridge reaches the
    edge. At most 1.3 mm, well inside the envelope.
    """
    locks, cap_label, cap_boundary, labels = _hair_components(positions, triangles)
    del locks
    verts = np.nonzero(labels == cap_label)[0]
    crown_index = int(verts[np.argmax(positions[verts, 1] - 0.45 * positions[verts, 2])])
    crown = positions[crown_index]
    interior = np.array([v for v in verts if v not in set(cap_boundary)])
    outward = positions[interior] - SCALP
    outward = outward / np.maximum(np.linalg.norm(outward, axis=1, keepdims=True), 1e-9)
    relief = np.array([whorl_relief(p, crown) for p in positions[interior]])
    distance = np.linalg.norm(positions[interior][:, None, :]
                              - positions[cap_boundary][None, :, :], axis=2).min(axis=1)
    edge = np.clip(distance / 0.018, 0.0, 1.0)
    edge = edge * edge * (3.0 - 2.0 * edge)
    moved = positions[interior] + outward * (relief * edge)[:, None]
    out = positions.copy()
    out[interior] = np.clip(moved, HAIR_BBOX_MIN, HAIR_BBOX_MAX)
    return out


def _ring_order(ring: np.ndarray, edges: np.ndarray) -> list[int]:
    """Walk a ring's cycle in edge order, from its lowest vertex id."""
    members = set(int(v) for v in ring)
    adj: dict[int, list[int]] = {int(v): [] for v in ring}
    for a, b in edges:
        a, b = int(a), int(b)
        if a in members and b in members:
            adj[a].append(b)
            adj[b].append(a)
    order = [min(members)]
    seen = {order[0]}
    while True:
        nxt = [w for w in sorted(adj[order[-1]]) if w not in seen]
        if not nxt:
            break
        order.append(nxt[0])
        seen.add(nxt[0])
    if len(order) != len(members):
        raise SystemExit(f'a ring walked as {len(order)} of {len(members)} vertices')
    return order


def hair_uv(positions: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    """The hair's UV atlas, for the maps the look draws on it.

    Each lock owns one atlas cell (`hair_cell`): U runs around the ring - offset half a
    column so no vertex sits on a seam and nothing wraps - and V runs root to tip. The
    cap maps azimuth (clipped to +/-115 deg, 0 = front) and height into its 3 x 3
    block; neither wraps, so no seam needs a duplicated vertex and the mesh keeps its
    exact V2 vertex count and topology.
    """
    locks, cap_label, _cap_boundary, labels = _hair_components(positions, triangles)
    uv = np.zeros((len(positions), 2))
    cell_w, cell_h = 1.0 / UV_COLS, 1.0 / UV_ROWS
    block_w, block_h = UV_CAP_CELLS * cell_w, UV_CAP_CELLS * cell_h
    cap_verts = np.nonzero(labels == cap_label)[0]
    d = positions[cap_verts] - SCALP
    az = np.degrees(np.arctan2(d[:, 0], -(d[:, 2])))
    ys = positions[cap_verts][:, 1]
    u = 0.02 + (np.clip(az, -115.0, 115.0) + 115.0) / 230.0 * (block_w - 0.04)
    v = 0.02 + (np.clip(ys, 1.515, 1.71) - 1.515) / 0.195 * (block_h - 0.04)
    uv[cap_verts] = np.stack([u, v], axis=1)
    used: set[tuple[int, int]] = set()
    for index, entry in enumerate(locks):
        col, row = hair_cell(index)
        if (col, row) in used:
            raise SystemExit(f'atlas cell {(col, row)} used twice')
        used.add((col, row))
        u0, v0 = col * cell_w, row * cell_h
        for k, ring in enumerate(entry['levels'][:5]):
            order = _ring_order(ring, entry['edges'])
            for slot, vid in enumerate(order):
                uv[vid] = (u0 + (slot + 0.5) / 10.0 * cell_w, v0 + k * 0.2 * cell_h)
        uv[entry['tip']] = (u0 + 0.5 * cell_w, v0 + 0.985 * cell_h)
    return uv


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
    # 6b. The r40 mop: every lock re-planted onto a dense layout -- a fringe over
    # the forehead, chunky strands over the crown and temples, a short nape --
    # then the crown whorl and the hair's own atlas, for the maps the look draws.
    hair_positions = barber_locks(hair_positions, hair_triangles, positions, triangles)
    hair_positions = whorl_cap(hair_positions, hair_triangles)
    hair_uv_atlas = hair_uv(hair_positions, hair_triangles)
    hair_normals = welded_normals(hair_positions, hair_triangles)

    # 7. The eyes, the eyebrows and the mouth's interior, on the sculpted head.
    face_parts = build_face_parts(document, binary, positions, displacement, triangles)

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
            'TEXCOORD_0': (np.round(hair_uv_atlas * 65535).astype(np.uint16), 5123, 'VEC2', True),
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
    hair_bounds = (hair_arrays['POSITION'].min(axis=0), hair_arrays['POSITION'].max(axis=0))
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
        'hair_has_uv': 'TEXCOORD_0' in document['meshes'][HAIR_MESH]['primitives'][HAIR_PRIM]['attributes'],
        'hair_bbox_min': [float(v) for v in hair_bounds[0]],
        'hair_bbox_max': [float(v) for v in hair_bounds[1]],
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
        'hair_has_uv': True,
    }
    failed = []
    for name, expected in expectations.items():
        if measured[name] != expected:
            failed.append(f'{name} is {measured[name]}, expected {expected}')
    for name, pinned in (('hair_bbox_min', MOP_BBOX_MIN), ('hair_bbox_max', MOP_BBOX_MAX)):
        drift = float(np.abs(np.asarray(measured[name]) - pinned).max())
        if drift > 1e-4:
            failed.append(f'{name} drifted {drift * 1000:.2f} mm off the pinned V2 envelope')
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
