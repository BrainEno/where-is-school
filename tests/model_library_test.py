#!/usr/bin/env python3
"""Boundary tests for ``tools/model_library.py``.

The model library check is the only thing that ever reads a `.glb` before it lands in the
pack, so it is tested the way the build check is: on the edges, with files this test
writes itself.

- a clean model passes, and each thing `docs/ASSET_PIPELINE.md` §1 forbids fails on its
  own: a scaled node, a matrix node, a camera, a light;
- the size budget fails one byte over the hard line and only notes one byte over the
  warning line (the same two numbers `tools/verify_build.py` uses, so the test pins the
  fact that they are shared rather than copied);
- embedded images do the same on their own budget;
- a missing sidecar fails, and so does a sidecar whose `dest_files` hash still points at
  the model's old path — the `git mv` mistake this check exists for;
- two models with the same name fail;
- a file that is not a `GLB`, a truncated one and a version-1 one are reported as problems
  instead of crashing the run;
- `--check` returns 1 when there is a problem and 0 when there is not, and `--report`
  prints a row per model;
- the runtime character manifest is tested against a synthetic rig: one extra node (with
  every count that a node does not change left alone), a removed node, a re-parented node,
  a split primitive, a reassigned material, a primitive that lost its weights, a reordered
  joint list, a lost joint, a lost skin, an animation that appeared inside the `.glb`, a
  lost animation and a changed channel target. The manifest's own failure modes get the
  same treatment: missing, not JSON, unknown schema, unsupported version, empty, a
  registered model on disk that is gone, and a development asset registered where only a
  runtime one belongs.

Run it with ``python3 tests/model_library_test.py`` (CI does). It needs no engine.
"""

from __future__ import annotations

import hashlib
import json
import os
import struct
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import model_library as ml  # noqa: E402  (the path has to be set up first)

FAILURES: list[str] = []
CHECKS: int = 0


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


def make_glb(document: dict, pad_to: int = 0) -> bytes:
    """A GLB with this JSON, padded with a BIN chunk so the file is exactly `pad_to` bytes.

    `pad_to` is how the size budget is tested from both sides without guessing how much
    JSON a model needs: ask for the exact number of bytes the budget allows and one more.
    """
    payload = json.dumps(document).encode("utf-8")
    payload += b" " * ((4 - len(payload) % 4) % 4)
    chunks = struct.pack("<II", len(payload), ml.CHUNK_JSON) + payload
    if pad_to:
        filler = pad_to - 12 - len(chunks) - 8
        assert filler > 0 and filler % 4 == 0, (pad_to, filler)
        chunks += struct.pack("<II", filler, ml.CHUNK_BIN) + b"\0" * filler
    total = 12 + len(chunks)
    return struct.pack("<III", ml.GLB_MAGIC, 2, total) + chunks


def make_glb_with_bin(document: dict) -> bytes:
    """A GLB whose one buffer is real vertex data, for the box measurements."""
    # three vertices, one triangle: (−0.5, 0, 0) (0.5, 0.0, 0) (0, 1, 0)
    vertices = struct.pack("<9f", -0.5, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 1.0, 0.0)
    indices = struct.pack("<3H", 0, 1, 2) + b"\0\0"  # padded to 4 bytes
    binary = vertices + indices
    document = dict(document)
    document["buffers"] = [{"byteLength": len(binary)}]
    document["bufferViews"] = [{"buffer": 0, "byteOffset": 0, "byteLength": len(vertices)},
                               {"buffer": 0, "byteOffset": len(vertices), "byteLength": 6}]
    document["accessors"] = [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
         "min": [-0.5, 0.0, 0.0], "max": [0.5, 1.0, 0.0]},
        {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"},
    ]
    payload = json.dumps(document).encode("utf-8")
    payload += b" " * ((4 - len(payload) % 4) % 4)
    chunks = struct.pack("<II", len(payload), ml.CHUNK_JSON) + payload
    chunks += struct.pack("<II", len(binary), ml.CHUNK_BIN) + binary
    return struct.pack("<III", ml.GLB_MAGIC, 2, 12 + len(chunks)) + chunks


def simple_model(**extra) -> dict:
    """One triangle, one material, positioned on the floor."""
    document = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "Model", "mesh": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
        "materials": [{"name": "WIS_test"}],
        "accessors": [
            {"count": 3, "type": "VEC3", "min": [-0.5, 0.0, -0.5], "max": [0.5, 1.0, 0.5]},
            {"count": 3, "type": "SCALAR"},
        ],
    }
    document.update(extra)
    return document


