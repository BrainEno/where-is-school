#!/usr/bin/env python3
"""Keep `scripts/ui/` free of new hard-coded colour literals (issue #229 / F-022).

`Palette` is the project's one palette and `tools/check_ui_palette.py` already refuses the
same RGB value written in two files. This check closes the other half of that gap: a colour
typed out *once* inside `scripts/ui/`, where it cannot be changed from one place and where
the next panel copies it instead of naming it.

## Why an allowlist and not a cleanup

34 literals are in `scripts/ui/` today. Almost all of them are legitimately local, and each
one is recorded below with the reason. This check does not ask anyone to move them; it stops
the set growing. `BASELINE` is a ratchet: a line may be removed as its file is tidied, and a
line left behind for a literal that no longer exists is itself a failure, so the list cannot
quietly stay loose.

## What is not a finding

- **Pure white, pure black and fully transparent.** `Color(1, 1, 1, 0)` is a tween target or
  a modulate endpoint, not a palette entry: naming it would put a name on arithmetic. This is
  the same exception `check_ui_palette.py` makes, and for the same reason.
- **A colour reached through a name.** `Color(Palette.INK, 0.5)`, `Color(MenuStyle.ACCENT)`
  and `Palette.INK` are already answering "which colour is this", which is the fix.
- **The palette file itself.** `scripts/theme/palette.gd` is where the values live.

## What it cannot see

It does not judge whether a remaining literal *should* move, and it does not check files
outside `scripts/ui/` (the world cue ambers are deliberately outside the interface palette;
see `check_ui_palette.py`). It is a gate on new drift, not a review of the old.

    python3 tools/check_ui_literals.py            # CI: fail on a new literal
    python3 tools/check_ui_literals.py --list     # every literal and its allowlist state

Standard library only, and it reads only GDScript.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI_DIR = "scripts/ui"
PALETTE_FILE = "scripts/theme/palette.gd"

# `Color(r, g, b)` / `Color(r, g, b, a)` with numeric literals only. A `Color(SOMETHING, a)`
# form is already using a name and is not matched.
LITERAL = re.compile(
    r"\bColor\(\s*"
    r"(?P<r>-?[0-9]*\.?[0-9]+)\s*,\s*"
    r"(?P<g>-?[0-9]*\.?[0-9]+)\s*,\s*"
    r"(?P<b>-?[0-9]*\.?[0-9]+)"
    r"(?:\s*,\s*(?P<a>-?[0-9]*\.?[0-9]+)\s*)?\)"
)

def is_achromatic(r: float, g: float, b: float) -> bool:
    """Pure white and pure black: tween endpoints and shadows, not palette entries."""
    return (r, g, b) in ((0.0, 0.0, 0.0), (1.0, 1.0, 1.0))


# Every literal that is allowed to stay, keyed by `path:line`, with the reason it is local.
#
# A line is the unit, not the value: two files may each need their own one-off ink, and the
# point of the list is that no *new* line appears.
BASELINE: dict[str, str] = {
    # The reading band's own inks. The band is written on its torn sheet, and its four
    # source colours are the ones issue #210 asks the owner to rule on: they differ from the
    # notebook's. Moving them would change how the prose reads, which is a visual decision,
    # not a refactor. See #210 and the contrast note in #229.
    "scripts/ui/dialogue_panel.gd:153": "band: source OBSERVED (owner decision in #210)",
    "scripts/ui/dialogue_panel.gd:154": "band: source REPORTED (owner decision in #210)",
    "scripts/ui/dialogue_panel.gd:155": "band: source RECALLED (owner decision in #210)",
    "scripts/ui/dialogue_panel.gd:156": "band: source IMAGINED (owner decision in #210)",
    "scripts/ui/dialogue_panel.gd:160": "band: the inner voices' rust, warmer than a speaker",
    "scripts/ui/dialogue_panel.gd:164": "band: a speaker without an accent (dark plum)",
    "scripts/ui/dialogue_panel.gd:166": "band: the sentence's blue-black ink",
    "scripts/ui/dialogue_panel.gd:174": "band: a taken choice, faded",
    # The notebook's paper: the drawn sheet, its rules, its margin and the pocket wedge. They
    # are composed against each other as one object and are not reused elsewhere.
    "scripts/ui/notebook_paper.gd:23": "notebook: the foot of the drawn sheet",
    "scripts/ui/notebook_paper.gd:24": "notebook: the sheet's shadow",
    "scripts/ui/notebook_paper.gd:25": "notebook: the ruled line",
    "scripts/ui/notebook_paper.gd:26": "notebook: the red margin rule",
    "scripts/ui/notebook_paper.gd:28": "notebook: the pocket wedge",
    "scripts/ui/notebook_paper.gd:29": "notebook: the wedge's hole",
    "scripts/ui/notebook_paper.gd:30": "notebook: the wedge's tick",
    # The ability check's verdict colours: one panel, read on a dark overlay.
    "scripts/ui/check_overlay.gd:27": "check overlay: success",
    "scripts/ui/check_overlay.gd:28": "check overlay: failure",
    "scripts/ui/check_overlay.gd:30": "check overlay: detail",
    # The imagination overlay's one scrim.
    "scripts/ui/imagination_overlay.gd:12": "imagination overlay: its one tint",
    # The title screen's painted backdrop: a painting composed against itself.
    "scripts/ui/title_screen.gd:391": "title screen: the warm underpainting",
    # A vignette scrim (pure black) and the menu's box shadow are achromatic and are skipped
    # by the check itself, so they are not listed here.
}


def ui_files(root: Path) -> list[Path]:
    """Every `.gd` under `scripts/ui/`, read from the working tree.

    `git ls-files` is deliberately not used: this must also run on a bare tree and on the
    fixture trees the test builds.
    """
    base = root / UI_DIR
    if not base.is_dir():
        return []
    return sorted(p for p in base.rglob("*.gd") if ".godot" not in p.parts)


def findings(root: Path, baseline: dict[str, str] | None = None) -> tuple[list[str], list[str]]:
    """New literals, and baseline entries that no longer match a literal.

    `baseline` is a parameter rather than a closed-over constant so a caller can ask the
    question of another tree; the tests use empty and small baselines on fixtures, where this
    repository's entries would all read as stale.
    """
    allowed = BASELINE if baseline is None else baseline
    seen: set[str] = set()
    grown: list[str] = []
    for path in ui_files(root):
        relative = path.relative_to(root).as_posix()
        for number, line in enumerate(
            path.read_text(encoding="utf-8-sig").splitlines(), 1
        ):
            code = line.split("#", 1)[0]
            for match in LITERAL.finditer(code):
                r, g, b = (float(match[name]) for name in ("r", "g", "b"))
                if is_achromatic(r, g, b):
                    continue
                key = f"{relative}:{number}"
                seen.add(key)
                if key not in allowed:
                    grown.append(
                        f"{key}: writes out Color({r:g}, {g:g}, {b:g}) in the interface - "
                        "name it in `Palette` (or read an existing name) so one value has "
                        "one home (issue #229)"
                    )
    stale = [
        f"{key}: is in the literal baseline but no longer matches a literal ({allowed[key]})"
        " - delete its line so the ratchet keeps the lower count"
        for key in sorted(allowed)
        if key not in seen
    ]
    return grown, stale


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--root", type=Path, default=root)
    parser.add_argument(
        "--list", action="store_true", help="print every interface literal and whether it is allowed"
    )
    args = parser.parse_args(argv)

    baseline = None if args.root.resolve() == ROOT.resolve() else {}

    if args.list:
        total = 0
        for path in ui_files(args.root):
            relative = path.relative_to(args.root).as_posix()
            for number, line in enumerate(
                path.read_text(encoding="utf-8-sig").splitlines(), 1
            ):
                code = line.split("#", 1)[0]
                for match in LITERAL.finditer(code):
                    r, g, b = (float(match[name]) for name in ("r", "g", "b"))
                    if is_achromatic(r, g, b):
                        continue
                    total += 1
                    key = f"{relative}:{number}"
                    state = "allowed" if (baseline or BASELINE) and key in (BASELINE if baseline is None else baseline) else "NEW"
                    print(f"{key}: Color({r:g}, {g:g}, {b:g})  [{state}]")
        print(f"{total} interface literal(s)")
        return 0

    grown, stale = findings(args.root, baseline)
    if grown or stale:
        for problem in grown + stale:
            print("UI_LITERALS_FAILURE: " + problem)
        return 1
    count = len(BASELINE) if baseline is None else 0
    print(
        "UI_LITERALS_OK: no interface file writes out a new colour literal; "
        f"{count} allowlisted literal(s) remain, each with its reason."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
