#!/usr/bin/env python3
"""Packaging and developer-tool contracts; no network, credentials or devices."""
from datetime import datetime, timedelta, timezone
from io import BytesIO
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "tools"), str(ROOT / "tools/macos/ios")]
from export_mobile import BuildError, PACKAGE, ios_signing_flags, verify_android_assets
from godot_pck import PackError, read_pack
from macos.ios import simulator_template
from release_pack_fixtures import fields, pack_files
from sign_ipa import export_options, profile_details
from simulator import available_runtimes, choose, devices
from verify_build import REQUIRED_PREFIXES


class AndroidContentTest(unittest.TestCase):
    members = {name.removeprefix("res://").removesuffix("/") + ("/sample.json" if name.endswith("/") else ""): b"x"
               for name in REQUIRED_PREFIXES}
    members.update(dict.fromkeys(("project.binary", "data/locale/en.json", "data/locale/zh-CN.json",
                                  "data/story/locations.json", "data/story/notebook_comparisons.json",
                                  "assets/fonts/NotoSansSC-Regular.ttf.import"), b"x"))

    def index(self, extra: tuple[str, bytes] | None = None) -> bytes:
        entries = list(self.members.items()) + ([extra] if extra else [])
        pack = pack_files(entries, flags=6)
        index = bytearray(pack[:104] + pack[fields(pack)["directory"]:])
        struct.pack_into("<QQ", index, 24, 0, 104)
        for row in range(len(entries)):
            struct.pack_into("<Q", index, fields(index, row)["offset"], 0)
        return bytes(index)

    def apk(self, files: dict[str, bytes], index: bytes, preview: bool = True) -> ZipFile:
        stream = BytesIO()
        with ZipFile(stream, "w") as package:
            package.writestr("assets/assets.sparsepck", index)
            for part in ["arm64-v8a", "x86_64"] if preview else ["arm64-v8a"]:
                package.writestr(f"lib/{part}/libgodot_android.so", b"fixture")
            for path, payload in files.items():
                package.writestr("assets/" + path, payload)
        return ZipFile(stream)

    def test_preview_and_release_verify_every_external_resource(self):
        for preview in (True, False):
            with self.apk(self.members, self.index(), preview) as apk:
                verify_android_assets(apk, preview)
        with self.assertRaises(PackError):
            read_pack(self.index(), 0)  # Existing desktop readers still refuse a bare index.

    def test_missing_or_same_size_replacement_is_rejected(self):
        for payload in (None, b"y", b"truncated or oversized"):
            sources = dict(self.members)
            name = "scenes/main/main.tscn"
            if payload is None:
                del sources[name]
            else:
                sources[name] = payload
            with self.apk(sources, self.index()) as apk, self.assertRaisesRegex(BuildError, name):
                verify_android_assets(apk, True)

    def test_development_files_and_bad_index_boundaries_fail(self):
        files = self.members | {"tests/private.gd": b"x"}
        with self.apk(files, self.index(("tests/private.gd", b"x"))) as apk, self.assertRaisesRegex(BuildError, "developer"):
            verify_android_assets(apk, True)
        with self.apk(self.members, self.index() + b"extra") as apk, self.assertRaises(PackError):
            verify_android_assets(apk, True)


class IOSProfileTest(unittest.TestCase):
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    team = "ABCDEFGHIJ"
    sample = {"TeamIdentifier": [team], "Platform": ["iOS"], "ExpirationDate": now + timedelta(days=1),
              "Entitlements": {"application-identifier": f"{team}.{PACKAGE}", "get-task-allow": True},
              "UUID": "00000000-ABCD-0000-0000-000000000000", "Name": "Development Profile Test",
              "ProvisionedDevices": ["example only"], "DeveloperCertificates": [b"not a real certificate"]}

    def test_correct_explicit_id_and_manual_flags(self):
        team, _, name, ids = profile_details(self.sample, "development", self.now)
        self.assertEqual(team, self.team)
        cert, = ids
        options = export_options(team, name, cert, "development")
        self.assertEqual(plistlib.loads(plistlib.dumps(options)), options)
        self.assertIn(f"PROVISIONING_PROFILE_SPECIFIER={name}", ios_signing_flags(team, options))
        self.assertEqual((options["destination"], options["method"]), ("export", "debugging"))
        self.assertEqual(export_options(team, name, cert, "ad-hoc")["method"], "release-testing")

    def test_reject_expired_wrong_team_wildcard_store_and_wrong_mode(self):
        for updates in ({"ExpirationDate": self.now}, {"TeamIdentifier": ["0000000000"]},
                        {"Entitlements": {"application-identifier": f"{self.team}.*"}},
                        {"ProvisionedDevices": []}, {"UUID": "../../elsewhere"}):
            with self.subTest(updates=updates), self.assertRaises(ValueError):
                profile_details(self.sample | updates, "development", self.now)
        with self.assertRaisesRegex(ValueError, "selected"):
            profile_details(self.sample, "ad-hoc", self.now)
        with self.assertRaises(BuildError):
            ios_signing_flags(self.team, {"signingStyle": "manual"})


