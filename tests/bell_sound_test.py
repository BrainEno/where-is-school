#!/usr/bin/env python3
"""Proves the school bell sounds like a bell and not like a beep.

The bell this replaces was two sine waves 52 Hz apart with a square-wave tremolo on them. It
was audible, it was short, and it was wrong in a way that no listening test in CI could catch:
it is a *synthesiser*, and a school bell is four pieces of metal being hit in a corridor.

What can be checked without speakers is the structure that makes the difference, and all of it
is measurable from the buffer:

1. **It is long enough to be a phrase.** A bell that rings four notes is not 2 seconds long.
2. **It has onsets.** A struck bar starts loud and decays; four of them in a row give the
   amplitude envelope a shape. A drone or a sine does not have one.
3. **Its partials are inharmonic.** This is the whole timbre argument. A bar's modes sit near
   2.76x and 5.40x the fundamental, not at 2x and 3x. If the buffer's energy at 2x exceeds its
   energy at 2.76x, what was generated is a harmonic series - a synth - whatever it looks like
   in the code.
4. **It is not clipped and not silent**, and the file is deterministic.

Run it with ``python3 tests/bell_sound_test.py``.
"""

from __future__ import annotations

import math
import os
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BELL = ROOT / "assets" / "audio" / "bell_second.wav"
GENERATOR = ROOT / "tools" / "generate_placeholder_audio.py"

## A phrase of four struck notes, twice, with the tail of the last one. Below this the file
## cannot be the bell being described.
MIN_SECONDS = 5.0
## The envelope has to show the strikes. Four notes played twice is eight; the last of each
## phrase decays into the next, so the count is a range rather than a number.
MIN_ONSETS = 5
## Above this the buffer is clipping, and a clipped bell is a buzz.
MAX_PEAK = 0.99
## The timbre test: the second mode of a struck bar is near 2.756x the first, and the second
## harmonic of a synth is at 2.0x. The margin is not delicate - they are different sounds.
INHARMONIC_RATIO = 2.756

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


def read_wav(path: Path) -> tuple[list[float], int]:
    handle = wave.open(str(path), "rb")
    try:
        frames = handle.getnframes()
        rate = handle.getframerate()
        raw = handle.readframes(frames)
    finally:
        handle.close()
    samples = struct.unpack("<%dh" % (len(raw) // 2), raw)
    return [value / 32768.0 for value in samples], rate


def envelope(samples: list[float], rate: int, bin_seconds: float = 0.1) -> list[float]:
    step = max(int(bin_seconds * rate), 1)
    out = []
    for start in range(0, len(samples) - step, step):
        window = samples[start : start + step]
        out.append(math.sqrt(sum(value * value for value in window) / len(window)))
    return out


def onsets(levels: list[float], floor: float = 0.05) -> list[int]:
    """Local maxima of the envelope, above a floor: one per strike that is audible."""
    found = []
    for index in range(1, len(levels) - 1):
        if levels[index] > levels[index - 1] and levels[index] >= levels[index + 1]:
            if levels[index] > floor:
                found.append(index)
    return found


def magnitude(samples: list[float], rate: int, frequency: float) -> float:
    real = 0.0
    imaginary = 0.0
    for index, value in enumerate(samples):
        angle = 2.0 * math.pi * frequency * index / rate
        real += value * math.cos(angle)
        imaginary -= value * math.sin(angle)
    return math.hypot(real, imaginary) / max(len(samples), 1)


def check_buffer() -> None:
    check(BELL.exists(), f"the bell buffer is missing: {BELL.relative_to(ROOT)}")
    if not BELL.exists():
        return
    samples, rate = read_wav(BELL)
    seconds = len(samples) / float(rate)
    peak = max((abs(value) for value in samples), default=0.0)
    check(
        seconds >= MIN_SECONDS,
        f"the bell is {seconds:.2f} s; a four-note phrase twice is not shorter than "
        f"{MIN_SECONDS:.1f} s",
    )
    check(peak <= MAX_PEAK, f"the bell peaks at {peak:.2f}; it is clipping")
    check(peak > 0.2, f"the bell peaks at {peak:.2f}; it is effectively silent")

    levels = envelope(samples, rate)
    strikes = onsets(levels)
    check(
        len(strikes) >= MIN_ONSETS,
        f"the envelope shows {len(strikes)} strike(s); four notes played twice needs at least "
        f"{MIN_ONSETS}. A buffer with no envelope shape is a tone, not a struck bar",
    )

    # The first note, measured where it is still ringing and before the next one lands.
    first = samples[int(0.02 * rate) : int(0.42 * rate)]
    fundamental = 587.33  # D5, the first of D5 B4 G4 A4
    second_harmonic = magnitude(first, rate, fundamental * 2.0)
    inharmonic = magnitude(first, rate, fundamental * INHARMONIC_RATIO)
    check(
        inharmonic > second_harmonic,
        f"the first note's energy at {INHARMONIC_RATIO}x the fundamental ({inharmonic:.4f}) "
        f"does not exceed its energy at 2x ({second_harmonic:.4f}). The partials are harmonic, "
        "so this is a tone with an envelope rather than a struck bar",
    )


def check_deterministic() -> None:
    """The script is the provenance: same bytes every run, so a diff means a real change."""
    if not GENERATOR.exists():
        return
    with tempfile.TemporaryDirectory() as scratch:
        environment = dict(os.environ, WIS_AUDIO_OUT=scratch)
        result = subprocess.run(
            [sys.executable, str(GENERATOR)],
            capture_output=True,
            text=True,
            env=environment,
        )
        if result.returncode != 0:
            failures.append(
                "the generator did not run: "
                + (result.stderr.strip().splitlines() or ["?"])[-1]
            )
            return
        produced = Path(scratch) / "bell_second.wav"
        check(produced.exists(), "the generator did not write bell_second.wav")
        if not produced.exists():
            return
        check(
            produced.read_bytes() == BELL.read_bytes(),
            "regenerating the bell produced different bytes; the file is not the script's output",
        )


def main() -> int:
    check_buffer()
    check_deterministic()
    if failures:
        for failure in failures:
            print(f"BELL_SOUND_FAILURE: {failure}")
        print(f"FAIL: {len(failures)} problem(s) found.")
        return 1
    print("BELL_SOUND: the bell is a phrase of struck inharmonic bars with an envelope.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
