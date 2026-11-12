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
- **The three runtime characters still have the structure
  `art/character_rig_audit/runtime_model_manifest.json` records.** Nodes, node paths, mesh
  and skin bindings, primitives, materials, the joint list in order, and the embedded
  animations (the former protagonist and Q have none; the protagonist embeds five the game
  does not play — its clips, like theirs, are built in
  `scripts/actors/character_animation.gd`) are compared against the file on every run. A
  lost bone, a split mesh, an unregistered node or an animation that appeared inside a
  `.glb` fails here; the other checks cannot see any of it, because a model can be clean,
  small, camera-free and still bound to a rig nobody declared. Structural changes are
  allowed — `--update-manifest` rewrites the record and the diff is the review.
- **The manifest is a document before it is a snapshot.** All three characters are
  registered, once each and nothing else; every structural field exists and has the right shape, and the
  counters agree with the lists they count; and mesh, skin and animation names are unique on
  both sides, because the comparison pairs resources by name and a duplicate would fold one
  of them out of the check. All of that is validated before a `.glb` is opened, and
  `--update-manifest` applies the same rules before it will touch the file.

What it does *not* check: triangles, materials, or where a model's origin is. Triangles are
a judgement call per model (the protagonist is 12k, the playground bench 8k, the corridor's
fire extinguisher 420), and an origin is reported rather than enforced because §1's "on the
floor" is not true of every kind of prop: a ceiling fan's origin is on the ceiling and a
wall clock's is the middle of its own face. `--report` prints each model's `min y` and
`max y` so a wrapper can be built from them, and `docs/MODEL_LIBRARY.md` says how to read
the two numbers for a floor prop, a wall fixture and a ceiling fixture.

Usage:

    python3 tools/model_library.py --check            # CI: fails on a contract violation
    python3 tools/model_library.py --report           # markdown table for docs/MODEL_LIBRARY.md
    python3 tools/model_library.py --update-manifest  # accept a reviewed structural change

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


# ---------------------------------------------------------------------------------------
# The runtime character manifest
# ---------------------------------------------------------------------------------------
#
# Everything above reads a model on its own terms: does it parse, is it in metres, is it
# inside the budget. None of it notices that the protagonist lost a hand bone, that a mesh
# was split in two, or that Q gained a node nobody meant to ship — the file is still clean,
# still the right size, still has no camera, and the character silently binds to a rig that
# is not the one the clips were written for.
#
# So the rigged models the game actually instantiates have a written-down structure:
# `art/character_rig_audit/runtime_model_manifest.json`. It is not a second audit of the
# Blender file and not a copy of the old rig audits — both of those describe different
# stages. It is what `REQUIRED_RUNTIME_MODELS` (the two protagonist models, Q and N)
# contain now, node by node, checked against the file on every `--check`.
#
# What it locks, and why each thing is structural rather than cosmetic:
#
# - **The node tree**, by path (`CHR_Protagonist_Root/RIG_Protagonist_Blockout/Neck`). A new
#   node, a lost node, a renamed node or a re-parented node all change a path. Paths — not
#   names — because both rigs contain two nodes called `Neck`, one a bone and one a mesh.
# - **Each node's mesh and skin binding.** A mesh that stops being skinned still renders;
#   it just stops following the bone it was bound to. That is invisible in every other check.
# - **Each mesh's primitive count and material.** Splitting a primitive is how a material
#   assignment changes, and a changed material assignment is a changed character.
# - **The material names.**
# - **The skins: the joint list, in order.** `JOINTS_0` stores *indices into* that list;
#   reordering it rebinds every vertex in the mesh to a different bone. The order is not a
#   detail, it is the bind.
# - **The embedded animations: names, channel counts and what each channel targets.** Both
#   models carry none, and that is a fact worth holding: the clips in
#   `scripts/actors/character_animation.gd` are built at run time against these bone names,
#   so an animation appearing inside a `.glb` means someone changed where animation comes
#   from without saying so.
#
# What it deliberately does not lock: node transforms, triangle and vertex counts, UVs,
# texture details, import metadata, file size. Those change with every legitimate art pass,
# and a manifest that fails on them would be a file lock nobody could work behind. The size
# budget above still applies to these models, and node scale is still forbidden by §1. A
# structural change is allowed too — it just has to be made on purpose, by running
# `--update-manifest` and committing the diff, which is the review.

MANIFEST_SCHEMA = "where-is-school/runtime-model-manifest"
MANIFEST_SCHEMA_VERSION = 1
MANIFEST_PARTS = ("art", "character_rig_audit", "runtime_model_manifest.json")

# The four rigged characters the game actually instantiates, exactly as the manifest must
# spell them: the former protagonist (now the seated classroom student), Q, the player's
# protagonist and substitute teacher N. The manifest registers *these*, once each, and
# nothing else. "At least one model" is not the contract: deleting Q's entry would leave the
# file valid, plausible and silently unchecked, which is the failure this list exists to
# make impossible. Each new character is appended, so the earlier ones keep the indices the
# tests address them by.
REQUIRED_RUNTIME_MODELS = (
    "assets/models/protagonist/protagonist.glb",
    "assets/models/q/q.glb",
    "assets/models/protagonist/Protagonist_Character.glb",
    "assets/models/teacher-n/teacher-n.glb",
)

