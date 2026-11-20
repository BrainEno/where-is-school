"""Box people, animals and moving materials for the exam-dream dressing (2026-11-20).

Everything is built from unrotated boxes in an assembly frame, so the one
`dream_motion` shader can move an assembly as a whole: the loop offset and the
turn about a shared pivot are the same for every part. No scripts, no physics, no
`NpcActor`: these are set dressing, not characters, and they never talk.
"""
from __future__ import annotations

from hashlib import blake2s

from build_teaching_block import child_path, srgb, vec3

MOTION = "res://assets/shaders/school/dream_motion.gdshader"
PEOPLE = {
    "skin": (205, 170, 141), "skin_dim": (168, 132, 108), "hair": (34, 31, 35), "hair_grey": (152, 148, 146),
    "mouth": (92, 52, 52), "coat_grey": (106, 108, 116), "coat_navy": (49, 58, 82), "coat_olive": (101, 103, 74),
    "coat_rust": (148, 86, 62), "coat_cream": (205, 196, 172), "coat_ink": (40, 40, 48), "trouser": (52, 54, 62),
    "scarf_red": (176, 58, 62), "scarf_blue": (64, 101, 150), "apron_blue": (78, 112, 140),
    "uniform": (66, 92, 104), "sleeve_white": (222, 220, 210),
    "horse_bay": (122, 74, 47), "horse_grey": (156, 151, 143), "mane": (40, 31, 27), "hoof": (44, 40, 38),
    "hen": (232, 226, 210), "hen_brown": (166, 108, 62), "comb": (196, 46, 44), "beak": (226, 168, 62),
    "chair_black": (32, 33, 38), "chair_seat": (58, 62, 76), "chrome": (178, 182, 188),
}
MOTIONS = {
    # One rider: up the slope and gone; the travel vector is set per escalator.
    "stamp": {"sway": (0, -.035, .075), "sway_rate": 1.15, "mechanical": 1},
    "punch": {"sway": (0, .02, .21), "sway_rate": .55, "mechanical": 1},
    "rake": {"sway": (0, 0, .24), "sway_rate": .32},
    "peck": {"sway": (0, -.06, .035), "sway_rate": 1.7, "mechanical": 1},
    "graze": {"sway": (0, -.05, .02), "sway_rate": .21},
    "nod": {"sway": (0, -.025, .012), "sway_rate": .4},
    "swivel": {"turn": .55, "turn_rate": .045},
    "fidget": {"turn": .16, "turn_rate": .11},
}


def _value(v):
    if isinstance(v, tuple):
        return vec3(v)
    if isinstance(v, str):
        return v
    text = f"{float(v):g}"
    return text if "." in text or "e" in text else text + ".0"


def shader_material(b, name, shader, params):
    """Deduplicate a shader's material variants by their serialized values."""
    body = f"shader = {shader}\n" + "".join(f"shader_parameter/{k} = {_value(v)}\n" for k, v in params.items())
    variant = blake2s(body.encode("ascii"), digest_size=8).hexdigest()
    key = f"{name}_{variant}"
    b.local_mats.setdefault(key, f'[sub_resource type="ShaderMaterial" id="Mat_{key}"]\n{body}')
    return key


def motion_material(b, colour, motion, extra=None, *, phase=None, pivot=None):
    """One pigment and motion, with phase/pivot in the material, not each instance."""
    if motion is None:
        return colour
    shader = b.bind("dream_motion", MOTION, "Shader")
    rgb = b.pigments.get(colour) or PEOPLE[colour]
    params = {"albedo": srgb(rgb), **MOTIONS.get(motion, {}), **(extra or {})}
    if phase is not None:
        params["phase"] = phase
    if pivot is not None:
        params["pivot"] = pivot
    return shader_material(b, f"{colour}_{motion}", shader, params)


def part(b, name, parent, pos, size, mat, *, rot=None, shadow=False):
    args = {"position": vec3(pos), "mesh": f'SubResource("{b.mesh("BoxMesh", size=vec3(size))}")',
            "material_override": b.surface(mat)}
    if rot:
        args["rotation_degrees"] = vec3(rot)
    if not shadow:
        args["cast_shadow"] = 0
    b.node(name, parent, "MeshInstance3D", **args)


