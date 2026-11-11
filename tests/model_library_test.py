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
  prints a row per model.

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

    # Exit codes and the report.
    with tempfile.TemporaryDirectory() as tmp:
        library = Library(tmp)
        library.add("classroom/classroom_desk.glb", make_glb(simple_model()))
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

    if FAILURES:
        for failure in FAILURES:
            print("MODEL_LIBRARY_TEST_FAILURE: " + failure)
        print("%d of %d check(s) failed." % (len(FAILURES), CHECKS))
        return 1
    print("MODEL_LIBRARY_TEST_OK: %d checks." % CHECKS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
