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
import os
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 22050
# `WIS_AUDIO_OUT` exists so a test can regenerate the set somewhere else and compare bytes
# without touching the repository. Unset, it writes the shipped files.
OUTPUT_DIR = Path(
    os.environ.get("WIS_AUDIO_OUT")
    or (Path(__file__).resolve().parent.parent / "assets" / "audio")
)


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


def _struck_bar(frequency: float, duration: float, decay: float, brightness: float) -> list[float]:
    """One struck metal bar, as it sounds before the room gets hold of it.

    What makes a struck bar read as metal rather than as a beep is that its partials are
    *not* whole multiples of the fundamental. A sine plus its octave is a synth; a bar's
    second mode sits near 2.76x the first, its third near 5.40x, and the high ones die away
    far faster than the low. Those three facts are the whole of the timbre, so they are here
    literally, with a short noise burst on the strike itself - the hammer, not the bar.
    """
    total = int(duration * SAMPLE_RATE)
    samples = []
    rng = random.Random(int(frequency))
    modes = (
        (1.0, 1.0, 1.0),
        (2.756, 0.5, 0.55),
        (5.404, 0.26, 0.32),
        (8.933, 0.14, 0.18),
        (13.35, 0.07, 0.10),
    )
    for index in range(total):
        time = index / SAMPLE_RATE
        value = 0.0
        for ratio, gain, lifetime in modes:
            partial = frequency * ratio
            if partial >= SAMPLE_RATE * 0.5:
                continue
            value += gain * math.exp(-time / (decay * lifetime)) * math.sin(
                2.0 * math.pi * partial * time
            )
        # The strike: 6 ms of filtered noise, gone before the ear can call it noise.
        strike = math.exp(-time / 0.006) * rng.uniform(-1.0, 1.0) * 0.22
        # A 1.5 ms attack, so the first sample is not a step.
        attack = min(1.0, time / 0.0015)
        samples.append((value * brightness + strike) * attack)
    return samples


def _room(samples: list[float], taps: tuple[tuple[float, float], ...]) -> list[float]:
    """Puts the bar in a corridor: a few early reflections, then a long soft tail.

    Built from the signal itself rather than from noise, because a reflection of a bell is
    still the bell. The taps are (delay in seconds, gain) and they are spaced unevenly on
    purpose - evenly spaced echoes sound like a machine and are the classic giveaway of a
    synthesised reverb.
    """
    out = list(samples)
    for delay, gain in taps:
        offset = int(delay * SAMPLE_RATE)
        if offset <= 0 or offset >= len(out):
            continue
        for index in range(len(out) - offset):
            out[index + offset] += samples[index] * gain
    return out


def _speaker(samples: list[float]) -> list[float]:
    """A wall speaker, not a hi-fi: band-limited, and a little driven.

    School bells come out of a horn behind a grille. That takes the very top away, keeps
    everything between roughly 300 Hz and 4 kHz, and adds a touch of saturation that a
    quiet playback level makes warm rather than harsh. The one-pole low-pass is applied
    twice, which is what turns a slope into a shelf.
    """
    lowpassed = []
    previous = 0.0
    coefficient = 0.55
    for value in samples:
        previous += (value - previous) * coefficient
        lowpassed.append(previous)
    previous = 0.0
    twice = []
    for value in lowpassed:
        previous += (value - previous) * coefficient
        twice.append(previous)
    # A high-pass at the bottom of the horn's range, so the tail does not muddy the room tone.
    out = []
    previous_in = 0.0
    previous_out = 0.0
    rc = 1.0 / (2.0 * math.pi * 260.0)
    dt = 1.0 / SAMPLE_RATE
    alpha = rc / (rc + dt)
    for value in twice:
        shaped = alpha * (previous_out + value - previous_in)
        previous_in = value
        previous_out = shaped
        out.append(math.tanh(shaped * 1.6) * 0.72)
    return out


def bell(duration: float = 7.4) -> list[float]:
    """The school's bell: four struck bars through a wall speaker in a corridor.

    This replaces a two-second sine with a tremolo on it, which was the sound of a machine
    beeping rather than of a school. What a real one does, and what is here:

    - four notes, in the Westminster order the Chinese school bell uses (a rising third,
      then a falling third, then the leading tone back to the tonic): D5, B4, G4, A4;
    - each note is a *struck bar*, so it has inharmonic partials and a hammer transient;
    - the notes overlap, because the bars ring into each other - the gap between them is
      0.62 s and a bar is still audible at 1.5 s;
    - the whole phrase repeats once, quieter and slightly later, which is the corridor
      answering;
    - all of it through the speaker filter, then into the room's reflections.

    The result is deterministic: same bytes every run, so the repository diff stays honest.
    """
    notes = (587.33, 493.88, 392.00, 440.00)  # D5 B4 G4 A4
    spacing = 0.62
    total = int(duration * SAMPLE_RATE)
    mix = [0.0] * total

    def place(phrase_start: float, gain: float, decay: float) -> None:
        for index, frequency in enumerate(notes):
            start = int((phrase_start + index * spacing) * SAMPLE_RATE)
            bar = _struck_bar(frequency, duration - phrase_start - index * spacing, decay, 1.0)
            for offset, value in enumerate(bar):
                target = start + offset
                if 0 <= target < total:
                    mix[target] += value * gain

    place(0.0, 1.0, 0.85)
    # The second pass: the corridor's answer, arriving late, quieter, and blurrier because it
    # has travelled. It is what makes the bell sound like it is somewhere, not in the ear.
    place(2.95, 0.34, 1.15)

    corridor = _room(
        mix,
        (
            (0.031, 0.34),
            (0.047, 0.27),
            (0.071, 0.21),
            (0.103, 0.16),
            (0.139, 0.12),
            (0.183, 0.09),
            (0.241, 0.07),
            (0.313, 0.05),
        ),
    )
    voiced = _speaker(corridor)

    # Fade the last 0.45 s so the file cannot click when it ends, and normalise to a peak the
    # scene's -9 dB player turns into a bell heard down a corridor rather than a fire alarm.
    fade = int(0.45 * SAMPLE_RATE)
    for index in range(min(fade, len(voiced))):
        voiced[len(voiced) - fade + index] *= 1.0 - index / fade
    peak = max((abs(value) for value in voiced), default=0.0)
    scale = (0.62 / peak) if peak > 0.0 else 0.0
    return [value * scale for value in voiced]


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
