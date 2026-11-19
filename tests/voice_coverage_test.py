#!/usr/bin/env python3
"""Proves every shipped voice clip says the line it is played for.

The bug this exists to catch had nothing to do with audio quality. Four clips sat in
``assets/audio/voice/zh-CN/`` with promising names - ``q_wake_q_1.mp3`` and friends - and were
0.05 to 0.28 seconds long. The lines they answered are two-second sentences. The game played
them, so a character opened their mouth, said "tick", and kept talking in text for another two
seconds. Nobody could hear what was wrong from the code; you had to hold the clip up against
the line.

There were two separate faults, and this checks both:

1. **A clip that is not speech.** A voice clip has to be long enough to say its line. Speech
   runs at a human rate, so the line's character count gives a floor and a ceiling: too short
   and the clip is a fragment, too long and it is a different sentence. Both are failures.
2. **A clip nothing can reach.** :func:`voice_director.resolve_clip_path` looks for
   ``<conversation_id>_<node_id>[.mp3|.ogg|.wav]``. A file called ``prologue_n1.mp3`` matches
   no line, so it is never played - it is a voice nobody will ever hear, and it hides the fact
   that the line it was meant for is unvoiced.

The dialogue tables are the source of truth: every clip is checked against the text the game
would show while playing it. Add a line and record a clip for it, and this holds; rename a node
and the clip becomes an orphan, which is the failure.

Run it with ``python3 tests/voice_coverage_test.py``.
"""

from __future__ import annotations

import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VOICE_DIR = ROOT / "assets" / "audio" / "voice"
DIALOGUE_DIR = ROOT / "data" / "dialogue"
INSPECTION_DIR = ROOT / "data" / "inspections"

## Mandarin syllables land between these, in characters per second, read at the pace the game
## uses for its reading band. Deliberately wide: the point is to catch a 0.12 s clip answering
## a nine-character line, not to grade a performance.
MIN_CHARS_PER_SECOND = 2.0
MAX_CHARS_PER_SECOND = 9.5

## A clip also needs a little air: the shortest real line, said briskly, still has an attack,
## a vowel and a tail. Below this it is a fragment whatever the arithmetic says.
MIN_CLIP_SECONDS = 0.45

## Punctuation that is spoken, and the silence it tends to carry. Used only to widen what
## counts as a plausible duration - a line full of commas is slower than one without.
PAUSE_CHARS = "，。！？、；：…—,.!?;:"

MP3_BITRATES_V1L3 = {
    1: 32, 2: 40, 3: 48, 4: 56, 5: 64, 6: 80, 7: 96,
    8: 112, 9: 128, 10: 160, 11: 192, 12: 224, 13: 256, 14: 320,
}
MP3_SAMPLE_RATES = {0: 44100, 1: 48000, 2: 32000}


def mp3_seconds(path: Path) -> float:
    """Duration of an MPEG-1 Layer III file, by walking its frames.

    There is no decoder in this repository's toolchain and none is wanted: the frame header
    carries everything needed to know how long the clip is, and that is the only property
    under test.
    """
    data = path.read_bytes()
    index = 0
    if data[:3] == b"ID3":
        index = 10 + struct.unpack(">I", b"\x00" + data[6:9])[0]
    seconds = 0.0
    while index < len(data) - 4:
        if data[index] != 0xFF or (data[index + 1] & 0xE0) != 0xE0:
            index += 1
            continue
        version = (data[index + 1] >> 3) & 3
        layer = (data[index + 1] >> 1) & 3
        bitrate_index = (data[index + 2] >> 4) & 0xF
        rate_index = (data[index + 2] >> 2) & 3
        if version != 3 or layer != 1 or bitrate_index in (0, 15) or rate_index == 3:
            index += 1
            continue
        bitrate = MP3_BITRATES_V1L3.get(bitrate_index, 128) * 1000
        rate = MP3_SAMPLE_RATES.get(rate_index, 44100)
        padding = (data[index + 2] >> 1) & 1
        seconds += 1152.0 / rate
        index += int(144 * bitrate / rate) + padding
    return seconds


