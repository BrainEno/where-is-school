"""Read and edit `export_presets.cfg` without starting the editor.

Two tools need to understand the preset file and they must agree about it: the version
stamper writes `application/file_version` before an export, and the build check reads the
same file to complain early — before a twenty-minute export — when the preset has been left
with an empty icon path or a version that is not a version.

The file is Godot's own INI-like format: `[preset.N]` sections holding the preset's identity,
`[preset.N.options]` sections holding its export options, `key=value` lines, strings quoted,
numbers and booleans bare. Only that much is implemented, deliberately: a parser for the
whole format would be a second engine to keep in sync, and the parts it does not understand
do not appear in an export preset.

    from export_presets import parse, set_option
    presets = parse(Path("export_presets.cfg").read_text())
    windows = presets["Windows Desktop"]
    windows.options["binary_format/embed_pck"]  # "true"
    new_text = set_option(text, "Windows Desktop", "application/file_version", "0.1.0.0")

Nothing here writes a file, so a caller can decide whether a change is worth keeping.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path


class PresetError(Exception):
    """A preset file this module cannot read, or a preset it cannot find."""


@dataclass
class Preset:
    """One `[preset.N]` plus the options of its `[preset.N.options]` block."""

    index: int
    fields: dict[str, str] = field(default_factory=dict)
    options: dict[str, str] = field(default_factory=dict)

    @property
    def name(self) -> str:
        return self.fields.get("name", "")

    @property
    def platform(self) -> str:
        return self.fields.get("platform", "")

    @property
    def export_path(self) -> str:
        return self.fields.get("export_path", "")

    @property
    def exclude_filter(self) -> str:
        return self.fields.get("exclude_filter", "")


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return value[1:-1]
    return value


def _blocks(text: str) -> list[tuple[str, list[str]]]:
    blocks: list[tuple[str, list[str]]] = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            blocks.append((stripped[1:-1], []))
        elif blocks:
            blocks[-1][1].append(line)
    return blocks


def parse(text: str) -> dict[str, Preset]:
    """Every preset in the file, keyed by its display name."""
    presets: dict[int, Preset] = {}
    for section, lines in _blocks(text):
        head, _, tail = section.partition(".")
        if head != "preset" or not tail:
            continue
        number, _, kind = tail.partition(".")
        if not number.isdigit():
            continue
        preset = presets.setdefault(int(number), Preset(index=int(number)))
        target = preset.options if kind == "options" else preset.fields
        for line in lines:
            key, _, value = line.partition("=")
            key = key.strip()
            if not key or key.startswith(";"):
                continue
            target[key] = _unquote(value)
    named: dict[str, Preset] = {}
    for preset in presets.values():
        if not preset.name:
            continue
        if preset.name in named:
            raise PresetError(f"two presets are named {preset.name!r}")
        named[preset.name] = preset
    return named


def read(path: Path) -> dict[str, Preset]:
    try:
        return parse(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise PresetError(f"cannot read {path}: {error}") from error


def section_of(text: str, name: str) -> tuple[int, int, bool]:
    """Line range of the option block of the preset called `name`.

    Returns `(start, end, found)`: the lines `[start:end]` of the `[preset.N.options]` body.
    """
    index = None
    for number, preset in parse(text).items():
        if preset.name == name:
            index = preset.index
            break
    if index is None:
        raise PresetError(f"no preset named {name!r}")
    wanted = f"preset.{index}.options"
    lines = text.splitlines()
    for position, line in enumerate(lines):
        if line.strip() == f"[{wanted}]":
            end = position + 1
            while end < len(lines) and not lines[end].strip().startswith("["):
                end += 1
            return position + 1, end, True
    raise PresetError(f"preset {name!r} has no [{wanted}] section")


def set_option(text: str, name: str, key: str, value: str) -> str:
    """Set one option of one preset, leaving every other byte of the file alone.

    Rewriting the whole file from a parse would reformat it, and a reformat is a diff nobody
    can review. This replaces the matching line, or appends one at the end of the block.
    """
    start, end, _ = section_of(text, name)
    lines = text.splitlines()
    block = lines[start:end]
    replacement = f'{key}="{value}"'
    for position, line in enumerate(block):
        if line.partition("=")[0].strip() == key:
            block[position] = replacement
            break
    else:
        while block and not block[-1].strip():
            block.pop()
        block.append(replacement)
        block.append("")
    trailing = "\n" if text.endswith("\n") else ""
    return "\n".join(lines[:start] + block + lines[end:]) + trailing