# The fields `describe_model` generates. `--update-manifest` replaces exactly these and
# keeps every other key of an entry, which is where the human writing lives (`wrapper`,
# `note`). A field nobody here produces is therefore preserved, not silently dropped.
MANIFEST_STRUCTURAL = ("counts", "scene_roots", "nodes", "meshes", "materials", "skins", "animations")

# Every counter `describe_model` writes into `counts`, and what each one counts. Validating
# the entries against these counters is what keeps a shortened list from passing as a
# smaller model: the lists and the counts have to agree with each other.
MANIFEST_COUNT_FIELDS = ("nodes", "meshes", "primitives", "materials", "skins", "joints",
                         "animations", "animation_channels")


class ManifestError(Exception):
    """A runtime model manifest that cannot be read as one."""


def manifest_path(root: str = ROOT) -> str:
    return os.path.join(root, *MANIFEST_PARTS)


def _node_paths(nodes: list[dict]) -> tuple[list[str], dict[int, int]]:
    """Every node's slash-joined path from its root, plus the child -> parent map.

    A path is a node's identity in the manifest. Names alone cannot be: `Neck` appears twice
    in both rigs. Siblings that genuinely share a name get an occurrence suffix (`#2`), so
    duplicating a node is a difference rather than an ambiguity.
    """
    parents: dict[int, int] = {}
    for index, node in enumerate(nodes):
        for child in node.get("children", []):
            if isinstance(child, int):
                parents[child] = index

    paths: list[str] = []
    occurrences: dict[str, int] = {}
    for index in range(len(nodes)):
        parts = []
        cursor: int | None = index
        guard: set[int] = set()
        while cursor is not None and cursor not in guard:
            guard.add(cursor)
            parts.append(nodes[cursor].get("name") or "(unnamed)")
            cursor = parents.get(cursor)
        if cursor is not None:  # a cycle: say so rather than loop forever
            parts.append("(cycle)")
        base = "/".join(reversed(parts))
        occurrences[base] = occurrences.get(base, 0) + 1
        paths.append(base if occurrences[base] == 1 else "%s#%d" % (base, occurrences[base]))
    return paths, parents


def describe_model(gltf: dict) -> dict:
    """The structural facts of one runtime model, in the shape the manifest stores them.

    Deterministic: every list is sorted by a stable key, so the same file always describes
    the same way and a diff between two manifests is a diff of structure.
    """
    nodes = gltf.get("nodes", [])
    meshes = gltf.get("meshes", [])
    materials = [material.get("name") or "(unnamed)" for material in gltf.get("materials", [])]
    paths, _parents = _node_paths(nodes)

    def path_of(index: object) -> str | None:
        if isinstance(index, int) and 0 <= index < len(paths):
            return paths[index]
        return None

    node_entries = []
    for index, node in enumerate(nodes):
        mesh_index = node.get("mesh")
        node_entries.append({
            "path": paths[index],
            "name": node.get("name") or "(unnamed)",
            "mesh": (meshes[mesh_index].get("name") or "(unnamed)")
            if isinstance(mesh_index, int) and 0 <= mesh_index < len(meshes) else None,
            "skin": node.get("skin") if isinstance(node.get("skin"), int) else None,
        })
    node_entries.sort(key=lambda entry: entry["path"])

    mesh_entries = []
    for mesh in meshes:
        primitives = []
        for primitive in mesh.get("primitives", []):
            material = primitive.get("material")
            attributes = primitive.get("attributes") or {}
            primitives.append({
                "material": materials[material]
                if isinstance(material, int) and 0 <= material < len(materials) else None,
                # Whether a vertex in this primitive carries bone weights. A primitive that
                # loses them stops following its skeleton without any other visible change.
                "skinned": "JOINTS_0" in attributes and "WEIGHTS_0" in attributes,
            })
        mesh_entries.append({"name": mesh.get("name") or "(unnamed)", "primitives": primitives})
    mesh_entries.sort(key=lambda entry: entry["name"])

    skin_entries = []
    for skin in gltf.get("skins", []):
        skin_entries.append({
            "name": skin.get("name") or "(unnamed)",
            "skeleton": path_of(skin.get("skeleton")),
            # Ordered: the order is what `JOINTS_0` indexes into.
            "joints": [path_of(joint) or str(joint) for joint in skin.get("joints", [])],
        })
    skin_entries.sort(key=lambda entry: entry["name"])

    animation_entries = []
    for animation in gltf.get("animations", []):
        channels = animation.get("channels", [])
        targets = []
        for channel in channels:
            target = channel.get("target") or {}
            targets.append({"node": path_of(target.get("node")), "path": target.get("path")})
        targets.sort(key=lambda target: (target["node"] or "", target["path"] or ""))
        animation_entries.append({
            "name": animation.get("name") or "(unnamed)",
            "channels": len(channels),
            "targets": targets,
        })
    animation_entries.sort(key=lambda entry: entry["name"])

    scenes = gltf.get("scenes", [])
    active = gltf.get("scene", 0 if scenes else None)
    scene_roots = []
    if isinstance(active, int) and 0 <= active < len(scenes):
        scene_roots = sorted(path for path in (path_of(node) for node in scenes[active].get("nodes", []))
                             if path is not None)

    return {
        "counts": {
            "nodes": len(nodes),
            "meshes": len(meshes),
            "primitives": sum(len(mesh.get("primitives", [])) for mesh in meshes),
            "materials": len(materials),
            "skins": len(skin_entries),
            "joints": sum(len(skin["joints"]) for skin in skin_entries),
            "animations": len(animation_entries),
            "animation_channels": sum(animation["channels"] for animation in animation_entries),
        },
        "scene_roots": scene_roots,
        "nodes": node_entries,
        "meshes": mesh_entries,
        "materials": sorted(materials),
        "skins": skin_entries,
        "animations": animation_entries,
    }


