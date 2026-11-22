#!/usr/bin/env python3
"""Package and verify an iPhoneOS archive for LiveContainer (not Apple distribution)."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from zipfile import ZipFile


def pack(source: Path, sha: str, output: Path, ipa: Path) -> None:
    sys.path.insert(0, str(source / "tools"))
    from export_mobile import file_sha256, require, verify_ios_app

    report = json.loads((output / "BUILD.json").read_text())
    require(report["head"] == sha and not report["modified_sources"], "Unexpected game source")
    require(report["target"] == "ios-unsigned" and report.get("variant", "retail") == "retail",
            "Expected an ordinary unsigned iPhoneOS archive")
    require(not ipa.exists(), "Refusing to reuse an existing IPA")
    archive = output / report["artifact"]
    app, = archive.glob("Products/Applications/*.app")
    game_pack, = output.glob("*.pck")
    verify_ios_app(app, game_pack, report["build"], report["version"], simulator=False)

    with tempfile.TemporaryDirectory(prefix="wis-lc-ipa-") as folder:
        staging = Path(folder)
        payload = staging / "Payload"
        payload.mkdir()
        staged_app = payload / app.name
        subprocess.run(["ditto", app, staged_app], check=True)
        require(not (staged_app / "embedded.mobileprovision").exists(), "Unexpected device profile")
        # This local signature adds no Apple certificate or provisioning profile.
        # LiveContainer handles signing at import, not the normal iOS installer.
        subprocess.run(["codesign", "--force", "--deep", "--sign", "-", staged_app], check=True)
        subprocess.run(["zip", "-q", "-9", "-X", "-r", "-y", ipa, "Payload"], cwd=staging, check=True)
        with ZipFile(ipa) as zipped:
            require(zipped.testzip() is None, "IPA ZIP integrity check failed")
        unpacked = staging / "checked"
        subprocess.run(["ditto", "-x", "-k", ipa, unpacked], check=True)
        packaged_app, = (unpacked / "Payload").glob("*.app")
        verify_ios_app(packaged_app, game_pack, report["build"], report["version"], simulator=False)
        require(not (packaged_app / "embedded.mobileprovision").exists(), "Packaged a device profile")
        info = subprocess.check_output(["plutil", "-extract", "CFBundleExecutable", "raw", "-o", "-",
                                        packaged_app / "Info.plist"], text=True).strip()
        binary = packaged_app / info
        platform = subprocess.check_output(["xcrun", "vtool", "-show-build", binary], text=True)
        require(re.search(r"(?m)^\s*platform\s+IOS\s*$", platform) is not None, "Not an iOS device Mach-O")
        commands = subprocess.check_output(["xcrun", "otool", "-l", binary], text=True)
        require(not any(int(n) for n in re.findall(r"(?m)^\s*cryptid\s+(\d+)\s*$", commands)),
                "LiveContainer requires an unencrypted executable")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", packaged_app], check=True)

    result = {"source_sha": sha, "godot": report["godot"], "version": report["version"],
              "build": report["build"], "sdk": "iphoneos", "arch": "arm64", "signing": "local-ad-hoc",
              "name": ipa.name, "bytes": ipa.stat().st_size, "sha256": file_sha256(ipa),
              "pck_sha256": file_sha256(game_pack)}
    payload = json.dumps(result, separators=(",", ":"))
    (ipa.parent / "IPA-verified.json").write_text(payload + "\n", encoding="utf-8")
    print(f"::notice title=LiveContainer device IPA::{payload}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("source_sha")
    parser.add_argument("archive_dir", type=Path)
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()
    pack(args.source.resolve(), args.source_sha, args.archive_dir.resolve(), args.ipa.resolve())


if __name__ == "__main__":
    main()
