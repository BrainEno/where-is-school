#!/usr/bin/env python3
"""Cut the bundled CJK fonts down to the characters this project can actually draw.

The shipped font is Noto Sans SC Regular: 10.6 MB and 30,890 mapped characters for a
15-minute slice that uses 820 of them. Every byte of it was in the export, because a
`.ttf` under `res://` is imported as a resource and every imported resource is packed
into the build.

The split this script maintains:

- `art/fonts/NotoSansSC-Regular.ttf` — the untouched upstream font. It is the *source*,
  it lives next to the .blend sources, and `art/fonts/.gdignore` keeps Godot from
  importing it (`docs/ASSET_PIPELINE.md` §5, `docs/IMPLEMENTATION_NOTES_PROPS.md`).
- `assets/fonts/NotoSansSC-Regular.ttf` — the subset the game loads. Same path, same
  import sidecar and same resource uid as before, so nothing else in the project had to
  move: only the bytes shrank.

A second face follows the same split: `art/fonts/NotoSerifSC-Regular.otf` (Noto Serif SC
Regular from notofonts/noto-cjk, 11.1 MiB) is cut down to
`assets/fonts/NotoSerifSC-Regular.otf`, the serif the dialogue panel sets its sentences,
names and options in (`scripts/ui/dialogue_panel.gd`), and the title screen and pause menu
their name, headings, entries and questions (`scripts/ui/menu_style.gd`). It only ever draws
game text, so its character set is taken from what can reach the player (`data/`, `scenes/`,
`scripts/`, `project.godot`) and not from the editor add-on or the tests; anything it does
not carry falls back to the Sans subset instead of becoming a tofu box (each user sets that
fallback). Both faces are built and checked by one run of this script, so CI did not need a
second step.

Re-run this after writing text that uses characters the subset does not carry:

    pip install fonttools
    python3 tools/subset_font.py

`--check` does the same build in memory and compares it byte for byte with every committed
subset, which is what CI runs: a content change that needs a new glyph then fails with the
list of characters to add, instead of shipping a build full of tofu boxes.

The character set is deliberately wider than today's text (see `ALWAYS_INCLUDED`): full
Latin-1, general punctuation, arrows, CJK punctuation and full-width forms are carried
whether or not a line uses them yet, because they are cheap and because the next line of
dialogue is likely to want a full-width comma.
"""

from __future__ import annotations

import argparse
import glob
import json
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

DEFAULT_SOURCE = Path("art/fonts/NotoSansSC-Regular.ttf")
DEFAULT_OUTPUT = Path("assets/fonts/NotoSansSC-Regular.ttf")

# Text that can reach a Label. `tests/` is included even though it never ships: a test
# that renders Chinese should not be the thing that discovers a missing glyph.
#
# `addons/` is the narrative editor. It never reaches a player's build either, but its dock
# is labelled in Chinese and wears this project's theme, so the font has to be able to draw
# every word in it — otherwise the author's own tool is the first thing that shows tofu.
TEXT_SOURCES = (
    "data/**/*.json",
    "scenes/**/*.tscn",
    "scripts/**/*.gd",
    "tests/**/*.gd",
    "addons/**/*.gd",
    "project.godot",
)

# What can reach the dialogue panel: content, locale tables, scenes and scripts. The serif
# face draws nothing else, so the editor add-on and the tests are left out on purpose; a
# glyph only they use is drawn by the Sans subset through the panel's fallback.
DIALOGUE_TEXT_SOURCES = (
    "data/**/*.json",
    "scenes/**/*.tscn",
    "scripts/**/*.gd",
    "project.godot",
)


@dataclass(frozen=True)
class Target:
    """One upstream font and the subset cut from it."""

    source: Path
    output: Path
    text_sources: tuple[str, ...]


# Every subset this script maintains. A run with no arguments builds all of them, and
# `--check` checks all of them.
TARGETS = (
    Target(DEFAULT_SOURCE, DEFAULT_OUTPUT, TEXT_SOURCES),
    Target(
        Path("art/fonts/NotoSerifSC-Regular.otf"),
        Path("assets/fonts/NotoSerifSC-Regular.otf"),
        DIALOGUE_TEXT_SOURCES,
    ),
)

# Ranges kept whether or not the current text uses them, so a new sentence with a dash,
# a curly quote or full-width punctuation does not need a regeneration. Only the margin is
# optional: any character the text actually uses is required whatever range it is in, so
# an arrow or a bullet written into a line is still drawn.
#
# Arrows, mathematical operators, currency signs and geometric shapes used to be kept as
# well. No shipped text used them, and together they cost about 26 KB across the two
# subsets - space the then 16 MiB pack (`tools/verify_build.py`) no longer had once the author's
# rewritten prologue needed its own new characters. Add a range back only with that budget.
ALWAYS_INCLUDED = (
    (0x0020, 0x007E),  # ASCII printable
    (0x00A0, 0x00FF),  # Latin-1 supplement (names, accents)
    (0x2000, 0x206F),  # general punctuation: en/em dash, ellipsis, curly quotes
    (0x3000, 0x303F),  # CJK punctuation: 、。「」『』
    (0xFF00, 0xFFEF),  # full-width forms: ，！？：；（）
)

