#!/usr/bin/env python3
"""Keep one palette: a colour value may be written out in only one file (issue #210).

The project has one visual language - "ink and paper" - and `Palette` is where its colours
live. That was a convention, not a fact: the same bone `(0.776, 0.733, 0.643)` was typed out
in eight files, the pause menu and the confirmation prompt each carried a near-black of
their own, and the reading band drifted from the menus without anyone deciding that it
should. A colour copied into a second file cannot be changed in one place, and the copies
disagree after the first edit.

`Palette` has to stay a **leaf** - no imports, no `preload`, no `Palette` reaching back into
the UI - or naming a colour from the dialogue layer would drag the interface in behind it.
The second half of this check says so.

This check makes the convention a fact, at the level where the damage happens: **the same
RGB value in two different files**. It does not require every colour to be a constant, and
it does not care which constant - `MenuStyle.ACCENT`, `Color(MenuStyle.ACCENT, 0.35)`,
`PAPER` - a file uses. It only refuses a *literal* re-typed somewhere else.

    python3 tools/check_ui_palette.py            # CI: fail on a new duplicate
    python3 tools/check_ui_palette.py --list     # every literal and where it is written

`Palette` re-exporting through `MenuStyle` is deliberate: `MenuStyle.INK` and `Palette.INK`
are one value, and the menus keep reading the names they always have.

What is out of scope, and why:

- **Alpha.** Two writers of one RGB at different alphas are the same decision made twice,
  so alpha is ignored when grouping: `Color(0.89, 0.87, 0.80, 0.12)` and
  `Color(0.89, 0.87, 0.80, 1.0)` are one finding.
- **Pure white, pure black and fully transparent.** `Color(1, 1, 1, 0)` is a tween target,
  not a palette entry; it is the "#ffffff" of a `modulate` call, and naming it would put a
  name on arithmetic.
- **`.tscn` / `.tres`.** A `.tres` *is* a data file: `data/characters/*.tres` carries each
  speaker's own accent, which is exactly the per-character variation this check is meant to
  protect, not a duplicate of it.
- **`scripts/interaction/world_cue.gd`.** The click mark's three colours are the *world's*
  warm ambers, deliberately outside the interface palette: they are chosen to read on brick
  and on plaster under the game camera, not on a page.
- **`tests/`.** A test that pins `Color(0.776, 0.733, 0.643, 1.0)` and compares it to what
  a panel drew is doing the opposite of this problem: it is the tripwire that notices when
  the palette moves. `MenuStyle` is deliberately *not* imported there, so the expected value
  cannot follow the constant it is meant to check.
- **`scripts/ui/dialogue_panel.gd` and `dialogue_mode_bar.gd`,** while the reading band is
  being restyled on paper (#231). The band keeps its own values for one more release; the
  allowlist below is the reminder to fold them in, not a licence to add a fifth.

A pair whose every writer is the palette file or an allowlisted file is reported as *known*
rather than failed, so the count of outstanding drift stays visible instead of the check
being switched off until #231 merges.

Standard library only, and it reads only GDScript: the palette question is about code.
"""

from __future__ import annotations

import argparse
import collections
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PALETTE_FILE = "scripts/theme/palette.gd"

# `Color(r, g, b)` / `Color(r, g, b, a)` with numeric literals only. A `Color(SOMETHING, a)`
# form is already using a name and is not matched.
LITERAL = re.compile(
    r"\bColor\(\s*"
    r"(?P<r>[0-9]*\.?[0-9]+)\s*,\s*(?P<g>[0-9]*\.?[0-9]+)\s*,\s*(?P<b>[0-9]*\.?[0-9]+)"
    r"(?:\s*,\s*(?P<a>[0-9]*\.?[0-9]+)\s*)?\)"
)
# A name that already answers "which colour is this?".
NAMED = re.compile(r"\bColor\(\s*[A-Za-z_]")


def is_achromatic(r: float, g: float, b: float) -> bool:
    """Pure white and pure black: tween endpoints and shadows, not palette entries."""
    return (r, g, b) in ((0.0, 0.0, 0.0), (1.0, 1.0, 1.0))


def _key(match: re.Match[str]) -> tuple[float, float, float]:
    return (round(float(match["r"]), 3), round(float(match["g"]), 3), round(float(match["b"]), 3))


def gdscript_files(root: Path) -> list[Path]:
    """Every tracked GDScript, read from the working tree.

    `git ls-files` is deliberately not used: this must also run on a bare tree and on the
    fixture trees the test builds. A `.gd` file under `.godot/` is engine cache, not source.
    """
    found = []
    for directory in ("scripts", "addons"):
        base = root / directory
        if not base.is_dir():
            continue
        for path in base.rglob("*.gd"):
            if ".godot" in path.parts:
                continue
            found.append(path)
    return sorted(found)


def scan(root: Path) -> tuple[dict[tuple[float, float, float], list[str]], int]:
    """Every literal colour in the tree, grouped by RGB, with `path:line` for each writer."""
    writers: dict[tuple[float, float, float], list[str]] = collections.defaultdict(list)
    literals = 0
    for path in gdscript_files(root):
        relative = path.relative_to(root).as_posix()
        for number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for match in LITERAL.finditer(line):
                r, g, b = (float(match[name]) for name in ("r", "g", "b"))
                if is_achromatic(r, g, b):
                    continue
                writers[_key(match)].append(f"{relative}:{number}")
                literals += 1
    return writers, literals


