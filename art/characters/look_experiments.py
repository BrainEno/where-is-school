"""The visual experiments of the character integration (docs/CHARACTER_INTEGRATION.md).

Read by build_character_looks.py, which writes each one to scenes/dev/character_lab/looks/
(export-excluded: an experiment is photographed in the game, never shipped). The scheme a
character finally ships is written by the builder's TARGETS; it may reuse one of these.

Same conventions as the builder: sRGB hex, rest-space metres, +Y up. The protagonist and Q
face +Z; N faces -Z (her eyes are at z = -0.09), so her face patches have negative z.

Each scheme is a *different idea*, not a different strength of the same one:

  protagonist_charcoal  charcoal on toned paper: the black gakuran lifted to a slate that
                        takes the sun, pale erased strokes along every turning edge so the
                        figure separates from the floor's violet shadows, strand marks that
                        draw the spiky hair from the gameplay camera above.
  q_oil                 thick oil: big stretched colour blocks, olive half-tones carrying the
                        broad face's planes, a dark eye socket for his heavy lids, impasto
                        fold strokes on a hoodie moved off the curtain's blue and the board's
                        green towards ochre-olive.
  q_paper               etched print: two hard bands, almost no colour drift, long diagonal
                        hatching in a darker tone of each part, flat black hair lit by pale
                        strands. Line and value instead of paint.
  n_chalk               pastel on grey paper: soft, smudged terminator, a lilac shade taken
                        from the room's ambient, pale chalk strokes over a lifted sage
                        cardigan, the portrait's pale face and dark bob; the cardigan's
                        flared hem taken in so she is no longer pear-shaped.
  n_woodcut             white-line woodcut: hard bands, deep violet shadow, pale gouges cut
                        along the form edges of a dark slate cardigan over the pale blouse, a
                        hand-cut wobbling contour, the hem taken in further and the crown of
                        the bob let out.
"""

from __future__ import annotations

import copy

LAB = "scenes/dev/character_lab/looks/"

# --- shared part templates -------------------------------------------------------------

FLAT = {"pigment_mix": 0.0, "pigment_value": 0.0}


def eye_parts(prefix: str, sclera: str, iris: str, pupil: str, inner: str) -> dict:
    return {
        f"{prefix}sclera": dict(FLAT, albedo=sclera, shadow_fill=0.6, half_tone=0.8, outline=False),
        f"{prefix}iris": dict(FLAT, albedo=iris, shadow_fill=0.6, outline=False),
        f"{prefix}pupil": dict(FLAT, albedo=pupil, outline=False),
        f"{prefix}mouthinner": dict(FLAT, albedo=inner, outline=False),
    }


def with_marks(part: dict, **marks: object) -> dict:
    result = dict(part)
    result.update({"mark_" + key: value for key, value in marks.items()})
    return result


# --- the protagonist: charcoal ------------------------------------------------------------

