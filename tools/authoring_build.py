"""Stage the author app without changing the committed project or retail presets."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile

import export_presets
import verify_build

ROOT = Path(__file__).resolve().parents[1]
AUTHOR_ID = "io.github.braineno.whereisschool.authoring"
AUTHOR_NAME = "Where Is School - Author"
AUTHOR_DIR = "scripts/story_editor/"
BOOTSTRAP = AUTHOR_DIR + "bootstrap.gd"
SCRIPTS = frozenset(AUTHOR_DIR + name + ".gd" for name in (
    "bootstrap", "author_overlay", "author_form", "branch_preview", "dialogue_patch",
    "draft_store", "draft_journal", "author_exchange",
))
PACK_PATHS = frozenset("res://" + path.removesuffix(".gd") + suffix for path in SCRIPTS
                       for suffix in (".gd", ".gdc", ".gd.remap"))
BRIDGE = ROOT / "tools/macos/ios/authoring"


def is_authoring_source(path: str) -> bool:
    return path.removesuffix(".uid") in SCRIPTS


def configure_project(tree: Path, head: str, *, editor: bool = True) -> None:
    project = tree / "project.godot"
    text = project.read_text(encoding="utf-8")
    if text.count('[autoload]\n') != 1 or text.count('config/name="where-is-school"') != 1:
        raise ValueError("Unexpected author project base; the retail settings were not modified")
    if any(not (tree / p).is_file() for p in SCRIPTS):
        # The retail iPhone pack carries the editor runtime too; a staged tree without it
        # would ship a preset that points at nothing.
        raise ValueError("The story editor pack requires all its tracked scripts")
    text = text.replace('config/name="where-is-school"', f'config/name={json.dumps(AUTHOR_NAME)}')
    if editor:
        # Last autoload, after GameState, Loc, Settings and Session are ready.
        text, count = re.subn(r'(Session="\*res://scripts/ui/game_session\.gd"\n)',
                             rf'\1Authoring="*res://{BOOTSTRAP}"\n', text)
        if count != 1:
            raise ValueError("Cannot locate the author app's autoload insertion point")
    project.write_text(text.rstrip() + f'\n\n[authoring]\nbase_commit={json.dumps(head)}\n', encoding="utf-8")


def configure_ios(text: str) -> str:
    preset = export_presets.parse(text)["iOS"]
    header = f"[preset.{preset.index}]"
    start = text.index(header) + len(header)
    end = text.index("\n[", start)
    excludes = [p.strip() for p in preset.exclude_filter.split(",") if p.strip()]
    # Godot scans .gdip files separately for Xcode integration. Keep plugin
    # source/binaries out of the resource pack, including in this variant.
    excludes.append("ios/plugins/*")
    segment, count = re.subn(r'^exclude_filter=.*$', f'exclude_filter={json.dumps(",".join(excludes))}',
                             text[start:end], flags=re.MULTILINE)
    if count != 1:
        raise ValueError("Cannot configure the author iOS resource selection")
    text = text[:start] + segment + text[end:]
    for key, value in (("application/bundle_identifier", AUTHOR_ID), ("plugins/WISAuthorFiles", True)):
        text = export_presets.set_option(text, "iOS", key, value)
    return text


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def configure_bridge(text: str) -> str:
    """The Files bridge block for a preset that keeps its own identity: the retail app."""
    return export_presets.set_option(text, "iOS", "plugins/WISAuthorFiles", True)


def compile_files_bridge(tree: Path, *, simulator: bool) -> None:
    sdk = "iphonesimulator" if simulator else "iphoneos"
    arch = platform.machine() if simulator else "arm64"
    destination = tree / "ios/plugins/wis_author_files"
    destination.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="wis-author-files-") as temp:
        object_file = Path(temp) / "FilesBridge.o"
        sysroot = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()
        suffix = "-simulator" if simulator else ""
        subprocess.run(["xcrun", "--sdk", sdk, "clang++", "-target", f"{arch}-apple-ios15.0{suffix}",
                        "-isysroot", sysroot, "-std=c++17", "-fobjc-arc", "-Os", "-Wall", "-Wextra",
                        "-c", BRIDGE / "FilesBridge.mm", "-o", object_file], check=True)
        subprocess.run(["xcrun", "libtool", "-static", "-o", destination / "libWISAuthorFiles.a", object_file], check=True)
    shutil.copyfile(BRIDGE / "FilesBridge.gdip", destination / "FilesBridge.gdip")
    # Evidence for the release check: which bridge source this slice was built from.
    manifest = {"source_sha256": file_sha256(BRIDGE / "FilesBridge.mm")}
    (destination / "BUNDLE.json").write_text(json.dumps(manifest) + "\n", encoding="utf-8")


def verify_pack(pack: Path) -> None:
    entries, header = verify_build.load_blob(pack.read_bytes(), embedded=False)
    problems, warnings = verify_build.verify(entries, header, allowed_paths=PACK_PATHS)
    paths = {name for name, _ in entries}
    for source in SCRIPTS:
        if not {"res://" + source, "res://" + source + "c"} & paths:
            problems.append(f"Author pack is missing {source}")
    for note in warnings:
        print(f"WARNING: {note}")
    if problems:
        raise ValueError("Author pack failed verification:\n" + "\n".join(problems))
    print(f"PASS: author pack ({len(entries)} verified entries); no other developer resources")


def main() -> int:
    # Import here because export_mobile also imports the isolated author config.
    import export_mobile

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--prepare-only", action="store_true", help="stage without starting Godot")
    args = parser.parse_args()
    try:
        tree = args.output.resolve()
        export_mobile.require(not tree.exists() or not any(tree.iterdir()), "Author staging directory must be empty")
        export_mobile.stage(tree, authoring=True)
        configure_project(tree, export_mobile.run("git", "rev-parse", "HEAD", cwd=ROOT, capture=True).strip())
        if not args.prepare_only:
            export_mobile.import_project(args.godot, tree)
            export_mobile.run(args.godot, "--path", tree)
        return 0
    except (OSError, ValueError, export_mobile.BuildError, subprocess.SubprocessError) as error:
        print(f"Author project: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
