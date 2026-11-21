"""Stage 03's figures as silent vignettes, not actors.

Native animation moves only the torso, head and posed forearms; the shoes stay
planted. Handheld props inherit the grip's pivot. The conversation has pauses;
the quieter study actions are offset from it, not another synchronized clerk loop.
"""
from __future__ import annotations

from dataclasses import dataclass
import math

from build_teaching_block import child_path, vec3
from dressing_geometry import rotate
from exam_crowd_forms import (
    INK, LOOKS, PAPER, RULE, PigmentMesh, add, head, legs, mix, scale, sub, tint, torso, unit,
)


@dataclass(frozen=True)
class Arm:
    elbow: tuple
    wrist: tuple
    grip: str = "rest"
    aim: tuple = (0, -.9, .25)


LOOSE_L = Arm((-.244, .16, -.036), (-.225, -.062, .045))
LOOSE_R = Arm((.23, .16, -.034), (.207, -.07, .056))
POCKET = Arm((-.250, .173, -.030), (-.145, .033, .127), "grip", (.55, -.58, .47))
ARMS = {
    "Converse": (POCKET, Arm((.263, .173, .030), (.339, .278, .224), "open", (.45, .22, .87))),
    "Listen": (Arm((-.232, .142, .082), (-.020, .122, .158), "grip", (.91, .1, .40)),
               Arm((.173, .145, .111), (.126, .370, .184), "open", (-.41, .89, .2))),
    "CheckSlip": (LOOSE_L, Arm((.193, .171, .083), (.088, .288, .270), "grip", (.31, .48, .83))),
    "Revise": (Arm((-.216, .165, .041), (-.152, .226, .269), "grip", (-.20, .32, .93)),
               Arm((.235, .194, .028), (.133, .309, .236), "grip", (-.68, -.13, .72))),
    "OfferSnacks": (POCKET, Arm((.222, .170, .033), (.139, .207, .244), "grip", (.22, .45, .86))),
    "RapOnPlaster": (POCKET, Arm((.191, .265, .236), (.018, .365, .422), "fist", (-.31, -.07, .95))),
    "Steady": (Arm((-.227, .205, .122), (-.106, .282, .317), "open", (.16, .35, .92)), LOOSE_R),
}

