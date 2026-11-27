#!/usr/bin/env python3
"""Build the runtime model of substitute teacher N from the owner's Blender export.

    python3 tools/prepare_teacher_n.py            # writes assets/models/teacher-n/teacher-n.glb
    python3 tools/prepare_teacher_n.py --check    # rebuilds in memory, compares with the file
    python3 tools/prepare_teacher_n.py --report   # prints what the source and the result hold

The source is the owner's export, kept byte for byte at
`art/character_models/teacher-n/teacher-n_source.glb` (Khronos glTF Blender I/O v5.2.41,
2,990,912 bytes). It is 2.9 MiB and carries things the game never draws, so it is over the
model budget (`tools/model_library.py`: 1.5 MiB hard) and cannot ship as it is. This script
is the only thing that turns it into the runtime file, and every step is listed here so a
re-export from Blender can go through the same pass:

1. **The stage floor goes.** `ST_Stage_Floor` is a 6 x 6 m preview plane (mesh
   `ST_Stage_Floor_mesh`, material `M_ST_Stage`) under the character. The classroom has
   its own floor; a second one would z-fight with it.
2. **The fifteen facial blend shapes go** (nine on `ST_Head_Skin`, three on each eyebrow;
   nine distinct names, `Eye_Blink_L` ... `Jaw_Open`).
   Nothing in the game drives a blend shape -- there is no facial animation in this
   prototype (AGENTS.md) -- and their position and normal deltas were 684 KiB, the
   largest single item in the file. The source keeps them.
3. **Bone weights are stored as normalized unsigned bytes** instead of 32-bit floats
   (core glTF 2.0, section 3.7.3.1). Each vertex is re-normalised so its four weights add up
   to exactly 255/255: each weight is rounded to the nearest 1/255 and the heaviest one
   absorbs what the others' rounding left over. 15,034 vertices blend across bones; the
   largest change to any weight is 0.005 (measured), on a 0..1 scale.
4. **Two over-tessellated parts are simplified, nothing else**: the head skin
   (`ST_Head_Skin` / `M_ST_Skin`, 18,790 triangles) and the two eyeballs
   (`ST_Eye_L|R` / `M_ST_Sclera`, 3,216 triangles each for a 2.5 cm sphere). meshoptimizer
   collapses edges onto *existing* vertices only, so every vertex that remains keeps its
   exact position, normal, joints and weights; open borders (the neck, the eye sockets,
   where lips and lashes meet the skin) are locked, so no crack can open against a
   neighbouring part. The error bound is absolute, 0.2 mm, and the collapse metric weighs
   the normal and the per-bone skin weights too, so a collapse that would bend shading or
   change how the surface deforms costs as much as one that moves it. Measured against the
   source surface (every source vertex against the simplified triangles): at most 0.32 mm
   away on the head and the scleras alike, on average 0.05 mm on the head and 0.12 mm on
   the scleras, on a figure 1.65 m tall.
   Every other mesh -- clothes, hair, hands, ears, mouth, the irises -- is untouched.
5. **Animation channels that never move are dropped.** The four clips key translation,
   rotation and scale on all 16 bones; only 1-3 rotation channels per clip change. A
   channel whose every key equals the rest pose (to 1e-6 per component) *is* the rest pose;
   Godot's importer would drop it anyway (`animation/remove_immutable_tracks`). Anything that
   moves at all -- the 0.5 degree breath on the neck included -- is copied untouched.
6. **Materials keep their names and colours.** Godot 4.7.2 does not import
   `KHR_materials_sheen`, `KHR_materials_clearcoat` or `KHR_materials_specular` (they are
   not in `GLTFDocument.get_supported_gltf_extensions()`), so the file stops declaring them
   rather than carrying data that silently does nothing. Six roughness values change, moved
   towards Q's -- the project's other owner-authored character (cloth, hair and brows 0.85,
   skin 0.8, eyes, lips and teeth 0.35) -- and the shoes from patent to leather: see
   `ROUGHNESS`. Metallic stays 0 everywhere and no base colour changes.

7. **Owner-authorised model refinement (geometry revision 1).** The immutable original
   stays intact. `character_geometry.py` replaces the broken rod-like hands with tapered
   palms and five unequal, relaxed digits, welded into a single closed surface per hand.
   New wrist weights blend the hand with its existing forearm (the original hand weights
   are NOT copied). It locally softens the supplied bob's corners and offsets its hem,
   adds rolled cuffs, makes millimetric jaw/cheek asymmetry edits, and reverses the six
   inward eye surfaces' winding and normals, removing production two-sided culling.

8. **Facial shape keys that have a job are kept (geometry revision 3).** Step 2 dropped
   all fifteen, which is why she had a dead face: `CharacterLookApplier` can only blink
   when `look.blink_shapes` names a shape the mesh carries, and N's listed none. The two
   blinks are kept (a blink displaces 130 of 9,469 head vertices -- 2 KiB as sparse data,
   which is how the owner's export already stores it), together with `Brow_Compress`,
   `Frown` and `Mouth_Close`, which are the shapes her resting expression is set from.
   The other ten stay out.

9. **The resting face is sculpted (geometry revision 3, `character_geometry.teacher_expression`).**
   Measured against the proportions in `docs/CHARACTER_MODEL_STANDARD.md`, the source face
   was anatomically sound -- eye line 0.52 of face height, nose base 0.249, jaw 0.72 of the
   cranium width -- except that the eyes were 24.3 mm wide on a 148 mm face (5.4 eyes
   across where the count should be 5) and the face carried no expression at all. So the
   change is anatomical first: the upper lid is brought down 5.5 mm over the pupil and
   thickened 2.6 mm above the lash line, which turns a hole in the head into a heavy-lidded
   eye; the aperture opens 2.2 mm sideways at the corners; the brows tilt (inner ends up
   3.8 mm, tails down), which is the skew that reads as worry; the mouth corners drop 3 mm
   and the mouth line shortens; the jaw angle narrows 9 % and the cheeks flatten. Skin
   weights, topology, vertex count and the jaw/eye/lip attachment surfaces are untouched,
   and every kept shape key follows the same warp, so a blink moves the lid that moved.
   It does not add bones or claim articulated fingers. Joint names/rest transforms,
   inverse binds, the other skin weights and the four authored loops are kept.
   Steps 1-6 describe the original preparation, not an unchanged-geometry claim for this
   new revision. The current regeneration and deformation checks are in the PR.
8. **Geometry revision 2.** Selectively replace the floating fringe tufts and loose
   neck rings, leaving the source bob shell, torso and limb weights. Sculpt eye/lip
   planes together; build sewn collar leaves, a knit welt and open cuff rims. The
   smaller welded hand mesh has a bevel, a knuckle arch and digit-specific relaxed curl.
9. **Blender head layer.** After the original geometry preparation, a pinned indexed
   edit refines the face and tucks the existing bob clear of the cheek and ear. No changes
   to binding indices or animation payloads. See `art/character_models/sculpt/README.md`.

No node is rotated, moved or scaled. The model faces -Z, which is what
`docs/ASSET_PIPELINE.md` section 1 asks a new export to do, and stands with its soles on the
origin.

Requires numpy and meshoptimizer 0.2.30a0 (which bundles meshoptimizer 0.22); both are
build-time only; the game does not need them. Tooling CI installs the pinned requirements
and checks this script's deterministic output, alongside the model-library/import tests. The output is
deterministic for that version -- two runs write the same bytes, which `--check` relies on.
The Python package has no wheel and builds from source, so it needs the CPython headers
(`Python.h`); where the interpreter ships without them, point `CFLAGS` and `CPPFLAGS` at a
copy of the matching CPython `Include/` directory plus its `pyconfig.h`. The package's own
`simplify_with_attributes()` declares no `argtypes` and fails on 64-bit sizes, so this
script calls the C function directly through ctypes with the signature declared below.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import struct
import sys

import numpy as np

import character_geometry as geometry
import character_hair as hair
from character_sculpt import apply

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = "art/character_models/teacher-n/teacher-n_source.glb"
OUTPUT = "assets/models/teacher-n/teacher-n.glb"
SOURCE_SHA256 = "f2d8247f2367567a8ed64d0201d322602c0ff933b23c54f1846033d8418994b0"
SOURCE_BYTES = 2990912
MESHOPTIMIZER_VERSION = "0.2.30a0"

DROP_NODES = ("ST_Stage_Floor",)
DROP_MESHES = ("ST_Stage_Floor_mesh",)
DROP_MATERIALS = ("M_ST_Stage",)
UNSUPPORTED_MATERIAL_EXTENSIONS = (
    "KHR_materials_sheen", "KHR_materials_clearcoat", "KHR_materials_specular",
)
## (mesh name, material name) -> absolute error bound in metres.
# Kept shape keys, per mesh. N's export carries fifteen; these five are the ones with a
# job. Order matters: it is the blend-shape order the runtime indexes.
SHAPES = {
    "ST_Head_Skin": ("Eye_Blink_L", "Eye_Blink_R", "Brow_Compress", "Frown", "Mouth_Close"),
    "ST_Eyebrow_L": ("Brow_Compress", "Frown"),
    "ST_Eyebrow_R": ("Brow_Compress", "Frown"),
}

SIMPLIFY = {
    ("ST_Head_Skin", "M_ST_Skin"): 0.0002,
    ("ST_Eye_L", "M_ST_Sclera"): 0.0002,
    ("ST_Eye_R", "M_ST_Sclera"): 0.0002,
}
## Weight of the vertex normal and of each bone's skin weight in the collapse metric.
NORMAL_WEIGHT = 0.5
SKIN_WEIGHT = 1.0
## Roughness changes, by material. Everything not listed keeps the owner's value.
ROUGHNESS = {
    # Unset in the export, i.e. 1.0: fully matte skin reads as chalk under the classroom's
    # key light. Q's skin is 0.8.
    "M_ST_Skin": 0.8,
    # 0.5 / 0.48 on near-black hair gives a hard plastic highlight. 0.75 / 0.72 keeps the
    # owner's "light strands are a little glossier" difference; Q's hair is 0.85.
    "M_ST_Hair": 0.75,
    "M_ST_HairLight": 0.72,
    # Brows and lashes are hair; Q's brow is 0.85.
    "M_ST_Brow": 0.85,
    "M_ST_Lash": 0.85,
    # Leather, not patent: 0.42 -> 0.6.
    "M_ST_Shoes": 0.6,
}
## A channel is constant when every key matches the rest value to this, per component.
CONSTANT_EPSILON = 1e-6

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32,
      5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963


class PrepareError(RuntimeError):
    pass


# --- reading -----------------------------------------------------------------


def load_glb(data: bytes) -> tuple[dict, bytes]:
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise PrepareError("not a glTF 2.0 binary of the length it declares")
    json_length, json_type = struct.unpack_from("<I4s", data, 12)
    if json_type != b"JSON":
        raise PrepareError("the first chunk is not JSON")
    document = json.loads(data[20:20 + json_length])
    offset = 20 + json_length
    bin_length, bin_type = struct.unpack_from("<I4s", data, offset)
    if bin_type != b"BIN\x00":
        raise PrepareError("the second chunk is not BIN")
    return document, data[offset + 8:offset + 8 + bin_length]


def read_accessor(document: dict, binary: bytes, index: int) -> np.ndarray:
    accessor = document["accessors"][index]
    if "sparse" in accessor:
        raise PrepareError("accessor %d is sparse; only morph targets use sparse data and "
                           "they are dropped before anything reads them" % index)
    width = NC[accessor["type"]]
    dtype = np.dtype(CT[accessor["componentType"]])
    view = document["bufferViews"][accessor["bufferView"]]
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", dtype.itemsize * width)
    count = accessor["count"]
    raw = np.frombuffer(binary, dtype=np.uint8,
                        count=stride * (count - 1) + dtype.itemsize * width, offset=offset)
    rows = np.lib.stride_tricks.as_strided(raw, (count, dtype.itemsize * width), (stride, 1))
    values = rows.copy().view(dtype).reshape(count, width)
    if accessor.get("normalized"):
        values = values.astype(np.float32) / float(np.iinfo(dtype).max)
    return values


def shape_names(mesh: dict) -> list:
    """Target names, which the Blender exporter stores on the mesh as extras."""
    extras = mesh.get("extras") or {}
    return list(extras.get("targetNames") or [])


def read_morph(document: dict, binary: bytes, accessor_index: int) -> tuple[np.ndarray, np.ndarray]:
    """A sparse morph target as (indices, displacements)."""
    accessor = document["accessors"][accessor_index]
    if "sparse" not in accessor:
        values = read_accessor(document, binary, accessor_index)
        return np.arange(len(values)), values
    count = accessor["count"]
    sparse_block = accessor["sparse"]
    index_info, value_info = sparse_block["indices"], sparse_block["values"]
    index_view = document["bufferViews"][index_info["bufferView"]]
    value_view = document["bufferViews"][value_info["bufferView"]]
    index_dtype = np.dtype(CT[index_info["componentType"]])
    indices = np.frombuffer(binary, dtype=index_dtype, count=sparse_block["count"],
                            offset=index_view.get("byteOffset", 0) + index_info.get("byteOffset", 0))
    width = NC[accessor["type"]]
    # Sparse values inherit the accessor's own componentType and type (glTF 2.0, 3.6.2.4).
    value_dtype = np.dtype(CT[accessor["componentType"]])
    values = np.frombuffer(binary, dtype=value_dtype, count=sparse_block["count"] * width,
                           offset=value_view.get("byteOffset", 0) + value_info.get("byteOffset", 0))
    return indices.astype(np.int64), values.reshape(-1, width).astype(np.float64)


# --- writing -----------------------------------------------------------------


class Builder:
    def __init__(self) -> None:
        self.binary = bytearray()
        self.views: list[dict] = []
        self.accessors: list[dict] = []
        self._inputs: dict[bytes, int] = {}

    def add(self, values: np.ndarray, kind: str, component: int, target: int | None = None,
            normalized: bool = False, bounds: bool = False,
            sparse_index: np.ndarray | None = None) -> int:
        """Append an accessor. With `sparse_index`, only those rows are stored."""
        if sparse_index is not None:
            return self._add_sparse(values, kind, component, target, sparse_index)
        values = np.ascontiguousarray(values, dtype=CT[component])
        while len(self.binary) % 4:
            self.binary.append(0)
        view = {"buffer": 0, "byteOffset": len(self.binary), "byteLength": values.nbytes}
        if target is not None:
            view["target"] = target
        self.binary.extend(values.tobytes())
        self.views.append(view)
        rows = values.reshape(len(values), -1)
        accessor = {"bufferView": len(self.views) - 1, "componentType": component,
                    "count": int(rows.shape[0]), "type": kind}
        if normalized:
            accessor["normalized"] = True
        if bounds:
            accessor["min"] = [float(x) for x in rows.min(axis=0)]
            accessor["max"] = [float(x) for x in rows.max(axis=0)]
        self.accessors.append(accessor)
        return len(self.accessors) - 1

    def _add_sparse(self, values: np.ndarray, kind: str, component: int,
                    target: int | None, rows: np.ndarray) -> int:
        """Morph data as a sparse accessor: most vertices never move in a given shape.

        A blink displaces 130 of 9,469 head vertices. Storing all 9,469 would cost
        114 KiB for that one shape; the sparse form costs 2 KiB and is core glTF 2.0
        (section 3.6.2.4) -- it is what the owner's export already does.
        """
        rows = np.asarray(rows, dtype=np.int64)
        order = np.argsort(rows)
        # `values` already holds one row per displaced vertex, in `rows` order.
        rows, subset = rows[order], np.asarray(values)[order]
        index_component = 5125 if rows.max(initial=0) >= 65536 else 5123
        indices = np.ascontiguousarray(rows, dtype=CT[index_component])
        payload = np.ascontiguousarray(subset, dtype=CT[component])
        parts = []
        for block in (indices, payload):
            while len(self.binary) % 4:
                self.binary.append(0)
            start = len(self.binary)
            self.binary.extend(block.tobytes())
            self.views.append({"buffer": 0, "byteOffset": start, "byteLength": block.nbytes,
                               "target": target})
            parts.append(len(self.views) - 1)
        width = NC[kind]
        self.accessors.append({
            "componentType": component, "count": int(len(values)), "type": kind,
            "sparse": {
                "count": int(len(rows)),
                "indices": {"bufferView": parts[0], "componentType": index_component},
                "values": {"bufferView": parts[1]},
            },
        })
        return len(self.accessors) - 1

    def add_time(self, times: np.ndarray) -> int:
        """Keyframe times, shared between every channel that uses the same ones."""
        key = np.ascontiguousarray(times, dtype=np.float32).tobytes()
        if key not in self._inputs:
            self._inputs[key] = self.add(times, "SCALAR", 5126, bounds=True)
        return self._inputs[key]


def write_glb(document: dict, binary: bytes) -> bytes:
    text = json.dumps(document, separators=(",", ":"), ensure_ascii=True).encode("ascii")
    text += b" " * (-len(text) % 4)
    blob = bytes(binary) + b"\x00" * (-len(binary) % 4)
    total = 12 + 8 + len(text) + 8 + len(blob)
    return (struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(text), b"JSON")
            + text + struct.pack("<I4s", len(blob), b"BIN\x00") + blob)


# --- the passes --------------------------------------------------------------


def _meshoptimizer():
    try:
        import meshoptimizer  # noqa: F401  (imported for its bundled shared library)
        from meshoptimizer._loader import lib
    except ImportError as error:
        raise PrepareError("meshoptimizer %s is required: pip install meshoptimizer==%s (%s)"
                           % (MESHOPTIMIZER_VERSION, MESHOPTIMIZER_VERSION, error))
    floats = ctypes.POINTER(ctypes.c_float)
    uints = ctypes.POINTER(ctypes.c_uint)
    size = ctypes.c_size_t
    # The Python wrapper of this alpha release does not declare argument types for this
    # entry point (a float argument then fails to convert), so they are declared here,
    # exactly as meshoptimizer.h 0.22 has them.
    lib.meshopt_simplifyWithAttributes.argtypes = [
        uints, uints, size, floats, size, size, floats, size, floats, size,
        ctypes.POINTER(ctypes.c_ubyte), size, ctypes.c_float, ctypes.c_uint, floats,
    ]
    lib.meshopt_simplifyWithAttributes.restype = size
    return lib


def simplify(indices: np.ndarray, positions: np.ndarray, normals: np.ndarray,
             joints: np.ndarray, weights: np.ndarray, bone_count: int,
             error: float) -> tuple[np.ndarray, float]:
    lib = _meshoptimizer()
    dense = np.zeros((len(positions), bone_count), np.float32)
    rows = np.arange(len(positions))
    for slot in range(4):
        np.add.at(dense, (rows, joints[:, slot].astype(np.int64)), weights[:, slot])
    attributes = np.ascontiguousarray(np.hstack([normals, dense]), np.float32)
    attribute_weights = np.array([NORMAL_WEIGHT] * 3 + [SKIN_WEIGHT] * bone_count, np.float32)
    source = np.ascontiguousarray(indices, np.uint32)
    points = np.ascontiguousarray(positions, np.float32)
    destination = np.zeros(len(source), np.uint32)
    result_error = ctypes.c_float(0.0)
    lock_border, error_absolute = 1, 4
    floats = ctypes.POINTER(ctypes.c_float)
    uints = ctypes.POINTER(ctypes.c_uint)
    count = lib.meshopt_simplifyWithAttributes(
        destination.ctypes.data_as(uints), source.ctypes.data_as(uints), len(source),
        points.ctypes.data_as(floats), len(points), 12,
        attributes.ctypes.data_as(floats), attributes.shape[1] * 4,
        attribute_weights.ctypes.data_as(floats), len(attribute_weights),
        ctypes.POINTER(ctypes.c_ubyte)(), 0, ctypes.c_float(error),
        lock_border | error_absolute, ctypes.byref(result_error),
    )
    if count == 0 or count % 3:
        raise PrepareError("simplification returned %d indices" % count)
    return destination[:count].copy(), float(result_error.value)


def quantize_weights(weights: np.ndarray) -> np.ndarray:
    """Four float weights per vertex -> four bytes that add up to exactly 255."""
    totals = weights.sum(axis=1, keepdims=True)
    if np.any(totals <= 0.0):
        raise PrepareError("a skinned vertex has no weight at all")
    scaled = weights / totals * 255.0
    quantized = np.floor(scaled + 0.5).astype(np.int32)
    residual = 255 - quantized.sum(axis=1)
    heaviest = np.argmax(weights, axis=1)
    quantized[np.arange(len(weights)), heaviest] += residual
    if quantized.min() < 0 or quantized.max() > 255:
        raise PrepareError("weight quantization left the 0..255 range")
    return quantized.astype(np.uint8)


def _drop_index(items: list[dict], names: tuple[str, ...], what: str) -> dict[int, int]:
    """Indices of `items` after dropping the named ones; raises if a name is missing."""
    found = [i for i, item in enumerate(items) if item.get("name") in names]
    if len(found) != len(names):
        raise PrepareError("expected %s %s in the source" % (what, ", ".join(names)))
    remap = {}
    for index in range(len(items)):
        if index not in found:
            remap[index] = len(remap)
    return remap


def _moves(values: np.ndarray, rest: list[float], path: str) -> bool:
    reference = np.array(rest, np.float64)
    keys = values.astype(np.float64)
    if path == "rotation":
        # q and -q are the same rotation; compare each key with the nearer sign.
        signs = np.where(keys @ reference < 0.0, -1.0, 1.0)[:, None]
        keys = keys * signs
    return bool(np.any(np.abs(keys - reference) > CONSTANT_EPSILON))


def _surface_warp(name: str):
    """The sculpt a mesh gets, as a field, so shape keys can follow it."""
    if name == "ST_Head_Skin" or name.startswith("ST_Eyebrow_"):
        return geometry.teacher_face
    return None


def _refine_surface(name: str, material: str, positions: np.ndarray, normals: np.ndarray,
                    joints: np.ndarray, weights: np.ndarray, indices: np.ndarray,
                    binds: np.ndarray) -> tuple:
    """The owner-authorised geometry revision; source rig/actions remain immutable."""
    shaped = None
    if name == "ST_Hands":
        parts, js, ws = [], [], []
        for right, joint in [(False, 6), (True, 9)]:
            part = geometry.hand_geometry(binds[joint], True, right)
            j, w = geometry.skin_arrays(len(part.positions), joint)
            # New topology needs new weights: blend the buried wrist into the existing
            # forearm, reaching a rigid hand before the metacarpus. Not copied weights.
            wrist_y = (np.c_[part.positions, np.ones(len(part.positions))] @ binds[joint].T)[:, 1]
            amount = np.clip((wrist_y + .007) / .025, 0, 1)
            j[:, 1], w[:, 0], w[:, 1] = (8 if right else 5), amount, 1 - amount
            parts.append(part)
            js.append(j)
            ws.append(w)
        shaped = geometry.join(*parts)
        joints, weights = np.concatenate(js), np.concatenate(ws)
    elif name == "ST_Hair":
        shaped, kept = geometry.teacher_bob(positions, indices.reshape(-1, 3))
        joints, weights = joints[kept], weights[kept]
    elif name in ("ST_Eye_L", "ST_Eye_R"):
        # The original three surfaces in each eye have inward winding/split normals.
        p, n = geometry.deform(positions, -normals, geometry.teacher_face)
        return p, n, joints, weights, indices.reshape(-1, 3)[:, [0, 2, 1]].ravel()
    elif name == "ST_Head_Skin" or name.startswith("ST_Eyebrow_"):
        p, n = geometry.deform(positions, normals, geometry.teacher_face)
        return p, n, joints, weights, indices
    elif name in ("ST_Blouse", "ST_Cardigan"):
        # The two original collar rings never meet the body: replace just their
        # triangles. Keep the torso/sleeve vertices' original (blended) skin weights.
        rings = positions[:, 1] > 1.363
        faces = indices.reshape(-1, 3)
        if not rings.any() or np.any(rings[faces].any(1) != rings[faces].all(1)):
            raise PrepareError(f"{name}: source neck ring no longer a separate component")
        kept, remap = np.unique(faces[~rings[faces].all(1)], return_inverse=True)
        knit = name == "ST_Cardigan"
        body = geometry.Geometry(geometry.teacher_tailoring(positions[kept], knit), remap.reshape(-1, 3))
        additions, js, ws = [], [], []
        for right, wrist in [(False, 6), (True, 9)]:
            detail = geometry.teacher_cuff(binds[wrist], right) if knit else geometry.teacher_collar(1 if right else -1)
            j, w = geometry.skin_arrays(len(detail.positions), (8 if right else 5) if knit else 1)
            if not knit:
                join_neck = .56 * geometry.smoothstep(1.347, 1.374, detail.positions[:, 1])
                j[:, 1], w[:, 0], w[:, 1] = 2, 1 - join_neck, join_neck
            additions.append(detail)
            js.append(j)
            ws.append(w)
        if knit:
            welt = geometry.teacher_welt(body)
            j, w = geometry.skin_arrays(len(welt.positions), 1)
            additions.append(welt)
            js.append(j)
            ws.append(w)
        shaped = geometry.join(body, *additions)
        joints = np.r_[joints[kept], np.concatenate(js)]
        weights = np.r_[weights[kept], np.concatenate(ws)]
    elif name.startswith("ST_Blouse_Button_"):
        shaped = geometry.Geometry(geometry.teacher_tailoring(positions, False), indices.reshape(-1, 3))
    if shaped is not None:
        return shaped.positions, geometry.normals(shaped), joints, weights, shaped.triangles.ravel()
    return positions, normals, joints, weights, indices


def prepare_base(source: bytes) -> tuple[bytes, dict]:
    if len(source) != SOURCE_BYTES or hashlib.sha256(source).hexdigest() != SOURCE_SHA256:
        raise PrepareError(
            "%s is not the export this script was written for (expected %d bytes, sha256 %s). "
            "Re-check every step against the new file, then update SOURCE_BYTES and "
            "SOURCE_SHA256." % (SOURCE, SOURCE_BYTES, SOURCE_SHA256))
    document, binary = load_glb(source)
    report: dict = {"simplified": {}, "dropped_channels": 0, "kept_channels": 0}

    node_map = _drop_index(document["nodes"], DROP_NODES, "node")
    mesh_map = _drop_index(document["meshes"], DROP_MESHES, "mesh")
    material_map = _drop_index(document["materials"], DROP_MATERIALS, "material")
    rest_by_node = {}
    for index, node in enumerate(document["nodes"]):
        rest_by_node[index] = {
            "translation": node.get("translation", [0.0, 0.0, 0.0]),
            "rotation": node.get("rotation", [0.0, 0.0, 0.0, 1.0]),
            "scale": node.get("scale", [1.0, 1.0, 1.0]),
        }

    out = Builder()
    bone_count = len(document["skins"][0]["joints"])
    binds = read_accessor(document, binary, document["skins"][0]["inverseBindMatrices"])
    binds = binds.reshape(-1, 4, 4).transpose(0, 2, 1)

    # Meshes, in their original order, minus the floor.
    meshes = []
    for old_index, mesh in enumerate(document["meshes"]):
        if old_index not in mesh_map:
            continue
        primitives = []
        # Shape keys the runtime actually drives: the two blinks (CharacterLookApplier
        # needs them to blink at all) and the three that set her resting face. The other
        # ten -- Brow_Raise, Jaw_Open, Mouth_Open -- stay out; nothing plays them and each
        # costs its own sparse displacement buffer.
        kept_shapes = SHAPES.get(mesh["name"], ())
        for primitive in mesh["primitives"]:
            attributes = primitive["attributes"]
            if set(attributes) != {"POSITION", "NORMAL", "JOINTS_0", "WEIGHTS_0"}:
                raise PrepareError("%s has attributes %s" % (mesh["name"], sorted(attributes)))
            if primitive.get("mode", 4) != 4:
                raise PrepareError("%s is not a triangle list" % mesh["name"])
            positions = read_accessor(document, binary, attributes["POSITION"])
            normals = read_accessor(document, binary, attributes["NORMAL"])
            joints = read_accessor(document, binary, attributes["JOINTS_0"])
            weights = read_accessor(document, binary, attributes["WEIGHTS_0"])
            indices = read_accessor(document, binary, primitive["indices"]).ravel()
            material_name = document["materials"][primitive["material"]]["name"]
            # Morph deltas are read before the mesh is simplified or re-sculpted: they are
            # re-based on whatever vertices survive, below.
            names = shape_names(mesh)
            wanted = [(slot, name) for slot, name in enumerate(names) if name in kept_shapes]
            deltas = {}
            for slot, name in wanted:
                target = primitive.get("targets", [])[slot]
                deltas[name] = read_morph(document, binary, target["POSITION"])
            bound = SIMPLIFY.get((mesh["name"], material_name))
            if bound is not None:
                before = (len(positions), len(indices) // 3)
                indices, reached = simplify(indices, positions, normals, joints, weights,
                                            bone_count, bound)
                kept = np.unique(indices)
                remap = np.full(len(positions), -1, np.int64)
                remap[kept] = np.arange(len(kept))
                indices = remap[indices]
                positions, normals = positions[kept], normals[kept]
                joints, weights = joints[kept], weights[kept]
                rebased = {}
                for name, (indices_of, values_of) in deltas.items():
                    keep = remap[indices_of] >= 0
                    rebased[name] = (remap[indices_of][keep], values_of[keep])
                deltas = rebased
                report["simplified"]["%s/%s" % (mesh["name"], material_name)] = {
                    "vertices": [before[0], len(positions)],
                    "triangles": [before[1], len(indices) // 3],
                    "error_m": round(reached, 6),
                }
            before_refine = positions.copy()
            positions, normals, joints, weights, indices = _refine_surface(
                mesh["name"], material_name, positions, normals, joints, weights, indices, binds)
            if deltas and len(positions) != len(before_refine):
                raise PrepareError("%s: a re-sculpt that changes topology cannot carry the "
                                   "source shape keys" % mesh["name"])
            if deltas:
                warp = _surface_warp(mesh["name"])
                if warp is not None:
                    deltas = {name: (indices_of,
                                     geometry.deform_delta(before_refine[indices_of],
                                                           values_of, warp))
                              for name, (indices_of, values_of) in deltas.items()}
            index_type = 5123 if len(positions) < 65536 else 5125
            primitive_out = {
                "attributes": {
                    "POSITION": out.add(positions, "VEC3", 5126, ARRAY_BUFFER, bounds=True),
                    "NORMAL": out.add(normals, "VEC3", 5126, ARRAY_BUFFER),
                    "JOINTS_0": out.add(joints, "VEC4", 5121, ARRAY_BUFFER),
                    "WEIGHTS_0": out.add(quantize_weights(weights), "VEC4", 5121,
                                         ARRAY_BUFFER, normalized=True),
                },
                "indices": out.add(indices.reshape(-1, 1), "SCALAR", index_type,
                                   ELEMENT_ARRAY_BUFFER),
                "material": material_map[primitive["material"]],
            }
            if deltas:
                order = [name for name in kept_shapes if name in deltas]
                primitive_out["targets"] = [
                    {"POSITION": out.add(deltas[name][1].astype(np.float32), "VEC3", 5126,
                                         ARRAY_BUFFER, sparse_index=deltas[name][0])}
                    for name in order]
            primitives.append(primitive_out)
        record = {"name": mesh["name"], "primitives": primitives}
        if any("targets" in primitive for primitive in primitives):
            # Blender's exporter keeps the names here; Godot reads them as blend shape names.
            record["extras"] = {"targetNames": list(kept_shapes)}
        meshes.append(record)

    # Nodes: unchanged transforms, minus the floor, with the mesh indices remapped.
    nodes = []
    for old_index, node in enumerate(document["nodes"]):
        if old_index not in node_map:
            continue
        copy = {key: value for key, value in node.items()}
        if "children" in copy:
            copy["children"] = [node_map[c] for c in copy["children"] if c in node_map]
        if "mesh" in copy:
            copy["mesh"] = mesh_map[copy["mesh"]]
        nodes.append(copy)

    skin = document["skins"][0]
    inverse_binds = read_accessor(document, binary, skin["inverseBindMatrices"])
    skins = [{
        "inverseBindMatrices": out.add(inverse_binds, "MAT4", 5126),
        "joints": [node_map[j] for j in skin["joints"]],
        "name": skin["name"],
    }]

    animations = []
    for animation in document["animations"]:
        samplers = []
        channels = []
        for channel in animation["channels"]:
            sampler = animation["samplers"][channel["sampler"]]
            target = channel["target"]
            values = read_accessor(document, binary, sampler["output"])
            if not _moves(values, rest_by_node[target["node"]][target["path"]], target["path"]):
                report["dropped_channels"] += 1
                continue
            times = read_accessor(document, binary, sampler["input"]).ravel()
            kind = "VEC4" if target["path"] == "rotation" else "VEC3"
            samplers.append({
                "input": out.add_time(times),
                "interpolation": sampler.get("interpolation", "LINEAR"),
                "output": out.add(values, kind, 5126),
            })
            channels.append({"sampler": len(samplers) - 1,
                             "target": {"node": node_map[target["node"]],
                                        "path": target["path"]}})
            report["kept_channels"] += 1
        if not channels:
            raise PrepareError("animation %s does not move anything" % animation["name"])
        animations.append({"name": animation["name"], "channels": channels,
                           "samplers": samplers})

    materials = []
    for old_index, material in enumerate(document["materials"]):
        if old_index not in material_map:
            continue
        copy = json.loads(json.dumps(material))
        extensions = copy.pop("extensions", {})
        unknown = set(extensions) - set(UNSUPPORTED_MATERIAL_EXTENSIONS)
        if unknown:
            raise PrepareError("%s uses %s" % (material["name"], sorted(unknown)))
        if material["name"] in ("M_ST_Sclera", "M_ST_Iris", "M_ST_Pupil"):
            copy["doubleSided"] = False
        pbr = copy.setdefault("pbrMetallicRoughness", {})
        if material["name"] in ROUGHNESS:
            pbr["roughnessFactor"] = ROUGHNESS[material["name"]]
        if float(pbr.get("metallicFactor", 1.0)) != 0.0:
            raise PrepareError("%s is metallic" % material["name"])
        materials.append(copy)

    scene_nodes = [node_map[n] for n in document["scenes"][0]["nodes"] if n in node_map]
    result = {
        "asset": {
            "generator": "where-is-school tools/prepare_teacher_n.py from %s"
                         % document["asset"].get("generator", "an unknown exporter"),
            "version": "2.0",
            "extras": {"source": SOURCE, "source_sha256": SOURCE_SHA256, "geometry_revision": 8},
        },
        "scene": 0,
        "scenes": [{"name": document["scenes"][0].get("name", "Scene"), "nodes": scene_nodes}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": materials,
        "skins": skins,
        "animations": animations,
        "accessors": out.accessors,
        "bufferViews": out.views,
        "buffers": [{"byteLength": len(out.binary) + (-len(out.binary) % 4)}],
    }
    data = write_glb(result, out.binary)
    report["bytes"] = len(data)
    return data, report


# Geometry revision 3 lives here: after the baked Blender stroke layer, so it edits what
# that layer leaves instead of being overwritten by it. Each entry is a pure field over
# bind-space positions and changes no topology, which is what makes a post-pass possible.
# The head skin's morph deltas are warped by the same field as its positions.
MORPH_FIELDS = {"ST_Head_Skin": geometry.teacher_resting_field}
RESTING = {
    "ST_Head_Skin": geometry.teacher_resting_face,
    "ST_Eyebrow_L": geometry.teacher_expression,
    "ST_Eyebrow_R": geometry.teacher_expression,
}
# The crop needs the head it sits on: `character_hair.teacher_crop` fits the shell to the
# skull, so the hair is a second stage after the head has been rewritten (see
# `_resting_channel`) rather than an entry here.
SILHOUETTE: dict = {}
HAIR_PARTS = {"M_ST_Hair": hair.teacher_crop,
              "M_ST_HairLight": hair.teacher_highlight}
# The eyeballs are not face-shaped (no lid, no brow), so they take their own small field.
EYEBALLS = {"ST_Eye_L": geometry.teacher_eyeball, "ST_Eye_R": geometry.teacher_eyeball}
# Each ear is its own thin shell, mirrored; the fit is symmetric, so one field does both.
EARS = {"ST_Ear_L": geometry.teacher_ear, "ST_Ear_R": geometry.teacher_ear}


class _Arrays:
    """Read and write accessors in place, over a copy of the binary chunk.

    Everything this pass needs is an in-place rewrite of arrays that already have the
    right count: positions, normals, and the sparse values of a morph target. Nothing is
    added or removed, so every accessor, view and stride the file declares stays valid.
    """

    def __init__(self, document: dict, binary: bytes) -> None:
        self.document = document
        self.views = document["bufferViews"]
        self.blocks = [bytearray(binary[v.get("byteOffset", 0):
                                         v.get("byteOffset", 0) + v["byteLength"]])
                       for v in self.views]

    def _shape(self, index: int):
        accessor = self.document["accessors"][index]
        width = NC[accessor["type"]]
        dtype = np.dtype(CT[accessor["componentType"]])
        view = self.views[accessor["bufferView"]]
        stride = view.get("byteStride") or dtype.itemsize * width
        return accessor, view, dtype, width, stride

    def read(self, index: int) -> np.ndarray:
        accessor, view, dtype, width, stride = self._shape(index)
        raw = np.frombuffer(bytes(self.blocks[accessor["bufferView"]]), dtype=np.uint8,
                            count=stride * accessor["count"],
                            offset=accessor.get("byteOffset", 0))
        return raw.reshape(accessor["count"], stride)[:, :dtype.itemsize * width].copy().view(
            dtype).reshape(accessor["count"], width)

    def write(self, index: int, values: np.ndarray) -> None:
        accessor, view, dtype, width, stride = self._shape(index)
        head = accessor.get("byteOffset", 0)
        width_bytes = dtype.itemsize * width
        rows = np.frombuffer(bytes(self.blocks[accessor["bufferView"]]),
                             dtype=np.uint8).reshape(-1, stride).copy()
        flat = np.ascontiguousarray(values, dtype=dtype).reshape(accessor["count"], width)
        rows[:, head:head + width_bytes] = flat.view(np.uint8).reshape(
            accessor["count"], width_bytes)
        self.blocks[accessor["bufferView"]] = bytearray(rows.tobytes())

    def read_morph_values(self, target: dict) -> tuple[np.ndarray, np.ndarray]:
        accessor = self.document["accessors"][target["POSITION"]]
        sparse = accessor["sparse"]
        index_info = sparse["indices"]
        index_view = self.views[index_info["bufferView"]]
        rows = np.frombuffer(bytes(self.blocks[index_info["bufferView"]]),
                             dtype=np.dtype(CT[index_info["componentType"]]),
                             count=sparse["count"],
                             # The block is already this view's slice, so only the
                             # accessor's own offset is added here.
                             offset=index_info.get("byteOffset", 0)).astype(np.int64)
        value_info = sparse["values"]
        value_view = self.views[value_info["bufferView"]]
        values = np.frombuffer(bytes(self.blocks[value_info["bufferView"]]),
                               dtype=np.dtype(CT[accessor["componentType"]]),
                               count=sparse["count"] * NC[accessor["type"]],
                               offset=value_info.get("byteOffset", 0)
                               ).reshape(-1, NC[accessor["type"]]).astype(np.float64)
        return rows, values

    def write_morph_values(self, target: dict, values: np.ndarray) -> None:
        accessor = self.document["accessors"][target["POSITION"]]
        sparse = accessor["sparse"]
        value_info = sparse["values"]
        view = self.views[value_info["bufferView"]]
        start = value_info.get("byteOffset", 0)
        dtype = np.dtype(CT[accessor["componentType"]])
        flat = np.ascontiguousarray(values, dtype=dtype).reshape(-1)
        block = np.frombuffer(bytes(self.blocks[value_info["bufferView"]]), dtype=np.uint8).copy()
        block[start:start + flat.nbytes] = flat.view(np.uint8)
        self.blocks[value_info["bufferView"]] = bytearray(block.tobytes())

    def packed(self) -> bytes:
        out = bytearray()
        for view, block in zip(self.views, self.blocks):
            out.extend(bytes(-len(out) % 4))
            view["byteOffset"], view["byteLength"] = len(out), len(block)
            out.extend(block)
            assert view["byteOffset"] + view["byteLength"] == len(out)
        self.document["buffers"][0]["byteLength"] = len(out)
        return bytes(out)


def _head_geometry(document: dict, arrays: "_Arrays") -> tuple[np.ndarray, np.ndarray]:
    """The head's skin surface as the hair has to sit on it: after the resting pass."""
    for mesh in document["meshes"]:
        if mesh["name"] != "ST_Head_Skin":
            continue
        for primitive in mesh["primitives"]:
            material = document["materials"][primitive["material"]]["name"]
            if material != "M_ST_Skin":
                continue
            return (arrays.read(primitive["attributes"]["POSITION"]).astype(np.float64),
                    arrays.read(primitive["attributes"]["NORMAL"]).astype(np.float64))
    raise PrepareError("ST_Head_Skin/M_ST_Skin is missing, so the hair cannot be fitted")


