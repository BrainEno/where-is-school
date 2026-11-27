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
import brow_seat
from glb_io import accessor
import character_geometry as geometry
import character_hair as hair
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


def _inside(points: np.ndarray, skin: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    """Point-in-mesh by ray parity, along a direction the skull has no face normal on."""
    direction = np.array([1.0, .3, 0.0])
    direction /= np.linalg.norm(direction)
    v0, v1, v2 = skin[triangles[:, 0]], skin[triangles[:, 1]], skin[triangles[:, 2]]
    e1, e2 = v1 - v0, v2 - v0
    h = np.cross(direction, e2)
    a = (e1 * h).sum(1)
    valid = np.abs(a) > 1e-12
    f = np.zeros_like(a)
    f[valid] = 1.0 / a[valid]
    out = np.zeros(len(points), bool)
    for i, point in enumerate(points):
        s = point - v0
        u = f * (s * h).sum(1)
        q = np.cross(s, e1)
        v = f * (q @ direction)
        t = f * (q * e2).sum(1)
        hits = valid & (u >= 0) & (u <= 1) & (v >= 0) & (u + v <= 1) & (t > 1e-6)
        out[i] = int(hits.sum()) % 2 == 1
    return out


def _spread(points: np.ndarray) -> np.ndarray:
    """Gaps, in degrees, between neighbouring points around their own centre."""
    angle = np.degrees(np.arctan2(points[:, 1], points[:, 0]))
    angle = np.sort(angle)
    return np.diff(np.append(angle, angle[0] + 360.0))


def _first_hit(origin: np.ndarray, rays: np.ndarray, points: np.ndarray,
               triangles: np.ndarray) -> np.ndarray:
    """Distance to the first triangle each ray meets, or inf."""
    v0, v1, v2 = points[triangles[:, 0]], points[triangles[:, 1]], points[triangles[:, 2]]
    e1, e2 = v1 - v0, v2 - v0
    out = np.full(len(rays), np.inf)
    for i, direction in enumerate(rays):
        h = np.cross(direction, e2)
        a = (e1 * h).sum(1)
        valid = np.abs(a) > 1e-12
        f = np.zeros_like(a)
        f[valid] = 1.0 / a[valid]
        s = origin - v0
        u = f * (s * h).sum(1)
        q = np.cross(s, e1)
        v = f * (q @ direction)
        t = f * (q * e2).sum(1)
        hit = valid & (u >= 0) & (u <= 1) & (v >= 0) & (u + v <= 1) & (t > 1e-6)
        if hit.any():
            out[i] = float(t[hit].min())
    return out


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

    def test_teacher_brows_keep_the_hand_built_pair(self) -> None:
        # Issue #385, teacher seat: N's brows are hand-built and sit within a
        # millimetre of their mirror (2.1 mm at the inner caps), both tubes ride
        # the brow ridge, and the two authored morph deltas keep their own small
        # lopsidedness. The pair is the author's; this contract pins it so a
        # rebuild cannot quietly tilt or flatten it.
        doc, blob, meshes = self.outputs[1]
        sides = [item for (name, _material), item in meshes.items() if name.startswith("ST_Eyebrow_")]
        self.assertEqual(len(sides), 2)
        left = next(item for item in sides if float(np.mean(item["POSITION"][:, 0])) < 0)
        right = next(item for item in sides if float(np.mean(item["POSITION"][:, 0])) > 0)
        residual = brow_seat.field_residuals(left["POSITION"].astype(float), right["POSITION"].astype(float)) * 1000
        self.assertLessEqual(residual.mean(), 1.3, "brow mirror mean (mm)")
        self.assertLessEqual(residual.max(), 2.5, "brow mirror max (mm)")
        brow = np.concatenate([left["POSITION"], right["POSITION"]]).astype(float)
        arch = brow_seat.arch_profile(brow)
        for band in ("inner", "mid", "outer"):
            self.assertLessEqual(abs(arch[("L", band)] - arch[("R", band)]) * 1000, 2.5,
                                 f"arch {band} L-R height gap (mm)")
        face = next(item for (name, material), item in meshes.items()
                    if name == "ST_Head_Skin" and material == "M_ST_Skin")
        gap = brow_seat.surface_gap(face["POSITION"].astype(float), face["triangles"], brow) * 1000
        self.assertLessEqual(gap.mean(), 1.5, "brow-to-skin gap mean (mm)")
        self.assertLessEqual(gap.max(), 3.0, "brow-to-skin gap max (mm)")
        # The build re-expresses the author's three brow shapes against the seated
        # rest and keeps two of them; the kept pair stays a hand-balanced match -
        # each side's peak delta within half a millimetre of the other's.
        peaks = {}
        for name in ("ST_Eyebrow_L", "ST_Eyebrow_R"):
            mesh = next(m for m in doc["meshes"] if m["name"] == name)
            names = (mesh.get("extras") or {}).get("targetNames") or []
            self.assertEqual(names, ["Brow_Compress", "Frown"], f"{name} kept shapes")
            for target_name, target in zip(names, mesh["primitives"][0]["targets"]):
                # The runtime stores morph deltas sparsely; glb_io's reader is the
                # one that expands them (teacher.read_accessor refuses sparse on
                # purpose, so nothing silently reads a half-written target).
                delta = np.asarray(accessor(doc, blob, target["POSITION"]), float)
                peaks[target_name, name] = float(np.linalg.norm(delta, axis=1).max()) * 1000
            self.assertLessEqual(max(peaks.values()), 4.0, f"{name} delta magnitude (mm)")
        for target_name in ("Brow_Compress", "Frown"):
            self.assertLessEqual(abs(peaks[target_name, "ST_Eyebrow_L"]
                                     - peaks[target_name, "ST_Eyebrow_R"]), 0.5,
                                 f"{target_name} authored L-R balance (mm)")

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

    def test_student_face_normals_have_canonical_axis_zeros(self) -> None:
        normals = self.outputs[0][2]["Head_Main_Mesh_Mesh", "WIS_Protagonist_Skin"]["NORMAL"]
        zero = normals == 0
        self.assertTrue(zero.any(), "there are symmetric vertices on the head centreline")
        self.assertFalse(np.signbit(normals[zero]).any(), "normalize signed zeros before writing")
        self.assertFalse((np.abs(normals[~zero]) < 1e-12).any(), "no CPU-dependent cancellation residue")

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
            # Thumb opposes the palm lower than the four unequal finger tips. Check
            # its reach relative to the narrower metacarpus, not a world-space width.
            cut = geometry.TEACHER_HAND if teacher_hand else geometry.STUDENT_HAND
            size = cut.scale
            self.assertEqual(components(p[:, 1] > .100 * size), 4, "four distinct fingers above the webs")
            x = p[:, 0] / (size * cut.width)
            thumb = x > .043
            self.assertEqual(components(thumb), 1, "thumb silhouette is missing or disconnected")
            self.assertGreater(x[thumb].max(), .057)
            self.assertLess(p[thumb, 1].max(), .090 * size)
            tips = [p[np.abs(x - (x0 + (.0015 if teacher_hand else .0032) * (1.5 - i))) < .004, 1].max()
                    for i, (x0, _length, _width) in enumerate(cut.digits)]
            self.assertEqual(len(set(np.round(tips, 4))), 4)
            self.assertGreater(tips[2], tips[3])
            self.assertLess(tips[0], tips[1])
            self.assertLess(len(t), 2400, "the shallow pads do not need revision 1's 4600 triangles")

    def test_student_relaxes_its_fingers_more_than_the_teacher(self) -> None:
        adult, student_hand = (geometry.canonical_hand(flag).positions for flag in [True, False])
        # Compare actual 3-D finger pads in the same canonical coordinate system.
        def tip_advance(p):
            return p[p[:, 1] > .112, 2].max() - np.median(p[p[:, 1] < .025, 2])
        self.assertGreater(tip_advance(student_hand), tip_advance(adult) + .008)
        self.assertLess(student_hand[:, 1].max(), adult[:, 1].max() - .014)


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

    def test_teacher_bob_keeps_shell_back_locks_and_exact_crown(self) -> None:
        _document, _binary, original = parts(self.teacher_source)
        _document, _binary, refined = self.outputs[1]
        for material in ("M_ST_Hair", "M_ST_HairLight"):
            old = original["ST_Hair", material]
            new = refined["ST_Hair", material]
            _geometry, kept = geometry.teacher_bob(old["POSITION"], old["triangles"])
            # Only disconnected forehead tufts may leave the source bob. Every other
            # original face stays, in order, even after compacting unused indices.
            remapped = kept[new["triangles"]]
            before = {tuple(triangle) for triangle in old["triangles"]}
            retained = {tuple(triangle) for triangle in remapped}
            self.assertTrue(retained < before)
            discarded = old["POSITION"][np.asarray(sorted(before - retained))]
            self.assertGreater(discarded[:, :, 1].min(), 1.53)
            self.assertLess(discarded[:, :, 2].max(), -.046)
            self.assertEqual(len(before - retained), 520 if material == "M_ST_Hair" else 208)
            # The shipped hair is the source pass plus the skull-fitted crop, so what is
            # checked here is the pair: the source vertices survive in order, and the crop
            # is a real short cut rather than a lift.
            shipped = new["POSITION"]
            self.assertEqual(len(shipped), len(kept))
            # The owner's r37 note re-cut the sides to drape over the ears and past the
            # lobes (revision 7), so the old 1.500 length line -- the earlier crop's
            # over-the-ear hem -- no longer measures the cut. Below 1.460 no hair is
            # authorised at all: the source bob's kept tail has hundreds of vertices
            # under it, the shipped cut has none.
            below = lambda points: int((points[:, 1] < 1.460).sum())
            self.assertLess(below(shipped), below(old["POSITION"][kept]) * .10,
                            "the crop did not take length off the bob")
            # Nothing hangs below the ear lobe, which is what made it a bob.
            self.assertGreater(float(shipped[:, 1].min()), 1.470)
            # The cut sits on the hairline, not somewhere up the shell: every vertex is at
            # or above the hem curve for its own angle, and the crown is untouched.
            radius, _outward, angle = hair.polar(shipped)
            hem = hair.hem_height(angle)
            self.assertGreater(int((shipped[:, 1] >= hem - 1e-6).sum()),
                               len(shipped) - 8)
            # The crown is where the skull stops having sides, so the radial fit has to be
            # faded out there (see `character_hair._place`); the cap keeps its authored
            # clearance, and the displacement above the top ring is a few millimetres
            # rather than the single millimetre a radial-only fit used to give.
            top = old["POSITION"][kept, 1] > 1.632
            if top.any():   # the highlight sheet is cards; it has no cap of its own
                self.assertLess(float(np.abs(shipped[top] - old["POSITION"][kept[top]]).max()),
                                .045)
            np.testing.assert_array_equal(old["JOINTS_0"][kept], new["JOINTS_0"])

    def test_teacher_hair_sits_outside_the_skull(self) -> None:
        """The bug that made the nape look torn: hair vertices inside the head.

        Revision 3 lifted and tucked the shell, which pushed most of its lower half through
        the skull; the skull then showed through the hair as the pale teeth at the nape.
        """
        _document, _binary, original = parts(self.teacher_source)
        document, binary, refined = self.outputs[1]
        skin = refined["ST_Head_Skin", "M_ST_Skin"]["POSITION"]
        triangles = refined["ST_Head_Skin", "M_ST_Skin"]["triangles"]
        # The skull is an open surface -- the neck, the mouth and both ear canals are holes
        # -- so a vertex just under a rim reads as "inside" without being buried. What has
        # to be true is that no *run* of the hair is inside: the revision this replaces had
        # whole rows of the shell through the skull, which is what showed as pale teeth.
        #
        # Two shapes of the same fact, because the two sheets fail differently. The curtain
        # is thousands of vertices, so it is a fraction of itself; the highlight sheet is
        # seventeen cards of sixteen, so a per-card fraction is the only meaningful unit.
        # (The curtain does keep a small pocket of its inner fold behind the crown, a few
        # centimetres inside the skull; it is enclosed by the hair above it and invisible.)
        for material in ("M_ST_Hair", "M_ST_HairLight"):
            points = refined["ST_Hair", material]["POSITION"]
            inside = _inside(points, skin, triangles)
            pieces = [np.asarray(part, np.int64) for part
                      in hair.islands(len(points), refined["ST_Hair", material]["triangles"])]
            largest = max(pieces, key=len)
            # A curtain this big says something as a fraction of itself; the highlight sheet
            # has no curtain at all (its largest piece is one card), so for it the per-card
            # check below is the whole statement. 3%, against the 43% that this check was
            # written for: what is left is the inner face of one fold behind the crown,
            # enclosed by the hair over it and never visible.
            if len(largest) > 1000:
                self.assertLess(inside[largest].mean(), .03,
                                "%s: %.1f%% of the curtain is inside the head"
                                % (material, 100 * inside[largest].mean()))
            for part in pieces:
                self.assertLess(inside[part].mean(), .60,
                                "%s: a piece of %d vertices is %.0f%% inside the head"
                                % (material, len(part), 100 * inside[part].mean()))

    def test_teacher_crown_shows_no_skin_through_the_hair(self) -> None:
        """From behind, no ray at the crown may reach the skull before the hair.

        The curtain is tangent to the skull along the back midline, and the skull was
        0.6 mm proud of it there, which showed as a hairline-thin pale seam running up the
        crown. Vertex-in-mesh tests cannot see this -- both sheets are outside each other
        almost everywhere -- so the check is the one the eye makes: cast from behind and
        see which surface is first. `teacher_crown_part` lifts the band until none is.
        """
        _document, _binary, _refined = self.outputs[1]
        refined = _refined
        skin = refined["ST_Head_Skin", "M_ST_Skin"]
        hair_points = refined["ST_Hair", "M_ST_Hair"]["POSITION"]
        # Rays from behind, straight down the midline: the seam was a sliver two pixels
        # wide that followed the sheets' tangency up the crown, so a fan wide enough to
        # miss it proves nothing. This is a narrow, dense grid on the line of the seam.
        eye = np.array([0.0, 1.60, .34])
        target = np.array([0.0, 1.585, .02])
        forward = target - eye
        forward /= np.linalg.norm(forward)
        right = np.cross(np.array([0.0, 1.0, 0.0]), forward)
        right /= np.linalg.norm(right)
        up = np.cross(forward, right)
        rows = np.linspace(-.30, .40, 70)[:, None]
        cols = np.linspace(-.030, .030, 25)[None, :]
        rays = (forward + cols[..., None] * np.tan(.10) * right
                + rows[..., None] * np.tan(.10) * up).reshape(-1, 3)
        rays /= np.linalg.norm(rays, axis=1, keepdims=True)
        skin_hit = _first_hit(eye, rays, skin["POSITION"], skin["triangles"])
        hair_hit = _first_hit(eye, rays, hair_points, refined["ST_Hair", "M_ST_Hair"]["triangles"])
        both = np.isfinite(skin_hit) & np.isfinite(hair_hit)
        # Only the back of the head: rays that reach the skull at the nape are below the
        # hem by design, so they are excluded by asking where they land.
        points = eye + rays * np.where(np.isfinite(skin_hit), skin_hit, 0.0)[:, None]
        crown = both & (points[:, 1] > 1.545)
        self.assertGreater(int(crown.sum()), 400, "the probe does not cover the crown")
        proud = crown & (skin_hit < hair_hit)
        self.assertEqual(int(proud.sum()), 0,
                         "%d of %d crown rays reach the skull before the hair"
                         % (proud.sum(), crown.sum()))

    def test_teacher_ear_has_a_concha(self) -> None:
        """The ear is a shell whose middle is the bowl, not the highest part of the dome.

        The source ear is one smooth convex dome -- frontmost at its rim and shallowing
        inward -- so it read as a flat oval pasted on the skull. The concha is what makes
        an ear read, and it is the one place where the front face must be *nearer* the
        skull than the cartilage around it.
        """
        _document, _binary, original = parts(self.teacher_source)
        _document, _binary, refined = self.outputs[1]
        for side in ("L", "R"):
            before = original["ST_Ear_" + side, "M_ST_Skin"]["POSITION"]
            after = refined["ST_Ear_" + side, "M_ST_Skin"]["POSITION"]
            self.assertEqual(len(before), len(after))
            # The bowl is dug about the ear's own middle: 9 mm across at y 1.5335.
            bowl = (np.abs(after[:, 1] - 1.5345) < .005) & (np.abs(after[:, 2] - .0140) < .005)
            radius = np.abs(after[:, 0])
            self.assertGreater(float(np.median(radius[bowl])), float(radius[~bowl].min()),
                               "the concha floor is not inside the rim")
            depth = float((radius[bowl] - np.abs(before[:, 0])[bowl]).min())
            self.assertLess(depth, -.0025,
                            "the concha is not a bowl (floor moved %.2f mm inwards)" % (depth * 1e3))
            # A bowl, not a squeeze. The source ear was convex, so its middle was the
            # *shallowest* part; afterwards the middle must be the deepest, by a real
            # margin, and the cut must die out before the helix.
            was = np.abs(before[:, 0])
            now = np.abs(after[:, 0])
            floor = np.argmin(now - was)          # the deepest point of the cut
            self.assertLess(float(now[floor] - was[floor]), -.0035,
                            "the concha is not deep enough to read")
            self.assertLess(float(now[floor]), float(now.max()),
                            "the deepest cut is not inside the ear's front face")
            # The old dome was frontmost in the middle; the bowl has to have taken that
            # distinction away, which is the whole read of a concha.
            room = np.hypot(before[:, 1] - 1.5335, before[:, 2] - .0140) < .006
            self.assertLess(float(now[room].max()), float(now.max()),
                            "the middle of the ear is still the front of a dome")
            rim = was > was.max() - .001
            self.assertLess(float(np.abs(after[rim] - before[rim]).max()), .002,
                            "the helix rim moved")
            self.assertLess(float(np.abs(after - before).max()), .007)
            np.testing.assert_array_equal(original["ST_Ear_" + side, "M_ST_Skin"]["JOINTS_0"],
                                          refined["ST_Ear_" + side, "M_ST_Skin"]["JOINTS_0"])

    def test_teacher_mouth_seam_is_evenly_spaced(self) -> None:
        """The seam where the lip tube meets the face is one ring of 74 vertices.

        The source lip was resampled by hand, so its ring ran in uneven steps and the
        seam read as a stair-step across the lip line: measured as the ring's own second
        difference, the source bends by up to 3.4 mm between neighbouring steps, which is
        the jaggedness. The ring is now fitted with a small Fourier series in its own
        polar angle, which keeps every vertex and every triangle and only spreads the ring
        out, so the fix has to show up as *smoothness* rather than as a big displacement.
        """
        _document, _binary, original = parts(self.teacher_source)
        _document, _binary, refined = self.outputs[1]
        key = ("ST_Head_Skin", "M_ST_Lip")
        before = original[key]["POSITION"]
        ids, targets = geometry.mouth_rim_targets(before, original[key]["triangles"])
        self.assertEqual(len(ids), 74)
        ring = lambda points: float(np.linalg.norm(
            np.roll(points, -1, 0) - 2.0 * points + np.roll(points, 1, 0), axis=1).max())
        self.assertGreater(ring(before[ids]), .003, "the source seam is not stepped")
        self.assertLess(ring(targets), .0007, "the seam is still stepped")
        # Spread, not displaced: two millimetres, and only a partial one on average.
        move = np.abs(targets - before[ids])
        self.assertLess(float(move.max()), .002)
        self.assertGreater(float(move.max()), .0005)
        # Both sheets took the same ring, so the seam stayed welded -- the mouth is four
        # separate meshes and the lip is a tube through the face; opening it would show.
        skin = refined[("ST_Head_Skin", "M_ST_Skin")]
        lip = refined[("ST_Head_Skin", "M_ST_Lip")]
        skin_rim = hair.boundary_loop(skin["triangles"])
        lip_rim = hair.boundary_loop(lip["triangles"])
        self.assertEqual(len(skin_rim), 74)
        self.assertEqual(len(lip_rim), 74)
        pairing = np.linalg.norm(skin["POSITION"][skin_rim][:, None]
                                 - lip["POSITION"][lip_rim][None], axis=2)
        self.assertLess(float(pairing.min(1).max()), 1e-5, "the mouth seam is torn")
        # The fix is stable: re-fitting the result moves it nowhere, on the source and on
        # the shipped mesh, where simplification has already moved the ring a little.
        _loop, again = geometry.mouth_rim_targets(before, original[key]["triangles"])
        self.assertLess(float(np.abs(again - targets).max()), 1e-12)
        loop, settled = geometry.mouth_rim_targets(lip["POSITION"], lip["triangles"])
        self.assertLess(float(np.abs(settled - lip["POSITION"][loop]).max()), 5e-6)

    def test_teacher_teeth_are_tucked_behind_the_lip(self) -> None:
        """The source teeth sat a millimetre in front of the mouth, as a white bar.

        They are a flat strip between the lips; at rest they have to be behind the lip's
        front rim, or a closed mouth shows a row of teeth.
        """
        _document, _binary, _original = parts(self.teacher_source)
        _document, _binary, refined = self.outputs[1]
        teeth = refined["ST_Head_Skin", "M_ST_Teeth"]["POSITION"]
        lip = refined["ST_Head_Skin", "M_ST_Lip"]["POSITION"]
        self.assertEqual(len(teeth), 96)
        self.assertLess(float(teeth[:, 2].max()), float(lip[:, 2].max()) - .0015,
                        "the teeth still reach past the lip")
        # Tucked, not eaten: the strip keeps nearly all of its width and reach.
        self.assertGreater(float(teeth[:, 0].max()), .018)
        self.assertGreater(float(teeth[:, 2].max() - teeth[:, 2].min()), .004)
        # And it is behind the lip the whole way across, corners included -- the corners
        # are where the lip turns away and the strip used to poke through.
        for x in (-.018, -.009, 0.0, .009, .018):
            strip = float(teeth[np.abs(teeth[:, 0] - x) < .004, 2].max())
            front = float(lip[np.abs(lip[:, 0] - x) < .008, 2].max())
            self.assertLess(strip, front, "the teeth show through the lip at x=%.3f" % x)

    def test_iris_pupil_and_glint_lie_on_the_cut_sclera(self) -> None:
        doc, _binary, surfaces = self.outputs[0]
        names = {n["name"]: doc["meshes"][n["mesh"]]["name"] for n in doc["nodes"] if "mesh" in n}
        for side, suffix in [(-1, "L"), (1, "R")]:
            cut = geometry.student_eye(side)
            for role, offset in [("Iris", .00026), ("Pupil", .00052), ("Glint", .00078)]:
                material = "Eye_Glint" if role == "Glint" else role
                p = surfaces[names[f"Eye_{role}_{suffix}"], f"WIS_Protagonist_{material}"]
                x, y, z = p["POSITION"].T.astype(np.float64)
                self.assertTrue(np.all(cut.level(x, y) < .977))
                np.testing.assert_allclose(z - cut.surface(x, y), offset, atol=2e-7)
                self.assertTrue((p["NORMAL"][:, 2] > 0).all())

    def test_student_uses_one_elbow_field_across_each_overlap(self) -> None:
        d, binary, surfaces = self.outputs[0]
        binds = teacher.read_accessor(d, binary, d["skins"][0]["inverseBindMatrices"])
        binds = binds.reshape(-1, 4, 4).transpose(0, 2, 1)
        for suffix, upper, lower in [("L", 4, 5), ("R", 7, 8)]:
            for band in ("Upper", "Lower"):
                q = surfaces[f"Cardigan_{band}Sleeve_{suffix}_Mesh", "WIS_Protagonist_Cardigan"]
                local = np.c_[q["POSITION"], np.ones(len(q["POSITION"]))] @ binds[lower].T
                d_to_elbow = local[:, 1]
                np.testing.assert_array_equal(q["JOINTS_0"][:, :2], [[upper, lower]] * len(local))
                s = np.clip((d_to_elbow + .031) / .073, 0, 1)
                np.testing.assert_allclose(q["WEIGHTS_0"][:, 1], s * s * (3 - 2 * s), atol=1 / 255)
                shared = q["WEIGHTS_0"][:, 1]
                self.assertGreater(np.count_nonzero((shared > 0) & (shared < 1)), 50)

    def test_tailoring_replaces_rings_with_attached_layers(self) -> None:
        _doc, _binary, surfaces = self.outputs[1]
        knit = surfaces["ST_Cardigan", "M_ST_Cardigan"]
        blouse = surfaces["ST_Blouse", "M_ST_Blouse"]
        self.assertLess(float(knit["POSITION"][:, 1].max()), 1.362)
        for side in [-1, 1]:
            part = geometry.teacher_collar(side)
            y = part.positions[:, 1]
            self.assertLess(y.min(), 1.328)
            self.assertGreater(y.max(), 1.371)
            self.assertTrue(np.all(side * part.positions[:, 0] > 0), "collar leaves must not meet across the neck")
        leaves = geometry.join(geometry.teacher_collar(-1), geometry.teacher_collar(1))
        np.testing.assert_allclose(blouse["POSITION"][-len(leaves.positions):], leaves.positions, atol=8e-8)
        joint = blouse["JOINTS_0"][-len(leaves.positions):]
        self.assertTrue(np.all(joint[:, 0] == 1) and np.all(joint[:, 1] == 2))
        self.assertTrue(np.any(blouse["WEIGHTS_0"][-len(leaves.positions):, 1] > .5))

    def test_runtime_models_stay_within_the_existing_hard_budget(self) -> None:
        for model in [self.teacher_bytes, self.student_bytes]:
            self.assertLessEqual(len(model), 1536 * 1024)
        for (doc, _binary, surfaces), limit, revision in zip(
                self.outputs, [64604, 62340], [2, 8]):
            # Revision 3 is the teacher's resting face, expression shapes and crop;
            # revisions 6-8 re-cut the hair into the owner's short bob -- 8 keeps the
            # approved tight crop's sides and hangs a feminine full fringe, and every
            # one of them digs the buried card slivers back out. The seated student is
            # unchanged at revision 2.
            self.assertEqual(doc["asset"]["extras"]["geometry_revision"], revision)
            self.assertLess(sum(len(part["triangles"]) for part in surfaces.values()), limit)

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


    def test_teacher_lower_face_lifts_only_the_front_of_the_lower_face(self) -> None:
        # Chin tip, eye line, back of the head and the far side are fixed; the nose base
        # rises 14 mm, which is what puts the lower third in its band.
        points = np.array([[0, 1.408, -.09], [0, 1.467, -.09], [0, 1.5324, -.09],
                           [0, 1.467, .05], [.09, 1.467, -.09]])
        lifted = geometry.teacher_lower_face(points)
        self.assertAlmostEqual(float(lifted[0, 1]), 1.408, places=9)
        self.assertAlmostEqual(float(lifted[1, 1]), 1.481, places=9)
        self.assertAlmostEqual(float(lifted[2, 1]), 1.5324, places=9)
        self.assertAlmostEqual(float(lifted[3, 1]), 1.467, places=9)
        self.assertAlmostEqual(float(lifted[4, 1]), 1.467, places=9)


class QBrowContractTests(unittest.TestCase):
    """Issue #385: Q's rest brows are an authored lopsided pair; pin the numbers.

    The right arch rides 4.3-7.2 mm lower at rest, the raise deltas are themselves
    lopsided, and the mesh carries a Brow_Asymmetric morph - the asymmetry is
    authored, so symmetrizing is the one-key flattening #385 forbids. The tilt
    goes to the owner with tools/character_review/brow_report.py; until the owner
    rules, the contract pins the authored numbers so a rebuild cannot quietly
    change them.
    """

    @classmethod
    def setUpClass(cls) -> None:
        import prepare_q as q
        cls.runtime, cls.blob = q.decode(q.OUTPUT.read_bytes())
        cls.source, cls.source_blob = q.decode(q.SOURCE.read_bytes())

    def test_brows_keep_the_authored_asymmetry(self) -> None:
        head = next(m for m in self.runtime["meshes"] if m["name"] == "Q_Head")
        brow = np.asarray(accessor(self.runtime, self.blob,
                                   head["primitives"][1]["attributes"]["POSITION"]), float)
        skin = np.asarray(accessor(self.runtime, self.blob,
                                   head["primitives"][0]["attributes"]["POSITION"]), float)
        triangles = np.asarray(accessor(self.runtime, self.blob,
                                        head["primitives"][0]["indices"]), np.int64).reshape(-1, 3)
        gap = brow_seat.surface_gap(skin, triangles, brow) * 1000
        self.assertLessEqual(gap.mean(), 1.5, "brow-to-skin gap mean (mm)")
        self.assertLessEqual(gap.max(), 3.5, "brow-to-skin gap max (mm)")
        residual = brow_seat.mirror_residuals(brow) * 1000
        self.assertLessEqual(residual.max(), 9.0, "authored brow tilt (mm)")
        arch = brow_seat.arch_profile(brow)
        for band in ("inner", "mid", "outer"):
            self.assertLessEqual(abs(arch[("L", band)] - arch[("R", band)]) * 1000, 8.0,
                                 f"arch {band} authored L-R height gap (mm)")
        index = head["extras"]["targetNames"].index("Brow_Asymmetric")
        delta = np.asarray(accessor(self.runtime, self.blob,
                                    head["primitives"][1]["targets"][index]["POSITION"]), float)
        source_head = next(m for m in self.source["meshes"] if m["name"] == "Q_Head")
        before = np.asarray(accessor(self.source, self.source_blob,
                                     source_head["primitives"][1]["targets"][index]["POSITION"]), float)
        self.assertTrue(np.array_equal(delta, before), "Brow_Asymmetric delta changed")


if __name__ == "__main__":
    unittest.main(verbosity=2)
