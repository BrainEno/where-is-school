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
import platform
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from zipfile import BadZipFile, ZipFile

import export_presets
import stamp_release_version
import verify_build
from godot_pck import PackError, read_pack

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
    require(ios.get("application/min_ios_version") == "15.0" and ios.get("application/targeted_device_family") == "3",
            "iOS deployment must target both iPhone and iPad (universal device family)")
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
        verify_android_assets(archive, preview)
    print(f"VERIFIED APK {package} {version} ({build}); complete indexed game and signed native libraries")


def verify_android_assets(archive: ZipFile, preview: bool) -> None:
    names = archive.namelist()
    paths = set(names)
    require(len(paths) == len(names), "APK contains duplicate ZIP members")
    expected = {"arm64-v8a", "x86_64"} if preview else {"arm64-v8a"}
    abis = {path.split("/")[1] for path in paths if re.fullmatch(r"lib/[^/]+/libgodot_android.so", path)}
    require(abis == expected, f"Unexpected APK ABIs: {sorted(abis)}")
    index_name = "assets/assets.sparsepck"
    require(index_name in paths and archive.getinfo(index_name).file_size <= 8 * verify_build.MiB,
            "APK has no bounded Godot sparse index")

    def verify_member(path: str, size: int, digest: bytes) -> None:
        name = "assets/" + path
        require(name in paths and archive.getinfo(name).file_size == size <= verify_build.HARD_CEILING,
                f"APK resource missing, oversized or truncated: {path}")
        with archive.open(name) as stream:
            actual = hashlib.file_digest(stream, lambda: hashlib.md5(usedforsecurity=False)).digest()
        require(actual == digest, f"APK resource does not match its Godot index: {path}")

    entries, header = read_pack(archive.read(index_name), 0, verify_external=verify_member)
    required = {"res://project.binary", "res://data/locale/en.json", "res://data/locale/zh-CN.json",
                "res://data/story/locations.json"}
    require(required <= dict(entries).keys(), "APK index is missing the project, locale or location data")
    require(not any(path.startswith(f"assets/{folder}/") for path in paths for folder in EXCLUDED),
            "APK contains editor/developer files")
    problems, warnings = verify_build.verify(entries, header)
    for warning in warnings:
        verify_build.annotate("warning", "Android build budget", warning)
    require(not problems, "; ".join(problems))
    require(archive.testzip() is None, "APK contains a corrupt member")


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


def verify_ios_app(app: Path, pack: Path, build: int, version: str, *, simulator: bool) -> None:
    info = plistlib.loads((app / "Info.plist").read_bytes())
    check_app(info, build, version)
    sdk = "iphonesimulator" if simulator else "iphoneos"
    require(info.get("DTPlatformName") == sdk, f"Expected an {sdk} application")
    executable = app / info["CFBundleExecutable"]
    arch = platform.machine() if simulator else "arm64"
    require(run("lipo", "-archs", executable, capture=True).strip() == arch,
            f"{sdk} executable must be {arch}")
    installed_pack = app / pack.name
    require(installed_pack.is_file() and file_sha256(installed_pack) == file_sha256(pack),
            "The built application does not contain the verified Godot pack")


def build_simulator(xcode: tuple[str | Path, ...], out: Path, flags: list[str]) -> Path:
    products = out / "simulator"
    cmd = (*xcode, "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination",
           "generic/platform=iOS Simulator", "-derivedDataPath", out / "DerivedData",
           f"CONFIGURATION_BUILD_DIR={products}", f"ARCHS={platform.machine()}", "build", *flags)
    log = out / "xcode-build.log"
    # Keep Xcode's output separate from import and simctl noise; on failure the
    # exact compiler/linker/target error should survive the CI log's summary.
    with log.open("w", encoding="utf-8") as stream:
        built = subprocess.run(cmd, stdout=stream, stderr=subprocess.STDOUT, check=False)
    if built.returncode:
        print(log.read_text(encoding="utf-8", errors="replace"), file=sys.stderr, end="")
        raise BuildError(f"Simulator xcodebuild exited {built.returncode}; see xcode-build.log")
    app, = products.glob("*.app")
    return app


def file_sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def ios_signing_flags(team: str, options: dict) -> list[str]:
    if options.get("signingStyle") != "manual":
        return [f"DEVELOPMENT_TEAM={team}", "CODE_SIGN_STYLE=Automatic"]
    profile = options.get("provisioningProfiles", {}).get(PACKAGE)
    certificate = options.get("signingCertificate")
    require(isinstance(profile, str) and bool(profile.strip()), "Manual signing needs the game's profile")
    require(isinstance(certificate, str) and bool(certificate.strip()), "Manual signing needs a certificate")
    return [f"DEVELOPMENT_TEAM={team}", "CODE_SIGN_STYLE=Manual", f"CODE_SIGN_IDENTITY={certificate}",
            f"PROVISIONING_PROFILE_SPECIFIER={profile}"]


