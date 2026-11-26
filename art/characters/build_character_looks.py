#!/usr/bin/env python3
"""Writes the protagonist's, Q's, N's and the classroom student's look resources.

    python3 art/characters/build_character_looks.py          # write both
    python3 art/characters/build_character_looks.py --check  # fail if they are out of date

Output (committed, read by the game):
    assets/characters/protagonist/protagonist_look.tres
    assets/characters/q/q_look.tres
    assets/characters/teacher_n/teacher_n_look.tres
    assets/characters/classroom_student/student_look.tres
and the character integration's unshipped experiments under scenes/dev/character_lab/looks/.

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
import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import look_experiments  # noqa: E402  (the experiments' palettes, next to this file)

ROOT = Path(__file__).resolve().parents[2]
# The hull's first two parameters keep the order the looks were first written in, so a
# look that sets nothing new is the same file as before.
OUTLINE_ORDER = ["ink", "width"]
PAINT_SHADER = "res://assets/shaders/characters/character_paint.gdshader"
OUTLINE_SHADER = "res://assets/shaders/characters/character_outline.gdshader"
# For a part marked `two_sided`: one whose GLB material is double-sided and whose triangles
# face inward (N's eyeballs). The ext_resource is only written when a look uses it.
TWO_SIDED_SHADER = "res://assets/shaders/characters/character_paint_two_sided.gdshader"
SCRIPT = "res://scripts/actors/character_look.gd"

# The biology-classroom experiment's ink (0.16, 0.14, 0.2), since the prologue art
# migration: the characters' contour is drawn with the same pen as the room's.
INK = "#292433"

# Shared defaults for character_paint.gdshader; a part overrides what it needs.
PART_DEFAULTS = {
    "shade_tint": "#A3A6C8",
    "light_tint": "#FFF3E2",
    "shadow_fill": 0.30,
    "half_tone": 0.62,
    "light_strength": 0.76,
    "shadow_edge": -0.05,
    "light_edge": 0.42,
    # The room's two-step terminator is hard (room_tone: ±0.03); the characters follow it.
    "edge_softness": 0.03,
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
    "outline_width": 0.01,
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
            # The iris paints its limbal ring from the model's own vertex colour
            # (issue #383): the ring lives in COLOR_0, so this material reads it.
            "use_vertex_paint": True,
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
    # The head's local UV textures (issue #383): the skin material samples them
    # through CharacterDetailMaps instead of the dropped vertex paint. Issue #386
    # adds the hair's own pair under the hair material's name: the maps ride the
    # same UV gate as the skin maps -- the hair mesh now carries the atlas
    # (`head_v2.hair_uv`), while the eyebrows, which share the material on the
    # head mesh without UVs, keep drawing exactly as before. Emitted into the
    # .tres by render() below -- the generator owns every byte of it.
    "detail_maps": {
        "ext": [
            ("4_albedo", "Texture2D",
             "res://assets/characters/protagonist/textures/head_albedo.png"),
            ("5_normal", "Texture2D",
             "res://assets/characters/protagonist/textures/head_normal.png"),
            ("6_maps", "Script", "res://scripts/actors/character_detail_maps.gd"),
            ("7_hair_albedo", "Texture2D",
             "res://assets/characters/protagonist/textures/hair_albedo.png"),
            ("8_hair_normal", "Texture2D",
             "res://assets/characters/protagonist/textures/hair_normal.png"),
        ],
        "maps": {
            "protagonist_mat_skin": {
                "id": "maps_skin",
                "script": "6_maps",
                "albedo": "4_albedo",
                "albedo_mix": 1.0,
                "normal": "5_normal",
                "normal_strength": 1.0,
            },
            "protagonist_mat_hair": {
                "id": "maps_hair",
                "script": "6_maps",
                "albedo": "7_hair_albedo",
                "albedo_mix": 0.75,
                "normal": "8_hair_normal",
                "normal_strength": 1.0,
            },
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
    # Directed face states (#387): absolute weights for the shapes each state names;
    # everything else stays at the resting expression above. Kept deliberately small and
    # below the model's own Face_Test extremes - a close-up should read as listening or
    # an easy reply, not as a performance. Q's tables must not name `Smile` or
    # `Mouth_Open`: the textbook pose owns those two while a book is up.
    "face_states": {
        "listening": {"BrowRaise": 0.16, "BrowCompress": 0.34, "JawOpen": 0.03},
        "attention": {"BrowRaise": 0.24, "BrowCompress": 0.30, "Frown": 0.10},
        "friendly": {"BrowCompress": 0.26, "Frown": 0.05, "LipTension": 0.20, "JawOpen": 0.04},
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
    "outline_width": 0.01,
    "parts": {
        "q_mat_skin": dict(
            Q_SKIN,
            # Flushed cheeks.
            patch_center=(0.044, 1.628, 0.105),
            patch_radius=(0.032, 0.026, 0.045),
            patch_color="#C9634C",
            patch_strength=0.45,
            # new-Q is centred on x = 0; only Q's mapping/coordinates change.
            mirror_center_x=0.0,
            outline=True,
        ),
        "q_mat_skinbody": dict(Q_SKIN, outline=True),
        # A 9 mm hull on these 2 cm-wide fingers fills the gaps between them.
        # Keep the source geometry; use the same paint without a hand hull.
        "q_hands/q_mat_skinbody": dict(Q_SKIN, outline=False),
        "q_head/q_mat_hair": {"albedo": "#1F1A1C", "pigment_mix": 0.0, "pigment_value": 0.0, "outline": False},
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
        "q_mat_sclera": {
            "albedo": "#DCD2BA",
            "pigment_mix": 0.0,
            "pigment_value": 0.0,
            "shadow_fill": 0.6,
            "half_tone": 0.8,
            "outline": False,
        },
        "q_mat_iris": {"albedo": "#2B1D15", "pigment_mix": 0.0, "pigment_value": 0.0, "shadow_fill": 0.6, "outline": False},
        "q_mat_pupil": {"albedo": "#0C0A09", "pigment_mix": 0.0, "pigment_value": 0.0, "outline": False},
        "q_mat_mouthinner": {"albedo": "#3B1713", "pigment_mix": 0.0, "pigment_value": 0.0, "outline": False},
        "q_mat_hoodie": {
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
        "q_mat_hoodierib": {"albedo": "#B39A5F", "pigment_mix": 0.0, "pigment_value": 0.08, "outline": False},
        "q_mat_trousers": {
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
    # Q's directed face states (#387), absolute weights on the shapes they name. `Smile`
    # and `Mouth_Open` are deliberately absent: `q_textbook_pose` writes those two while
    # a book is up, and two writers on one shape is the bug this channel exists to avoid.
    # `Smirk` stays out too - Q is a chatty classmate, not a smirk.
    "face_states": {
        "listening": {"Brow_Raise": 0.14, "Mouth_Close": 0.08},
        "attention": {"Brow_Raise": 0.22, "Brow_Compress": 0.05},
        "friendly": {"Brow_Raise": 0.08, "Jaw_Open": 0.05, "Mouth_Close": 0.03},
    },
    "blink_shapes": ["Eye_Blink_L", "Eye_Blink_R"],
    "blink_interval": (2.5, 5.0),
    "blink_duration": 0.16,
}

# --- the classroom student ---------------------------------------------------------------
# The first protagonist model (`protagonist.glb`), seated at desk A1 since the protagonist was
# replaced. Until now it was the one person in the room still in its GLB's smooth PBR
# colours, which read as a toy beside the painted protagonist, Q and N. It gets the same
# painted surface and ink hull as they do, in the protagonist's charcoal manner (wobbling
# contour, pale erased strokes along the cardigan's turning edges), and a palette of its
# own so it is nobody's double: a plum-grey cardigan that takes the room's violet shadows
# (not the protagonist's slate, Q's moss or N's sage, and off the classroom's teal trim), a
# cream shirt, navy-charcoal trousers, a warm ordinary skin with lilac shade.
#
# Its source was 78 rigid pieces; geometry revision 1 integrates the hands and face.
# The remaining small parts (locks, panels, creases) still need selective outlines, so
# the ink line goes only on the closed outer forms: cardigan body and sleeves, trousers,
# shoes, the hair cap and back, and the head, ears and neck (named per mesh; the skin
# material is also every finger, and a hull per finger would weld them into a mitten). The
# lapels, pockets, collars, creases and the face's small planes carry none. Every GLB
# material is listed, so no surface is left in its PBR colour.
STUDENT_SKIN = {
    "albedo": "#C9A084",
    "pigment_a": "#C48E74",
    "pigment_b": "#AFA07E",
    "pigment_mix": 0.4,
    "pigment_value": 0.12,
    "pigment_scale": 18.0,
    "pigment_stretch": (1.0, 1.4, 1.0),
    "shade_tint": "#A7A3C6",
    "light_tint": "#FFEBD4",
    "shadow_fill": 0.34,
    "half_tone": 0.55,
    "edge_break": 0.22,
    "light_edge": 0.5,
    "light_strength": 0.72,
}
STUDENT_ERASED = {
    "strength": 0.45,
    "color": "#A99E8E",
    "scale": 70.0,
    "across": (1.0, 0.15, 0.3),
    "width": 0.22,
    "length": 9.0,
    "coverage": 0.04,
    "contour": 0.9,
    "contour_power": 2.5,
    "jitter": 0.6,
}
STUDENT_HAIR = {
    "albedo": "#221D22",
    "pigment_a": "#332F45",
    "pigment_b": "#3E3029",
    "pigment_mix": 0.5,
    "pigment_value": 0.28,
    "pigment_scale": 12.0,
    "shade_tint": "#7C7C9C",
    "shadow_fill": 0.45,
    "light_strength": 0.85,
}
STUDENT_FLAT = {"pigment_mix": 0.0, "pigment_value": 0.0, "outline": False}
STUDENT = {
    "label": "classroom student: charcoal (integrated)",
    "outline_width": 0.01,
    "outline": {"wobble": 0.55, "wobble_scale": 11.0},
    "parts": {
        "wis_protagonist_skin": dict(STUDENT_SKIN, outline=False),
        "head_main_mesh/wis_protagonist_skin": dict(STUDENT_SKIN, outline=True),
        "neck/wis_protagonist_skin": dict(STUDENT_SKIN, outline=True),
        "ear_l/wis_protagonist_skin": dict(STUDENT_SKIN, outline=True),
        "ear_r/wis_protagonist_skin": dict(STUDENT_SKIN, outline=True),
        "wis_protagonist_skin_light": dict(STUDENT_SKIN, albedo="#D8AE90", pigment_mix=0.2, outline=False),
        "wis_protagonist_skin_shadow": dict(STUDENT_FLAT, albedo="#8E6658", shadow_fill=0.45),
        # The tired under-eyes the first protagonist was modelled with, kept but quieter.
        "wis_protagonist_undereye": dict(STUDENT_FLAT, albedo="#A27E74", shadow_fill=0.45),
        "wis_protagonist_eye_offwhite": dict(STUDENT_FLAT, albedo="#DCD3BE", shadow_fill=0.6, half_tone=0.8),
        "wis_protagonist_iris": dict(STUDENT_FLAT, albedo="#3A2A22", shadow_fill=0.6),
        "wis_protagonist_pupil": dict(STUDENT_FLAT, albedo="#100C0B"),
        "wis_protagonist_eye_glint": dict(STUDENT_FLAT, albedo="#F2EAD8", shadow_fill=0.85, half_tone=0.9),
        "wis_protagonist_hair": look_experiments.with_marks(
            dict(STUDENT_HAIR, outline=True),
            strength=0.4,
            color="#4C4656",
            scale=110.0,
            across=(1.0, 0.0, 0.6),
            width=0.25,
            length=12.0,
            coverage=0.12,
            contour=0.12,
            jitter=0.4,
        ),
        "wis_protagonist_hair_warm": dict(STUDENT_HAIR, albedo="#2E2420", outline=False),
        "wis_protagonist_cardigan": look_experiments.with_marks(
            {
                "albedo": "#5A4A5E",
                "pigment_a": "#4A4060",
                "pigment_b": "#64544E",
                "pigment_mix": 0.45,
                "pigment_value": 0.22,
                "pigment_scale": 6.0,
                "pigment_stretch": (1.0, 3.0, 1.0),
                "shade_tint": "#8C86B8",
                "light_tint": "#FFE6C4",
                "shadow_fill": 0.4,
                "light_strength": 0.9,
                "light_edge": 0.25,
                "outline": True,
            },
            **STUDENT_ERASED,
        ),
        "wis_protagonist_cardigan_light": {
            "albedo": "#6E5D6C",
            "pigment_a": "#5E5470",
            "pigment_b": "#7A6A60",
            "pigment_mix": 0.35,
            "shade_tint": "#8C86B8",
            "shadow_fill": 0.4,
            "outline": False,
        },
        "wis_protagonist_cardigan_shadow": dict(STUDENT_FLAT, albedo="#3C3242", shade_tint="#8C86B8"),
        "wis_protagonist_button": dict(STUDENT_FLAT, albedo="#8A6E46", shadow_fill=0.45),
        "wis_protagonist_stitch": dict(STUDENT_FLAT, albedo="#8E7F6A"),
        # The model's own dab of paint on the shoulder: an art-club student, kept rust.
        "wis_protagonist_brush_rust": dict(STUDENT_FLAT, albedo="#8A4A36"),
        "wis_protagonist_shirt": {
            "albedo": "#D8CFB8",
            "pigment_a": "#C9CCB8",
            "pigment_b": "#DDCBA8",
            "pigment_mix": 0.35,
            "shade_tint": "#9894B8",
            "shadow_fill": 0.36,
            "outline": False,
        },
        "wis_protagonist_shirt_shadow": dict(STUDENT_FLAT, albedo="#B2A890", shade_tint="#9894B8", shadow_fill=0.36),
        "wis_protagonist_trousers": look_experiments.with_marks(
            {
                "albedo": "#2F3340",
                "pigment_a": "#2A2E48",
                "pigment_b": "#3E3C3A",
                "pigment_mix": 0.4,
                "pigment_value": 0.18,
                "pigment_scale": 6.0,
                "pigment_stretch": (1.0, 3.4, 1.0),
                "shade_tint": "#8D86A6",
                "shadow_fill": 0.38,
                "outline": True,
            },
            **dict(STUDENT_ERASED, strength=0.35),
        ),
        "wis_protagonist_trousers_light": dict(STUDENT_FLAT, albedo="#474B5A", shade_tint="#8D86A6"),
        "wis_protagonist_shoes": {
            "albedo": "#2B2321",
            "pigment_a": "#2E2830",
            "pigment_b": "#3A2C24",
            "pigment_mix": 0.4,
            "pigment_value": 0.15,
            "outline": True,
        },
        "wis_protagonist_sole": dict(STUDENT_FLAT, albedo="#3E3632"),
    },
    # The first protagonist has no blend shapes: no expression and no blink.
    "expression": {},
    "blink_shapes": [],
    "blink_interval": (2.5, 5.0),
    "blink_duration": 0.16,
}

# PROTAGONIST and Q above are option C, the painted looks the game shipped before the
# character integration (docs/CHARACTER_INTEGRATION.md). The looks the wrappers carry now
# are built on them by look_experiments.py: the protagonist's charcoal, Q's oil and N's
# chalk. A frozen copy of each option C file is in scenes/dev/character_lab/looks/before/.
# --- the room key ------------------------------------------------------------------------
# Everyone the game ships stands in the same painted room, so their shadows and lights are
# keyed to it (item 2 of the prologue art review: the characters' style has to match the
# environment). The room's shadows are a violet ink (the experiment's shadow marks are
# (0.12, 0.10, 0.22)) and its light is the warm apricot of the windows and fittings
# (art/classroom/README.md: APRICOT_PALE). Each part keeps its own direction - Q's moss
# shadow, the protagonist's slate - and moves part of the way towards the room's, so the
# figures stop reading as lit by a different lamp from the walls behind them. The unshipped
# experiments keep their tints, for the comparison.
ROOM_SHADE = "#7E74B0"
ROOM_LIGHT = "#FFE0B4"
ROOM_KEY = 0.3


def _mix_hex(a: str, b: str, t: float) -> str:
    ca = [int(a[i : i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i : i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02X}" for x, y in zip(ca, cb))


def room_keyed(look: dict) -> dict:
    """`look` with every part's shade and light tint moved towards the room's."""
    result = dict(look)
    parts = {}
    for name, part in look["parts"].items():
        keyed = dict(part)
        keyed["shade_tint"] = _mix_hex(part.get("shade_tint", PART_DEFAULTS["shade_tint"]), ROOM_SHADE, ROOM_KEY)
        keyed["light_tint"] = _mix_hex(part.get("light_tint", PART_DEFAULTS["light_tint"]), ROOM_LIGHT, ROOM_KEY)
        parts[name] = keyed
    result["parts"] = parts
    return result


def surface_work(part: dict, kind: int, scale: float, tint: str, strength: float) -> None:
    """Fine diffuse-only work on an existing part, not a new material/mesh pipeline."""
    part.update(detail_kind=kind, detail_scale=scale, detail_tint=tint, detail_strength=strength)


def refined_teacher(look: dict) -> dict:
    """Retain N's chalk/sage identity, with fine cloth and a quieter face/contour.

    These are only the shipped look's overrides. The retired woodcut experiment and
    the protagonist/Q are deliberately not restyled. Coordinates are measured on N's
    -Z-facing source, in the same bind space as the refined model's painted patches.
    """
    result = copy.deepcopy(look)
    result["outline_width"] = 0.0055
    result["outline"].update(wobble=0.18)
    parts = result["parts"]
    # Geometry revision 1 repairs the eyes' winding/normals in prepare_teacher_n.py.
    # Keep the historical experiment unchanged; the production look is one-sided.
    for name in ("m_st_sclera", "m_st_iris", "m_st_pupil"):
        parts[name].pop("two_sided", None)
    parts["m_st_skin"].update(
        pigment_blend=0.82, pigment_scale=23.0, pigment_mix=0.29, pigment_value=0.061,
        edge_break=0.095, edge_softness=0.15, patch_feather=0.92,
        patch_strength=0.24, patch2_strength=0.23,
    )
    # Value steps on the compressed eyelid and lip are deliberately closer to skin.
    parts["m_st_sclera"].update(albedo="#C7B9A8", shadow_fill=0.56)
    parts["m_st_iris"].update(albedo="#543F31")
    parts["m_st_brow"].update(albedo="#4A3A37")
    parts["m_st_lash"].update(albedo="#3E3032")
    parts["m_st_lip"].update(albedo="#AB7F75", shadow_fill=0.54)
    for name in ("m_st_hair", "m_st_hairlight"):
        part = parts[name]
        part.update(
            pigment_blend=0.69, pigment_value=0.15, pigment_scale=14.0,
            mark_strength=0.16, mark_coverage=0.08, mark_contour=0.085,
            detail_origin=(-0.019, 1.61, 0.008),
        )
        surface_work(part, 3, 128.0, "#685449", 0.31)
    parts["m_st_hairlight"].update(albedo="#322720", outline=False)
    cardigan = parts["m_st_cardigan"]
    cardigan.update(
        albedo="#838E78", pigment_a="#819276", pigment_b="#777B78", shadow_fill=0.44,
        pigment_blend=0.64, pigment_value=0.11, pigment_mix=0.39, pigment_scale=8.0,
        mark_strength=0.17, mark_coverage=0.12, mark_contour=0.12,
    )
    surface_work(cardigan, 1, 151.0, "#A8AC8F", 0.24)
    parts["m_st_blouse"].update(albedo="#DAD0B7", pigment_blend=0.7, pigment_value=0.04, outline=False)
    surface_work(parts["m_st_blouse"], 2, 180.0, "#F4E7D1", 0.16)
    trousers = parts["m_st_trousers"]
    trousers.update(pigment_blend=0.5, pigment_value=0.10, mark_strength=0.10)
    surface_work(trousers, 2, 160.0, "#6C6C7C", 0.22)
    return result


def refined_student(look: dict) -> dict:
    """Keep the seated student's plum cardigan and rigid-piece model, not a player clone."""
    result = copy.deepcopy(look)
    result["outline_width"] = 0.0055
    result["outline"].update(wobble=0.20)
    parts = result["parts"]
    for name, part in parts.items():
        if name.endswith("/wis_protagonist_skin") or name in (
            "wis_protagonist_skin", "wis_protagonist_skin_light"
        ):
            part.update(
                pigment_blend=0.8, pigment_value=0.06, pigment_scale=24.0,
                edge_break=0.10, edge_softness=0.08, half_tone=0.6,
            )
    parts["wis_protagonist_skin_light"]["albedo"] = "#C69C83"
    parts["wis_protagonist_skin_shadow"]["albedo"] = "#987367"
    parts["wis_protagonist_undereye"]["albedo"] = "#AB8E82"
    parts["wis_protagonist_eye_offwhite"].update(albedo="#BFB29D", shadow_fill=0.52, half_tone=0.62)
    parts["wis_protagonist_iris"].update(albedo="#574233", shadow_fill=0.51)
    parts["wis_protagonist_pupil"].update(albedo="#1D171B")
    parts["wis_protagonist_eye_glint"].update(albedo="#D7C9AF", shadow_fill=0.66)
    parts["head_main_mesh/wis_protagonist_skin"].update(
        patch_center=(0.043, 1.564, 0.109), patch_radius=(0.027, 0.008, 0.023),
        patch_color="#8F7984", patch_strength=0.16,
        patch2_center=(0.058, 1.521, 0.105), patch2_radius=(0.033, 0.025, 0.045),
        patch2_color="#C68C78", patch2_strength=0.15, patch_feather=0.85,
    )
    for name in ("wis_protagonist_hair", "wis_protagonist_hair_warm"):
        part = parts[name]
        part.update(
            pigment_blend=0.66, pigment_value=0.14, mark_strength=0.14,
            detail_origin=(-0.012, 1.646, 0.044),
        )
        surface_work(part, 3, 120.0, "#554854", 0.29)
    parts["wis_protagonist_hair_warm"]["albedo"] = "#392A2D"
    for name in ("wis_protagonist_cardigan", "wis_protagonist_cardigan_light", "wis_protagonist_cardigan_shadow"):
        part = parts[name]
        part.update(pigment_blend=0.6, pigment_value=0.11, pigment_scale=10.0)
        surface_work(part, 1, 150.0, "#A79A98", 0.22)
    parts["wis_protagonist_cardigan"].update(
        albedo="#705565", pigment_a="#60506A", pigment_b="#7B5A58", shadow_fill=0.49,
        pigment_mix=0.38, mark_strength=0.18, mark_contour=0.41, mark_coverage=0.033,
    )
    parts["wis_protagonist_cardigan_light"].update(albedo="#806775", shadow_fill=0.47)
    parts["wis_protagonist_cardigan_shadow"]["albedo"] = "#584251"
    for name in ("wis_protagonist_shirt", "wis_protagonist_shirt_shadow"):
        parts[name].update(pigment_blend=0.7, pigment_value=0.04)
        surface_work(parts[name], 2, 190.0, "#ECE0CC", 0.18)
    for name in ("wis_protagonist_trousers", "wis_protagonist_trousers_light"):
        parts[name].update(pigment_blend=0.55, pigment_value=0.10, mark_strength=0.10)
        surface_work(parts[name], 2, 160.0, "#676C7C", 0.28)
    return result


