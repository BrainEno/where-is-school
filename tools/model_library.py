#!/usr/bin/env python3
"""Read the model library under `assets/models/` and hold it to the pipeline contract.

`docs/ASSET_PIPELINE.md` §1 is a list of promises a `.glb` makes to the rest of the
project: metres, +Y up, faces -Z, no node scale, no cameras, no lights. §3 says where a
model file lives. Until now both were prose: nothing in CI had ever looked inside a
`.glb`, so a model could arrive with a camera in it, a 2x node scale that throws off every
collision shape written against it, or 4K textures that blow the 16 MiB pack budget on
their own, and the first time anyone found out was a red export job weeks later.

This tool is the reader. `--check` walks every `assets/models/**/*.glb` and fails on the
things the pipeline says must not be there; `--report` prints the catalogue that
`docs/MODEL_LIBRARY.md` is built from, so the numbers in the documentation cannot drift
away from the files.

What it checks, and why each one is a failure rather than a note:

- **The file parses.** A `.glb` that Godot cannot read is not a model. Cheap to catch and
  it makes every other number below trustworthy.
- **No node scale, no node matrix.** §1 asks for a model whose mesh is in metres. A scaled
  node means the numbers in the file are not the numbers on screen, so a wrapper's
  `CollisionShape3D` (authored against those numbers) is wrong by exactly the scale factor
  — the class of bug that reads as "the collision is a bit off" instead of "this model
  lies about its size".
- **No cameras, no lights.** A glTF camera imported into a `.tscn` silently replaces not
  only the shot but the whole `.tscn`'s camera if a wrapper is instanced wholesale, and a
  light in a prop double-lights the scene. Neither belongs inside geometry.
- **File size inside the budget `tools/verify_build.py` already enforces.** The same table
  is reused here (not copied) so the two can never disagree; the number that fails a
  release should fail at the commit that adds the file.
- **Embedded images inside a texture budget.** An embedded PNG/JPEG is texture weight that
  ends up in the pack. One model that inlines three 4K maps is larger than the entire
  release budget; it is a source file, not a runtime asset.
- **A sidecar next to the model.** Godot writes `<name>.glb.import` beside every imported
  file and the repository commits them; without it a fresh clone re-imports with default
  options and whatever the author configured is lost. The sidecar is also checked for a
  `dest_files` hash that matches the model's `res://` path, because that hash is what
  `git mv`-ing a model without its `.import` breaks.
- **Model names are unique across the library.** Wrappers, tests and `.gitignore`
  exceptions are all written against a model's bare name; two files called the same thing
  make `grep` and code review lie.

What it does *not* check: triangles, materials, or where a model's origin is. Triangles are
a judgement call per model (the protagonist is 12k, the playground bench 8k, the corridor's
fire extinguisher 420), and an origin is reported rather than enforced because §1's "on the
floor" is not true of every kind of prop: a ceiling fan's origin is on the ceiling and a
wall clock's is the middle of its own face. `--report` prints each model's `min y` and
`max y` so a wrapper can be built from them, and `docs/MODEL_LIBRARY.md` says how to read
the two numbers for a floor prop, a wall fixture and a ceiling fixture.

Usage:

    python3 tools/model_library.py --check     # CI: fails on a contract violation
    python3 tools/model_library.py --report    # markdown table for docs/MODEL_LIBRARY.md

It needs no engine and no network.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LIBRARY = os.path.join(ROOT, "assets", "models")

sys.path.insert(0, HERE)

import verify_build as vb  # noqa: E402  (the path has to be set up first)

# The ceiling on bytes an individual `.glb` may carry as embedded images. `verify_build.py`
# allows 2 MiB for a single texture file and 8 MiB for the whole warning-level pack; a
# model that inlines more than a quarter of a megabyte of images is already a third of the
# pack, and the football that arrived in PR #85 inlined 66 MiB.
EMBED_WARN = 512 * 1024
EMBED_HARD = 2 * 1024 * 1024

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


class Problem(Exception):
    """A `.glb` that cannot be read far enough to be judged."""


def read_glb(path: str) -> tuple[dict, bytes, int]:
    """Return `(gltf_json, bin_chunk, image_bytes)` for a binary glTF file.

    Only the pieces this tool needs: the JSON chunk, the BIN chunk the vertex pass reads,
    and how many bytes of it belong to `images` (a `bufferView` or a data URI), which is
    what the pack has to carry.
    """
    with open(path, "rb") as handle:
        data = handle.read()
    if len(data) < 12:
        raise Problem("shorter than a GLB header (%d bytes)" % len(data))
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise Problem("not a GLB (bad magic)")
    if version != 2:
        raise Problem("glTF version %d, this project imports version 2" % version)
    if length != len(data):
        raise Problem("header says %d bytes, file is %d" % (length, len(data)))

    gltf = None
    binary = b""
    offset = 12
    while offset + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        payload = data[offset : offset + chunk_length]
        offset += chunk_length
        if chunk_type == CHUNK_JSON:
            try:
                gltf = json.loads(payload.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise Problem("JSON chunk does not parse (%s)" % error) from None
        elif chunk_type == CHUNK_BIN:
            binary = payload
    if gltf is None:
        raise Problem("no JSON chunk")

    images = 0
    buffer_views = gltf.get("bufferViews", [])
    for image in gltf.get("images", []):
        view = image.get("bufferView")
        if isinstance(view, int) and 0 <= view < len(buffer_views):
            images += int(buffer_views[view].get("byteLength", 0)) or 0
        uri = image.get("uri")
        if isinstance(uri, str) and uri.startswith("data:"):
            # base64 payload: 4 characters carry 3 bytes, minus the padding.
            payload = uri.split(",", 1)[-1]
            images += len(payload) * 3 // 4 - payload.count("=", len(payload) - 2)
    return gltf, binary, images


def _accessor_count(gltf: dict, index: int) -> int:
    accessors = gltf.get("accessors", [])
    if 0 <= index < len(accessors):
        return int(accessors[index].get("count", 0)) or 0
    return 0


def _quat_matrix(q: list[float]) -> list[list[float]]:
    """Rotation matrix of a glTF quaternion, `[x, y, z, w]`."""
    x, y, z, w = q
    return [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]


def _local_matrix(node: dict) -> list[list[float]]:
    """A node's own transform as a 4×4 row-major matrix (identity if it has none)."""
    if "matrix" in node:  # column-major in glTF
        m = [float(v) for v in node["matrix"]]
        return [[m[col * 4 + row] for col in range(4)] for row in range(4)]
    t = [float(v) for v in node.get("translation", [0.0, 0.0, 0.0])]
    r = _quat_matrix([float(v) for v in node.get("rotation", [0.0, 0.0, 0.0, 1.0])])
    s = [float(v) for v in node.get("scale", [1.0, 1.0, 1.0])]
    return [
        [r[0][0] * s[0], r[0][1] * s[1], r[0][2] * s[2], t[0]],
        [r[1][0] * s[0], r[1][1] * s[1], r[1][2] * s[2], t[1]],
        [r[2][0] * s[0], r[2][1] * s[1], r[2][2] * s[2], t[2]],
        [0.0, 0.0, 0.0, 1.0],
    ]