# A font bigger than this under `res://` is a packaging mistake, not a style choice: it
# is either the unsplit source font or an asset nobody trimmed. The subset is ~330 KB.
MAX_SHIPPED_FONT_BYTES = 2 * 1024 * 1024

# fontTools' subsetter output is not guaranteed identical across its own versions, so the
# byte-for-byte half of `--check` only runs on the version CI installs. Coverage — the part
# that matters, since it is what turns into tofu boxes — is checked on any version.
PINNED_FONTTOOLS = "4.58.5"


def collect_characters(text_sources: tuple[str, ...] = TEXT_SOURCES) -> tuple[set[str], set[str]]:
    """Characters the project can ask the font to draw, and the ones kept as margin.

    The first set is a hard requirement: if the source font cannot draw one of them, the
    game would show a tofu box and the build must fail. The second set is convenience —
    punctuation and symbols that are cheap to carry and likely to be wanted next — so a
    code point the font happens not to map is simply dropped there.
    """
    characters: set[str] = set()
    for pattern in text_sources:
        for name in glob.glob(pattern, recursive=True):
            # This drawer is absent from the retail pack and uses a system CJK fallback.
            if Path(name).as_posix().startswith("scripts/dev/authoring/"):
                continue
            text = Path(name).read_text(encoding="utf-8", errors="ignore")
            if name.endswith(".json"):
                # Only the *values* matter, but keys are cheap and a key that leaks into
                # a label should not be the surprise.
                try:
                    parsed = json.loads(text)
                except json.JSONDecodeError as error:
                    raise SystemExit(f"{name}: not valid JSON ({error})")
                characters.update(_walk_json(parsed))
            else:
                characters.update(text)
    used = {character for character in characters if character.isprintable() or character == " "}
    margin: set[str] = set()
    for low, high in ALWAYS_INCLUDED:
        margin.update(chr(code) for code in range(low, high + 1))
    return used, {character for character in margin if character.isprintable() or character == " "}


def _walk_json(node: object) -> set[str]:
    found: set[str] = set()
    if isinstance(node, dict):
        for key, value in node.items():
            found.update(str(key))
            found.update(_walk_json(value))
    elif isinstance(node, list):
        for value in node:
            found.update(_walk_json(value))
    elif isinstance(node, str):
        found.update(node)
    return found


def build(source: Path, characters: set[str], destination: Path, margin: set[str] = set()) -> None:
    """Write the subset to `destination`. Deterministic: same input, same bytes."""
    from fontTools import subset  # imported here so --help works without fonttools
    from fontTools.ttLib import TTFont

    if not source.is_file():
        raise SystemExit(
            f"{source} is missing. It is the upstream font, tracked in art/fonts/ "
            "(docs/ASSET_PIPELINE.md §5); restore it before regenerating the subset."
        )

    mapped = set(TTFont(source, lazy=True).getBestCmap())
    characters = characters | {character for character in margin if ord(character) in mapped}
    unmapped = sorted(character for character in characters if ord(character) not in mapped)
    if unmapped:
        listed = ", ".join(f"{character!r} U+{ord(character):04X}" for character in unmapped[:20])
        raise SystemExit(
            f"{source} cannot draw {len(unmapped)} character(s) the project uses: {listed}\n"
            "Either the source font is not the one these strings were written against, or "
            "a character from another script slipped into the text."
        )

    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.layout_features = ["*"]
    options.notdef_outline = True
    options.recalc_bounds = True
    options.glyph_names = False

    font = subset.load_font(str(source), options)
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text="".join(sorted(characters)))
    subsetter.subset(font)
    font.flavor = None
    subset.save_font(font, str(destination), options)
    font.close()


def report(source: Path, output: Path, characters: set[str], margin: set[str]) -> None:
    print(f"characters required : {len(characters)} (+ up to {len(margin)} margin)")
    print(f"source              : {source} ({source.stat().st_size / 1048576:.2f} MiB)")
    print(f"subset              : {output} ({output.stat().st_size / 1024:.0f} KiB)")
    print(f"reduction           : {source.stat().st_size / output.stat().st_size:.0f}x")


def _missing_coverage(output: Path, characters: set[str]) -> list[str]:
    from fontTools.ttLib import TTFont

    mapped = set(TTFont(output, lazy=True).getBestCmap())
    return sorted(character for character in characters if ord(character) not in mapped)