def _smooth_the_mouth_rim(document: dict, arrays: "_Arrays", moved: dict) -> None:
    """Replace the stepped mouth rim with a smooth curve, on both sheets that share it.

    The skin and the lip are separate meshes with separate vertex numbering -- the lip has
    a few hundred vertices, the head a few thousand -- so the rim's identity is its
    *position*, not its index. The lip's rim is re-derived as a smooth curve, and each of
    the skin's opening vertices is moved to the curve point it already sits on. Nothing
    else on either mesh moves, and every rim vertex keeps a partner at zero distance, so the
    seam stays welded by construction rather than by a tolerance.
    """
    lip_base = lip_shape = None
    for mesh in document["meshes"]:
        if mesh["name"] != "ST_Head_Skin":
            continue
        for primitive in mesh["primitives"]:
            if document["materials"][primitive["material"]]["name"] != "M_ST_Lip":
                continue
            lip_base = arrays.read(primitive["attributes"]["POSITION"]).astype(np.float64)
            lip_shape = arrays.read(primitive["indices"]).reshape(-1, 3)
    if lip_base is None:
        raise PrepareError("the lip is missing, so the mouth rim cannot be smoothed")
    loop, target = geometry.mouth_rim_targets(lip_base, lip_shape)

    for mesh in document["meshes"]:
        if mesh["name"] != "ST_Head_Skin":
            continue
        for primitive in mesh["primitives"]:
            if document["materials"][primitive["material"]]["name"] not in ("M_ST_Lip", "M_ST_Skin"):
                continue
            attributes = primitive["attributes"]
            base = arrays.read(attributes["POSITION"]).astype(np.float64)
            positions = base.copy()
            if len(base) == len(lip_base):
                positions[loop] = target          # the lip itself: same numbering
            else:
                # The head: match the opening's vertices to the rim by position.
                for vertex, point in zip(loop, target):
                    near = np.linalg.norm(base - lip_base[vertex], axis=1) < 1e-7
                    positions[near] = point
            shift = positions - base
            arrays.write(attributes["POSITION"], positions)
            for target_accessor in primitive.get("targets", []):
                rows, deltas = arrays.read_morph_values(target_accessor)
                arrays.write_morph_values(target_accessor, deltas + shift[rows])
            key = "%s/%s" % (mesh["name"], document["materials"][primitive["material"]]["name"])
            moved[key] = max(moved.get(key, 0.0), float(np.abs(shift).max()))


