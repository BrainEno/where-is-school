#!/usr/bin/env python3
"""Exercise the content gate with invented data, never with author text fixtures."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "tools/check_content_placeholders.py"
ALLOWLIST = "tools/content_placeholder_allowlist.json"
DIALOGUE = "data/dialogue/en/example.json"
FIELD = "/conversations/fixture/nodes/@intro/choices/@try/text"
DRAFT = "TODO: synthetic sentence for this test"


class ContentPlaceholdersTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.write_json(ALLOWLIST, {"format_version": 1, "groups": []})

    def write(self, relative: str, content: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def write_json(self, relative: str, document: object) -> None:
        self.write(relative, json.dumps(document, ensure_ascii=False))

    def dialogue(self, text: str = DRAFT, *, extra_nodes: tuple[dict, ...] = ()) -> None:
        self.write_json(DIALOGUE, {"conversations": {"fixture": {"nodes": [
            *extra_nodes, {"id": "intro", "choices": [{"id": "try", "text": text}]},
        ]}}})

    def group(self, *, reason: str = "Synthetic test debt", issue: int = 1) -> dict:
        return {"issue": issue, "reason": reason, "files": {
            DIALOGUE: {FIELD: hashlib.sha256(DRAFT.encode()).hexdigest()},
        }}

    def acknowledge_draft(self) -> None:
        self.write_json(ALLOWLIST, {"format_version": 1, "groups": [self.group()]})

    def audit(self, *options: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(TOOL), "--root", str(self.root), *options],
            check=False, capture_output=True, encoding="utf-8",
        )

    def test_readable_content_passes_both_modes(self) -> None:
        self.dialogue("A finished test line.")
        for options in ((), ("--release",)):
            with self.subTest(options=options):
                run = self.audit(*options)
                self.assertEqual(run.returncode, 0, run.stderr)
                self.assertIn("1 JSON files checked; 0 recorded placeholder field(s)", run.stdout)

    def test_finds_markers_in_each_player_text_family_without_logging_passages(self) -> None:
        self.dialogue()
        self.write_json("data/inspections/zh-CN/example.json", {
            "desk": {"text": "待做：fixture", "repeat_text": "wip · fixture", "recall_text": "TBD"},
        })
        self.write_json("data/abilities/en.json", {"abilities": {"spare": {"description": "fixme!"}}})
        self.write_json("data/locale/en.json", {"strings": {"menu/example": "[TBD]"}})
        self.write_json("data/story/fixture.json", {"title": "Title: TODO"})
        run = self.audit()
        self.assertEqual(run.returncode, 1, run.stderr)
        for site in (
            DIALOGUE + "#" + FIELD, "/desk/text [待做]", "/desk/repeat_text [WIP]", "/desk/recall_text [TBD]",
            "/abilities/spare/description [FIXME]", "/strings/menu~1example [TBD]", "/title [TODO]",
        ):
            self.assertIn(site, run.stdout)
        self.assertIn("7 new or changed field(s)", run.stdout)
        self.assertNotIn(DRAFT, run.stdout)
        self.assertNotIn("Title: TODO", run.stdout)

    def test_effect_records_keep_their_entry_id_anchor(self) -> None:
        self.write_json(DIALOGUE, {"nodes": [{"id": "test", "effects": [
            {"type": "set_flag", "flag": "TODO", "value": True},
            {"type": "remember", "entry_id": "first~second/third", "text": DRAFT},
        ]}]})
        run = self.audit()
        self.assertEqual(run.returncode, 1, run.stderr)
        self.assertIn("/nodes/@test/effects/@first~0second~1third/text [TODO]", run.stdout)
        self.assertIn("1 new or changed field(s)", run.stdout)

    def test_ignores_ids_editor_notes_and_tokens_inside_words(self) -> None:
        self.write_json(DIALOGUE, {"conversations": {"text": {"nodes": [{
            "id": "TODO", "editor_note": "FIXME", "next": "TBD",
            "text": "Neither WIPER nor TODOISH nor some_FIXME_label is a marker.",
        }]}}, "_comment": "待做"})
        self.write_json("data/story/locations.json", {"locations": {"fixture": {"objective": "TODO"}}})
        self.write_json("docs/author_fixture.json", {"text": DRAFT})
        run = self.audit("--release")
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_exact_allowance_survives_inserting_a_node_but_cannot_cover_its_copy(self) -> None:
        self.acknowledge_draft()
        self.dialogue(extra_nodes=({"id": "inserted", "text": "Readable."},))
        run = self.audit()
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("1 recorded placeholder field(s)", run.stdout)
        self.dialogue(extra_nodes=({"id": "copy", "choices": [{"id": "try", "text": DRAFT}]},))
        run = self.audit()
        self.assertEqual(run.returncode, 1, run.stderr)
        self.assertIn("/nodes/@copy/choices/@try/text", run.stdout)
        self.assertNotIn(FIELD, run.stdout)

    def test_rewording_an_acknowledged_placeholder_fails(self) -> None:
        self.acknowledge_draft()
        self.dialogue("FIXME: a different draft at the exact same field")
        run = self.audit()
        self.assertEqual(run.returncode, 1, run.stderr)
        self.assertIn(FIELD + " [FIXME]; recorded text changed (issue #1)", run.stdout)

    def test_obsolete_allowance_must_be_removed_in_the_same_change(self) -> None:
        self.acknowledge_draft()
        self.dialogue("Final fixture text.")
        run = self.audit()
        self.assertEqual(run.returncode, 1, run.stderr)
        self.assertIn("CONTENT_PLACEHOLDER_STALE: " + DIALOGUE + "#" + FIELD, run.stdout)
        self.assertIn("0 new or changed field(s), 1 stale allowance(s)", run.stdout)
        # Release scans the text itself, never the development allowlist.
        self.assertEqual(self.audit("--release").returncode, 0)
        self.write_json(ALLOWLIST, {"format_version": 1, "groups": []})
        self.assertEqual(self.audit().returncode, 0)

    def test_tagged_release_refuses_even_the_exact_acknowledged_text(self) -> None:
        self.dialogue()
        self.acknowledge_draft()
        self.assertEqual(self.audit().returncode, 0)
        run = self.audit("--release")
        self.assertEqual(run.returncode, 1, run.stderr)
        self.assertIn("CONTENT_PLACEHOLDERS_RELEASE_BLOCKED: 1 placeholder field(s)", run.stdout)
        self.assertIn(DIALOGUE + "#" + FIELD, run.stdout)

    def test_invalid_allowance_cannot_swallow_debt(self) -> None:
        self.dialogue()
        for groups in ([self.group(reason=" ")], [self.group(issue=0)], [self.group(), self.group(issue=2)],
                       [{"issue": 1, "reason": "Fixture", "files": {DIALOGUE: {FIELD: "*"}}}]):
            with self.subTest(groups=groups):
                self.write_json(ALLOWLIST, {"format_version": 1, "groups": groups})
                run = self.audit()
                self.assertEqual(run.returncode, 2, run.stdout)
                self.assertIn(ALLOWLIST, run.stderr)

    def test_invalid_or_ambiguous_json_fails_in_both_modes(self) -> None:
        for broken in ('{"text": "TODO"', '{"text": "TODO", "text": "hidden"}', '"not a table"'):
            self.write(DIALOGUE, broken)
            for options in ((), ("--release",)):
                with self.subTest(broken=broken, options=options):
                    run = self.audit(*options)
                    self.assertEqual(run.returncode, 2, run.stdout)
                    self.assertIn(DIALOGUE, run.stderr)

    def test_empty_source_tree_is_an_audit_error(self) -> None:
        for options in ((), ("--release",)):
            run = self.audit(*options)
            self.assertEqual(run.returncode, 2, run.stdout)
            self.assertIn("expected source JSON files", run.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
