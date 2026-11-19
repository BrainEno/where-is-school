#!/usr/bin/env python3
"""Build mobile packages from the tracked sources in an isolated staging project.

No signing secrets are written to the preset or used by PR CI. An iOS project export,
unsigned device archive, and signed IPA have separate commands and separate verdicts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from zipfile import ZipFile

import export_presets
import stamp_release_version

ROOT = Path(__file__).resolve().parents[1]
APP = "where-is-school"
PACKAGE = "io.github.braineno.whereisschool"
PREVIEW = PACKAGE + ".preview"
ANDROID_API = 36
ANDROID_TOOLS = "36.1.0"
UNSIGNED_TEAM = "0000000000"  # Used only to satisfy the Xcode project exporter.
EXCLUDED = {"tests", "tools", "docs", "art", "scenes/dev", "scripts/dev", ".github", "addons"}
RELEASE_KEY = tuple("GODOT_ANDROID_KEYSTORE_RELEASE_" + k for k in ("PATH", "USER", "PASSWORD"))
ORIENTATIONS = {"UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"}
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"


class BuildError(Exception):
    pass


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise BuildError(reason)


def run(*args: str | Path, cwd: Path | None = None, capture: bool = False) -> str:
    result = subprocess.run(args, cwd=cwd, check=True, text=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout or ""


def configure(text: str, preset: str, options: dict[str, str | int | bool]) -> str:
    for key, value in options.items():
        text = export_presets.set_option(text, preset, key, value)
    return text


def project_settings(project: Path) -> dict[str, str]:
    settings = {}
    prefix = ""
    for line in project.read_text(encoding="utf-8").splitlines():
        if line.startswith("[") and line.endswith("]"):
            prefix = line[1:-1] + "/"
        elif not line.lstrip().startswith((";", "#")) and "=" in line:
            name, value = line.split("=", 1)
            settings[prefix + name.strip()] = value.strip()
    return settings


def check_presets(root: Path) -> None:
    presets = export_presets.read(root / "export_presets.cfg")
    for platform, target in (("Android", ".apk"), ("iOS", ".xcodeproj")):
        preset = presets.get(platform)
        require(preset is not None, f"Missing {platform} preset")
        assert preset is not None
        require(preset.platform == platform and preset.export_path.endswith(target), f"Invalid {platform} target")
        paths = {part.strip().removesuffix("/*") for part in preset.exclude_filter.split(",")}
        require(EXCLUDED <= paths, f"{platform} may ship developer content: {sorted(EXCLUDED - paths)}")
        require(preset.fields.get("export_filter") == "all_resources", f"{platform} might omit data-driven assets")
    android, ios = presets["Android"].options, presets["iOS"].options
    require(android.get("package/unique_name") == ios.get("application/bundle_identifier") == PACKAGE,
            "Do not change the installed application identity without a migration plan")
    require(android.get("package/signed") == "true" and android.get("architectures/arm64-v8a") == "true",
            "Android must sign an ARM64 APK")
    require(ios.get("application/app_store_team_id", "") == "" and ios.get("application/export_project_only") == "true",
            "Checked-in iOS preset must describe a project, not a signed export")
    require(not any(v for k, v in android.items() if k.startswith("keystore/")), "Do not commit signing parameters")
    require(not any(v for k, v in ios.items() if "provisioning_profile" in k or "code_sign_identity" in k),
            "Do not commit provisioning profile or certificate selections")
    require(not any(v == "true" for k, v in android.items() if k.startswith("permissions/")),
            "The game does not need Android permissions")
    require(android.get("screen/edge_to_edge") == "true" and android.get("screen/immersive_mode") == "false",
            "Keep Android system bars represented in the safe area")
    require(ios.get("application/min_ios_version") == "15.0" and ios.get("application/targeted_device_family") == "2",
            "iOS deployment must cover the declared iPhone and iPad support")
    settings = project_settings(root / "project.godot")
    require(settings.get("display/window/handheld/orientation") == "4", "Both landscape orientations are required")
    require(settings.get("rendering/renderer/rendering_method.mobile") == '"gl_compatibility"',
            "Keep the Android Compatibility renderer")
    require(settings.get("rendering/renderer/rendering_method.ios") == '"mobile"', "Use the Mobile renderer on iOS")
    require(settings.get("rendering/textures/vram_compression/import_etc2_astc") == "true", "Enable mobile textures")


def stage(destination: Path) -> None:
    """Do not rewrite the working copy, editor settings, user data or export credentials."""
    for name in run("git", "ls-files", "-z", cwd=ROOT, capture=True).split("\0"):
        if not name or name.split("/")[0] not in {"assets", "data", "scenes", "scripts", "addons",
                                                  "project.godot", "export_presets.cfg", "default_bus_layout.tres"}:
            continue
        if any(name.startswith(p + "/") for p in ("scenes/dev", "scripts/dev")):
            continue
        source, target = ROOT / name, destination / name
        require(source.is_file() and not source.is_symlink(), f"Expected a tracked file: {name}")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)


def import_project(godot: str, project: Path) -> None:
    # On a fresh import the theme can be read before fonts are available. Match the
    # main CI: don't treat that as proof of a good or a bad import. Audit the actual
    # destinations, then start the editor once with the now imported resources.
    first = subprocess.run([godot, "--headless", "--path", project, "--import"], check=False)
    require(0 <= first.returncode < 128, f"Godot import crashed ({first.returncode})")
    conventional = re.compile(r'res://(\.godot/imported/[^"\s]+)')
    for sidecar in project.joinpath("assets").rglob("*.import"):
        for relative in set(conventional.findall(sidecar.read_text(encoding="utf-8"))):
            require((project / relative).is_file(), f"Missing import output: {relative}")
    editor = subprocess.run([godot, "--headless", "--editor", "--path", project, "--quit"],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    print(editor.stdout, end="")
    require(editor.returncode == 0 and not re.search(r"SCRIPT ERROR|Parse Error", editor.stdout),
            "Imported project could not compile in Godot")


def check_manifest(xml: str, package: str, build: int, version: str) -> None:
    manifest = ET.fromstring(xml)
    ns = ANDROID_NS
    require(manifest.get("package") == package and manifest.get(ns + "versionCode") == str(build)
            and manifest.get(ns + "versionName") == version, "APK package/version does not match the selected build")
    sdk = manifest.find("uses-sdk")
    require(sdk is not None and sdk.get(ns + "minSdkVersion") == "24"
            and sdk.get(ns + "targetSdkVersion") == str(ANDROID_API), "Unexpected SDK range")
    permissions = [node.get(ns + "name") for node in manifest if node.tag.startswith("uses-permission")]
    require("android.permission.INTERNET" not in permissions, "APK requests Internet access")
    # Godot puts LAUNCHER on an exported activity alias. aapt's badging output only
    # walks activity elements, so inspect the decoded manifest rather than its summary.
    for node in manifest.findall("./application/*"):
        if node.tag not in {"activity", "activity-alias"} or node.get(ns + "exported") != "true":
            continue
        for intent in node.findall("intent-filter"):
            if any(a.get(ns + "name") == "android.intent.action.MAIN" for a in intent.findall("action")) \
                    and any(c.get(ns + "name") == "android.intent.category.LAUNCHER" for c in intent.findall("category")):
                return
    raise BuildError("APK has no exported MAIN/LAUNCHER activity or alias")


def verify_apk(apk: Path, sdk_tools: Path, package: str, build: int, version: str, preview: bool) -> None:
    suffix = ".bat" if os.name == "nt" else ""
    run(sdk_tools / ("apksigner" + suffix), "verify", "--verbose", "--print-certs", apk)
    cmdline = sdk_tools.parents[1] / "cmdline-tools"
    analyzer_name = "apkanalyzer" + suffix
    analyzers = sorted(cmdline.glob(f"*/bin/{analyzer_name}"), reverse=True)
    require(bool(analyzers), "Install Android SDK Command-line Tools (apkanalyzer)")
    check_manifest(run(analyzers[0], "manifest", "print", apk, capture=True), package, build, version)
    with ZipFile(apk) as archive:
        paths = set(archive.namelist())
        expected = {"arm64-v8a", "x86_64"} if preview else {"arm64-v8a"}
        abis = {path.split("/")[1] for path in paths if path.endswith("/libgodot_android.so")}
        require(abis == expected, f"Unexpected APK ABIs: {sorted(abis)}")
        required = {"assets/project.binary", "assets/assets.sparsepck", "assets/data/locale/en.json",
                    "assets/data/locale/zh-CN.json", "assets/data/story/locations.json"}
        require(required <= paths, f"APK is missing runtime content: {sorted(required - paths)}")
        require(not any(path.startswith(f"assets/{p}/") for p in EXCLUDED for path in paths),
                "APK contains editor/developer files")
        require(archive.testzip() is None, "APK contains a corrupt member")
    print(f"VERIFIED APK {package} {version} ({build}); ABI {', '.join(sorted(abis))}")


def android(args: argparse.Namespace, tree: Path, text: str, version: str, out: Path) -> Path:
    java, sdk = (os.environ.get(k) for k in ("JAVA_HOME", "ANDROID_HOME"))
    require(bool(java and sdk), "Set JAVA_HOME (JDK 17) and ANDROID_HOME (Android SDK) before starting Godot")
    tools = Path(str(sdk)) / "build-tools" / ANDROID_TOOLS
    require(tools.is_dir(), f"Install Android SDK platforms;android-{ANDROID_API} and build-tools;{ANDROID_TOOLS}")
    debug = args.target == "android-preview"
    if not debug:
        require(all(os.environ.get(key) for key in RELEASE_KEY), "Configure Godot release-keystore environment variables locally")
    bundle = PREVIEW if debug else PACKAGE
    target = out / f"{APP}{'-preview' if debug else ''}.apk"
    (tree / "export_presets.cfg").write_text(configure(text, "Android", {
        "package/unique_name": bundle, "package/name": APP + (" Preview" if debug else ""),
        "version/code": args.build, "version/name": version, "architectures/x86_64": debug,
    }), encoding="utf-8")
    require(not target.exists(), "Choose an empty output directory; refusing to reuse a stale APK")
    import_project(args.godot, tree)
    run(args.godot, "--headless", "--path", tree, "--export-debug" if debug else "--export-release", "Android", target)
    verify_apk(target, tools, bundle, args.build, version, debug)
    return target


def check_app(info: dict, build: int, version: str) -> None:
    require(info.get("CFBundleIdentifier") == PACKAGE, "Unexpected iOS bundle ID")
    require(str(info.get("CFBundleVersion")) == str(build) and info.get("CFBundleShortVersionString") == version,
            "Unexpected iOS build number or marketing version")
    require(info.get("MinimumOSVersion") == "15.0", "Unexpected iOS deployment target")
    require(set(info.get("UIDeviceFamily", ())) == {1, 2}, "iOS must support iPhone and iPad")
    for key in ("UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations~ipad"):
        require(set(info.get(key, ())) == ORIENTATIONS, f"Expected sensor landscape in {key}")


def ios(args: argparse.Namespace, tree: Path, text: str, version: str, out: Path) -> Path:
    signed = args.target == "ios-ipa"
    if signed:
        require(sys.platform == "darwin", "A signed IPA requires macOS and Xcode")
        require(bool(re.fullmatch(r"[A-Z0-9]{10}", args.team or "")) and args.team != UNSIGNED_TEAM,
                "A real Apple Team ID is required for IPA export")
        require(args.export_options is not None, "Supply a local Xcode ExportOptions.plist")
        options = plistlib.loads(args.export_options.read_bytes())
        require(options.get("destination", "export") == "export", "This command exports locally, never uploads")
        require(options.get("teamID", args.team) == args.team, "Export options select a different Apple team")
    else:
        require(args.target == "ios-project" or sys.platform == "darwin", "The device archive requires macOS and Xcode")
    project = out / f"{APP}.xcodeproj"
    require(not project.exists(), "Choose an empty output directory; refusing to reuse an old Xcode project")
    (tree / "export_presets.cfg").write_text(configure(text, "iOS", {
        "application/app_store_team_id": args.team if signed else UNSIGNED_TEAM,
        "application/short_version": version, "application/version": str(args.build),
    }), encoding="utf-8")
    import_project(args.godot, tree)
    run(args.godot, "--headless", "--path", tree, "--export-release", "iOS", project)
    pack = out / f"{APP}.pck"
    require((project / "project.pbxproj").is_file() and pack.is_file(),
            "Godot did not produce the Xcode project and game pack")
    run(sys.executable, ROOT / "tools/verify_build.py", "--pck", pack)
    if args.target == "ios-project":
        return project
    archive = out / f"{APP}.xcarchive"
    flags = [f"DEVELOPMENT_TEAM={args.team}", "CODE_SIGN_STYLE=Automatic"] if signed else [
        "DEVELOPMENT_TEAM=", "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO"]
    run("xcodebuild", "-project", project, "-scheme", APP, "-configuration", "Release", "-sdk", "iphoneos",
        "-destination", "generic/platform=iOS", "-archivePath", archive, "archive", *flags)
    app, = archive.glob("Products/Applications/*.app")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    check_app(info, args.build, version)
    require(run("lipo", "-archs", app / info["CFBundleExecutable"], capture=True).strip() == "arm64",
            "Archive must contain a device ARM64 executable, not a simulator build")
    require(any(app.rglob("*.pck")), "iOS app is missing its Godot pack")
    if not signed:
        print("VERIFIED unsigned iOS device archive; NOT an installable IPA")
        return archive
    run("codesign", "--verify", "--deep", "--strict", app)
    run("xcodebuild", "-exportArchive", "-archivePath", archive, "-exportOptionsPlist", args.export_options,
        "-exportPath", out / "ipa")
    ipa, = (out / "ipa").glob("*.ipa")
    with ZipFile(ipa) as export:
        plist, = [name for name in export.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
        check_app(plistlib.loads(export.read(plist)), args.build, version)
        require(plist.removesuffix("Info.plist") + "_CodeSignature/CodeResources" in export.namelist(),
                "The exported IPA has no code-signature resources")
        require(export.testzip() is None, "IPA contains a corrupt member")
    return ipa


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=("check", "android-preview", "android-release", "ios-project", "ios-unsigned", "ios-ipa"))
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--output", type=Path, default=ROOT / "build/mobile")
    parser.add_argument("--build", type=int, default=1, help="Monotonically increasing distribution build number")
    parser.add_argument("--team", default=os.environ.get("IOS_TEAM_ID"))
    parser.add_argument("--export-options", type=Path, help="Local Xcode export options for a signed IPA")
    args = parser.parse_args()
    try:
        check_presets(ROOT)
        if args.target == "check":
            print("PASS: committed Android and iOS mobile export contracts")
            return 0
        require(1 <= args.build <= 2_100_000_000, "Build number outside the Android distribution range")
        expected = (ROOT / ".godot-version").read_text().strip()
        actual = run(args.godot, "--version", capture=True).strip()
        require(actual.startswith(expected + ".stable.") and ".mono." not in actual,
                f"Expected standard Godot {expected} stable; got {actual}")
        version = stamp_release_version.parse(stamp_release_version.read_version_file(ROOT / "packaging/version.txt"))["core"]
        out = args.output.resolve()
        require(not out.exists() or not any(out.iterdir()), "Build output directory must be empty")
        out.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="wis-mobile-") as temp:
            tree = Path(temp)
            stage(tree)
            presets = (tree / "export_presets.cfg").read_text(encoding="utf-8")
            build = android if args.target.startswith("android-") else ios
            artifact = build(args, tree, presets, version, out)
        report = {"target": args.target, "head": run("git", "rev-parse", "HEAD", cwd=ROOT, capture=True).strip(),
                  "modified_sources": bool(run("git", "status", "--porcelain", "--untracked-files=no",
                                               cwd=ROOT, capture=True)),
                  "godot": actual, "version": version, "build": args.build, "artifact": str(artifact.relative_to(out))}
        if artifact.is_file():
            with artifact.open("rb") as stream:
                report["sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()
        (out / "BUILD.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report))
        return 0
    except (BuildError, OSError, ValueError, ET.ParseError, plistlib.InvalidFileException, subprocess.CalledProcessError,
            stamp_release_version.VersionError, export_presets.PresetError) as error:
        print(f"Mobile export failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