# --- reading the manifest as a document --------------------------------------
#
# The comparison below assumes the manifest has the shape `describe_model` writes. That
# assumption used to be checked entry by entry, halfway through the comparison, so a
# manifest with one broken entry could raise a KeyError in the middle of the loop, or — worse
# — compare the fields it happened to find and quietly skip the ones that were missing. The
# reader below checks the whole document *before* any `.glb` is opened: schema, required
# models, entry shape, element shape, name uniqueness and the counts' agreement with the
# lists. Everything it finds is a sentence, so the caller never has to print a traceback.

def _summarise(problems: list[str], limit: int = 4) -> str:
    """One line for a raised `ManifestError`, with the count kept honest."""
    shown = "; ".join(problems[:limit])
    if len(problems) > limit:
        shown += "; …and %d more" % (len(problems) - limit)
    return shown


def _duplicate_problems(entries: list, key: str, rel: str, owner: str) -> list[str]:
    """Names (or paths) that appear more than once in a list the comparison keys by.

    `compare_model` builds `{name: entry}` from both sides, so a duplicate collapses and one
    of the two entries becomes invisible to the check. The contract is therefore that these
    names are unique: duplicates are rejected as a problem, not folded away.
    """
    counts: dict[object, int] = {}
    for entry in entries:
        if isinstance(entry, dict):
            counts[entry.get(key)] = counts.get(entry.get(key), 0) + 1
    return ["%s: %s %r appears %d times, and the manifest compares by %s — the copies would "
            "collapse into one and hide a difference; give each one its own name"
            % (rel, owner, name, count, key)
            for name, count in sorted(counts.items(), key=lambda item: str(item[0]))
            if count > 1]


def _str_problems(value: object, label: str, optional: bool = False) -> list[str]:
    """A string, or (where the glTF allows it) null."""
    if value is None and optional:
        return []
    if not isinstance(value, str):
        wanted = "a string or null" if optional else "a string"
        return ["%s is %r, which is not %s" % (label, value, wanted)]
    return []


def _list_problems(value: object, label: str) -> list[str]:
    if not isinstance(value, list):
        return ["%s is %r, which is not a list" % (label, value)]
    return []


def _count_problems(value: object, label: str) -> list[str]:
    # `bool` is an `int` in Python and `true` is not a node count.
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        return ["%s is %r, which is not a count (a whole number, zero or more)" % (label, value)]
    return []


