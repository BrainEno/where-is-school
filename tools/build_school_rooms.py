#!/usr/bin/env python3
"""Generate the fitted 03 staff office, 01 restroom and their two-sided thresholds."""
from __future__ import annotations

import argparse

from build_teaching_block import ROOT, ROOM_PORTAL_WIDTH, complement, srgb, vec3
from fixture_geometry import Facets, FixtureBuild, basin, pipe, rounded_rect, vessel

OFFICE_WIDTH, OFFICE_DEPTH = 8.70, 6.20
WASH_WIDTH, WASH_DEPTH = 8.24, 6.32
OFFICE_DOOR_X, WASH_DOOR_Z = -2.28, 1.51
DOOR_H = 2.36
ROLES = {
    "staff_office": ("StaffOffice", (62, 69, 98), (104, 123, 116), "教师办公室", "STAFF OFFICE", "03"),
    "restroom": ("Restroom", (45, 72, 86), (83, 129, 147), "厕所", "RESTROOM", "01"),
}


def label(b, name, parent, pos, text, pixel, rotation=(0, 0, 0), ink=(241, 224, 187)):
    font = b.bind("font", "res://assets/fonts/NotoSansSC-Regular.ttf", "FontFile")
    b.node(name, parent, "Label3D", position=vec3(pos), rotation_degrees=vec3(rotation),
           text=f'"{text}"', font=font, font_size=54, pixel_size=pixel, outline_size=0, modulate=srgb(ink))


def solid(b, name, parent, pos, size, mat, *, fade=False, rotation=(0, 0, 0)):
    p = b.shell(name, parent, pos, rotation, ("camera_occluder",) if fade else ())
    b.shape("Collision", p, (0, 0, 0), size)
    b.box("Surface", p, (0, 0, 0), size, mat, shadow=True)
    return p


def door_path(role):
    return f"res://scenes/environment/props/{role}_door.tscn"


def door(role):
    room, trim, skin, cn, en, number = ROLES[role]
    b = FixtureBuild(room + "Door", {"door_frame": trim, "door_leaf": skin, "edge": (40, 46, 56),
                     "tread": (103, 100, 98), "steel": (190, 177, 148), "vision": (67, 93, 107),
                     "vision_light": (134, 156, 159), "sign_ink": (48, 47, 65)})
    w = ROOM_PORTAL_WIDTH
    p = b.shell("Panel", ".", groups=("camera_occluder",))
    b.shape("ClosedThreshold", p, (0, DOOR_H/2, 0), (w, DOOR_H, 0.22))
    b.box("Leaf", p, (0, 1.132, 0), (w-0.22, 2.25, 0.148), "door_leaf", shadow=True)
    for side, x in (("Left", -w/2+0.058), ("Right", w/2-0.058)):
        b.box("Jamb"+side, p, (x, DOOR_H/2, 0), (0.116, DOOR_H, 0.29), "door_frame", shadow=True)
    b.box("Head", p, (0, DOOR_H-0.056, 0), (w, 0.112, 0.29), "door_frame")
    b.box("Sill", p, (0, 0.018, 0), (w, 0.036, 0.27), "tread")
    # The lock and hinge stay at the same physical edges on the two faces.
    for name, sign, yaw in (("Hall", 1, 0), ("Room", -1, 180)):
        z = sign*0.085
        b.box(name+"Kick", p, (0, 0.172, z), (w-0.25, 0.21, 0.020), "door_frame")
        b.box(name+"Backplate", p, (0.623, 1.035, z), (0.095, 0.32, 0.029), "edge")
        b.box(name+"LeverMount", p, (0.623, 1.102, z+sign*.033), (0.05, 0.042, 0.058), "steel")
        b.box(name+"Lever", p, (0.547, 1.102, z+sign*.056), (0.20, 0.041, 0.032), "steel")
        for i, y in enumerate((0.33, 1.20, 2.01)):
            b.round(f"{name}Hinge{i}", p, (-0.795, y, z), 0.022, 0.143, "steel", sides=8)
        if role == "staff_office":
            b.box(name+"Bead", p, (0, 1.45, z), (0.71, 0.44, 0.035), "door_frame")
            b.box(name+"Glass", p, (0, 1.45, z+sign*.018), (0.622, 0.35, 0.014), "vision")
            for i in range(2):
                b.box(f"{name}Glaze{i}", p, (-.13+.25*i, 1.45, z+sign*.027), (0.037, 0.29, 0.005), "vision_light")
        else:
            b.box(name+"Grille", p, (0, 0.56, z), (0.57, 0.34, 0.034), "door_frame")
            for i in range(5):
                b.box(f"{name}Louvre{i}", p, (0, 0.44+i*.058, z+sign*.027), (0.51, 0.022, 0.029), "vision_light")
        b.box(name+"Sign", p, (0, 1.95, z+sign*.017), (1.08, 0.30, 0.042), "sign_ink")
        label(b, name+"Primary", p, (0, 2.005, z+sign*.043), cn if sign > 0 else number, 0.0027, (0, yaw, 0))
        label(b, name+"Secondary", p, (0, 1.881, z+sign*.043), en if sign > 0 else "HALL", 0.00138, (0, yaw, 0))
    return b.emit()