def _multiply(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
    return [[sum(a[row][k] * b[k][col] for k in range(4)) for col in range(4)]
            for row in range(4)]


def _apply(m: list[list[float]], point: list[float]) -> list[float]:
    x, y, z = point
    return [m[row][0] * x + m[row][1] * y + m[row][2] * z + m[row][3] for row in range(3)]


def _node_transforms(gltf: dict) -> list[list[list[float]]]:
    """World matrix per node index, walking the scene graph from its roots.

    Node transforms are not decoration: `stationery_supplies.glb` is nine meshes laid out
    by nine `translation`s, and a bounding box built from the accessors alone reports that
    arrangement as 8 cm deep instead of 30. Every number in the catalogue is world space.
    """
    nodes = gltf.get("nodes", [])
    identity = [[1.0 if row == col else 0.0 for col in range(4)] for row in range(4)]
    world: list[list[list[float]] | None] = [None] * len(nodes)
    roots: list[int] = []
    scenes = gltf.get("scenes", [])
    if scenes and isinstance(gltf.get("scene", 0), int) and 0 <= gltf["scene"] < len(scenes):
        roots = [int(i) for i in scenes[gltf["scene"]].get("nodes", []) if 0 <= int(i) < len(nodes)]
    if not roots:  # no scene, or a scene that lists nothing: treat every node as a root
        referenced = {int(c) for node in nodes for c in node.get("children", [])}
        roots = [i for i in range(len(nodes)) if i not in referenced]
    stack = [(index, identity) for index in roots]
    while stack:
        index, parent = stack.pop()
        if not (0 <= index < len(nodes)) or world[index] is not None:
            continue
        matrix = _multiply(parent, _local_matrix(nodes[index]))
        world[index] = matrix
        for child in nodes[index].get("children", []):
            stack.append((int(child), matrix))
    for index in range(len(nodes)):  # nodes the scene never reaches still count
        if world[index] is None:
            world[index] = _local_matrix(nodes[index])
    return [matrix or identity for matrix in world]


_COMPONENTS = {
    5120: ("b", 1, 127.0),
    5121: ("B", 1, 255.0),
    5122: ("h", 2, 32767.0),
    5123: ("H", 2, 65535.0),
    5125: ("I", 4, 0.0),
    5126: ("f", 4, 0.0),
}


def _positions(gltf: dict, binary: bytes, accessor_index: int) -> list[tuple[float, float, float]]:
    """Decode a POSITION accessor into world-independent vertex positions.

    Read from the buffer rather than from the accessor's `min`/`max`, because those are
    per-primitive and say nothing about where the node puts the primitive. The corner
    method — transform the eight corners of each accessor's box — is cheaper, but it
    inflates the result for every rotated part, and this set has 27 rotated parts in the
    window curtains alone: a 0.12 m deep curtain read as 0.18 m that way.
    """
    accessors = gltf.get("accessors", [])
    views = gltf.get("bufferViews", [])
    if not (0 <= accessor_index < len(accessors)):
        return []
    accessor = accessors[accessor_index]
    if accessor.get("type") != "VEC3" or "bufferView" not in accessor:
        return []
    view = views[accessor["bufferView"]] if 0 <= accessor["bufferView"] < len(views) else None
    if view is None:
        return []
    code, width, norm = _COMPONENTS.get(int(accessor.get("componentType", 5126)), ("f", 4, 0.0))
    count = int(accessor.get("count", 0))
    stride = int(view.get("byteStride", 0)) or width * 3
    start = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
    limit = int(view.get("byteOffset", 0)) + int(view.get("byteLength", 0))
    points = []
    for index in range(count):
        at = start + index * stride
        if at + width * 3 > min(limit, len(binary)):
            break
        values = struct.unpack_from("<" + code * 3, binary, at)
        if norm:
            values = tuple(v / norm for v in values)
        points.append(values)
    return points


def measure(gltf: dict, binary: bytes = b"") -> dict:
    """Triangles, vertices, materials and the world-space bounding box."""
    triangles = 0
    vertices = 0
    for mesh in gltf.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            if int(primitive.get("mode", 4)) != 4:  # TRIANGLES
                continue
            position = primitive.get("attributes", {}).get("POSITION")
            if not isinstance(position, int):
                continue
            vertices += _accessor_count(gltf, position)
            indices = primitive.get("indices")
            count = _accessor_count(gltf, indices) if isinstance(indices, int) else None
            triangles += (count if count is not None else vertices) // 3

    world = _node_transforms(gltf)
    accessors = gltf.get("accessors", [])
    meshes = gltf.get("meshes", [])
    low = [0.0, 0.0, 0.0]
    high = [0.0, 0.0, 0.0]
    seen = False
    for index, node in enumerate(gltf.get("nodes", [])):
        mesh_index = node.get("mesh")
        if not isinstance(mesh_index, int) or not (0 <= mesh_index < len(meshes)):
            continue
        for primitive in meshes[mesh_index].get("primitives", []):
            position = primitive.get("attributes", {}).get("POSITION")
            if not isinstance(position, int) or not (0 <= position < len(accessors)):
                continue
            points = _positions(gltf, binary, position)
            accessor = accessors[position]
            lo, hi = accessor.get("min"), accessor.get("max")
            if not points:
                # Nothing to decode (no buffer, or a compressed accessor): fall back to the
                # accessor's own box, which is still true of the primitive, just coarser.
                if not (isinstance(lo, list) and isinstance(hi, list)) or len(lo) < 3:
                    continue
                points = [[lo[axis] if corner & (1 << axis) else hi[axis] for axis in range(3)]
                          for corner in range(8)]
            for point in points:
                moved = _apply(world[index], point)
                if not seen:
                    low, high, seen = list(moved), list(moved), True
                else:
                    for axis in range(3):
                        low[axis] = min(low[axis], moved[axis])
                        high[axis] = max(high[axis], moved[axis])

    return {
        "triangles": triangles,
        "vertices": vertices,
        "materials": len(gltf.get("materials", [])),
        "images": len(gltf.get("images", [])),
        "size": [high[i] - low[i] for i in range(3)] if seen else [0.0, 0.0, 0.0],
        "low": low if seen else [0.0, 0.0, 0.0],
        "high": high if seen else [0.0, 0.0, 0.0],
    }


def sidecar_problems(model_path: str, root: str = ROOT) -> list[str]:
    """Does `<model>.glb.import` exist, point at this model, and hash the right path?"""
    sidecar = model_path + ".import"
    if not os.path.exists(sidecar):
        return ["no %s.import beside it (Godot writes one per imported file; commit it)"
                % os.path.basename(model_path)]
    with open(sidecar, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    problems = []
    res_path = "res://" + os.path.relpath(model_path, root).replace(os.sep, "/")
    if 'source_file="%s"' % res_path not in text:
        problems.append("its .import names a different source_file than %s" % res_path)
    digest = hashlib.md5(res_path.encode()).hexdigest()
    if digest not in text:
        problems.append(
            "its .import dest_files hash is not md5(%s) — the model was moved or renamed "
            "without its sidecar being updated" % res_path
        )
    return problems


def collect() -> list[str]:
    """Every `.glb` under `assets/models/`, sorted by path."""
    found = []
    for dirpath, dirnames, filenames in os.walk(LIBRARY):
        dirnames.sort()
        for name in sorted(filenames):
            if name.lower().endswith(".glb"):
                found.append(os.path.join(dirpath, name))
    return found


def kind_of(model_path: str) -> str:
    """The directory a model sits in. That directory *is* its kind.

    `assets/models/<kind>/<name>.glb` is the layout `docs/ASSET_PIPELINE.md` §3 promises:
    `protagonist/`, `q/` (characters), `classroom/`, `corridor/`, `playground/` (a room's
    furniture and fixtures), and the one-model directories (`school_desk/`, `student_backpack/`, …).
    """
    return os.path.basename(os.path.dirname(model_path))


def audit(models: list[str], root: str = ROOT) -> tuple[list[str], list[str], dict[str, dict]]:
    """Return `(problems, notes, measurements)`. Problems fail `--check`; notes do not."""
    problems: list[str] = []
    notes: list[str] = []
    measured: dict[str, dict] = {}
    stems: dict[str, str] = {}

    model_category = vb.BY_NAME["model"]

    for path in models:
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        size = os.path.getsize(path)
        try:
            gltf, binary, image_bytes = read_glb(path)
        except Problem as error:
            problems.append("%s: %s" % (rel, error))
            continue

        info = measure(gltf, binary)
        info["bytes"] = size
        info["image_bytes"] = image_bytes
        info["kind"] = kind_of(path)
        measured[rel] = info

        stem = os.path.splitext(os.path.basename(path))[0]
        if stem in stems:
            problems.append("%s: another model is already called %s (%s)"
                            % (rel, stem, stems[stem]))
        else:
            stems[stem] = rel

        for node in gltf.get("nodes", []):
            name = node.get("name", "(unnamed)")
            if "matrix" in node:
                problems.append("%s: node %s uses a matrix transform, §1 asks for a plain "
                                "transform the wrapper can read" % (rel, name))
            scale = node.get("scale")
            if isinstance(scale, list) and any(abs(float(s) - 1.0) > 1e-4 for s in scale):
                problems.append("%s: node %s is scaled to %s, §1 asks for no node scale"
                                % (rel, name, scale))
        if gltf.get("cameras"):
            problems.append("%s: contains %d camera(s); a prop must not carry a camera"
                            % (rel, len(gltf["cameras"])))
        used = " ".join(gltf.get("extensionsUsed", []))
        for node in gltf.get("nodes", []):
            used += " " + " ".join((node.get("extensions") or {}).keys())
        if "KHR_lights_punctual" in used:
            problems.append("%s: contains a light; a prop must not carry a light" % rel)

        if size > model_category.hard:
            problems.append("%s: %.1f KiB is over the %.0f KiB hard budget for a model"
                            % (rel, size / 1024.0, model_category.hard / 1024.0))
        elif size > model_category.warn:
            notes.append("%s: %.1f KiB is over the %.0f KiB warning line"
                         % (rel, size / 1024.0, model_category.warn / 1024.0))
        if image_bytes > EMBED_HARD:
            problems.append("%s: %.1f KiB of embedded images, over the %.0f KiB ceiling — "
                            "this is a source file, not a runtime asset"
                            % (rel, image_bytes / 1024.0, EMBED_HARD / 1024.0))
        elif image_bytes > EMBED_WARN:
            notes.append("%s: %.1f KiB of embedded images, over the %.0f KiB warning line"
                         % (rel, image_bytes / 1024.0, EMBED_WARN / 1024.0))

        problems.extend("%s: %s" % (rel, line) for line in sidecar_problems(path, root))

    return problems, notes, measured


def _fmt(value: float) -> str:
    return ("%.2f" % value).rstrip("0").rstrip(".") if abs(value) < 100 else "%.0f" % value


def report(measured: dict[str, dict]) -> str:
    """The markdown catalogue, grouped by kind, in the shape docs/MODEL_LIBRARY.md uses."""
    lines: list[str] = []
    by_kind: dict[str, list[str]] = {}
    for rel, info in measured.items():
        by_kind.setdefault(info["kind"], []).append(rel)

    for kind in sorted(by_kind):
        rows = sorted(by_kind[kind])
        total = sum(measured[r]["bytes"] for r in rows)
        lines.append("### `%s/` — %d model%s, %.0f KiB"
                     % (kind, len(rows), "" if len(rows) == 1 else "s", total / 1024.0))
        lines.append("")
        lines.append("| model | KiB | tris | materials | textures | W × H × D (m) "
                     "| min y (m) | max y (m) |")
        lines.append("|---|---|---|---|---|---|---|---|")
        for rel in rows:
            info = measured[rel]
            size = " × ".join(_fmt(v) for v in info["size"])
            textures = ("%d (%.0f KiB)" % (info["images"], info["image_bytes"] / 1024.0)
                        if info["images"] else "—")
            lines.append("| `%s` | %.1f | %d | %d | %s | %s | %+.3f | %+.3f |"
                         % (os.path.splitext(os.path.basename(rel))[0],
                            info["bytes"] / 1024.0, info["triangles"], info["materials"],
                            textures, size, info["low"][1] + 0.0, info["high"][1] + 0.0))
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="fail on anything the pipeline contract forbids")
    parser.add_argument("--report", action="store_true",
                        help="print the markdown catalogue for docs/MODEL_LIBRARY.md")
    options = parser.parse_args(argv or ["--check"])

    root = os.path.dirname(os.path.dirname(LIBRARY))  # <root>/assets/models
    models = collect()
    if not models:
        print("MODEL_LIBRARY_PROBLEM: no .glb found under %s"
              % os.path.relpath(LIBRARY, root))
        return 1

    problems, notes, measured = audit(models, root)

    if options.report:
        sys.stdout.write(report(measured))
        return 0

    total = sum(i["bytes"] for i in measured.values())
    kinds = sorted({i["kind"] for i in measured.values()})
    print("%d model(s) in %d kind(s) (%s), %.1f KiB on disk"
          % (len(models), len(kinds), ", ".join(kinds), total / 1024.0))

    for note in notes:
        print("MODEL_LIBRARY_NOTE: " + note)
    if problems:
        for problem in problems:
            print("MODEL_LIBRARY_PROBLEM: " + problem)
        print("%d model(s) break the pipeline contract; see docs/ASSET_PIPELINE.md §1." % len(problems))
        return 1

    print("MODEL_LIBRARY_OK: every model parses, carries no scale/node matrix, camera or "
          "light, fits its budget, and has a matching .import sidecar.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