TARGETS = look_experiments.shipped(PROTAGONIST, Q)
TARGETS["assets/characters/teacher_n/teacher_n_look.tres"] = refined_teacher(
    TARGETS["assets/characters/teacher_n/teacher_n_look.tres"]
)
TARGETS["assets/characters/classroom_student/student_look.tres"] = refined_student(STUDENT)
TARGETS = {relative: room_keyed(look) for relative, look in TARGETS.items()}

# The schemes that were tried and not shipped, written under scenes/dev/ (which no export
# carries) for the in-game comparison.
EXPERIMENTS = look_experiments.experiments(PROTAGONIST, Q)


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


def shape_keys(part: dict) -> dict:
    """A part's silhouette shaping, which its ink hull has to follow."""
    return {key: value for key, value in part.items() if key.startswith("shape")}


def sub_id(name: str) -> str:
    return "m_" + name.replace("/", "__")


def outline_block(sub: str, look: dict, extra: dict) -> list[str]:
    """One ink hull material: the look's shared settings plus a part's own (its shape)."""
    settings = {"ink": INK, "width": look["outline_width"]}
    settings.update(look.get("outline", {}))
    settings.update(extra)
    lines = [f'[sub_resource type="ShaderMaterial" id="{sub}"]']
    lines.append('resource_name = "character_ink_outline"')
    lines.append('shader = ExtResource("3_outline")')
    for key in OUTLINE_ORDER + sorted(k for k in settings if k not in OUTLINE_ORDER):
        if key in settings:
            lines.append(f"shader_parameter/{key} = {parameter(settings[key])}")
    lines.append("")
    return lines