def protagonist_charcoal(base: dict) -> dict:
    look = copy.deepcopy(base)
    look["label"] = "protagonist: charcoal (experiment)"
    look["outline_width"] = 0.012
    look["outline"] = {"wobble": 0.55, "wobble_scale": 11.0}
    parts = look["parts"]
    erased = {
        "strength": 0.55,
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
    parts["protagonist_mat_jacket"] = with_marks(
        {
            "albedo": "#44505E",
            "pigment_a": "#34405A",
            "pigment_b": "#56604F",
            "pigment_mix": 0.45,
            "pigment_value": 0.24,
            "pigment_scale": 5.5,
            "pigment_stretch": (1.0, 3.2, 1.0),
            "shade_tint": "#8C86B8",
            "light_tint": "#FFE6C4",
            "shadow_fill": 0.4,
            "light_strength": 0.95,
            # Shoulders and back catch the sun from the gameplay camera above (v1: 0.3).
            "light_edge": 0.2,
            "outline": True,
        },
        **erased,
    )
    parts["protagonist_mat_trousers"] = with_marks(
        {
            "albedo": "#4A423C",
            "pigment_a": "#3E3848",
            "pigment_b": "#5A4C40",
            "pigment_mix": 0.42,
            "pigment_value": 0.2,
            "pigment_scale": 5.5,
            "pigment_stretch": (1.0, 3.6, 1.0),
            "shade_tint": "#8D86A6",
            "shadow_fill": 0.38,
            "outline": True,
        },
        **dict(erased, strength=0.4),
    )
    parts["protagonist_mat_hair"] = with_marks(
        {
            "albedo": "#2A2530",
            "pigment_a": "#3A3550",
            "pigment_b": "#4A3A30",
            "pigment_mix": 0.5,
            "pigment_value": 0.3,
            "pigment_scale": 11.0,
            "shade_tint": "#7C7C9C",
            "shadow_fill": 0.45,
            "light_strength": 0.85,
            "outline": True,
        },
        # v1 (0.6 strength, 0.25 coverage) cluttered the face in close-up. v2 (#6A6474, 0.5,
        # contour 0.35) laid a pale grey veil along every spike: strands this fine fade to
        # their average tone, and the contour weight put that tone on the edges.
        strength=0.45,
        color="#4C4656",
        scale=110.0,
        across=(1.0, 0.0, 0.6),
        width=0.25,
        length=12.0,
        coverage=0.12,
        contour=0.12,
        jitter=0.4,
    )
    parts["protagonist_mat_shirt"] = dict(parts["protagonist_mat_shirt"], albedo="#D8CFB8")
    return look


# --- Q: oil ----------------------------------------------------------------------------

# The hollow under each brow, over the upper lid (his eyes span |x| 0.014-0.046, centres
# y 1.661): it stops 1.4 cm from the middle, so the two never meet over the bridge of the
# nose (v1, centred lower and 3 cm wide, painted one smudge across it).
Q_EYE_SOCKET = {"center": (0.031, 1.676, 0.103), "radius": (0.017, 0.009, 0.02)}
# new-Q's body skin pokes through the hoodie at the shoulder seams (docs/Q_MODEL_MIGRATION.md
# §8): the vertices lie at |x| 0.2-0.3, y 1.33-1.46. Body skin is never meant to be seen
# there, so it is painted the hoodie's colour and carries no ink; the approved source
# geometry is not touched. The neck (|x| < 0.07, y > 1.425) is outside the patch.
Q_SHOULDER = {"center": (0.24, 1.38, 0.0), "radius": (0.13, 0.1, 0.14)}


def q_body_skin(skin: dict, hoodie: str) -> dict:
    return dict(
        skin,
        patch_center=Q_SHOULDER["center"],
        patch_radius=Q_SHOULDER["radius"],
        patch_color=hoodie,
        patch_strength=1.0,
        mirror_center_x=0.0,
        outline=False,
    )


def q_oil(base: dict) -> dict:
    look = copy.deepcopy(base)
    look["label"] = "Q: oil (experiment)"
    look["outline_width"] = 0.011
    look["outline"] = {"wobble": 0.35, "wobble_scale": 12.0}
    parts = look["parts"]
    # The owner's r37 note: Q's face read as uneven colour -- the oil scheme's
    # coarse value blocks and hard bands patched the cheeks. The flush and the
    # eye sockets stay (they are the character), as feathered glazes; the blocks
    # glaze together and the bands soften on N's refined recipe.
    skin = {
        "albedo": "#CC9670",
        "pigment_a": "#D88565",
        "pigment_b": "#A9935E",
        "pigment_blend": 0.8,
        "pigment_mix": 0.26,
        "pigment_value": 0.06,
        "pigment_scale": 18.0,
        "pigment_stretch": (1.0, 1.8, 0.6),
        "shade_tint": "#C0BBA0",
        "light_tint": "#FFEBD0",
        "shadow_fill": 0.52,
        "half_tone": 0.6,
        "light_edge": 0.35,
        "edge_softness": 0.15,
        "edge_break": 0.095,
        "light_strength": 0.74,
    }
    parts["q_mat_skin"] = dict(
        skin,
        patch_center=(0.044, 1.628, 0.105),
        patch_radius=(0.032, 0.026, 0.045),
        patch_color="#C25E48",
        patch_strength=0.26,
        patch_feather=0.88,
        patch2_center=Q_EYE_SOCKET["center"],
        patch2_radius=Q_EYE_SOCKET["radius"],
        patch2_color="#7E5642",
        patch2_strength=0.26,
        mirror_center_x=0.0,
        outline=True,
    )
    parts["q_mat_skinbody"] = dict(skin, outline=True)
    parts["q_body/q_mat_skinbody"] = q_body_skin(skin, "#56693F")
    parts["q_hands/q_mat_skinbody"] = dict(skin, outline=False)
    parts["q_mat_hair"] = with_marks(
        {
            "albedo": "#1C1820",
            "pigment_a": "#2E2A44",
            "pigment_b": "#3A2A20",
            "pigment_mix": 0.5,
            "pigment_value": 0.32,
            "pigment_scale": 8.0,
            "pigment_stretch": (1.0, 2.5, 1.0),
            "shade_tint": "#7C7C9C",
            "shadow_fill": 0.42,
            "outline": True,
        },
        strength=0.55,
        color="#45425E",
        scale=60.0,
        across=(1.0, 0.0, 0.5),
        width=0.35,
        length=8.0,
        coverage=0.3,
        contour=0.2,
        jitter=0.5,
    )
    parts["q_mat_hoodie"] = with_marks(
        {
            "albedo": "#56693F",
            "pigment_a": "#6B7A3A",
            "pigment_b": "#3E5A52",
            "pigment_mix": 0.5,
            "pigment_value": 0.24,
            "pigment_scale": 6.0,
            "pigment_stretch": (1.0, 2.6, 1.0),
            "shade_tint": "#8F88A8",
            "light_tint": "#FFEBC8",
            "shadow_fill": 0.34,
            "edge_break": 0.28,
            "outline": True,
        },
        strength=0.6,
        color="#2F3A2A",
        scale=40.0,
        across=(0.2, 1.0, 0.3),
        width=0.35,
        length=5.0,
        coverage=0.06,
        contour=0.55,
        jitter=0.6,
    )
    parts["q_mat_hoodierib"] = dict(FLAT, albedo="#A08850", pigment_value=0.1, outline=False)
    parts["q_mat_trousers"] = dict(parts["q_mat_trousers"], pigment_scale=5.0, pigment_value=0.22)
    return look


# --- Q: etched print -------------------------------------------------------------------

PRINT_BANDS = {
    "half_tone": 0.35,
    "shadow_edge": 0.05,
    "light_edge": 0.12,
    "edge_softness": 0.015,
    "edge_break": 0.05,
    "pigment_mix": 0.1,
    "pigment_value": 0.04,
}


def hatch(colour: str, strength: float = 0.45, coverage: float = 0.45) -> dict:
    return {
        "mark_strength": strength,
        "mark_color": colour,
        "mark_scale": 120.0,
        "mark_across": (0.7, 0.7, 0.0),
        "mark_width": 0.28,
        "mark_length": 30.0,
        "mark_coverage": coverage,
        "mark_contour": 0.4,
        "mark_contour_power": 1.5,
        "mark_jitter": 0.15,
    }


def q_paper(base: dict) -> dict:
    look = copy.deepcopy(base)
    look["label"] = "Q: etched print (experiment)"
    look["outline_width"] = 0.013
    look["outline"] = {"wobble": 0.2, "wobble_scale": 16.0}
    parts = look["parts"]
    skin = dict(
        PRINT_BANDS,
        albedo="#D9A97C",
        pigment_a="#D99A78",
        pigment_b="#C2A274",
        shade_tint="#B09A86",
        light_tint="#FFF1DC",
        shadow_fill=0.4,
        light_strength=0.78,
    )
    parts["q_mat_skin"] = dict(
        skin,
        patch_center=(0.044, 1.628, 0.105),
        patch_radius=(0.032, 0.026, 0.045),
        patch_color="#C8664E",
        patch_strength=0.35,
        patch2_center=Q_EYE_SOCKET["center"],
        patch2_radius=Q_EYE_SOCKET["radius"],
        patch2_color="#6E4A3A",
        patch2_strength=0.6,
        mirror_center_x=0.0,
        outline=True,
    )
    parts["q_mat_skinbody"] = dict(skin, outline=True)
    parts["q_body/q_mat_skinbody"] = q_body_skin(skin, "#5E7446")
    parts["q_hands/q_mat_skinbody"] = dict(skin, outline=False)
    parts["q_mat_hair"] = dict(
        PRINT_BANDS,
        albedo="#141216",
        pigment_mix=0.0,
        pigment_value=0.0,
        shade_tint="#7C7C9C",
        shadow_fill=0.4,
        outline=True,
        mark_strength=0.5,
        mark_color="#4A4658",
        mark_scale=90.0,
        mark_across=(1.0, 0.0, 0.5),
        mark_width=0.3,
        mark_length=25.0,
        mark_coverage=0.2,
        mark_contour=0.25,
        mark_jitter=0.3,
    )
    parts["q_mat_hoodie"] = dict(
        PRINT_BANDS,
        albedo="#5E7446",
        pigment_a="#64783E",
        pigment_b="#4E6650",
        shade_tint="#8F88A8",
        light_tint="#FFF0D6",
        shadow_fill=0.34,
        outline=True,
        **hatch("#2E3A26"),
    )
    parts["q_mat_hoodierib"] = dict(FLAT, albedo="#A89058", outline=False, **PRINT_BANDS)
    parts["q_mat_trousers"] = dict(
        PRINT_BANDS,
        albedo="#33405A",
        pigment_a="#2C3458",
        pigment_b="#3C4450",
        shade_tint="#8D86A6",
        outline=True,
        **hatch("#1C2234"),
    )
    parts["q_mat_shoes"] = dict(parts["q_mat_shoes"], **PRINT_BANDS)
    return look


# --- N: the parts both her schemes share -----------------------------------------------
# Her GLB's seventeen materials (tools/prepare_teacher_n.py keeps the owner's names).

# Over each upper lid (eyes at |x| 0.032, y 1.531, front at z -0.09). v1 was centred on the
# eye and 2.6 cm wide: it drew a ring round the eyeball that read as round spectacles.
N_EYE_SOCKET = {"center": (0.032, 1.543, -0.084), "radius": (0.016, 0.008, 0.02)}
N_CHEEK = {"center": (0.05, 1.49, -0.07), "radius": (0.025, 0.02, 0.04)}
# The cardigan's flared hem (y 0.82-0.93, 0.136 m deep): the torso only, not the sleeves,
# which hang at |x| > 0.25.
N_HEM = {"center": (0.0, 0.87, 0.0), "radius": (0.22, 0.13, 0.2)}
N_CROWN = {"center": (0.0, 1.64, 0.01), "radius": (0.1, 0.06, 0.12)}


def n_face_parts(lip: str, brow: str) -> dict:
    parts = eye_parts("m_st_", "#D8D0C0", "#3A2A1E", "#0E0B0A", "#3A1A18")
    # teacher-n.glb's eyeballs are wound, and their normals point, inward; the GLB material
    # is double-sided, which hid it. One-sided, the iris and pupil were culled and the
    # inside of the eyeball's back wall showed: blank, ringed eyes.
    for name in ("m_st_sclera", "m_st_iris", "m_st_pupil"):
        parts[name]["two_sided"] = True
    parts.update(
        {
            "m_st_brow": dict(FLAT, albedo=brow, shadow_fill=0.5, outline=False),
            "m_st_lash": dict(FLAT, albedo="#1A1414", outline=False),
            "m_st_lip": dict(FLAT, albedo=lip, shadow_fill=0.4, outline=False),
            "m_st_teeth": dict(FLAT, albedo="#D0C8B8", shadow_fill=0.6, outline=False),
            "m_st_button": dict(FLAT, albedo="#8A7A60", shadow_fill=0.45, outline=False),
        }
    )
    return parts


def n_look(label: str) -> dict:
    return {
        "label": label,
        "outline_width": 0.009,
        "parts": {},
        "expression": {},
        # Her GLB has no blend shapes: no blink, no expression.
        "blink_shapes": [],
        "blink_interval": (2.5, 5.0),
        "blink_duration": 0.16,
    }


# --- N: chalk ---------------------------------------------------------------------------

def n_chalk() -> dict:
    look = n_look("N: chalk (experiment)")
    look["outline"] = {"wobble": 0.45, "wobble_scale": 12.0}
    # N's GLB carries the eyelid blink and the brow/mouth expression shapes (revision 6).
    look["expression"] = {"Brow_Compress": 0.42, "Frown": 0.28, "Mouth_Close": 0.34}
    look["blink_shapes"] = ["Eye_Blink_L", "Eye_Blink_R"]
    soft = {"edge_softness": 0.1, "edge_break": 0.3}
    skin = dict(
        soft,
        albedo="#D8BFA8",
        pigment_a="#E2C4B0",
        pigment_b="#C8B8A8",
        pigment_mix=0.35,
        pigment_value=0.1,
        pigment_scale=16.0,
        pigment_stretch=(1.0, 1.5, 1.0),
        shade_tint="#A8A4C8",
        light_tint="#FFF3E6",
        shadow_fill=0.4,
        light_strength=0.74,
    )
    chalk = {
        "strength": 0.5,
        "color": "#C8C4B0",
        "scale": 55.0,
        "across": (1.0, 0.25, 0.4),
        "width": 0.3,
        "length": 7.0,
        "coverage": 0.3,
        "contour": 0.2,
        "jitter": 0.7,
    }
    hair = with_marks(
        dict(
            soft,
            albedo="#221A18",
            pigment_a="#2E2636",
            pigment_b="#3A2A22",
            pigment_mix=0.45,
            pigment_value=0.25,
            pigment_scale=12.0,
            shade_tint="#7C7C9C",
            shadow_fill=0.42,
            outline=True,
        ),
        strength=0.55,
        color="#7A6E6A",
        scale=90.0,
        across=(1.0, 0.0, 0.4),
        width=0.28,
        length=14.0,
        coverage=0.18,
        contour=0.3,
        jitter=0.4,
    )
    look["parts"] = {
        "m_st_skin": dict(
            skin,
            patch_center=N_EYE_SOCKET["center"],
            patch_radius=N_EYE_SOCKET["radius"],
            patch_color="#8E7E90",
            patch_strength=0.45,
            patch2_center=N_CHEEK["center"],
            patch2_radius=N_CHEEK["radius"],
            patch2_color="#D69A8C",
            patch2_strength=0.25,
            outline=True,
        ),
        "m_st_hair": hair,
        # The light strands were the striping on her bob; one tone, the marks do the rest.
        "m_st_hairlight": dict(hair, albedo="#2A201C"),
        "m_st_cardigan": with_marks(
            dict(
                soft,
                albedo="#6E7A6A",
                pigment_a="#7E8A70",
                pigment_b="#5E6E70",
                pigment_mix=0.45,
                pigment_value=0.2,
                pigment_scale=7.0,
                pigment_stretch=(1.0, 2.8, 1.0),
                shade_tint="#9A94B8",
                shadow_fill=0.36,
                shape_center=N_HEM["center"],
                shape_radius=N_HEM["radius"],
                shape_offset=-0.008,
                outline=True,
            ),
            **chalk,
        ),
        "m_st_blouse": dict(
            soft,
            albedo="#E2DCCB",
            pigment_a="#E6E0D0",
            pigment_b="#D8D0BE",
            pigment_mix=0.3,
            pigment_value=0.06,
            shade_tint="#A8A6C4",
            shadow_fill=0.42,
            outline=True,
        ),
        "m_st_trousers": with_marks(
            dict(
                soft,
                albedo="#3A3F4C",
                pigment_a="#363A54",
                pigment_b="#46464C",
                pigment_mix=0.4,
                pigment_value=0.16,
                pigment_scale=6.5,
                pigment_stretch=(1.0, 3.2, 1.0),
                shade_tint="#8D86A6",
                outline=True,
            ),
            **dict(chalk, color="#8A8C98", coverage=0.15, strength=0.4),
        ),
        "m_st_shoes": dict(soft, albedo="#3A2A22", pigment_mix=0.2, outline=True),
        "m_st_sole": dict(FLAT, albedo="#4A403A", outline=False),
    }
    look["parts"].update(n_face_parts(lip="#9A6A62", brow="#2A201C"))
    return look


# --- N: woodcut -------------------------------------------------------------------------

def n_woodcut() -> dict:
    look = n_look("N: woodcut (experiment)")
    look["outline_width"] = 0.014
    look["outline"] = {"wobble": 0.7, "wobble_scale": 9.0}
    cut = {
        "edge_softness": 0.012,
        "edge_break": 0.1,
        "half_tone": 0.45,
        "shadow_fill": 0.22,
        "pigment_mix": 0.15,
        "pigment_value": 0.08,
        "pigment_steps": 3.0,
    }
    gouge = {
        "strength": 0.8,
        "color": "#B8B4A0",
        "scale": 45.0,
        "across": (1.0, 0.2, 0.3),
        "width": 0.32,
        "length": 6.0,
        "coverage": 0.04,
        "contour": 0.75,
        "contour_power": 2.0,
        "jitter": 0.5,
    }
    skin = dict(
        cut,
        albedo="#E0C8B0",
        pigment_a="#E6CCB6",
        pigment_b="#D4C2AE",
        shade_tint="#7E7AA8",
        light_tint="#FFF0DC",
        light_strength=0.85,
    )
    hair = with_marks(
        dict(cut, albedo="#15100F", pigment_mix=0.0, pigment_value=0.0, shade_tint="#6E6E90", shadow_fill=0.3),
        strength=0.75,
        color="#8E8078",
        scale=70.0,
        across=(1.0, 0.0, 0.4),
        width=0.3,
        length=10.0,
        coverage=0.12,
        contour=0.55,
        jitter=0.4,
    )
    hair.update(
        shape_center=N_CROWN["center"], shape_radius=N_CROWN["radius"], shape_offset=0.01, outline=True
    )
    look["parts"] = {
        "m_st_skin": with_marks(
            dict(
                skin,
                patch_center=N_EYE_SOCKET["center"],
                patch_radius=N_EYE_SOCKET["radius"],
                patch_color="#5E4E62",
                patch_strength=0.7,
                patch2_center=N_CHEEK["center"],
                patch2_radius=N_CHEEK["radius"],
                patch2_color="#C88A80",
                patch2_strength=0.3,
                outline=True,
            ),
            strength=0.5,
            color="#6A5060",
            scale=60.0,
            across=(1.0, 0.6, 0.0),
            width=0.25,
            length=5.0,
            coverage=0.0,
            contour=0.5,
            contour_power=3.0,
            jitter=0.4,
        ),
        "m_st_hair": hair,
        "m_st_hairlight": dict(hair, albedo="#1C1513"),
        "m_st_cardigan": with_marks(
            dict(
                cut,
                albedo="#2E3B37",
                pigment_a="#2A3A40",
                pigment_b="#3A4434",
                pigment_scale=6.0,
                pigment_stretch=(1.0, 3.0, 1.0),
                shade_tint="#7A74A8",
                shape_center=N_HEM["center"],
                shape_radius=N_HEM["radius"],
                shape_offset=-0.012,
                outline=True,
            ),
            **gouge,
        ),
        "m_st_blouse": dict(cut, albedo="#E6DFCE", shade_tint="#9894B8", shadow_fill=0.36, outline=True),
        "m_st_trousers": with_marks(
            dict(cut, albedo="#252A36", shade_tint="#7A74A8", outline=True),
            **dict(gouge, color="#8C8EA0", contour=0.6, strength=0.6),
        ),
        "m_st_shoes": dict(cut, albedo="#2E221C", outline=True),
        "m_st_sole": dict(FLAT, albedo="#3E3632", outline=False),
    }
    look["parts"].update(n_face_parts(lip="#8E5A54", brow="#1C1513"))
    return look


def integrated(look: dict, label: str) -> dict:
    """An experiment promoted to what the game ships, under its own label."""
    result = copy.deepcopy(look)
    result["label"] = label
    return result


def shipped(protagonist: dict, q: dict) -> dict:
    """What the wrappers carry after the integration: the scheme that won for each."""
    return {
        "assets/characters/protagonist/protagonist_look.tres": integrated(
            protagonist_charcoal(protagonist), "protagonist: charcoal (integrated)"
        ),
        "assets/characters/q/q_look.tres": integrated(q_oil(q), "Q: oil (integrated)"),
        "assets/characters/teacher_n/teacher_n_look.tres": integrated(n_chalk(), "N: chalk (integrated)"),
    }


def experiments(protagonist: dict, q: dict) -> dict:
    """The schemes that were tried and not shipped, kept for the comparison."""
    return {
        LAB + "q_paper.tres": q_paper(q),
        LAB + "n_woodcut.tres": n_woodcut(),
    }
