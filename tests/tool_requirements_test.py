#!/usr/bin/env python3
"""Keep Python maintenance imports, version guards and installed pins in sync (#227).

Run with the interpreter from the documented fresh virtual environment. This checks
Python dependencies, not the compiler/libc/WebP toolchain or a shipped game runtime.
"""

from __future__ import annotations

import ast
import importlib.metadata
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check_test_registration import workflow_runs
from godot_sidecars import tracked_files

PIN = re.compile(r"([A-Za-z_0-9.-]+)(?:\[[A-Za-z_0-9,.-]+\])?==([A-Za-z_0-9.+-]+)")
IMPORT_DISTRIBUTIONS = {"PIL": "Pillow", "fontTools": "fonttools", "yaml": "PyYAML"}
# Blender supplies these two APIs in its embedded interpreter, not in the tools
# venv. Only the explicitly Blender-invoked source driver may use them.
BLENDER_DRIVERS = {"art/character_models/teacher_b/make_blender_source.py"}
BLENDER_MODULES = {"bpy", "mathutils"}


def normalized(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def pins_from(text: str) -> dict[str, str]:
    result = {}
    for line in text.splitlines():
        value = line.split("#", 1)[0].strip()
        if not value:
            continue
        match = PIN.fullmatch(value)
        if not match or "*" in value:
            raise ValueError(f"Expected an exact package==version pin: {value}")
        name, version = normalized(match[1]), match[2]
        if name in result:
            raise ValueError(f"Duplicate dependency: {name}")
        result[name] = version
    return result


def constant(relative: str, name: str) -> str:
    tree = ast.parse((ROOT / relative).read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == name
                                                for target in node.targets):
            return ast.literal_eval(node.value)
    raise ValueError(f"{relative}: missing version guard {name}")


class ToolRequirementsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.pins = pins_from((ROOT / "tools/requirements.txt").read_text(encoding="utf-8"))
        cls.inventory = set(tracked_files(str(ROOT)))

    def test_manifest_parser_rejects_unpinned_duplicate_or_wildcard(self) -> None:
        for value in ("numpy", "numpy>=2", "numpy==2.*", "numpy==2.2.6\nNumPy==2.2.6", "-r other.txt"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                pins_from(value)
        self.assertEqual(pins_from("# comment\nPillow==11.3.0\nlark[regex]==1.2.2 # extra\n"),
                         {"pillow": "11.3.0", "lark": "1.2.2"})

    def test_documented_direct_dependencies_are_present(self) -> None:
        self.assertLessEqual({"gdtoolkit", "fonttools", "pyyaml", "numpy", "pillow", "meshoptimizer"},
                             self.pins.keys())

    def test_clean_environment_has_every_declared_version(self) -> None:
        for name, version in self.pins.items():
            with self.subTest(package=name):
                self.assertEqual(importlib.metadata.version(name), version,
                                 "Install tools/requirements.txt in the documented fresh venv")

    def test_all_maintenance_third_party_imports_are_declared(self) -> None:
        # Scene-local art generators are maintenance tools too. Audit their imports
        # and recognize them as local modules when a tool reuses their code.
        files = [relative for relative in self.inventory if relative.endswith(".py")
                 and relative.startswith(("tools/", "art/", "scenes/"))]
        local_modules = {Path(relative).stem for relative in files}
        # Platform tools also reuse first-party modules via qualified paths under
        # tools/. Match the whole path against tracked files, not a namespace prefix.
        qualified_tools = {relative.removeprefix("tools/").removesuffix(".py").replace("/", ".")
                           for relative in files if relative.startswith("tools/")}
        for relative in sorted(files):
            tree = ast.parse((ROOT / relative).read_text(encoding="utf-8"))
            imports = set()
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    imports.update(alias.name for alias in node.names)
                elif isinstance(node, ast.ImportFrom) and not node.level and node.module:
                    imports.add(node.module)
            for qualified in sorted(imports - qualified_tools):
                module = qualified.split(".", 1)[0]
                if module in sys.stdlib_module_names or module in local_modules:
                    continue
                if relative in BLENDER_DRIVERS and qualified in BLENDER_MODULES:
                    continue
                with self.subTest(path=relative, module=qualified):
                    distribution = normalized(IMPORT_DISTRIBUTIONS.get(module, module))
                    self.assertIn(distribution, self.pins,
                                  "Declare new third-party imports and map nonmatching distribution names")

    def test_font_and_native_asset_guards_match_the_manifest(self) -> None:
        self.assertEqual(constant("tools/subset_font.py", "PINNED_FONTTOOLS"), self.pins["fonttools"])
        self.assertEqual(constant("tools/prepare_teacher_n.py", "MESHOPTIMIZER_VERSION"),
                         self.pins["meshoptimizer"])

    def test_existing_ci_inline_pins_do_not_drift(self) -> None:
        # Keep the old, narrow CI venvs intact while another PR owns those workflows.
        # The new tooling workflow installs the manifest. If either side changes a
        # parser/font pin, this catches the disagreement instead of silently upgrading.
        seen = set()
        for origin, text in workflow_runs(ROOT, self.inventory):
            for name, version in re.findall(r"\b(gdtoolkit|fonttools)==([0-9A-Za-z.+-]+)", text):
                with self.subTest(origin=origin, package=name):
                    self.assertEqual(version, self.pins[normalized(name)])
                    seen.add(normalized(name))
        self.assertEqual(seen, {"gdtoolkit", "fonttools"})

    def test_recorded_classroom_paint_versions_are_preserved(self) -> None:
        for relative in ("art/classroom/README.md", "art/classroom/README.zh-CN.md"):
            text = (ROOT / relative).read_text(encoding="utf-8")
            with self.subTest(path=relative):
                self.assertRegex(text, r"Pillow\s+" + re.escape(self.pins["pillow"]))
                self.assertRegex(text, r"NumPy\s+" + re.escape(self.pins["numpy"]))


if __name__ == "__main__":
    unittest.main()
