#!/usr/bin/env python3
"""The V2 protagonist export, pinned against its archived V1 source (issue #383).

The runtime model is built by tools/head_v2.py from
art/character_models/sculpt/lead_v1_head.glb -- the sculpt chain's own output --
so the contract lives here: the build is reproducible, the head got the density,
UV and morph resampling it was rebuilt for, and everything outside the scope of
the change arrives from V1 with its values intact.

Pin history (deliberate updates, each with its reason):
- 2026-11 the protagonist reconstruction brief supersedes issue #383's
  "mirror-perfect brows": the art direction now asks for controlled asymmetry
  (his right brow rides ~2 mm higher and thicker). The brow test pins the
  designed asymmetry band and its direction instead of a sub-mm mirror, while
  the brow morph deltas stay mirrored so an expression cannot re-tilt them.
- 2026-11 the wardrobe pass (issue #383's later clothing phase) subdivides and
  reshapes three garment primitives (jacket, trousers, jacket details). Those
  are now in scope: their joints/weights/attribute sets are asserted by value
  and by set, never by byte. The other five body primitives remain byte pins.
- 2026-11 the hair redesign retires V1's 1.767 m spike silhouette for the
  designed 1.708 m crown; the silhouette test pins the ground line exactly and
  the crown to the designed band. The runtime is no longer byte-comparable to
  V1 anywhere in scope, so "skins" compares joints and inverse-bind values
  rather than accessor indices (the packer re-indexes accessors).
"""
from __future__ import annotations

import hashlib
import sys
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import brow_seat
import head_v2
from glb_io import accessor, decode

V1 = ROOT / "art/character_models/sculpt/lead_v1_head.glb"
RUNTIME = ROOT / "assets/models/protagonist/Protagonist_Character.glb"

# The meshes the V2 head/hair/eyes rebuild owns. The three wardrobe primitives
# are garment geometry owned by the wardrobe pass. Everything else -- the body
# under the jacket, the buttons, the feet, the hands, the skeleton and the
# clips -- has to come through with its values untouched.
V2_MESHES = {"Protagonist_Head", "Protagonist_Hair", "Protagonist_Eyes"}
WARDROBE_PRIMS = {(7, 0), (0, 1), (8, 0)}  # jacket, trousers, jacket details


def read(doc, data, index):
    return np.asarray(accessor(doc, data, index))


def floats(doc, data, index):
    """An accessor as float64, undoing glTF's normalized-integer storage."""
    acc = doc["accessors"][index]
    values = read(doc, data, index).astype(np.float64)
    if acc.get("normalized"):
        full_scale = {5120: 127.0, 5121: 255.0, 5122: 32767.0, 5123: 65535.0}
        values = values / full_scale[acc["componentType"]]
    return values


def primitives(doc):
    for mesh_index, mesh in enumerate(doc["meshes"]):
        for prim_index, prim in enumerate(mesh["primitives"]):
            yield mesh_index, mesh.get("name"), prim_index, prim


def clip_structure(doc):
    """Animations with their sample payloads replaced by nothing: names, targets, modes."""
    return [
        {
            "name": animation.get("name"),
            "samplers": [{"interpolation": s.get("interpolation")} for s in animation["samplers"]],
            "channels": animation["channels"],
        }
        for animation in doc["animations"]
    ]


def dense_weights(doc, data, prim):
    """Effective per-joint weights - slot order carries no meaning."""
    joints = read(doc, data, prim["attributes"]["JOINTS_0"]).astype(np.int64)
    weights = floats(doc, data, prim["attributes"]["WEIGHTS_0"])
    width = int(joints.max()) + 1 if len(joints) else 1
    dense = np.zeros((len(joints), width), np.float64)
    for slot in range(4):
        np.add.at(dense, (np.arange(len(joints)), joints[:, slot]), weights[:, slot])
    return dense


