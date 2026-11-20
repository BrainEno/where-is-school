"""Hall and reverse dressings for the same fitted leaf/collider.

No room names on the experimental leaves. HallSign is a small piece of the
silhouette that can be picked along with the handle, not a second hotspot.
"""

FACE_PIGMENTS = {
    "milk": (218, 202, 164), "faded_coral": (164, 83, 77), "paper_grey": (203, 187, 175),
    "carbon": (65, 60, 85), "old_gold": (183, 143, 83), "machine_green": (154, 188, 169),
    "wash_enamel": (98, 126, 135), "wine": (120, 59, 73),
}


def fitted_face(b, p, role, side, sign):
    def piece(name, x, y, w, h, tone, lay=.087, thickness=.022, roll=0):
        b.box(side+name, p, (x, y, sign*lay), (w, h, thickness), tone,
              rot=(0, 0, roll) if roll else None)

    def rim(name, x, y, w, h, tone, t=.043, lay=.097):
        piece(name+"Top", x, y+h/2, w, t, tone, lay)
        piece(name+"Bottom", x, y-h/2, w, t, tone, lay)
        piece(name+"Left", x-(w-t)/2, y, t, h-t, tone, lay)
        piece(name+"Right", x+(w-t)/2, y, t, h-t, tone, lay)

    if role == "projection_room":
        # A steel light trap with the pale edge of a strip just visible in it.
        piece("Baffle", .03, 1.27, .94, 1.72, "edge", .093, .041)
        rim("LightTrap", .03, 1.29, .78, 1.49, "door_frame", .091, .121)
        piece("FilmLeader", -.21, 1.27, .27, 1.29, "wine", .126, .017)
        for i in range(7):
            piece(f"Perforation{i}", -.22, .76+i*.138, .079, .048, "old_gold", .141, .015)
        rim("Gate", .15, 1.47, .34, .52, "old_gold", .046, .129)
        piece("Sign", .17, 1.991, .31, .152, "carbon", .143)
        piece("LeaderTip", .20, 1.996, .15, .019, "milk", .157)
    elif role == "computer_room":
        # A rack panel, not the usual classroom vision-light and kick plate.
        piece("Rack", -.01, .86, 1.15, 1.33, "edge", .093, .045)
        for i in range(7):
            piece(f"RackSlat{i}", -.03 if i != 4 else .095, .30+i*.167, .96 if i != 4 else .71,
                  .096, "machine_green" if i == 4 else "door_frame", .124, .047)
        piece("Sign", .15, 1.921, .48, .217, "edge", .111, .063)
        for i in range(3):
            piece(f"Line{i}", .079+.058*i, 1.976-.055*i, .20, .022, "machine_green", .15, .018)
    elif role == "vacant_office":
        # A closed leaf that almost continues the surrounding wall; old tack
        # holes and an ink corner are all that remain of its sign.
        piece("PaintOver", -.016, .94, 1.56, .32, "paper_grey", .087)
        piece("PaintTape", -.014, .777, 1.57, .026, "door_frame", .095, .013)
        piece("GhostStock", .019, 1.761, .58, .43, "paper_grey", .088, .020, 3)
        piece("Sign", .121, 1.838, .40, .28, "door_leaf", .107, .024, -4)
        piece("InkCornerA", .102, 1.901, .28, .025, "faded_coral", .126, .010)
        piece("InkCornerB", .229, 1.844, .027, .103, "faded_coral", .126, .010)
        for i, x in enumerate((-.22, .35)):
            piece(f"Tack{i}", x, 1.97-i*.037, .029, .029, "carbon", .11, .020)
    elif role == "principal_office":
        # Ornamental architecture that misses its own axis. It looks imposing
        # without forming another opening or moving the actual latch.
        piece("Ground", 0, 1.25, 1.16, 1.96, "carbon", .091, .033)
        for i, (x, y, w, h) in enumerate(((-.42, 1.17, .094, 1.75), (.45, 1.18, .08, 1.77),
                                            (-.01, .40, 1.08, .093), (.10, 1.77, .81, .084))):
            piece(f"Moulding{i}", x, y, w, h, "old_gold", .120, .040)
        piece("GableLeft", -.244, 1.99, .49, .074, "old_gold", .127, .052, 19)
        piece("GableRight", .320, 2.036, .49, .074, "old_gold", .127, .052, -22)
        piece("Sign", .066, 1.965, .26, .231, "wine", .134, .042)
        piece("Pin", .106, 1.958, .045, .151, "milk", .161)
    elif role == "staff_office":
        # Long, wired glass and a half-raised shade from a working building.
        piece("VisionRebate", -.044, 1.618, 1.22, .68, "door_frame", .091, .034)
        piece("WiredGlass", -.044, 1.598, 1.13, .547, "vision", .115)
        for i in range(6):
            piece(f"Wire{i}", -.49+i*.178, 1.590, .010, .492, "vision_light", .130, .008)
        piece("Shade", -.114, 1.787, .98, .245, "milk", .142, .016, -3)
        piece("Sign", .26, 1.555, .32, .224, "faded_coral", .148)
        piece("RotaStroke", .267, 1.576, .19, .020, "milk", .162)
        piece("ScuffRail", -.026, .83, 1.51, .056, "steel", .107, .053)
        piece("KickRail", .013, .253, 1.49, .19, "door_frame")
    elif role == "restroom_03":
        # Enamel, drain slots and a small abstract water mark, like the tiles
        # on the landing. The prompt still identifies this as a public toilet.
        piece("Glaze", .012, .79, 1.56, 1.19, "wash_enamel", .088)
        piece("Grille", 0, .52, .87, .33, "door_frame", .107)
        for i in range(4):
            piece(f"Louvre{i}", -.018, .40+i*.075, .73-i*.047, .034, "vision_light", .128, .030)
        piece("Sign", .15, 1.821, .41, .36, "door_frame", .109, .068)
        piece("TileA", .09, 1.862, .098, .098, "milk", .156, .018, 45)
        piece("TileB", .215, 1.768, .098, .098, "machine_green", .156, .018, 45)
    else:
        raise ValueError(role)