def painted_field(b, name, pigments, scale, strength):
    shader = b.bind("paint", "res://assets/shaders/painterly/environment_surface.gdshader", "Shader")
    base, dark, light = map(srgb, pigments)
    b.subs.append(f'''[sub_resource type="ShaderMaterial" id="Mat_{name}"]
shader = {shader}
shader_parameter/base_color = {base}
shader_parameter/shadow_pigment = {dark}
shader_parameter/highlight_pigment = {light}
shader_parameter/brush_pigment = {dark}
shader_parameter/patch_scale = {scale}
shader_parameter/patch_strength = {strength}
shader_parameter/brush_scale = 5.4
shader_parameter/brush_strength = 0.075
shader_parameter/style_level = 2
''')
    # Build.flat calls surface even for local shader materials; register that name once.
    # Keep the resource in the same material table as its StandardMaterial neighbours.
    b.local_mats[name] = b.subs.pop()


def start_room(role, pigments, ambient, backdrop, light, *, sun=0.77, sun_yaw=-37):
    b = FixtureBuild(ROLES[role][0], pigments)
    script = b.bind("location", "res://scripts/world/location_root.gd", "Script")
    b.nodes[0] += f'script = {script}\nlocation_id = &"{role}"\n'
    b.subs.append(f'''[sub_resource type="Environment" id="RoomEnvironment"]
background_mode = 1
background_color = {srgb(backdrop)}
ambient_light_source = 2
ambient_light_color = {srgb(ambient)}
ambient_light_energy = 0.73
tonemap_mode = 2
tonemap_exposure = 0.76
''')
    b.node("WorldEnvironment", ".", "WorldEnvironment", environment='SubResource("RoomEnvironment")')
    b.node("Sun", ".", "DirectionalLight3D", rotation_degrees=vec3((-53, sun_yaw, 0)),
           light_color=srgb(light), light_energy=sun, shadow_enabled="true", directional_shadow_max_distance=22)
    nav = b.bind("navigation", "res://scripts/world/location_navigation.gd", "Script")
    b.node("Navigation", ".", "NavigationRegion3D", script=nav)
    tone = b.bind("room_tone", "res://assets/audio/room_tone_walkway.wav", "AudioStream")
    player = b.bind("ambience", "res://scripts/world/ambience_player.gd", "Script")
    b.node("Ambience", ".", "AudioStreamPlayer", stream=tone, script=player, volume_db=-26, target_db=-29)
    return b


def walls(b, dims, role, door_at, *, door_on_east=False):
    # Roofless cutaway. The near cheeks are still solid: there is no invisible clipping box.
    w, d = dims
    solid(b, "Slab", ".", (0, -.08, 0), (w+.22, .16, d+.22), "floor")
    for name, span, cross, yaw, height, window_side in (
        ("North", (-w/2, w/2), -d/2, 0, 2.88, True),
        ("West", (-d/2, d/2), -w/2, 90, 2.88, True),
        ("South", (-w/2, w/2), d/2, 180, .88, False),
        ("East", (-d/2, d/2), w/2, -90, .88, False),
    ):
        doorway = name == ("East" if door_on_east else "South")
        breaks = [(door_at-ROOM_PORTAL_WIDTH/2, door_at+ROOM_PORTAL_WIDTH/2)] if doorway else []
        for i, (lo, hi) in enumerate(complement(*span, breaks)):
            pos = ((lo+hi)/2, 0, cross) if name in ("North", "South") else (cross, 0, (lo+hi)/2)
            p = b.shell(f"Wall{name}{i}", ".", pos, (0, yaw, 0), ("camera_occluder",))
            width = hi-lo
            b.shape("Solid", p, (0, height/2, 0), (width, height, .19))
            cap = 1.20 if window_side else height-.062
            b.box("Lower", p, (0, cap/2, 0), (width, cap, .19), "lower", shadow=True)
            b.box("Trim", p, (0, cap+.030, 0), (width, .060, .216), "trim")
            b.box("Base", p, (0, .059, .107), (width, .118, .038), "skirt")
            if window_side:
                b.box("Plaster", p, (0, (height+cap+.06)/2, 0), (width, height-cap-.06, .19), "plaster", shadow=True)
                b.box("Rail", p, (0, height-.077, .106), (width, .062, .043), "trim")
    b.bind("door", door_path(role), "PackedScene")
    pos, yaw = ((w/2, 0, door_at), 90) if door_on_east else ((door_at, 0, d/2), 0)
    b.nodes.append('[node name="Door" parent="." instance=ExtResource("door")]\n'
                   f'position = {vec3(pos)}\nrotation_degrees = {vec3((0,yaw,0))}\n')


