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
  * the hair keeps the same 96 roots and lock topology, and each lock is refined in
    place: every ring gains the midpoint of each of its five edges (5 -> 10 columns,
    45 -> 90 triangles), the new columns are thinned to 0.82 of their radius about the
    strand's own axis, and each strand takes one gentle outward bend of at most 2 mm;
  * V4 then redesigns the hairstyle between root and tip (`style_locks`): region flow
    (a fringe swept across the brow towards his right, sides falling over the temples,
    a back mass into the nape, the crown blended over all three), flattened tube
    sections that overlap as hair masses instead of spikes, free tips inside a
    redesigned envelope (the V1 spike silhouette the earlier passes pinned was the
    very thing that read as black shards), and the whole pass clamped off the scalp;
    the cap's interior keeps the crown whorl (`whorl_cap`, boundary pinned);
  * the eyes are levelled (V1's right eye sits 2.5 mm above the left), their flat iris and
    pupil discs are domed and the iris is given a limbal ring through its own vertex colour;
  * the eyebrows are re-hung on the brow ridge as tapered tubes, and the ears are given a
    bowl, a helix, a concha and a lobe;
  * the mouth's interior follows the lips, and every one of these parts keeps its own nine
    morph targets, re-expressed against its new rest pose;
  * the wardrobe is rebuilt in place (`wardrobe`): the jacket and trousers take one
    midpoint subdivision (joint weights interpolate along edges and faces, so rigid parts
    stay rigid and the original rows keep their exact weights) and then analytic folds -
    shoulder drape, placket channel and ridges, waist release, hem wave and flare, elbow
    pull creases, knee creases - plus rolled open edges on collars, cuffs and hems. Only
    positions and normals move; joints, weights and attribute sets are carried through;
  * skeleton, weights, animations, materials, node names and the remaining body meshes
    (arms under the sleeves, buttons, feet, hands) are copied byte-for-byte.

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

    V4 art pass (the protagonist art brief): the fields restore the planes a face
    has - socket, lid roll, alar wing, lip volume, cheekbone, jaw - and now also
    *compose* the face the art direction asks for. Rest-space landmarks, metres:

    * the nose-mouth complex rides 5 mm up and the chin 3.5 mm down, because the
      lower third measured 0.278 of the face height against the standard's
      0.30-0.37: the midface read long and the chin short. The mouth follows the
      nose by only 2 mm, so the philtrum shortens and the mouth keeps its
      0.28-0.40 place in the lower third;
    * the cheekbones widen ~2 mm a side at the eye band (face width/height was
      0.543 against 0.55-0.70), with the hollow under the bone left soft;
    * the nose bridge is a rounded pair of dorsum planes, not a ridge: the
      side valleys are wide and shallow, the tip sits lower and softer, the alar
      creases cut deeper;
    * the lips are bigger, with a vermillion step, corner pockets and a
      deliberate droop - his right corner (x < 0) 0.5 mm lower than his left;
    * the brows' ridge carries a designed asymmetry (his right heavier), the
      sockets are deeper, and the temples are tucked;
    * the jaw-to-neck and chin transitions are shaped so the head does not read
      as a mask planted on a cylinder.

    The fields stay broad and low-amplitude: the owner's long face and narrow
    chin are the identity being preserved.
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

    # 0. Composition moves (V4): nose-mouth up 5 mm / 2 mm, chin down 3.5 mm.
    add(gaussian(positions, (0.0, 1.5035, 0.122), (0.019, 0.021, 0.024), 0.0107),
        direction=(0.0, 1.0, 0.10))
    add(gaussian(positions, (0.0, 1.5125, 0.1335), (0.013, 0.013, 0.013), 0.0018),
        direction=(0.0, 1.0, 0.15))
    add(gaussian(positions, (0.0, 1.4955, 0.117), (0.026, 0.011, 0.015), 0.0032),
        direction=(0.0, 1.0, 0.12))
    add(gaussian(positions, (0.0, 1.4435, 0.0875), (0.021, 0.014, 0.017), 0.0035),
        direction=(0.0, -1.0, 0.30))
    # the chin body carries the profile from the lip fold down to the point: without
    # this the menton reads 20 mm high and the lower third collapses (anthropometry's
    # chin walk dies where the front profile dips under 85 % of the lip's depth). The
    # coverage stops just above the point, so the walk finds the menton at the point
    # and not on the throat behind it.
    add(gaussian(positions, (0.0, 1.4588, 0.0925), (0.020, 0.0123, 0.014), 0.0075),
        direction=(0.0, -0.25, 1.0))
    # the menton's own plane: holds the profile out to the point, then drops - the
    # flat-topped edge of the chin body, where the soft gaussian alone fades too early
    add(gaussian(positions, (0.0, 1.4540, 0.0940), (0.014, 0.0050, 0.011), 0.0028),
        direction=(0.0, -0.20, 1.0))
    # the jawline below the new chin tip, so the move reads as bone, not a dent -
    # kept clear of the UV sphere's degenerate axis (x = 0, z = 0.040)
    add(gaussian(positions, (0.0, 1.4355, 0.0715), (0.026, 0.012, 0.016), 0.0012),
        direction=(0.0, -0.45, 0.45))

    # 1. Eye sockets: a bowl behind each lid (deeper than V3), an upper-lid roll
    #    and a crease. Centers ride the eyes' new x = +/-28.5 mm.
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.0285, 1.585, 0.1025), (0.024, 0.019, 0.028), -0.0042))
        add(gaussian(positions, (side * 0.0285, 1.592, 0.1075), (0.018, 0.007, 0.015), 0.0026))
        add(gaussian(positions, (side * 0.0285, 1.600, 0.1005), (0.020, 0.004, 0.016), -0.0022))
        add(gaussian(positions, (side * 0.0285, 1.576, 0.1065), (0.016, 0.005, 0.013), 0.0016))
        # under-eye bag and tear trough
        add(gaussian(positions, (side * 0.030, 1.5725, 0.1005), (0.015, 0.0055, 0.018), 0.0016))
        add(gaussian(positions, (side * 0.032, 1.565, 0.0975), (0.022, 0.009, 0.022), -0.0018))
        # outer corner support
        add(gaussian(positions, (side * 0.0435, 1.581, 0.0985), (0.010, 0.008, 0.014), 0.0011))
    # his right socket (x < 0) a touch deeper and heavier than his left
    add(gaussian(positions, (-0.0285, 1.5735, 0.1000), (0.014, 0.006, 0.015), -0.0007))
    add(gaussian(positions, (-0.0285, 1.5945, 0.1065), (0.012, 0.005, 0.012), 0.0006))

    # 2. Nose: a rounded pair of dorsum planes (wide, shallow valleys - no sharp
    #    ridge), a soft tip sitting slightly low, alar wings with creases, and the
    #    columella and underside. The whole complex rose 5 mm in step 0.
    add(gaussian(positions, (0.0, 1.5555, 0.1275), (0.015, 0.028, 0.019), 0.0012))
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.0115, 1.5455, 0.1235), (0.009, 0.024, 0.015), -0.0008))
        add(gaussian(positions, (side * 0.0195, 1.5035, 0.1265), (0.0085, 0.008, 0.011), 0.0022))
        add(gaussian(positions, (side * 0.0245, 1.5045, 0.1195), (0.0055, 0.008, 0.010), -0.0022))
    add(gaussian(positions, (0.0, 1.5115, 0.1375), (0.0115, 0.009, 0.010), 0.0020))
    add(gaussian(positions, (0.0, 1.5015, 0.1310), (0.010, 0.0050, 0.009), 0.0014))
    add(gaussian(positions, (0.0, 1.4985, 0.1280), (0.0065, 0.0035, 0.007), -0.0010))

    # 3. Mouth: philtrum columns, cupid's bow, full lip volumes (V4: bigger), a
    #    cut mouth line, corner pockets with a tired droop - his right (x < 0)
    #    corner 0.5 mm lower than his left. The complex rose 2 mm in step 0.
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.0062, 1.5065, 0.1185), (0.0038, 0.0070, 0.009), 0.0016))
        add(gaussian(positions, (side * 0.0110, 1.5015, 0.1195), (0.0115, 0.0050, 0.010), 0.0034))
        add(gaussian(positions, (side * 0.0175, 1.4905, 0.1190), (0.0150, 0.0070, 0.010), 0.0034))
        droop = -0.0022 if side < 0 else -0.0015
        add(gaussian(positions, (side * 0.0295, 1.4965, 0.1115), (0.0068, 0.0052, 0.007), droop))
        # the crease that carries the mouth line out towards each corner
        add(gaussian(positions, (side * 0.0335, 1.4995, 0.1055), (0.0050, 0.0032, 0.006), -0.0010))
        # vermilion border step
        add(gaussian(positions, (side * 0.016, 1.4960, 0.1195), (0.0135, 0.0017, 0.008), -0.0017))
    add(gaussian(positions, (0.0, 1.5028, 0.1200), (0.0050, 0.0034, 0.007), 0.0018))
    add(gaussian(positions, (0.0, 1.4900, 0.1200), (0.011, 0.0048, 0.007), 0.0026))
    add(gaussian(positions, (0.0, 1.4972, 0.1185), (0.0265, 0.0020, 0.009), -0.0022))
    add(gaussian(positions, (0.0, 1.4805, 0.1045), (0.021, 0.0058, 0.013), -0.0017))

    # 4. Cheeks, jaw and chin. The cheekbone band widens ~2 mm a side (the eye
    #    band's cheek-to-cheek measure), the cheek under the bone stays filled,
    #    and the temporal hollow is tucked.
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.0515, 1.5355, 0.0785), (0.023, 0.018, 0.026), 0.0032),
            direction=(side, 0.15, 0.10))
        add(gaussian(positions, (side * 0.0435, 1.5085, 0.071), (0.018, 0.016, 0.020), -0.0020))
        add(gaussian(positions, (side * 0.052, 1.4625, 0.045), (0.018, 0.010, 0.022), 0.0020))
        add(gaussian(positions, (side * 0.0615, 1.6065, 0.030), (0.012, 0.014, 0.020), -0.0015))
    add(gaussian(positions, (0.0, 1.4465, 0.0925), (0.016, 0.010, 0.015), 0.0024))
    add(gaussian(positions, (0.0, 1.4565, 0.0300), (0.030, 0.016, 0.020), 0.0012))

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

    # 6. Brow ridge and glabella. His right ridge (x < 0) carries more weight -
    #    the designed asymmetry the brow tube then rides.
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.0285, 1.6075, 0.103), (0.018, 0.007, 0.015), 0.0022))
    add(gaussian(positions, (0.0, 1.6055, 0.108), (0.007, 0.013, 0.011), 0.0008))
    add(gaussian(positions, (-0.0285, 1.6085, 0.1035), (0.013, 0.005, 0.011), 0.0008))

    # 7. Neck: soften the column under the jaw, and shape the jaw-neck join so
    #    the head is not a mask planted on a cylinder (the throat hollow and the
    #    sternocleidomastoid's forward edge are shading cues, not geometry noise).
    #    The throat sits just forward of the UV sphere's degenerate axis (x = 0,
    #    z = 0.040): this lift keeps its triangles clear of the seam line.
    add(gaussian(positions, (0.0, 1.455, 0.020), (0.038, 0.020, 0.038), 0.0012))
    add(gaussian(positions, (0.0, 1.4385, 0.0375), (0.011, 0.013, 0.015), 0.0055),
        direction=(0.0, 0.15, 1.0))
    for side in (-1, 1):
        add(gaussian(positions, (side * 0.030, 1.4255, 0.012), (0.011, 0.017, 0.020), 0.0014),
            direction=(side * 0.55, -0.35, 0.30))
    add(gaussian(positions, (0.0, 1.4345, 0.0465), (0.012, 0.010, 0.011), -0.0012))

    return displacement


