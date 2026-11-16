#!/usr/bin/env python3
"""Writes the character art review looks (issue #188, development only).

    python3 scenes/dev/character_art_review/build_review_looks.py          # write all six
    python3 scenes/dev/character_art_review/build_review_looks.py --check  # fail if stale

Output (committed, read only by the review scene and its capture):
    scenes/dev/character_art_review/looks/d1_stage_{protagonist,q}.tres
    scenes/dev/character_art_review/looks/d2_pastel_{protagonist,q}.tres
    scenes/dev/character_art_review/looks/d3_planes_{protagonist,q}.tres

Each file is a production `CharacterLook` (scripts/actors/character_look.gd, used read-only):
one ShaderMaterial per GLB material name, on one of the review shaders in
`scenes/dev/character_art_review/shaders/`, with `review_outline.gdshader` as `next_pass`
on the parts that carry a contour. `CharacterLookApplier` swaps them in at run time exactly
as it does the production look, so nothing in the GLBs, the wrappers, the production looks
or the production shaders changes. Colours are sRGB hex; positions are the models' rest
space in metres (+Y up, +Z forward, +X the character's left), measured from the GLBs.

Procedural, no third-party data. Standard library only.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = "res://scenes/dev/character_art_review"
SCRIPT = "res://scripts/actors/character_look.gd"
OUTLINE_SHADER = f"{HERE}/shaders/review_outline.gdshader"

# Rest-space landmarks (measured from the GLBs; see docs/CHARACTER_ART.md §2 for the models).
P_UNDER_EYE = dict(center=(0.034, 1.565, 0.104), radius=(0.03, 0.02, 0.034))
P_CHEEK_HOLLOW = dict(center=(0.052, 1.528, 0.088), radius=(0.022, 0.03, 0.04))
P_NOSE = dict(center=(0.0, 1.545, 0.142), radius=(0.02, 0.022, 0.03))
P_KNUCKLES = dict(center=(0.487, 0.836, 0.025), radius=(0.032, 0.036, 0.045))
Q_CHEEKS = dict(center=(0.044, 1.488, 0.112), radius=(0.034, 0.028, 0.045))
Q_EARS = dict(center=(0.108, 1.49, 0.01), radius=(0.028, 0.042, 0.04))
Q_MIRROR = -0.012

# The protagonist's face: the model's own blend shapes, held further towards the owner's
# Protagonist_Face_Test than production C (BrowCompress 0.45, LipTension 0.35).
TENSE_FACE = {"BrowCompress": 0.62, "LipTension": 0.52, "Frown": 0.24, "Blink_L": 0.2, "Blink_R": 0.26}


def patch(slot: int, spec: dict, colour: str, strength: float) -> dict:
    prefix = "patch" if slot == 1 else "patch2"
    return {
        f"{prefix}_center": spec["center"],
        f"{prefix}_radius": spec["radius"],
        f"{prefix}_color": colour,
        f"{prefix}_strength": strength,
    }


# --- D1: stage light ----------------------------------------------------------------------
D1_P = {
    "key_direction": (0.15, 1.0, 0.3),
    "threshold": 0.22,
    "key_color": "#F2F0E6",
    "shadow_color": "#28314F",
    "edge_color": "#7A3550",
    "stage_share": 0.72,
    "pool_low": 0.35,
    "pool_high": 1.5,
    "pool_floor": 0.5,
}
D1_Q = {
    "key_direction": (-0.3, -0.6, 0.75),
    "threshold": 0.05,
    "key_color": "#FFE2B0",
    "shadow_color": "#3A1A14",
    "edge_color": "#D0602A",
    "stage_share": 0.72,
    "pool_invert": True,
    "pool_low": 0.2,
    "pool_high": 1.7,
    "pool_floor": 0.55,
}


def part(*bases: dict, **settings) -> dict:
    """The shared settings of a direction, then any overrides, then this part's own."""
    out: dict = {}
    for base in bases:
        out.update(base)
    out.update(settings)
    return out


