#!/usr/bin/env python3
"""Keep returned story documents inside their existing bilingual chapter files.

All input and JSON below are synthetic. Tests patch ROOT/DATA to a temporary fake
project; real author text is never copied or written. Run with:
    python3 tests/story_doc_paths_test.py
"""

from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import story_doc as sd  # noqa: E402


class StoryDocPathsTest(unittest.TestCase):
    def setUp(self) -> None:
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.scratch = Path(scratch.name)
        self.root = self.scratch / "project"
        self.data = self.root / "data"
        roots = patch.multiple(sd, ROOT=self.root, DATA=self.data)
        roots.start()
        self.addCleanup(roots.stop)
        self.put(self.data / "locale" / "zh-CN.json", {"strings": {}})
        self.put(self.data / "abilities" / "abilities.json", {"abilities": {}})
        self.put(self.data / "abilities" / "zh-CN.json", {"abilities": {}})
        self.names = sd.Names()
        for locale in (sd.MASTER, sd.MIRROR):
            for kind in ("dialogue", "inspections"):
                self.put(self.target(kind, locale), self.table(kind, locale))
        self.outside = self.scratch / "outside.json"
        self.put(self.outside, self.table("inspections", sd.MASTER))

    @staticmethod
    def put(path: Path, data: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(sd.dump_json(data), encoding="utf-8")

    @staticmethod
    def table(kind: str, locale: str) -> dict:
        table = {"format_version": 1, "locale": locale}
        if kind == "dialogue":
            table["conversations"] = {
                "fixture_conv": {"start": "first", "nodes": [
                    {"id": "first", "speaker": "protagonist", "text": "fixture-before", "next": None},
                ]},
            }
        else:
            table["fixture_item"] = {"text": "fixture-before"}
        return table

    def target(self, kind: str, locale: str, chapter: str = "fixture") -> Path:
        return self.data / kind / locale / f"{chapter}.json"

    @staticmethod
    def document(kind: str, chapter: str = "fixture") -> list[str]:
        if kind == "dialogue":
            return [f"◆ 对话 {chapter}", "■ 会话 fixture_conv", "属性：起点 first",
                    "[first] 旁白：fixture-after", "下一句：结束"]
        return ["◆ 检视", f"▣ 章节 {chapter}", "■ 检视 fixture_item", "首次：fixture-after"]

    def snapshot(self) -> dict[str, bytes]:
        return {path.relative_to(self.scratch).as_posix(): path.read_bytes()
                for path in self.scratch.rglob("*") if not path.is_symlink() and path.is_file()}

    def assert_refused(self, lines: list[str], *, write: bool = True) -> None:
        before = self.snapshot()
        try:
            with self.assertRaises(sd.DocError) as caught:
                sd.apply_document(lines, self.names, write=write)
            self.assertIn("章节", str(caught.exception))
        finally:
            self.assertEqual(self.snapshot(), before, "a refused import changed or created a file")

    def test_inspection_parent_traversal_is_refused_without_overwriting_outside(self) -> None:
        for write in (False, True):
            with self.subTest(write=write):
                self.assert_refused(self.document("inspections", "../../../../outside"), write=write)

    def test_dialogue_parent_traversal_is_refused_before_reading_outside(self) -> None:
        self.put(self.outside, self.table("dialogue", sd.MASTER))
        for write in (False, True):
            with self.subTest(write=write), patch.object(sd, "load_json", side_effect=AssertionError("unsafe read")):
                self.assert_refused(self.document("dialogue", "../../../../outside"), write=write)

    def test_non_ids_and_cross_platform_paths_are_refused(self) -> None:
        invalid = ("../fixture", "sub/fixture", r"..\fixture", r"sub\fixture",
                   "C:fixture", r"C:\fixture", r"\\server\share\fixture", ".", "..", "Fixture")
        for kind in ("dialogue", "inspections"):
            for chapter in (*invalid, str(self.outside.with_suffix(""))):
                with self.subTest(kind=kind, chapter=chapter):
                    self.assert_refused(self.document(kind, chapter))

    def test_unknown_chapter_is_refused_for_both_document_kinds(self) -> None:
        for kind in ("dialogue", "inspections"):
            with self.subTest(kind=kind):
                self.assert_refused(self.document(kind, "unknown_chapter"))

    def test_later_invalid_chapter_does_not_write_earlier_valid_chapter(self) -> None:
        for chapter in ("unknown_chapter", "../../../../outside"):
            for write in (False, True):
                with self.subTest(chapter=chapter, write=write):
                    lines = self.document("inspections") + self.document("inspections", chapter)[1:]
                    self.assert_refused(lines, write=write)

    def test_master_and_mirror_file_symlinks_are_refused_before_content_reads(self) -> None:
        for kind in ("dialogue", "inspections"):
            for locale in (sd.MASTER, sd.MIRROR):
                with self.subTest(kind=kind, locale=locale):
                    target = self.target(kind, locale)
                    before = target.read_bytes()
                    target.unlink()
                    self.put(self.outside, self.table(kind, locale))
                    target.symlink_to(self.outside)
                    try:
                        with patch.object(sd, "load_json", side_effect=AssertionError("unsafe read")):
                            self.assert_refused(self.document(kind))
                    finally:
                        target.unlink()
                        target.write_bytes(before)

    def test_parent_directory_symlinks_are_refused(self) -> None:
        for relative in ("data", "data/inspections", "data/inspections/zh-CN", "data/inspections/en"):
            with self.subTest(directory=relative):
                target = self.root / relative
                redirected = self.scratch / "redirected"
                target.rename(redirected)
                target.symlink_to(redirected, target_is_directory=True)
                try:
                    self.assert_refused(self.document("inspections"))
                finally:
                    target.unlink()
                    redirected.rename(target)

    def test_dangling_and_looping_symlinks_are_refused(self) -> None:
        target = self.target("inspections", sd.MIRROR)
        before = target.read_bytes()
        for link in (self.scratch / "missing.json", target):
            with self.subTest(loop=link == target):
                target.unlink()
                target.symlink_to(link)
                try:
                    self.assert_refused(self.document("inspections"))
                finally:
                    target.unlink()
                    target.write_bytes(before)

    def test_existing_in_locale_alias_cannot_overwrite_another_chapter(self) -> None:
        target = self.target("inspections", sd.MASTER)
        other = self.target("inspections", sd.MASTER, "other")
        shutil.copyfile(target, other)
        target.unlink()
        target.symlink_to(other)
        self.assert_refused(self.document("inspections"))

    def test_later_linked_mirror_does_not_write_earlier_valid_chapter(self) -> None:
        self.put(self.target("inspections", sd.MASTER, "other"), self.table("inspections", sd.MASTER))
        linked = self.target("inspections", sd.MIRROR, "other")
        linked.symlink_to(self.outside)
        lines = self.document("inspections") + self.document("inspections", "other")[1:]
        self.assert_refused(lines)

    def test_resolution_errors_are_reported_as_document_errors(self) -> None:
        with patch.object(Path, "resolve", side_effect=OSError("fixture-resolution-error")):
            self.assert_refused(self.document("inspections"))

    def test_checkout_root_may_be_reached_through_a_symlink(self) -> None:
        alias = self.scratch / "checkout"
        alias.symlink_to(self.root, target_is_directory=True)
        before = self.snapshot()
        with patch.multiple(sd, ROOT=alias, DATA=alias / "data"):
            result = sd.apply_document(self.document("inspections"), self.names, write=False)
        self.assertTrue(result["changed"])
        self.assertEqual(self.snapshot(), before)

    def test_dry_run_of_known_chapters_does_not_write(self) -> None:
        for kind in ("dialogue", "inspections"):
            with self.subTest(kind=kind):
                before = self.snapshot()
                summary = sd.apply_document(self.document(kind), self.names, write=False)
                self.assertEqual(summary["changed"], [str(self.target(kind, sd.MASTER).relative_to(self.root))])
                self.assertEqual(self.snapshot(), before)

    def test_known_chapters_write_only_the_authorized_file_and_keep_english(self) -> None:
        for kind in ("dialogue", "inspections"):
            with self.subTest(kind=kind):
                before = self.snapshot()
                english = self.target(kind, sd.MIRROR).read_bytes()
                summary = sd.apply_document(self.document(kind), self.names, write=True)
                master = str(self.target(kind, sd.MASTER).relative_to(self.root))
                self.assertEqual(summary["changed"], [master])
                self.assertTrue(summary["pending_en"])
                self.assertEqual(self.target(kind, sd.MIRROR).read_bytes(), english)
                after = self.snapshot()
                changed = [name for name, content in after.items() if before.get(name) != content]
                relative = self.target(kind, sd.MASTER).relative_to(self.scratch).as_posix()
                self.assertEqual(changed, [relative])
                self.assertEqual(sd.apply_document(self.document(kind), self.names, write=True)["changed"], [])

    def test_missing_mirror_file_can_be_created_for_existing_master(self) -> None:
        for kind in ("dialogue", "inspections"):
            with self.subTest(kind=kind):
                target = self.target(kind, sd.MIRROR)
                target.unlink()
                summary = sd.apply_document(self.document(kind), self.names, write=True)
                self.assertIn(str(target.relative_to(self.root)), summary["changed"])
                self.assertEqual(sd.load_json(target)["locale"], sd.MIRROR)


if __name__ == "__main__":
    unittest.main()