def render(look: dict) -> str:
    parts: dict = look["parts"]
    shaped = {name for name, part in parts.items() if part.get("outline") and shape_keys(part)}
    lines: list[str] = []
    two_sided = any(part.get("two_sided") for part in parts.values())
    detail = look.get("detail_maps") or {}
    exts = detail.get("ext", ())
    maps = detail.get("maps", {})
    ext_ids = {ext_id for ext_id, _type, _path in exts}
    load_steps = 3 + int(two_sided) + 1 + len(parts) + len(shaped) + 1 + len(exts) + len(maps)
    lines.append(
        f'[gd_resource type="Resource" script_class="CharacterLook" load_steps={load_steps} format=3]'
    )
    lines.append("")
    lines.append(f'[ext_resource type="Script" path="{SCRIPT}" id="1_look"]')
    lines.append(f'[ext_resource type="Shader" path="{PAINT_SHADER}" id="2_paint"]')
    lines.append(f'[ext_resource type="Shader" path="{OUTLINE_SHADER}" id="3_outline"]')
    if two_sided:
        lines.append(f'[ext_resource type="Shader" path="{TWO_SIDED_SHADER}" id="4_paint_two_sided"]')
    for ext_id, ext_type, ext_path in exts:
        lines.append(f'[ext_resource type="{ext_type}" path="{ext_path}" id="{ext_id}"]')
    lines.append("")
    lines.extend(outline_block("outline", look, {}))
    for name in parts:
        if name in shaped:
            lines.extend(outline_block("outline_" + sub_id(name), look, shape_keys(parts[name])))
    for name, part in parts.items():
        settings = dict(PART_DEFAULTS)
        settings.update(part)
        outline = bool(settings.pop("outline"))
        shader = "4_paint_two_sided" if settings.pop("two_sided", False) else "2_paint"
        lines.append(f'[sub_resource type="ShaderMaterial" id="{sub_id(name)}"]')
        lines.append(f'resource_name = "{name} (painted)"')
        if outline:
            hull = "outline_" + sub_id(name) if name in shaped else "outline"
            lines.append(f'next_pass = SubResource("{hull}")')
        lines.append(f'shader = ExtResource("{shader}")')
        for key in sorted(settings):
            lines.append(f"shader_parameter/{key} = {parameter(settings[key])}")
        lines.append("")
    for spec in maps.values():
        lines.append(f'[sub_resource type="Resource" id="{spec["id"]}"]')
        for key, value in spec.items():
            if key == "id":
                continue
            if isinstance(value, str) and value in ext_ids:
                lines.append(f'{key} = ExtResource("{value}")')
            else:
                lines.append(f"{key} = {parameter(value)}")
        lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_look")')
    entries = ",\n".join(f'"{name}": SubResource("{sub_id(name)}")' for name in parts)
    lines.append("materials = {\n" + entries + "\n}")
    if maps:
        map_entries = ",\n".join(
            f'"{name}": SubResource("{spec["id"]}")' for name, spec in maps.items()
        )
        lines.append("detail_maps = {\n" + map_entries + "\n}")
    expression = ",\n".join(f'"{shape}": {weight:g}' for shape, weight in look["expression"].items())
    lines.append("expression = {\n" + expression + "\n}" if expression else "expression = {}")
    states = look.get("face_states", {})
    if states:
        state_lines = []
        for state, shapes in states.items():
            shapes_text = ", ".join(f'"{shape}": {weight:g}' for shape, weight in shapes.items())
            state_lines.append(f'"{state}": {{{shapes_text}}}')
        lines.append("face_states = {\n" + ",\n".join(state_lines) + "\n}")
    else:
        lines.append("face_states = {}")
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
    for relative, look in {**TARGETS, **EXPERIMENTS}.items():
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