D1_PROTAGONIST = {
    "label": "review D1 stage light: protagonist",
    "shader": f"{HERE}/shaders/review_stage_light.gdshader",
    "outline": {"ink": "#120E14", "width": 0.012},
    "parts": {
        "protagonist_mat_skin": part(
            D1_P, albedo="#D8CDB4", shadow_local=0.35, edge_color="#8C3A4A",
            **patch(1, P_UNDER_EYE, "#4A3A66", 0.8), **patch(2, P_CHEEK_HOLLOW, "#7C8A78", 0.5), outline=True,
        ),
        "protagonist_mat_skinbody": part(D1_P, albedo="#CBBFA6", shadow_local=0.35, outline=True),
        "protagonist_mat_hair": part(D1_P, albedo="#2A2630", shadow_color="#0E0F1C", edge_color="#3A3550", edge_strength=0.4, outline=True),
        "protagonist_head/protagonist_mat_hair": part(D1_P, albedo="#2A2427", shadow_color="#141420", edge_strength=0.0, outline=False),
        "protagonist_mat_jacket": part(D1_P, albedo="#3E4A5C", shadow_color="#141A2E", edge_color="#5A3A6A", outline=True),
        "protagonist_mat_button": part(D1_P, albedo="#9A7A4A", edge_strength=0.0, outline=False),
        "protagonist_mat_shirt": part(D1_P, albedo="#D8D2BE", outline=False),
        "protagonist_mat_trousers": part(D1_P, albedo="#5A4A3E", shadow_color="#1C1820", edge_color="#6A3A30", outline=True),
        "protagonist_mat_shoes": part(D1_P, albedo="#2A2220", shadow_color="#100C0C", edge_strength=0.2, outline=True),
        "protagonist_mat_sclera": part(D1_P, albedo="#E0DACA", shadow_color="#6A7088", shadow_local=0.5, edge_strength=0.0, outline=False),
        "protagonist_mat_iris": part(D1_P, albedo="#3B2B23", shadow_color="#1A1414", edge_strength=0.0, outline=False),
        "protagonist_mat_pupil": part(D1_P, albedo="#0F0C0B", shadow_color="#050404", edge_strength=0.0, outline=False),
        "protagonist_mat_mouthinner": part(D1_P, albedo="#4A201D", shadow_color="#1A0A0A", edge_strength=0.0, outline=False),
    },
    "expression": TENSE_FACE,
    "blink_shapes": ["Blink_L", "Blink_R"],
    "blink_interval": (1.6, 3.8),
    "blink_duration": 0.15,
}
D1_QLOOK = {
    "label": "review D1 stage light: Q",
    "shader": f"{HERE}/shaders/review_stage_light.gdshader",
    "outline": {"ink": "#120E14", "width": 0.012},
    "parts": {
        "q_mat_skin": part(
            D1_Q, albedo="#E0A070", shadow_local=0.4,
            **patch(1, Q_CHEEKS, "#D0402A", 0.6), **patch(2, Q_EARS, "#C8503A", 0.5),
            mirror_center_x=Q_MIRROR, outline=True,
        ),
        "q_mat_hair": part(D1_Q, albedo="#1C1820", shadow_color="#0C0A0E", edge_strength=0.35, outline=True),
        "q_mat_brow": part(D1_Q, albedo="#1F1A1C", edge_strength=0.0, outline=False),
        "q_mat_eye": part(D1_Q, albedo="#E8DCC0", shadow_color="#7A6050", shadow_local=0.5, edge_strength=0.0, outline=False),
        "q_mat_iris": part(D1_Q, albedo="#2B1D15", edge_strength=0.0, outline=False),
        "q_mat_pupil": part(D1_Q, albedo="#0C0A09", edge_strength=0.0, outline=False),
        "q_mat_lip": part(D1_Q, albedo="#B04030", edge_strength=0.0, outline=False),
        "q_mat_mouthdark": part(D1_Q, albedo="#3B1713", edge_strength=0.0, outline=False),
        "q_mat_teeth": part(D1_Q, albedo="#E0D0B0", shadow_color="#6A5040", edge_strength=0.0, outline=False),
        "q_mat_cloth": part(D1_Q, albedo="#6E8A3C", shadow_color="#23301A", edge_color="#D07A2A", outline=True),
        "q_mat_collar": part(D1_Q, albedo="#C0A060", edge_strength=0.0, outline=False),
        "q_mat_pants": part(D1_Q, albedo="#2E3A5A", shadow_color="#12162A", edge_color="#8A4A3A", outline=True),
        "q_mat_shoes": part(D1_Q, albedo="#3A2A20", shadow_color="#140E0A", outline=True),
        "q_mat_sole": part(D1_Q, albedo="#C0B090", edge_strength=0.0, outline=False),
    },
    "expression": {},
    "blink_shapes": [],
    "blink_interval": (2.5, 5.0),
    "blink_duration": 0.16,
}

