"""The separate author project can only be produced by explicit staging."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import authoring_build as author
import export_mobile as mobile
import export_presets
from macos.ios.sign_ipa import export_options, profile_details
from review_author_draft import preserve_source_values
from subset_font import collect_characters
from verify_build import verify_contents


class AuthoringToolsTest(unittest.TestCase):
    def test_author_selection_is_exact_and_never_added_to_the_normal_project(self):
        candidates = ["project.godot", *sorted(author.SCRIPTS), "scripts/dev/stray.gd", "scenes/dev/preview.tscn",
                      "tools/macos/ios/authoring/FilesBridge.gdip", "ios/plugins/stray.gdip"]
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source = work / "source"
            for name in candidates:
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text((ROOT / name).read_text() if name == "project.godot" else "fixture")
            with patch.object(mobile, "ROOT", source), patch.object(mobile, "run", return_value="\0".join(candidates)):
                mobile.stage(work / "retail")
                mobile.stage(work / "author", authoring=True)
            self.assertEqual({p.relative_to(work / "retail").as_posix() for p in (work / "retail").rglob("*") if p.is_file()},
                             {"project.godot"})
            self.assertEqual({p.relative_to(work / "author").as_posix() for p in (work / "author").rglob("*") if p.is_file()},
                             {"project.godot", *author.SCRIPTS})
            author.configure_project(work / "author", "abc")
            retail = mobile.project_settings(work / "retail/project.godot")
            authored = mobile.project_settings(work / "author/project.godot")
            self.assertNotIn("autoload/Authoring", retail)
            self.assertEqual(authored["autoload/Authoring"], json.dumps("*res://" + author.BOOTSTRAP))
            self.assertNotEqual(retail["application/config/name"], authored["application/config/name"])
            self.assertEqual(authored["authoring/base_commit"], '"abc"')
            self.assertTrue(all(retail[k] == authored[k] for k in retail if k != "application/config/name"))

    def test_separate_ios_id_and_only_the_approved_native_bridge(self):
        text = (ROOT / "export_presets.cfg").read_text()
        retail = export_presets.parse(text)
        with_author = export_presets.parse(author.configure_ios(text))
        self.assertEqual(with_author["Android"], retail["Android"])
        self.assertEqual(with_author["Linux"], retail["Linux"])
        ios = with_author["iOS"]
        self.assertEqual(ios.options["application/bundle_identifier"], author.AUTHOR_ID)
        self.assertEqual(ios.options["plugins/WISAuthorFiles"], "true")
        for field in ("tests/*", "tools/*", "scenes/dev/*", "ios/plugins/*"):
            self.assertIn(field, ios.exclude_filter)
        self.assertNotIn("scripts/dev/*", ios.exclude_filter)
        self.assertEqual(retail["iOS"].options["application/bundle_identifier"], mobile.PACKAGE)
        self.assertNotIn("plugins/WISAuthorFiles", retail["iOS"].options)

    def test_author_pack_exception_does_not_relax_other_developer_paths(self):
        author_path = "res://" + author.BOOTSTRAP + "c"
        leaks = [(author_path, 1), ("res://scripts/dev/private.gdc", 1), ("res://ios/plugins/backdoor.gdip", 1)]
        retail = verify_contents(leaks)
        authored = verify_contents(leaks, allowed_paths=author.PACK_PATHS)
        self.assertTrue(any("2 file(s) under res://scripts/dev/" in line for line in retail))
        self.assertTrue(any("1 file(s) under res://scripts/dev/" in line for line in authored))
        self.assertTrue(any("private.gdc" in line for line in authored))
        self.assertTrue(any("res://ios/plugins/" in line for line in retail))
        self.assertTrue(any("res://ios/plugins/" in line for line in authored))

    def test_author_signature_requires_a_distinct_provisioning_profile(self):
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        team = "ABCDEFGHIJ"
        author_profile = {"TeamIdentifier": [team], "Platform": ["iOS"], "ExpirationDate": now + timedelta(days=1),
                          "Entitlements": {"application-identifier": f"{team}.{author.AUTHOR_ID}", "get-task-allow": True},
                          "UUID": "00000000-ABCD-0000-0000-000000000000", "Name": "Author profile fixture",
                          "ProvisionedDevices": ["fixture only"], "DeveloperCertificates": [b"fixture only"]}
        with self.assertRaisesRegex(ValueError, "explicit app ID"):
            profile_details(author_profile, "development", now)
        _, _, name, digest = profile_details(author_profile, "development", now, author.AUTHOR_ID)
        certificate, = digest
        options = export_options(team, name, certificate, "development", author.AUTHOR_ID)
        with self.assertRaises(mobile.BuildError):
            mobile.ios_signing_flags(team, options)
        self.assertIn(f"PROVISIONING_PROFILE_SPECIFIER={name}", mobile.ios_signing_flags(team, options, author.AUTHOR_ID))

    def test_author_preview_fixtures_do_not_expand_the_retail_font(self):
        with patch("subset_font.glob.glob", return_value=["tests/authoring_classroom_test.gd",
                                                          "scripts/dev/authoring/author_form.gd"]):
            used, _ = collect_characters(("unused",))
        self.assertFalse(used)
        with patch("subset_font.glob.glob", return_value=["tests/dialogue_layout_test.gd"]):
            used, _ = collect_characters(("unused",))
        self.assertTrue(used)

    def test_review_does_not_rewrite_unrelated_numeric_leaves(self):
        before = [{"id": "a", "check": {"difficulty": 9}, "text": "A"}]
        after = [{"id": "new", "text": "Test new"}, {"id": "a", "check": {"difficulty": 9.0}, "text": "Edited"}]
        result = preserve_source_values(after, before)
        self.assertEqual(result[1]["text"], "Edited")
        self.assertIs(type(result[1]["check"]["difficulty"]), int)


if __name__ == "__main__":
    unittest.main()
