#!/usr/bin/env python3
"""Exercise the staged mobile preset without a JDK, Xcode, or signing credentials."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import export_mobile
import export_presets


class MobileExportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")

    def test_preview_settings_keep_config_file_types(self) -> None:
        configured = export_mobile.configure(self.presets, "Android", {
            "package/unique_name": export_mobile.PREVIEW,
            "version/code": 37,
            "version/name": "0.1.0",
            "architectures/x86_64": True,
        })
        for expected in ('package/unique_name="io.github.braineno.whereisschool.preview"',
                         'version/code=37', 'version/name="0.1.0"', 'architectures/x86_64=true'):
            self.assertIn(expected, configured.splitlines())
        original = export_presets.parse(self.presets)
        staged = export_presets.parse(configured)
        for name in ("Linux", "Windows Desktop", "iOS"):
            self.assertEqual(staged[name], original[name])

    def test_ios_settings_quote_team_and_build_exactly_once(self) -> None:
        configured = export_mobile.configure(self.presets, "iOS", {
            "application/app_store_team_id": export_mobile.UNSIGNED_TEAM,
            "application/version": "37",
        })
        for expected in ('application/app_store_team_id="0000000000"', 'application/version="37"'):
            self.assertIn(expected, configured.splitlines())
        self.assertEqual(export_presets.parse(configured)["Android"], export_presets.parse(self.presets)["Android"])


if __name__ == "__main__":
    unittest.main()
