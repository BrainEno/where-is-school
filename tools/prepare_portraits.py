#!/usr/bin/env python3
"""Derive the shipped dialogue portraits from their sources in `art/portraits/`.

The three portraits (the protagonist, Q and N) arrive as large painted images: 1145x1374
to 1280x1936 pixels and 2.4 to 3.6 MB each. Every one of them is over the 2 MiB texture
limit `tools/verify_build.py` holds a shipped file to, and every one is bigger than the
dialogue panel ever draws it (the tallest is 72% of a 1080-pixel-high window, about 780
pixels). So the split is the same as for the fonts and the .blend files:

- `art/portraits/*` - the untouched sources as the owner supplied them. `art/portraits/.gdignore`
  keeps Godot from importing them, so they never reach a build.
- `assets/ui/portraits/*.webp` - what the game loads: cropped to the part of the picture the
  panel shows, scaled to `TARGET_HEIGHT`, and saved as high-quality WebP. Godot re-encodes
  them once more on import (lossy WebP, see the `.import` sidecars) so the packed texture
  stays well under the 512 KiB texture warning line.

The crop of each portrait is a composition decision and lives here, in pixels of the
source, so it can be reviewed and changed in one place:

- the protagonist keeps the whole bust and loses only the ragged cardboard edge;
- Q keeps the pointing hand and the face and loses the empty right edge, so he reads at a
  useful size inside the panel's width cap instead of as a small square;
- N is a full-length standing figure; the panel cannot show that at a readable size, so
  she is cut just above the knees, with her hands, her cardigan and the light ground
  around her still in the picture.

Usage (Pillow is the only dependency; nothing in CI runs this):

    pip install pillow
    python3 tools/prepare_portraits.py           # rewrite assets/ui/portraits/*.webp
    python3 tools/prepare_portraits.py --check   # verify the shipped files match
"""

from __future__ import annotations

import argparse
import hashlib
import io
import sys
from dataclasses import dataclass
from pathlib import Path

SOURCE_DIR = Path("art/portraits")
OUTPUT_DIR = Path("assets/ui/portraits")

# Height of every shipped portrait. The panel draws them at most at 72% of the window
# height; 1100 px covers a 1440p window at full size and leaves mipmaps to do the rest.
TARGET_HEIGHT = 1100
WEBP_QUALITY = 92


@dataclass(frozen=True)
class Portrait:
    """One source image and how it is cut for the dialogue panel."""

    name: str
    source: str
    # (left, top, right, bottom) in source pixels.
    crop: tuple[int, int, int, int]
    # sha256 of the source as supplied, so a silently replaced file is noticed.
    source_sha256: str


PORTRAITS = (
    Portrait(
        "protagonist",
        "protagonist.png",
        (20, 20, 1125, 1354),
        "2b8494996f8569977a94b4a79e34aa866ae98f933d1b563bfc2aed5aad9c7b2b",
    ),
    Portrait(
        "q",
        "q.webp",
        (25, 20, 1085, 1254),
        "993a6055dfa537ef790e8034823bf2dff77e4fdc428f1098b4444caca165d386",
    ),
    Portrait(
        "n",
        "n.webp",
        (180, 30, 1150, 1500),
        "2417a5b79db609d754ad2bc78705bf0fad495af7f4fa7ab82f65612679feae3d",
    ),
)


def render(portrait: Portrait) -> bytes:
    """The shipped WebP for one portrait. Deterministic for a given Pillow version."""
    from PIL import Image  # imported here so --help works without Pillow

    source = SOURCE_DIR / portrait.source
    if not source.is_file():
        raise SystemExit(f"{source} is missing; the shipped portrait is derived from it.")
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != portrait.source_sha256:
        raise SystemExit(
            f"{source} is not the file the crop was chosen for (sha256 {digest}); "
            "review the crop and update PORTRAITS before regenerating."
        )
    with Image.open(source) as image:
        cropped = image.convert("RGB").crop(portrait.crop)
    width = round(cropped.width * TARGET_HEIGHT / cropped.height)
    scaled = cropped.resize((width, TARGET_HEIGHT), Image.Resampling.LANCZOS)
    buffer = io.BytesIO()
    scaled.save(buffer, "WEBP", quality=WEBP_QUALITY, method=6)
    return buffer.getvalue()


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the shipped portraits instead of rewriting them",
    )
    arguments = parser.parse_args(argv)
    if not SOURCE_DIR.is_dir():
        raise SystemExit(f"run this from the repository root ({SOURCE_DIR} not found)")

    status = 0
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for portrait in PORTRAITS:
        output = OUTPUT_DIR / f"{portrait.name}.webp"
        data = render(portrait)
        if arguments.check:
            if not output.is_file() or output.read_bytes() != data:
                print(f"FAIL: {output} is not what this script derives from its source", file=sys.stderr)
                status = 1
            else:
                print(f"PASS: {output} ({len(data) / 1024:.0f} KiB)")
            continue
        output.write_bytes(data)
        print(f"{output}: {len(data) / 1024:.0f} KiB")
    return status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
