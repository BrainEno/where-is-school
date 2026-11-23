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

    def test_only_handheld_exports_select_the_touch_layout(self) -> None:
        presets = export_presets.parse(self.presets)
        handheld = {name for name, preset in presets.items()
                    if "wis_handheld" in preset.fields.get("custom_features", "").split(",")}
        self.assertEqual(handheld, {"iOS", "Android"})

    def test_reference_only_classroom_models_stay_out_of_every_pack(self) -> None:
        for preset in export_presets.parse(self.presets).values():
            with self.subTest(preset=preset.name):
                excluded = {item.strip() for item in preset.exclude_filter.split(",")}
                for model in ("classroom_window_curtains", "classroom_biology_chart"):
                    self.assertIn(f"assets/models/classroom/{model}.glb", excluded)
                self.assertNotIn("assets/models/classroom/*", excluded, "Keep the used classroom models")

    def test_ios_settings_quote_team_and_build_exactly_once(self) -> None:
        configured = export_mobile.configure(self.presets, "iOS", {
            "application/app_store_team_id": export_mobile.UNSIGNED_TEAM,
            "application/version": "37",
        })
        for expected in ('application/app_store_team_id="0000000000"', 'application/version="37"'):
            self.assertIn(expected, configured.splitlines())
        self.assertEqual(export_presets.parse(configured)["Android"], export_presets.parse(self.presets)["Android"])

    def test_android_launcher_alias(self) -> None:
        manifest = f"""<manifest xmlns:android="http://schemas.android.com/apk/res/android"
                    package="{export_mobile.PREVIEW}" android:versionCode="37" android:versionName="0.1.0">
          <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36" />
          <application>
            <activity android:name=".GodotApp" android:exported="false" />
            <activity-alias android:name=".Launcher" android:targetActivity=".GodotApp" android:exported="true">
              <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
              </intent-filter>
            </activity-alias>
          </application>
        </manifest>"""
        export_mobile.check_manifest(manifest, export_mobile.PREVIEW, 37, "0.1.0")
        for invalid in (manifest.replace('exported="true"', 'exported="false"'),
                        manifest.replace("android.intent.category.LAUNCHER", "android.intent.category.DEFAULT"),
                        manifest.replace('minSdkVersion="24"', 'minSdkVersion="29"')):
            with self.assertRaises(export_mobile.BuildError):
                export_mobile.check_manifest(invalid, export_mobile.PREVIEW, 37, "0.1.0")


if __name__ == "__main__":
    unittest.main()