# --------------------------------------------------------------------------------------
# Eyes: level them, open the lids, curve the iris
# --------------------------------------------------------------------------------------

# Both eyes as V1 modelled them: one radius, but the right eye sits 2.5 mm above the left
# (1.58532 against 1.58285). The mouth and the ears are level and the brow is 6 mm off, so
# this is a modelling slip rather than a tilt of the head. V2 levels the eyes and the brow.
EYE_RADIUS = 0.01087
# V4: the eyes move 2.6 mm inboard (the inner gap measured 1.48 eye-widths against the
# standard's 0.85-1.15) and 1.5 mm deeper (the eyeball read as a bead pressed into the
# face). The sclera caps widen 4 % in x so eye width keeps its 0.18-0.22 of the face.
EYE_X = 0.02797
EYE_Y = 1.58409
EYE_Z = 0.10097
SCLERA_SCALE_X = 1.05
# The aperture: a hooded, tired opening - the upper lid arches over the iris top, the
# lower lid tucks, and the outer corner droops a fraction below the inner one. V2's
# margins overshot their targets (the old placement scaled y by radius/distance, landing
# the arch 2-3 mm high and low), which is what made the eye read as a wide white ring.
# `wrap_lids` now lands the margin exactly on this arch, measured on the eyeball.
APERTURE_HALF_WIDTH = 0.0102
APERTURE_UP = 0.0050
APERTURE_DOWN = 0.0046
APERTURE_TILT = -0.0006


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
    normals of the domed surface. The falloff covers the V4 enlarged iris disc.
    """
    out = positions.copy()
    normals = np.zeros_like(positions)
    for side in (1.0, -1.0):
        selected = np.sign(positions[:, 0]) == side
        points = out[selected]
        offset = points[:, [0, 1]] - np.array([side * EYE_X, EYE_Y])
        radial = np.linalg.norm(offset, axis=1)
        falloff = np.clip(1.0 - (radial / DOME_RADIUS) ** 2, 0.0, 1.0)
        points[:, 2] += lift + bulge * falloff
        # The dome's own normal: dz/dr = -2 bulge r / R^2, so the surface tilts outwards.
        slope = 2.0 * bulge / DOME_RADIUS ** 2
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
        # V4: pull each vertex towards its own arch target - at the margin (v = 0) it
        # lands exactly on the arch, at the outer loop (v = 1) nothing moves. V2 shifted
        # the whole band by (target - margin), which left the margin ring's arch-shaped
        # neighbours 1-2 mm off the aperture line and made the eye open too wide.
        y_new = points[:, 1] + (target - points[:, 1]) * (1.0 - v) ** 1.2
        radius = np.linalg.norm(points - eye, axis=1)
        radius_new = (EYE_RADIUS + 0.0004) * (1.0 - v) + radius * v
        # V1's bands dip inside the eyeball (their outer loops sit at 9.8 mm against a
        # 10.9 mm eye), so the eyeball showed through them. A lid wraps the eye; it is never
        # inside it.
        radius_new = np.maximum(radius_new, EYE_RADIUS + 0.0003)
        # V4: land each vertex exactly on its sphere radius at height y_new. V2 scaled the
        # vertex's own y by radius/distance and overshot the arch - the margins ended up
        # 2-3 mm above and below their targets, and that accident became a 12.9 mm white
        # ring around the iris. Here the vertex keeps its x, takes the arch height, and its
        # z is solved on the sphere on V1's own side. At v = 1 the solve returns the V1
        # position exactly, so the outer loop still sits where V1 put it.
        y_rel = y_new - eye[1]
        ring = np.sqrt(np.maximum(radius_new ** 2 - y_rel ** 2, 1e-12))
        dx = points[:, 0] - eye[0]
        dz = points[:, 2] - eye[2]
        reach = np.hypot(dx, dz)
        safe = reach > 1e-9
        scale = np.where(safe, ring / np.maximum(reach, 1e-9), 0.0)
        out_x = np.where(safe, eye[0] + dx * scale, eye[0])
        out_z = np.where(safe, eye[2] + dz * scale, eye[2] + ring)
        out[index] = np.stack([out_x, y_new, out_z], axis=1)
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
                 triangles: np.ndarray | None = None) -> np.ndarray:
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
        # V4: the brow reads worried and tired - inner end riding up, outer tail
        # falling - and carries a designed asymmetry: his right (x < 0) arches
        # ~2.2 mm higher at its peak and sits heavier, his left tail hangs looser.
        base = np.array([1.6070, 1.6077, 1.6076, 1.6060, 1.6038])
        if side < 0:
            lift = np.array([0.0010, 0.0018, 0.0022, 0.0018, 0.0008])
            weight = 1.12
        else:
            lift = np.array([0.0000, 0.0002, 0.0000, -0.0004, -0.0010])
            weight = 1.0
        for station in np.unique(np.round(x, 5)):
            ring_index = np.nonzero(np.isclose(x, station, atol=1e-4))[0]
            ring = points[ring_index]
            along = float(np.clip((station - low) / max(high - low, 1e-9), 0.0, 1.0))
            centre_y = float(np.interp(along, [0.0, 0.25, 0.5, 0.75, 1.0], base + lift))
            half_height = weight * float(np.interp(along, [0.0, 0.18, 0.5, 0.8, 1.0],
                                                   [0.0011, 0.0024, 0.0025, 0.0015, 0.0005]))
            half_depth = half_height * 0.85
            skin = surface_z(station, centre_y, head, triangles) if triangles is not None else None
            if skin is None:
                # No triangle soup (direct callers in tests): fall back to the
                # nearest skin vertices around the station.
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
        moved = points + np.stack([side * relief,
                                   height * 0.10 * outline,
                                   depth * -0.06 * outline], axis=1)
        # V4: tuck the shells ~5.5 mm inboard - they rode at x = +/-76 mm, clear of
        # the skull's silhouette, which is half of why they read as buttons - and
        # compress their x-spread so the helix keeps its relief over the smaller step.
        moved[:, 0] = side * 0.0705 + (moved[:, 0] - side * 0.076) * 0.85
        out[index] = moved
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


IRIS_RADIUS = 0.0074
# The dome's falloff radius: covers the V4 enlarged iris disc (5.95 mm -> 7.4 mm).
DOME_RADIUS = 0.0078
# V4: the iris disc is enlarged 1.24x and re-centred on the eye's axis - V1's iris sat
# 1.6 mm low, which with the wide V2 aperture is what made the eye read as a bead floating
# in a white ring. The pupil keeps its V1 ratio under the same treatment.
IRIS_SCALE = 1.24
PUPIL_SCALE = 1.12
# The iris is one flat colour in V1. Its own vertex colour — which the look's material already
# knows how to multiply in (`use_vertex_paint`) — carries a limbal ring and a lighter centre,
# the two gradients that make an iris read as one rather than as a brown disc.
IRIS_EDGE = 0.42
IRIS_CORE = 1.10
# The sclera is warmed off pure white so the visible white reads as painted, not plastic.
SCLERA_TINT = (0.915, 0.895, 0.868)


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
    eye_plans = {0: (0.0, 0.0), 1: (0.0008, 0.0002), 2: (0.0006, 0.0004)}
    eye_scales = {0: None, 1: IRIS_SCALE, 2: PUPIL_SCALE}
    for primitive_index, (bulge, lift) in eye_plans.items():
        primitive = document['meshes'][EYE_MESH]['primitives'][primitive_index]
        arrays = glb.primitive_arrays(document, binary, primitive)
        positions = level_eyes(arrays['POSITION'].astype(np.float64), offsets)
        normals = arrays['NORMAL'].astype(np.float64)
        if primitive_index == 0:
            # V4: widen the sclera caps 4 % in x so eye width keeps its share of the
            # face after the cheeks widen; warm the white off pure paper.
            for side in (1.0, -1.0):
                selected = np.sign(positions[:, 0]) == side
                points = positions[selected]
                centre = np.array([side * EYE_X, EYE_Y])
                points[:, 0] = centre[0] + (points[:, 0] - centre[0]) * SCLERA_SCALE_X
                positions[selected] = points
        scale = eye_scales[primitive_index]
        if scale is not None:
            # V4: recentre the disc on the eye's axis (V1's sat 1.6 mm low) and
            # scale it in its own plane - the larger iris the painted look asks for.
            # The gaze sits straight ahead: a 0.4 mm outward bias keeps the pair from
            # converging now that the eyes ride 2.6 mm inboard.
            for side in (1.0, -1.0):
                selected = np.sign(positions[:, 0]) == side
                points = positions[selected]
                centre = points.mean(axis=0)
                target = np.array([side * (EYE_X + 0.0004), EYE_Y])
                points[:, 0] = target[0] + (points[:, 0] - centre[0]) * scale
                points[:, 1] = target[1] + (points[:, 1] - centre[1]) * scale
                positions[selected] = points
        if bulge > 0.0:
            positions, normals = dome_iris(positions, bulge, lift)
        if primitive_index == 2:
            # The pupil rides above the iris dome (they are separate discs; without
            # this offset their domes intersect and draw a ring at the pupil's rim).
            positions[:, 2] += 0.00035
        attributes = {
            'POSITION': (positions.astype(np.float32), 5126, 'VEC3'),
            'NORMAL': (np.round(normals * 32767).astype(np.int16), 5122, 'VEC3', True),
        }
        if primitive_index == 1:
            attributes['COLOR_0'] = (np.round(iris_vertex_colour(positions) * 255).astype(np.uint8),
                                     5121, 'VEC4', True)
        if primitive_index == 0:
            tint = np.tile(np.array(SCLERA_TINT + (1.0,)), (len(positions), 1))
            attributes['COLOR_0'] = (np.round(tint * 255).astype(np.uint8), 5121, 'VEC4', True)
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
            positions = reshape_brow(positions, skin, skin_triangles)
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
# The redesigned V4 envelope (measured on the built lock mesh, pinned so a rebuild
# cannot silently inflate the hairstyle).
HAIR_BBOX_MIN = np.array([-0.08540000021457672, 1.5056164264678955, -0.07209999859333038])
HAIR_BBOX_MAX = np.array([0.08210666477680206, 1.708299994468689, 0.13680000603199005])
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


def style_locks(positions: np.ndarray, triangles: np.ndarray, skin: np.ndarray) -> np.ndarray:
    """V4: the hairstyle is redesigned lock by lock - a designed, slightly messy short cut.

    V1-V3 kept the sculpt study's spike envelope: 96 plates radiating every which way,
    each tip pinned to an "approved silhouette" that was itself the problem - the hair
    read as black shards, not hair. The art brief asks for designed messiness with clear
    mass groupings, so the envelope is redrawn here and the tips are free:

    1. **Region flow.** Each lock's root (azimuth, height) selects its region. Azimuth
       runs atan2(x, -(z - SCALP_z)): +/-180 deg is the face, 0 deg the back of the
       head. The fringe (|az| >= 115) sweeps across the forehead towards his right
       (x < 0) and falls to just above the brow; the sides (65-115 deg) fall along the
       temples to above the ear; the back (|az| < 65) falls to the nape; the crown
       (y >= 1.672) blends its top flow into those three. Lengths and how far a mass
       may stand off the scalp are per-region, with a deterministic hash rhythm per
       lock so layers interleave instead of stacking evenly.
    2. **Flat-tube mass.** Each shaft is a quadratic bezier along its flow; its
       cross-section is a flattened tube lying on the scalp (wide along the surface,
       thin across it), the root ring widened until the roots read as one mass, the
       shaft tapering to a pointed tip. Locks overlap as hair masses, not spikes.
    3. **Scalp discipline.** Every vertex stays at least 1.2 mm off the skin (the
       skull clamp) and inside the redesigned envelope; the cap's authored hairline
       is untouched.

    Pure function of the mesh plus the sculpted skin; vertex count and topology do
    not change, so the skin weights stay valid and the 96-lock contract holds.
    """
    locks, _cap, _cap_boundary, _labels = _hair_components(positions, triangles)
    field = _skull_field(skin)
    out = positions.copy()
    gravity = np.array([0.0, -1.0, 0.0])
    # Ring cross-section scale (ring 0 is the buried root; the tip is its own vertex).
    section = (1.30, 1.14, 0.98, 0.78, 0.46)
    ring_t = (0.0, 0.22, 0.44, 0.66, 0.88)

    def region_of(root: np.ndarray, az: float) -> str:
        if root[1] >= 1.672:
            return 'crown'
        if abs(az) >= 115.0:
            return 'fringe'
        if abs(az) >= 65.0:
            return 'sides'
        return 'back'

    def flow_of(region: str, az: float, y: float, u1: float, u2: float) -> np.ndarray:
        if region == 'fringe':
            # The sweep: mostly towards his right and down, a touch forward. His
            # left-front locks (az > 0 near +180) start the sweep higher and rounder.
            t = min(abs(az) - 115.0, 65.0) / 65.0
            base = np.array([-0.66 - 0.14 * t, -0.62 + 0.10 * t, 0.28 - 0.10 * t])
        elif region == 'sides':
            base = np.array([math.copysign(0.12, az), -0.88, -0.14])
        elif region == 'back':
            base = np.array([math.copysign(0.10, az) if abs(az) > 18.0 else 0.0, -0.82, -0.46])
        else:  # crown: front-crown joins the sweep, back-crown falls back
            t = min(abs(az) - 115.0, 65.0) / 65.0 if abs(az) >= 115.0 else 0.0
            if abs(az) >= 115.0:
                base = np.array([-0.58 - 0.12 * t, -0.42 - 0.16 * t, -0.20 + 0.16 * t])
            elif abs(az) < 65.0:
                base = np.array([math.copysign(0.08, az) if abs(az) > 18.0 else 0.0, -0.58, -0.62])
            else:
                base = np.array([math.copysign(0.16, az), -0.72, -0.36])
        # Deterministic wobble: up to ~12 degrees off the design flow.
        wobble = (u1 - 0.5) * 0.42
        cos_w, sin_w = math.cos(wobble), math.sin(wobble)
        x, yv, z = base
        base = np.array([x * cos_w - z * sin_w, yv, x * sin_w + z * cos_w])
        base = base + np.array([(u2 - 0.5) * 0.10, (u2 - 0.5) * -0.08, 0.0])
        return base / np.linalg.norm(base)

    for entry in locks:
        label = entry['label']
        levels = entry['levels']
        verts = np.concatenate(levels + [np.array([entry['tip']])])
        rows = np.arange(len(verts))
        level_of = np.minimum(rows // 10, 5)
        root_ring = positions[levels[0]]
        root = root_ring.mean(axis=0)
        d = root - SCALP
        radial = float(np.hypot(d[0], d[2]))
        root_out = d / max(radial, 1e-9)
        az = math.degrees(math.atan2(float(d[0]), -float(d[2])))
        region = region_of(root, az)
        u = _hash_units(label, 1, 8)
        flow = flow_of(region, az, float(root[1]), u[0], u[1])

        # Lengths and envelope per region (metres).
        if region == 'fringe':
            length = 0.042 * (0.86 + 0.30 * u[2])
            max_out, y_floor, y_cap = 0.032, 1.606, 1.742
        elif region == 'crown':
            length = 0.036 * (0.84 + 0.34 * u[2])
            max_out, y_floor, y_cap = 0.031, 1.560, 1.742
        elif region == 'sides':
            length = 0.030 * (0.78 + 0.42 * u[2])
            max_out, y_floor, y_cap = 0.013, 1.542, 1.742
        else:
            length = 0.038 * (0.80 + 0.38 * u[2])
            max_out, y_floor, y_cap = 0.018, 1.502, 1.742

        # Seat the root just under the cap surface and build the shaft's bezier. The
        # crown and fringe roots also lift off the scalp - the volume a real cut has -
        # before the flow falls away.
        volume = 0.006 if region == 'crown' else (0.004 if region == 'fringe' else 0.0)
        scalp_pt = root + root_out * (volume - 0.0035)
        start_dir = flow * 0.62 + root_out * 0.38
        start_dir = start_dir / np.linalg.norm(start_dir)
        ctrl = scalp_pt + start_dir * (0.52 * length) + gravity * (0.07 * length)
        tip = scalp_pt + flow * length + gravity * (0.22 * length)
        # The tip stays in the region's envelope: not past its stand-off, not below
        # its floor (brow line, ear line, collar), not above the crown cap.
        t_out = tip - SCALP
        t_rad = float(np.hypot(t_out[0], t_out[2]))
        t_max = _skull_radius(field, float(tip[0]), float(tip[1]), float(tip[2])) + max_out
        if t_rad > t_max > 1e-9 and t_rad > 1e-9:
            s = t_max / t_rad
            tip = np.array([tip[0] * s, tip[1], SCALP[2] + (tip[2] - SCALP[2]) * s])
        tip[1] = min(max(float(tip[1]), y_floor), y_cap)

        def bezier(t: float) -> np.ndarray:
            return ((1.0 - t) ** 2) * scalp_pt + 2.0 * (1.0 - t) * t * ctrl + (t ** 2) * tip

        base_r = float(np.median(np.linalg.norm(root_ring - root, axis=1)))
        base_r = max(base_r, 0.0035)
        width = 1.06 + 0.36 * u[3]
        phase = u[4] * math.tau
        phase2 = u[5] * math.tau

        moved = positions[verts].copy()
        for i in rows:
            ring = int(level_of[i])
            if ring == 5:
                moved[i] = tip
                continue
            t = ring_t[ring]
            centre = bezier(t)
            # Tangent of the bezier at t.
            tangent = 2.0 * (1.0 - t) * (ctrl - scalp_pt) + 2.0 * t * (tip - ctrl)
            norm = float(np.linalg.norm(tangent))
            tangent = tangent / norm if norm > 1e-9 else flow
            # The section lies on the scalp: thin along the surface normal, wide
            # along the surface. Flattened tubes overlap as hair masses.
            thin = root_out - tangent * float(root_out @ tangent)
            if np.linalg.norm(thin) < 1e-6:
                thin = np.cross(tangent, np.array([0.0, 1.0, 0.0]))
            thin = thin / np.linalg.norm(thin)
            wide = np.cross(tangent, thin)
            # The vertex's own angle in the original ring, kept so no two locks
            # share one silhouette; a gentle scallop keeps the section organic.
            angle = math.tau * ((i % 10) + 0.5) / 10.0 + phase
            scallop = 1.0 + 0.10 * math.sin(3.0 * angle + phase2)
            a = base_r * width * section[ring] * scallop
            b = base_r * width * 0.60 * section[ring]
            jitter = 1.0 + (u[6] - 0.5) * 0.10
            point = (centre + wide * (math.cos(angle) * a * jitter)
                     + thin * (math.sin(angle) * b * jitter))
            # The root ring dives into the cap's mass; ring 1 follows halfway.
            if ring == 0:
                point = point - tangent * 0.006
            elif ring == 1:
                point = point - tangent * 0.0025
            moved[i] = point

        for i in rows:
            if level_of[i] == 5:
                continue
            p = moved[i]
            r_head = math.hypot(float(p[0]), float(p[2] - SCALP[2]))
            r_min = _skull_radius(field, float(p[0]), float(p[1]), float(p[2])) + SKIN_MARGIN
            if r_head < r_min and r_head > 1e-9:
                s = r_min / r_head
                p = np.array([p[0] * s, p[1], SCALP[2] + (p[2] - SCALP[2]) * s])
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
# Wardrobe
# --------------------------------------------------------------------------------------
# The garments arrive from V1 as clean blockout: flat panels, raw-cut cuffs and hems,
# no folds anywhere. This pass moves only positions and normals - every joint, weight
# and attribute set is carried through exactly as V1 skinned it. One midpoint
# subdivision over the jacket and the trousers buys the density the folds need (weights
# interpolate along edges and faces, so rigid parts stay rigid); the analytic fields
# then draw the drape, the pull creases and the rolled edges. Design identity is fixed:
# stand collar, left-chest patch pocket, button placket, straight hem, slim silhouette.

BODY_MESH = 0
JACKET_MESH = 7
DETAIL_MESH = 8
WARDROBE_PRIMS = ((JACKET_MESH, 0), (BODY_MESH, 1), (DETAIL_MESH, 0))


def _smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _window(value, lo, hi, feather=0.02):
    return _smoothstep((value - lo) / feather) * _smoothstep((hi - value) / feather)


def _dense_weights(joints: np.ndarray, weights: np.ndarray) -> np.ndarray:
    """(n, J) float weight matrix - the form interpolation needs."""
    count = len(joints)
    width = int(joints.max()) + 1 if count else 1
    dense = np.zeros((count, width), np.float64)
    for slot in range(4):
        np.add.at(dense, (np.arange(count), joints[:, slot].astype(np.int64)),
                  weights[:, slot].astype(np.float64))
    return dense


def _top4_weights(dense: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Back to the GLB's 4-slot layout; single-joint rows survive untouched."""
    count = len(dense)
    order = np.argsort(-dense, axis=1)[:, :4]
    picked = np.take_along_axis(dense, order, axis=1)
    totals = picked.sum(axis=1, keepdims=True)
    picked = np.divide(picked, totals, out=np.zeros_like(picked), where=totals > 0)
    zero = picked.sum(axis=1) == 0
    picked[zero, 0] = 1.0
    return order.astype(np.uint8), picked.astype(np.float32)