def check(source: Path, output: Path, characters: set[str], margin: set[str]) -> int:
    """Verify the committed subset covers the text, and was built by this script."""
    import fontTools

    if not output.is_file():
        print(f"FAIL: {output} is missing; run tools/subset_font.py", file=sys.stderr)
        return 1

    uncovered = _missing_coverage(output, characters)
    if uncovered:
        listed = ", ".join(f"{character!r} U+{ord(character):04X}" for character in uncovered[:20])
        print(
            f"FAIL: {output} cannot draw {len(uncovered)} character(s) the project uses: "
            f"{listed}\nRun `python3 tools/subset_font.py` and commit the result.",
            file=sys.stderr,
        )
        return 1

    if fontTools.version != PINNED_FONTTOOLS:
        print(
            f"note: fontTools {fontTools.version} is installed and {PINNED_FONTTOOLS} is what "
            "CI pins; skipping the byte-for-byte comparison (coverage is complete)"
        )
        print(f"PASS: {output} covers every character the project uses ({output.stat().st_size / 1024:.0f} KiB)")
        return 0

    with tempfile.TemporaryDirectory() as scratch:
        fresh = Path(scratch) / f"fresh{output.suffix}"
        build(source, characters, fresh, margin)
        committed = output.read_bytes()
        rebuilt = fresh.read_bytes()
        if committed != rebuilt:
            print(
                f"FAIL: {output} is not what tools/subset_font.py builds from the current "
                f"text ({len(committed)} bytes committed, {len(rebuilt)} bytes fresh).\n"
                "Run `python3 tools/subset_font.py` and commit the result.",
                file=sys.stderr,
            )
            return 1
    print(f"PASS: {output} matches a fresh subset ({output.stat().st_size / 1024:.0f} KiB)")
    return 0


# Documents that describe the shipped subset in the present tense (issue #286). Its size
# changes whenever the text does, so a byte or KiB count written next to "subset" in one of
# them is stale by the next content PR; `--check` prints the real size instead. Dated
# measurements (the archive, the pack-size tables) are records of a moment and are not
# listed. A count that equals an upstream source font's size is stable and allowed.
LIVE_SIZE_PROSE = (
    "README.md",
    "docs/TECHNICAL_ROADMAP.md",
    "docs/ASSET_PROVENANCE.md",
    ".github/workflows/godot-ci.yml",
    ".github/workflows/test-tooling.yml",
)
SIZE_LITERAL = re.compile(r"\b(\d[\d,.]*)\s?(KiB|KB|kB|bytes)\b")


def stale_size_prose(root: Path = Path(".")) -> list[str]:
    stable = {path.stat().st_size for target in TARGETS for path in (root / target.source,) if path.is_file()}
    problems = []
    for relative in LIVE_SIZE_PROSE:
        path = root / relative
        if not path.is_file():
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if "subset" not in line.lower():
                continue
            for match in SIZE_LITERAL.finditer(line):
                value = match.group(1).replace(",", "")
                if match.group(2) == "bytes" and value.isdigit() and int(value) in stable:
                    continue
                problems.append(f"{relative}:{number}: \"{match.group(0)}\" next to the font subset")
    return problems


def oversized_shipped_fonts() -> list[Path]:
    return [
        path
        for pattern in ("*.ttf", "*.otf")
        for path in sorted(Path("assets").rglob(pattern))
        if path.stat().st_size > MAX_SHIPPED_FONT_BYTES
    ]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--source",
        type=Path,
        default=None,
        help="build one custom pair instead of every target (needs --output)",
    )
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the committed subset instead of rewriting it",
    )
    arguments = parser.parse_args(argv)

    for path in (Path("data"), Path("scenes")):
        if not path.is_dir():
            raise SystemExit(f"run this from the repository root ({path} not found)")

    if (arguments.source is None) != (arguments.output is None):
        parser.error("--source and --output go together")
    if arguments.source is None:
        targets = TARGETS
    else:
        targets = (Target(arguments.source, arguments.output, TEXT_SOURCES),)

    if arguments.check:
        status = 0
        for target in targets:
            characters, margin = collect_characters(target.text_sources)
            status |= check(target.source, target.output, characters, margin)
        fat = oversized_shipped_fonts()
        if fat:
            for path in fat:
                print(
                    f"FAIL: {path} is {path.stat().st_size / 1048576:.2f} MiB; fonts under "
                    "res:// are packed into the build",
                    file=sys.stderr,
                )
            status = 1
        stale = stale_size_prose()
        for problem in stale:
            print(
                f"FAIL: {problem}; the subset's size changes with the text - drop the number "
                "and point at `tools/subset_font.py --check` (issue #286)",
                file=sys.stderr,
            )
        if stale:
            status = 1
        return status

    for target in targets:
        characters, margin = collect_characters(target.text_sources)
        target.output.parent.mkdir(parents=True, exist_ok=True)
        build(target.source, characters, target.output, margin)
        report(target.source, target.output, characters, margin)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