def add_route(b, role, spawn, anchor, heading):
    b.bind("tap_target", "res://scenes/interaction/interactable.tscn", "PackedScene")
    b.bind("exit", "res://scenes/interaction/location_exit.tscn", "PackedScene")
    b.node("SpawnPoints", ".")
    b.nodes.append('[node name="FromCorridor" type="Marker3D" parent="SpawnPoints" groups=["spawn_point"]]\n'
                   f'position = {vec3(spawn)}\nrotation_degrees = {vec3((0,heading,0))}\n')
    b.node("Interactables", ".")
    b.nodes.append(f'''[node name="BackToCorridor" parent="Interactables" instance=ExtResource("exit")]
position = {vec3(anchor)}
interact_id = &"{role}_to_corridor"
prompt_text = "Return to the corridor"
prompt_key = "prompt.return_to_corridor"
outline_paths = PackedStringArray("../../Door/Panel/Leaf", "../../Door/Panel/RoomLever")
support_paths = PackedStringArray("../../Door/Panel")
radius = 1.42
destination_scene = "res://scenes/locations/corridor/corridor.tscn"
destination_spawn = &"From{ROLES[role][0]}"
destination_id = &"corridor"
''')


def look(b, name, inspection, pos, outline, supports, radius, shot):
    script = b.bind("camera_shot", "res://scripts/world/camera_shot.gd", "Script")
    distance, height, yaw, lens, offset = shot
    b.subs.append(f'''[sub_resource type="Resource" id="Shot_{name}"]
script = {script}
look_offset = {vec3(offset)}
subject_mix = 0.72
distance_scale = {distance}
height_scale = {height}
yaw_degrees = {yaw}
fov = {lens}
glide_seconds = 0.68
''')

    def paths(nodes):
        return "PackedStringArray(" + ", ".join(f'"../../{p}"' for p in nodes) + ")"

    b.nodes.append(f'''[node name="{name}" parent="Interactables" instance=ExtResource("tap_target")]
position = {vec3(pos)}
interact_id = &"{inspection}"
inspection_id = &"{inspection}"
radius = {radius}
outline_paths = {paths(outline)}
support_paths = {paths(supports)}
camera_shot = SubResource("Shot_{name}")
''')


def window(b, name, parent, x, y, z, width, height, blind=False):
    # A deep sill and opaque painted glazing. The warm stripe belongs to the glass,
    # rather than casting a texture on a wall or asking for another viewport.
    b.box(name+"Frame", parent, (x, y, z), (width+.14, height+.14, .114), "skirt", shadow=True)
    for i in range(3):
        w = width/3
        cx = x+(i-1)*w
        b.box(f"{name}Pane{i}", parent, (cx, y, z+.062), (w-.03, height, .012), "sky")
        b.box(f"{name}Horizon{i}", parent, (cx, y-height*.30, z+.070), (w-.03, height*.35, .005), "sky_low")
        if blind and i < 2:
            for j in range(5):
                b.box(f"{name}Slat{i}_{j}", parent, (cx, y+height*.43-.113*j, z+.09),
                      (w-.026, .052, .036), "blind", rot=(15, 0, 0))
    b.box(name+"Sill", parent, (x, y-height/2-.073, z+.080), (width+.23, .075, .30), "trim", shadow=True)