def _tuck_the_teeth(document: dict, arrays: "_Arrays", moved: dict) -> None:
    """Push the teeth behind the lip so the closed mouth shows no white bar."""
    lip = None
    for mesh in document["meshes"]:
        if mesh["name"] != "ST_Head_Skin":
            continue
        for primitive in mesh["primitives"]:
            if document["materials"][primitive["material"]]["name"] == "M_ST_Lip":
                lip = arrays.read(primitive["attributes"]["POSITION"]).astype(np.float64)
    if lip is None:
        raise PrepareError("the lip is missing, so the teeth cannot be placed behind it")
    for mesh in document["meshes"]:
        if mesh["name"] != "ST_Head_Skin":
            continue
        for primitive in mesh["primitives"]:
            if document["materials"][primitive["material"]]["name"] != "M_ST_Teeth":
                continue
            attributes = primitive["attributes"]
            base = arrays.read(attributes["POSITION"]).astype(np.float64)
            positions = geometry.teacher_teeth(base, lip)
            shift = positions - base
            arrays.write(attributes["POSITION"], positions)
            for target_accessor in primitive.get("targets", []):
                rows, deltas = arrays.read_morph_values(target_accessor)
                arrays.write_morph_values(target_accessor, deltas + shift[rows])
            moved["ST_Head_Skin/M_ST_Teeth"] = float(np.abs(shift).max())


