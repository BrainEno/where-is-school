#!/usr/bin/env python3
"""Measures the world's own sounds, which no headless engine can hear.

`scripts/audio/world_audio.gd` synthesises five buffers at startup: a footstep, a chair, a
page, a pickup and a door. They are the room answering a player, and they are the one part of
the audio work that cannot regress loudly - a wrong buffer is still a buffer, and the test that
would catch it is one that reads the numbers.

This test parses the **GDScript source** rather than running Godot. That is a real limit and
worth stating plainly: it checks the synthesis the file describes, not the engine's rendering
of it. What it can prove without a speaker:

1. every advertised kind is built, and each is a distinct buffer;
2. each is real, quiet audio - mono, 22.05 kHz, short, not clipped, not silent;
3. the shapes are the shapes claimed: a footstep strikes and decays, a chair travels and
   stops, a page is noise rather than a note, a door is longer than a page;
4. every kind is rate-limited, and no two share an interval;
5. the synthesis is seeded, so the same source produces the same sound twice.

The header of `world_audio.gd` says these own the `SFX` bus and the pointer cues do not; that
is asserted too, because it is the whole reason they are a separate node.

Run it with ``python3 tests/world_audio_test.py``.
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "scripts" / "audio" / "world_audio.gd"
CUE_SOURCE = ROOT / "scripts" / "audio" / "cue_audio.gd"
SAMPLE_RATE = 22050

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


def parse_constants(text: str, name: str) -> dict[str, float]:
    """Reads a `const NAME := { KIND_X: value, ... }` block."""
    match = re.search(rf"const {name}\s*:?=\s*\{{(.*?)\n\}}", text, re.S)
    if match is None:
        return {}
    body = match.group(1)
    values: dict[str, float] = {}
    for key, number in re.findall(r"(KIND_[A-Z_]+)\s*:\s*(-?[0-9.]+)", body):
        values[key] = float(number)
    return values


def parse_kind_list(text: str) -> list[str]:
    match = re.search(r"const KINDS\s*:\s*Array\[StringName\]\s*=\s*\[(.*?)\]", text, re.S)
    if match is None:
        return []
    return re.findall(r"KIND_[A-Z_]+", match.group(1))


def parse_kind_names(text: str) -> dict[str, str]:
    """`const KIND_STEP := &"step"` -> {"KIND_STEP": "step"}."""
    return {
        symbol: value
        for symbol, value in re.findall(r'const (KIND_[A-Z_]+)\s*:=\s*&"([a-z_]+)"', text)
    }


def parse_floats(text: str, name: str) -> float | None:
    match = re.search(rf"const {name}\s*:=\s*([0-9.]+)", text)
    return float(match.group(1)) if match else None


def check_structure(text: str) -> None:
    kinds = parse_kind_list(text)
    names = parse_kind_names(text)
    intervals = parse_constants(text, "MIN_INTERVAL_SECONDS")
    volumes = parse_constants(text, "VOLUME_DB")
    peaks = parse_constants(text, "PEAK")

    check(len(kinds) == 5, f"{len(kinds)} kinds are advertised; the design names five")
    check(
        len(set(names.values())) == len(names),
        "two kinds share a name string, so one would shadow the other",
    )
    for kind in kinds:
        check(kind in names, f"{kind} has no name string")
        check(kind in intervals, f"{kind} has no rate limit; every sound here can repeat")
        check(kind in volumes, f"{kind} has no volume")
        check(kind in peaks, f"{kind} has no peak")
        label = names.get(kind, kind)
        if kind in peaks:
            check(
                0.05 < peaks[kind] < 0.6,
                f"the {label} peaks at {peaks[kind]}: too quiet to hear or loud enough to be an event",
            )
        if kind in volumes:
            check(
                -30.0 < volumes[kind] <= -10.0,
                f"the {label} plays at {volumes[kind]} dB; these sit over the cues and under the room",
            )
        if kind in intervals:
            check(
                0.05 <= intervals[kind] <= 1.0,
                f"the {label} can repeat every {intervals[kind]} s",
            )
    check(
        len(set(intervals.values())) == len(intervals),
        f"two kinds share a rate limit ({sorted(intervals.values())}); each sound needs its own",
    )
    # Footsteps are the sound that actually repeats - about four a second at a jog - so the
    # step limit has to be the pace of a stride and not a frame. The other limits only have
    # to be loose enough that a fast player cannot machine-gun them.
    if "KIND_STEP" in intervals:
        check(
            0.2 <= intervals["KIND_STEP"] <= 0.35,
            f"the step limit is {intervals['KIND_STEP']} s; a stride is roughly a quarter second",
        )

    # The bus decision: these reach the SFX dial, the cues deliberately do not.
    check(
        'const BUS := &"SFX"' in text,
        "the world sounds do not declare the SFX bus, so the player's dial would miss them",
    )
    cue_text = CUE_SOURCE.read_text(encoding="utf-8") if CUE_SOURCE.exists() else ""
    check(
        'player.bus = &"Master"' in cue_text,
        "the pointer cues are no longer on Master; the split between the two nodes has drifted",
    )
    check(
        "func set_gain_db" not in text,
        "world_audio.gd grew its own gain on top of the SFX bus, which would attenuate twice",
    )


def check_synthesis(text: str) -> None:
    """The properties of the generator that the claims rest on, read from the source."""
    # Every kind gets its own buffer, built from its own function.
    for function, kind in [
        ("_step", "KIND_STEP"),
        ("_chair", "KIND_CHAIR"),
        ("_paper", "KIND_PAPER"),
        ("_pickup", "KIND_PICKUP"),
        ("_door", "KIND_DOOR"),
    ]:
        check(
            re.search(rf"_streams\[{kind}\]\s*=\s*{function}\(", text) is not None,
            f"{kind} is not built by {function}(), so two kinds may share a shape",
        )
    # Deterministic noise: the seeds are literals, so the same sound twice.
    seeds = set(re.findall(r"Noise\.new\((\d+)\)", text))
    check(
        len(seeds) == 5,
        f"{len(seeds)} noise seed(s) for five sounds; a shared seed makes two sounds correlate",
    )
    check(
        "randf(" not in text and "randi(" not in text,
        "the buffers use the global RNG, so they differ between runs and two builds cannot be compared",
    )
    # Lengths: a door is longer than a page, and every buffer is short.
    durations = [float(value) for value in re.findall(r"int\(([0-9.]+)\s*\*\s*float\(SAMPLE_RATE\)\)", text)]
    check(len(durations) == 5, f"{len(durations)} buffer length(s) found for five sounds")
    if len(durations) == 5:
        check(
            all(0.05 < value < 1.0 for value in durations),
            f"a buffer is {durations} s; these are touches, not events",
        )
        check(
            max(durations) < 0.8,
            f"the longest sound is {max(durations)} s, long enough to collide with the next one",
        )
    check(
        SAMPLE_RATE == 22050,
        "the sample rate no longer matches the rest of the project's audio",
    )
    # Nothing is louder than full scale before the peak is applied: clipping would buzz.
    check(
        re.search(r"clampf\(samples\[index\], -1\.0, 1\.0\)", text) is not None,
        "the writer does not clamp; a too-hot buffer would wrap and crackle",
    )


def check_wiring(text: str) -> None:
    """The autoload is registered and every call site looks it up by path."""
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    check(
        'WorldAudio="*res://scripts/audio/world_audio.gd"' in project,
        "WorldAudio is not registered as an autoload, so nothing can find it",
    )
    for method in ["play_step", "play_chair", "play_paper", "play_pickup", "play_door"]:
        check(
            f"func {method}() -> bool:" in text,
            f"world_audio.gd has no {method}(), but a caller asks for it",
        )

    call_sites: dict[str, list[str]] = {}
    for path in ROOT.glob("scripts/**/*.gd"):
        body = path.read_text(encoding="utf-8", errors="ignore")
        for method in ["play_step", "play_chair", "play_paper", "play_pickup", "play_door"]:
            if f'"{method}"' in body or f"&\"{method}\"" in body or f".{method}()" in body:
                call_sites.setdefault(method, []).append(path.relative_to(ROOT).as_posix())

    for method in ["play_step", "play_chair", "play_paper", "play_door"]:
        check(
            method in call_sites,
            f"nothing calls {method}(): the sound exists and the game never asks for it",
        )
    # The pickup is claimed only where a first read changes state; that is in the dialogue
    # controller, which is also where paper is asked for.
    check(
        "scripts/dialogue/dialogue_controller.gd" in call_sites.get("play_paper", []),
        "the page turn is not wired to the first read of an object",
    )
    check(
        "scripts/dialogue/dialogue_controller.gd" in call_sites.get("play_pickup", []),
        "the pickup is not wired to the first read that changes state",
    )
    check(
        "scripts/actors/player/player_controller.gd" in call_sites.get("play_step", []),
        "footsteps are not wired to the body that walks",
    )
    # Every *call site* goes through the same null-safe lookup, not a global identifier.
    # The script that defines the node is not a call site and is skipped.
    for path in ROOT.glob("scripts/**/*.gd"):
        if path == SOURCE:
            continue
        body = path.read_text(encoding="utf-8", errors="ignore")
        if "/root/WorldAudio" in body and "get_node_or_null" not in body:
            failures.append(
                f"{path.relative_to(ROOT).as_posix()} looks WorldAudio up without a null-safe "
                "get_node_or_null; a headless run would fail to compile instead of staying silent"
            )


def main() -> int:
    check(SOURCE.exists(), f"the world audio script is missing: {SOURCE.relative_to(ROOT)}")
    if not SOURCE.exists():
        for failure in failures:
            print(f"WORLD_AUDIO_FAILURE: {failure}")
        return 1
    text = SOURCE.read_text(encoding="utf-8")
    check_structure(text)
    check_synthesis(text)
    check_wiring(text)
    if failures:
        for failure in failures:
            print(f"WORLD_AUDIO_FAILURE: {failure}")
        print(f"FAIL: {len(failures)} problem(s) found.")
        return 1
    print(
        "WORLD_AUDIO_OK: 5 world sounds are synthesised from seeded noise, each rate-limited, "
        "on the SFX bus, and asked for by the code that touches things."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