def _entry_shape_problems(entry: dict, label: str) -> list[str]:
    """The shape of one entry: which lists exist, what they hold, and whether they agree."""
    problems: list[str] = []

    for field in MANIFEST_STRUCTURAL:
        if field not in entry:
            problems.append("%s is missing %r; a field that is absent is a field the "
                            "comparison would skip" % (label, field))
    counts = entry.get("counts")
    if "counts" in entry:
        if not isinstance(counts, dict):
            problems.append("%s: counts is %r, which is not an object of counts"
                            % (label, counts))
        else:
            for field in MANIFEST_COUNT_FIELDS:
                if field not in counts:
                    problems.append("%s: counts is missing %r" % (label, field))
                else:
                    problems.extend(_count_problems(counts[field], "%s: counts.%s" % (label, field)))
            for field in sorted(set(counts) - set(MANIFEST_COUNT_FIELDS)):
                problems.append("%s: counts.%s is not a count this tool knows; the comparison "
                                "would ignore it" % (label, field))

    roots = entry.get("scene_roots")
    if "scene_roots" in entry:
        problems.extend(_list_problems(roots, "%s: scene_roots" % label))
        if isinstance(roots, list):
            for index, root in enumerate(roots):
                problems.extend(_str_problems(root, "%s: scene_roots[%d]" % (label, index)))

    nodes = entry.get("nodes")
    if "nodes" in entry:
        problems.extend(_list_problems(nodes, "%s: nodes" % label))
        if isinstance(nodes, list):
            for index, node in enumerate(nodes):
                node_label = "%s: nodes[%d]" % (label, index)
                if not isinstance(node, dict):
                    problems.append("%s is %r, which is not an object" % (node_label, node))
                    continue
                problems.extend(_str_problems(node.get("path"), node_label + ".path"))
                problems.extend(_str_problems(node.get("name"), node_label + ".name"))
                if not isinstance(node.get("mesh"), (str, type(None))):
                    problems.append("%s.mesh is %r, which is neither a mesh name nor null"
                                    % (node_label, node.get("mesh")))
                skin = node.get("skin")
                if isinstance(skin, bool) or not isinstance(skin, (int, type(None))):
                    problems.append("%s.skin is %r, which is neither a skin index nor null"
                                    % (node_label, skin))
            # A node's identity is its path, not its name: both rigs genuinely carry two
            # nodes called `Neck`, and `_node_paths` tells them apart with a `#2` suffix.
            problems.extend(_duplicate_problems(nodes, "path", label, "node"))

    meshes = entry.get("meshes")
    if "meshes" in entry:
        problems.extend(_list_problems(meshes, "%s: meshes" % label))
        if isinstance(meshes, list):
            for index, mesh in enumerate(meshes):
                mesh_label = "%s: meshes[%d]" % (label, index)
                if not isinstance(mesh, dict):
                    problems.append("%s is %r, which is not an object" % (mesh_label, mesh))
                    continue
                problems.extend(_str_problems(mesh.get("name"), mesh_label + ".name"))
                primitives = mesh.get("primitives")
                problems.extend(_list_problems(primitives, mesh_label + ".primitives"))
                if isinstance(primitives, list):
                    for number, primitive in enumerate(primitives):
                        primitive_label = "%s.primitives[%d]" % (mesh_label, number)
                        if not isinstance(primitive, dict):
                            problems.append("%s is %r, which is not an object"
                                            % (primitive_label, primitive))
                            continue
                        material = primitive.get("material", "absent")
                        if material != "absent" and not isinstance(material, (str, type(None))):
                            problems.append("%s.material is %r, which is neither a material "
                                            "name nor null" % (primitive_label, material))
                        if not isinstance(primitive.get("skinned"), bool):
                            problems.append("%s.skinned is %r, which is not true or false"
                                            % (primitive_label, primitive.get("skinned")))
            problems.extend(_duplicate_problems(meshes, "name", label, "mesh"))

    materials = entry.get("materials")
    if "materials" in entry:
        problems.extend(_list_problems(materials, "%s: materials" % label))
        if isinstance(materials, list):
            for index, material in enumerate(materials):
                problems.extend(_str_problems(material, "%s: materials[%d]" % (label, index)))

    skins = entry.get("skins")
    if "skins" in entry:
        problems.extend(_list_problems(skins, "%s: skins" % label))
        if isinstance(skins, list):
            for index, skin in enumerate(skins):
                skin_label = "%s: skins[%d]" % (label, index)
                if not isinstance(skin, dict):
                    problems.append("%s is %r, which is not an object" % (skin_label, skin))
                    continue
                problems.extend(_str_problems(skin.get("name"), skin_label + ".name"))
                problems.extend(_str_problems(skin.get("skeleton"), skin_label + ".skeleton",
                                              optional=True))
                joints = skin.get("joints")
                problems.extend(_list_problems(joints, skin_label + ".joints"))
                if isinstance(joints, list):
                    for number, joint in enumerate(joints):
                        problems.extend(_str_problems(
                            joint, "%s.joints[%d]" % (skin_label, number)))
            problems.extend(_duplicate_problems(skins, "name", label, "skin"))

    animations = entry.get("animations")
    if "animations" in entry:
        problems.extend(_list_problems(animations, "%s: animations" % label))
        if isinstance(animations, list):
            for index, animation in enumerate(animations):
                animation_label = "%s: animations[%d]" % (label, index)
                if not isinstance(animation, dict):
                    problems.append("%s is %r, which is not an object"
                                    % (animation_label, animation))
                    continue
                problems.extend(_str_problems(animation.get("name"), animation_label + ".name"))
                problems.extend(_count_problems(animation.get("channels"),
                                                animation_label + ".channels"))
                targets = animation.get("targets")
                problems.extend(_list_problems(targets, animation_label + ".targets"))
                if isinstance(targets, list):
                    for number, target in enumerate(targets):
                        target_label = "%s.targets[%d]" % (animation_label, number)
                        if not isinstance(target, dict):
                            problems.append("%s is %r, which is not an object"
                                            % (target_label, target))
                            continue
                        problems.extend(_str_problems(target.get("node"), target_label + ".node",
                                                      optional=True))
                        problems.extend(_str_problems(target.get("path"), target_label + ".path",
                                                      optional=True))
            problems.extend(_duplicate_problems(animations, "name", label, "animation"))

    problems.extend(_count_agreement_problems(entry, label))
    return problems