def _resting_channel(document: dict, binary: bytes, report: dict) -> bytes:
    arrays = _Arrays(document, binary)
    moved = {}
    for mesh in document["meshes"]:
        callback = (RESTING.get(mesh["name"]) or SILHOUETTE.get(mesh["name"])
                    or EYEBALLS.get(mesh["name"]) or EARS.get(mesh["name"]))
        if callback is None:
            continue
        for primitive in mesh["primitives"]:
            attributes = primitive["attributes"]
            base = arrays.read(attributes["POSITION"]).astype(np.float64)
            normals = arrays.read(attributes["NORMAL"]).astype(np.float64)
            if (mesh["name"] in SILHOUETTE or mesh["name"] in EYEBALLS
                    or mesh["name"] in EARS):
                positions = callback(base)
                _, normals_out = geometry.deform(base, normals, callback)
                for target in primitive.get("targets", []):
                    rows, deltas = arrays.read_morph_values(target)
                    arrays.write_morph_values(target, callback(base[rows] + deltas)
                                              - callback(base[rows]))
            else:
                positions, normals_out = callback(base, normals)
                for target in primitive.get("targets", []):
                    rows, deltas = arrays.read_morph_values(target)
                    arrays.write_morph_values(
                        target, geometry.deform_delta(
                            base[rows], deltas,
                            MORPH_FIELDS.get(mesh["name"], geometry.teacher_expression_field)))
            arrays.write(attributes["POSITION"], positions)
            arrays.write(attributes["NORMAL"], normals_out)
            moved.setdefault(mesh["name"], 0.0)
            moved[mesh["name"]] = max(moved[mesh["name"]],
                                      float(np.abs(positions - base).max()))

    _smooth_the_mouth_rim(document, arrays, moved)
    _tuck_the_teeth(document, arrays, moved)

    # The hair is fitted to the skull, so it can only run once the head has been rewritten.
    skin = _head_geometry(document, arrays)
    for mesh in document["meshes"]:
        if mesh["name"] != "ST_Hair":
            continue
        for primitive in mesh["primitives"]:
            callback = HAIR_PARTS.get(document["materials"][primitive["material"]]["name"])
            if callback is None:
                raise PrepareError("ST_Hair has a part with no fitted style")
            attributes = primitive["attributes"]
            base = arrays.read(attributes["POSITION"]).astype(np.float64)
            normals = arrays.read(attributes["NORMAL"]).astype(np.float64)
            shape = arrays.read(primitive["indices"]).reshape(-1, 3)

            def fit(points, _skin=skin, _shape=shape, _callback=callback):
                return _callback(points, _skin, _shape)

            positions = fit(base)
            # The hair is re-shaped wholesale, so its normals are recomputed from the new
            # surface instead of being carried through the map's Jacobian: pinning the cut
            # edge is a step in that map, and a step cannot be differentiated. It also
            # replaces the source's split strip normals, which the new form invalidates.
            del normals
            positions = geometry.teacher_crown_part(positions)
            normals_out = geometry.normals(geometry.Geometry(positions, shape))
            arrays.write(attributes["POSITION"], positions)
            arrays.write(attributes["NORMAL"], normals_out)
            name = "%s/%s" % (mesh["name"], document["materials"][primitive["material"]]["name"])
            moved[name] = float(np.abs(positions - base).max())

    report["resting_channel_m"] = {name: round(value, 6) for name, value in moved.items()}
    # `packed()` has just rewritten every view's offset, so the GLB header and JSON chunk
    # have to be re-serialised around the new binary rather than reused.
    return write_glb(document, arrays.packed())