class V2Export(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.v1, cls.v1_bin = V1.read_bytes(), None
        cls.rt, cls.rt_bin = RUNTIME.read_bytes(), None
        cls.v1_doc, cls.v1_bin = decode(cls.v1)
        cls.rt_doc, cls.rt_bin = decode(cls.rt)

    def test_v1_source_is_the_recorded_export(self):
        digest = hashlib.sha256(self.v1).hexdigest()
        self.assertEqual(digest, head_v2.V1_SHA)

    def test_contract_holds_and_the_committed_runtime_is_this_build(self):
        # check() re-exports from the archived V1 and fails unless the committed
        # runtime is byte-for-byte that build's output, then measures the V2
        # contract: UV atlas inside [0, 1] with no seam-wrapping triangle, four
        # eyelid shells with an 8-10 mm aperture, nine morph targets, the 96
        # hair locks of the approved style, the pinned hair envelope, and the
        # model size budget.
        report = head_v2.check()
        self.assertTrue(report["head_has_uv"])
        self.assertEqual(report["head_targets"], 9)
        self.assertEqual(report["lid_shells"], 4)
        self.assertEqual(report["hair_locks"], 96)
        self.assertEqual(report["eye_targets"], 0)

    def test_skeleton_clips_and_untouched_prims_keep_their_v1_values(self):
        # Reason for the pin change: glb_edit re-packs accessors, so skins are
        # compared by joints/skeleton/inverse-bind VALUES (an accessor index is
        # packing, not data), and the three wardrobe primitives are compared by
        # attribute set and by weight validity instead of bytes. The five
        # untouched body primitives stay byte-pinned as before.
        for key in ("asset", "nodes", "scenes", "materials"):
            self.assertEqual(self.v1_doc[key], self.rt_doc[key], key)
        self.assertEqual(len(self.v1_doc["skins"]), len(self.rt_doc["skins"]), "skin count")
        for a, b in zip(self.v1_doc["skins"], self.rt_doc["skins"]):
            self.assertEqual(a.get("joints"), b.get("joints"), "skin joints")
            self.assertEqual(a.get("skeleton"), b.get("skeleton"), "skin skeleton")
            np.testing.assert_array_equal(
                read(self.v1_doc, self.v1_bin, a["inverseBindMatrices"]),
                read(self.rt_doc, self.rt_bin, b["inverseBindMatrices"]),
                err_msg="inverse bind matrices",
            )
        untouched = 0
        for (m1, n1, p1, a), (m2, n2, p2, b) in zip(
            primitives(self.v1_doc), primitives(self.rt_doc)
        ):
            self.assertEqual((m1, n1, p1), (m2, n2, p2))
            if n1 in V2_MESHES:
                continue
            self.assertEqual(set(a["attributes"]), set(b["attributes"]), n1)
            if (m1, p1) in WARDROBE_PRIMS:
                # The wardrobe pass subdivides: original rows keep their weights
                # (new rows are interpolations that must stay normalised), the
                # joints stay inside V1's set, and nothing else moved in schema.
                original = len(read(self.v1_doc, self.v1_bin, a["attributes"]["POSITION"]))
                self.assertGreaterEqual(
                    len(read(self.rt_doc, self.rt_bin, b["attributes"]["POSITION"])), original, n1)
                np.testing.assert_allclose(
                    dense_weights(self.v1_doc, self.v1_bin, a),
                    dense_weights(self.rt_doc, self.rt_bin, b)[:original],
                    rtol=0, atol=2e-3, err_msg=f"{n1} weights (original rows)")
                dense_rt = dense_weights(self.rt_doc, self.rt_bin, b)
                np.testing.assert_allclose(dense_rt.sum(axis=1), 1.0, rtol=0, atol=2e-3,
                                           err_msg=f"{n1} weights sum")
                joints = read(self.rt_doc, self.rt_bin, b["attributes"]["JOINTS_0"])
                self.assertLessEqual(int(joints.max()), 58, f"{n1} joints")
                continue
            untouched += 1
            for key in sorted(a["attributes"]):
                np.testing.assert_array_equal(
                    read(self.v1_doc, self.v1_bin, a["attributes"][key]),
                    read(self.rt_doc, self.rt_bin, b["attributes"][key]),
                    err_msg=f"{n1}.{key}",
                )
            np.testing.assert_array_equal(
                read(self.v1_doc, self.v1_bin, a["indices"]),
                read(self.rt_doc, self.rt_bin, b["indices"]),
                err_msg=f"{n1}.indices",
            )
            self.assertEqual(len(a.get("targets", ())), len(b.get("targets", ())), n1)
        # Nine meshes; the V2 trio is not allowed to hide a fourth, and the
        # wardrobe three leave five body primitives byte-identical to V1.
        self.assertEqual(untouched, 5)

    def test_clips_keep_their_channels_and_samples(self):
        self.assertEqual(clip_structure(self.v1_doc), clip_structure(self.rt_doc))
        for a, b in zip(
            (s for animation in self.v1_doc["animations"] for s in animation["samplers"]),
            (s for animation in self.rt_doc["animations"] for s in animation["samplers"]),
        ):
            np.testing.assert_array_equal(
                read(self.v1_doc, self.v1_bin, a["input"]),
                read(self.rt_doc, self.rt_bin, b["input"]),
            )
            np.testing.assert_array_equal(
                read(self.v1_doc, self.v1_bin, a["output"]),
                read(self.rt_doc, self.rt_bin, b["output"]),
            )

    def test_head_keeps_the_silhouette_height_uvs_and_expression_keys(self):
        def bounds(doc, data):
            ys = np.concatenate(
                [read(doc, data, p["attributes"]["POSITION"])[:, 1] for _, _, _, p in primitives(doc)]
            )
            return ys.min(), ys.max()

        # Reason for the pin change: the ground line is a hard pin (nothing may
        # float or sink), but the crown band replaces V1's exact 1.7669 m spike
        # silhouette - the hair redesign retires it for the designed 1.708 m cut.
        v1_min, v1_max = bounds(self.v1_doc, self.v1_bin)
        rt_min, rt_max = bounds(self.rt_doc, self.rt_bin)
        self.assertAlmostEqual(rt_min, v1_min, delta=1e-3, msg="ground line")
        self.assertGreaterEqual(rt_max, 1.704, "designed crown (low)")
        self.assertLessEqual(rt_max, 1.712, "designed crown (high)")
        head_v1 = next(p for _, n, _, p in primitives(self.v1_doc) if n == "Protagonist_Head")
        head_rt = next(p for _, n, _, p in primitives(self.rt_doc) if n == "Protagonist_Head")
        self.assertIn("TEXCOORD_0", head_rt["attributes"])
        self.assertNotIn("TEXCOORD_0", head_v1["attributes"])
        uv = floats(self.rt_doc, self.rt_bin, head_rt["attributes"]["TEXCOORD_0"])
        self.assertTrue(np.isfinite(uv).all())
        self.assertGreaterEqual(uv.min(), 0.0)
        self.assertLessEqual(uv.max(), 1.0)
        normals = floats(self.rt_doc, self.rt_bin, head_rt["attributes"]["NORMAL"])
        # V2 stores normals as normalized int16, so a unit vector is only unit
        # to within one quantisation step (1/32767 per component).
        np.testing.assert_allclose(np.linalg.norm(normals, axis=1), 1.0, rtol=0, atol=1e-4)
        keys_v1 = set(self.v1_doc["meshes"][head_v2.HEAD_MESH].get("extras", {}).get("targetNames", ()))
        keys_rt = set(self.rt_doc["meshes"][head_v2.HEAD_MESH].get("extras", {}).get("targetNames", ()))
        self.assertEqual(keys_v1, keys_rt)
        self.assertEqual(len(keys_rt), 9)
        # The rebuild is a precision change, not a decimation.
        tris = lambda doc, data: sum(
            len(read(doc, data, p["indices"])) // 3
            for _, n, _, p in primitives(doc) if n == "Protagonist_Head"
        )
        self.assertGreater(tris(self.rt_doc, self.rt_bin), 3 * tris(self.v1_doc, self.v1_bin))

    def test_brows_read_as_one_design_with_mirrored_motions(self):
        # Issue #385 asked for one perfectly even arch; the reconstruction brief
        # that supersedes it asks for controlled asymmetry - a tired face where
        # the his-right brow rides about 2 mm higher and reads thicker. So the
        # rest pose pins a designed asymmetry band WITH a direction (his side,
        # every band), while the brow-moving morph deltas stay mirrored so no
        # expression can re-tilt the pair. Seating is unchanged: no vertex may
        # droop off its tube or float off the skin.
        brow = np.asarray(accessor(self.rt_doc, self.rt_bin,
                                   self.rt_doc["meshes"][head_v2.HEAD_MESH]["primitives"][1]["attributes"]["POSITION"])).astype(float)
        skin = np.asarray(accessor(self.rt_doc, self.rt_bin,
                                   self.rt_doc["meshes"][head_v2.HEAD_MESH]["primitives"][0]["attributes"]["POSITION"])).astype(float)
        tris = np.asarray(accessor(self.rt_doc, self.rt_bin,
                                   self.rt_doc["meshes"][head_v2.HEAD_MESH]["primitives"][0]["indices"]), np.int64).reshape(-1, 3)
        residual = brow_seat.mirror_residuals(brow) * 1000
        self.assertGreaterEqual(residual.mean(), 1.0, "designed brow asymmetry mean (mm)")
        self.assertLessEqual(residual.mean(), 3.5, "designed brow asymmetry mean (mm)")
        self.assertLessEqual(residual.max(), 6.0, "brow mirror max (mm)")
        arch = brow_seat.arch_profile(brow)
        for band in ("inner", "mid", "outer"):
            # brow_seat's L is the x < 0 side = the character's right.
            gap = (arch[("L", band)] - arch[("R", band)]) * 1000
            self.assertGreaterEqual(gap, 0.5, f"arch {band} his-right lift (mm)")
            self.assertLessEqual(gap, 4.0, f"arch {band} his-right lift (mm)")
        gap = brow_seat.surface_gap(skin, tris, brow) * 1000
        self.assertLessEqual(gap.mean(), 1.5, "brow-to-skin gap mean (mm)")
        self.assertLessEqual(gap.max(), 3.5, "brow-to-skin gap max (mm)")
        names = self.rt_doc["meshes"][head_v2.HEAD_MESH].get("extras", {}).get("targetNames", ())
        for target in ("BrowRaise", "BrowCompress", "Frown"):
            index = names.index(target)
            delta = np.asarray(accessor(self.rt_doc, self.rt_bin,
                                        self.rt_doc["meshes"][head_v2.HEAD_MESH]["primitives"][1]["targets"][index]["POSITION"])).astype(float)
            self.assertLessEqual(brow_seat.field_residuals(
                delta[brow[:, 0] < 0], delta[brow[:, 0] > 0]).max() * 1000, 1.0,
                f"{target} delta mirror max (mm)")


if __name__ == "__main__":
    unittest.main(verbosity=2)