def _count_agreement_problems(entry: dict, label: str) -> list[str]:
    """The counters against the lists they count.

    Without this a shortened list would still compare against a stale counter and report one
    difference, when what actually happened is that the entry lost data.
    """
    counts = entry.get("counts")
    if not isinstance(counts, dict):
        return []
    problems: list[str] = []

    def compare(field: str, actual: int, what: str) -> None:
        stored = counts.get(field)
        if isinstance(stored, int) and not isinstance(stored, bool) and stored != actual:
            problems.append("%s: counts.%s is %d but the entry holds %d %s; the counter and "
                            "the list must agree" % (label, field, stored, actual, what))

    meshes = entry.get("meshes")
    nodes = entry.get("nodes")
    skins = entry.get("skins")
    animations = entry.get("animations")
    materials = entry.get("materials")
    if isinstance(nodes, list):
        compare("nodes", len(nodes), "nodes")
    if isinstance(meshes, list):
        compare("meshes", len(meshes), "meshes")
        primitives = [primitive for mesh in meshes if isinstance(mesh, dict)
                      for primitive in (mesh.get("primitives") or [])
                      if isinstance(mesh.get("primitives"), list)]
        compare("primitives", len(primitives), "primitives")
    if isinstance(materials, list):
        compare("materials", len(materials), "materials")
    if isinstance(skins, list):
        compare("skins", len(skins), "skins")
        joints = [joint for skin in skins if isinstance(skin, dict)
                  and isinstance(skin.get("joints"), list) for joint in skin["joints"]]
        compare("joints", len(joints), "joints")
    if isinstance(animations, list):
        compare("animations", len(animations), "animations")
        channels = sum(animation.get("channels") for animation in animations
                       if isinstance(animation, dict)
                       and isinstance(animation.get("channels"), int)
                       and not isinstance(animation.get("channels"), bool))
        compare("animation_channels", channels, "channels")
    return problems


def validate_manifest(document: object, rel_manifest: str,
                      required: tuple[str, ...] = REQUIRED_RUNTIME_MODELS) -> list[str]:
    """Every reason this document cannot be read as a runtime manifest, as sentences.

    Pure: it takes the parsed JSON and returns strings. `check_manifest` and
    `update_manifest` both call it first, so "the manifest is malformed" is diagnosed the
    same way by both, and neither can reach the comparison with a document whose shape it
    has not established.
    """
    if not isinstance(document, dict):
        return ["%s holds a %s, not an object" % (rel_manifest, type(document).__name__)]

    problems: list[str] = []
    if document.get("schema") != MANIFEST_SCHEMA:
        problems.append("%s: schema is %r, this tool reads %r"
                        % (rel_manifest, document.get("schema"), MANIFEST_SCHEMA))
    if document.get("schema_version") != MANIFEST_SCHEMA_VERSION:
        problems.append("%s: schema_version is %r, this tool reads %d"
                        % (rel_manifest, document.get("schema_version"), MANIFEST_SCHEMA_VERSION))

    entries = document.get("models")
    if not isinstance(entries, list) or not entries:
        problems.append("%s: 'models' is empty; a manifest that registers nothing checks "
                        "nothing" % rel_manifest)
        return problems

    # Which models are registered before how each entry is written: a manifest that gained
    # an entry or lost one is a completeness problem, and that is what the reader needs to
    # see first, not the shape of the stray entry.
    registered = [entry["path"] for entry in entries
                  if isinstance(entry, dict) and isinstance(entry.get("path"), str)]
    for path in sorted(set(registered) - set(required)):
        problems.append("%s: %s is registered but is not one of the runtime characters this "
                        "manifest covers; an extra entry starts a structural check nobody "
                        "asked for" % (rel_manifest, path))
    for path in required:
        count = registered.count(path)
        if count == 0:
            problems.append("%s: %s is a runtime character and has no entry; without one its "
                            "structure is not checked at all" % (rel_manifest, path))
        elif count > 1:
            problems.append("%s: %s is registered %d times; each runtime character has "
                            "exactly one entry" % (rel_manifest, path, count))

    for index, entry in enumerate(entries):
        label = "%s: models[%d]" % (rel_manifest, index)
        if not isinstance(entry, dict):
            problems.append("%s is %r, not an object" % (label, entry))
            continue
        path = entry.get("path")
        if not isinstance(path, str) or not path.strip():
            problems.append("%s has no 'path'; every entry names the model it covers" % label)
            problems.extend(_entry_shape_problems(entry, label))
            continue
        # Every shape problem names the model as well as the field: the reader of a red CI
        # job knows which character to open.
        if not path.startswith("assets/models/"):
            problems.append("%s: %s is registered, but the runtime manifest only covers "
                            "runtime models under assets/models/ — dev and retarget assets "
                            "are a different stage" % (rel_manifest, path))
        elif not path.endswith(".glb"):
            problems.append("%s: %s is not a .glb; the runtime models are glTF binary files"
                            % (rel_manifest, path))
        problems.extend(_entry_shape_problems(entry, "%s (%s)" % (label, path)))

    return problems