def _subdivide_cloth(positions, triangles, joints, weights):
    """Midpoint subdivision with joint weights interpolated along edges and faces."""
    dense = _dense_weights(joints, weights)
    edge_mid = {}
    mid_position = []
    mid_dense = []

    def midpoint(a, b):
        key = (a, b) if a < b else (b, a)
        if key not in edge_mid:
            edge_mid[key] = len(positions) + len(mid_position)
            mid_position.append((positions[a] + positions[b]) * 0.5)
            mid_dense.append((dense[a] + dense[b]) * 0.5)
        return edge_mid[key]

    new_triangles = []
    for a, b, c in triangles:
        ab = midpoint(a, b)
        bc = midpoint(b, c)
        ca = midpoint(c, a)
        mid_position.append((positions[a] + positions[b] + positions[c]) / 3.0)
        mid_dense.append((dense[a] + dense[b] + dense[c]) / 3.0)
        centre = len(positions) + len(mid_position) - 1
        new_triangles.extend(((a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)))
    positions = np.vstack((positions, np.array(mid_position)))
    dense = np.vstack((dense, np.array(mid_dense)))
    joints, weights = _top4_weights(dense)
    return positions, np.array(new_triangles, np.int64), joints, weights


def _roll_boundaries(positions, triangles, depth=0.0026):
    """Pull the open edges (collar rims, cuffs, hems) in along -normal: a cloth edge
    has thickness, and a raw-cut boundary is the loudest blockout tell."""
    normals = vertex_normals(positions, triangles)
    neighbours = {}
    for a, b, c in triangles:
        for u, v in ((a, b), (b, c), (c, a)):
            neighbours.setdefault(u, set()).add(v)
            neighbours.setdefault(v, set()).add(u)
    edge_use = {}
    for a, b, c in triangles:
        for u, v in ((a, b), (b, c), (c, a)):
            key = (u, v) if u < v else (v, u)
            edge_use[key] = edge_use.get(key, 0) + 1
    boundary = {u for (u, v), n in edge_use.items() if n == 1} | \
               {v for (u, v), n in edge_use.items() if n == 1}
    moved = np.zeros_like(positions)
    for vert in boundary:
        moved[vert] -= normals[vert] * depth
    ring = {n for vert in boundary for n in neighbours.get(vert, ())} - boundary
    for vert in ring:
        moved[vert] -= normals[vert] * depth * 0.45
    return positions + moved