# Each column is (seconds, degrees). Pauses and accents, not constant oscillation.
# The talker extends first; the others answer with a lean or a delayed nod.
LOOPS = {
    "Converse": (6.4, {
        "Body": ((0, (-1, -6, -3)), (.9, (1, 1, -3)), (2.15, (3, 6, -2)),
                 (2.90, (1, 0, -4)), (4.1, (-2, -8, -3)), (6.4, (-1, -6, -3))),
        "Body/Head": ((0, (-2, 2, -3)), (1.4, (1, -5, 4)), (2.8, (0, -1, 2)),
                      (3.8, (5, 12, -5)), (4.6, (-2, 10, -3)), (6.4, (-2, 2, -3))),
        "Body/ForearmR": ((0, (14, 4, -12)), (.9, (-15, -5, 15)), (1.55, (-6, -7, 4)),
                          (2.1, (-18, 9, 26)), (3.15, (3, 6, 4)), (4.25, (18, 4, -14)), (6.4, (14, 4, -12))),
    }),
    "Listen": (6.4, {
        "Body": ((0, (3, 5, 3)), (1.8, (2, 1, 2)), (3.4, (4, -5, 3)), (6.4, (3, 5, 3))),
        "Body/Head": ((0, (1, -8, 7)), (2.25, (4, -3, 5)), (2.72, (15, -1, 6)), (3.13, (3, -1, 6)),
                      (3.48, (11, 0, 6)), (4.25, (-1, 2, 6)), (5.45, (4, 13, 3)), (6.4, (1, -8, 7))),
    }),
    "CheckSlip": (7.1, {
        "Body": ((0, (5, -3, 2)), (3.05, (7, 2, 1)), (5.18, (0, 0, -2)), (7.1, (5, -3, 2))),
        "Body/Head": ((0, (20, -2, -3)), (1.9, (23, 3, 2)), (3.35, (10, -5, 0)),
                      (4.5, (-2, -21, 4)), (5.48, (-1, -17, 3)), (7.1, (20, -2, -3))),
        "Body/ForearmR": ((0, (1, 1, 0)), (1.45, (-9, -5, 3)), (2.95, (-6, 4, 1)),
                          (4.45, (20, 1, -5)), (5.63, (13, 2, -1)), (7.1, (1, 1, 0))),
    }),
    "Revise": (8.0, {
        "Body": ((0, (6, -2, -2)), (2.2, (8, -2, -1)), (5.8, (5, 1, -2)), (8, (6, -2, -2))),
        "Body/Head": ((0, (21, 3, -2)), (1.7, (26, -6, -1)), (2.8, (23, 11, 3)),
                      (4.6, (26, 1, 2)), (6.23, (8, 18, -3)), (7.3, (22, 7, -2)), (8, (21, 3, -2))),
        "Body/ForearmR": ((0, (-7, 1, 3)), (1.5, (0, 0, 0)), (2.78, (0, 9, 0)),
                          (3.25, (-5, -7, -3)), (4.15, (-.2, -8, -3)), (5.26, (-.2, 5, -3)),
                          (5.88, (-9, 9, 1)), (8, (-7, 1, 3))),
    }),
    "OfferSnacks": (7.5, {
        "Body": ((0, (3, 2, -2)), (1.75, (2, -4, 3)), (4, (4, 8, 1)), (7.5, (3, 2, -2))),
        "Body/Head": ((0, (9, 0, -3)), (1.9, (0, -14, 6)), (3.65, (-2, 11, 6)), (5.7, (3, 18, -5)), (7.5, (9, 0, -3))),
        "Body/ForearmR": ((0, (7, -4, -7)), (2.2, (-14, -5, 4)), (3.1, (-15, 1, 4)),
                          (4.6, (-3, 4, 3)), (7.5, (7, -4, -7))),
    }),
    "RapOnPlaster": (5.4, {
        "Body": ((0, (-3, -5, 3)), (.9, (1, -6, -1)), (1.54, (5, 0, -2)), (1.95, (1, 0, 1)),
                 (2.7, (-2, 2, 3)), (5.4, (-3, -5, 3))),
        "Body/Head": ((0, (-2, -9, 1)), (1.5, (5, 4, 5)), (2.7, (6, 7, -2)), (4.22, (-5, -22, 4)), (5.4, (-2, -9, 1))),
        "Body/ForearmR": ((0, (39, 4, 21)), (.86, (27, 4, 14)), (1.54, (2, 0, 0)), (1.86, (30, 0, 16)),
                          (2.14, (6, 0, 4)), (2.85, (21, 1, 12)), (5.4, (39, 4, 21))),
    }),
    "Steady": (5.4, {
        "Body": ((0, (6, -9, -3)), (1.56, (9, -5, -4)), (2.2, (6, -6, -3)), (5.4, (6, -9, -3))),
        "Body/Head": ((0, (7, 1, -4)), (1.93, (-2, 6, -5)), (3.45, (5, -25, 2)), (5.4, (7, 1, -4))),
        "Body/ForearmL": ((0, (5, 8, -5)), (1.56, (0, 2, 3)), (2.23, (-2, 4, 2)), (5.4, (5, 8, -5))),
    }),
}


def keyframes(b, figure, action):
    duration, tracks = LOOPS[action]
    props = {"length": duration, "loop_mode": 1}
    for i, (path, keys) in enumerate(tracks.items()):
        slot = f"tracks/{i}/"
        props[slot + "type"] = '"value"'
        props[slot + "path"] = f'NodePath("{path}:rotation_degrees")'
        props[slot + "interp"] = 2
        props[slot + "loop_wrap"] = "true"
        times = ", ".join(f"{time:g}" for time, _ in keys)
        transitions = ", ".join("1" for _ in keys)
        values = ", ".join(vec3(value) for _, value in keys)
        props[slot + "keys"] = (f'{{"times": PackedFloat32Array({times}), "transitions": '
                                f'PackedFloat32Array({transitions}), "update": 0, "values": [{values}]}}')
    animation = b.mesh("Animation", **props)
    library = b.mesh("AnimationLibrary", _data=f'{{&"{action}": SubResource("{animation}")}}')
    b.node("Motion", figure, "AnimationPlayer", autoplay=f'"{action}"', libraries=f'{{&"": SubResource("{library}")}}')


def visible(b, name, parent, mesh, origin=(0, 0, 0), *, shadow=True):
    if "exam_pigment" not in b.local_mats:
        b.mat("exam_pigment", vertex_color_use_as_albedo="true", vertex_color_is_srgb="true", diffuse_mode=2)
    mesh.points = [sub(p, origin) for p in mesh.points]
    b.flat(name, parent, b.mesh("ArrayMesh", _surfaces=mesh.surface()), "exam_pigment", (0, 0, 0), shadow=shadow)