def ios(args: argparse.Namespace, tree: Path, text: str, version: str, out: Path) -> Path:
    signed = args.target == "ios-ipa"
    simulator = args.target == "ios-simulator"
    flags = ["DEVELOPMENT_TEAM=", "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO"]
    require(args.target == "ios-project" or sys.platform == "darwin", "This iOS build needs macOS and full Xcode")
    if signed:
        require(bool(re.fullmatch(r"[A-Z0-9]{10}", args.team or "")) and args.team != UNSIGNED_TEAM,
                "A real Apple Team ID is required for IPA export")
        require(args.export_options is not None, "Supply a local Xcode ExportOptions.plist")
        options = plistlib.loads(args.export_options.read_bytes())
        require(options.get("destination", "export") == "export", "This command exports locally, never uploads")
        require(options.get("teamID", args.team) == args.team, "Export options select a different Apple team")
        flags = ios_signing_flags(args.team, options)
    if simulator:
        # Godot's official simulator slices omit both Metal and Vulkan. Do not
        # change the device preset or the source tree to get a simulator build.
        settings = tree / "project.godot"
        source, count = re.subn(r'^renderer/rendering_method\.ios="mobile"$',
                                'renderer/rendering_method.ios="gl_compatibility"',
                                settings.read_text(encoding="utf-8"), flags=re.M)
        require(count == 1, "Cannot select the Compatibility renderer for the simulator")
        settings.write_text(source, encoding="utf-8")
    project = out / f"{APP}.xcodeproj"
    (tree / "export_presets.cfg").write_text(configure(text, "iOS", {
        "application/app_store_team_id": args.team if signed else UNSIGNED_TEAM,
        "application/short_version": version, "application/version": str(args.build),
    }), encoding="utf-8")
    import_project(args.godot, tree)
    run(args.godot, "--headless", "--path", tree, "--export-debug" if simulator else "--export-release", "iOS", project)
    pack = out / f"{APP}.pck"
    require((project / "project.pbxproj").is_file() and pack.is_file(),
            "Godot did not produce the Xcode project and game pack")
    run(sys.executable, ROOT / "tools/verify_build.py", "--pck", pack)
    if args.target == "ios-project":
        return project
    xcode = ("xcodebuild", "-project", project, "-scheme", APP)
    if simulator:
        from macos.ios.simulator_template import ensure_simulator_slice

        version_pin = (ROOT / ".godot-version").read_text().strip()
        ensure_simulator_slice(out, APP, platform.machine(), version_pin, args.engine_version, no_download=args.no_download)
        app = build_simulator(xcode, out, flags)
        verify_ios_app(app, pack, args.build, version, simulator=True)
        return app
    archive = out / f"{APP}.xcarchive"
    run(*xcode, "-configuration", "Release", "-sdk", "iphoneos", "-destination", "generic/platform=iOS",
        "-archivePath", archive, "archive", *flags)
    app, = archive.glob("Products/Applications/*.app")
    verify_ios_app(app, pack, args.build, version, simulator=False)
    if args.target == "ios-unsigned":
        print("VERIFIED unsigned iOS device archive; NOT an installable IPA")
        return archive
    if args.target == "ios-unsigned-ipa":
        # LiveContainer can sign an unsigned guest app with its imported
        # AltStore/SideStore certificate (or launch it with JIT where supported).
        # Keep this preview separate from the protected, device-provisioned release.
        ipa_dir = out / "ipa"
        ipa_dir.mkdir(parents=True, exist_ok=True)
        payload = out / "ipa-staging" / "Payload"
        payload.mkdir(parents=True, exist_ok=True)
        shutil.copytree(app, payload / app.name, symlinks=True)
        ipa = ipa_dir / f"{APP}-unsigned.ipa"
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", payload, ipa)
        with ZipFile(ipa) as packaged:
            require(packaged.testzip() is None, "Unsigned IPA contains a corrupt ZIP member")
            require(f"Payload/{APP}.app/Info.plist" in packaged.namelist(),
                    "Unsigned IPA is missing its iOS application bundle")
        with tempfile.TemporaryDirectory(prefix="wis-verify-unsigned-ipa-") as unpacked:
            run("ditto", "-x", "-k", ipa, unpacked)
            exported = Path(unpacked) / "Payload" / f"{APP}.app"
            verify_ios_app(exported, pack, args.build, version, simulator=False)
        print("VERIFIED unsigned arm64 iOS IPA for LiveContainer; signing is delegated to LiveContainer")
        return ipa
    run("codesign", "--verify", "--deep", "--strict", app)
    run("xcodebuild", "-exportArchive", "-archivePath", archive, "-exportOptionsPlist", args.export_options,
        "-exportPath", out / "ipa")
    ipa, = (out / "ipa").glob("*.ipa")
    # Verify the *exported* app, not just the archive that Xcode can re-sign.
    with ZipFile(ipa) as export:
        require(export.testzip() is None, "IPA contains a corrupt member")
    with tempfile.TemporaryDirectory(prefix="wis-verify-ipa-") as unpacked:
        run("ditto", "-x", "-k", ipa, unpacked)
        exported, = (Path(unpacked) / "Payload").glob("*.app")
        verify_ios_app(exported, pack, args.build, version, simulator=False)
        run("codesign", "--verify", "--deep", "--strict", exported)
    return ipa


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=("check", "android-preview", "android-release", "ios-project", "ios-unsigned", "ios-unsigned-ipa", "ios-simulator", "ios-ipa"))
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--output", type=Path, default=ROOT / "build/mobile")
    parser.add_argument("--build", type=int, default=1, help="Monotonically increasing distribution build number")
    parser.add_argument("--team", default=os.environ.get("IOS_TEAM_ID"))
    parser.add_argument("--no-download", action="store_true", help="do not fetch a missing iOS Simulator slice")
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
        args.engine_version = actual
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
            report["sha256"] = file_sha256(artifact)
        (out / "BUILD.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report))
        return 0
    except (BuildError, PackError, BadZipFile, OSError, ValueError, ET.ParseError, plistlib.InvalidFileException,
            subprocess.CalledProcessError,
            stamp_release_version.VersionError, export_presets.PresetError) as error:
        print(f"Mobile export failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
