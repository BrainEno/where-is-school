#!/usr/bin/env python3
"""Build a device IPA with a temporary signing identity on a trusted macOS runner."""
from __future__ import annotations

import argparse
import base64
from contextlib import ExitStack
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from authoring_build import AUTHOR_ID
from export_mobile import PACKAGE, UNSIGNED_TEAM


def security(*args, label: str, binary: bool = False):
    completed = subprocess.run(["security", *args], capture_output=True, timeout=60)
    if completed.returncode:
        # Never print security arguments, certificates, profile contents or command output here.
        raise ValueError(f"Apple signing: {label} failed. Check the protected environment inputs.")
    return completed.stdout if binary else completed.stdout.decode()


def secret(name: str, *, encoded: bool = True):
    value = os.environ.pop(name, "")
    if not value:
        raise ValueError(f"Configure {name} in the protected ios-signing environment before building.")
    if not encoded:
        return value
    try:
        return base64.b64decode(re.sub(r"\s+", "", value), validate=True)
    except ValueError:
        raise ValueError(f"{name} must be Base64 data.") from None


def profile_details(
    profile: dict, distribution: str, now: datetime, bundle: str = PACKAGE
) -> tuple[str, str, str, set[str]]:
    team, = profile.get("TeamIdentifier", ())
    if not re.fullmatch(r"[A-Z0-9]{10}", team) or team == UNSIGNED_TEAM:
        raise ValueError("Profile must have one real Apple Team ID.")
    expires = profile["ExpirationDate"]
    expires = expires.replace(tzinfo=timezone.utc) if expires.tzinfo is None else expires
    if expires <= now or "iOS" not in profile.get("Platform", ()):
        raise ValueError("Use an unexpired iOS provisioning profile.")
    entitlements = profile.get("Entitlements", {})
    if entitlements.get("application-identifier") != f"{team}.{bundle}":
        raise ValueError(f"Profile must authorize the explicit app ID {bundle}, not a wildcard or another app.")
    if not profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices"):
        raise ValueError("Use a Development or Ad Hoc profile that lists the intended test devices.")
    if bool(entitlements.get("get-task-allow")) != (distribution == "development"):
        raise ValueError("The profile is not for the selected Development/Ad Hoc distribution mode.")
    name = profile["Name"]
    if not isinstance(name, str) or not name.strip() or any(ord(char) < 32 for char in name):
        raise ValueError("Profile has an invalid name.")
    profile_id = str(uuid.UUID(profile["UUID"])).upper()
    certificates = {hashlib.sha1(cert, usedforsecurity=False).hexdigest().upper() for cert in profile["DeveloperCertificates"]}
    if not certificates:
        raise ValueError("The profile does not list any signing certificates.")
    return team, profile_id, name, certificates


def export_options(team: str, profile: str, certificate: str, distribution: str, bundle: str = PACKAGE) -> dict:
    return {"method": "debugging" if distribution == "development" else "release-testing",
            "destination": "export", "teamID": team, "manageAppVersionAndBuildNumber": False,
            "signingStyle": "manual", "signingCertificate": certificate,
            "provisioningProfiles": {bundle: profile}, "thinning": "<none>"}


def build(args: argparse.Namespace) -> None:
    if sys.platform != "darwin":
        raise ValueError("A signed iOS IPA requires macOS and full Xcode.")
    bundle = AUTHOR_ID if args.authoring else PACKAGE
    # Remove the secret environment entries before invoking any child tool.
    p12_data = secret("IOS_SIGNING_P12_BASE64")
    profile_data = secret("IOS_PROVISIONING_PROFILE_BASE64")
    password = secret("IOS_SIGNING_P12_PASSWORD", encoded=False)
    if args.authoring and subprocess.check_output(
        ["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT, text=True
    ).strip():
        raise ValueError("Sign the clean author commit that passed CI, not an edited working tree.")
    with tempfile.TemporaryDirectory(prefix="wis-ios-signing-") as temp, ExitStack() as cleanup:
        directory = Path(temp)
        p12, mobileprovision, keychain = (directory / f for f in ("signing.p12", "game.mobileprovision", "build.keychain-db"))
        p12.write_bytes(p12_data)
        mobileprovision.write_bytes(profile_data)
        decoded = security("cms", "-D", "-i", mobileprovision, label="decode provisioning profile", binary=True)
        team, profile_id, name, allowed = profile_details(plistlib.loads(decoded), args.distribution, datetime.now(timezone.utc), bundle)

        old_search = shlex.split(security("list-keychains", "-d", "user", label="read keychain search list"))
        key_password = secrets.token_hex(24)
        security("create-keychain", "-p", key_password, keychain, label="create temporary keychain")
        cleanup.callback(security, "delete-keychain", keychain, label="delete temporary keychain")
        security("set-keychain-settings", "-lut", "3600", keychain, label="set temporary keychain timeout")
        security("unlock-keychain", "-p", key_password, keychain, label="unlock temporary keychain")
        security("import", p12, "-P", password, "-k", keychain, "-T", "/usr/bin/codesign", label="import signing identity")
        p12.unlink()
        security("set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", key_password, keychain,
                 label="authorize Xcode codesign access")
        cleanup.callback(security, "list-keychains", "-d", "user", "-s", *old_search, label="restore keychain search list")
        security("list-keychains", "-d", "user", "-s", keychain, *old_search, label="add temporary keychain")
        identities = security("find-identity", "-v", "-p", "codesigning", keychain, label="find signing identity")
        kind = "Apple Development" if args.distribution == "development" else "Apple Distribution"
        matches = {digest for digest, common_name in re.findall(r'\b([A-F0-9]{40})\s+"([^"]+)"', identities)
                   if digest in allowed and common_name.startswith(kind + ":")}
        if len(matches) != 1:
            raise ValueError("Provide one valid Apple certificate/private key that is included in this profile.")
        certificate, = matches
        # Xcode 16+ stores profiles under UserData, not the older MobileDevice directory.
        installed = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles" / (profile_id + ".mobileprovision")
        installed.parent.mkdir(parents=True, exist_ok=True)
        if installed.exists():
            if installed.read_bytes() != profile_data:
                raise ValueError("An installed profile with the same UUID differs; refusing to overwrite it.")
        else:
            with installed.open("xb") as stream:
                cleanup.callback(installed.unlink, missing_ok=True)
                stream.write(profile_data)
        options = directory / "ExportOptions.plist"
        options.write_bytes(plistlib.dumps(export_options(team, name, certificate, args.distribution, bundle)))
        command = [sys.executable, ROOT / "tools/export_mobile.py", "ios-ipa", "--team", team, "--export-options", options,
                   "--godot", args.godot, "--output", args.output, "--build", str(args.build)]
        if args.authoring:
            command.append("--authoring")
        subprocess.run(command, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--authoring", action="store_true", help="sign the separate author app on a private runner")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--distribution", choices=("development", "ad-hoc"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--build", type=int, required=True)
    try:
        build(parser.parse_args())
    except (OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException) as error:
        print(f"IPA signing failed: {error}", file=sys.stderr)
        return 1
    except subprocess.SubprocessError:
        # Avoid leaking a password if the security process timed out.
        print("An Apple signing or export command failed; see its build step and check the environment.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
