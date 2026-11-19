"""Fill a missing native Simulator slice in the exported Debug project only.

Godot 4.7.2's template declares arm64 in Info.plist but libgodot.a only
contains x86_64. Build the missing slice from the same official release tag;
never relabel a device library or edit the user's installed export templates.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

SOURCE = "https://github.com/godotengine/godot.git"
SCONS = "scons==4.10.1 --hash=sha256:bd9d1c52f908d874eba92a8c0c0a8dcf2ed9f3b88ab956d0fce1da479c4e7126\n"
FLAGS = ("platform=ios", "target=template_debug", "simulator=yes", "opengl3=yes", "metal=no", "vulkan=no",
         "module_mono_enabled=no", "optimize=debug", "debug_symbols=no")


def capture(*args, cwd: Path | None = None) -> str:
    return subprocess.run(args, cwd=cwd, check=True, text=True, stdout=subprocess.PIPE).stdout.strip()


def has_arch(library: Path, arch: str) -> bool:
    return library.is_file() and subprocess.run(["lipo", "-verify_arch", arch, library],
                                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def release_ref(version: str, engine: str) -> tuple[str, str]:
    match = re.fullmatch(re.escape(version) + r"\.stable\.official\.([0-9a-f]{9,40})", engine)
    if not match or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Simulator source fallback requires the pinned, official standard Godot editor.")
    return f"refs/tags/{version}-stable", match[1]


def compile_slice(names: tuple[str, ...], build: Path, ref: str, commit_prefix: str, arch: str, log: Path) -> None:
    source = build / "godot"
    source.mkdir()
    subprocess.run(["git", "init", "-q", source], check=True)
    subprocess.run(["git", "fetch", "--depth=1", "--no-tags", SOURCE, ref], cwd=source, check=True)
    sha = capture("git", "rev-parse", "FETCH_HEAD^{commit}", cwd=source)
    if not sha.startswith(commit_prefix):
        raise ValueError("Godot's upstream tag does not match the pinned editor's commit.")
    subprocess.run(["git", "checkout", "-q", "--detach", sha], cwd=source, check=True)
    venv = build / "venv"
    subprocess.run([sys.executable, "-m", "venv", venv], check=True)
    requirements = build / "requirements.txt"
    requirements.write_text(SCONS, encoding="utf-8")
    subprocess.run([venv / "bin/python", "-m", "pip", "--isolated", "install", "--no-deps", "--require-hashes",
                    "--index-url", "https://pypi.org/simple", "--only-binary=:all:", "-r", requirements], check=True)
    targets = [f"bin/{Path(name).stem}.ios.template_debug.{arch}.simulator.a" for name in names]
    print(f"Compiling the {arch} iOS Simulator template from Godot {sha}. See {log.name} for compiler output.", flush=True)
    with log.open("w", encoding="utf-8") as stream:
        workers = min(6, os.cpu_count() or 2)
        result = subprocess.run([venv / "bin/scons", f"-j{workers}", f"arch={arch}", *FLAGS, *targets], cwd=source,
                                stdout=stream, stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise ValueError(f"Godot Simulator template compilation failed ({result.returncode}); see {log.name}.")
    for name, target in zip(names, targets, strict=True):
        library = source / target
        if not has_arch(library, arch):
            raise ValueError(f"The source build did not produce a {arch} Simulator {name}.")
        library.rename(build / name)


def ensure_simulator_slice(out: Path, app: str, arch: str, version: str, engine: str, *, no_download: bool) -> None:
    frameworks = {"libgodot.a": out / f"{app}.xcframework"}
    camera = out / f"{app}_camera.xcframework"
    if camera.is_dir():
        frameworks["libgodot_camera.a"] = camera
    libraries = {name: directory / "ios-arm64_x86_64-simulator" / name for name, directory in frameworks.items()}
    for file in libraries.values():
        if not file.is_file():
            raise ValueError(f"Expected the official Debug Simulator template in {file.parent.name}/{file.name}.")
    missing = tuple(name for name, file in libraries.items() if not has_arch(file, arch))
    if not missing:
        print(f"Using the official Godot {arch} Simulator slice.", flush=True)
        return
    ref, prefix = release_ref(version, engine)
    sdk = capture("xcrun", "--sdk", "iphonesimulator", "--show-sdk-build-version")
    key = hashlib.sha256(repr((ref, engine, arch, sdk, capture("xcodebuild", "-version"), FLAGS, SCONS, missing))
                         .encode()).hexdigest()[:24]
    cache = Path.home() / "Library/Caches/where-is-school/godot/simulator" / key
    if not all(has_arch(cache / name, arch) for name in missing):
        if no_download:
            raise ValueError(f"The official template lacks {arch} and no matching cached Simulator build exists. "
                             "Run without --no-download to build the missing slice from source.")
        cache.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="source-", dir=cache.parent) as temp:
            build = Path(temp)
            compile_slice(missing, build, ref, prefix, arch, out / "simulator-template.log")
            cache.mkdir(exist_ok=True)
            for name in missing:
                (build / name).replace(cache / name)
    for name in missing:
        library = libraries[name]
        staging = library.with_suffix(".new.a")
        subprocess.run(["lipo", "-create", library, cache / name, "-output", staging], check=True)
        if not has_arch(staging, arch):
            raise ValueError(f"Failed to install the matching {arch} Simulator slice for {name}.")
        staging.replace(library)
    print(f"Added the matching Godot {arch} Simulator slice to the exported Debug project.", flush=True)