def upper_sleeve(mesh, look, shoulder, elbow):
    cloth = look.trim if look.cut == "varsity" else look.cloth
    end = add(elbow, scale(unit(sub(elbow, shoulder)), .020))
    mesh.sweep([(shoulder, .070, .073), (mix(shoulder, elbow, .34), .083, .083),
                (mix(shoulder, elbow, .79), .067, .067), (end, .060, .063)],
               [tint(cloth, 5), cloth, look.trim if look.cut == "shirt" else tint(cloth, -12)])


def hand(mesh, arm, skin):
    wrist, aim = arm.wrist, unit(arm.aim)
    length = .094 if arm.grip == "open" else .076
    point = lambda distance: add(wrist, scale(aim, distance))
    mesh.sweep([(point(-.013), .031, .033), (point(.029), .043, .027),
                (point(length*.76), .037, .023), (point(length), .026, .014)],
               [skin, tint(skin, 6), tint(skin, -7)], 8)
    # Offset thumb and a shallower raised finger plane make the free hand readable.
    side = -1 if wrist[0] > 0 else 1
    thumb = add(point(.046), (side*.041, .005, .006))
    mesh.sweep([(point(.021), .019, .020), (thumb, .016, .014),
                (add(thumb, scale(aim, .024)), .012, .010)], [tint(skin, 3), tint(skin, 12)], 6)
    if arm.grip == "open":
        across = (side*.014, .007, 0)
        mesh.sweep([(add(point(.059), across), .017, .015), (add(point(.106), across), .013, .009)],
                   [tint(skin, 8)], 6)


def forearm(look, arm):
    m = PigmentMesh()
    elbow, wrist = arm.elbow, arm.wrist
    axis = unit(sub(wrist, elbow))
    at = lambda d: add(wrist, scale(axis, d))
    cutoff = -.146 if look.cut == "shirt" else -.010
    cloth = look.skin if look.cut == "shirt" else look.trim if look.cut == "varsity" else look.cloth
    m.sweep([(sub(elbow, scale(axis, .029)), .060, .061), (mix(elbow, at(cutoff), .47), .058, .058),
             (at(cutoff-.029), .048, .046), (at(cutoff), .039, .040)],
            [tint(cloth, -8), cloth, look.trim if look.cut in ("knit", "varsity") else tint(cloth, -15)])
    if look.cut == "shirt":
        m.sweep([(at(cutoff-.014), .048, .045), (at(-.077), .043, .040),
                 (at(.005), .032, .033)], [tint(look.skin, -7), look.skin])
    hand(m, arm, look.skin)
    return m


def paper_piece(name):
    mesh = PigmentMesh()
    if name == "Notes":
        at, tilt = (-.018, .250, .332), (-18, 0, 0)
        on_page = lambda x, y, z: add(at, rotate((x, y, z), tilt))
        mesh.tile((55, 100, 110), on_page(0, -.010, 0), (.311, .019, .218), tilt)
        for i, side in enumerate((-1, 1)):
            mesh.tile(PAPER, on_page(.074*side, .003, -.004), (.143, .012, .197-i*.014), tilt)
            for j, width in enumerate((.103, .080, .113, .097, .062)):
                x, z = side*.074-width*.5, -.061+.026*j+i*.006
                mesh.panel(RULE, [on_page(a, .010, b) for a, b in ((x,z), (x+width,z), (x+width,z+.004),
                                                                  (x,z+.004))], at)
        mesh.panel((158, 89, 73), [on_page(x, .011, z) for x, z in ((.034, -.079), (.039, -.078),
                       (.039, .075), (.034, .076))], at)
    elif name == "Pencil":
        # Tip reaches the right-hand page on the low strokes; the recovery lifts clear.
        tip, tail = (.071, .274, .378), (.157, .337, .241)
        stations = [(tip, .001, .001), (mix(tip, tail, .13), .0058, .0058),
                    (mix(tip, tail, .88), .0058, .0058), (tail, .006, .006)]
        mesh.sweep(stations, [(194, 164, 115), (221, 162, 72), (173, 103, 89)], 6)
    elif name == "AdmissionSlip":
        at, tilt = (.120, .354, .327), (63, 5, -13)
        mesh.tile(PAPER, at, (.157, .004, .181), tilt, radius=.004)
        for x, w, z, h, color in ((0, .139, -.064, .024, (161, 85, 75)), (-.048, .026, -.019, .029, RULE),
                                  (.017, .083, -.023, .006, INK), (.010, .070, -.003, .005, RULE),
                                  (.007, .103, .020, .007, RULE), (.007, .102, .042, .006, RULE)):
            mesh.panel(color, [add(at, rotate((a, .003, b), tilt)) for a, b in (
                (x-w/2,z-h/2), (x+w/2,z-h/2), (x+w/2,z+h/2), (x-w/2,z+h/2))], at)
    elif name == "SnackPouch":
        cloth = (168, 76, 64)
        mesh.form([(.160, .042, .025, .146, .321), (.193, .069, .040, .151, .326),
                   (.287, .067, .032, .156, .322), (.314, .052, .016, .152, .318),
                   (.330, .057, .017, .161, .314)], [tint(cloth, -16), cloth, tint(cloth, 8), PAPER], 8)
        mesh.panel(PAPER, [(.110, .204, .357), (.195, .212, .356), (.183, .263, .356), (.115, .254, .36)], (.15, .23, .32))
    else:
        raise ValueError(f"Unknown held prop {name}")
    return mesh