def office():
    colors = {"lower": (93, 110, 109), "skirt": (55, 63, 71), "trim": (155, 139, 111),
              "maple": (157, 125, 86), "edge": (76, 65, 65), "enamel": (82, 105, 96),
              "ochre": (171, 113, 66), "chaff": (205, 176, 130), "paper": (228, 212, 176),
              "ledger": (92, 109, 114), "rule": (135, 117, 97), "stamp": (143, 75, 57),
              "steel": (172, 166, 154), "cup": (191, 199, 176), "seam": (97, 86, 90),
              "sun_wash": (194, 160, 119), "sky": (192, 163, 131), "sky_low": (137, 139, 156),
              "blind": (126, 121, 130), "lamp_skin": (226, 199, 145)}
    b = start_room("staff_office", colors, (177, 181, 211), (73, 66, 86), (255, 223, 172))
    painted_field(b, "plaster", ((188, 177, 160), (152, 151, 162), (220, 202, 172)), .68, .29)
    painted_field(b, "floor", ((130, 115, 117), (99, 96, 118), (174, 146, 125)), .94, .28)
    walls(b, (OFFICE_WIDTH, OFFICE_DEPTH), "staff_office", OFFICE_DOOR_X)
    north = "WallNorth0"
    window(b, "WestWindow", north, -2.21, 2.08, .101, 2.95, 1.11, True)
    window(b, "CopyWindow", north, 2.21, 2.12, .101, 1.91, 1.03)
    for i, z in enumerate((-2.04, -.78, .47, 1.71, 2.89)):
        b.box(f"FloorJoint{i}", ".", (0, .003, z), (8.49, .004, .021), "seam")
    light = Facets()
    light.face((-3.62, .007, -2.84), (-.92, .007, -2.84), (.41, .007, -.78), (-2.17, .007, -.49))
    b.detail("WindowWash", ".", (0, 0, 0), light, "sun_wash")

    # Reading table and an empty chair on its working side. Both cast tidy contact shadows.
    p = solid(b, "Desk", ".", (-2.28, .81, -1.43), (2.60, .086, 1.04), "maple")
    b.box("Lip", p, (0, -.070, .421), (2.47, .090, .147), "edge")
    for i, x in enumerate((-3.37, -1.20)):
        foot = solid(b, f"Pedestal{i}", ".", (x, .384, -1.45), (.36, .768, .85), "enamel")
        for j, y in enumerate((-.210, 0, .210)):
            b.box(f"Drawer{j}", foot, (0, y, .43), (.31, .173, .036), "maple")
            b.box(f"Pull{j}", foot, (0, y+.032, .458), (.17, .028, .038), "edge")
    chair = solid(b, "Chair", ".", (-2.38, .445, -2.45), (.49, .094, .50), "ochre", rotation=(0, -11, 0))
    for i, dx in enumerate((-.198, .198)):
        b.box(f"BackPost{i}", chair, (dx, .21, -.224), (.044, .49, .047), "edge")
        for j, dz in enumerate((-.194, .194)):
            b.box(f"Foot{i}_{j}", chair, (dx, -.229, dz), (.047, .437, .049), "edge", shadow=True)
    b.box("ChairBack", chair, (0, .370, -.233), (.47, .17, .067), "maple", shadow=True)

    b.node("Rota", ".", position=vec3((-2.19, .853, -1.27)), rotation_degrees=vec3((0, -9, 0)))
    b.box("Binder", "Rota", (0, .012, 0), (.94, .024, .50), "ledger")
    for i, x in enumerate((-.225, .225)):
        b.box(f"Leaf{i}", "Rota", (x, .029, 0), (.43, .017, .469), "paper")
        b.box(f"Column{i}", "Rota", (x-.121, .039, .029), (.009, .002, .347), "rule")
        for row in range(5):
            b.box(f"Row{i}_{row}", "Rota", (x, .039, -.106+.070*row), (.382, .002, .008), "rule")
        for row in range(3 if i == 0 else 2):
            b.box(f"Tick{i}_{row}", "Rota", (x-.161, .041, -.074+.070*row), (.037, .003, .019), "stamp", rot=(0, -14, 0))
    label(b, "Heading", "Rota", (-.18, .040, -.185), "值日  DUTY", .00135, (-90, 0, 0), (74, 61, 65))
    for i, z in enumerate((-.157, .159)):
        b.round(f"Ring{i}", "Rota", (0, .04, z), .017, .022, "steel", sides=10, rot=(90, 0, 0))
    b.round("Pencil", "Rota", (.31, .049, .181), .012, .27, "ochre", sides=6, rot=(0, -28, 90))
    b.node("Carbon", p, position=vec3((-.80,.043,.172)), rotation_degrees=vec3((0,13,0)))
    carbon = p+"/Carbon"
    b.box("Sheet", carbon, (0,.004,0), (.32,.008,.38), "chaff")
    for i in range(5):
        b.box(f"Rule{i}", carbon, (0,.009,-.108+i*.056), (.28,.002,.005), "rule")
    b.box("DateStamp", p, (-.85, .086, -.232), (.138, .086, .103), "stamp")
    b.round("StampKnob", p, (-.85, .144, -.232), .051, .047, "edge")
    b.round("Coaster", p, (.87, .049, .27), .104, .012, "edge")
    b.detail("Cup", p, (.87, .055, .27), vessel(((0,.056), (.01,.069), (.115,.081), (.132,.079),
             (.132,.073), (.018,.060)), 16), "cup", shadow=True)
    b.detail("CupHandle", p, (.87, .054, .285), pipe(((.072,.037), (.117,.052), (.122,.087), (.078,.111)), .010, 8), "cup")
    b.round("LampFoot", p, (.965, .060, -.30), .129, .034, "edge")
    b.detail("LampArm", p, (.965, .074, -.30), pipe(((0,0), (0,.28), (-.11,.42), (-.30,.44)), .018), "edge")
    b.round("LampShade", p, (.665, .492, -.30), .172, .12, "enamel", top=.101, rot=(0,0,-16))
    b.round("LampLens", p, (.649, .429, -.30), .144, .02, "lamp_skin", rot=(0,0,-16))
    b.node("DeskGlow", ".", "OmniLight3D", position=vec3((-1.62, 1.345, -1.65)),
           light_color=srgb((255,211,155)), light_energy=.48, omni_range=2.45)

    mail = solid(b, "MailCabinet", ".", (2.02, .462, -2.62), (2.45,.924,.71), "enamel")
    b.box("CabinetTop", mail, (0,.485,0), (2.51,.048,.77), "maple")
    for i, x in enumerate((-.798, 0, .798)):
        b.box(f"Door{i}", mail, (x, -.021,.361), (.75,.797,.043), "lower")
        b.box(f"LabelSlot{i}", mail, (x,.25,.388), (.22,.074,.020), "steel")
        label(b, f"Label{i}", mail, (x,.25,.402), f"0{i+1}", .00115, ink=(52,58,69))
        b.box(f"Handle{i}", mail, (x,.139,.398), (.158,.030,.041), "edge")
    for i, (x, base_y) in enumerate(((1.44, .971), (2.62, .971))):
        name = f"Tray{i}"
        b.node(name, ".", position=vec3((x, base_y, -2.64)), rotation_degrees=vec3((0, (-5,9)[i], 0)))
        b.box("Base", name, (0,.020,0), (.71,.051,.48), "ochre")
        for j, dx in enumerate((-.344,.344)):
            b.box(f"Side{j}", name, (dx,.069,0), (.024,.071,.48), "edge")
        b.box("Back", name, (0,.068,-.23), (.66,.073,.025), "edge")
        b.box("Ticket", name, (0,.055,.116), (.43,.022,.168), "paper" if not i else "stamp")
        label(b, "Index", name, (0,.069,.116), ("出  OUT", "入  IN")[i], .00128, (-90,0,0),
              (78,62,71) if not i else (233,210,180))
        if not i:
            for j in range(3):
                b.box(f"Slip{j}", name, (-.037+.013*j,.05+.012*j,-.06), (.52,.014,.22), "chaff", rot=(0, j*3, 0))
    # Mount the board to the room, not the fade group for the west wall.
    # The rig's facing ray reaches past the wall while reading this board.
    key = "Keys"
    b.node(key, ".", position=vec3((-OFFICE_WIDTH/2+.122, 1.50, -.25)), rotation_degrees=vec3((0,90,0)))
    b.box("Back", key, (0,0,0), (1.47,.53,.069), "maple", shadow=True)
    b.box("Rail", key, (0,.116,.047), (1.34,.112,.061), "edge")
    for i in range(6):
        x = -.53+.212*i
        b.box(f"Hook{i}", key, (x,.109,.094), (.026,.029,.077), "steel")
        if i != 3:
            b.box(f"Loop{i}", key, (x,.070,.104), (.024,.063,.022), "steel")
            b.box(f"Tag{i}", key, (x,-.013,.091), (.086,.132,.024),
                  "paper" if i != 1 else "ochre", rot=(0,0,(i-3)*3))
            b.box(f"Key{i}", key, (x,-.087,.111), (.032,.117,.019), "steel")
        label(b, f"Slot{i}", key, (x,.213,.044), str(i+1), .00112, ink=(63,58,61))

    # A lockable file pedestal marks the quiet side of the room, outside the
    # routes between the cabinet, reading position and the threshold.
    files = solid(b, "FilePedestal", ".", (3.76,.393,.28), (.55,.786,1.28), "enamel")
    b.box("Cap", files, (0,.412,0), (.58,.05,1.32), "maple")
    for i, z in enumerate((-.31,.31)):
        b.box(f"Door{i}", files, (-.28,-.028,z), (.038,.634,.572), "lower")
        b.box(f"Tag{i}", files, (-.303,.131,z), (.018,.065,.193), "steel")
        b.box(f"Pull{i}", files, (-.322,.031,z), (.048,.035,.128), "edge")
    for i, y in enumerate((.440,.454,.472)):
        b.box(f"Folder{i}", files, (-.045,y,.30-.018*i), (.32,.018,.42), "paper" if i == 1 else "ledger",
              rot=(0,(i-1)*6,0))
    b.box("DoorMat", ".", (OFFICE_DOOR_X,.003,2.37), (1.51,.006,.61), "enamel")
    for i in range(5):
        b.box(f"MatRule{i}", ".", (OFFICE_DOOR_X,.007,2.15+i*.107), (1.41,.002,.013), "edge")

    # A slight turn toward the working area also makes this an explicit facing
    # basis (the player preserves the old yaw on identity teleports).
    add_route(b, "staff_office", (OFFICE_DOOR_X,0,1.67), (OFFICE_DOOR_X,.81,2.61), -12)
    look(b, "RotaLook", "staff_office_rota", (-2.18,.95,-1.04), ("Rota/Leaf0","Rota/Leaf1","Rota/Binder"),
         ("Desk",), 1.31, (.61,.86,8,45,(0,0,-.15)))
    look(b, "TrayLook", "staff_office_trays", (2.03,1.07,-2.355), ("Tray0/Base","Tray1/Base","Tray0/Ticket","Tray1/Ticket"),
         ("MailCabinet",), 1.33, (.69,.86,8,48,(.07,0,-.11)))
    look(b, "KeysLook", "staff_office_keys", (-4.00,1.45,-.25), (key+"/Back",key+"/Rail"),
         ("WallWest0",), 1.29, (.64,.76,22,45,(-.04,0,0)))
    return b.emit()