# --- D2: charcoal and oil pastel ----------------------------------------------------------
D2_P = {
    "key_direction": (-0.3, 0.85, 0.45),
    "hatch_angle": 1.25,
    "cross_angle": -0.35,
    "hatch_start": 0.6,
    "cross_start": 0.32,
    "charcoal": "#1A1A20",
    "boil_fps": 6.0,
    "spacing_px": 6.5,
    "hatch_strength": 0.85,
}
D2_Q = {
    "key_direction": (0.35, 0.7, 0.6),
    "hatch_angle": 0.25,
    "cross_angle": 1.4,
    "hatch_start": 0.45,
    "cross_start": 0.2,
    "charcoal": "#2E2018",
    "boil_fps": 6.0,
    "spacing_px": 8.0,
    "hatch_strength": 0.75,
    "grain_amount": 0.42,
}
NO_HATCH = {"hatch_start": 0.0, "cross_start": 0.0, "grain_amount": 0.0}
SKIN_HATCH = {"hatch_start": 0.36, "cross_start": 0.0, "hatch_strength": 0.6}

D2_PROTAGONIST = {
    "label": "review D2 charcoal and pastel: protagonist",
    "shader": f"{HERE}/shaders/review_pastel.gdshader",
    "outline": {"ink": "#1A1A20", "width": 0.011, "width_variation": 0.85, "gap": 0.18, "boil_fps": 6.0},
    "parts": {
        "protagonist_mat_skin": part(
            D2_P, SKIN_HATCH, albedo="#D9CFB8", pastel_b="#C8CCB0", grain_amount=0.25, shade_tint="#8FA0B8",
            **patch(1, P_UNDER_EYE, "#6A4A7A", 0.85), **patch(2, P_NOSE, "#C0503A", 0.55), outline=True,
        ),
        "protagonist_mat_skinbody": part(D2_P, albedo="#D2C6AC", pastel_b="#B8C4A8", grain_amount=0.3, shade_tint="#8FA0B8", outline=True),
        "protagonist_hands/protagonist_mat_skinbody": part(
            D2_P, albedo="#D2C6AC", pastel_b="#C8A890", grain_amount=0.3, shade_tint="#8FA0B8",
            **patch(1, P_KNUCKLES, "#C04A3A", 0.65), outline=True,
        ),
        "protagonist_mat_hair": part(D2_P, albedo="#2A2628", pastel_b="#3A3448", grain_amount=0.4, shade_tint="#C0C0D0", outline=True),
        "protagonist_head/protagonist_mat_hair": part(D2_P, NO_HATCH, albedo="#2A2427", pastel_b="#2A2427", outline=False),
        "protagonist_mat_jacket": part(D2_P, albedo="#4A5260", pastel_b="#424B5E", grain_amount=0.25, shade_tint="#8088A8", hatch_strength=0.9, outline=True),
        "protagonist_mat_button": part(D2_P, NO_HATCH, albedo="#A08050", pastel_b="#A08050", outline=False),
        "protagonist_mat_shirt": part(D2_P, albedo="#E0D8C0", pastel_b="#D0D4C4", grain_amount=0.25, shade_tint="#A0A8B8", outline=False),
        "protagonist_mat_trousers": part(D2_P, albedo="#5A4E44", pastel_b="#4A4038", grain_amount=0.35, shade_tint="#8A86A0", outline=True),
        "protagonist_mat_shoes": part(D2_P, albedo="#2E2624", pastel_b="#3A2E28", outline=True),
        "protagonist_mat_sclera": part(D2_P, NO_HATCH, albedo="#E4DCC8", pastel_b="#E4DCC8", outline=False),
        "protagonist_mat_iris": part(D2_P, NO_HATCH, albedo="#3B2B23", pastel_b="#3B2B23", outline=False),
        "protagonist_mat_pupil": part(D2_P, NO_HATCH, albedo="#0F0C0B", pastel_b="#0F0C0B", outline=False),
        "protagonist_mat_mouthinner": part(D2_P, NO_HATCH, albedo="#4A201D", pastel_b="#4A201D", outline=False),
    },
    "expression": TENSE_FACE,
    "blink_shapes": ["Blink_L", "Blink_R"],
    "blink_interval": (1.6, 3.8),
    "blink_duration": 0.15,
}
D2_QLOOK = {
    "label": "review D2 charcoal and pastel: Q",
    "shader": f"{HERE}/shaders/review_pastel.gdshader",
    "outline": {"ink": "#2E2018", "width": 0.011, "width_variation": 0.7, "gap": 0.1, "boil_fps": 6.0},
    "parts": {
        "q_mat_skin": part(
            D2_Q, SKIN_HATCH, albedo="#EBB88A", pastel_b="#EDAA7C", grain_amount=0.25, shade_tint="#A0A878",
            **patch(1, Q_CHEEKS, "#D8503A", 0.7), **patch(2, Q_EARS, "#D05A40", 0.6),
            mirror_center_x=Q_MIRROR, outline=True,
        ),
        "q_mat_hair": part(D2_Q, albedo="#221C20", pastel_b="#3A2A2A", shade_tint="#C0C0C0", outline=True),
        "q_mat_brow": part(D2_Q, NO_HATCH, albedo="#1F1A1C", pastel_b="#1F1A1C", outline=False),
        "q_mat_eye": part(D2_Q, NO_HATCH, albedo="#E8DCC0", pastel_b="#E8DCC0", outline=False),
        "q_mat_iris": part(D2_Q, NO_HATCH, albedo="#2B1D15", pastel_b="#2B1D15", outline=False),
        "q_mat_pupil": part(D2_Q, NO_HATCH, albedo="#0C0A09", pastel_b="#0C0A09", outline=False),
        "q_mat_lip": part(D2_Q, NO_HATCH, albedo="#B84838", pastel_b="#B84838", outline=False),
        "q_mat_mouthdark": part(D2_Q, NO_HATCH, albedo="#3B1713", pastel_b="#3B1713", outline=False),
        "q_mat_teeth": part(D2_Q, NO_HATCH, albedo="#E0D0B0", pastel_b="#E0D0B0", outline=False),
        "q_mat_cloth": part(D2_Q, albedo="#7A9A4A", pastel_b="#93A852", grain_amount=0.22, shade_tint="#7080A0", outline=True),
        "q_mat_collar": part(D2_Q, NO_HATCH, albedo="#D0B070", pastel_b="#D0B070", outline=False),
        "q_mat_pants": part(D2_Q, albedo="#3A4868", pastel_b="#42517A", grain_amount=0.18, shade_tint="#8888A8", outline=True),
        "q_mat_shoes": part(D2_Q, albedo="#4A3428", pastel_b="#5A4030", outline=True),
        "q_mat_sole": part(D2_Q, NO_HATCH, albedo="#D0C0A0", pastel_b="#D0C0A0", outline=False),
    },
    "expression": {},
    "blink_shapes": [],
    "blink_interval": (2.5, 5.0),
    "blink_duration": 0.16,
}

