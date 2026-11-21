#!/usr/bin/env python3
"""Sculpt the yard resident as a painted, jointed native scene (no imported textures).

The measured ring profiles are the editable source. Each moving panel has one
RGBA8-painted surface, so sleeves, face and repairs add no material passes.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

from dressing_geometry import face_out
from fixture_geometry import Facets
from build_playground_art import vec3


OUTPUT = Path(__file__).resolve().parents[1] / "scenes/environment/characters/roof_collector.tscn"
MOTION = "res://scenes/environment/characters/roof_collector_pose.gd"

OLIVE = (108, 118, 78)
MOSS = (79, 93, 68)
TWILL = (136, 133, 91)
YOKE = (172, 125, 64)
SHIRT = (55, 75, 79)
ZIP = (204, 184, 134)
PANTS = (75, 82, 93)
DARN = (123, 124, 117)
LEATHER = (63, 47, 42)
SOLE = (39, 42, 45)
SKIN = (179, 127, 102)
CHEEK = (203, 145, 116)
HAIR = (66, 61, 58)
SILVER = (152, 143, 126)
LIPS = (113, 70, 61)


class Painted(Facets):
    """One draw per joint; facet pigments are data, not runtime overrides."""

    def __init__(self):
        super().__init__()
        self.colors = bytearray()
        self.ink = OLIVE

    def face(self, *points):
        super().face(*points)
        self.colors.extend(bytes((*self.ink, 255)) * len(points))

    def surface(self):
        return super().surface(bytes(self.colors))

    def patch(self, color, points, away=(0, 0, 0.6)):
        self.ink = color
        face_out(self, points, away)

    def loft(self, profile, pigments, *, sides=8):
        # (height, half-width, half-depth, depth-centre[, x-centre]); local front is -Z.
        rings = []
        for y, rx, rz, z, *x in profile:
            rings.append([((x[0] if x else 0) + rx * math.cos(a), y, z + rz * math.sin(a))
                          for a in (math.tau * i / sides for i in range(sides))])
        for j, (lo, hi) in enumerate(zip(rings, rings[1:])):
            palette = pigments[j] if isinstance(pigments, list) else pigments
            for i in range(sides):
                k = (i + 1) % sides
                if isinstance(palette[0], tuple):
                    self.ink = palette[i % len(palette)]
                else:
                    self.ink = palette
                self.face(lo[i], lo[k], hi[k], hi[i])
        self.face(*reversed(rings[0]))
        self.face(*rings[-1])
        return self


def jacket():
    m = Painted().loft([
        (-0.11, .144, .097, .006), (-.054, .174, .112, .015), (.119, .158, .108, .017),
        (.311, .204, .124, .007), (.46, .228, .104, -.003), (.52, .135, .087, -.019),
        (.545, .075, .059, -.013),
    ], [MOSS, OLIVE, (OLIVE, MOSS, MOSS, OLIVE, OLIVE, TWILL, OLIVE, TWILL), OLIVE, TWILL, SHIRT])
    m.loft([(.514, .059, .053, -.015), (.605, .051, .047, -.018)], SKIN)
    # The open top of the work jacket, overlapping collar, repaired pocket and zip.
    m.patch(SHIRT, [(-.065, .49, -.091), (.069, .49, -.091), (.023, .275, -.124), (-.02, .275, -.124)])
    m.patch(MOSS, [(-.137, .483, -.091), (-.057, .515, -.105), (-.02, .287, -.132), (-.104, .347, -.118)])
    m.patch(TWILL, [(.057, .522, -.102), (.145, .469, -.095), (.102, .383, -.118), (.02, .283, -.132)])
    m.patch(ZIP, [(-.007, -.046, -.11), (.005, -.046, -.11), (.017, .278, -.128), (.006, .279, -.128)])
    m.patch(YOKE, [(.071, .211, -.11), (.147, .224, -.099), (.151, .308, -.089), (.066, .302, -.117)])
    m.patch(TWILL, [(.071, .281, -.118), (.148, .281, -.096), (.152, .312, -.094), (.066, .312, -.118)])
    m.patch(DARN, [(-.17, .095, -.028), (-.126, .075, -.083), (-.117, .181, -.10), (-.157, .185, -.06)])
    return m


def head():
    m = Painted().loft([
        (.012, .061, .055, -.007), (.047, .082, .080, -.019), (.108, .113, .091, -.013),
        (.168, .113, .106, .006), (.221, .117, .105, .008), (.27, .10, .093, .011),
        (.306, .053, .052, .014),
    ], [(SKIN, LIPS, SKIN, CHEEK), (SKIN, CHEEK, SKIN, SKIN), SKIN, CHEEK, SKIN, HAIR], sides=12)
    # Sweep of hair: a higher corner on one side and two cool temple planes.
    m.loft([(.205, .114, .105, .016), (.251, .118, .105, .012), (.30, .087, .076, .018, -.01),
            (.324, .035, .038, .016, -.024)],
           [(SILVER, HAIR, HAIR, HAIR, SILVER, HAIR), HAIR, HAIR], sides=10)
    for side in (-1, 1):
        m.loft([(.109, .014, .013, .011, side*.115), (.155, .02, .022, .009, side*.117),
                (.177, .012, .014, .007, side*.111)], SKIN, sides=6)
        x = side * .049
        m.patch(LIPS, [(x-.034, .167, -.092), (x+.032, .17, -.095),
                       (x+.026, .181, -.097), (x-.028, .179, -.096)])
        m.patch(HAIR, [(x-.031, .197, -.096), (x+.03, .202, -.094),
                       (x+.031, .211, -.095), (x-.027, .207, -.098)])
    m.loft([(.105, .021, .016, -.097), (.125, .028, .041, -.101),
            (.147, .024, .035, -.105), (.198, .013, .009, -.102)], CHEEK, sides=6)
    m.patch(LIPS, [(-.037, .080, -.102), (.028, .078, -.104), (.039, .089, -.103), (-.032, .090, -.108)])
    m.patch(SILVER, [(-.064, .052, -.081), (.054, .049, -.082), (.048, .066, -.095), (-.05, .064, -.089)])
    return m


def upper_arm(patched):
    m = Painted().loft([
        (-.268, .059, .063, -.005), (-.206, .070, .072, .012),
        (-.061, .092, .086, .003), (.027, .077, .069, 0), (.067, .044, .041, .006),
    ], [MOSS, OLIVE, TWILL, OLIVE], sides=8)
    if patched:
        m.patch(YOKE, [(.006, -.198, -.067), (.047, -.177, -.056),
                       (.057, -.09, -.060), (.012, -.101, -.086)])
    return m


def lower_arm():
    m = Painted().loft([
        (-.21, .052, .048, -.012), (-.178, .059, .054, -.006), (-.056, .068, .067, .004),
        (.032, .056, .059, .008),
    ], [TWILL, OLIVE, MOSS], sides=8)
    m.loft([(-.326, .031, .027, -.024), (-.29, .041, .039, -.012),
            (-.213, .034, .037, -.01), (-.18, .038, .04, -.008)], SKIN, sides=8)
    m.loft([(-.281, .014, .016, -.047, .026), (-.249, .019, .019, -.033, .028)], CHEEK, sides=6)
    return m


def thigh():
    return Painted().loft([
        (-.46, .077, .078, -.009), (-.323, .087, .079, -.004),
        (-.153, .106, .097, 0), (-.018, .109, .093, .012), (.051, .1, .085, .014),
    ], [PANTS, (PANTS, PANTS, PANTS, PANTS, PANTS, DARN, PANTS, PANTS), PANTS, PANTS])


def shin(darned):
    m = Painted().loft([
        (-.353, .057, .063, -.009), (-.30, .064, .067, .001), (-.095, .073, .075, .016),
        (-.01, .083, .083, .004), (.041, .07, .071, -.003),
    ], [(57, 67, 76), PANTS, PANTS, PANTS])
    if darned:
        m.patch(DARN, [(-.033, -.123, -.066), (.043, -.12, -.061),
                       (.041, .013, -.072), (-.035, .008, -.078)])
    return m


def boot():
    return Painted().loft([
        (-.082, .066, .128, -.048), (-.055, .07, .137, -.049),
        (-.012, .066, .127, -.047), (.032, .055, .083, -.01), (.074, .056, .066, .006),
    ], [SOLE, LEATHER, ((118, 90, 70), LEATHER, LEATHER, LEATHER), LEATHER])


def scene():
    meshes, nodes = [], []

    def joint(name, parent, at, mesh=None, key=None):
        nodes.append(f'[node name="{name}" type="Node3D" parent="{parent}"]\nposition = {vec3(at)}\n')
        path = name if parent == "." else f"{parent}/{name}"
        if mesh is not None:
            resource = key or name
            if not any(existing.startswith(f'[sub_resource type="ArrayMesh" id="{resource}"]') for existing in meshes):
                meshes.append(f'[sub_resource type="ArrayMesh" id="{resource}"]\n_surfaces = {mesh.surface()}\n')
            nodes.append(f'[node name="Pigment" type="MeshInstance3D" parent="{path}"]\n'
                         f'mesh = SubResource("{resource}")\nmaterial_override = SubResource("ClothAndSkin")\n')
        return path

    hip = joint("Hip", ".", (0, .872, 0))
    trunk = joint("Trunk", hip, (0, 0, 0), jacket())
    joint("Head", trunk, (0, .548, -.016), head())
    lower, upper_leg, shoe = lower_arm(), thigh(), boot()
    for tag, side in (("L", -1), ("R", 1)):
        arm = joint("Arm" + tag, trunk, (side*.217, .434 if side < 0 else .421, .01), upper_arm(side > 0))
        joint("Elbow", arm, (side*.035, -.234, .007), lower, "Forearm")
        leg = joint("Thigh" + tag, hip, (side*.103, 0, .012), upper_leg, "Trousers")
        ankle = joint("Shin", leg, (0, -.445, 0), shin(side < 0), "Shin" + tag)
        joint("Boot", ankle, (0, -.345, 0), shoe, "Shoe")
    header = f'''[gd_scene load_steps={len(meshes) + 3} format=3]

[ext_resource type="Script" path="{MOTION}" id="pose"]

[sub_resource type="StandardMaterial3D" id="ClothAndSkin"]
vertex_color_use_as_albedo = true
vertex_color_is_srgb = true
roughness = 0.96
'''
    root = '[node name="RoofCollector" type="Node3D"]\nscript = ExtResource("pose")\n'
    return '\n'.join([header, *meshes, root, *nodes])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = scene()
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_text() != text:
            parser.error("roof_collector.tscn is stale; run tools/build_roof_collector.py")
    else:
        OUTPUT.write_text(text)
    print(f"Painted collector: {len(text):,} bytes of scene source; no imported images.")


if __name__ == "__main__":
    main()
