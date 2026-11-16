#!/usr/bin/env python3
"""Prepare the approved new Q without changing geometry, skinning or authored poses.

The immutable upload lives under art/ (never imported/exported). Only the production
copy is imported: remove its skeleton-display mesh, give its uncoloured materials the
existing Q palette, and omit animation channels which are exactly the rest pose.
Every action (including the pose and face previews), moving channel, morph target,
vertex, joint, rest transform and inverse bind matrix is preserved.

    python3 tools/prepare_q.py
    python3 tools/prepare_q.py --check
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art/character_models/q/new-Q_source.glb"
OUTPUT = ROOT / "assets/models/q/new-Q.glb"
SOURCE_SHA256 = "4d2d7d5939840bdfcc8b94f111f864e1d080a715380969ec335a7e1e60509f45"
# Existing production Q colours, assigned to the new export's material names. These
# are fallback colours too: the painted Look still owns the shipping presentation.
PALETTE = {
    "Q_Mat_SkinBody": "CE9A70", "Q_Mat_Trousers": "313D52",
    "Q_Mat_Sclera": "DCD2BA", "Q_Mat_Iris": "2B1D15",
    "Q_Mat_Pupil": "0C0A09", "Q_Mat_Shoes": "2F2521",
    "Q_Mat_Sole": "B4A585", "Q_Mat_Hair": "18151B",
    "Q_Mat_Skin": "CE9A70", "Q_Mat_MouthInner": "3B1713",
    "Q_Mat_Hoodie": "516F4C", "Q_Mat_HoodieRib": "B39A5F",
}
COMPONENTS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def decode(data: bytes) -> tuple[dict, bytes]:
    if len(data) < 28 or data[:4] != b"glTF":
        raise ValueError("not a binary glTF")
    version, size = struct.unpack_from("<II", data, 4)
    json_size, kind = struct.unpack_from("<II", data, 12)
    if version != 2 or size != len(data) or kind != 0x4E4F534A:
        raise ValueError("invalid glTF header")
    document = json.loads(data[20:20 + json_size])
    offset = 20 + json_size
    bin_size, kind = struct.unpack_from("<II", data, offset)
    if kind != 0x004E4942 or offset + 8 + bin_size != len(data):
        raise ValueError("expected a single embedded BIN chunk")
    return document, data[offset + 8:]


def encode(document: dict, binary: bytes) -> bytes:
    text = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode()
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    size = 12 + 8 + len(text) + 8 + len(binary)
    return (struct.pack("<4sII", b"glTF", 2, size)
            + struct.pack("<II", len(text), 0x4E4F534A) + text
            + struct.pack("<II", len(binary), 0x004E4942) + binary)


def accessor(document: dict, binary: bytes, index: int) -> list[tuple]:
    item = document["accessors"][index]
    width = WIDTH[item["type"]]
    fmt = "<" + COMPONENTS[item["componentType"]] * width
    size = struct.calcsize(fmt)
    result = [(0,) * width for _ in range(item["count"])]
    if "bufferView" in item:
        view = document["bufferViews"][item["bufferView"]]
        stride = view.get("byteStride", size)
        start = view.get("byteOffset", 0) + item.get("byteOffset", 0)
        result = [struct.unpack_from(fmt, binary, start + row * stride)
                  for row in range(item["count"])]
    if "sparse" in item:
        sparse = item["sparse"]
        indices, values = sparse["indices"], sparse["values"]
        index_fmt = "<" + COMPONENTS[indices["componentType"]]
        index_size = struct.calcsize(index_fmt)
        index_start = (document["bufferViews"][indices["bufferView"]].get("byteOffset", 0)
                       + indices.get("byteOffset", 0))
        value_start = (document["bufferViews"][values["bufferView"]].get("byteOffset", 0)
                       + values.get("byteOffset", 0))
        for row in range(sparse["count"]):
            index = struct.unpack_from(index_fmt, binary, index_start + row * index_size)[0]
            result[index] = struct.unpack_from(fmt, binary, value_start + row * size)
    return result


def _rest_channel(document: dict, binary: bytes, channel: dict, sampler: dict) -> bool:
    target = channel["target"]
    path = target["path"]
    defaults = {"rotation": [0, 0, 0, 1], "translation": [0, 0, 0], "scale": [1, 1, 1]}
    if path not in defaults or sampler.get("interpolation", "LINEAR") not in ("LINEAR", "STEP"):
        return False
    rest = document["nodes"][target["node"]].get(path, defaults[path])
    for row in accessor(document, binary, sampler["output"]):
        difference = max(abs(x - y) for x, y in zip(row, rest))
        if path == "rotation":
            # q and -q encode the same rotation.
            difference = min(difference, max(abs(x + y) for x, y in zip(row, rest)))
        if difference > 0.000002:
            return False
    return True


def _compact(document: dict, binary: bytes) -> bytes:
    """Copy live accessor/view bytes verbatim; never re-quantize geometry or animation."""
    refs: list[tuple[dict, str]] = []
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            refs.extend((primitive["attributes"], key) for key in primitive["attributes"])
            if "indices" in primitive:
                refs.append((primitive, "indices"))
            for target in primitive.get("targets", []):
                refs.extend((target, key) for key in target)
    for skin in document["skins"]:
        refs.append((skin, "inverseBindMatrices"))
    for animation in document["animations"]:
        for sampler in animation["samplers"]:
            refs.extend([(sampler, "input"), (sampler, "output")])
    live = sorted({holder[key] for holder, key in refs})
    mapping = {old: new for new, old in enumerate(live)}
    accessors = [document["accessors"][old] for old in live]
    for holder, key in refs:
        holder[key] = mapping[holder[key]]
    document["accessors"] = accessors
    view_refs: list[dict] = []
    for item in accessors:
        if "bufferView" in item:
            view_refs.append(item)
        if "sparse" in item:
            view_refs.extend([item["sparse"]["indices"], item["sparse"]["values"]])
    views = sorted({item["bufferView"] for item in view_refs})
    mapping = {old: new for new, old in enumerate(views)}
    packed = bytearray()
    kept = []
    for old in views:
        view = copy.deepcopy(document["bufferViews"][old])
        if view["buffer"] != 0:
            raise ValueError("external buffer is not supported")
        packed.extend(b"\0" * (-len(packed) % 4))
        start = view.get("byteOffset", 0)
        block = binary[start:start + view["byteLength"]]
        if len(block) != view["byteLength"]:
            raise ValueError("truncated buffer view")
        view["byteOffset"] = len(packed)
        packed.extend(block)
        kept.append(view)
    for item in view_refs:
        item["bufferView"] = mapping[item["bufferView"]]
    document["bufferViews"] = kept
    document["buffers"] = [{"byteLength": len(packed)}]
    return bytes(packed)


def prepare(data: bytes) -> bytes:
    digest = hashlib.sha256(data).hexdigest()
    if digest != SOURCE_SHA256:
        raise ValueError(f"approved Q source changed: {digest}; review before changing the pinned source")
    document, binary = decode(data)
    # In this exact upload these are final entries, with no incoming references from
    # skins or actions. Assert the shape instead of guessing indices on a future file.
    if document["nodes"][-1] != {"mesh": 9, "name": "Q_SkeletonPreview"}:
        raise ValueError("skeleton preview changed; review its removal")
    if document["meshes"][-1]["name"] != "Q_SkeletonPreview":
        raise ValueError("preview mesh changed")
    if document["materials"][-1]["name"] != "Q_Mat_BonePreview":
        raise ValueError("preview material changed")
    preview = len(document["nodes"]) - 1
    document["scenes"][0]["nodes"].remove(preview)
    document["nodes"].pop()
    document["meshes"].pop()
    document["materials"].pop()
    for material in document["materials"]:
        name = material["name"]
        colour = PALETTE[name]
        values = [int(colour[index:index + 2], 16) / 255 for index in (0, 2, 4)]
        linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
                  for value in values]
        pbr = material["pbrMetallicRoughness"]
        pbr["baseColorFactor"] = linear + [1.0]
        pbr["roughnessFactor"] = 0.85
        # KHR_materials_specular isn't imported by the pinned engine. The existing
        # painterly shader has no specular; removing this doesn't remove any colour.
        material.pop("extensions", None)
    document.pop("extensionsUsed", None)
    for animation in document["animations"]:
        kept_channels, kept_samplers = [], []
        for channel in animation["channels"]:
            sampler = animation["samplers"][channel["sampler"]]
            if _rest_channel(document, binary, channel, sampler):
                continue
            channel["sampler"] = len(kept_samplers)
            kept_channels.append(channel)
            kept_samplers.append(sampler)
        if not kept_channels:
            raise ValueError(f"preparation would erase the action {animation['name']}")
        animation["channels"] = kept_channels
        animation["samplers"] = kept_samplers
    binary = _compact(document, binary)
    return encode(document, binary)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        result = prepare(SOURCE.read_bytes())
    except (ValueError, OSError, KeyError) as error:
        print(f"FAIL: {error}")
        return 1
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_bytes() != result:
            print("FAIL: production Q differs; run python3 tools/prepare_q.py")
            return 1
        print("PASS: new-Q.glb is reproducible from the approved source")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_bytes(result)
        print(f"WROTE assets/models/q/new-Q.glb ({len(result):,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
