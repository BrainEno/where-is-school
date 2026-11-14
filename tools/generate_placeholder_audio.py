#!/usr/bin/env python3
"""Generates the placeholder audio used by the biology-class slice.

The project has no licensed sound library (see docs/ASSET_PROVENANCE.md), so the
only audio in this milestone is synthesised here from scratch: a room tone for the
classroom, a duller walkway tone, a school bell, and the low thud that opens the
scene. Everything is mono 16-bit PCM so it stays small and portable.

Usage:
    python3 tools/generate_placeholder_audio.py
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 22050
OUTPUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio"


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for value in samples:
        clamped = max(-1.0, min(1.0, value))
        frames += struct.pack("<h", int(clamped * 32767))
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(bytes(frames))


def crossfade_loop(samples: list[float], fade_seconds: float = 0.25) -> list[float]:
    """Makes the buffer loop by mixing its tail back over its head."""
    fade = int(fade_seconds * SAMPLE_RATE)
    if fade * 2 >= len(samples):
        return samples
    for index in range(fade):
        mix = index / fade
        head = samples[index]
        tail = samples[len(samples) - fade + index]
        samples[index] = head * mix + tail * (1.0 - mix)
    return samples[: len(samples) - fade]


def room_tone(duration: float = 6.0, level: float = 0.055, air: float = 0.5) -> list[float]:
    rng = random.Random(7)
    total = int(duration * SAMPLE_RATE)
    samples = []
    for index in range(total):
        time = index / SAMPLE_RATE
        hum = (
            0.5 * math.sin(2 * math.pi * 50.0 * time)
            + 0.25 * math.sin(2 * math.pi * 100.0 * time + 0.4)
            + 0.12 * math.sin(2 * math.pi * 150.0 * time + 1.1)
        )
        noise = rng.uniform(-1.0, 1.0) * air * 0.35
        samples.append(level * (hum * 0.6 + noise))
    return crossfade_loop(samples)


def bell(duration: float = 2.0) -> list[float]:
    total = int(duration * SAMPLE_RATE)
    samples = []
    for index in range(total):
        time = index / SAMPLE_RATE
        envelope = math.exp(-2.4 * time)
        tremolo = 1.0 if math.sin(2 * math.pi * 22.0 * time) > 0 else 0.45
        tone = math.sin(2 * math.pi * 884.0 * time) + 0.7 * math.sin(2 * math.pi * 936.0 * time)
        tone += 0.25 * math.sin(2 * math.pi * 1768.0 * time)
        attack = min(1.0, time * 180.0)
        samples.append(0.26 * envelope * tremolo * attack * tone)
    return samples


def wake_thud(duration: float = 1.6) -> list[float]:
    total = int(duration * SAMPLE_RATE)
    samples = []
    rng = random.Random(11)
    for index in range(total):
        time = index / SAMPLE_RATE
        thud = math.exp(-6.0 * time) * math.sin(2 * math.pi * 62.0 * time)
        tick = math.exp(-40.0 * time) * rng.uniform(-1.0, 1.0) * 0.25
        breath = math.exp(-2.0 * max(0.0, time - 0.25)) * 0.05 * rng.uniform(-1.0, 1.0)
        samples.append(0.3 * thud + tick + breath)
    return samples


def laboratory_hum(duration: float = 6.0) -> list[float]:
    """The laboratory's bed: a mixer running somewhere, and the room it is in.

    Lower and heavier than the school's room tones, with a slow beat between two nearly
    equal low partials so the bed seems to turn over every few seconds. The room it belongs
    to has a large machine in the middle of it that nobody switches off, and this is the
    sound of that fact rather than a piece of music: no melody, no rhythm to speak of.
    """
    rng = random.Random(23)
    total = int(duration * SAMPLE_RATE)
    samples = []
    for index in range(total):
        time = index / SAMPLE_RATE
        # 54 and 55 Hz beat against each other about once a second; 108 and 162 give the
        # hum a body without turning it into a chord.
        hum = (
            0.55 * math.sin(2 * math.pi * 54.0 * time)
            + 0.30 * math.sin(2 * math.pi * 55.0 * time + 0.7)
            + 0.18 * math.sin(2 * math.pi * 108.0 * time + 0.3)
            + 0.08 * math.sin(2 * math.pi * 162.0 * time + 1.9)
        )
        # Air: a low-passed noise floor, quieter than the school tones' air so the hum reads.
        flutter = 0.06 * math.sin(2 * math.pi * 0.5 * time)
        noise = rng.uniform(-1.0, 1.0) * 0.22
        samples.append(0.075 * (hum * (0.85 + flutter) + noise))
    return crossfade_loop(samples)


def main() -> None:
    write_wav(OUTPUT_DIR / "room_tone_classroom.wav", room_tone())
    write_wav(OUTPUT_DIR / "room_tone_walkway.wav", room_tone(level=0.04, air=0.9))
    write_wav(OUTPUT_DIR / "bell_second.wav", bell())
    write_wav(OUTPUT_DIR / "wake_thud.wav", wake_thud())
    write_wav(OUTPUT_DIR / "laboratory_hum.wav", laboratory_hum())
    print("Wrote placeholder audio to", OUTPUT_DIR)


if __name__ == "__main__":
    main()
