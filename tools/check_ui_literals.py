#!/usr/bin/env python3
"""Keep scripts/ui/ free of new numeric RGB(A) literals (issues #210/#229).

`Palette` is the shared owner. This check is for a hard-coded colour written even
once; check_ui_palette.py separately checks copies across files. The exceptions
below are one occurrence of an approved RGBA in one file, not a line number or
permission to write any colour in that file. Reformatting or shifting lines is
fine. Replacing/removing/duplicating an approved literal needs review.

Named colours, computed channels, and pure white/black tween endpoints are not
findings. The check does not choose which ink an artist should use or rewrite art.

    python3 tools/check_ui_literals.py
    python3 tools/check_ui_literals.py --list
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

from gdscript_source import DECIMAL, mask_non_code, numbered_matches

ROOT = Path(__file__).resolve().parent.parent
UI_DIR = "scripts/ui"
Rgba = tuple[float, float, float, float]
Key = tuple[str, Rgba]

# RGB or RGBA, including multiline constructors, exponents, and a trailing comma.
_RADIX = r"[+-]?(?:0x[\da-fA-F](?:_?[\da-fA-F])*|0b[01](?:_?[01])*)"
_NUMBER = rf"(?:{_RADIX}|{DECIMAL})"
LITERAL = re.compile(
    rf"\bColor\s*\(\s*(?P<r>{_NUMBER})\s*,\s*(?P<g>{_NUMBER})\s*,\s*(?P<b>{_NUMBER})"
    rf"(?:\s*,\s*(?P<a>{_NUMBER}))?\s*,?\s*\)"
)

# The distinct band inks stay as authored pending the visual decision in #210.
# The notebook paper is painted as a whole, not a general UI colour system.
BASELINE: dict[Key, str] = {
    ("scripts/ui/dialogue_panel.gd", (0.42, 0.35, 0.29, 1.0)): "band: source OBSERVED",
    ("scripts/ui/dialogue_panel.gd", (0.24, 0.37, 0.52, 1.0)): "band: source REPORTED",
    ("scripts/ui/dialogue_panel.gd", (0.32, 0.4, 0.34, 1.0)): "band: source RECALLED",
    ("scripts/ui/dialogue_panel.gd", (0.64, 0.32, 0.15, 1.0)): "band: source IMAGINED",
    ("scripts/ui/dialogue_panel.gd", (0.62, 0.27, 0.13, 1.0)): "band: inner voices' rust",
    ("scripts/ui/dialogue_panel.gd", (0.30, 0.16, 0.20, 1.0)): "band: unaccented speaker's plum",
    ("scripts/ui/dialogue_panel.gd", (0.16, 0.14, 0.20, 1.0)): "band: sentence's blue-black ink",
    ("scripts/ui/dialogue_panel.gd", (0.58, 0.44, 0.40, 1.0)): "band: faded ink for a taken choice",
    ("scripts/ui/notebook_paper.gd", (0.88, 0.845, 0.76, 1.0)): "notebook: foot of the sheet",
    ("scripts/ui/notebook_paper.gd", (0.02, 0.02, 0.05, 0.36)): "notebook: sheet shadow",
    ("scripts/ui/notebook_paper.gd", (0.55, 0.65, 0.82, 0.62)): "notebook: ruled line",
    ("scripts/ui/notebook_paper.gd", (0.80, 0.38, 0.36, 0.70)): "notebook: red margin rule",
    ("scripts/ui/notebook_paper.gd", (0.12, 0.10, 0.22, 0.94)): "notebook: pocket wedge",
    ("scripts/ui/notebook_paper.gd", (0.88, 0.83, 0.70, 0.85)): "notebook: wedge hole",
    ("scripts/ui/notebook_paper.gd", (0.88, 0.83, 0.70, 0.60)): "notebook: wedge tick",
    ("scripts/ui/check_overlay.gd", (0.62, 0.78, 0.56, 1.0)): "verdict overlay: success",
    ("scripts/ui/check_overlay.gd", (0.85, 0.50, 0.42, 1.0)): "verdict overlay: failure",
    ("scripts/ui/check_overlay.gd", (0.72, 0.66, 0.60, 1.0)): "verdict overlay: detail on dark ground",
    ("scripts/ui/imagination_overlay.gd", (0.298, 0.169, 0.129, 0.55)): "imagination scrim",
    ("scripts/ui/title_screen.gd", (0.20, 0.11, 0.075, 1.0)): "title backdrop underpainting",
}


@dataclass(frozen=True)
class Use:
    path: str
    line: int
    color: Rgba
    reason: str | None

    def describe(self) -> str:
        return f"{self.path}:{self.line}: {color_label(self.color)}"


def color_label(color: Rgba) -> str:
    return "Color(" + ", ".join(str(channel) for channel in color) + ")"


def component(text: str) -> float:
    return int(text, 0) if _RADIX_RE.fullmatch(text) else float(text)


_RADIX_RE = re.compile(_RADIX)


def scan(root: Path, baseline: dict[Key, str]) -> tuple[list[Use], dict[Key, str]]:
    remaining = dict(baseline)
    found: list[Use] = []
    for path in sorted((root / UI_DIR).rglob("*.gd")):
        relative = path.relative_to(root)
        if ".godot" in relative.parts:
            continue
        code = mask_non_code(path.read_text(encoding="utf-8-sig"))
        for line, match in numbered_matches(LITERAL, code):
            r, g, b = (component(match[name]) for name in ("r", "g", "b"))
            if (r, g, b) in ((0, 0, 0), (1, 1, 1)):
                continue
            color = (r, g, b, component(match["a"]) if match["a"] is not None else 1.0)
            name = relative.as_posix()
            found.append(Use(name, line, color, remaining.pop((name, color), None)))
    return found, remaining


def problems(uses: list[Use], remaining: dict[Key, str]) -> tuple[list[str], list[str]]:
    grown = [
        f"{use.describe()} is not allowlisted here - name it in `Palette` (or reuse a name)"
        for use in uses if use.reason is None
    ]
    stale = [
        f"{path}: {color_label(color)} is no longer present ({reason}) - delete its line from BASELINE"
        for (path, color), reason in sorted(remaining.items())
    ]
    return grown, stale


def findings(root: Path, baseline: dict[Key, str] | None = None) -> tuple[list[str], list[str]]:
    return problems(*scan(root, BASELINE if baseline is None else baseline))


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=root)
    parser.add_argument("--list", action="store_true", help="report each use and its allowlist state")
    args = parser.parse_args(argv)
    baseline = BASELINE if args.root.resolve() == ROOT else {}
    uses, remaining = scan(args.root, baseline)
    if args.list:
        for use in uses:
            print(f"{use.describe()}  [{use.reason or 'NEW'}]")
        print(f"{len(uses)} interface literal(s)")
        return 0
    grown, stale = problems(uses, remaining)
    if grown or stale:
        for problem in grown + stale:
            print("UI_LITERALS_FAILURE: " + problem)
        return 1
    print(f"UI_LITERALS_OK: no new colour literals; {len(baseline)} allowlisted occurrence(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
