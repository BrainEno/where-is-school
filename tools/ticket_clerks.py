"""First-party seated meshes for the teaching block's three ticket clerks.

The booth keeps the same clock for all three hands. Human detail lives in the
painted faces and tailored uniforms, not in a different animation for each clerk.
Local metres: seats at floor level, fronts towards +Z.
"""
from __future__ import annotations

from build_teaching_block import child_path, vec3
from exam_crowd import Arm, hand, pose_loop, visible
from exam_crowd_forms import Look, PigmentMesh, add, draped_applique, hall_shoe, tint
from exam_hall_heads import HeadCut, sculpt_head


COAT = (65, 86, 101)
LINEN = (211, 200, 176)
SKIRT = (66, 65, 79)
# Nearest the door first. The counter is rotated to face into the gallery.
STATIONS = (.91, 0., -.91)
SEAT_Z = -.14
ELBOW = (.199, .973, .065)
PRESS_Z = SEAT_Z + ELBOW[2] + .305

FACES = (
    ((211, 158, 121), (57, 47, 48), .99, .176, 1.169, False,
     HeadCut(1.04, 1.04, .955, (.017, .097, .028), (.043, .000, .0048), (.026, -.005),
             (.182, .065, .059, .258, -.021), "bob", mature=True)),
    ((182, 133, 109), (67, 58, 58), .97, .186, 1.184, True,
     HeadCut(.99, 1.02, 1.014, (.015, .092, .031), (.043, -.002, .0046), (.025, -.004),
             (.191, .141, .107, .260, .021), "part", mature=True)),
    ((219, 169, 138), (64, 47, 46), 1.02, .181, 1.157, False,
     HeadCut(1.08, 1.08, .973, (.018, .098, .022), (.045, .001, .005), (.027, -.003),
             (.196, .151, .104, .263, -.010), "knot", mature=True)),
)


def sleeved_arm(mesh, shoulder, elbow):
    mesh.sweep([(shoulder, .068, .063),
                (tuple((a+b)*.5 for a, b in zip(shoulder, elbow)), .068, .064),
                (elbow, .050, .047)], [COAT, tint(COAT, -8)], 8)


def forearm(mesh, look, elbow, wrist):
    cuff = add(wrist, (0, -.005, -.022))
    mesh.sweep([(elbow, .048, .045), (add(cuff, (0, -.004, -.044)), .037, .035),
                (cuff, .033, .031), (wrist, .032, .028)],
               [COAT, tint(COAT, 4), LINEN], 8)
    hand(mesh, Arm(elbow, wrist, "grip", (0, -.08, 1)), look.skin)


def uniform(look, head_y):
    f = look.frame
    profile = [(.488, f*.91, .138, 0, .011), (.562, f*.98, .137, 0, .002),
               (.675, f*.87, .114, 0, -.004), (.804, f*.91, .121, -.003, -.004),
               (.945, f, .130, 0, .003), (1.042, f, .092, 0, -.004),
               (1.108, .058, .055, 0, -.005)]
    m = PigmentMesh().form(profile, [tint(COAT, -18), COAT, COAT, tint(COAT, 5), COAT, tint(COAT, 10)], 12)
    m.form([(1.075, .049, .043, 0, -.004), (head_y+.019, .041, .037, 0, .001)], look.skin, 8)
    mark = lambda color, poly: draped_applique(m, profile, color, poly, .003)
    mark(tint(COAT, -23), ((-.007, .542), (.008, .542), (.010, 1.073), (-.006, 1.073)))
    mark((112, 70, 77), ((-.023, 1.092), (.024, 1.092), (.038, 1.033), (.004, 1.001), (-.032, 1.044)))
    for s in (-1, 1):
        mark(LINEN, [(s*x, y) for x, y in ((.043, 1.109), (.084, 1.061), (.054, 1.020), (.017, 1.075))])
    for y in (.672, .754, .839, .928):
        mark((170, 146, 110), ((-.007, y), (.001, y-.007), (.009, y), (.001, y+.007)))
    # Brushed pin and pocket welt, not a printed or named portrait panel.
    mark((183, 155, 111), ((-.152, .976), (-.092, .976), (-.092, .952), (-.152, .952)))
    mark(tint(COAT, 20), ((-.147, .918), (-.085, .918), (-.085, .908), (-.147, .908)))
    left_elbow = (-.193, .966, .035)
    sleeved_arm(m, (-f*.87, 1.031, -.034), left_elbow)
    sleeved_arm(m, (f*.87, 1.030, -.034), ELBOW)
    forearm(m, look, left_elbow, (-.132, 1.038, .277))
    return m


def seated_legs(look):
    m = PigmentMesh().form([(.425, .170, .213, 0, .111), (.460, .175, .214, 0, .116),
                            (.562, .155, .164, 0, .074)], [tint(SKIRT, -12), SKIRT], 10)
    for s in (-1, 1):
        x = s*.091
        m.sweep([((x, .071, .253), .036, .036), ((x, .195, .263), .049, .045),
                 ((x, .440, .292), .058, .059)], [tint(SKIRT, -5), tint(SKIRT, 5)], 8)
        hall_shoe(m, look, x, .249, s, "flat")
    return m


def build_clerk(b, booth, index, seat_x):
    skin, hair, head_width, shoulders, head_y, glasses, cut = FACES[index]
    look = Look("clerk", COAT, LINEN, SKIRT, skin, hair, cut.lock, .50,
                shoulders, 1., head_width, glasses)
    name = f"Clerk{index}"
    clerk = child_path(booth, name)
    b.node(name, booth, position=vec3((seat_x, 0, SEAT_Z)))
    visible(b, "PlantedFeet", clerk, seated_legs(look))
    visible(b, "Uniform", clerk, uniform(look, head_y))
    head = child_path(clerk, "Head")
    b.node("Head", clerk, position=vec3((0, head_y, .004)), rotation_degrees=vec3((0, 8, 0)))
    visible(b, "FaceAndHair", head, sculpt_head(look, cut))
    pivot = child_path(clerk, "StampArm")
    b.node("StampArm", clerk, position=vec3(ELBOW), rotation_degrees=vec3((-18, 0, 0)))
    m = PigmentMesh()
    forearm(m, look, ELBOW, add(ELBOW, (-.008, .084, .252)))
    visible(b, "SleeveAndHand", pivot, m, ELBOW)
    b.box("StampFoot", pivot, (0, .028, .305), (.059, .026, .051), "stamp_rubber")
    b.round("StampHandle", pivot, (0, .065, .305), .019, .050, "stamp_wood", sides=8)
    return f"{name}/StampArm"


def stamp_loop(b, booth, tracks):
    # Decisive stops, repeated without anticipation, shifting posture or a reaction to being watched.
    length = 2.80
    keys = ((0, -18), (.78, -18), (.88, 0), (1.045, 0), (1.20, -18),
            (1.48, -18), (1.58, 0), (1.73, 0), (1.88, -18), (length, -18))
    pose = tuple((t, (pitch, 0, 0)) for t, pitch in keys)
    pose_loop(b, booth, "Stamp", length, {path: pose for path in tracks}, interpolation=1)
