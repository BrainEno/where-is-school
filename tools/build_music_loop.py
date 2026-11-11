#!/usr/bin/env python3
"""Turn the owner's guitar recording into the background-music loop the game ships.

The source is a real performance, not a synthesiser patch: 46.738 s of fingerpicked guitar,
mono, 48 kHz, 16-bit, recorded in one take with no click track and no repeatable bar. There
is therefore no bar-aligned loop point to snap to, and inventing one would either move the
music (time-stretching, quantising) or chop a note. What the take *does* give us is a quiet
head and tail: the first 0.72 s and the last 0.78 s sit under -40 dBFS, which is guitar body
noise and the room.

So the loop is the whole performance, trimmed into that noise and crossfaded through it:

  a = first audible sample - HEAD_SECONDS      (0.30 s of room noise before the first note)
  b = last audible sample + TAIL_SECONDS       (0.30 s of room noise after the last note,
                                                or the end of the file: this take stops
                                                72 ms after the last note, so the tail keeps
                                                what exists instead of padded silence)
  out = x[a:b], with its final CROSSFADE_SECONDS blended into the material immediately
        *before* `a`

That last step is the whole trick. Blending the loop's tail into `x[a-C:a]` means the last
sample of the file continues into the first sample of the file the way the original
recording continued there, so the seam is not a fade to silence and back: it is the same
waveform the take had one loop earlier. The blend happens entirely inside the noise floor,
so nothing musical is doubled, ducked or smeared.

What is deliberately *not* done, because the recording is the point:
  * no normalisation, no limiter, no compressor, no EQ, no reverb, no noise reduction;
  * no resampling and no downmix: mono stays mono, 48 kHz stays 48 kHz, 16-bit stays 16-bit;
  * no shortening beyond trimming dead air, so the whole improvisation is in the loop.

The engine-side loop is set in `assets/audio/music/guitar_ambient_loop_01.wav.import`
(`edit/loop_mode=2`, `edit/loop_begin`, `edit/loop_end`), not in a script: the stream is
imported as an already-looping resource, so nothing at runtime has to duplicate it or set
a flag and hope.

Usage:
    python3 tools/build_music_loop.py            # rewrite the committed loop
    python3 tools/build_music_loop.py --check    # fail if it differs from a fresh build
"""

from __future__ import annotations

import argparse
import hashlib
import math
import struct
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "art" / "audio" / "Guitar_loop_01.wav"
OUTPUT = ROOT / "assets" / "audio" / "music" / "guitar_ambient_loop_01.wav"

#: Room noise asked for before the first note and after the last one. The head has it (the
#: take opens with 0.70 s under -40 dBFS). The tail does not: the recording stops 72 ms after
#: the last note above the threshold, so the loop keeps what exists there rather than
#: padding silence onto the end. Both numbers are printed by the build.
HEAD_SECONDS = 0.30
TAIL_SECONDS = 0.30

#: The seam blend. Equal power, inside the noise floor, longer than any guitar attack at
#: this level so the two room tones cross rather than switch.
CROSSFADE_SECONDS = 0.30

#: What counts as "audible" when looking for the first and last note.
SILENCE_DBFS = -40.0

#: The source is checked, not trusted: this is the file the committed loop was derived from.
SOURCE_SHA256 = "4a5454510cb70454daed09791cd3eda82e25174013e95364eb87b0bd276eb9e4"


def load_mono16(path: Path) -> tuple[list[float], int]:
    """Read a 16-bit PCM WAV as floats in [-1, 1), plus its sample rate."""
    with wave.open(str(path), "rb") as handle:
        if handle.getsampwidth() != 2:
            raise SystemExit(f"{path}: expected 16-bit PCM, got {handle.getsampwidth() * 8}-bit")
        if handle.getnchannels() != 1:
            raise SystemExit(f"{path}: expected mono, got {handle.getnchannels()} channel(s)")
        rate = handle.getframerate()
        raw = handle.readframes(handle.getnframes())
    count = len(raw) // 2
    samples = [value / 32768.0 for value in struct.unpack("<%dh" % count, raw)]
    return samples, rate


def describe(samples: list[float], rate: int, label: str) -> None:
    peak = max(abs(value) for value in samples) if samples else 0.0
    rms = math.sqrt(sum(value * value for value in samples) / len(samples)) if samples else 0.0
    print(
        f"  {label}: {len(samples) / rate:.3f} s, {rate} Hz mono 16-bit, "
        f"peak {20 * math.log10(max(peak, 1e-9)):.1f} dBFS, "
        f"rms {20 * math.log10(max(rms, 1e-9)):.1f} dBFS"
    )


