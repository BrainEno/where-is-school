#!/usr/bin/env python3
"""Geometry, rig and regeneration contracts for the two refined classroom NPCs.

    python3 tests/character_geometry_test.py

These are structural/deformation-input checks, not a substitute for the Godot captures
or the owner's visual decision. No test loosens the existing seating/animation bounds.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import sys
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import character_geometry as geometry
import prepare_classroom_student as student
import prepare_teacher_n as teacher


def parts(data: bytes) -> tuple:
    d, b = teacher.load_glb(data)
    result = {}
    for mesh in d["meshes"]:
        for p in mesh["primitives"]:
            a = p["attributes"]
            result[mesh["name"], d["materials"][p["material"]]["name"]] = {
                key: teacher.read_accessor(d, b, value) for key, value in a.items()
            } | {"triangles": teacher.read_accessor(d, b, p["indices"]).reshape(-1, 3)}
    return d, b, result


class RefinedCharacterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.student_source = student.SOURCE.read_bytes()
        cls.teacher_source = (ROOT / teacher.SOURCE).read_bytes()
        cls.student_bytes = student.prepare(cls.student_source)
        cls.teacher_bytes, _report = teacher.prepare(cls.teacher_source)
        cls.outputs = [parts(cls.student_bytes), parts(cls.teacher_bytes)]

    def test_immutable_sources_and_committed_outputs(self) -> None:
        self.assertEqual(hashlib.sha256(self.student_source).hexdigest(), student.SOURCE_SHA256)
        self.assertEqual(hashlib.sha256(self.teacher_source).hexdigest(), teacher.SOURCE_SHA256)
        self.assertEqual(student.OUTPUT.read_bytes(), self.student_bytes)
        self.assertEqual((ROOT / teacher.OUTPUT).read_bytes(), self.teacher_bytes)

    def test_both_builds_are_deterministic(self) -> None:
        self.assertEqual(student.prepare(self.student_source), self.student_bytes)
        self.assertEqual(teacher.prepare(self.teacher_source)[0], self.teacher_bytes)

    def test_unreviewed_source_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            student.prepare(self.student_source[:-1] + b"!")
        with self.assertRaises(teacher.PrepareError):
            teacher.prepare(self.teacher_source[:-1] + b"!")

    def test_joint_order_and_rest_transforms_are_identical(self) -> None:
        for source, (out, _binary, _parts) in zip(
                [self.student_source, self.teacher_source], self.outputs):
            before, _ = teacher.load_glb(source)
            old = [before["nodes"][j] for j in before["skins"][0]["joints"]]
            new = [out["nodes"][j] for j in out["skins"][0]["joints"]]
            self.assertEqual([n["name"] for n in old], [n["name"] for n in new])
            self.assertEqual(len(new), 16)
            for a, b in zip(old, new):
                for key in ["translation", "rotation", "scale", "matrix"]:
                    self.assertEqual(a.get(key), b.get(key), (a["name"], key))
            def parents(document: dict) -> dict:
                return {document["nodes"][c]["name"]: n["name"]
                        for n in document["nodes"] for c in n.get("children", [])
                        if c in document["skins"][0]["joints"]}
            self.assertEqual(parents(before), parents(out))

    def test_inverse_binds_are_bit_exact(self) -> None:
        for source, (out, binary, _parts) in zip(
                [self.student_source, self.teacher_source], self.outputs):
            before, old_binary = teacher.load_glb(source)
            a = teacher.read_accessor(before, old_binary, before["skins"][0]["inverseBindMatrices"])
            b = teacher.read_accessor(out, binary, out["skins"][0]["inverseBindMatrices"])
            np.testing.assert_array_equal(a, b)

    def test_every_moving_teacher_channel_is_preserved_exactly(self) -> None:
        before, old_binary = teacher.load_glb(self.teacher_source)
        after, binary, _parts = self.outputs[1]
        def moving(document: dict, blob: bytes) -> dict:
            result = {}
            for animation in document.get("animations", []):
                for channel in animation["channels"]:
                    target = channel["target"]
                    node = document["nodes"][target["node"]]
                    sampler = animation["samplers"][channel["sampler"]]
                    values = teacher.read_accessor(document, blob, sampler["output"])
                    defaults = {"translation": [0, 0, 0], "rotation": [0, 0, 0, 1], "scale": [1, 1, 1]}
                    if teacher._moves(values, node.get(target["path"], defaults[target["path"]]), target["path"]):
                        times = teacher.read_accessor(document, blob, sampler["input"])
                        key = (animation["name"], node["name"], target["path"])
                        result[key] = (times.tobytes(), values.tobytes(), sampler.get("interpolation", "LINEAR"))
            return result
        self.assertEqual(moving(before, old_binary), moving(after, binary))
        self.assertEqual(len(moving(after, binary)), 8)
        self.assertEqual(len(after["animations"]), 4)
        self.assertFalse(self.outputs[0][0].get("animations"))

    def test_geometry_is_finite_normalized_and_bound(self) -> None:
        for _document, _binary, surfaces in self.outputs:
            for label, p in surfaces.items():
                with self.subTest(surface=label):
                    for key in ["POSITION", "NORMAL", "WEIGHTS_0"]:
                        self.assertTrue(np.isfinite(p[key]).all())
                    np.testing.assert_allclose(np.linalg.norm(p["NORMAL"], axis=1), 1, atol=2e-4)
                    np.testing.assert_allclose(p["WEIGHTS_0"].sum(1), 1, atol=1e-6)
                    self.assertGreaterEqual(p["JOINTS_0"].min(), 0)
                    self.assertLess(p["JOINTS_0"].max(), 16)
                    self.assertLess(p["triangles"].max(), len(p["POSITION"]))
                    self.assertGreaterEqual(p["triangles"].min(), 0)
                    tri = p["POSITION"][p["triangles"]]
                    area = np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1)
                    self.assertTrue((area > 1e-17).all(), "zero-area geometry is not refinement")

    def test_five_digits_are_one_closed_connected_surface(self) -> None:
        for teacher_hand in [True, False]:
            hand = geometry.canonical_hand(teacher_hand)
            p, t = hand.positions, hand.triangles
            edges = np.sort(np.concatenate((t[:, [0, 1]], t[:, [1, 2]], t[:, [2, 0]])), axis=1)
            _edges, uses = np.unique(edges, axis=0, return_counts=True)
            np.testing.assert_array_equal(uses, 2, "hand has an open seam or non-manifold connection")
            def components(mask: np.ndarray) -> int:
                adjacent = {i: set() for i in np.flatnonzero(mask)}
                for a, b in _edges:
                    if mask[a] and mask[b]:
                        adjacent[a].add(b)
                        adjacent[b].add(a)
                result = 0
                while adjacent:
                    pending = [next(iter(adjacent))]
                    result += 1
                    while pending:
                        index = pending.pop()
                        pending.extend(adjacent.pop(index, set()))
                return result
            self.assertEqual(components(np.ones(len(p), bool)), 1, "digits are still disconnected capped rods")
            size = 1 if teacher_hand else .91
            self.assertEqual(components(p[:, 1] > .100 * size), 4, "four long fingers must separate above the webs")
            self.assertGreater(p[:, 0].max(), .059 * size, "thumb silhouette is missing")
            tips = [p[np.abs(p[:, 0] / size - x) < .004, 1].max()
                    for x, _length, _width in geometry.HAND_DIGITS]
            self.assertEqual(len(set(np.round(tips, 4))), 4)
            self.assertGreater(tips[2], tips[3])
            self.assertLess(tips[0], tips[1])

    def test_exported_hands_really_contain_the_new_digits(self) -> None:
        for teacher_hand, (document, binary, surfaces) in zip([False, True], self.outputs):
            binds = teacher.read_accessor(document, binary, document["skins"][0]["inverseBindMatrices"])
            binds = binds.reshape(-1, 4, 4).transpose(0, 2, 1)
            for right, joint in [(False, 6), (True, 9)]:
                expected = geometry.hand_geometry(binds[joint], teacher_hand, right).positions.astype(np.float32)
                name = "ST_Hands" if teacher_hand else ("Sphere.028" if right else "Sphere.027")
                material = "M_ST_Skin" if teacher_hand else "WIS_Protagonist_Skin"
                part = surfaces[name, material]
                actual = part["POSITION"][part["JOINTS_0"][:, 0] == joint]
                np.testing.assert_allclose(actual, expected, atol=2e-7)
                weights = part["WEIGHTS_0"][part["JOINTS_0"][:, 0] == joint]
                if teacher_hand:
                    local = np.c_[actual, np.ones(len(actual))] @ binds[joint].T
                    expected = np.clip((local[:, 1] + .007) / .025, 0, 1)
                    np.testing.assert_allclose(weights[:, 0], expected, atol=1 / 255 + 1e-5)
                    self.assertTrue(np.any((weights[:, 0] > 0) & (weights[:, 0] < 1)))
                    self.assertTrue((weights[local[:, 1] > .0181, 0] == 1).all())
                else:
                    np.testing.assert_array_equal(weights[:, 0], 1)

    def test_student_has_no_obsolete_mitten_or_cheek_pads(self) -> None:
        document, _binary, surfaces = self.outputs[0]
        self.assertFalse({n["name"] for n in document["nodes"]} & student.REMOVED_NODES)
        self.assertEqual(len(document["meshes"]), 64)
        self.assertEqual(len(surfaces), 64)
        # The continuous face contains substantially more modelling than the old sphere;
        # density alone is not a visual pass, but losing it must not silently regress.
        self.assertGreater(len(surfaces["Head_Main_Mesh_Mesh", "WIS_Protagonist_Skin"]["POSITION"]), 4000)

    def test_student_eyes_are_low_relief_not_globes(self) -> None:
        for side in [-1, 1]:
            g = geometry.eye_patch(side, "sclera")
            span = np.ptp(g.positions, axis=0)
            self.assertLess(span[0], .051)
            self.assertLess(span[1], .026)
            # The boundary follows the sculpted socket, not one floating z plane.
            self.assertLess(span[2], .030)
            relief = g.positions[:, 2] - geometry.student_front(g.positions[:, 0], g.positions[:, 1])
            self.assertLess(relief.max(), .01041)
            self.assertGreaterEqual(relief.min(), .00039)
            n = geometry.normals(g)
            self.assertTrue((n[:, 2] > 0).all(), "front-facing eye patch was wound backwards")

    def test_teacher_eye_winding_and_normals_are_outward(self) -> None:
        document, _binary, surfaces = self.outputs[1]
        for name in ["ST_Eye_L", "ST_Eye_R"]:
            for material in ["M_ST_Sclera", "M_ST_Iris", "M_ST_Pupil"]:
                p = surfaces[name, material]
                radial = p["POSITION"] - p["POSITION"].mean(0)
                self.assertGreater((radial * p["NORMAL"]).sum(1).mean(), 0)
                tri = p["POSITION"][p["triangles"]]
                face = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
                shading = p["NORMAL"][p["triangles"]].mean(1)
                self.assertGreater(((face * shading).sum(1) > 0).mean(), .99)
        for m in document["materials"]:
            if m["name"] in ("M_ST_Sclera", "M_ST_Iris", "M_ST_Pupil"):
                self.assertFalse(m.get("doubleSided", False))

    def test_teacher_bob_is_locally_refined_not_replaced_by_a_generic_cap(self) -> None:
        _document, _binary, original = parts(self.teacher_source)
        _document, _binary, refined = self.outputs[1]
        for material in ("M_ST_Hair", "M_ST_HairLight"):
            old = original["ST_Hair", material]
            new = refined["ST_Hair", material]
            np.testing.assert_array_equal(old["triangles"], new["triangles"])
            self.assertGreater(np.linalg.norm(old["POSITION"] - new["POSITION"], axis=1).max(), .001)
            self.assertLess(np.linalg.norm(old["POSITION"] - new["POSITION"], axis=1).max(), .0041)
            np.testing.assert_array_equal(old["JOINTS_0"], new["JOINTS_0"])

    def test_runtime_models_stay_within_the_existing_hard_budget(self) -> None:
        for model in [self.teacher_bytes, self.student_bytes]:
            self.assertLessEqual(len(model), 1536 * 1024)

    def test_existing_scale_and_sole_contracts_are_preserved(self) -> None:
        for source, (_document, _binary, surfaces) in zip(
                [self.student_source, self.teacher_source], self.outputs):
            _old_doc, _old_binary, old = parts(source)
            # N's source includes a separate preview floor, which is intentionally not a body.
            original = np.concatenate([p["POSITION"] for (name, _mat), p in old.items()
                                       if name != "ST_Stage_Floor_mesh"])
            refined = np.concatenate([p["POSITION"] for p in surfaces.values()])
            np.testing.assert_allclose(refined.min(0), original.min(0), atol=.02)
            np.testing.assert_allclose(refined.max(0), original.max(0), atol=.02)
            self.assertAlmostEqual(float(refined[:, 1].min()), float(original[:, 1].min()), places=6)


if __name__ == "__main__":
    unittest.main(verbosity=2)
