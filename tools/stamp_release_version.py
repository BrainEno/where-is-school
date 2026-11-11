#!/usr/bin/env python3
"""Write the release version into the Windows export preset, and check that it is there.

Windows shows a program's version in Explorer, in Task Manager and in the file's properties
dialog, and it reads it out of the executable's version resource — not out of the zip's
name. Godot fills that resource in from four preset fields (`application/file_version`,
`application/product_version`, and the product strings next to them), and a preset cannot
be overridden from the command line. So the version to build is written into
`export_presets.cfg` before the export:

    python3 tools/stamp_release_version.py                    # from packaging/version.txt
    python3 tools/stamp_release_version.py --version 0.1.0-rc.1
    python3 tools/stamp_release_version.py --check             # what the repository says

A version is `MAJOR.MINOR.PATCH` with an optional `-prerelease` tail. The tail is a tag and
file-name thing and cannot go into a version resource, which holds four integers, so the
executable gets `MAJOR.MINOR.PATCH.0` and the package keeps the full string. That split is
the same rule `tools/verify_build.py --package` applies when it compares the two; both read
it from here.

`--check` is what keeps the committed preset honest: the repository is supposed to say
"this is version 0.1.0", and a preset that says something else means somebody exported by
hand and left the difference behind.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import export_presets  # noqa: E402  (sibling tool, imported after the path is set up)

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PRESETS = ROOT / "export_presets.cfg"
VERSION_FILE = ROOT / "packaging" / "version.txt"

# The preset this tool stamps. Written out rather than "the first preset", because a
# repository with two presets and one of them Windows is exactly the situation this exists
# for.
WINDOWS_PRESET = "Windows Desktop"

# The fields a version resource is built from. The first two hold the version; the rest are
# set in the preset itself and only checked here, since they do not change per build.
STAMPED = ("application/file_version", "application/product_version")

_VERSION = re.compile(r"^(?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)(?:-(?P<tail>[0-9A-Za-z][0-9A-Za-z.-]*))?$")


class VersionError(Exception):
    """A version string, or a preset, that cannot be used as-is."""


def parse(version: str) -> dict[str, str]:
    """Split a version into its four-part resource form and its package form."""
    match = _VERSION.match(version.strip())
    if not match:
        raise VersionError(
            f"{version!r} is not MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-prerelease, "
            "which is the only shape a tag and a Windows version resource share"
        )
    parts = [match.group("major"), match.group("minor"), match.group("patch")]
    for part in parts:
        if int(part) > 65535:
            # A version resource is four 16-bit halves; 70000.0.0 fits in a tag and not in
            # the file it is supposed to name.
            raise VersionError(f"{version!r}: {part} does not fit in a 16-bit version field")
    return {
        "full": version.strip(),
        "core": ".".join(parts),
        "resource": ".".join(parts) + ".0",
        "prerelease": match.group("tail") or "",
    }


def read_version_file(path: Path) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise VersionError(f"cannot read {path}: {error}") from error
    lines = [line.strip() for line in text.splitlines() if line.strip() and not line.startswith("#")]
    if len(lines) != 1:
        raise VersionError(f"{path} should hold exactly one version line, found {len(lines)}")
    return lines[0]


def stamp(text: str, resource_version: str, preset: str = WINDOWS_PRESET) -> str:
    """Return `export_presets.cfg` text with the version fields of one preset set."""
    for key in STAMPED:
        text = export_presets.set_option(text, preset, key, resource_version)
    return text


def check(text: str, expected: dict[str, str], preset: str = WINDOWS_PRESET) -> list[str]:
    """What the committed preset says instead of the version it is supposed to carry."""
    presets = export_presets.parse(text)
    if preset not in presets:
        return [f"export_presets.cfg has no preset named {preset!r}"]
    problems = []
    for key in STAMPED:
        actual = presets[preset].options.get(key)
        if actual != expected["resource"]:
            problems.append(
                f'{preset} {key} is {actual!r}, {expected["full"]} needs '
                f'{expected["resource"]!r}: run tools/stamp_release_version.py'
            )
    return problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--version",
        help="the version to stamp; defaults to the single line in packaging/version.txt",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="report whether the committed preset still carries the version it claims",
    )
    parser.add_argument("--presets", type=Path, default=PRESETS, help=argparse.SUPPRESS)
    arguments = parser.parse_args(argv)

    try:
        version = parse(arguments.version or read_version_file(VERSION_FILE))
    except VersionError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1

    try:
        text = arguments.presets.read_text(encoding="utf-8")
    except OSError as error:
        print(f"FAIL: cannot read {arguments.presets}: {error}", file=sys.stderr)
        return 1

    if arguments.check:
        try:
            problems = check(text, version)
        except VersionError as error:
            print(f"FAIL: {error}", file=sys.stderr)
            return 1
        for problem in problems:
            print(f"FAIL: {problem}", file=sys.stderr)
        if problems:
            return 1
        print(
            f"RELEASE_VERSION_OK: the {WINDOWS_PRESET} preset carries {version['full']} "
            f"(file and product version {version['resource']})."
        )
        return 0

    try:
        updated = stamp(text, version["resource"])
    except export_presets.PresetError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    if updated != text:
        arguments.presets.write_text(updated, encoding="utf-8")
        print(f"stamped {arguments.presets.name}: file and product version {version['resource']}")
    else:
        print(f"{arguments.presets.name} already carried {version['resource']}")
    print(
        f"RELEASE_VERSION_STAMPED: {version['full']} -> {version['resource']} in the "
        f"{WINDOWS_PRESET} preset; the package will be named {version['full']}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
