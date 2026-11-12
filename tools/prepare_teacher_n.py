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

Nothing is rotated, moved or scaled. The model faces -Z, which is what
`docs/ASSET_PIPELINE.md` section 1 asks a new export to do, and stands with its soles on the
origin.

Requires numpy and meshoptimizer 0.2.30a0 (which bundles meshoptimizer 0.22); both are
build-time only, and neither the game nor CI needs them: CI checks the committed output
(`tools/model_library.py --check`, the Godot import tests), not this script. The output is
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


# --- writing -----------------------------------------------------------------


class Builder:
    def __init__(self) -> None:
        self.binary = bytearray()
        self.views: list[dict] = []
        self.accessors: list[dict] = []
        self._inputs: dict[bytes, int] = {}

    def add(self, values: np.ndarray, kind: str, component: int, target: int | None = None,
            normalized: bool = False, bounds: bool = False) -> int:
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


def prepare(source: bytes) -> tuple[bytes, dict]:
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

    # Meshes, in their original order, minus the floor.
    meshes = []
    for old_index, mesh in enumerate(document["meshes"]):
        if old_index not in mesh_map:
            continue
        primitives = []
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
                report["simplified"]["%s/%s" % (mesh["name"], material_name)] = {
                    "vertices": [before[0], len(positions)],
                    "triangles": [before[1], len(indices) // 3],
                    "error_m": round(reached, 6),
                }
            index_type = 5123 if len(positions) < 65536 else 5125
            primitives.append({
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
            })
        meshes.append({"name": mesh["name"], "primitives": primitives})

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
            "extras": {"source": SOURCE, "source_sha256": SOURCE_SHA256},
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
    except (OSError, PrepareError) as error:
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