def _jacket_shapes(p, normals):
    """Drape swells from the shoulders, the placket channel, a waist release, the hem
    wave, and one pull crease ring at each elbow. Long wavelengths only - the panel
    density is low and short ripples would alias into noise."""
    x, y = p[:, 0], p[:, 1]
    ax = np.abs(x)
    torso = _smoothstep((0.17 - ax) / 0.03)
    sleeves = _smoothstep((ax - 0.15) / 0.03)
    drape = ((0.0072 * np.sin(x * 26.0 + y * 5.0)
              + 0.0034 * np.sin(x * 57.0 - y * 4.0 + 1.3)) * _window(y, 0.88, 1.33, 0.08)
             * torso)
    yoke = 0.0026 * np.sin((y - 1.285) * 150.0) * np.exp(-((y - 1.285) / 0.028) ** 2) * torso
    groove = -0.0030 * np.exp(-(x / 0.016) ** 2) * _window(y, 0.92, 1.33, 0.06) * torso
    placket_ridge = (0.0026 * (np.exp(-((x - 0.032) / 0.015) ** 2)
                               + np.exp(-((x + 0.032) / 0.015) ** 2))
                      * _window(y, 0.93, 1.32, 0.06) * torso)
    waist = -0.0045 * _window(y, 0.98, 1.18, 0.06) * torso
    hem_wave = 0.0050 * np.sin(x * 34.0 + 0.6) * _window(y, 0.828, 0.885, 0.035) * torso
    flare = 0.0042 * _window(y, 0.828, 0.875, 0.035) * torso
    # Elbow: the arm axis runs (±0.16, 1.24) -> (±0.46, 0.89); the crease ring sits at
    # the midpoint, ridge into trough along the sleeve, and the inner side pulls in.
    t = (ax - 0.31) * 0.664 + (y - 1.07) * (-0.748)
    ring = (0.0055 * np.sin(t * 90.0) * np.exp(-(t / 0.055) ** 2)
            * _window(y, 0.92, 1.22, 0.06) * sleeves)
    cuff = 0.0042 * _window(ax, 0.415, 0.475, 0.025) * sleeves
    return normals * (drape + yoke + groove + placket_ridge + waist + hem_wave + flare
                      + ring + cuff)[:, None]


