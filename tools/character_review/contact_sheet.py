#!/usr/bin/env python3
"""Four-view + close-up contact sheet of one character GLB, rendered offline.

    python3 tools/character_review/contact_sheet.py OUT.png GLB [GLB ...]

Each GLB becomes one row: front, three-quarter, profile, back-of-head, and a
close-up of the eyes. Rows can be compared directly, which is how a change to a
face or a haircut gets reviewed without Blender.
"""
from __future__ import annotations

import sys

import numpy as np
from PIL import Image

from glbview import Glb, render

# Camera tables per model: teacher N faces -Z with her eye line at y = 1.534,
# the protagonist faces +Z with his at y = 1.584 (docs/CHARACTER_MODEL_STANDARD.md
# section 1). Getting this wrong frames the back of the head.
N_LOOKS = [
    ("front", (0.00, 1.520, -0.620), 26),
    ("quarter", (-0.30, 1.550, -0.520), 26),
    ("profile", (-0.620, 1.530, -0.050), 26),
    ("back", (0.00, 1.550, 0.580), 26),
    ("eyes", (0.00, 1.534, -0.310), 20),
]
LEAD_LOOKS = [
    ("front", (0.00, 1.575, 0.620), 26),
    ("quarter", (-0.30, 1.600, 0.520), 26),
    ("profile", (-0.620, 1.590, 0.050), 26),
    ("back", (0.00, 1.600, -0.580), 26),
    ("eyes", (0.00, 1.584, 0.310), 20),
]
N_CENTRE = (0.0, 1.520, -0.060), (0.0, 1.534, -0.088)
LEAD_CENTRE = (0.0, 1.575, 0.060), (0.0, 1.584, 0.088)
SIZE = 300


def cameras(glb):
    names = {name for name, *_ in glb.instances()}
    if "Protagonist_Head" in names:
        return LEAD_LOOKS, LEAD_CENTRE
    return N_LOOKS, N_CENTRE


def row(path):
    glb = Glb(path)
    looks, (centre, eye_target) = cameras(glb)
    centre = np.array(centre)
    tiles = []
    for _name, eye, fov in looks:
        target = np.array(eye_target) if fov == 20 else centre
        image = render(glb, np.array(eye), target, size=(SIZE, SIZE), fov=fov,
                       ambient=.34)
        tiles.append((np.clip(image, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8))
    return np.concatenate(tiles, axis=1)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    output, models = argv[1], argv[2:]
    sheet = np.concatenate([row(path) for path in models], axis=0)
    Image.fromarray(sheet).save(output)
    print("wrote %s (%dx%d)" % (output, sheet.shape[1], sheet.shape[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