def wash_station(b):
    x0, x1 = -4.008, -3.03
    y, x = .865, -3.495
    centres = (-1.63, -.12)
    cuts = [(z-.34, z+.34) for z in centres]
    p = "Basins"
    b.node(p, ".")
    for i, (lo, hi) in enumerate(complement(-2.42, .82, cuts)):
        b.box(f"Deck{i}", p, ((x0+x1)/2, y-.026, (lo+hi)/2), (x1-x0,.052,hi-lo), "deck")
    for i, (z, (lo, hi)) in enumerate(zip(centres, cuts)):
        for side, a, c in (("Front", x+.26, x1), ("Back", x0, x-.26)):
            b.box(f"Rail{side}{i}", p, ((a+c)/2, y-.026, z), (c-a,.052,hi-lo), "deck")
        b.detail(f"Bowl{i}", p, (x,y,z), basin(.590,.741,.154,.098), "ceramic", shadow=True)
        b.drain(f"Strainer{i}", p, (x,y-.160,z), .038, "trim" if i == 0 else "steel", "edge")
        b.tap(f"Tap{i}", p, (-3.883,y,z), "steel", "valve", rise=.263, reach=.369)
        # Visible wall brackets and pipes; the dark valves are fittings, not controls.
        b.detail(f"Trap{i}", p, (x,y-.149,z), pipe(((0,0), (0,-.206), (-.039,-.272),
                 (-.104,-.266), (-.142,-.184), (-.515,-.184)), .028), "steel", shadow=True)
        b.round(f"WallCoupling{i}", p, (-3.994,.532,z), .055,.036,"edge", rot=(0,0,90))
    b.box("Splashback", p, (-3.993,1.015,-.80), (.035,.32,3.31), "deck", shadow=True)
    b.box("ApronHighlight", p, (-3.017,.847,-.80), (.029,.039,3.24), "ceramic")
    solid(b, "Apron", p, (-3.073,.752,-.80), (.115,.174,3.24), "trim")
    for i, z in enumerate((-2.33,-.86,.74)):
        b.box(f"Bracket{i}", p, (-3.63,.68,z), (.77,.083,.093), "edge", shadow=True)
        b.box(f"Knee{i}", p, (-3.79,.525,z), (.62,.075,.069), "steel", rot=(0,0,35))
    b.box("SoapDish", p, (-3.62,y+.010,.50), (.21,.020,.225), "edge")
    for i in range(3):
        b.box(f"SoapSlot{i}", p, (-3.62+.052*(i-1),y+.025,.50), (.017,.016,.21), "ceramic")
    b.box("Soap", p, (-3.65,y+.049,.52), (.13,.036,.10), "soap", rot=(0,-13,0))
    b.node("Mirror", "WallWest0", position=vec3((.81,1.66,.12)))
    p = "WallWest0/Mirror"
    b.box("Frame", p, (0,0,0), (3.16,.81,.066), "edge", shadow=True)
    b.box("Silver", p, (0,0,.037), (3.06,.722,.021), "mirror")
    # Painted reflection, in keeping with the other school windows. No live camera.
    for i,(x,w,tone) in enumerate(((-1.01,.77,"mirror_light"), (-.14,.23,"sky_low"), (.88,1.05,"mirror_light"))):
        b.box(f"Light{i}", p, (x,-.048,.050), (w,.49,.005), tone)
    b.box("Frost", p, (0,.289,.050), (3.06,.14,.005), "sky_low")
    b.box("Join", p, (.127,0,.054), (.019,.722,.019), "steel")
    for i, x in enumerate((-1.52,.127,1.52)):
        b.box(f"MirrorClip{i}", p, (x,-.32,.064), (.039,.053,.035), "steel")