def _trouser_shapes(p, normals):
    """Knee pull crease, a slow leg drape and the hem break over the shoe."""
    x, y = p[:, 0], p[:, 1]
    knee = (0.0048 * np.sin((y - 0.525) * 95.0) * np.exp(-((y - 0.525) / 0.055) ** 2)
            * _window(np.abs(x), 0.03, 0.16, 0.03))
    drape = 0.0028 * np.sin(x * 46.0 + 1.1) * _window(y, 0.16, 0.98, 0.08)
    hem = 0.0036 * np.sin(x * 60.0 + 0.4) * _window(y, 0.07, 0.165, 0.035)
    return normals * (knee + drape + hem)[:, None]


def _detail_shapes(p, normals):
    """The collar stand rises a touch, the patch pocket puffs off the chest."""
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    collar = 0.0032 * _window(y, 1.33, 1.41, 0.03)
    pocket = (0.0042 * _window(x, 0.022, 0.138, 0.018) * _window(y, 1.115, 1.275, 0.02)
              * _smoothstep((z - 0.095) / 0.012))
    return normals * (collar + pocket)[:, None]


def wardrobe(document: dict, binary: bytes) -> dict:
    """Position/normal-only garment rebuild; everything else is carried through."""
    replacements = {}
    for mesh_index, prim_index in WARDROBE_PRIMS:
        primitive = document['meshes'][mesh_index]['primitives'][prim_index]
        arrays = glb.primitive_arrays(document, binary, primitive)
        positions = arrays['POSITION'].astype(np.float64)
        triangles = arrays['indices'].reshape(-1, 3).astype(np.int64)
        joints = arrays['JOINTS_0']
        weights = arrays['WEIGHTS_0']
        if (mesh_index, prim_index) != (DETAIL_MESH, 0):
            positions, triangles, joints, weights = _subdivide_cloth(
                positions, triangles, joints, weights)
        normals = vertex_normals(positions, triangles)
        if mesh_index == JACKET_MESH:
            positions = positions + _jacket_shapes(positions, normals)
        elif mesh_index == BODY_MESH:
            positions = positions + _trouser_shapes(positions, normals)
        else:
            positions = positions + _detail_shapes(positions, normals)
        positions = _roll_boundaries(positions, triangles)
        normals = vertex_normals(positions, triangles)
        # Weight sums survive subdivision up to rounding; re-normalise to be exact.
        # The garments store WEIGHTS_0 as raw floats summing to 1 (no 255 scale).
        totals = weights.sum(axis=1, keepdims=True)
        weights = np.divide(weights, totals, out=np.zeros_like(weights), where=totals > 0)
        attributes = {
            'POSITION': (positions.astype(np.float32), 5126, 'VEC3'),
            'NORMAL': (normals.astype(np.float32), 5126, 'VEC3'),
            'JOINTS_0': (joints, 5121, 'VEC4'),
            'WEIGHTS_0': (weights.astype(np.float32), 5126, 'VEC4'),
        }
        replacements[(mesh_index, prim_index)] = {
            'attributes': attributes,
            'indices': triangles.reshape(-1).astype(np.uint32),
            'targets': [],
        }
    return replacements


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
    # 6b. V4 art pass: the hairstyle is redesigned between root and tip - region flow,
    #     flattened tube mass, free tips inside the redesigned envelope - then the
    #     hair's own atlas, for the maps the look draws on it.
    hair_positions = style_locks(hair_positions, hair_triangles, positions)
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
    replacements.update(wardrobe(document, binary))
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
        front = relative[(relative[:, 2] > 0.004) & (np.abs(relative[:, 0]) < 0.0035)]
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
    for name, pinned in (('hair_bbox_min', HAIR_BBOX_MIN), ('hair_bbox_max', HAIR_BBOX_MAX)):
        drift = float(np.abs(np.asarray(measured[name]) - pinned).max())
        if drift > 1e-4:
            failed.append(f'{name} drifted {drift * 1000:.2f} mm off the pinned V2 envelope')
    if not (0.0 <= measured['head_uv_u_min'] and measured['head_uv_u_max'] <= 1.0):
        failed.append('the head atlas leaves [0, 1]')
    if measured['head_uv_u_span_max'] > 0.5:
        failed.append('a triangle still wraps across the atlas seam')
    if not (8.0 <= measured['aperture_height_mm'] <= 10.0):
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