class Library:
    """A throw-away project tree with `assets/models/` under it, as a test needs it."""

    def __init__(self, project_root: str) -> None:
        self.root = project_root                      # the `res://` root
        self.models = os.path.join(project_root, "assets", "models")
        os.makedirs(self.models, exist_ok=True)

    def add(self, rel: str, data: bytes, sidecar: bool = True) -> str:
        path = os.path.join(self.models, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(data)
        if sidecar:
            self.write_sidecar(path)
        return path

    def write_sidecar(self, path: str, res_path: str | None = None) -> None:
        res_path = res_path or "res://" + os.path.relpath(path, self.root).replace(os.sep, "/")
        digest = hashlib.md5(res_path.encode()).hexdigest()
        dest = "res://.godot/imported/%s-%s.scn" % (os.path.basename(path), digest)
        with open(path + ".import", "w", encoding="utf-8") as handle:
            handle.write('[remap]\n\nuid="uid://test%s"\npath="%s"\n\n[deps]\n\n'
                         'source_file="%s"\n\ndest_files=["%s"]\n'
                         % (digest[:6], dest, res_path, dest))

    def paths(self) -> list[str]:
        return sorted(os.path.join(dirpath, name)
                      for dirpath, _, names in os.walk(self.models)
                      for name in names if name.lower().endswith(".glb"))

    def audit(self) -> tuple[list[str], list[str]]:
        problems, notes, _ = ml.audit(self.paths(), self.root)
        return problems, notes


def run(rel: str, data: bytes, sidecar: bool = True) -> tuple[list[str], list[str]]:
    with tempfile.TemporaryDirectory() as tmp:
        library = Library(tmp)
        library.add(rel, data, sidecar)
        return library.audit()


# --- the runtime character manifest ------------------------------------------
#
# The manifest is a snapshot of a rig, and a snapshot test is only worth having if the
# mutations it is supposed to catch are actually tried. So every case below starts from a
# synthetic character with a skin, a joint chain, three meshes worth of primitives and an
# animation, writes the manifest from it, then changes *one* thing in the model or in the
# manifest and expects that exact thing to be named in the failure.
#
# Nothing here touches the production characters: the fixtures are written into a temporary
# project tree, which is also what keeps this test from failing when an artist legitimately
# changes the protagonist.


def character_document(extra_node: dict | None = None) -> dict:
    """A small rigged character: a root, an armature with two joints, one skinned body."""
    nodes = [
        {"name": "CHR_Test", "children": [1, 4]},                       # 0
        {"name": "RIG_Test", "children": [2, 3]},                       # 1
        {"name": "Root", "children": [3]},                              # 2  joint 0
        {"name": "Spine", "children": []},                              # 3  joint 1
        {"name": "Body", "mesh": 0, "skin": 0},                         # 4
    ]
    if extra_node is not None:
        nodes.append(extra_node)
        nodes[1]["children"] = list(nodes[1]["children"]) + [len(nodes) - 1]
    return {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": nodes,
        "meshes": [
            {"name": "Body_Mesh", "primitives": [
                {"attributes": {"POSITION": 0, "JOINTS_0": 1, "WEIGHTS_0": 1}, "material": 0},
            ]},
        ],
        "materials": [{"name": "WIS_Test_Body"}],
        "skins": [{"name": "RIG_Test", "joints": [2, 3]}],
        "animations": [
            {"name": "Idle", "samplers": [{"input": 0, "output": 0}],
             "channels": [{"sampler": 0, "target": {"node": 3, "path": "rotation"}}]},
        ],
        "accessors": [
            {"count": 3, "type": "VEC3", "min": [-0.5, 0.0, -0.5], "max": [0.5, 1.0, 0.5]},
            {"count": 3, "type": "SCALAR"},
        ],
    }


class ManifestLibrary(Library):
    """A temporary project tree with a runtime manifest under `art/character_rig_audit/`."""

    MANIFEST = os.path.join("art", "character_rig_audit", "runtime_model_manifest.json")

    def __init__(self, project_root: str) -> None:
        super().__init__(project_root)
        self.manifest = os.path.join(project_root, self.MANIFEST)

    PREFIX = "assets/models/"

    def register(self, rel: str, document: dict, note: str = "test character") -> str:
        """Write the model and record its structure in the manifest.

        `rel` is the path as the manifest spells it (`assets/models/<kind>/<name>.glb`);
        `Library.add` takes it relative to `assets/models/`, so the prefix comes off here
        instead of at twenty call sites.
        """
        self.add(rel[len(self.PREFIX):] if rel.startswith(self.PREFIX) else rel, make_glb(document))
        entry = {"path": rel if rel.startswith(self.PREFIX) else self.PREFIX + rel, "note": note}
        entry.update(ml.describe_model(document))
        document_json = {
            "schema": ml.MANIFEST_SCHEMA,
            "schema_version": ml.MANIFEST_SCHEMA_VERSION,
            "models": [entry],
        }
        os.makedirs(os.path.dirname(self.manifest), exist_ok=True)
        with open(self.manifest, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(document_json, indent=2) + "\n")
        return rel

    def write_manifest(self, document: dict) -> None:
        os.makedirs(os.path.dirname(self.manifest), exist_ok=True)
        with open(self.manifest, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(document, indent=2) + "\n")

    def check_manifest(self) -> tuple[list[str], list[str]]:
        return ml.check_manifest(self.paths(), self.root)

    def replace_model(self, rel: str, document: dict) -> None:
        self.add(rel[len(self.PREFIX):] if rel.startswith(self.PREFIX) else rel, make_glb(document))


def test_manifest_accepts_the_registered_structure() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        library = ManifestLibrary(tmp)
        library.register("assets/models/test_character/test_character.glb", character_document())
        problems, notes = library.check_manifest()
        check(problems == [], "a registered structure must pass, got: %s" % problems)
        check(any("1 skin(s) with 2 joint(s)" in note for note in notes),
              "the manifest check must report the rig it checked, got: %s" % notes)


def test_manifest_catches_an_unknown_node() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        library = ManifestLibrary(tmp)
        rel = library.register("assets/models/test_character/test_character.glb", character_document())
        # The case the issue asks for by name: one extra node, no change to meshes, so the
        # counts of everything else stay the same and only the node tree can see it.
        library.replace_model(rel, character_document(extra_node={"name": "Q_Extra_Prop"}))
        problems, _ = library.check_manifest()
        check(any("node" in problem and "Q_Extra_Prop" in problem and "not in the manifest" in problem
                  for problem in problems),
              "an unregistered node must be named in the failure, got: %s" % problems)
        check(any("counts.nodes" in problem for problem in problems),
              "the node count change must be reported too, got: %s" % problems)


def test_manifest_catches_a_missing_node() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        library = ManifestLibrary(tmp)
        rel = library.register("assets/models/test_character/test_character.glb", character_document())
        document = character_document()
        # Drop the shoulder joint and its child link along with it.
        document["nodes"][2]["children"] = []
        del document["nodes"][3]
        document["nodes"][1]["children"] = [2]
        document["skins"][0]["joints"] = [2]
        document["animations"][0]["channels"][0]["target"]["node"] = 2
        # The body node shifts down into the freed index and keeps its mesh and skin.
        library.replace_model(rel, document)
        problems, _ = library.check_manifest()
        check(any("missing from the model" in problem and "Spine" in problem for problem in problems),
              "a removed node must be named, got: %s" % problems)


def test_manifest_catches_a_hierarchy_change() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        library = ManifestLibrary(tmp)
        rel = library.register("assets/models/test_character/test_character.glb", character_document())
        document = character_document()
        # Same nodes, same names, same mesh count: only the parent changes, which is exactly
        # what a manifest keyed on names instead of paths would miss.
        document["nodes"][1]["children"] = []
        document["nodes"][2]["children"] = []
        document["nodes"].append({"name": "Spine", "children": []})
        document["skins"][0]["joints"] = [2, 5]
        document["animations"][0]["channels"][0]["target"]["node"] = 5
        library.replace_model(rel, document)
        problems, _ = library.check_manifest()
        check(any("not in the manifest" in problem and "Spine" in problem for problem in problems),
              "a re-parented node must be reported by its new path, got: %s" % problems)
        check(any("missing from the model" in problem and "RIG_Test/Root/Spine" in problem
                  for problem in problems),
              "the old path must be reported as gone, got: %s" % problems)


def test_manifest_catches_mesh_and_primitive_changes() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        library = ManifestLibrary(tmp)
        rel = library.register("assets/models/test_character/test_character.glb", character_document())

        split = character_document()
        split["meshes"][0]["primitives"].append(
            dict(split["meshes"][0]["primitives"][0]))
        library.replace_model(rel, split)
        problems, _ = library.check_manifest()
        check(any("Body_Mesh" in problem and "2 primitive(s)" in problem for problem in problems),
              "a split primitive must be reported, got: %s" % problems)

        library.replace_model(rel, character_document())
        reassigned = character_document()
        reassigned["materials"].append({"name": "WIS_Test_Other"})
        reassigned["meshes"][0]["primitives"][0]["material"] = 1
        library.replace_model(rel, reassigned)
        problems, _ = library.check_manifest()
        check(any("primitive 0 material" in problem and "WIS_Test_Other" in problem
                  for problem in problems),
              "a reassigned material must be reported, got: %s" % problems)

        library.replace_model(rel, character_document())
        unskinned = character_document()
        unskinned["meshes"][0]["primitives"][0]["attributes"].pop("JOINTS_0")
        library.replace_model(rel, unskinned)
        problems, _ = library.check_manifest()
        check(any("primitive 0 skinned" in problem for problem in problems),
              "a primitive that lost its weights must be reported, got: %s" % problems)


def test_manifest_catches_joint_changes() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        library = ManifestLibrary(tmp)
        rel = library.register("assets/models/test_character/test_character.glb", character_document())

        reordered = character_document()
        reordered["skins"][0]["joints"] = [3, 2]
        library.replace_model(rel, reordered)
        problems, _ = library.check_manifest()
        check(any("joint 0" in problem and "the joint order" in problem for problem in problems),
              "a reordered joint list must be reported, got: %s" % problems)

        library.replace_model(rel, character_document())
        fewer = character_document()
        fewer["skins"][0]["joints"] = [2]
        library.replace_model(rel, fewer)
        problems, _ = library.check_manifest()
        check(any("1 joint(s), the manifest says 2" in problem for problem in problems),
              "a lost joint must be reported, got: %s" % problems)

        library.replace_model(rel, character_document())
        no_skin = character_document()
        no_skin["skins"] = []
        no_skin["nodes"][4].pop("skin")
        library.replace_model(rel, no_skin)
        problems, _ = library.check_manifest()
        check(any("skin 'RIG_Test' is registered and missing" in problem for problem in problems),
              "a removed skin must be reported, got: %s" % problems)


def test_manifest_catches_animation_changes() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        library = ManifestLibrary(tmp)
        rel = library.register("assets/models/test_character/test_character.glb", character_document())

        added = character_document()
        added["animations"].append({
            "name": "Wave",
            "samplers": [{"input": 0, "output": 0}],
            "channels": [{"sampler": 0, "target": {"node": 2, "path": "rotation"}}],
        })
        library.replace_model(rel, added)
        problems, _ = library.check_manifest()
        check(any("embedded animation 'Wave'" in problem for problem in problems),
              "an animation that appeared inside the .glb must be reported, got: %s" % problems)

        library.replace_model(rel, character_document())
        gone = character_document()
        gone["animations"] = []
        library.replace_model(rel, gone)
        problems, _ = library.check_manifest()
        check(any("embedded animation 'Idle' is registered and missing" in problem
                  for problem in problems),
              "a lost animation must be reported, got: %s" % problems)

        library.replace_model(rel, character_document())
        retargeted = character_document()
        retargeted["animations"][0]["channels"].append(
            {"sampler": 0, "target": {"node": 2, "path": "translation"}})
        library.replace_model(rel, retargeted)
        problems, _ = library.check_manifest()
        check(any("animation 'Idle' has 2 channel(s)" in problem for problem in problems),
              "a changed channel count must be reported, got: %s" % problems)
        check(any("animation 'Idle' targets" in problem and "Root.translation" in problem
                  for problem in problems),
              "the changed target must be named, got: %s" % problems)


def test_manifest_format_errors() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        library = ManifestLibrary(tmp)
        problems, _ = library.check_manifest()
        check(any("is missing" in problem for problem in problems),
              "a missing manifest must fail, got: %s" % problems)

        os.makedirs(os.path.dirname(library.manifest), exist_ok=True)
        with open(library.manifest, "w", encoding="utf-8") as handle:
            handle.write('{"schema": "where-is-school/runtime-model-manifest",\n')
        problems, _ = library.check_manifest()
        check(any("not valid JSON" in problem and "(line " in problem and "column" in problem
                  for problem in problems),
              "broken JSON must say where it broke, got: %s" % problems)

        library.write_manifest({"schema": "something-else", "schema_version": 1, "models": []})
        problems, _ = library.check_manifest()
        check(any("schema is" in problem for problem in problems),
              "an unknown schema must fail, got: %s" % problems)

        library.write_manifest({"schema": ml.MANIFEST_SCHEMA, "schema_version": 99, "models": []})
        problems, _ = library.check_manifest()
        check(any("schema_version is 99" in problem for problem in problems),
              "an unsupported version must fail, got: %s" % problems)

        library.write_manifest({"schema": ml.MANIFEST_SCHEMA,
                                "schema_version": ml.MANIFEST_SCHEMA_VERSION, "models": []})
        problems, _ = library.check_manifest()
        check(any("checks nothing" in problem for problem in problems),
              "a manifest that registers nothing must fail, got: %s" % problems)

        library.write_manifest({"schema": ml.MANIFEST_SCHEMA,
                                "schema_version": ml.MANIFEST_SCHEMA_VERSION,
                                "models": [{"path": "assets/models/absent/absent.glb"}]})
        problems, _ = library.check_manifest()
        check(any("does not exist" in problem for problem in problems),
              "a registered model that is not on disk must fail, got: %s" % problems)

        library.write_manifest({"schema": ml.MANIFEST_SCHEMA,
                                "schema_version": ml.MANIFEST_SCHEMA_VERSION,
                                "models": [{"path": "scenes/dev/animation_retarget_test/q_rigged.glb"}]})
        problems, _ = library.check_manifest()
        check(any("only covers runtime models under assets/models/" in problem for problem in problems),
              "a development asset must not be registrable, got: %s" % problems)


def test_manifest_leaves_unregistered_models_to_the_generic_checks() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        library = ManifestLibrary(tmp)
        library.register("assets/models/test_character/test_character.glb", character_document())
        library.add("classroom/classroom_desk.glb", make_glb(simple_model()))
        problems, notes = library.check_manifest()
        check(problems == [], "an unregistered model must not fail the manifest check, got: %s" % problems)
        check(all("test_character" in note for note in notes),
              "only registered models are described, got: %s" % notes)


def test_manifest_update_accepts_a_reviewed_change() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        library = ManifestLibrary(tmp)
        rel = library.register("assets/models/test_character/test_character.glb", character_document(),
                               note="kept across an update")
        document = character_document(extra_node={"name": "Q_Extra_Prop"})
        library.replace_model(rel, document)

        problems, _ = library.check_manifest()
        check(problems != [], "the manifest must disagree before the update")

        accepted, rel_manifest = ml.update_manifest(library.root, library.manifest)
        check(any("Q_Extra_Prop" in line for line in accepted),
              "the update must report what it accepted, got: %s" % accepted)
        check(rel_manifest.endswith("runtime_model_manifest.json"), "the update names its file")
        problems, _ = library.check_manifest()
        check(problems == [], "the updated manifest must agree with the model, got: %s" % problems)

        with open(library.manifest, encoding="utf-8") as handle:
            updated = json.load(handle)
        check(updated["models"][0]["note"] == "kept across an update",
              "the update must not drop the human-written note")
        check(any("Q_Extra_Prop" in node["path"] for node in updated["models"][0]["nodes"]
                  if "Q_Extra_Prop" in node["path"]),
              "the update must record the new node")

        accepted, _ = ml.update_manifest(library.root, library.manifest)
        check(accepted == [], "a second update must accept nothing, got: %s" % accepted)


def test_manifest_is_wired_into_check() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        library = ManifestLibrary(tmp)
        rel = library.register("assets/models/test_character/test_character.glb", character_document())
        saved = ml.LIBRARY
        try:
            ml.LIBRARY = library.models
            check(ml.main(["--check"]) == 0, "--check must pass on a library that matches its manifest")
            library.replace_model(rel, character_document(extra_node={"name": "Q_Extra_Prop"}))
            check(ml.main(["--check"]) == 1,
                  "--check must fail when a runtime character gained a node")
        finally:
            ml.LIBRARY = saved



def main() -> int:
    # A clean model, and the same model in a two-model kind directory.
    problems, _ = run("classroom/classroom_desk.glb", make_glb(simple_model()))
    check(problems == [], "a clean model must pass, got: %s" % problems)

    # The bounding box is world space: a translated node moves it.
    lifted = simple_model(
        meshes=[{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]},
                {"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
    )
    lifted["nodes"] = [{"name": "root", "children": [1]}, {"name": "up", "mesh": 1, "translation": [0.0, 2.0, 0.0]}]
    with tempfile.TemporaryDirectory() as tmp:
        library = Library(tmp)
        path = library.add("classroom/classroom_desk.glb", make_glb_with_bin(lifted))
        gltf, binary, _ = ml.read_glb(path)
        info = ml.measure(gltf, binary)
        check(abs(info["high"][1] - 3.0) < 1e-6,
              "a node translated 2 m up must lift the box to 3 m, got %s" % (info["high"],))

    # §1: no node scale.
    scaled = simple_model(nodes=[{"name": "Model", "scale": [2.0, 2.0, 2.0]}])
    problems, _ = run("classroom/classroom_desk.glb", make_glb(scaled))
    check(any("scaled to [2.0, 2.0, 2.0]" in p for p in problems),
          "a scaled node must fail, got: %s" % problems)
    uniform = simple_model(nodes=[{"name": "Model", "scale": [1.0, 1.0, 1.0]}])
    problems, _ = run("classroom/classroom_desk.glb", make_glb(uniform))
    check(problems == [], "a node scaled to exactly 1 must not fail, got: %s" % problems)

    # §1: no node matrix.
    matrix = simple_model(nodes=[{"name": "Model", "matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]}])
    problems, _ = run("classroom/classroom_desk.glb", make_glb(matrix))
    check(any("matrix transform" in p for p in problems),
          "a matrix node must fail, got: %s" % problems)

    # §1: no cameras, no lights.
    camera = simple_model(cameras=[{"type": "perspective", "perspective": {"yfov": 1.0}}])
    problems, _ = run("classroom/classroom_desk.glb", make_glb(camera))
    check(any("camera" in p for p in problems), "a camera must fail, got: %s" % problems)
    light = simple_model(extensionsUsed=["KHR_lights_punctual"])
    problems, _ = run("classroom/classroom_desk.glb", make_glb(light))
    check(any("light" in p for p in problems), "a light must fail, got: %s" % problems)

    # The model budget is verify_build's, not a second copy of it.
    budget = ml.vb.BY_NAME["model"].hard
    problems, notes = run("classroom/classroom_desk.glb", make_glb(simple_model(), pad_to=budget))
    check(problems == [], "%d bytes is exactly the hard line and must pass, got: %s"
          % (budget, problems))
    problems, _ = run("classroom/classroom_desk.glb", make_glb(simple_model(), pad_to=budget + 4))
    check(any("hard budget" in p for p in problems),
          "one aligned step over the hard line must fail, got: %s" % problems)
    warn = ml.vb.BY_NAME["model"].warn
    problems, notes = run("classroom/classroom_desk.glb", make_glb(simple_model(), pad_to=warn + 4))
    check(problems == [] and any("warning line" in n for n in notes),
          "one step over the warning line must note but pass, got: %s / %s" % (problems, notes))

    # Embedded images have their own ceiling, because they land in the pack as textures.
    big = simple_model(bufferViews=[{"byteLength": ml.EMBED_HARD + 4}], images=[{"bufferView": 0}])
    problems, _ = run("classroom/classroom_desk.glb", make_glb(big))
    check(any("embedded images" in p for p in problems),
          "embedded images over the ceiling must fail, got: %s" % problems)
    medium = simple_model(bufferViews=[{"byteLength": ml.EMBED_WARN + 4}], images=[{"bufferView": 0}])
    problems, notes = run("classroom/classroom_desk.glb", make_glb(medium))
    check(problems == [] and any("embedded images" in n for n in notes),
          "embedded images over the warning line must note but pass, got: %s / %s"
          % (problems, notes))
    # A data URI is counted too, since that is the other way a texture hides in a .glb.
    uri = simple_model(images=[{"uri": "data:image/png;base64," + "A" * 4 * ((ml.EMBED_HARD // 3) + 8)}])
    problems, _ = run("classroom/classroom_desk.glb", make_glb(uri))
    check(any("embedded images" in p for p in problems),
          "an oversized data-URI texture must fail too, got: %s" % problems)

    # The sidecar: present, naming this model, and hashing this model's path.
    problems, _ = run("classroom/classroom_desk.glb", make_glb(simple_model()), sidecar=False)
    check(any(".import beside it" in p for p in problems),
          "a model without a sidecar must fail, got: %s" % problems)
    with tempfile.TemporaryDirectory() as tmp:
        library = Library(tmp)
        path = library.add("classroom/classroom_desk.glb", make_glb(simple_model()))
        library.write_sidecar(path, res_path="res://assets/models/new models/classroom_desk.glb")
        problems, _ = library.audit()
        check(any("different source_file" in p for p in problems),
              "a sidecar naming another path must fail, got: %s" % problems)
        moved = os.path.join(library.models, "corridor", "corridor_desk.glb")
        os.makedirs(os.path.dirname(moved), exist_ok=True)
        os.rename(path, moved)
        os.rename(path + ".import", moved + ".import")
        problems, _ = library.audit()
        check(any("moved or renamed without its sidecar" in p for p in problems),
              "a model moved without its sidecar must fail, got: %s" % problems)

    # Two models called the same thing.
    with tempfile.TemporaryDirectory() as tmp:
        library = Library(tmp)
        library.add("classroom/desk.glb", make_glb(simple_model()))
        library.add("corridor/desk.glb", make_glb(simple_model()))
        problems, _ = library.audit()
        check(any("already called desk" in p for p in problems),
              "a duplicated model name must fail, got: %s" % problems)

    # Files that are not models at all: reported, never fatal.
    problems, _ = run("classroom/classroom_desk.glb", b"glTF")
    check(any("shorter than a GLB header" in p for p in problems),
          "a file too short to hold a header must be a problem, got: %s" % problems)
    problems, _ = run("classroom/classroom_desk.glb", b"NOPE" + b"\0" * 40)
    check(any("bad magic" in p for p in problems), "bad magic must be a problem, got: %s" % problems)
    good = make_glb(simple_model())
    problems, _ = run("classroom/classroom_desk.glb", good[:-8])
    check(any("header says" in p for p in problems),
          "a truncated file must be a problem, got: %s" % problems)
    v1 = struct.pack("<III", ml.GLB_MAGIC, 1, len(good)) + good[12:]
    problems, _ = run("classroom/classroom_desk.glb", v1)
    check(any("version 1" in p for p in problems), "a version-1 GLB must fail, got: %s" % problems)

    # Exit codes and the report. This library carries a manifest because `--check` now
    # requires one: a project without `art/character_rig_audit/runtime_model_manifest.json`
    # is a project whose runtime characters are not structurally checked, and that is a
    # failure rather than a pass (the check below on a manifest-less tree pins it).
    with tempfile.TemporaryDirectory() as tmp:
        library = ManifestLibrary(tmp)
        library.register("assets/models/classroom/classroom_desk.glb", simple_model())
        saved = ml.LIBRARY
        try:
            ml.LIBRARY = library.models
            check(ml.main(["--check"]) == 0, "--check must return 0 for a clean library")
            library.add("corridor/corridor_camera.glb",
                        make_glb(simple_model(cameras=[{"type": "perspective",
                                                        "perspective": {"yfov": 1.0}}])))
            check(ml.main(["--check"]) == 1, "--check must return 1 when a model is broken")
            _, _, measured = ml.audit(library.paths(), library.root)
            table = ml.report(measured)
            check("### `classroom/` — 1 model" in table,
                  "--report must group by kind, got:\n%s" % table)
            check("| `classroom_desk` |" in table and "| +0.000 | +1.000 |" in table,
                  "--report must print one row per model with its min and max y, got:\n%s" % table)
        finally:
            ml.LIBRARY = saved

    # The manifest cases live in their own functions because each one builds a temporary
    # project tree; they are run here, after the checks above, so a failure in either group
    # is reported the same way.
    for name, function in sorted(globals().items()):
        if name.startswith("test_") and callable(function):
            function()

    if FAILURES:
        for failure in FAILURES:
            print("MODEL_LIBRARY_TEST_FAILURE: " + failure)
        print("%d of %d check(s) failed." % (len(FAILURES), CHECKS))
        return 1
    print("MODEL_LIBRARY_TEST_OK: %d checks." % CHECKS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