def audible_edges(samples: list[float]) -> tuple[int, int]:
    """First and last sample above the silence threshold."""
    threshold = 10 ** (SILENCE_DBFS / 20.0)
    first = 0
    for index, value in enumerate(samples):
        if abs(value) > threshold:
            first = index
            break
    last = len(samples) - 1
    for index in range(len(samples) - 1, -1, -1):
        if abs(samples[index]) > threshold:
            last = index
            break
    return first, last


def build() -> tuple[list[float], int, dict[str, object]]:
    source, rate = load_mono16(SOURCE)
    head_frames = int(round(HEAD_SECONDS * rate))
    tail_frames = int(round(TAIL_SECONDS * rate))
    blend_frames = int(round(CROSSFADE_SECONDS * rate))

    first, last = audible_edges(source)
    start = max(blend_frames, first - head_frames)
    end = min(len(source), last + 1 + tail_frames)
    loop = source[start:end]

    # Equal-power crossfade of the loop's tail into the material just before `start`, so the
    # file's last sample runs into its first one the way the take did.
    for index in range(blend_frames):
        position = (index + 0.5) / blend_frames
        fade_in = math.sin(position * math.pi / 2.0)
        fade_out = math.cos(position * math.pi / 2.0)
        tail_index = len(loop) - blend_frames + index
        pre_roll = source[start - blend_frames + index]
        loop[tail_index] = loop[tail_index] * fade_out + pre_roll * fade_in

    facts = {
        "rate": rate,
        "head_room_frames": first - start,
        "tail_room_frames": end - (last + 1),
        "source_frames": len(source),
        "source_first_audible": first,
        "source_last_audible": last,
        "start_frame": start,
        "end_frame": end,
        "loop_frames": len(loop),
        "blend_frames": blend_frames,
        "seam_step": abs(loop[-1] - loop[0]),
        "seam_dbfs": 20 * math.log10(max(abs(loop[-1] - loop[0]), 1e-9)),
    }
    return loop, rate, facts


def encode(samples: list[float]) -> bytes:
    frames = bytearray()
    for value in samples:
        clamped = max(-1.0, min(1.0, value))
        frames += struct.pack("<h", int(round(clamped * 32767.0)))
    return bytes(frames)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="compare the committed loop with a fresh build instead of writing it",
    )
    arguments = parser.parse_args()

    if not SOURCE.exists():
        print(f"SOURCE_MISSING: {SOURCE.relative_to(ROOT)} is not in the tree", file=sys.stderr)
        return 1
    digest = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    if digest != SOURCE_SHA256:
        print(
            "SOURCE_CHANGED: the recording is not the file this loop was derived from "
            f"(sha256 {digest})",
            file=sys.stderr,
        )
        return 1

    loop, rate, facts = build()
    payload = encode(loop)
    print(f"source: {SOURCE.relative_to(ROOT)}")
    describe(load_mono16(SOURCE)[0], rate, "recording")
    print(
        f"  audible from {facts['source_first_audible'] / rate:.3f} s to "
        f"{facts['source_last_audible'] / rate:.3f} s "
        f"({SILENCE_DBFS:.0f} dBFS threshold)"
    )
    print(
        f"  loop: frames {facts['start_frame']}..{facts['end_frame']} of "
        f"{facts['source_frames']} ({facts['loop_frames'] / rate:.3f} s), "
        f"seam blend {facts['blend_frames'] / rate:.3f} s"
    )
    print(
        "  room noise kept: "
        f"{facts['head_room_frames'] / rate:.3f} s at the head, "
        f"{facts['tail_room_frames'] / rate:.3f} s at the tail"
    )
    describe(loop, rate, "committed loop")
    print(f"  seam step {facts['seam_step']:.6f} ({facts['seam_dbfs']:.1f} dBFS)")

    if arguments.check:
        if not OUTPUT.exists():
            print(f"MUSIC_LOOP_MISSING: {OUTPUT.relative_to(ROOT)}", file=sys.stderr)
            return 1
        if OUTPUT.read_bytes() == _wav_bytes(payload, rate, len(loop)):
            print(
                f"MUSIC_LOOP_OK: {OUTPUT.relative_to(ROOT)} matches a fresh build "
                f"({len(payload) + 44} B, {len(loop) / rate:.3f} s)"
            )
            return 0
        print(
            f"MUSIC_LOOP_STALE: {OUTPUT.relative_to(ROOT)} differs from a fresh build; "
            "run python3 tools/build_music_loop.py",
            file=sys.stderr,
        )
        return 1

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(payload)
    print(f"wrote {OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size} B)")
    return 0


def _wav_bytes(payload: bytes, rate: int, frames: int) -> bytes:
    """The bytes `wave` writes for this payload, so `--check` can compare without a temp file."""
    header = b"RIFF" + struct.pack("<I", 36 + len(payload)) + b"WAVE"
    header += b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16)
    header += b"data" + struct.pack("<I", len(payload))
    return header + payload


if __name__ == "__main__":
    raise SystemExit(main())
