#!/usr/bin/env python3
"""Offline source/asset contracts, not a substitute for Godot rendering tests.

Run: python3 tests/prologue_details_test.py
The existing classroom_visual_slice, imported_assets, opening_flow and dialogue_layout
engine tests cover the corresponding live scene contracts.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "art/characters"))
import build_character_looks as looks  # noqa: E402


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def block(text: str, name: str) -> str:
    match = re.search(r'^\[node name="' + re.escape(name) + r'"[^\n]*\]\n(.*?)(?=^\[|\Z)',
                      text, re.MULTILINE | re.DOTALL)
    if match is None:
        raise AssertionError(f"Missing scene node: {name}")
    return match.group(1)


def vector(text: str, property_name: str) -> tuple[float, ...]:
    match = re.search(re.escape(property_name) + r" = Vector3\(([^)]+)\)", text)
    if match is None:
        raise AssertionError(f"Missing vector: {property_name}")
    return tuple(float(value) for value in match.group(1).split(","))


def luminance(rgb: tuple[float, ...]) -> float:
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb[:3]]
    return sum(v * w for v, w in zip(linear, (0.2126, 0.7152, 0.0722)))


class PrologueDetailsTest(unittest.TestCase):
    def test_no_left_desk_and_no_dangling_pick_support(self) -> None:
        scene = read("scenes/locations/classroom/classroom.tscn")
        self.assertNotIn('name="FrontDesk"', scene)
        self.assertNotIn("Furniture/FrontDesk", scene)
        square = block(scene, "SetSquareInspect")
        self.assertIn('outline_paths = PackedStringArray("../../Props/SetSquare")', square)
        self.assertIn('support_paths = PackedStringArray("../../Stage/Lectern")', square)
        self.assertIn('inspection_id = &"classroom_set_square"', square)
        # Preserve the old interact/record ids, so saves and dialogue routes remain valid.
        self.assertIn('interact_id = &"front_desk"', block(scene, "FrontDeskInspect"))
        self.assertIn('outline_paths = PackedStringArray("../../Stage/Lectern")',
                      block(scene, "FrontDeskInspect"))

    def test_square_follows_real_lectern_surface(self) -> None:
        room = read("scenes/locations/classroom/classroom.tscn")
        lectern = read("scenes/environment/props/teacher_lectern.tscn")
        stage = vector(block(room, "Stage"), "position")
        desk = vector(block(room, "Lectern"), "position")
        square = vector(block(room, "SetSquare"), "position")
        angle = vector(block(room, "SetSquare"), "rotation_degrees")
        top_angle = vector(block(lectern, "Top"), "rotation_degrees")
        self.assertEqual(angle, top_angle)
        top = vector(block(lectern, "Top"), "position")
        self.assertAlmostEqual(square[0], stage[0] + desk[0] + top[0])
        self.assertAlmostEqual(square[2], stage[2] + desk[2] + top[2])
        # 3 mm clearance over the 30 mm top, not over its papers/register.
        self.assertAlmostEqual(square[1] - stage[1] - desk[1] - top[1], 0.018, places=4)
        for prop in ("LessonPapers", "Register"):
            self.assertLess(vector(block(lectern, prop), "position")[1], 0.5)

    def test_every_student_surface_is_painted_and_ink_is_selective(self) -> None:
        raw = (ROOT / "assets/models/protagonist/protagonist.glb").read_bytes()
        length = struct.unpack_from("<I", raw, 12)[0]
        gltf = json.loads(raw[20:20 + length])
        look = looks.TARGETS["assets/characters/classroom_student/student_look.tres"]
        surfaces = outlined = 0
        for node in gltf["nodes"]:
            if "mesh" not in node:
                continue
            for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
                material = gltf["materials"][primitive["material"]]["name"].lower()
                specific = node["name"].lower() + "/" + material
                part = look["parts"].get(specific, look["parts"].get(material))
                self.assertIsNotNone(part, specific)
                surfaces += 1
                outlined += int(part["outline"])
                if node["name"].lower().startswith(("eye", "mouth", "hand")):
                    self.assertFalse(part["outline"], specific)
        self.assertEqual(surfaces, 78)
        self.assertGreater(outlined, 0)
        self.assertLess(outlined, 10)
        wrapper = read("scenes/environment/characters/classroom_student.tscn")
        self.assertIn('start_seated = true', wrapper)
        self.assertIn('position = Vector3(0, -0.347, 0)', wrapper)
        self.assertIn('student_look.tres', wrapper)

    def test_character_resources_match_their_authored_palettes(self) -> None:
        for path, look in {**looks.TARGETS, **looks.EXPERIMENTS}.items():
            self.assertEqual(read(path), looks.render(look), path)
        for look in looks.TARGETS.values():
            self.assertLessEqual(look["outline_width"], 0.008)
            for part in look["parts"].values():
                if part["outline"]:
                    self.assertEqual(part["shade_tint"], "#9992B4")
                    self.assertEqual(part["light_tint"], "#F4DFC0")

    def test_notebook_ink_contrast_and_noninteractive_decoration(self) -> None:
        scene = read("scenes/ui/dialogue_panel.tscn")
        self.assertIn('mouse_filter = 2', block(scene, "NotebookPaper"))
        self.assertIn('visible = false', block(scene, "Wash"))
        self.assertIn('bg_color = Color(0, 0, 0, 0)', scene)
        paper = tuple(int(v, 16) / 255 for v in ("f7", "f4", "eb"))
        colors = re.findall(r'(?:font_color|default_color) = Color\(([^)]+)\)', scene)
        self.assertGreaterEqual(len(colors), 6)
        for color in colors:
            rgba = tuple(float(v) for v in color.split(","))
            ratio = (luminance(paper) + 0.05) / (luminance(rgba) + 0.05)
            self.assertGreaterEqual(ratio, 4.5, (color, ratio))
        script = read("scripts/ui/dialogue_panel.gd")
        for color in re.findall(r'const CHOICE_\w+ := Color\(([^)]+)\)', script):
            rgb = tuple(float(v) for v in color.split(","))
            self.assertGreaterEqual((luminance(paper) + 0.05) / (luminance(rgb) + 0.05), 4.5)

    def test_herbarium_cannot_obstruct_navigation(self) -> None:
        scene = read("scenes/environment/props/classroom_art/unbound_herbarium.tscn")
        self.assertNotIn("CollisionShape3D", scene)
        self.assertNotIn("StaticBody3D", scene)
        self.assertNotIn('type="Script"', scene)
        for node in re.findall(r'\[node name="([^"]+)" type="CSGPolygon3D"', scene):
            self.assertIn("use_collision = false", block(scene, node))

    def test_referenced_assets_exist(self) -> None:
        seeds = ["scenes/locations/classroom/classroom.tscn", "scenes/ui/dialogue_panel.tscn",
                 "scenes/environment/characters/classroom_student.tscn"]
        visited: set[str] = set()
        while seeds:
            path = seeds.pop()
            if path in visited:
                continue
            visited.add(path)
            text = read(path)
            for ref in re.findall(r'path="res://([^"]+)"', text):
                self.assertTrue((ROOT / ref).is_file(), f"{path}: {ref}")
                if Path(ref).suffix in (".tscn", ".tres"):
                    seeds.append(ref)


if __name__ == "__main__":
    unittest.main(verbosity=2)