def identity_problems(actual: dict, rel: str) -> list[str]:
    """The same name-uniqueness contract, checked on the model's own lists."""
    return (_duplicate_problems(actual["meshes"], "name", rel, "the model's mesh")
            + _duplicate_problems(actual["skins"], "name", rel, "the model's skin")
            + _duplicate_problems(actual["animations"], "name", rel, "the model's animation"))


def compare_model(expected: dict, actual: dict, rel: str) -> list[str]:
    """Every structural difference between the manifest's record and the file, as sentences.

    Each line names the model, the field and both values. That is what makes a failure
    actionable without opening the manifest by hand: the reader is told *what* changed, not
    only that something did.
    """
    problems: list[str] = []

    for key, value in (expected.get("counts") or {}).items():
        if actual["counts"].get(key) != value:
            problems.append("%s: counts.%s is %s, the manifest says %s"
                            % (rel, key, actual["counts"].get(key), value))

    if sorted(expected.get("scene_roots") or []) != actual["scene_roots"]:
        problems.append("%s: the scene roots are %s, the manifest says %s"
                        % (rel, actual["scene_roots"], expected.get("scene_roots")))

    wanted = {node["path"]: node for node in expected.get("nodes") or []}
    have = {node["path"]: node for node in actual["nodes"]}
    for path in sorted(set(have) - set(wanted)):
        problems.append("%s: node %r is in the model and not in the manifest "
                        "(a node nobody registered was added)" % (rel, path))
    for path in sorted(set(wanted) - set(have)):
        problems.append("%s: node %r is registered and missing from the model" % (rel, path))
    for path in sorted(set(wanted) & set(have)):
        for field in ("name", "mesh", "skin"):
            if wanted[path].get(field) != have[path].get(field):
                problems.append("%s: node %r field %s is %r, the manifest says %r"
                                % (rel, path, field, have[path].get(field), wanted[path].get(field)))

    wanted_meshes = {mesh["name"]: mesh for mesh in expected.get("meshes") or []}
    have_meshes = {mesh["name"]: mesh for mesh in actual["meshes"]}
    for name in sorted(set(have_meshes) - set(wanted_meshes)):
        problems.append("%s: mesh %r is not in the manifest" % (rel, name))
    for name in sorted(set(wanted_meshes) - set(have_meshes)):
        problems.append("%s: mesh %r is registered and missing from the model" % (rel, name))
    for name in sorted(set(wanted_meshes) & set(have_meshes)):
        want = wanted_meshes[name].get("primitives") or []
        got = have_meshes[name]["primitives"]
        if len(want) != len(got):
            problems.append("%s: mesh %r has %d primitive(s), the manifest says %d"
                            % (rel, name, len(got), len(want)))
        for index in range(min(len(want), len(got))):
            for field in ("material", "skinned"):
                if want[index].get(field) != got[index].get(field):
                    problems.append("%s: mesh %r primitive %d %s is %r, the manifest says %r"
                                    % (rel, name, index, field, got[index].get(field),
                                       want[index].get(field)))

    wanted_materials = sorted(expected.get("materials") or [])
    if wanted_materials != actual["materials"]:
        added = sorted(set(actual["materials"]) - set(wanted_materials))
        removed = sorted(set(wanted_materials) - set(actual["materials"]))
        detail = []
        if added:
            detail.append("new: " + ", ".join(added[:6]))
        if removed:
            detail.append("gone: " + ", ".join(removed[:6]))
        problems.append("%s: materials are %d (%s), the manifest says %d"
                        % (rel, len(actual["materials"]), "; ".join(detail) or "reordered",
                           len(wanted_materials)))

    wanted_skins = {skin["name"]: skin for skin in expected.get("skins") or []}
    have_skins = {skin["name"]: skin for skin in actual["skins"]}
    for name in sorted(set(have_skins) - set(wanted_skins)):
        problems.append("%s: skin %r is not in the manifest" % (rel, name))
    for name in sorted(set(wanted_skins) - set(have_skins)):
        problems.append("%s: skin %r is registered and missing from the model" % (rel, name))
    for name in sorted(set(wanted_skins) & set(have_skins)):
        want, got = wanted_skins[name], have_skins[name]
        if want.get("skeleton") != got.get("skeleton"):
            problems.append("%s: skin %r skeleton is %r, the manifest says %r"
                            % (rel, name, got.get("skeleton"), want.get("skeleton")))
        want_joints, got_joints = want.get("joints") or [], got["joints"]
        if len(want_joints) != len(got_joints):
            problems.append("%s: skin %r has %d joint(s), the manifest says %d"
                            % (rel, name, len(got_joints), len(want_joints)))
        for index in range(min(len(want_joints), len(got_joints))):
            if want_joints[index] != got_joints[index]:
                # The order is the bind: JOINTS_0 indexes into this list.
                problems.append("%s: skin %r joint %d is %r, the manifest says %r "
                                "(the joint order is what the mesh's bone indices point at)"
                                % (rel, name, index, got_joints[index], want_joints[index]))

    wanted_animations = {animation["name"]: animation for animation in expected.get("animations") or []}
    have_animations = {animation["name"]: animation for animation in actual["animations"]}
    for name in sorted(set(have_animations) - set(wanted_animations)):
        problems.append("%s: embedded animation %r is not in the manifest (the clips are "
                        "meant to come from scripts/actors/character_animation.gd)"
                        % (rel, name))
    for name in sorted(set(wanted_animations) - set(have_animations)):
        problems.append("%s: embedded animation %r is registered and missing from the model"
                        % (rel, name))
    for name in sorted(set(wanted_animations) & set(have_animations)):
        want, got = wanted_animations[name], have_animations[name]
        if want.get("channels") != got["channels"]:
            problems.append("%s: animation %r has %d channel(s), the manifest says %s"
                            % (rel, name, got["channels"], want.get("channels")))
        want_targets = [(t.get("node"), t.get("path")) for t in want.get("targets") or []]
        got_targets = [(t.get("node"), t.get("path")) for t in got["targets"]]
        if want_targets != got_targets:
            added = [target for target in got_targets if target not in want_targets]
            removed = [target for target in want_targets if target not in got_targets]
            problems.append("%s: animation %r targets %s, the manifest says %s"
                            % (rel, name,
                               ", ".join("%s.%s" % (node, path) for node, path in added[:4]) or "the same nodes",
                               ", ".join("%s.%s" % (node, path) for node, path in removed[:4]) or "the same nodes"))

    return problems