PROPS = {"Revise": ("Notes", "Pencil"), "CheckSlip": (None, "AdmissionSlip"), "OfferSnacks": (None, "SnackPouch")}


def student(b, parent, name, pos, yaw, outfit, action, *, step=.035, seated=False):
    look = LOOKS[outfit]
    figure = child_path(parent, name)
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)))
    visible(b, "PlantedFeet", figure, legs(look, step, seated))

    body = child_path(figure, "Body")
    hip = .516 if seated else look.hip
    b.node("Body", figure, position=vec3((0, hip, 0)), scale=vec3((1, look.torso, 1)))
    chest = torso(look)
    for side, s, arm, prop in zip("LR", (-1, 1), ARMS[action], PROPS.get(action, (None, None))):
        upper_sleeve(chest, look, (s*look.frame*.91, .421, .009), arm.elbow)
        name = "Forearm" + side
        b.node(name, body, position=vec3(arm.elbow))
        fore = child_path(body, name)
        visible(b, "SleeveAndHand", fore, forearm(look, arm), arm.elbow)
        if prop:
            visible(b, prop, fore, paper_piece(prop), arm.elbow, shadow=False)
    visible(b, "Tailoring", body, chest)
    b.node("Head", body, position=vec3((.006, .536, .017)))
    visible(b, "FaceAndHair", child_path(body, "Head"), head(look))
    keyframes(b, figure, action)


def group(b, parent, name, origin, placements):
    b.node(name, parent, position=vec3(origin))
    p = child_path(parent, name)
    for i, (x, z, yaw, outfit, action, stride, seated) in enumerate(placements):
        student(b, p, f"Person{i}", (x, 0, z), yaw, outfit, action, step=stride, seated=seated)
    return p


def exam_candidates(b, parent, rise):
    # Slightly open triangles, not closed rings of people in the travel lane.
    group(b, parent, "Clique0", (-1.5, rise, -41.43), (
        (-.62, .04,  111, "knit", "Listen", .043, False),
        ( .54, -.12, -77, "varsity", "Converse", -.052, False),
        ( .06, .47,  166, "shirt", "CheckSlip", .036, False),
    ))
    group(b, parent, "Clique1", (14.4, rise, -41.30), (
        (-.48, -.02, 125, "hoodie", "Revise", -.042, False),
        ( .47, .10, -137, "coat", "CheckSlip", .051, False),
    ))
    b.node("Troublemaker", parent, position=vec3((-13.55, rise, -29.2)))
    p = child_path(parent, "Troublemaker")
    student(b, p, "Ranter", (0, 0, 0), -90, "windbreaker", "RapOnPlaster", step=.079)
    student(b, p, "Accomplice", (.51, 0, .43), -142, "workshirt", "Steady", step=-.060)
    return p


def waiting_candidates(b, parent):
    group(b, parent, "Clique0", (1.45, 0, 1.30), (
        (-.57, -.04,  87, "cardigan", "OfferSnacks", .036, False),
        ( .56, -.13, -81, "blouson", "Converse", -.048, False),
        ( .02, .59,  175, "jersey", "Listen", .028, False),
    ))
    p = group(b, parent, "Clique1", (-3.75, 0, 2.51), (
        (-.09, -.03, 154, "pullover", "Revise", .025, True),
        ( .52, .07, -147, "vest", "CheckSlip", -.020, False),
    ))
    # A borrowed stool stays against the wall, out of the door/inspection stances.
    # The existing switched-away chairs still turn on their lifts.
    b.round("StudyStool", p, (-.09, .420, -.035), .220, .063, "pomo_mint", top=.211, sides=12, shadow=True)
    for i, (x, z) in enumerate(((-.22, -.145), (.046, -.102), (-.111, .127))):
        b.round(f"StoolLeg{i}", p, (x, .204, z), .020, .408, "pomo_black", top=.014, sides=7)