# --- D3: expressionist colour planes ------------------------------------------------------


def planes(key: str, side: str, top: str, under: str, back: str, **extra) -> dict:
    out = {"plane_key": key, "plane_side": side, "plane_top": top, "plane_under": under, "plane_back": back}
    out.update(extra)
    return out


def flat(colour: str, **extra) -> dict:
    return planes(colour, colour, colour, colour, colour, gouge_strength=0.0, **extra)


D3_PROTAGONIST = {
    "label": "review D3 colour planes: protagonist",
    "shader": f"{HERE}/shaders/review_color_planes.gdshader",
    "outline": {"ink": "#141018", "width": 0.013},
    "parts": {
        "protagonist_mat_skin": planes(
            "#CBC39E", "#9EAE9A", "#DED3AE", "#8E7282", "#76809A", shade_tint="#6070A8", jitter=0.2,
            **patch(1, P_UNDER_EYE, "#3A3070", 0.85), **patch(2, P_CHEEK_HOLLOW, "#5E8070", 0.5), outline=True,
        ),
        "protagonist_mat_skinbody": planes("#C2B994", "#97A693", "#D4C9A2", "#86697A", "#6E7892", shade_tint="#6070A8", jitter=0.2, outline=True),
        "protagonist_mat_hair": planes("#2C2A3A", "#1E2230", "#3A3A55", "#181418", "#141620", gouge_strength=0.3, outline=True),
        "protagonist_head/protagonist_mat_hair": flat("#2A2427", outline=False),
        "protagonist_mat_jacket": planes("#3E4E70", "#2A3048", "#56688C", "#1E1E30", "#22283E", shade_tint="#5058A0", outline=True),
        "protagonist_mat_button": flat("#A08048", outline=False),
        "protagonist_mat_shirt": planes("#E0DCC0", "#B0B8A8", "#F0E8D0", "#8A8478", "#9A9AA0", outline=False),
        "protagonist_mat_trousers": planes("#6A5040", "#4A3A34", "#7A6048", "#2E2420", "#3A2E2A", outline=True),
        "protagonist_mat_shoes": planes("#2E2624", "#221C1C", "#3A302C", "#141010", "#181414", gouge_strength=0.0, outline=True),
        "protagonist_mat_sclera": flat("#E0DACA", shadow_fill=0.7, outline=False),
        "protagonist_mat_iris": flat("#3B2B23", shadow_fill=0.6, outline=False),
        "protagonist_mat_pupil": flat("#0F0C0B", outline=False),
        "protagonist_mat_mouthinner": flat("#4A201D", outline=False),
    },
    "expression": TENSE_FACE,
    "blink_shapes": ["Blink_L", "Blink_R"],
    "blink_interval": (1.6, 3.8),
    "blink_duration": 0.15,
}
D3_QLOOK = {
    "label": "review D3 colour planes: Q",
    "shader": f"{HERE}/shaders/review_color_planes.gdshader",
    "outline": {"ink": "#141018", "width": 0.013},
    "parts": {
        "q_mat_skin": planes(
            "#EDA46C", "#DC8268", "#F2BC84", "#B88E62", "#C27C5A", shade_tint="#7A8A60", jitter=0.18,
            **patch(1, Q_CHEEKS, "#E03A2A", 0.65), **patch(2, Q_EARS, "#D84030", 0.6),
            mirror_center_x=Q_MIRROR, outline=True,
        ),
        "q_mat_hair": planes("#26202A", "#1C1820", "#3A3040", "#141014", "#141014", gouge_strength=0.3, outline=True),
        "q_mat_brow": flat("#1F1A1C", outline=False),
        "q_mat_eye": flat("#E8DCC0", shadow_fill=0.7, outline=False),
        "q_mat_iris": flat("#2B1D15", outline=False),
        "q_mat_pupil": flat("#0C0A09", outline=False),
        "q_mat_lip": flat("#C03A2A", outline=False),
        "q_mat_mouthdark": flat("#3B1713", outline=False),
        "q_mat_teeth": flat("#E0D0B0", shadow_fill=0.6, outline=False),
        "q_mat_cloth": planes("#8AB040", "#4A8060", "#C0C858", "#2E4A3A", "#3A5A50", shade_tint="#5A6A90", outline=True),
        "q_mat_collar": flat("#D0A850", outline=False),
        "q_mat_pants": planes("#3A4E80", "#2A3460", "#5068A0", "#1A2038", "#222A48", outline=True),
        "q_mat_shoes": planes("#5A3A26", "#3E2A1E", "#6A4A30", "#22160E", "#2A1C14", gouge_strength=0.0, outline=True),
        "q_mat_sole": flat("#D0C0A0", outline=False),
    },
    "expression": {},
    "blink_shapes": [],
    "blink_interval": (2.5, 5.0),
    "blink_duration": 0.16,
}

