#!/usr/bin/env python3
"""Positive and negative contracts for tools/check_agent_docs.py (issue #221).

No Godot, third-party packages or network. Fixture trees prove that a missing type,
stale path, duplicate, false declaration in a string, broken link, oversized entry or
missing PR search section cannot silently look current. The real repository is checked
as well. Run with python3 tests/agent_docs_test.py.
"""

from __future__ import annotations

import contextlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import check_agent_docs as docs  # noqa: E402


def write(root: Path, relative: str, text: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def row(name: str, path: str, summary: str = "Existing owner, not a parallel implementation.") -> str:
    return f"| `{name}` | [`{path}`](../{path}) | {summary} |\n"


class AgentDocsTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = "scripts/alpha.gd"
        write(self.root, self.source, "class_name Alpha\nextends RefCounted\n")
        for relative in docs.REQUIRED_AGENT_LINKS:
            write(self.root, relative, "# Reference\n")
        write(self.root, "AGENTS.md", "# Agent instructions\n\n" + "\n".join(
            f"- [{relative}]({relative})" for relative in docs.REQUIRED_AGENT_LINKS
        ) + "\n")
        write(self.root, "README.md", "[Instructions](AGENTS.md)\n")
        write(self.root, docs.PROTOCOL, "# Mandatory protocol\n\n[Entry](../AGENTS.md)\n")
        self.write_index(row("Alpha", self.source))
        write(self.root, docs.TEMPLATE, "\n".join(
            f"## {number}. {name}\n" for number, name in enumerate(docs.PR_SECTIONS, 1)
        ) + "\n### 已检索\n\n检索关键词与实际命令\n已有模块、调用点与相关测试\n复用决定与理由\n")

    def write_index(self, rows: str) -> None:
        write(self.root, docs.INDEX,
              "# Public module index\n\n" + docs.INDEX_START + "\n\n"
              "| Public type | Source | Responsibility / reuse boundary |\n|---|---|---|\n"
              + rows + "\n" + docs.INDEX_END + "\n")

    def replace(self, relative: str, old: str, new: str) -> None:
        path = self.root / relative
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text)
        path.write_text(text.replace(old, new), encoding="utf-8")

    def assert_problem(self, message: str) -> None:
        errors = docs.check(self.root).errors
        self.assertTrue(any(message in error for error in errors), errors)

    def test_clean_tree_and_cli_pass(self) -> None:
        result = docs.check(self.root)
        self.assertEqual(result.errors, [])
        self.assertEqual((len(result.declarations), result.indexed), (1, 1))
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = docs.main(["--check", "--root", str(self.root)])
        self.assertEqual(code, 0)
        self.assertIn("AGENT_DOCS=success", out.getvalue())

    def test_scan_after_extends_with_icon_and_inline_extends(self) -> None:
        write(self.root, self.source, 'extends RefCounted\n@icon("res://icon.svg")\nclass_name Alpha\n')
        write(self.root, "some/new/folder/beta.gd", "class_name Beta extends Node # exported type\n")
        write(self.root, "scenes/room/local.gd", "class_name LocalRoom\nextends Node\n")
        self.write_index(row("Alpha", self.source)
                         + row("Beta", "some/new/folder/beta.gd")
                         + row("LocalRoom", "scenes/room/local.gd"))
        self.assertEqual(docs.check(self.root).errors, [])
        self.assertEqual(docs.public_types(self.root)[0].line, 3)

    def test_comments_and_quoted_examples_are_not_declarations(self) -> None:
        text = '\n'.join([
            '# class_name Commented',
            '## class_name Documented',
            'const SINGLE = "class_name NotAType"',
            "const MULTI = '''",
            'class_name PretendSingle',
            "'''",
            'const DOUBLE = """',
            'class_name PretendDouble',
            '# a string line, not a comment terminator',
            '"""',
            'const RAW = r"""',
            'class_name PretendRaw',
            '"""',
            r'const ESCAPED = "a \" quoted word # still a string"',
            'class_name Alpha # real declaration',
            'extends RefCounted',
            '',
        ])
        write(self.root, self.source, text)
        self.assertEqual([entry.name for entry in docs.public_types(self.root)], ["Alpha"])
        self.assertEqual(docs.check(self.root).errors, [])

    def test_new_type_missing_from_index_fails(self) -> None:
        write(self.root, "scripts/beta.gd", "class_name Beta\nextends Node\n")
        self.assert_problem("missing Beta -> scripts/beta.gd")

    def test_renamed_type_reports_missing_and_stale(self) -> None:
        write(self.root, self.source, "class_name Renamed\nextends Node\n")
        self.assert_problem("missing Renamed")
        self.assert_problem("stale type Alpha")

    def test_moved_source_path_fails(self) -> None:
        (self.root / self.source).unlink()
        write(self.root, "scripts/moved/alpha.gd", "class_name Alpha\nextends Node\n")
        self.assert_problem("Alpha source is scripts/moved/alpha.gd")

    def test_duplicate_public_declaration_fails(self) -> None:
        write(self.root, "scripts/another.gd", "class_name Alpha\nextends Node\n")
        self.assert_problem("duplicate class_name Alpha")

    def test_duplicate_index_row_fails(self) -> None:
        self.write_index(row("Alpha", self.source) * 2)
        self.assert_problem("duplicate index row for Alpha")

    def test_link_cannot_point_to_different_existing_source(self) -> None:
        write(self.root, "scripts/other.gd", "extends Node\n")
        self.replace(docs.INDEX, f"](../{self.source})", "](../scripts/other.gd)")
        self.assert_problem("Alpha link does not point to its source path")

    def test_wrong_source_label_even_with_matching_link_fails(self) -> None:
        write(self.root, "scripts/other.gd", "extends Node\n")
        self.write_index(row("Alpha", "scripts/other.gd"))
        self.assert_problem(f"Alpha source is {self.source}")

    def test_missing_source_and_empty_description_fail(self) -> None:
        self.write_index(row("Alpha", "gone.gd", "   "))
        self.assert_problem("broken local file link: ../gone.gd")
        self.assert_problem("needs a responsibility/reuse description")

    def test_malformed_row_does_not_count_as_coverage(self) -> None:
        self.replace(docs.INDEX, "| `Alpha` |", "| Alpha |")
        self.assert_problem("malformed public-type row")
        self.assert_problem("missing Alpha")

    def test_index_markers_must_be_unique_and_in_order(self) -> None:
        original = (self.root / docs.INDEX).read_text()
        for variant in (
            original.replace(docs.INDEX_START, ""),
            original + docs.INDEX_START,
            docs.INDEX_END + "\n" + docs.INDEX_START,
        ):
            with self.subTest(variant=variant):
                write(self.root, docs.INDEX, variant)
                self.assert_problem("class-name-index marker")

    def test_150_line_boundary(self) -> None:
        agents = (self.root / "AGENTS.md").read_text()
        agents += "\n" * (150 - len(agents.splitlines()))
        write(self.root, "AGENTS.md", agents)
        self.assertEqual(len(agents.splitlines()), 150)
        self.assertEqual(docs.check(self.root).errors, [])
        write(self.root, "AGENTS.md", agents + "\n")
        self.assert_problem("151 lines exceeds 150")

    def test_required_discovery_link_cannot_be_plain_prose(self) -> None:
        self.replace("AGENTS.md", f"[{docs.INDEX}]({docs.INDEX})", docs.INDEX)
        self.assert_problem(f"missing mandatory discovery link to {docs.INDEX}")

    def test_missing_protocol_and_broken_local_link_fail(self) -> None:
        (self.root / docs.PROTOCOL).unlink()
        self.assert_problem(f"{docs.PROTOCOL}: cannot read document")
        self.assert_problem(f"broken local file link: {docs.PROTOCOL}")

    def test_remote_links_and_unchecked_heading_anchors_are_not_fetched(self) -> None:
        write(self.root, "README.md", "[Web](https://example.invalid/not-fetched)\n"
              "[Heading](#not-an-anchor-check)\n[File](AGENTS.md#not-an-anchor-check)\n")
        self.assertEqual(docs.check(self.root).errors, [])

    def test_outside_repository_link_fails(self) -> None:
        self.replace("README.md", "(AGENTS.md)", "(../outside.md)")
        self.assert_problem("local link leaves the repository")

    def test_deleted_singular_entry_cannot_be_reintroduced_silently(self) -> None:
        write(self.root, "AGENT.md", "Read AGENTS.md.\n")
        self.assert_problem("AGENT.md: removed in #221")

    def test_missing_search_evidence_fields_fail(self) -> None:
        original = (self.root / docs.TEMPLATE).read_text()
        for field in ("### 已检索", "检索关键词与实际命令", "已有模块、调用点与相关测试", "复用决定与理由"):
            with self.subTest(field=field):
                write(self.root, docs.TEMPLATE, original.replace(field, ""))
                self.assert_problem("missing search-evidence field")

    def test_pr_sections_must_remain_in_order(self) -> None:
        self.replace(docs.TEMPLATE, "## 2. 变更摘要", "## 9. 变更摘要")
        self.assert_problem("all eight numbered PR sections")

    def test_git_inventory_ignores_untracked_and_engine_cache(self) -> None:
        subprocess.run(["git", "init", "-q", str(self.root)], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(self.root), "add", self.source], check=True, capture_output=True)
        write(self.root, "scratch.gd", "class_name Scratch\nextends Node\n")
        write(self.root, ".godot/cache.gd", "class_name Cached\nextends Node\n")
        self.assertEqual([entry.name for entry in docs.public_types(self.root)], ["Alpha"])
        self.assertEqual(docs.check(self.root).errors, [])
        subprocess.run(["git", "-C", str(self.root), "add", "scratch.gd"], check=True, capture_output=True)
        self.assert_problem("missing Scratch")

    def test_missing_tracked_source_is_an_error_not_an_empty_inventory(self) -> None:
        subprocess.run(["git", "init", "-q", str(self.root)], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(self.root), "add", self.source], check=True, capture_output=True)
        (self.root / self.source).unlink()
        self.assert_problem(f"{self.source}: cannot read UTF-8 source")

    def test_invalid_utf8_source_fails_visibly(self) -> None:
        (self.root / self.source).write_bytes(b"class_name Alpha\n\xff\n")
        self.assert_problem("cannot read UTF-8 source (UnicodeDecodeError)")

    def test_cli_failure_and_list_inventory(self) -> None:
        self.write_index("")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = docs.main(["--check", "--root", str(self.root)])
        self.assertEqual(code, 1)
        self.assertIn("AGENT_DOCS=failure", out.getvalue())
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = docs.main(["--list", "--root", str(self.root)])
        self.assertEqual(code, 0)
        self.assertIn(f"Alpha\t{self.source}:1", out.getvalue())

    def test_this_repository_has_complete_discovery_contracts(self) -> None:
        result = docs.check(docs.ROOT)
        self.assertEqual(result.errors, [])
        self.assertEqual(len(result.declarations), result.indexed)
        names = {entry.name for entry in result.declarations}
        self.assertTrue({"MenuStyle", "UiTextScale", "CameraShot", "CameraFocusDirector"} <= names)
        self.assertNotIn("TestHarness", names)  # it must stay a local preload alias
        index = (docs.ROOT / docs.INDEX).read_text()
        self.assertIn("../tests/test_harness.gd", index)
        self.assertIn("../addons/narrative_editor/README.md", index)
        protocol = (docs.ROOT / docs.PROTOCOL).read_text()
        self.assertIn("~~~markdown\n### 工作进展\n", protocol)
        self.assertIn("Agents must not merge their own PR", protocol)


if __name__ == "__main__":
    unittest.main(verbosity=2)