def prepare(source: bytes) -> tuple[bytes, dict]:
    basis, report = prepare_base(source)
    sculpted = apply(basis, "n")
    document, binary = load_glb(sculpted)
    data = _resting_channel(document, binary, report)
    report["bytes"] = len(data)
    return data, report


def describe(data: bytes) -> str:
    document, binary = load_glb(data)
    vertices = triangles = 0
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            vertices += document["accessors"][primitive["attributes"]["POSITION"]]["count"]
            triangles += document["accessors"][primitive["indices"]]["count"] // 3
    morphs = sum(len(p.get("targets", [])) for m in document["meshes"] for p in m["primitives"])
    return ("%d bytes (%.1f KiB), %d nodes, %d meshes, %d materials, %d vertices, %d triangles, "
            "%d morph target(s), %d animation(s) with %d channel(s)"
            % (len(data), len(data) / 1024.0, len(document["nodes"]), len(document["meshes"]),
               len(document["materials"]), vertices, triangles, morphs,
               len(document.get("animations", [])),
               sum(len(a["channels"]) for a in document.get("animations", []))))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="rebuild in memory and fail if the committed file differs")
    parser.add_argument("--report", action="store_true", help="print what was done")
    args = parser.parse_args(argv)
    try:
        with open(os.path.join(ROOT, SOURCE), "rb") as handle:
            source = handle.read()
        data, report = prepare(source)
    except (OSError, PrepareError, ValueError, KeyError) as error:
        print("PREPARE_TEACHER_N_PROBLEM: %s" % error)
        return 1
    target = os.path.join(ROOT, OUTPUT)
    if args.report or not args.check:
        print("source: " + describe(source))
        print("result: " + describe(data))
        for part, numbers in report["simplified"].items():
            print("simplified %s: %d -> %d vertices, %d -> %d triangles, error %.3f mm"
                  % (part, numbers["vertices"][0], numbers["vertices"][1],
                     numbers["triangles"][0], numbers["triangles"][1],
                     numbers["error_m"] * 1000.0))
        print("animation channels: %d kept, %d constant ones dropped"
              % (report["kept_channels"], report["dropped_channels"]))
    if args.check:
        try:
            with open(target, "rb") as handle:
                committed = handle.read()
        except OSError as error:
            print("PREPARE_TEACHER_N_PROBLEM: %s" % error)
            return 1
        if committed != data:
            print("PREPARE_TEACHER_N_PROBLEM: %s differs from what %s builds from %s"
                  % (OUTPUT, os.path.basename(__file__), SOURCE))
            return 1
        print("PREPARE_TEACHER_N_OK: %s is exactly what the source builds (%s)"
              % (OUTPUT, hashlib.sha256(data).hexdigest()))
        return 0
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "wb") as handle:
        handle.write(data)
    print("wrote %s (sha256 %s)" % (OUTPUT, hashlib.sha256(data).hexdigest()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
