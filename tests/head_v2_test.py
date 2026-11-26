#!/usr/bin/env python3
"""The V2 protagonist head export, pinned against its archived V1 source (issue #383).

The runtime head is built by tools/head_v2.py from
art/character_models/sculpt/lead_v1_head.glb -- the sculpt chain's own output --
so the contract lives here: the build is reproducible, the head got the density,
UV and morph resampling it was rebuilt for, and everything issue #383 puts
outside the scope of the change (body, clothes, skeleton, weights, clips) arrives
from V1 with its values intact.
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

# The meshes issue #383 puts in scope for the V2 export. Everything else -- the
# body, jacket, buttons, feet, hands, the skeleton and the clips -- has to come
# through with its values untouched.
V2_MESHES = {"Protagonist_Head", "Protagonist_Hair", "Protagonist_Eyes"}


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
        # eyelid shells with a 10-15 mm aperture, nine morph targets, the 96
        # hair locks of the approved style, and the model size budget.
        report = head_v2.check()
        self.assertTrue(report["head_has_uv"])
        self.assertEqual(report["head_targets"], 9)
        self.assertEqual(report["lid_shells"], 4)
        self.assertEqual(report["hair_locks"], 96)
        self.assertEqual(report["eye_targets"], 0)

    def test_body_clothes_skeleton_and_weights_keep_their_v1_values(self):
        for key in ("asset", "nodes", "skins", "scenes", "materials"):
            self.assertEqual(self.v1_doc[key], self.rt_doc[key], key)
        checked = 0
        for (m1, n1, p1, a), (m2, n2, p2, b) in zip(
            primitives(self.v1_doc), primitives(self.rt_doc)
        ):
            self.assertEqual((m1, n1, p1), (m2, n2, p2))
            if n1 in V2_MESHES:
                continue
            checked += 1
            self.assertEqual(set(a["attributes"]), set(b["attributes"]), n1)
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
        # Nine meshes, and the three in scope are not allowed to hide a fourth:
        # the other six meshes hold eight primitives, all of them V1's.
        self.assertEqual(checked, 8)

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

        np.testing.assert_allclose(bounds(self.v1_doc, self.v1_bin),
                                   bounds(self.rt_doc, self.rt_bin),
                                   rtol=0, atol=3e-7)
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

    def test_brows_read_as_one_arch(self):
        # Issue #385: at close range the brows are the first thing the eye reads,
        # and "one brow lower" was the last visible residue of V1's floating brow -
        # an inner-end fan vertex the re-seating pass left at V1's position, 3.9 mm
        # below its ring. The contract here is the owner's ask in numbers: the two
        # brows read as one arch (heights within a millimetre at every third), no
        # vertex has drooped off the tube, the tubes ride the ridge, and the
        # brow-moving morph targets stay mirrored so an expression cannot re-tilt
        # them. The remaining ~2.7 mm mirror residual is V1's own end construction
        # (the two sides cap their inner ends differently, at stations 0.2 mm
        # apart), and each side now seats on its own local skin - levelling it
        # would be the mirror-flattening issue #385 forbids.
        brow = np.asarray(accessor(self.rt_doc, self.rt_bin,
                                   self.rt_doc["meshes"][head_v2.HEAD_MESH]["primitives"][1]["attributes"]["POSITION"])).astype(float)
        skin = np.asarray(accessor(self.rt_doc, self.rt_bin,
                                   self.rt_doc["meshes"][head_v2.HEAD_MESH]["primitives"][0]["attributes"]["POSITION"])).astype(float)
        tris = np.asarray(accessor(self.rt_doc, self.rt_bin,
                                   self.rt_doc["meshes"][head_v2.HEAD_MESH]["primitives"][0]["indices"]), np.int64).reshape(-1, 3)
        residual = brow_seat.mirror_residuals(brow) * 1000
        self.assertLessEqual(residual.mean(), 0.8, "brow mirror mean (mm)")
        self.assertLessEqual(residual.max(), 3.0, "brow mirror max (mm)")
        arch = brow_seat.arch_profile(brow)
        for band in ("inner", "mid", "outer"):
            self.assertLessEqual(abs(arch[("L", band)] - arch[("R", band)]) * 1000, 0.8,
                                 f"arch {band} L-R height gap (mm)")
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