def _load_manifest(manifest: str, rel_manifest: str) -> tuple[object, list[str]]:
    """The parsed document, or the reason it could not be parsed. Never raises."""
    if not os.path.exists(manifest):
        return None, ["%s is missing; the runtime characters are not structurally checked "
                      "without it (rebuild it with --update-manifest)" % rel_manifest]
    try:
        with open(manifest, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as error:
        return None, ["%s cannot be read: %s" % (rel_manifest, error)]
    try:
        return json.loads(text), []
    except json.JSONDecodeError as error:
        return None, ["%s is not valid JSON (line %d, column %d): %s"
                      % (rel_manifest, error.lineno, error.colno, error.msg)]


def _model_problems(entry: dict, full: str, rel: str, models: list[str] | None) -> tuple[list[str], dict | None, dict | None]:
    """Open one registered model and hold it to its entry.

    Returns `(problems, actual, gltf)`; `actual` is None when the model could not be read or
    its names are ambiguous, because comparing a structure whose identity is broken would
    report the wrong thing.
    """
    problems: list[str] = []
    if not os.path.exists(full):
        return (["%s is registered and does not exist" % rel], None, None)
    if models is not None and full not in models:
        # The file is there and parseable but the library walk did not see it: that means the
        # manifest points outside the library the rest of the check reads.
        problems.append("%s: %s is not under the model library this run scanned" % (rel, rel))
    try:
        gltf, _binary, _images = read_glb(full)
    except Problem as error:
        return (problems + ["%s: %s" % (rel, error)], None, None)
    actual = describe_model(gltf)
    duplicated = identity_problems(actual, rel)
    if duplicated:
        return (problems + duplicated
                + ["%s: the structure is not compared while two of its resources share a "
                   "name — rename one in Blender, then run --update-manifest" % rel],
                None, gltf)
    return problems, actual, gltf


def check_manifest(models: list[str] | None = None, root: str = ROOT,
                   path: str | None = None,
                   required: tuple[str, ...] = REQUIRED_RUNTIME_MODELS) -> tuple[list[str], list[str]]:
    """Read the runtime manifest and hold the registered models to it.

    Returns `(problems, notes)`, like `audit`. The document is validated in full before a
    single `.glb` is opened: a manifest that lost an entry, gained one, or holds a field of
    the wrong shape is reported as such, and the structure comparison never runs on a
    document whose shape is in doubt. Every failure names the manifest path or the model
    path and the field, in that order, because the reader of a red CI job has the log and
    nothing else.
    """
    problems: list[str] = []
    notes: list[str] = []
    manifest = path or manifest_path(root)
    rel_manifest = os.path.relpath(manifest, root).replace(os.sep, "/")

    document, load_problems = _load_manifest(manifest, rel_manifest)
    problems.extend(load_problems)
    problems.extend(validate_manifest(document, rel_manifest, required))
    if problems:
        return problems, notes

    for entry in document["models"]:
        rel = entry["path"]
        full = os.path.join(root, rel.replace("/", os.sep))
        entry_problems, actual, _gltf = _model_problems(entry, full, rel, models)
        problems.extend(entry_problems)
        if actual is None:
            continue
        differences = compare_model(entry, actual, rel)
        problems.extend(differences)
        if differences:
            problems.append(
                "%s: %d structural difference(s) from %s; if they are intended, run "
                "`python3 tools/model_library.py --update-manifest` and commit the manifest "
                "diff so the change is reviewed" % (rel, len(differences), rel_manifest))
        counts = actual["counts"]
        notes.append("%s: %d node(s), %d mesh(es), %d primitive(s), %d material(s), "
                     "%d skin(s) with %d joint(s), %d embedded animation(s)"
                     % (rel, counts["nodes"], counts["meshes"], counts["primitives"],
                        counts["materials"], counts["skins"], counts["joints"],
                        counts["animations"]))
    return problems, notes


def update_manifest(root: str = ROOT, path: str | None = None,
                    required: tuple[str, ...] = REQUIRED_RUNTIME_MODELS) -> tuple[list[str], str]:
    """Rewrite the manifest's structural fields from the registered models.

    Human-written fields of an entry (`wrapper`, `note`, anything this tool does not
    generate) are kept; only `MANIFEST_STRUCTURAL` is replaced. Returns the accepted
    differences and the new file text, so the caller can print what it just agreed to — a
    manifest update is a reviewed change, and the diff is the review.

    The document is validated before anything is read, and the text is validated again
    before it replaces the file, which is written atomically. A malformed manifest is
    therefore never "repaired" by overwriting it with whatever this run happened to
    generate: it is refused, unchanged, with the reason.
    """
    manifest = path or manifest_path(root)
    rel_manifest = os.path.relpath(manifest, root).replace(os.sep, "/")
    if not os.path.exists(manifest):
        raise ManifestError("%s does not exist; there is nothing to update" % rel_manifest)
    with open(manifest, encoding="utf-8") as handle:
        try:
            document = json.loads(handle.read())
        except json.JSONDecodeError as error:
            raise ManifestError("%s is not valid JSON (line %d, column %d): %s"
                                % (rel_manifest, error.lineno, error.colno, error.msg)) from error

    problems = validate_manifest(document, rel_manifest, required)
    if problems:
        raise ManifestError("%s cannot be updated because it is not a valid manifest (%s); "
                            "the file is untouched — fix the manifest by hand, then rerun"
                            % (rel_manifest, _summarise(problems)))

    accepted: list[str] = []
    for entry in document["models"]:
        rel = entry["path"]
        full = os.path.join(root, rel.replace("/", os.sep))
        entry_problems, actual, _gltf = _model_problems(entry, full, rel, None)
        if actual is None:
            raise ManifestError("%s cannot be updated because %s"
                                % (rel_manifest, _summarise(entry_problems)))
        accepted.extend(compare_model(entry, actual, rel))
        for field in MANIFEST_STRUCTURAL:
            if field in actual:
                entry[field] = actual[field]

    text = json.dumps(document, indent=2, ensure_ascii=False) + "\n"
    # Validate what is about to be written, not only what was read: a bug in the generator
    # must not be able to leave a manifest behind that the very next --check rejects.
    written = validate_manifest(json.loads(text), rel_manifest, required)
    if written:
        raise ManifestError("%s was not written: the regenerated document is not valid (%s); "
                            "the file on disk is untouched" % (rel_manifest, _summarise(written)))

    temporary = manifest + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.replace(temporary, manifest)
    return accepted, rel_manifest


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
    parser.add_argument("--update-manifest", action="store_true",
                        help="rewrite the runtime character manifest from the registered "
                             "models (a reviewed change: commit the diff)")
    options = parser.parse_args(argv or ["--check"])

    root = os.path.dirname(os.path.dirname(LIBRARY))  # <root>/assets/models

    if options.update_manifest:
        try:
            accepted, rel_manifest = update_manifest(root)
        except ManifestError as error:
            print("MODEL_LIBRARY_PROBLEM: " + str(error))
            return 1
        # Every accepted line carries both values, which is what the reviewer of the diff
        # needs; the cap keeps a first build of the manifest from filling the log.
        for line in accepted[:25]:
            print("MODEL_LIBRARY_ACCEPTED: " + line)
        if len(accepted) > 25:
            print("MODEL_LIBRARY_ACCEPTED: … and %d more difference(s); all of them are in "
                  "the manifest diff." % (len(accepted) - 25))
        summary = ("no accepted difference: the manifest already described these files"
                   if not accepted else
                   "%d accepted difference(s), which belong in the review" % len(accepted))
        print("MODEL_LIBRARY_MANIFEST_UPDATED: %s now records the structure of the files on "
              "disk (%s)." % (rel_manifest, summary))
        return 0

    models = collect()
    if not models:
        print("MODEL_LIBRARY_PROBLEM: no .glb found under %s"
              % os.path.relpath(LIBRARY, root))
        return 1

    problems, notes, measured = audit(models, root)

    if options.report:
        sys.stdout.write(report(measured))
        return 0

    # The runtime characters get one check more than the rest of the library: the structure
    # the manifest records. It is not a subset of the checks above and not a replacement for
    # them — a model can pass every one of those and still be bound to the wrong rig.
    manifest_problems, manifest_notes = check_manifest(models, root)
    problems.extend(manifest_problems)
    notes.extend(manifest_notes)

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
          "light, fits its budget, and has a matching .import sidecar; the runtime "
          "characters match art/character_rig_audit/runtime_model_manifest.json.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