TARGETS = {
    "scenes/dev/character_art_review/looks/d1_stage_protagonist.tres": D1_PROTAGONIST,
    "scenes/dev/character_art_review/looks/d1_stage_q.tres": D1_QLOOK,
    "scenes/dev/character_art_review/looks/d2_pastel_protagonist.tres": D2_PROTAGONIST,
    "scenes/dev/character_art_review/looks/d2_pastel_q.tres": D2_QLOOK,
    "scenes/dev/character_art_review/looks/d3_planes_protagonist.tres": D3_PROTAGONIST,
    "scenes/dev/character_art_review/looks/d3_planes_q.tres": D3_QLOOK,
}


def colour(hex_value: str) -> str:
    value = hex_value.lstrip("#")
    r, g, b = (int(value[i : i + 2], 16) / 255.0 for i in (0, 2, 4))
    return f"Color({r:.4f}, {g:.4f}, {b:.4f}, 1)"


def parameter(value: object) -> str:
    if isinstance(value, str) and value.startswith("#"):
        return colour(value)
    if isinstance(value, tuple):
        return "Vector3({:g}, {:g}, {:g})".format(*value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return f"{value:g}"
    return str(value)


def sub_id(name: str) -> str:
    return "m_" + name.replace("/", "__")


def render(look: dict) -> str:
    parts: dict = look["parts"]
    lines = [
        f'[gd_resource type="Resource" script_class="CharacterLook" load_steps={3 + 1 + len(parts) + 1} format=3]',
        "",
        f'[ext_resource type="Script" path="{SCRIPT}" id="1_look"]',
        f'[ext_resource type="Shader" path="{look["shader"]}" id="2_surface"]',
        f'[ext_resource type="Shader" path="{OUTLINE_SHADER}" id="3_outline"]',
        "",
        '[sub_resource type="ShaderMaterial" id="outline"]',
        'resource_name = "review_outline"',
        'shader = ExtResource("3_outline")',
    ]
    for key in sorted(look["outline"]):
        lines.append(f"shader_parameter/{key} = {parameter(look['outline'][key])}")
    lines.append("")
    for name, part in parts.items():
        settings = dict(part)
        outline = bool(settings.pop("outline"))
        lines.append(f'[sub_resource type="ShaderMaterial" id="{sub_id(name)}"]')
        lines.append(f'resource_name = "{name} (review)"')
        if outline:
            lines.append('next_pass = SubResource("outline")')
        lines.append('shader = ExtResource("2_surface")')
        for key in sorted(settings):
            lines.append(f"shader_parameter/{key} = {parameter(settings[key])}")
        lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_look")')
    entries = ",\n".join(f'"{name}": SubResource("{sub_id(name)}")' for name in parts)
    lines.append("materials = {\n" + entries + "\n}")
    expression = ",\n".join(f'"{shape}": {weight:g}' for shape, weight in look["expression"].items())
    lines.append("expression = {\n" + expression + "\n}" if expression else "expression = {}")
    shapes = ", ".join(f'"{shape}"' for shape in look["blink_shapes"])
    lines.append(f"blink_shapes = PackedStringArray({shapes})")
    lines.append("blink_interval = Vector2({:g}, {:g})".format(*look["blink_interval"]))
    lines.append(f"blink_duration = {look['blink_duration']:g}")
    lines.append(f'label = "{look["label"]}"')
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail if a written file differs")
    args = parser.parse_args()
    stale = []
    for relative, look in TARGETS.items():
        path = ROOT / relative
        text = render(look)
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                stale.append(relative)
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        print(f"wrote {relative} ({len(look['parts'])} parts)")
    if stale:
        print("out of date (run scenes/dev/character_art_review/build_review_looks.py): " + ", ".join(stale))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
