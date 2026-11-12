#!/usr/bin/env python3
"""Writes the protagonist's and Q's look resources from the palette below.

    python3 art/characters/build_character_looks.py          # write both
    python3 art/characters/build_character_looks.py --check  # fail if they are out of date

Output (committed, read by the game):
    assets/characters/protagonist/protagonist_look.tres
    assets/characters/q/q_look.tres

Each is a `CharacterLook` (scripts/actors/character_look.gd): one ShaderMaterial per GLB
material, on `assets/shaders/characters/character_paint.gdshader`, with the ink hull
`character_outline.gdshader` as `next_pass` on the parts that carry a line, plus the
protagonist's resting expression on his model's own blend shapes. The GLBs are not
touched: `CharacterLookApplier` swaps the materials in at runtime by name.

The palette is the art direction, so it lives here in one readable table rather than in
two hand-edited resources. Colours are sRGB hex, as the inspector shows them. Positions
(the painted patches) are in the model's rest space, metres, +Y up, +Z forward, measured
from the GLBs (eye joints, sclera and lip bounds; see docs/CHARACTER_ART.md).

No third-party data. Standard library only.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PAINT_SHADER = "res://assets/shaders/characters/character_paint.gdshader"
OUTLINE_SHADER = "res://assets/shaders/characters/character_outline.gdshader"
SCRIPT = "res://scripts/actors/character_look.gd"

INK = "#2B2622"

# Shared defaults for character_paint.gdshader; a part overrides what it needs.
PART_DEFAULTS = {
    "shade_tint": "#A3A6C8",
    "light_tint": "#FFF3E2",
    "shadow_fill": 0.30,
    "half_tone": 0.62,
    "light_strength": 0.76,
    "shadow_edge": -0.05,
    "light_edge": 0.42,
    "edge_softness": 0.05,
    "edge_break": 0.18,
    "pigment_scale": 9.0,
    "pigment_stretch": (1.0, 2.2, 1.0),
    "pigment_steps": 4.0,
    "pigment_value": 0.12,
    "pigment_mix": 0.3,
}

# --- the protagonist ------------------------------------------------------------------
# Cool and held in: a pale, grey-green skin that has not slept, bruised under-eyes that
# make the eyes the first thing read in the face, a slate-black gakuran (the portrait's),
# warm charcoal trousers so jacket and legs separate, near-black hair.
PROTAGONIST_SKIN = {
    "albedo": "#B4A58C",
    "pigment_a": "#98A088",
    "pigment_b": "#C2A68E",
    # Coarse enough to be seen as blocks at the gameplay camera's distance; at 24 the face
    # read as smooth.
    "pigment_mix": 0.46,
    "pigment_value": 0.14,
    "pigment_scale": 15.0,
    "pigment_stretch": (1.0, 1.5, 1.0),
    "shade_tint": "#9AA6C6",
    "light_tint": "#F4EADC",
    "shadow_fill": 0.32,
    # A darker half-tone so the cheekbone, nose and brow ridge keep their planes.
    "half_tone": 0.5,
    "edge_break": 0.24,
    # Less of the face in the full light: the tired face is mostly half-tone.
    "light_edge": 0.55,
    "light_strength": 0.7,
}
PROTAGONIST = {
    "label": "protagonist: painted (option C)",
    "outline_width": 0.009,
    "parts": {
        "protagonist_mat_skin": dict(
            PROTAGONIST_SKIN,
            # Under the eyes: a violet-grey bruise of tiredness (the portrait's).
            patch_center=(0.034, 1.565, 0.104),
            patch_radius=(0.03, 0.02, 0.034),
            patch_color="#665570",
            patch_strength=0.75,
            # The hollow under the cheekbone, greened.
            patch2_center=(0.052, 1.528, 0.088),
            patch2_radius=(0.022, 0.03, 0.04),
            patch2_color="#98997F",
            patch2_strength=0.4,
            outline=True,
        ),
        "protagonist_mat_skinbody": dict(PROTAGONIST_SKIN, albedo="#A99A83", outline=True),
        "protagonist_mat_hair": {
            "albedo": "#221E21",
            "pigment_a": "#2E2B3A",
            "pigment_b": "#3A2E27",
            "pigment_mix": 0.5,
            "pigment_value": 0.25,
            "pigment_scale": 14.0,
            "shade_tint": "#7C7C9C",
            "shadow_fill": 0.4,
            "outline": True,
        },
        # The same material is his eyebrows on the head mesh: no line, or they become blots.
        "protagonist_head/protagonist_mat_hair": {
            "albedo": "#2A2427",
            "pigment_mix": 0.0,
            "pigment_value": 0.0,
            "shade_tint": "#7C7C9C",
            "shadow_fill": 0.5,
            "outline": False,
        },
        "protagonist_mat_jacket": {
            "albedo": "#37414A",
            "pigment_a": "#2B344E",
            "pigment_b": "#48524B",
            "pigment_mix": 0.42,
            "pigment_value": 0.2,
            "pigment_scale": 7.0,
            "pigment_stretch": (1.0, 2.8, 1.0),
            "shade_tint": "#8E84AE",
            "light_tint": "#F6E7D2",
            "shadow_fill": 0.34,
            "outline": True,
        },
        "protagonist_mat_button": {
            "albedo": "#8A6E46",
            "pigment_mix": 0.0,
            "pigment_value": 0.0,
            "shadow_fill": 0.45,
            "outline": False,
        },
        "protagonist_mat_shirt": {
            "albedo": "#CBC2AA",
            "pigment_a": "#BFC2AE",
            "pigment_b": "#D7C6A6",
            "pigment_mix": 0.35,
            "outline": False,
        },
        "protagonist_mat_trousers": {
            "albedo": "#3B3836",
            "pigment_a": "#373247",
            "pigment_b": "#4A4139",
            "pigment_mix": 0.4,
            "pigment_value": 0.18,
            "pigment_scale": 6.5,
            "pigment_stretch": (1.0, 3.2, 1.0),
            "shade_tint": "#8D86A6",
            "outline": True,
        },
        "protagonist_mat_shoes": {
            "albedo": "#2B2321",
            "pigment_a": "#2E2830",
            "pigment_b": "#3A2C24",
            "pigment_mix": 0.4,
            "pigment_value": 0.15,
            "outline": True,
        },
        # The eyes stay light and keep more of their light in shadow: the bruise around them
        # is what makes them prominent, not a bigger eyeball.
        "protagonist_mat_sclera": {
            "albedo": "#D9D0BA",
            "pigment_mix": 0.0,
            "pigment_value": 0.0,
            "shadow_fill": 0.6,
            "half_tone": 0.8,
            "outline": False,
        },
        "protagonist_mat_iris": {
            "albedo": "#3B2B23",
            "pigment_mix": 0.0,
            "pigment_value": 0.0,
            "shadow_fill": 0.6,
            "outline": False,
        },
        "protagonist_mat_pupil": {
            "albedo": "#0F0C0B",
            "pigment_mix": 0.0,
            "pigment_value": 0.0,
            "outline": False,
        },
        "protagonist_mat_mouthinner": {
            "albedo": "#4A201D",
            "pigment_mix": 0.0,
            "pigment_value": 0.0,
            "outline": False,
        },
    },
    # The model's own shapes, at the uneasy setting the owner's Protagonist_Face_Test
    # reaches (BrowCompress 0.8, LipTension 0.7), held well below it; the lids a little
    # heavy and not even.
    "expression": {
        "BrowCompress": 0.45,
        "LipTension": 0.35,
        "Frown": 0.15,
        "Blink_L": 0.1,
        "Blink_R": 0.15,
    },
    "blink_shapes": ["Blink_L", "Blink_R"],
    "blink_interval": (1.8, 4.2),
    "blink_duration": 0.15,
}

# --- Q ---------------------------------------------------------------------------------
# Warm and ordinary: a ruddy tan with flushed cheeks and olive shadows (his portrait), the
# model's own green sweater pushed to a moss green that does not sit in the classroom's
# teal, navy trousers, dull matte eyes and lips (the GLB's 0.35 roughness shone).
Q_SKIN = {
    "albedo": "#CE9A70",
    "pigment_a": "#D68A6A",
    "pigment_b": "#B59968",
    "pigment_mix": 0.36,
    "pigment_value": 0.1,
    "pigment_scale": 20.0,
    "pigment_stretch": (1.0, 1.4, 1.0),
    "shade_tint": "#B5B88E",
    "light_tint": "#FFEFD8",
    "shadow_fill": 0.36,
    "light_strength": 0.72,
}
Q = {
    "label": "Q: painted (option C)",
    "outline_width": 0.009,
    "parts": {
        "q_mat_skin": dict(
            Q_SKIN,
            # Flushed cheeks.
            patch_center=(0.044, 1.488, 0.112),
            patch_radius=(0.032, 0.026, 0.045),
            patch_color="#C9634C",
            patch_strength=0.45,
            # His face is centred 1.2 cm to -X of the model's origin (eyes -0.061..0.041,
            # lips -0.055..0.027), so the cheeks mirror across that, not x = 0.
            mirror_center_x=-0.012,
            outline=True,
        ),
        "q_mat_hair": {
            "albedo": "#18151B",
            "pigment_a": "#272335",
            "pigment_b": "#2C241F",
            "pigment_mix": 0.5,
            "pigment_value": 0.25,
            "pigment_scale": 14.0,
            "shade_tint": "#7C7C9C",
            "shadow_fill": 0.4,
            "outline": True,
        },
        "q_mat_brow": {"albedo": "#1F1A1C", "pigment_mix": 0.0, "pigment_value": 0.0, "outline": False},
        "q_mat_eye": {
            "albedo": "#DCD2BA",
            "pigment_mix": 0.0,
            "pigment_value": 0.0,
            "shadow_fill": 0.6,
            "half_tone": 0.8,
            "outline": False,
        },
        "q_mat_iris": {"albedo": "#2B1D15", "pigment_mix": 0.0, "pigment_value": 0.0, "shadow_fill": 0.6, "outline": False},
        "q_mat_pupil": {"albedo": "#0C0A09", "pigment_mix": 0.0, "pigment_value": 0.0, "outline": False},
        "q_mat_lip": {"albedo": "#A4493C", "pigment_mix": 0.0, "pigment_value": 0.05, "outline": False},
        "q_mat_mouthdark": {"albedo": "#3B1713", "pigment_mix": 0.0, "pigment_value": 0.0, "outline": False},
        "q_mat_teeth": {"albedo": "#D8CBAE", "pigment_mix": 0.0, "pigment_value": 0.0, "shadow_fill": 0.55, "outline": False},
        "q_mat_cloth": {
            "albedo": "#516F4C",
            "pigment_a": "#5F7C43",
            "pigment_b": "#3F5F5A",
            "pigment_mix": 0.4,
            "pigment_value": 0.16,
            "pigment_scale": 11.0,
            "pigment_stretch": (1.0, 1.6, 1.0),
            "shade_tint": "#8F88A8",
            "light_tint": "#FFF0D6",
            "shadow_fill": 0.32,
            "outline": True,
        },
        "q_mat_collar": {"albedo": "#B39A5F", "pigment_mix": 0.0, "pigment_value": 0.08, "outline": False},
        "q_mat_pants": {
            "albedo": "#313D52",
            "pigment_a": "#2C3458",
            "pigment_b": "#3C4450",
            "pigment_mix": 0.4,
            "pigment_value": 0.16,
            "pigment_scale": 6.5,
            "pigment_stretch": (1.0, 3.2, 1.0),
            "shade_tint": "#8D86A6",
            "outline": True,
        },
        "q_mat_shoes": {
            "albedo": "#2F2521",
            "pigment_a": "#30292E",
            "pigment_b": "#3C2D24",
            "pigment_mix": 0.4,
            "pigment_value": 0.15,
            "outline": True,
        },
        "q_mat_sole": {"albedo": "#B4A585", "pigment_mix": 0.0, "pigment_value": 0.06, "outline": False},
    },
    "expression": {},
    "blink_shapes": [],
    "blink_interval": (2.5, 5.0),
    "blink_duration": 0.16,
}

TARGETS = {
    "assets/characters/protagonist/protagonist_look.tres": PROTAGONIST,
    "assets/characters/q/q_look.tres": Q,
}


def colour(hex_value: str) -> str:
    value = hex_value.lstrip("#")
    r, g, b = (int(value[i : i + 2], 16) / 255.0 for i in (0, 2, 4))
    return f"Color({r:.4f}, {g:.4f}, {b:.4f}, 1)"


def vector(values: tuple[float, float, float]) -> str:
    return "Vector3({:g}, {:g}, {:g})".format(*values)


def parameter(value: object) -> str:
    if isinstance(value, str) and value.startswith("#"):
        return colour(value)
    if isinstance(value, tuple):
        return vector(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return f"{value:g}"
    return str(value)


def sub_id(name: str) -> str:
    return "m_" + name.replace("/", "__")


def render(look: dict) -> str:
    parts: dict = look["parts"]
    lines: list[str] = []
    load_steps = 3 + 1 + len(parts) + 1
    lines.append(
        f'[gd_resource type="Resource" script_class="CharacterLook" load_steps={load_steps} format=3]'
    )
    lines.append("")
    lines.append(f'[ext_resource type="Script" path="{SCRIPT}" id="1_look"]')
    lines.append(f'[ext_resource type="Shader" path="{PAINT_SHADER}" id="2_paint"]')
    lines.append(f'[ext_resource type="Shader" path="{OUTLINE_SHADER}" id="3_outline"]')
    lines.append("")
    lines.append('[sub_resource type="ShaderMaterial" id="outline"]')
    lines.append('resource_name = "character_ink_outline"')
    lines.append('shader = ExtResource("3_outline")')
    lines.append(f"shader_parameter/ink = {colour(INK)}")
    lines.append(f"shader_parameter/width = {look['outline_width']:g}")
    lines.append("")
    for name, part in parts.items():
        settings = dict(PART_DEFAULTS)
        settings.update(part)
        outline = bool(settings.pop("outline"))
        lines.append(f'[sub_resource type="ShaderMaterial" id="{sub_id(name)}"]')
        lines.append(f'resource_name = "{name} (painted)"')
        if outline:
            lines.append('next_pass = SubResource("outline")')
        lines.append('shader = ExtResource("2_paint")')
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
        print("out of date (run art/characters/build_character_looks.py): " + ", ".join(stale))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
