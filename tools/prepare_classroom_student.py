#!/usr/bin/env python3
"""Refine the owner-authored seated student, preserving the exact original 16-joint rig.

    python3 tools/prepare_classroom_student.py
    python3 tools/prepare_classroom_student.py --check

The supplied blockout is preserved byte-for-byte under art/character_models/ (excluded
from imports/exports). This deterministic geometry revision replaces four-digit mitten
parts, globe-like eyes and the featureless facial sphere; solidifies garment panels and
rounds selected low-sided forms. It is NOT a replacement player, an animation controller,
a new bone hierarchy or a claim of equivalence to a commercial game's finished artwork.
Build tools only: the existing pinned numpy and GLB reader/writer from prepare_teacher_n.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
from pathlib import Path

import numpy as np

import character_geometry as geometry
from prepare_teacher_n import (ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER, Builder, load_glb,
                               quantize_weights, read_accessor, write_glb)

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art/character_models/classroom_student/student_source.glb"
OUTPUT = ROOT / "assets/models/protagonist/protagonist.glb"
SOURCE_SHA256 = "5928e55a26bc03168d61618815724d7555881710f54715405e18428af855cd8d"
# The two integrated palms now include four full fingers and a thumb each. The separate
# cheek/under-eye ellipsoids become authored planes of the continuous head, not hidden
# obsolete meshes. Material names are kept so all existing look variants stay usable.
REMOVED_NODES = {f"Hand_Finger_{side}_{digit}" for side in "LR" for digit in range(1, 4)} | {
    "Hand_Thumb_L", "Hand_Thumb_R", "Cheek_Plane_L", "Cheek_Plane_R",
    "UnderEye_Shadow_L", "UnderEye_Shadow_R", "Nose_Bridge", "Nose_Tip",
}


def _skin_nearest(points: np.ndarray, source: np.ndarray, joints: np.ndarray,
                  weights: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    nearest = []
    for chunk in np.array_split(points, max(1, (len(points) + 255) // 256)):
        distance = ((chunk[:, None, :] - source[None, :, :]) ** 2).sum(axis=2)
        nearest.extend(np.argmin(distance, axis=1))
    return joints[nearest], weights[nearest]


def _surface(name: str, points: np.ndarray, indices: np.ndarray,
             binds: np.ndarray) -> geometry.Geometry | None:
    if name == "Head_Main_Mesh":
        return geometry.student_face()
    if name == "Body_Cardigan_Torso":
        return geometry.student_torso()
    if name.startswith("Hand_Palm_"):
        right = name.endswith("R")
        return geometry.hand_geometry(binds[9 if right else 6], False, right)
    if name.startswith("Eye_"):
        role = name.split("_")[1].lower()
        return geometry.eye_patch(-1 if name.endswith("L") else 1, role)
    if name.startswith("Upper_Eyelid_"):
        return geometry.eyelid(-1 if name.endswith("L") else 1)
    if name.startswith("Eyebrow_"):
        return geometry.brow(-1 if name.endswith("L") else 1)
    if name.startswith("Nostril_Shadow_"):
        x = -.008 if name.endswith("L") else .007
        z = float(geometry.student_front(np.asarray(x), np.asarray(1.540))) + .0006
        return geometry.ellipsoid([x, 1.540, z], [.0026, .0013, .0006], 20, 8)
    if name == "Mouth_Line":
        return geometry.tube([[-.026, 1.492, .111], [-.014, 1.490, .116],
                              [0, 1.4895, .118], [.014, 1.490, .116], [.026, 1.491, .111]],
                             [.0008, .0014, .0015, .0012, .0007], 10, .64)
    if name == "Lower_Lip_Plane":
        return geometry.tube([[-.019, 1.486, .112], [-.010, 1.484, .117],
                              [0, 1.483, .119], [.010, 1.484, .117], [.018, 1.486, .112]],
                             [.0008, .0018, .0021, .0018, .0008], 12, .7)
    if name == "Hair_Cap":
        return geometry.student_hair_cap()
    if name.startswith("Hair_Fringe_Lock_"):
        index = int(name.rsplit("_", 1)[1]) - 1
        x = -.057 + index * .027
        path = [[x + .015, 1.716 - index * .001], [x + .010, 1.690 - index * .002],
                [x - .004, 1.662 - index * .003], [x - .015, 1.631 + index * .002]]
        return geometry.tube([[xx, yy, geometry.student_hair_front(xx, yy)] for xx, yy in path],
                             [.010, .013, .010, .0025], 12, .24)
    if name.startswith("Hair_Side_Lock_"):
        side = -1 if name.endswith("L") else 1
        return geometry.tube([[side * .084, 1.650, .035], [side * .087, 1.621, .045],
                              [side * .086, 1.598, .048], [side * .080, 1.578, .043]],
                             [.009, .011, .008, .0025], 12, .6)
    if name.startswith("Cardigan_UpperSleeve_"):
        return geometry.student_sleeve(points, binds[4 if name.endswith("L") else 7], True)
    if name.startswith("Cardigan_LowerSleeve_"):
        return geometry.student_sleeve(points, binds[5 if name.endswith("L") else 8], False)
    if name.startswith(("Cardigan_Lapel_", "Shirt_Collar_")) or name in ("Shirt_Front_Panel", "Cardigan_Pocket"):
        side = -1 if name.endswith("Left") else 1
        if name.startswith("Cardigan_Lapel_"):
            xy = [[side * .111, 1.360], [side * .027, 1.354],
                  [side * .024, 1.181], [side * .074, 1.248]]
        elif name.startswith("Shirt_Collar_"):
            xy = [[side * .048, 1.394], [side * .006, 1.378],
                  [side * .025, 1.337], [side * .064, 1.371]]
        elif name == "Shirt_Front_Panel":
            xy = [[-.032, 1.365], [.032, 1.365], [.029, 1.086], [-.032, 1.086]]
        else:
            xy = [[-.121, 1.151], [-.073, 1.151], [-.074, 1.090], [-.117, 1.091]]
        xy = np.asarray(xy)
        return geometry.garment_panel(xy, .006 if "Collar" in name else .004)
    if name.startswith("Cardigan_Button_") or name == "Paint_Mark_Lower_Cardigan":
        shaped = points.copy()
        y, x = points[:, 1].mean(), points[:, 0].mean()
        shaped[:, 2] += float(geometry.student_garment_front(np.asarray(x), np.asarray(y))) + .007 - points[:, 2].mean()
        return geometry.Geometry(shaped, indices.reshape(-1, 3))
    if name in ("Ear_L", "Ear_R", "Ear_Inner_L", "Ear_Inner_R"):
        p = points.copy()
        c = (p.min(0) + p.max(0)) / 2
        p = c + (p - c) * [1.0, .87, .90]
        return geometry.rounded_source(p, indices.reshape(-1, 3), 1)
    if name == "Neck":
        p = points.copy()
        p[:, 2] -= .012 * np.clip((p[:, 1] - 1.36) / .09, 0, 1)
        return geometry.rounded_source(p, indices.reshape(-1, 3), 1)
    if (name in ("Trousers_Hip", "Hair_Back", "Shoe_L", "Shoe_R")
            or name.startswith(("Sleeve_Cuff_", "Trouser_Thigh_", "Trouser_Shin_"))):
        return geometry.rounded_source(points, indices.reshape(-1, 3), 1)
    return None


def prepare(data: bytes) -> bytes:
    if hashlib.sha256(data).hexdigest() != SOURCE_SHA256:
        raise ValueError("the immutable student source changed; review it before changing the pin")
    document, binary = load_glb(data)
    if document.get("animations") or len(document["skins"]) != 1:
        raise ValueError("the source is no longer the unanimated single-skin student")
    found = {n["name"] for n in document["nodes"]} & REMOVED_NODES
    if found != REMOVED_NODES:
        raise ValueError(f"source component names changed: missing {sorted(REMOVED_NODES - found)}")
    nodes = document["nodes"]
    removed_meshes = {n["mesh"] for n in nodes if n["name"] in REMOVED_NODES}
    node_map = {old: new for new, old in enumerate(i for i, n in enumerate(nodes)
                                                  if n["name"] not in REMOVED_NODES)}
    mesh_map = {old: new for new, old in enumerate(i for i in range(len(document["meshes"]))
                                                  if i not in removed_meshes)}
    names = {n["mesh"]: n["name"] for n in nodes if "mesh" in n}
    skin = document["skins"][0]
    binds = read_accessor(document, binary, skin["inverseBindMatrices"])
    frames = binds.reshape(-1, 4, 4).transpose(0, 2, 1)
    builder = Builder()
    meshes = []
    for index, mesh in enumerate(document["meshes"]):
        if index not in mesh_map:
            continue
        name = names[index]
        prims = []
        for primitive in mesh["primitives"]:
            a = primitive["attributes"]
            p, n, j, w = [read_accessor(document, binary, a[key])
                           for key in ["POSITION", "NORMAL", "JOINTS_0", "WEIGHTS_0"]]
            t = read_accessor(document, binary, primitive["indices"]).ravel()
            shaped = _surface(name, p, t, frames)
            if shaped is not None:
                if name.startswith("Hand_Palm_"):
                    j, w = geometry.skin_arrays(len(shaped.positions), 9 if name.endswith("R") else 6)
                else:
                    j, w = _skin_nearest(shaped.positions, p, j, w)
                p, n, t = shaped.positions, geometry.normals(shaped), shaped.triangles.ravel()
            prims.append({"attributes": {
                "POSITION": builder.add(p, "VEC3", 5126, ARRAY_BUFFER, bounds=True),
                "NORMAL": builder.add(n, "VEC3", 5126, ARRAY_BUFFER),
                "JOINTS_0": builder.add(j, "VEC4", 5121, ARRAY_BUFFER),
                "WEIGHTS_0": builder.add(quantize_weights(w), "VEC4", 5121, ARRAY_BUFFER,
                                         normalized=True),
            }, "indices": builder.add(t.reshape(-1, 1), "SCALAR", 5123, ELEMENT_ARRAY_BUFFER),
                "material": primitive["material"]})
        meshes.append({"name": mesh["name"], "primitives": prims})
    kept_nodes = []
    for index, node in enumerate(nodes):
        if index not in node_map:
            continue
        node = copy.deepcopy(node)
        if "children" in node:
            node["children"] = [node_map[c] for c in node["children"] if c in node_map]
        if "mesh" in node:
            node["mesh"] = mesh_map[node["mesh"]]
        kept_nodes.append(node)
    skin = copy.deepcopy(skin)
    skin["joints"] = [node_map[j] for j in skin["joints"]]
    skin["inverseBindMatrices"] = builder.add(binds, "MAT4", 5126)
    if "skeleton" in skin:
        skin["skeleton"] = node_map[skin["skeleton"]]
    scenes = copy.deepcopy(document["scenes"])
    for scene in scenes:
        scene["nodes"] = [node_map[n] for n in scene["nodes"] if n in node_map]
    result = {"asset": {"version": "2.0", "generator": "where-is-school prepare_classroom_student.py",
                        "extras": {"source": str(SOURCE.relative_to(ROOT)),
                                   "source_sha256": SOURCE_SHA256, "geometry_revision": 1}},
              "scene": document.get("scene", 0), "scenes": scenes, "nodes": kept_nodes,
              "meshes": meshes, "materials": document["materials"], "skins": [skin],
              "accessors": builder.accessors, "bufferViews": builder.views,
              "buffers": [{"byteLength": len(builder.binary)}]}
    return write_glb(result, builder.binary)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        result = prepare(SOURCE.read_bytes())
        if args.check:
            if OUTPUT.read_bytes() != result:
                raise ValueError("student runtime differs; run tools/prepare_classroom_student.py")
            print("PASS: the refined seated student is reproducible from its immutable source")
        else:
            OUTPUT.write_bytes(result)
            print(f"WROTE {OUTPUT.relative_to(ROOT)} ({len(result):,} bytes)")
    except (OSError, ValueError, KeyError) as error:
        print(f"FAIL: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