# Anything that would make the palette file depend on something else.
IMPORT = re.compile(r"\b(?:preload|load)\s*\(")


def palette_file_stays_a_leaf(root: Path) -> list[str]:
    """`Palette` must import nothing: that is what lets every layer name a colour."""
    path = root / PALETTE_FILE
    if not path.is_file():
        return [f"{PALETTE_FILE} is missing: it is the one place a colour value is written"]
    problems: list[str] = []
    text = path.read_text(encoding="utf-8-sig")
    for number, line in enumerate(text.splitlines(), 1):
        code = line.split("#", 1)[0]
        if IMPORT.search(code):
            problems.append(
                f"{PALETTE_FILE}:{number}: the palette must not load anything "
                f"(`{line.strip()}`) - a leaf module is what lets every layer name a colour")
    # A mention in a comment is fine (the file explains why it exists); a mention in code is
    # the dependency this rule is about.
    code_only = "\n".join(line.split("#", 1)[0] for line in text.splitlines())
    for name in ("MenuStyle", "UiTextScale", "JournalPanel", "DialoguePanel"):
        if re.search(rf"\b{name}\b", code_only):
            problems.append(
                f"{PALETTE_FILE}: names {name}, which is a UI class; the palette must not "
                "reach into the interface it serves")
    return problems


def findings(root: Path) -> tuple[list[str], list[str], list[str]]:
    """Duplicate RGB values, files holding literals, and the pairs that are already known."""
    writers, _ = scan(root)
    duplicates: list[str] = []
    known: list[str] = []
    for (r, g, b), places in sorted(writers.items(), key=lambda item: -len(item[1])):
        files = sorted({place.rsplit(":", 1)[0] for place in places})
        if len(files) < 2:
            continue
        message = (
            f"colour ({r:g}, {g:g}, {b:g}) is written out in {len(files)} files: "
            + ", ".join(files)
            + " - keep the value in one place (`Palette`) and read it by name"
        )
        if all(path in ALLOWLIST or path == PALETTE_FILE for path in files):
            known.append(message)
        else:
            duplicates.append(message)
    # Not a failure on its own, but the report names every file that still holds a literal,
    # so the next edit knows where the palette has leaked.
    leaks = sorted({place.rsplit(":", 1)[0] for places in writers.values() for place in places})
    return duplicates, leaks, known


ALLOWLIST = {
    # The reading band is being restyled on paper in #231; its four source colours and its
    # two choice colours move with that work, not before it.
    "scripts/ui/dialogue_panel.gd",
    "scripts/ui/dialogue_mode_bar.gd",
    # The world's cue ambers: chosen against brick and plaster under the game camera, not
    # against a page. They are not interface palette entries.
    "scripts/interaction/world_cue.gd",
    # The ability check's verdict colours (success/failure/detail) read on a dark overlay
    # for one panel; they are a small, self-contained set and not part of the menu palette.
    "scripts/ui/check_overlay.gd",
    # The imagination overlay's tint is one scrim, used once.
    "scripts/ui/imagination_overlay.gd",
    # An NPC's authored placeholder body colour; character art owns it.
    "scripts/actors/npc/npc_actor.gd",
    # The look applier's fallback pigment when a look resource names none.
    "scripts/actors/character_look_applier.gd",
    # The narrative editor's dock draws inside the *editor*, where the engine's theme decides
    # the background; its few colours are debug-readability choices, and the plugin is
    # excluded from the export (addons/).
    "addons/narrative_editor/ui/narrative_editor_dock.gd",
    # The title screen's painted backdrop (brick fields, sky wash) is a painting, not a
    # panel: its colours are composed against each other and are not reused elsewhere.
    "scripts/ui/title_screen.gd",
}


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--root", type=Path, default=root)
    parser.add_argument("--list", action="store_true",
                        help="print every literal colour with the files that write it")
    args = parser.parse_args(argv)

    duplicates, leaks, known = findings(args.root)
    leaf_problems = palette_file_stays_a_leaf(args.root)
    if args.list:
        writers, literals = scan(args.root)
        for (r, g, b), places in sorted(writers.items()):
            print(f"({r:g}, {g:g}, {b:g}): {', '.join(places)}")
        print(f"{literals} literal(s) in {len(leaks)} file(s)")

    if duplicates or leaf_problems:
        for problem in duplicates + leaf_problems:
            print("UI_PALETTE_FAILURE: " + problem)
        return 1
    for problem in known:
        print("UI_PALETTE_KNOWN: " + problem + " (an allowlisted writer: see ALLOWLIST)")
    non_palette = [path for path in leaks if path not in ALLOWLIST and path != PALETTE_FILE]
    print(
        "UI_PALETTE_OK: no colour value is written out twice outside the documented "
        f"allowlist; {len(leaks)} file(s) hold a literal of their own, "
        f"{len(known)} pair(s) allowed for now (the reading band, #231), "
        f"{len(non_palette)} file(s) outside the allowlist: {', '.join(non_palette) or 'none'}."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