def _parts(pose, look):
    """(name, centre, size, pigment, group). Feet at the origin, facing +Z."""
    coat, legs, hair = look.get("coat", "coat_grey"), look.get("legs", "trouser"), look.get("hair", "hair")
    skin = look.get("skin", "skin")
    if pose == "sit":
        p = [("ThighL", (-.09, .50, .17), (.14, .13, .42), legs, "body"),
             ("ThighR", (.09, .50, .17), (.14, .13, .42), legs, "body"),
             ("ShinL", (-.09, .23, .36), (.12, .46, .13), legs, "body"),
             ("ShinR", (.09, .23, .36), (.12, .46, .13), legs, "body"),
             ("Torso", (0, .86, -.02), (.40, .60, .23), coat, "body"),
             ("Neck", (0, 1.20, .0), (.10, .08, .10), skin, "body"),
             ("Head", (0, 1.34, .03), (.21, .24, .22), skin, "body"),
             ("Hair", (0, 1.45, -.01), (.225, .07, .235), hair, "body"),
             ("ForearmL", (-.21, .98, .22), (.09, .09, .34), coat, "hand"),
             ("ForearmR", (.21, .98, .22), (.09, .09, .34), coat, "hand"),
             ("HandL", (-.21, .98, .42), (.08, .06, .09), skin, "hand"),
             ("HandR", (.21, .98, .42), (.08, .06, .09), skin, "hand"),
             ("UpperArmL", (-.24, .95, -.01), (.09, .30, .11), coat, "body"),
             ("UpperArmR", (.24, .95, -.01), (.09, .30, .11), coat, "body")]
        face_y = 1.34
    elif pose == "squat":
        p = [("Knees", (0, .36, .16), (.38, .24, .32), legs, "body"),
             ("Feet", (0, .06, .12), (.34, .12, .30), "hair", "body"),
             ("Torso", (0, .62, -.04), (.38, .46, .26), coat, "body"),
             ("Head", (0, 1.00, .05), (.20, .22, .21), skin, "body"),
             ("Scarf", (0, 1.09, .02), (.235, .12, .235), hair, "body"),
             ("ArmL", (-.22, .55, .14), (.09, .09, .36), coat, "hand"),
             ("ArmR", (.22, .55, .14), (.09, .09, .36), coat, "hand")]
        face_y = 1.00
    else:
        p = [("LegL", (-.09, .43, 0), (.14, .86, .16), legs, "body"),
             ("LegR", (.09, .43, 0), (.14, .86, .16), legs, "body"),
             ("Torso", (0, 1.15, 0), (.42, .60, .24), coat, "body"),
             ("Neck", (0, 1.49, .01), (.10, .08, .10), skin, "body"),
             ("ArmL", (-.27, 1.12, 0), (.10, .58, .12), coat, "body"),
             ("ArmR", (.27, 1.12, 0), (.10, .58, .12), coat, "hand")]
        face_y = 1.63
        if pose == "bowed":
            p += [("Head", (0, 1.58, .08), (.21, .24, .22), skin, "body"),
                  ("Hair", (0, 1.69, .05), (.225, .07, .235), hair, "body")]
            face_y = 1.58
        else:
            p += [("Head", (0, 1.63, .01), (.21, .24, .22), skin, "body"),
                  ("Hair", (0, 1.74, -.01), (.225, .07, .235), hair, "body")]
    if look.get("droop"):
        # A mouth that only ever turns down: three short strokes, not a texture.
        z = .03 + .111 if pose != "bowed" else .08 + .111
        p += [("Mouth", (0, face_y - .065, z), (.07, .013, .01), "mouth", "body"),
              ("MouthL", (-.045, face_y - .078, z), (.022, .022, .01), "mouth", "body"),
              ("MouthR", (.045, face_y - .078, z), (.022, .022, .01), "mouth", "body")]
    if look.get("scarf"):
        p.append(("Collar", (0, face_y - .17 if pose != "squat" else .82, .0), (.30, .07, .27), look["scarf"], "body"))
    return p


