#!/usr/bin/env python3
"""Lossless Q preparation, source approval pin, fingers and retirement contract."""
from __future__ import annotations

import hashlib
import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import prepare_q as q


class QPreparationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source_bytes = q.SOURCE.read_bytes()
        cls.runtime_bytes = q.OUTPUT.read_bytes()
        cls.source, cls.source_bin = q.decode(cls.source_bytes)
        cls.runtime, cls.runtime_bin = q.decode(cls.runtime_bytes)
        cls.basis, cls.basis_bin = q.decode(q.prepare_base(cls.source_bytes))

    def test_exact_approved_source_and_reproducible_output(self) -> None:
        self.assertEqual(hashlib.sha256(self.source_bytes).hexdigest(), q.SOURCE_SHA256)
        self.assertEqual(q.prepare(self.source_bytes), self.runtime_bytes)
        with self.assertRaisesRegex(ValueError, "approved Q source changed"):
            q.prepare(self.source_bytes[:-1] + bytes([self.source_bytes[-1] ^ 1]))

    def test_only_the_debug_display_node_mesh_and_material_are_removed(self) -> None:
        self.assertEqual(self.source["nodes"][:-1], self.runtime["nodes"])
        self.assertEqual(self.runtime["scenes"][0]["nodes"], [69])
        self.assertEqual(len(self.runtime["meshes"]), 9)
        self.assertEqual(len(self.runtime["materials"]), 12)
        self.assertTrue(all("preview" not in m["name"].lower() for m in self.runtime["meshes"]))
        self.assertEqual(self.source["skins"][0]["joints"], self.runtime["skins"][0]["joints"])
        self.assertEqual(len(self.runtime["skins"][0]["joints"]), 60)
        self.assertEqual(q.accessor(self.source, self.source_bin, self.source["skins"][0]["inverseBindMatrices"]),
                         q.accessor(self.runtime, self.runtime_bin, self.runtime["skins"][0]["inverseBindMatrices"]))

    def _equal_accessor(self, before: int, after: int) -> None:
        self.assertEqual(q.accessor(self.source, self.source_bin, before),
                         q.accessor(self.runtime, self.runtime_bin, after))

    def _equal_basis_accessor(self, before: int, after: int) -> None:
        self.assertEqual(q.accessor(self.source, self.source_bin, before),
                         q.accessor(self.basis, self.basis_bin, after))

    def test_basis_copies_every_vertex_normal_weight_index_colour_and_morph(self) -> None:
        for source, basis in zip(self.source["meshes"][:-1], self.basis["meshes"], strict=True):
            self.assertEqual(source["name"], basis["name"])
            self.assertEqual(source.get("extras"), basis.get("extras"))
            self.assertEqual(len(source["primitives"]), len(basis["primitives"]))
            for a, b in zip(source["primitives"], basis["primitives"], strict=True):
                self.assertEqual(a.get("mode", 4), b.get("mode", 4))
                self.assertEqual(a["material"], b["material"])
                self._equal_basis_accessor(a["indices"], b["indices"])
                self.assertEqual(set(a["attributes"]), set(b["attributes"]))
                for key in a["attributes"]:
                    self._equal_basis_accessor(a["attributes"][key], b["attributes"][key])
                self.assertEqual(len(a.get("targets", [])), len(b.get("targets", [])))
                for x, y in zip(a.get("targets", []), b.get("targets", []), strict=True):
                    self.assertEqual(set(x), set(y))
                    for key in x:
                        self._equal_basis_accessor(x[key], y[key])
        head = next(m for m in self.runtime["meshes"] if m["name"] == "Q_Head")
        self.assertEqual(len(head["extras"]["targetNames"]), 13)

    def test_all_six_actions_and_every_non_rest_channel_are_preserved(self) -> None:
        expected = {"Q_Casual_Hand_Gesture": 21, "Q_Head_Movement": 3,
                    "Q_Idle_Breathing": 7, "Q_Pose_Preview": 29,
                    "Q_Slight_Body_Lean": 9, "Q_Face_Test": 1}
        self.assertEqual({a["name"]: len(a["channels"]) for a in self.runtime["animations"]}, expected)
        for source, runtime in zip(self.source["animations"], self.runtime["animations"]):
            kept = {(c["target"]["node"], c["target"]["path"]): c for c in runtime["channels"]}
            for channel in source["channels"]:
                target = channel["target"]
                key = target["node"], target["path"]
                sampler = source["samplers"][channel["sampler"]]
                if key in kept:
                    after = runtime["samplers"][kept[key]["sampler"]]
                    self.assertEqual(sampler.get("interpolation"), after.get("interpolation"))
                    self._equal_accessor(sampler["input"], after["input"])
                    self._equal_accessor(sampler["output"], after["output"])
                else:
                    # Independently verify every discarded sample equals the rest:
                    # a constant *posed* channel must not be removed with the constants.
                    defaults = {"translation": (0, 0, 0), "rotation": (0, 0, 0, 1), "scale": (1, 1, 1)}
                    self.assertIn(target["path"], defaults)
                    rest = self.source["nodes"][target["node"]].get(target["path"], defaults[target["path"]])
                    for row in q.accessor(self.source, self.source_bin, sampler["output"]):
                        if target["path"] == "rotation":
                            dot = abs(sum(x * y for x, y in zip(row, rest)))
                            self.assertAlmostEqual(dot, 1.0, places=5)
                        else:
                            self.assertLess(max(abs(x - y) for x, y in zip(row, rest)), 0.0000021)

    def test_both_hands_have_five_individually_weighted_three_joint_fingers(self) -> None:
        doc, binary = self.runtime, self.runtime_bin
        joints = doc["skins"][0]["joints"]
        parents = {child: index for index, node in enumerate(doc["nodes"]) for child in node.get("children", [])}
        by_name = {node["name"]: index for index, node in enumerate(doc["nodes"])}
        used = set()
        hand = next(m for m in doc["meshes"] if m["name"] == "Q_Hands")
        for primitive in hand["primitives"]:
            bones = q.accessor(doc, binary, primitive["attributes"]["JOINTS_0"])
            weights = q.accessor(doc, binary, primitive["attributes"]["WEIGHTS_0"])
            for row, values in zip(bones, weights):
                self.assertTrue(all(math.isfinite(w) and w >= 0 for w in values))
                self.assertAlmostEqual(sum(values), 1.0, places=5)
                for joint, weight in zip(row, values):
                    if weight > 0.000001:
                        self.assertLess(joint, len(joints))
                        used.add(doc["nodes"][joints[joint]]["name"])
        for side in "LR":
            for finger in ("Thumb", "Index", "Middle", "Ring", "Little"):
                parent = by_name[f"Hand_{side}"]
                for segment in (1, 2, 3):
                    name = f"{finger}_{segment:02}_{side}"
                    index = by_name[name]
                    self.assertIn(name, used)
                    self.assertEqual(parents[index], parent)
                    parent = index

    def test_missing_material_colours_are_repaired_without_textures(self) -> None:
        self.assertFalse(self.runtime.get("textures"))
        self.assertFalse(self.runtime.get("images"))
        for material in self.runtime["materials"]:
            self.assertNotIn("extensions", material)
            colour = material["pbrMetallicRoughness"]["baseColorFactor"]
            self.assertEqual(len(colour), 4)
            self.assertNotEqual(colour, [1, 1, 1, 1])
            self.assertTrue(all(0 <= component <= 1 for component in colour))

    def test_no_retired_q_asset_can_be_imported_as_a_fallback(self) -> None:
        for relative in ("assets/models/q/q.glb", "assets/models/q/q.glb.import",
                         "scenes/dev/animation_retarget_test/q_rigged.glb",
                         "scenes/dev/animation_retarget_test/q_rigged.glb.import",
                         "art/character_rigging/q/q_unrigged_source.glb",
                         "art/character_rigging/q/q_rigged_working.blend"):
            self.assertFalse((q.ROOT / relative).exists(), relative)
        self.assertEqual(sorted(p.name for p in q.OUTPUT.parent.glob("*.glb")), ["new-Q.glb"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