def stalls(b):
    p = "Cubicles"
    b.node(p, ".")
    # One open niche. Only the visible partition, seat and closed bay meet the body.
    for name, x in (("Left", -.75), ("Centre", 1.61)):
        q = solid(b, name, p, (x,.944,-1.979), (.093,1.888,1.99), "stall", fade=True)
        b.box("Cap", q, (0,.958,0), (.117,.066,2.05), "edge")
        b.box("Foot", q, (0,-.902,.898), (.164,.084,.167), "steel")
    # No walkable approach behind this leaf. Fading it when the player looks
    # toward the bolt would erase the very thing that the shot is about.
    closed = solid(b, "Closed", p, (2.79,.970,-.986), (2.34,1.94,.12), "stall")
    b.box("Jamb", closed, (-1.09,0,.077), (.13,1.94,.08), "edge")
    b.box("Post", closed, (1.102,0,.077), (.132,1.94,.09), "edge")
    b.box("FittedLeaf", closed, (0,.029,.080), (1.57,1.70,.062), "lower")
    b.box("LatchPlate", closed, (-.55,.118,.13), (.15,.228,.04), "edge")
    b.box("Keeper", closed, (-.762,.118,.13), (.11,.208,.04), "edge")
    b.box("Bolt", closed, (-.665,.085,.135), (.105,.039,.029), "steel")
    b.box("Latch", closed, (-.57,.127,.157), (.136,.044,.050), "steel")
    b.box("Witness", closed, (-.55,.187,.155), (.046,.031,.012), "valve")
    label(b, "Number", closed, (0,.715,.12), "02", .0015, ink=(233,219,193))
    # Glazed pan, with the bowl suspended from its foot and cistern.
    b.node("OpenPan", p, position=vec3((.40,0,-2.52)))
    pan = f"{p}/OpenPan"
    b.detail("Foot", pan, (0,0,.070), Facets().loft([rounded_rect(y,w,d,r) for y,w,d,r in (
        (0,.32,.38,.14), (.043,.34,.41,.15), (.201,.31,.41,.13),
        (.331,.44,.59,.208), (.399,.506,.656,.232), (.423,.506,.656,.234),
    )]), "ceramic", shadow=True)
    b.detail("Bowl", pan, (0,.429,.070), basin(.52,.67,.177,.241,drain=.09), "ceramic", shadow=True)
    # Turn the basin's loft into a seat: raised one-piece lip, sloping inward to the sump.
    # The push plate and inlet sit against the north wall, directly behind the pan.
    b.box("Cistern", pan, (0,.699,-.307), (.44,.335,.388), "ceramic", shadow=True)
    b.box("CisternLid", pan, (0,.880,-.307), (.472,.046,.413), "deck")
    b.round("Button", pan, (0,.908,-.307), .049,.014,"steel")
    b.round("Inlet", pan, (0,.435,-.249), .026,.22,"steel", shadow=True)
    b.round("Sump", pan, (0,.244,.070), .096,.018,"mirror")
    b.shape("PanGuard", b.shell("PanFootprint", pan), (0,.242,-.012), (.52,.48,.81))
    # Door leaf held back along the left screen; actual aisle at the opening stays clear.
    b.box("OpenLeaf", p, (-.661,1.068,-1.76), (.073,1.72,1.46), "lower")
    b.box("OpenPull", p, (-.595,1.136,-1.129), (.086,.056,.190), "steel")
    b.box("PaperHolder", p, (-.646,.813,-1.415), (.153,.129,.181), "edge")
    b.round("Roll", p, (-.554,.765,-1.415), .071,.146,"paper", rot=(90,0,0))


