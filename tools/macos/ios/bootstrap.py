"""Prepare the pinned Godot editor and iOS template without altering Xcode selection."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.request import Request, urlopen
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[3]


def xcode_check() -> None:
    if sys.platform != "darwin":
        raise ValueError("The iOS Simulator requires macOS.")
    checks = (("xcodebuild", "-checkFirstLaunchStatus"), ("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"))
    for command in checks:
        if subprocess.run(command, stdout=subprocess.DEVNULL).returncode:
            raise ValueError("Install and open full Xcode once, select it in Xcode Settings > Locations "
                             "(or set DEVELOPER_DIR), and complete Xcode's first-launch setup.")


def download(asset: dict, destination: Path) -> None:
    url = asset["browser_download_url"]
    sha = asset.get("digest", "")
    if not url.startswith("https://github.com/godotengine/godot-builds/releases/download/") or not re.fullmatch(
            r"sha256:[a-f0-9]{64}", sha):
        raise ValueError("Godot release does not provide a trusted asset URL and SHA-256.")
    print(f"Downloading {asset['name']} ({asset['size'] / 1024**2:.0f} MiB)...", file=sys.stderr, flush=True)
    # Let curl retry transport failures; never unpack an incomplete/unverified download.
    subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "2",
                    "--connect-timeout", "20", "--max-time", "1200", "-o", destination, url], check=True)
    with destination.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha256").hexdigest()
    if destination.stat().st_size != asset["size"] or f"sha256:{actual}" != sha:
        raise ValueError("Godot release download failed its SHA-256/length check.")


def engine_ready(executable: Path, version: str) -> bool:
    if not executable.is_file():
        return False
    result = subprocess.run([executable, "--version"], capture_output=True, text=True, timeout=20)
    return result.returncode == 0 and result.stdout.startswith(version + ".stable.") and ".mono." not in result.stdout


def prepare_godot(override: str | None, *, no_download: bool) -> Path:
    version = (ROOT / ".godot-version").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Expected a stable version in .godot-version.")
    cache = Path.home() / "Library/Caches/where-is-school/godot" / version
    binary = cache / "Godot.app/Contents/MacOS/Godot"
    template = Path.home() / "Library/Application Support/Godot/export_templates" / (version + ".stable") / "ios.zip"
    if override:
        binary = Path(shutil.which(override) or override).expanduser().resolve()
        if not engine_ready(binary, version):
            raise ValueError(f"--godot must point to standard Godot {version} stable.")
    else:
        for candidate in (shutil.which("godot"), "/Applications/Godot.app/Contents/MacOS/Godot"):
            if candidate and engine_ready(Path(candidate), version):
                binary = Path(candidate)
                break
    need_editor = not engine_ready(binary, version)
    need_template = not template.is_file()
    if not need_editor and not need_template:
        return binary
    if no_download:
        raise ValueError(f"Godot {version} editor or iOS template missing. Remove --no-download or install the official pair.")
    request = Request(f"https://api.github.com/repos/godotengine/godot-builds/releases/tags/{version}-stable",
                      headers={"User-Agent": "where-is-school-ios-setup"})
    with urlopen(request, timeout=30) as response:
        assets = {asset["name"]: asset for asset in json.load(response)["assets"]}
    prefix = f"Godot_v{version}-stable"
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=cache) as work:
        temp = Path(work)
        if need_editor:
            path = temp / "editor.zip"
            download(assets[prefix + "_macos.universal.zip"], path)
            subprocess.run(["ditto", "-x", "-k", path, temp], check=True)
            if not engine_ready(temp / "Godot.app/Contents/MacOS/Godot", version):
                raise ValueError("The downloaded Godot executable did not report the pinned version.")
            app = cache / "Godot.app"
            if app.exists():
                raise ValueError(f"An unusable cached editor exists. Move it aside and retry: {app}")
            (temp / app.name).rename(app)
        if need_template:
            path = temp / "templates.tpz"
            download(assets[prefix + "_export_templates.tpz"], path)
            template.parent.mkdir(parents=True, exist_ok=True)
            # The large bundle is temporary; keep only the iOS template for this version.
            with ZipFile(path) as archive, archive.open("templates/ios.zip") as source:
                with tempfile.NamedTemporaryFile(dir=template.parent, delete=False) as staged:
                    staged_path = Path(staged.name)
                    try:
                        shutil.copyfileobj(source, staged)
                        staged.close()
                        if not template.exists():
                            staged_path.replace(template)
                    finally:
                        staged_path.unlink(missing_ok=True)
    return binary
