#!/usr/bin/env python3
"""Refine the owner-authored seated student, preserving the exact original 16-joint rig.

    python3 tools/prepare_classroom_student.py
    python3 tools/prepare_classroom_student.py --check

The supplied blockout is preserved byte-for-byte under art/character_models/ (excluded
from imports/exports). The deterministic revision cuts smaller anatomical eyes and a
swept crop, bends the welded hands and tailors the knit around a seated silhouette. It is
not a replacement player, an animation controller, a new bone hierarchy or a claim of
equivalence to a commercial game's finished artwork.
Build tools only: the existing pinned numpy and GLB reader/writer from prepare_teacher_n.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
from pathlib import Path

import numpy as np

import character_geometry as geometry
from character_sculpt import apply
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


def _elbow_skin(points: np.ndarray, binds: np.ndarray, right: bool) -> tuple[np.ndarray, np.ndarray]:
    """Both sides of the sleeve overlap use the same forearm-local weight field."""
    arm, elbow = (7, 8) if right else (4, 5)
    distance = points @ binds[elbow, 1, :3] + binds[elbow, 1, 3]
    flex = geometry.smoothstep(-.031, .042, distance)
    joints, weights = geometry.skin_arrays(len(points), arm)
    joints[:, 1], weights[:, 0], weights[:, 1] = elbow, 1 - flex, flex
    return joints, weights


def _resting_lips(lower: bool) -> geometry.Geometry:
    x = np.linspace(-.021, .023, 13) * (.79 if lower else 1)
    t = x / .023
    y = 1.490 - .0018 * t - .0021 * t ** 2 - (.0038 if lower else 0)
    z = geometry.student_front(x, y) + (.00085 if lower else .00068)
    r = .00035 + (.00125 if lower else .00077) * (1 - np.abs(t))
    return geometry.tube(np.c_[x, y, z].tolist(), r.tolist(), 9, .70)


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
        x = -.0105 if name.endswith("L") else .0085
        y = 1.5396 if x < 0 else 1.5413
        z = float(geometry.student_front(x, y)) + .0001
        return geometry.ellipsoid([x, y, z], [.00235, .00092, .0005], 16, 7)
    if name in ("Mouth_Line", "Lower_Lip_Plane"):
        return _resting_lips(name.startswith("Lower"))
    if name == "Hair_Cap":
        return geometry.student_hair_cap()
    if name.startswith("Hair_Fringe_Lock_"):
        return geometry.student_fringe(int(name.rsplit("_", 1)[1]) - 1)
    if name.startswith("Hair_Side_Lock_"):
        side = -1 if name.endswith("L") else 1
        tip = 1.591 if side < 0 else 1.581
        return geometry.tube([[side * .084, 1.645, .034], [side * .088, 1.618, .048],
                              [side * .085, tip + .011, .051], [side * .080, tip, .048]],
                             [.007, .008, .006, .0025], 10, .56)
    if name.startswith("Cardigan_UpperSleeve_"):
        return geometry.student_sleeve(points, binds[4 if name.endswith("L") else 7], True, name.endswith("R"))
    if name.startswith("Cardigan_LowerSleeve_"):
        return geometry.student_sleeve(points, binds[5 if name.endswith("L") else 8], False, name.endswith("R"))
    if name.startswith(("Cardigan_Lapel_", "Shirt_Collar_")) or name in ("Shirt_Front_Panel", "Cardigan_Pocket"):
        side = -1 if name.endswith("Left") else 1
        if name.startswith("Cardigan_Lapel_"):
            # One side lies flatter, the other rocks away from the shoulder seam.
            xy = [[side * .104, 1.352], [side * .031, 1.355],
                  [side * .022, 1.180], [side * .074, 1.258 + .015 * side]]
        elif name.startswith("Shirt_Collar_"):
            xy = [[side * .049, 1.393], [side * .006, 1.378],
                  [side * .030, 1.335 + .006 * side], [side * .069, 1.357 + .004 * side]]
        elif name == "Shirt_Front_Panel":
            xy = [[-.031, 1.367], [.032, 1.366], [.023, 1.073], [-.027, 1.073]]
        else:
            xy = [[-.130, 1.153], [-.065, 1.147], [-.070, 1.083], [-.118, 1.088]]
        xy = np.asarray(xy)
        relief = .008 if "Collar" in name else .0055 if "Lapel" in name else .0038
        return geometry.garment_panel(xy, relief)
    if name.startswith("Cardigan_Button_") or name == "Paint_Mark_Lower_Cardigan":
        shaped = points.copy()
        y, x = points[:, 1].mean(), points[:, 0].mean()
        shaped[:, 2] += float(geometry.student_garment_front(np.asarray(x), np.asarray(y))) + .007 - points[:, 2].mean()
        return geometry.Geometry(shaped, indices.reshape(-1, 3))
    if name in ("Ear_L", "Ear_R", "Ear_Inner_L", "Ear_Inner_R"):
        p = points.copy()
        c = (p.min(0) + p.max(0)) / 2
        p = c + (p - c) * [1.0, .83, .88]
        # Taper the lobule and tip the helix back rather than presenting a round disk.
        p[:, 0] = np.sign(c[0]) * (np.abs(p[:, 0]) - .004)
        p[:, 2] -= (p[:, 1] - c[1]) * .31 + (.003 if "Inner" in name else 0)
        return geometry.rounded_source(p, indices.reshape(-1, 3), 1)
    if name == "Neck":
        p = points.copy()
        p[:, 2] -= .012 * np.clip((p[:, 1] - 1.36) / .09, 0, 1)
        return geometry.rounded_source(p, indices.reshape(-1, 3), 1)
    if (name in ("Trousers_Hip", "Hair_Back", "Shoe_L", "Shoe_R")
            or name.startswith(("Sleeve_Cuff_", "Trouser_Thigh_", "Trouser_Shin_"))):
        return geometry.rounded_source(points, indices.reshape(-1, 3), 1)
    return None


def prepare_base(data: bytes) -> bytes:
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
                elif name.startswith(("Cardigan_UpperSleeve_", "Cardigan_LowerSleeve_")):
                    j, w = _elbow_skin(shaped.positions, frames, name.endswith("R"))
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
                                   "source_sha256": SOURCE_SHA256, "geometry_revision": 2}},
              "scene": document.get("scene", 0), "scenes": scenes, "nodes": kept_nodes,
              "meshes": meshes, "materials": document["materials"], "skins": [skin],
              "accessors": builder.accessors, "bufferViews": builder.views,
              "buffers": [{"byteLength": len(builder.binary)}]}
    return write_glb(result, builder.binary)


def prepare(data: bytes) -> bytes:
    return apply(prepare_base(data), "seated")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        result = prepare(SOURCE.read_bytes())
        if args.check:
            if OUTPUT.read_bytes() != result:
                raise ValueError("student runtime differs; run tools/prepare_classroom_student.py")
            print("PASS: the refined seated student is reproducible from its immutable source and Blender head layer")
        else:
            OUTPUT.write_bytes(result)
            print(f"WROTE {OUTPUT.relative_to(ROOT)} ({len(result):,} bytes)")
    except (OSError, ValueError, KeyError) as error:
        print(f"FAIL: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
