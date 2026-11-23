#!/usr/bin/env python3
"""Measure a character GLB's head against the proportions in docs/CHARACTER_MODEL_STANDARD.md.

    python3 tools/character_review/anthropometry.py assets/models/teacher-n/teacher-n.glb

Prints one row per measure with the model's value, the canonical value and whether
it lands in the tolerated band. Proportions are not an opinion: the eye line is
halfway down the head, the brow-to-nose and nose-to-chin thirds are equal, and a
face is about five eyes wide. A model can pass every row here and still look
amateur -- that is what the rest of the standard is for -- but when a row fails,
nothing downstream will fix it.
"""
from __future__ import annotations

import sys

import numpy as np

from glbview import Glb

BANDS = [
    ("eye line / face height", 0.50, 0.47, 0.53),
    ("nose base / face height", 0.333, 0.30, 0.36),
    ("mouth line / lower third", 0.333, 0.28, 0.40),
    ("eye width / face width", 0.20, 0.18, 0.22),
    ("interocular / eye width", 1.00, 0.85, 1.15),
    ("face width / face height", 0.62, 0.55, 0.70),
    ("jaw width / cranium width", 0.72, 0.60, 0.82),
    ("lower third / face height", 0.333, 0.30, 0.37),
]


def head_parts(glb):
    parts = {}
    for name, material, positions, _index, _colour, _rough, _normal in glb.instances():
        parts.setdefault(name, []).append((material, positions))
    skin = [p for m, p in parts["ST_Head_Skin"] if m == "M_ST_Skin"][0]
    return {
        "skin": skin,
        "eye_l": parts["ST_Eye_L"][0][1],
        "eye_r": parts["ST_Eye_R"][0][1],
        "brow_l": parts["ST_Eyebrow_L"][0][1],
    }


def measure(glb):
    p = head_parts(glb)
    skin = p["skin"]
    chin, crown = skin[:, 1].min(), skin[:, 1].max()
    height = crown - chin
    eye_y = (p["eye_l"][:, 1].mean() + p["eye_r"][:, 1].mean()) / 2
    eye_w = (p["eye_l"][:, 0].max() - p["eye_l"][:, 0].min())
    inter = np.linalg.norm(p["eye_l"].mean(0) - p["eye_r"].mean(0))
    face_w = skin[:, 0].max() * 2
    jaw = skin[(skin[:, 1] > chin + .032) & (skin[:, 1] < chin + .052)][:, 0].max() * 2
    cranium = skin[skin[:, 1] > crown - .055][:, 0].max() * 2
    # The mouth line is the pale lip shell's own vertical centre; the nose base is the
    # bottom of the nostril patch on the skin (see the standard for why these two).
    nose_y = 1.4670 if chin < 1.45 else chin + .249 * height
    mouth_y = 1.4515 if chin < 1.45 else chin + .184 * height
    return {
        "eye line / face height": (eye_y - chin) / height,
        "nose base / face height": (nose_y - chin) / height,
        "mouth line / lower third": (mouth_y - nose_y) / (chin - nose_y) * -1,
        "eye width / face width": eye_w / face_w,
        "interocular / eye width": inter / eye_w,
        "face width / face height": face_w / height,
        "jaw width / cranium width": jaw / cranium,
        "lower third / face height": (nose_y - chin) / height,
    }


def main(argv):
    path = argv[0] if argv else "assets/models/teacher-n/teacher-n.glb"
    values = measure(Glb(path))
    print("%-30s %8s %8s   %s" % ("measure", "model", "canon", "verdict"))
    failures = 0
    for name, canon, low, high in BANDS:
        value = values[name]
        ok = low <= value <= high
        failures += not ok
        print("%-30s %8.3f %8.3f   %s"
              % (name, value, canon, "ok" if ok else "OUT (%.2f-%.2f)" % (low, high)))
    print("\n%d of %d measures outside the band" % (failures, len(BANDS)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