def figure(b, parent, name, pos, yaw, look, *, pose="stand", body=None, hand=None, phase=None,
           extra=None, shadow=True):
    """One person. `body`/`hand` name a motion; travel extras ride in `extra`."""
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)))
    p = child_path(parent, name)
    for part_name, centre, size, colour, group in _parts(pose, look):
        motion = hand if group == "hand" and hand else body
        mat = motion_material(b, colour, motion, extra if motion == body else None, phase=phase)
        part(b, part_name, p, centre, size, mat, shadow=shadow and size[1] > .2)
    return p


def horse(b, parent, name, pos, yaw, coat, phase=0.0):
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)))
    p = child_path(parent, name)
    part(b, "Body", p, (0, 1.22, -.15), (.56, .62, 1.55), coat, shadow=True)
    for i, (x, z) in enumerate(((-.17, .45), (.17, .45), (-.17, -.75), (.17, -.75))):
        part(b, f"Leg{i}", p, (x, .47, z), (.13, .92, .14), coat, shadow=True)
        part(b, f"Hoof{i}", p, (x, .05, z), (.15, .10, .16), "hoof")
    part(b, "Tail", p, (0, 1.05, -.98), (.09, .66, .10), "mane")
    head = motion_material(b, coat, "graze", phase=phase)
    mane = motion_material(b, "mane", "graze", phase=phase)
    for part_name, centre, size, mat in (("Neck", (0, 1.62, .66), (.27, .58, .34), head),
                                         ("Head", (0, 1.86, .98), (.24, .29, .58), head),
                                         ("Muzzle", (0, 1.78, 1.25), (.21, .2, .12), head),
                                         ("Mane", (0, 1.83, .58), (.07, .44, .32), mane),
                                         ("EarL", (-.07, 2.06, .78), (.05, .11, .05), mane),
                                         ("EarR", (.07, 2.06, .78), (.05, .11, .05), mane)):
        part(b, part_name, p, centre, size, mat, shadow=True)


def hen(b, parent, name, pos, yaw, coat, phase):
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)))
    p = child_path(parent, name)
    part(b, "Body", p, (0, .2, 0), (.19, .17, .27), coat)
    part(b, "Tail", p, (0, .29, -.15), (.11, .12, .06), coat)
    for i, x in enumerate((-.04, .04)):
        part(b, f"Leg{i}", p, (x, .06, 0), (.02, .12, .02), "beak")
    for part_name, centre, size, colour in (("Head", (0, .33, .14), (.09, .10, .1), coat),
                                            ("Comb", (0, .40, .14), (.025, .04, .07), "comb"),
                                            ("Beak", (0, .32, .2), (.03, .025, .04), "beak")):
        part(b, part_name, p, centre, size, motion_material(b, colour, "peck", phase=phase))


def swivel_chair(b, parent, name, pos, yaw, phase, motion="swivel"):
    """An office chair turned away, drifting on its gas lift."""
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)))
    p = child_path(parent, name)
    for part_name, centre, size, colour in (
        ("Seat", (0, .47, 0), (.48, .08, .46), "chair_seat"),
        ("Back", (0, .83, -.22), (.44, .58, .06), "chair_black"),
        ("Spine", (0, .58, -.2), (.06, .2, .05), "chrome"),
        ("ArmL", (-.25, .62, -.02), (.04, .05, .30), "chair_black"),
        ("ArmR", (.25, .62, -.02), (.04, .05, .30), "chair_black"),
        ("Lift", (0, .25, 0), (.05, .4, .05), "chrome"),
        ("StarA", (0, .05, 0), (.62, .04, .05), "chair_black"),
        ("StarB", (0, .05, 0), (.05, .04, .62), "chair_black"),
    ):
        mat = motion_material(b, colour, motion, phase=phase, pivot=(-centre[0], 0, -centre[2]))
        part(b, part_name, p, centre, size, mat)
