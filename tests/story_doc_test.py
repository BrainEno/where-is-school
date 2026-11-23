#!/usr/bin/env python3
"""Proves a story document can be edited and brought back without losing anything.

The writers edit the dialogue as scripts in Google Docs (``tools/story_doc.py``; the format is
``docs/STORY_DOCS.zh-CN.md``) and hand them back. Two things have to hold for that to be safe:

1. **An untouched script is a no-op.** Export every table and import the scripts again: every
   JSON file comes back byte for byte, key order included. If it does not, the format has a
   field it cannot carry, and a writer's first harmless edit would silently drop it.
2. **A broken script is refused, line by line, before anything is written.** An unknown
   speaker, a jump to a line that does not exist, a subjective scene that tries to set a flag:
   each comes back as a Chinese message naming the conversation and the line, and no file
   changes. A writer can fix the script; a half-written table would be worse than none.

And the edits a writer actually makes - rewording a line, adding one - come through with the
English kept by id and the line listed for translation, so the two locales cannot drift.

The ``.docx`` the writers actually open is checked too: every script written as ``.docx`` reads
back as the same lines, so what Google Docs receives is exactly the text the round trip proved.

Run it with ``python3 tests/story_doc_test.py``. Standard library only, like the tool.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import story_doc as sd  # noqa: E402

FAILURES: list[str] = []


def expect(condition: bool, message: str) -> None:
    if not condition:
        FAILURES.append(message)


def script(chapter: str, names: sd.Names) -> list[str]:
    return [text for _style, text in sd.export_dialogue(chapter, names, {})]


def refused(lines: list[str], names: sd.Names, needle: str, label: str) -> None:
    try:
        sd.apply_document(lines, names, write=False)
    except sd.DocError as error:
        expect(needle in str(error), f"{label}: refused, but the message does not say {needle!r}: {error}")
        return
    FAILURES.append(f"{label}: the broken script was accepted")


def line_index(lines: list[str], prefix: str) -> int:
    return next(index for index, line in enumerate(lines) if line.startswith(prefix))


def main() -> int:
    names = sd.Names()
    for error in sd.roundtrip_errors():
        FAILURES.append(f"round trip: {error}")

    alley = script("alley", names)
    first = line_index(alley, "[aa_1]")
    old_text = alley[first].split("：", 1)[1]

    # A reworded line: Chinese changes, English keeps its old text and is queued.
    reworded = list(alley)
    reworded[first] = reworded[first] + "（改）"
    summary = sd.apply_document(reworded, names, write=False)
    pending = [entry for entry in summary["pending_en"] if entry["path"][-2:] == ["#aa_1", "text"]]
    expect(len(pending) == 1, f"a reworded line is not queued for translation: {summary['pending_en']}")
    if pending:
        expect(pending[0]["zh_before"] == old_text, "the queued line lost its old Chinese text")
        expect(bool(pending[0]["en_before"]), "the queued line lost its English text")
    expect(not summary["structure"], f"rewording reported structure changes: {summary['structure']}")

    # A new line between two others: accepted, reported, and queued.
    added = list(alley)
    added.insert(line_index(alley, "[aa_2]"), "[aa_new] 旁白：新加的一句。")
    summary = sd.apply_document(added, names, write=False)
    expect("alley_arrival: 新增 [aa_new]" in summary["structure"], f"a new line is not reported: {summary['structure']}")
    expect(
        any(entry["path"][-2:] == ["#aa_new", "text"] for entry in summary["pending_en"]),
        "a new line is not queued for translation",
    )

    # Broken scripts, each refused with a message that points at the problem.
    bad_speaker = list(alley)
    bad_speaker[first] = "[aa_1] 路人甲：你好。"
    refused(bad_speaker, names, "不认识的说话人「路人甲」", "unknown speaker")

    dangling = [line.replace("下一句：结束", "下一句：nowhere", 1) for line in alley]
    refused(dangling, names, "下一句 指向 nowhere", "dangling next")

    duplicate = list(alley)
    duplicate.insert(first + 1, alley[first])
    refused(duplicate, names, "[aa_1] 用了两次", "duplicate id")

    bad_objective = list(alley)
    bad_objective.insert(first + 1, "效果：目标 走出去")
    refused(bad_objective, names, "目标要写成", "objective without a key")

    voice = script("prologue", names)
    start = line_index(voice, "■ 会话 expected_b")
    node = next(index for index in range(start, len(voice)) if voice[index].startswith("["))
    subjective = list(voice)
    subjective.insert(node + 1, "效果：设旗 b_imagined = true")
    refused(subjective, names, "主观会话不能设旗", "flag in a subjective scene")

    # Author tooling uses the same six identities and subjective boundary as Godot.
    expected_voices = {
        "洞察": "insight", "细察": "scrutiny", "回声": "echo",
        "臆想": "imagination", "推演": "inference", "共鸣": "resonance",
    }
    expect(set(names.ability) == set(expected_voices.values()), "author tooling does not expose exactly six voices")
    for label, ability_id in expected_voices.items():
        expect(names.ability_id(label, "fixture") == ability_id, f"wrong ability identity for {label}")
        expect(names.speaker_id(label, "fixture") == "voice_" + ability_id, f"wrong speaker identity for {label}")
    for retired in ("路感", "异想天开", "orientation", "whimsy"):
        try:
            names.ability_id(retired, "fixture")
        except sd.DocError:
            pass
        else:
            FAILURES.append(f"retired ability is still accepted by the author tool: {retired}")
    expect(sd.IMAGINATION_ABILITIES == ("imagination",), "subjective author-tool whitelist drifted")
    check_line = line_index(voice, "检定：臆想 ")
    for label in expected_voices:
        if label == "臆想":
            continue
        blocked = list(voice)
        blocked[check_line] = blocked[check_line].replace("检定：臆想 ", f"检定：{label} ", 1)
        refused(blocked, names, "主观会话只能带「臆想」检定", f"{label} check inside a fantasy")

    # Every script survives the .docx layer unchanged.
    with tempfile.TemporaryDirectory() as scratch:
        for name, lines in sd.build_all(names).items():
            path = Path(scratch) / f"{name}.docx"
            sd.write_docx(lines, path)
            expect(sd.read_lines(path) == [text for _style, text in lines], f"{name}.docx does not read back as its script")

    # The objective preview in brackets is for the reader; the import keeps only the key.
    prologue_lines = script("prologue", names)
    previews = [line for line in prologue_lines if line.startswith("效果：目标 ") and "（" in line]
    expect(bool(previews), "objective effects no longer show their text")

    for failure in FAILURES:
        print(f"FAIL {failure}")
    print("story_doc_test: " + ("FAILED" if FAILURES else "ok"))
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