def wave_seconds(path: Path) -> float:
    """Duration of a PCM WAV, read straight from its fmt/data chunks."""
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return 0.0
    index = 12
    rate = channels = bits = 0
    while index + 8 <= len(data):
        chunk = data[index : index + 4]
        size = struct.unpack("<I", data[index + 4 : index + 8])[0]
        body = index + 8
        if chunk == b"fmt ":
            channels = struct.unpack("<H", data[body + 2 : body + 4])[0]
            rate = struct.unpack("<I", data[body + 4 : body + 8])[0]
            bits = struct.unpack("<H", data[body + 14 : body + 16])[0]
        elif chunk == b"data":
            frame_bytes = max(channels * bits // 8, 1)
            return size / float(frame_bytes * max(rate, 1))
        index = body + size + (size & 1)
    return 0.0


def clip_seconds(path: Path) -> float:
    suffix = path.suffix.lower()
    if suffix == ".mp3":
        return mp3_seconds(path)
    if suffix == ".wav":
        return wave_seconds(path)
    # Ogg Vorbis: the last page's granule position is the sample count, but reading it needs
    # the codec's page structure for no gain here - the repository ships no Ogg voices, and a
    # new one should come with a duration check of its own rather than a silent 0.
    return 0.0


def spoken_length(text: str) -> tuple[int, int]:
    """Characters that are actually said, and the count that sets the slow end."""
    said = [char for char in text if not char.isspace()]
    pauses = sum(1 for char in said if char in PAUSE_CHARS)
    return len(said) - pauses, len(said)


def dialogue_lines() -> dict[tuple[str, str], str]:
    """Every spoken line the game can show, keyed by what a clip is named after."""
    lines: dict[tuple[str, str], str] = {}
    for path in sorted(DIALOGUE_DIR.glob("*/*.json")):
        try:
            table = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        for conversation_id, conversation in (table.get("conversations") or {}).items():
            for node in conversation.get("nodes") or []:
                text = node.get("text")
                if text:
                    lines[(conversation_id, node["id"])] = text
    return lines


def inspections() -> dict[str, str]:
    """Every inspection's text, keyed by the id a clip is named after."""
    found: dict[str, str] = {}
    for path in sorted(INSPECTION_DIR.glob("*/*.json")):
        try:
            table = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        for key, entry in table.items():
            if key in ("format_version", "locale") or not isinstance(entry, dict):
                continue
            if entry.get("text"):
                found[key] = entry["text"]
    return found


def expected_duration(text: str) -> tuple[float, float]:
    """The window a clip answering `text` has to fall inside, in seconds."""
    said, total = spoken_length(text)
    counted = max(said, 1)
    # Pauses are time without characters, so they relax the fast end rather than the slow one.
    fast = counted / MAX_CHARS_PER_SECOND + 0.12 * (total - said)
    slow = counted / MIN_CHARS_PER_SECOND + 0.30 * (total - said)
    return max(fast, MIN_CLIP_SECONDS * 0.5), max(slow, MIN_CLIP_SECONDS)


def clips() -> list[Path]:
    if not VOICE_DIR.exists():
        return []
    return sorted(
        path
        for path in VOICE_DIR.glob("*/*")
        if path.suffix.lower() in (".mp3", ".wav", ".ogg") and not path.name.endswith(".import")
    )


def audit() -> list[str]:
    """Every way a shipped clip can disagree with the words. Empty means they agree."""
    problems: list[str] = []
    lines = dialogue_lines()
    inspected = inspections()

    for clip in clips():
        locale = clip.parent.name
        stem = clip.stem
        if stem.startswith("inspection_"):
            inspection_id = stem[len("inspection_") :]
            text = inspected.get(inspection_id)
            if inspection_id not in inspected and ("classroom_" + inspection_id) in inspected:
                text = inspected["classroom_" + inspection_id]
            if text is None:
                problems.append(
                    f"{clip.relative_to(ROOT)}: no inspection is named '{inspection_id}' - "
                    "this clip is never played"
                )
                continue
        else:
            match = None
            for key in lines:
                if f"{key[0]}_{key[1]}" == stem:
                    match = key
                    break
            if match is None:
                problems.append(
                    f"{clip.relative_to(ROOT)}: no `conversation_node` line resolves to "
                    f"'{stem}' - VoiceDirector looks for `<conversation_id>_<node_id>`, so "
                    "this clip is never played"
                )
                continue
            text = lines[match]

        seconds = clip_seconds(clip)
        if seconds <= 0.0:
            problems.append(
                f"{clip.relative_to(ROOT)}: duration could not be read ({clip.suffix}); "
                "ship voice clips as .mp3 or .wav so the sync check can measure them"
            )
            continue
        fast, slow = expected_duration(text)
        if seconds < fast:
            problems.append(
                f"{clip.relative_to(ROOT)}: {seconds:.2f} s for a "
                f"{spoken_length(text)[0]}-character line. The line needs at least "
                f"{fast:.2f} s, so this clip is a fragment, not the line: "
                f"\u300c{text[:24]}\u300d"
            )
        elif seconds > slow:
            problems.append(
                f"{clip.relative_to(ROOT)}: {seconds:.2f} s for a "
                f"{spoken_length(text)[0]}-character line, which reads in about "
                f"{slow:.2f} s at the slowest. This clip says something else: "
                f"\u300c{text[:24]}\u300d"
            )

    return problems


def main(argv: list[str]) -> int:
    problems = audit()
    if problems:
        for problem in problems:
            print(f"VOICE_COVERAGE_FAILURE: {problem}")
        print(f"FAIL: {len(problems)} problem(s) found.")
        return 1
    total = len(clips())
    lines = dialogue_lines()
    print(
        f"VOICE_COVERAGE_OK: {total} voice clip(s) each measured against the line it plays "
        f"for; {len(lines)} dialogue line(s) and {len(inspections())} inspection(s) read."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