def restroom():
    colors = {"lower": (108, 143, 148), "skirt": (68, 82, 91), "trim": (60, 94, 111),
              "floor_grid": (108, 126, 125), "deck": (181, 191, 177), "tile_gap": (176, 185, 171),
              "ceramic": (217, 222, 203), "steel": (148, 164, 158), "edge": (50, 74, 86),
              "soap": (176, 127, 87), "valve": (145, 87, 65), "stall": (82, 119, 132),
              "paper": (231, 223, 192), "sky": (177, 198, 195), "sky_low": (149, 168, 185),
              "mirror": (89, 119, 139), "mirror_light": (118, 153, 175), "repair": (167, 140, 101)}
    # Along the aisle: a player reading beside the grate should not shade it.
    b = start_room("restroom", colors, (169,195,206), (63,79,98), (240,230,207), sun=.63, sun_yaw=-4)
    painted_field(b, "plaster", ((191,200,191), (164,178,183), (222,214,186)), 1.05, .21)
    painted_field(b, "floor", ((125,146,139), (94,119,124), (147,158,140)), .83, .31)
    walls(b, (WASH_WIDTH,WASH_DEPTH), "restroom", WASH_DOOR_Z, door_on_east=True)
    for name, w in (("WallNorth0", WASH_WIDTH), ("WallWest0", WASH_DEPTH)):
        for i in range(1, 6):
            b.box(f"BedJoint{i}", name, (0,i*.20,.097), (w-.026,.009,.006), "tile_gap")
        for row in range(6):
            x = -w/2+.264+(row%2)*.165
            tile = 0
            while x < w/2-.12:
                b.box(f"HeadJoint{row}_{tile}", name, (x,row*.20+.10,.097), (.009,.20,.006), "tile_gap")
                tile += 1
                x += .66
    window(b, "Clerestory", "WallNorth0", -1.6, 2.24,.101, 2.6,.51)
    window(b, "HighPane", "WallNorth0", 2.11, 2.32,.101, 1.94,.39)
    for i, z in enumerate((-2.49,-1.66,-.83,0,.83,1.66,2.49)):
        b.box(f"TileRow{i}", ".", (0,.002,z), (8.05,.003,.015), "floor_grid")
    for i, x in enumerate((-3.35,-2.51,-1.67,-.83,.01,.85,1.69,2.53,3.37)):
        b.box(f"TileColumn{i}", ".", (x,.002,0), (.015,.003,6.13), "floor_grid")
    b.box("StripWest", ".", (-2.72,.005,0), (.11,.006,6.16), "trim")
    b.box("StripInner", ".", (-2.54,.005,0), (.045,.006,6.16), "repair")
    wash_station(b)
    stalls(b)
    b.node("FloorDrain", ".", position=vec3((-.89,.004,.84)))
    for i, side in enumerate((-1, 1)):
        b.box(f"FrameX{i}", "FloorDrain", (side*.137,.004,0), (.038,.008,.29), "trim")
        b.box(f"FrameZ{i}", "FloorDrain", (0,.004,side*.131), (.236,.008,.028), "trim")
    b.drain("Grate", "FloorDrain", (0,.015,0), .117, "steel", "edge")
    b.box("Patch", "FloorDrain", (-.196,.0036,.168), (.073,.008,.083), "repair")
    # Service riser, mechanical sleeves, and one replaced tile. The rest of the wall is quiet.
    b.round("ServicePipe", "WallWest0", (-2.65,1.17,.203), .044,2.34,"valve", sides=12, shadow=True)
    for i, y in enumerate((.22, .94, 1.87)):
        b.round(f"Sleeve{i}", "WallWest0", (-2.65,y,.203), .056,.077,"steel", sides=12)
        b.box(f"Saddle{i}", "WallWest0", (-2.65,y,.137), (.154,.076,.079), "edge")
    b.box("ReplacedTile", "WallWest0", (-2.19, .706,.101), (.553,.171,.008), "repair")
    b.box("AccessCover", "WallWest0", (-2.11,1.385,.102), (.38,.31,.035), "trim")
    for i, x in enumerate((-2.24,-1.98)):
        b.round(f"Fastener{i}", "WallWest0", (x,1.483,.125), .015,.014,"steel", rot=(90,0,0))
    b.box("LightTray", "WallNorth0", (-1.54,2.575,.392), (1.10,.077,.20), "edge")
    b.box("WashTube", "WallNorth0", (-1.54,2.527,.392), (.972,.033,.13), "ceramic")
    b.node("WashLight", ".", "OmniLight3D", position=vec3((-3.27,2.58,-1.89)),
           light_color=srgb((222,239,253)), light_energy=.52, omni_range=3.7)

    add_route(b, "restroom", (2.73,0,WASH_DOOR_Z), (3.64,.80,WASH_DOOR_Z), 90)
    look(b, "BasinsLook", "restroom_basins", (-2.97,1.02,-.98), ("Basins/Bowl0","Basins/Bowl1","Basins/Tap0Spout","Basins/Tap1Spout",
         "WallWest0/Mirror/MirrorClip1"),
         ("Basins/Apron", "WallWest0"), 1.50, (.66,.91,16,49,(-.30,0,.02)))
    look(b, "LatchLook", "restroom_latch", (2.18,1.09,-.68), ("Cubicles/Closed/LatchPlate","Cubicles/Closed/Latch","Cubicles/Closed/Witness","Cubicles/Closed/Bolt"),
         ("Cubicles/Closed",), 1.23, (.61,.76,-15,45,(0,0,-.05)))
    look(b, "DrainLook", "restroom_drain", (-.89,.15,.84), ("FloorDrain/GrateBridge1","FloorDrain/GrateRing","FloorDrain/FrameX0","FloorDrain/Patch"),
         ("Slab",), 1.12, (.54,.87,4,44,(0,0,-.06)))
    return b.emit()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the generated scenes differ")
    args = parser.parse_args()
    generated = {}
    for role, room_builder in (("staff_office", office), ("restroom", restroom)):
        generated[ROOT / door_path(role).removeprefix("res://")] = door(role)
        generated[ROOT / f"scenes/locations/{role}/{role}.tscn"] = room_builder()
    for path, text in generated.items():
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                parser.exit(1, f"STALE: {path.relative_to(ROOT)}\n")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8", newline="\n")
    print("School office and restroom: four scenes " + ("match the builder." if args.check else "regenerated."))


if __name__ == "__main__":
    main()
