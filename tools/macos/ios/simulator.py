#!/usr/bin/env python3
"""Select a simulator, export a complete Debug app, and test it without signing."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from zipfile import BadZipFile

from bootstrap import ROOT, prepare_godot, xcode_check

BUNDLE = "io.github.braineno.whereisschool"
SIMCTL = ("xcrun", "simctl")


def run(*args, timeout: int = 180, capture: bool = False) -> str:
    return subprocess.run(args, check=True, timeout=timeout, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout or ""


def inventory() -> dict:
    return json.loads(run(*SIMCTL, "list", "-j", capture=True))


def ios_version(identifier: str) -> tuple[int, ...]:
    match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+(?:-\d+)*)", identifier)
    return tuple(map(int, match[1].split("-"))) if match else ()


def devices(data: dict) -> list[dict]:
    rows = [dict(row, runtime=ios_version(runtime)) for runtime, group in data["devices"].items()
            for row in group if ios_version(runtime) and row["isAvailable"]]
    return sorted(rows, key=lambda row: (row["state"] == "Booted", row["runtime"], row["name"].startswith("iPhone")),
                  reverse=True)


def label(row: dict) -> str:
    return f"{row['name']} (iOS {'.'.join(map(str, row['runtime']))}, {row['state']}) — {row['udid']}"


def available_runtimes(data: dict) -> list[dict]:
    return sorted((rt for rt in data["runtimes"] if ios_version(rt["identifier"]) and rt["isAvailable"]),
                  key=lambda rt: ios_version(rt["identifier"]), reverse=True)


def choose(rows: list[dict], device: str | None, non_interactive: bool) -> dict:
    if not rows:
        raise ValueError("No iOS Simulator devices. Add an iPhone/iPad in Xcode > Window > Devices and Simulators.")
    if device:
        matches = [row for row in rows if row["udid"].casefold() == device.casefold() or row["name"] == device]
        if len(matches) != 1:
            raise ValueError("Choose an unambiguous iPhone/iPad UDID from --list.")
        return matches[0]
    if len(rows) == 1 or non_interactive:
        return rows[0]
    for index, row in enumerate(rows, 1):
        print(f"[{index}] {label(row)}")
    answer = input("Simulator number [1]: ").strip() or "1"
    if not answer.isdecimal() or not 1 <= int(answer) <= len(rows):
        raise ValueError("Invalid simulator number.")
    return rows[int(answer) - 1]


def build_and_launch(args: argparse.Namespace, godot: Path, row: dict) -> None:
    udid = row["udid"]
    if args.output is None:
        parent = ROOT / "build/mobile/ios-simulator"
        parent.mkdir(parents=True, exist_ok=True)
        out = Path(tempfile.mkdtemp(prefix="run-", dir=parent))
    else:
        out = args.output.resolve()
    print(f"Simulator: {label(row)}\nBuild and logs: {out}", flush=True)
    run(sys.executable, ROOT / "tools/export_mobile.py", "ios-simulator", "--godot", godot, "--output", out, timeout=900)
    record = json.loads((out / "BUILD.json").read_text())
    app = out / record["artifact"]
    if record["target"] != "ios-simulator" or not app.is_dir():
        raise ValueError("No verified Simulator application was produced.")
    if args.build_only:
        return
    started = False
    try:
        if row["state"] != "Booted":
            run(*SIMCTL, "boot", udid)
            started = True
        run(*SIMCTL, "bootstatus", udid, "-b", timeout=420)
        run(*SIMCTL, "install", udid, app)
        result = run(*SIMCTL, "launch", "--terminate-running-process", udid, BUNDLE, capture=True)
        (out / "launch.txt").write_text(result, encoding="utf-8")
        match = re.search(rf"^{re.escape(BUNDLE)}: (\d+)$", result, flags=re.M)
        if not match:
            raise ValueError("simctl did not return the game's process ID; see launch.txt.")
        pid = int(match[1])
        predicate = f'processIdentifier == {pid} AND subsystem == "{BUNDLE}"'
        deadline = time.monotonic() + 60
        while True:
            os.kill(pid, 0)  # Simulator processes run on the host under the current user.
            logs = run(*SIMCTL, "spawn", udid, "log", "show", "--last", "2m", "--style", "compact", "--info",
                       "--predicate", predicate, capture=True, timeout=20)
            (out / "runtime.log").write_text(logs, encoding="utf-8")
            if re.search(r"SCRIPT ERROR|Parse Error|Failed to load script", logs, re.I):
                raise ValueError("Godot runtime errors; see runtime.log.")
            if re.search(r"OpenGL (API|ES)|Compatibility.*Renderer", logs, re.I):
                break
            if time.monotonic() >= deadline:
                raise ValueError("Godot did not report the Simulator Compatibility renderer; see runtime.log.")
            time.sleep(2)
        run(*SIMCTL, "io", udid, "screenshot", out / "title.png")
        os.kill(pid, 0)
        print(f"PASS: iOS Simulator app installed and reached Godot's renderer. Evidence: {out}")
        if not args.no_open:
            run("open", "-a", "Simulator", "--args", "-CurrentDeviceUDID", udid)
            print(f"To attach Xcode: open '{out / 'where-is-school.xcodeproj'}', select {row['name']} and run or attach.")
    finally:
        if args.shutdown and started:
            run(*SIMCTL, "shutdown", udid)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--list", action="store_true", help="list available iPhone/iPad simulators only")
    modes.add_argument("--setup-only", action="store_true", help="prepare Xcode runtime and Godot without building")
    modes.add_argument("--build-only", action="store_true", help="produce a Simulator .app without launching")
    parser.add_argument("--device", help="simulator UDID or unique name from --list")
    parser.add_argument("--no-download", action="store_true", help="use only already-installed dependencies")
    parser.add_argument("--update-runtime", action="store_true", help="ask Xcode to download its current iOS runtime")
    parser.add_argument("--godot", help="use this pinned official Godot executable instead of downloading it")
    parser.add_argument("--output", type=Path, help="empty directory for the app and evidence")
    parser.add_argument("--non-interactive", action="store_true", help="choose a booted or recent iOS device automatically")
    parser.add_argument("--no-open", action="store_true", help="do not open the Simulator GUI")
    parser.add_argument("--shutdown", action="store_true", help="shut down only the simulator started by this run")
    args = parser.parse_args()
    try:
        xcode_check()
        data = inventory()
        if args.list:
            for row in devices(data):
                print(label(row))
            if not devices(data):
                raise ValueError("No iOS Simulator devices; run --setup-only first.")
            return 0
        if args.update_runtime or not available_runtimes(data):
            if args.no_download:
                raise ValueError("No usable runtime (or --update-runtime requested); downloads are disabled.")
            run("xcodebuild", "-downloadPlatform", "iOS", timeout=3600)
            data = inventory()
        rows = devices(data)
        if not rows and not args.device and not args.no_download:
            runtimes = available_runtimes(data)
            if runtimes:
                models = [model for model in runtimes[0].get("supportedDeviceTypes", [])
                          if model["name"].startswith("iPhone")]
                if models:
                    run(*SIMCTL, "create", "Where is school iPhone", models[-1]["identifier"], runtimes[0]["identifier"])
                    rows = devices(inventory())
        chosen = choose(rows, args.device, args.non_interactive or args.setup_only or args.build_only)
        godot = prepare_godot(args.godot, no_download=args.no_download)
        if args.setup_only:
            print(f"Ready: {godot}. Default simulator: {label(chosen)}")
        else:
            build_and_launch(args, godot, chosen)
        return 0
    except (OSError, ValueError, KeyError, EOFError, BadZipFile, subprocess.SubprocessError) as error:
        print(f"iOS simulator failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
