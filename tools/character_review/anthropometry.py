#!/usr/bin/env python3
"""Measure a character GLB's head against the proportions in docs/CHARACTER_MODEL_STANDARD.md.

    python3 tools/character_review/anthropometry.py assets/models/teacher-n/teacher-n.glb
    python3 tools/character_review/anthropometry.py assets/models/protagonist/Protagonist_Character.glb

Prints one row per measure with the model's value, the canonical value and whether
it lands in the tolerated band. Proportions are not an opinion: the eye line is
halfway down the head, the brow-to-nose and nose-to-chin thirds are equal, and a
face is about five eyes wide. A model can pass every row here and still look
amateur -- that is what the rest of the standard is for -- but when a row fails,
nothing downstream will fix it.

Two layouts are understood: teacher N's (`ST_Head_Skin` and friends) and the
protagonist's (`Protagonist_Head`, one sclera primitive holding both eyes, the
mouth line read off the inner-lip tube). The protagonist faces +Z, carries his
neck inside the skin primitive and has his ears on it too, so his chin is found
where the midline front profile falls away under the chin plane, and his face
width is the cheek-to-cheek width of the front of the face, not the ear tips.
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
    ("inner gap / eye width", 1.00, 0.85, 1.15),
    ("face width / face height", 0.62, 0.55, 0.70),
    ("jaw width / cranium width", 0.72, 0.60, 0.82),
    ("lower third / face height", 0.333, 0.30, 0.37),
]


def nose_base(skin, chin, y_cap=1.53, forward=-1):
    """Where the nose stops protruding from the face, measured on the front midline.

    The nose is the skin, not a mesh, so it is read off the front profile: the tip is the
    most forward point below the eyes, and the base is the lowest height at which the
    profile has come half way from the upper lip's surface out to the tip. `forward` is
    the sign of the face's own axis: teacher N faces -Z, the protagonist +Z. With the
    default arguments this is N's original measurement, unchanged.
    """
    reach = forward * skin[:, 2]
    front = skin[(np.abs(skin[:, 0]) < .004) & (reach > 0) & (skin[:, 1] > chin + .02)
                 & (skin[:, 1] < y_cap)]
    reach = forward * front[:, 2]
    tip = front[np.argmax(reach)]
    lip = front[(front[:, 1] < chin + .05)]
    surface = np.median(forward * lip[:, 2]) if len(lip) else forward * tip[2]
    halfway = (forward * tip[2] + surface) / 2
    below = front[(front[:, 1] < tip[1]) & (forward * front[:, 2] < halfway)]
    return below[:, 1].max() if len(below) else tip[1]


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
        "lip": [p for m, p in parts["ST_Head_Skin"] if m == "M_ST_Lip"][0],
    }


def protagonist_parts(glb):
    parts = {}
    for name, material, positions, _index, _colour, _rough, _normal in glb.instances():
        parts.setdefault((name, material), positions)
    skin = parts[("Protagonist_Head", "Protagonist_Mat_Skin")]
    sclera = parts[("Protagonist_Eyes", "Protagonist_Mat_Sclera")]
    return {
        "skin": skin,
        # one primitive holds both eyeballs: split it on the midline
        "eye_l": sclera[sclera[:, 0] < 0],
        "eye_r": sclera[sclera[:, 0] > 0],
        "lip": parts[("Protagonist_Head", "Protagonist_Mat_MouthInner")],
    }


def protagonist_chin(skin, mouth_y):
    """The menton: the lowest midline height where the front profile is still the chin.

    The skin primitive carries the neck, so its y-min is the neck bottom, not the
    chin, and the midline mesh is sparse: front points cluster, stray interior
    points sit near z = 0, and no fixed point-to-point gap means anything. Walk
    down the mouth-to-chin stretch in 1 mm steps over a +/-2.5 mm window instead
    -- wide enough that a stray point never hides the profile, narrow enough that
    the window falls off the chin before it reaches the neck -- and take the
    lowest real front point above the window where the profile finally dies.
    """
    mid = skin[np.abs(skin[:, 0]) < 0.004]
    lip_z = float(np.median(mid[np.abs(mid[:, 1] - mouth_y) < 0.012][:, 2]))
    front_z = 0.85 * lip_z
    stop = mouth_y - 0.09
    for y0 in np.arange(mouth_y - 0.001, stop, -0.001):
        # Front-surface points only: the closed skin shell carries interior strays
        # near z = 0, and a window full of those is a hole in the midline, not the
        # profile dying (the docstring's own rule; without the filter one stray pair
        # 20 mm above the menton ended the walk early).
        window = mid[(np.abs(mid[:, 1] - y0) < 0.0025) & (mid[:, 2] > 0.02)]
        if len(window) < 2:
            continue  # too sparse to judge: a hole in the midline, not the jawline
        if float(window[:, 2].max()) < front_z:
            stop = y0
            break
    front = mid[(mid[:, 1] >= stop) & (mid[:, 1] < mouth_y) & (mid[:, 2] >= front_z)]
    return float(front[:, 1].min())


def measure_protagonist(glb):
    p = protagonist_parts(glb)
    skin = p["skin"]
    mouth_y = float((p["lip"][:, 1].min() + p["lip"][:, 1].max()) / 2)
    chin = protagonist_chin(skin, mouth_y)
    crown = skin[:, 1].max()
    height = crown - chin
    eye_y = (p["eye_l"][:, 1].mean() + p["eye_r"][:, 1].mean()) / 2
    eye_w = float(p["eye_l"][:, 0].max() - p["eye_l"][:, 0].min())
    inter = float(p["eye_r"][:, 0].min() - p["eye_l"][:, 0].max())
    # cheek-to-cheek across the front of the face: the ears ride at z ~ 0 and the
    # back of the skull is behind, so a plain |x| max would measure the ears.
    front = skin[(skin[:, 1] > eye_y - 0.03) & (skin[:, 1] < eye_y + 0.01) & (skin[:, 2] > 0.04)]
    face_w = 2 * float(np.abs(front[:, 0]).max())
    jaw_band = skin[(skin[:, 1] > chin + 0.032) & (skin[:, 1] < chin + 0.052)]
    jaw = 2 * float(np.abs(jaw_band[:, 0]).max())
    cranium = 2 * float(np.abs(skin[skin[:, 1] > crown - 0.055][:, 0]).max())
    nose_y = nose_base(skin, chin, y_cap=eye_y + 0.01, forward=1)
    return {
        "eye line / face height": (eye_y - chin) / height,
        "nose base / face height": (nose_y - chin) / height,
        "mouth line / lower third": (nose_y - mouth_y) / (nose_y - chin),
        "eye width / face width": eye_w / face_w,
        "inner gap / eye width": inter / eye_w,
        "face width / face height": face_w / height,
        "jaw width / cranium width": jaw / cranium,
        "lower third / face height": (nose_y - chin) / height,
    }


def measure(glb):
    p = head_parts(glb)
    skin = p["skin"]
    chin, crown = skin[:, 1].min(), skin[:, 1].max()
    height = crown - chin
    eye_y = (p["eye_l"][:, 1].mean() + p["eye_r"][:, 1].mean()) / 2
    eye_w = (p["eye_l"][:, 0].max() - p["eye_l"][:, 0].min())
    # "Two eyes apart by exactly one eye" is the gap between the inner corners, not the
    # distance between the eyes' centres (that is about two eye widths in any face).
    inter = p["eye_r"][:, 0].min() - p["eye_l"][:, 0].max()
    face_w = skin[:, 0].max() * 2
    jaw = skin[(skin[:, 1] > chin + .032) & (skin[:, 1] < chin + .052)][:, 0].max() * 2
    cranium = skin[skin[:, 1] > crown - .055][:, 0].max() * 2
    nose_y = nose_base(skin, chin)
    mouth_y = (p["lip"][:, 1].min() + p["lip"][:, 1].max()) / 2
    return {
        "eye line / face height": (eye_y - chin) / height,
        "nose base / face height": (nose_y - chin) / height,
        "mouth line / lower third": (nose_y - mouth_y) / (nose_y - chin),
        "eye width / face width": eye_w / face_w,
        "inner gap / eye width": inter / eye_w,
        "face width / face height": face_w / height,
        "jaw width / cranium width": jaw / cranium,
        "lower third / face height": (nose_y - chin) / height,
    }


def main(argv):
    path = argv[0] if argv else "assets/models/teacher-n/teacher-n.glb"
    glb = Glb(path)
    names = {name for name, *_ in glb.instances()}
    values = measure_protagonist(glb) if "Protagonist_Head" in names else measure(glb)
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
