#!/usr/bin/env python3
"""Prepare the approved Q and install the separate Blender head revision.

The immutable upload lives under art/ (never imported/exported). Only the production
copy is imported: remove its skeleton-display mesh, give its uncoloured materials the
existing Q palette, and omit animation channels which are exactly the rest pose.
The preparation basis preserves every vertex and animation delta. A separate
Blender layer refines only the head/eyes/hair, leaving the approved upload,
skeleton, skin binding, expressions and authored poses intact.

    python3 tools/prepare_q.py
    python3 tools/prepare_q.py --check
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import math
from pathlib import Path

from character_sculpt import apply
from glb_io import accessor, decode, encode

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


def prepare_base(data: bytes) -> bytes:
    """Lossless geometry phase; also used to verify the pinned approved upload."""
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


def prepare(data: bytes) -> bytes:
    return apply(prepare_base(data), "q")


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
        print("PASS: new-Q.glb is reproducible from the approved source and Blender head layer")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_bytes(result)
        print(f"WROTE assets/models/q/new-Q.glb ({len(result):,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
