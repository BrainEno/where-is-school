#!/usr/bin/env python3
"""The single-writer contract for face morphs (#387).

`CharacterLookApplier` composes every layer of a shipped character's face - resting
expression, directed state, blink - in one function, and the whole point of that is
that no second script starts writing the same mesh behind its back. So the contract
is frozen here as a file list:

- `scripts/actors/character_look_applier.gd` is the writer (its own claim, and the
  only production script allowed to call `set_blend_shape_value`);
- `scripts/actors/npc/q_textbook_pose.gd` owns exactly the two shapes no face state
  may name (`Smile`, `Mouth_Open`) - a held book is a performance of its own;
- `scripts/dev/animation_preview.gd` and `scenes/dev/classmates/classmates_review.gd`
  are dev diagnostics that stand the applier's processing down while they run (the
  preview test asserts that ownership trade directly);
- everything under `tests/` may write morphs freely: tests are the place white-box
  claims are made.

Any other production file reaching for `set_blend_shape_value` fails the check with
a message naming it. Run with `python3 tests/morph_writer_contract_test.py` (CI does).
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ALLOWED = {
    "scripts/actors/character_look_applier.gd",
    "scripts/actors/npc/q_textbook_pose.gd",
    "scripts/dev/animation_preview.gd",
    "scenes/dev/classmates/classmates_review.gd",
}
CALL = re.compile(r"\bset_blend_shape_value\s*\(")


def main() -> int:
    listing = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "*.gd"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.splitlines()
    offenders: list[str] = []
    for relative in listing:
        if relative in ALLOWED or relative.startswith("tests/"):
            continue
        text = (ROOT / relative).read_text(encoding="utf-8")
        if CALL.search(text):
            offenders.append(relative)
    if offenders:
        for relative in offenders:
            print(
                f"{relative}: writes blend shapes directly; the face's one writer is "
                "CharacterLookApplier (see tests/morph_writer_contract_test.py)."
            )
        return 1
    print(f"MORPH_WRITER_CONTRACT_OK: {len(listing)} scripts, one writer.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