class SimulatorSelectionTest(unittest.TestCase):
    def test_no_unavailable_or_non_ios_and_no_ambiguous_names(self):
        prefix = "com.apple.CoreSimulator.SimRuntime."
        phone = {"name": "iPhone Test", "state": "Shutdown", "isAvailable": True}
        data = {"devices": {prefix + "iOS-26-2": [phone | {"udid": "new"}],
                            prefix + "iOS-26-1": [phone | {"udid": "old"}],
                            prefix + "iOS-25-9": [phone | {"udid": "bad", "isAvailable": False}],
                            prefix + "watchOS-26-2": [phone | {"udid": "watch"}]},
                "runtimes": [{"identifier": prefix + "iOS-26-2", "isAvailable": True},
                             {"identifier": prefix + "iOS-26-1", "isAvailable": False}]}
        rows = devices(data)
        self.assertEqual([r["udid"] for r in rows], ["new", "old"])
        self.assertEqual(len(available_runtimes(data)), 1)
        self.assertEqual(choose(rows, None, True)["udid"], "new")
        self.assertEqual(choose(rows, "OLD", False)["udid"], "old")
        with self.assertRaises(ValueError):
            choose(rows, "iPhone Test", False)


class SimulatorTemplateTest(unittest.TestCase):
    def test_exact_official_editor_version_for_source_fallback(self):
        self.assertEqual(simulator_template.release_ref("4.7.2", "4.7.2.stable.official.ed1daf0bf"),
                         ("refs/tags/4.7.2-stable", "ed1daf0bf"))
        for engine in ("4.7.1.stable.official.ed1daf0bf", "4.7.2.stable.custom_build.ed1daf0bf",
                       "4.7.2.stable.mono.official.ed1daf0bf", "4.7.2.beta.official.ed1daf0bf"):
            with self.subTest(engine=engine), self.assertRaisesRegex(ValueError, "official"):
                simulator_template.release_ref("4.7.2", engine)

    def test_lipo_uses_the_real_architecture_list(self):
        archive = Path(__file__)  # The fixture only needs a file for the mocked lipo call.
        with patch.object(simulator_template, "capture", return_value="x86_64") as lipo:
            self.assertFalse(simulator_template.has_arch(archive, "arm64"))
            lipo.assert_called_once_with("lipo", "-archs", archive)
        with patch.object(simulator_template, "capture", return_value="x86_64 arm64"):
            self.assertTrue(simulator_template.has_arch(archive, "arm64"))

    def test_missing_slice_offline_fails_without_mutating_the_device_library(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            framework = out / "test.xcframework"
            simulator = framework / "ios-arm64_x86_64-simulator/libgodot.a"
            device = framework / "ios-arm64/libgodot.a"
            for archive in (simulator, device):
                archive.parent.mkdir(parents=True)
                archive.write_bytes(b"fixture")
            with (patch.object(Path, "home", return_value=out),
                  patch.object(simulator_template, "capture", return_value="Test SDK"),
                  patch.object(simulator_template, "has_arch", return_value=False),
                  patch.object(simulator_template, "compile_slice") as compile_slice):
                with self.assertRaisesRegex(ValueError, "no matching cached Simulator build"):
                    simulator_template.ensure_simulator_slice(out, "test", "arm64", "4.7.2",
                                                               "4.7.2.stable.official.ed1daf0bf", no_download=True)
                compile_slice.assert_not_called()
            self.assertEqual(device.read_bytes(), b"fixture")
            self.assertEqual(simulator.read_bytes(), b"fixture")


class WorkflowTest(unittest.TestCase):
    def test_builds_only_run_when_requested_or_from_explicit_tooling_pr_gate(self):
        def workflow(name):
            return yaml.load((ROOT / f".github/workflows/{name}.yml").read_text(), Loader=yaml.BaseLoader)
        android, ios, gate = map(workflow, ("build-android", "build-ios", "mobile-tooling"))
        self.assertEqual(set(android["on"]), {"workflow_dispatch", "workflow_call"})
        self.assertEqual(set(ios["on"]), {"workflow_dispatch"})
        self.assertNotIn("concurrency", android)
        self.assertNotIn("concurrency", ios)
        self.assertEqual(ios["jobs"]["ipa"]["environment"], "ios-signing")
        self.assertEqual(ios["jobs"]["ipa"]["needs"], "request")
        request = ios["jobs"]["request"]["steps"][0]
        self.assertIn("refs/heads/main", request["run"])
        consent = ios["on"]["workflow_dispatch"]["inputs"]["publish_device_profile"]
        self.assertEqual((consent["type"], consent["default"]), ("boolean", "false"))
        self.assertIn('"$REPO_PRIVATE" != true && "$PUBLISH_DEVICE_PROFILE" != true', request["run"])
        self.assertNotIn("secrets.", str(gate))
        self.assertNotIn("assets/**", gate["on"]["pull_request"]["paths"])
        self.assertEqual(gate["jobs"]["android"]["uses"], "./.github/workflows/build-android.yml")
        self.assertEqual(set(workflow("mobile-ci")["jobs"]), {"controls"})


if __name__ == "__main__":
    unittest.main()
