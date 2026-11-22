#!/usr/bin/env python3
"""Fit the six optional school rooms and their shared hall-facing route fragment.

All media are original scene geometry or spatial materials. Nothing under
scenes/dev is referenced by a production room; the experiments are references.
"""
from __future__ import annotations

import argparse
import math
import random

from build_school_rooms import add_route, label, look, solid, start_room, walls
from build_teaching_block import ROOT, child_path, quad, srgb, vec3
from fixture_geometry import Facets, FixtureBuild, rounded_rect
from school_annex_layout import ANNEXES, THRESHOLDS, UNMARKED_ANNEXES
from postmodern_office import POMO, memphis_desk, principal_suite, swivel_chair, vacant_workroom
from registry_archive import index_desk, registry_archive


COMMON = {
    "edge": (43, 45, 51), "trim": (60, 62, 67), "skirt": (68, 60, 66),
    "paper": (238, 220, 173), "rules": (140, 86, 72), "wood": (124, 86, 64),
    "wood_light": (175, 128, 84), "ink": (40, 49, 66), "red": (180, 65, 52),
    "white": (233, 225, 192), "oxide": (166, 113, 68), "teal": (67, 123, 132),
    "ochre": (223, 163, 67), "brass": (203, 167, 97), "navy": (50, 61, 104),
    "cream": (217, 204, 162), "putty": (167, 154, 118), "phosphor": (124, 194, 149),
}
# Dimension, exit axis, and the room's authored pigments. The left/north wall
# is dominant from the real gameplay camera. The floor and props hold the reveal.
PALETTES = {
    "archive": ((8.8, 6.9), 2.86, (199, 171, 126), (105, 71, 62), (162, 126, 88), (73, 51, 68)),
    "plan_room": ((8.8, 6.9), 2.86, (135, 154, 155), (54, 81, 91), (58, 103, 122), (48, 66, 83)),
    "projection_room": ((8.8, 6.9), 2.86, (96, 64, 81), (57, 44, 60), (74, 53, 71), (51, 42, 61)),
    "computer_room": ((10.1, 7.2), 3.45, (139, 137, 153), (76, 80, 100), (92, 100, 111), (50, 48, 67)),
    "vacant_office": ((8.8, 6.9), 2.86, (216, 212, 200), (131, 130, 126), (188, 186, 180), (96, 93, 96)),
    "principal_office": ((9.2, 6.9), 2.86, (124, 89, 101), (61, 48, 76), (68, 63, 94), (54, 46, 69)),
}


def tissue(b, name, stock, ink, press=0):
    shader = b.bind("paper_shader", "res://assets/shaders/school/registration_paper.gdshader", "Shader")
    b.local_mats[name] = f'''[sub_resource type="ShaderMaterial" id="Mat_{name}"]
shader = {shader}
shader_parameter/stock = {srgb(stock)}
shader_parameter/ink = {srgb(ink)}
shader_parameter/press = {press}
'''


def paper(b, name, parent, pos, width, height, material, angle=0.0, *, floor=False, folded=False):
    """A sheet silhouette with a torn leading edge; supported by its authored surface."""
    rng = random.Random(sum(ord(c) for c in name))
    points = [(-.5, -.47), (-.28, -.49), (-.07, -.465), (.12, -.50),
              (.34, -.455), (.5, -.482), (.49, .51), (-.47, .489)]
    a = math.radians(angle)
    rim = []
    for i, (u, v) in enumerate(points):
        x = u*width*math.cos(a) - v*height*math.sin(a)
        y = u*width*math.sin(a) + v*height*math.cos(a)
        z = rng.uniform(-.024, .094) if folded else 0.0
        rim.append((x,z,y) if floor else (x,y,z))
    centre = (0,.045,0) if floor and folded else (0,0,.045 if folded else 0)
    mesh = Facets()
    for i in range(len(rim)):
        # Two-sided paper shading also handles a curled edge back toward the wall.
        a, d = rim[i], rim[(i+1) % len(rim)]
        mesh.face(centre, a, d) if floor else mesh.face(centre, d, a)
    b.detail(name, parent, pos, mesh, material, shadow=folded)


def flat_mark(b, name, points, material, height=.011):
    mesh = Facets()
    signed_area = sum(x*bz-bx*z for (x,z),(bx,bz) in zip(points, points[1:]+points[:1]))
    ring = points if signed_area > 0 else points[::-1]
    mesh.face(*[(x, height, z) for x,z in ring])
    b.detail(name, "FloorComposition", (0,0,0), mesh, material)


def table(b, name, pos, width, depth, *, top="wood_light", legs="trim", tall=.79):
    group = b.shell(name, ".", pos)
    b.box("Top", group, (0,tall-.038,0), (width,.076,depth), top, shadow=True)
    b.box("Apron", group, (0,tall-.134,-depth*.34), (width-.12,.135,.08), legs)
    b.shape("Body", group, (0,tall/2,0), (width,tall,depth))
    for i, (x,z) in enumerate(((-1,-1), (-1,1), (1,-1),(1,1))):
        b.box(f"Foot{i}", group, (x*(width/2-.11),(tall-.07)/2,z*(depth/2-.095)),
              (.062,tall-.07,.062), legs, shadow=True)
    return group


def chair(b, name, pos, yaw=0, ink="wood_light", *, playable=False):
    # The sit animation expects local -Z forward. Mirror the existing chair
    # around its seat rather than rotating the animation or sharing classroom art.
    axis = -1 if playable else 1
    if playable:
        slide = b.bind("chair_slide", "res://scripts/environment/pushable_chair.gd", "Script")
        b.node(name, ".", position=vec3(pos), script=slide)
        q = name
        body = b.shell("Solid", q, layer=0)
        b.node("SeatMark", q, "Marker3D")
    else:
        q = b.shell(name, ".", pos, (0,yaw,0))
        body = q
    b.shape("SeatStop", body, (0,.37,0), (.47,.72,.50))
    b.box("Seat", q, (0,.431,0), (.449,.073,.455), ink, shadow=True)
    b.box("Back", q, (0,.763,-.21*axis), (.442,.227,.071), ink, rot=(-7*axis,0,0), shadow=True)
    for i,(x,z) in enumerate(((-.179,.162),(.179,.162),(-.18,-.197),(.18,-.197))):
        h = .797 if z<0 else .421
        b.box(f"Stile{i}", q, (x,h/2,z*axis), (.040,h,.044), "edge", shadow=True)
    return q


def cabinet(b, name, pos, w, h, drawers=5, material="wood"):
    q = solid(b, name, ".", (pos[0],h/2,pos[1]), (w,h,.55), material)
    for i in range(drawers):
        ht = (h-.16)/drawers
        y = -h/2+.09+(i+.5)*ht
        b.box(f"Front{i}", q, (0,y,.294), (w-.076,ht-.029,.033), "wood_light")
        b.box(f"Pull{i}", q, (0,y-.019,.322), (.162,.031,.041), "edge")
        b.box(f"Card{i}", q, (-w*.26,y+.034,.316), (.16,.087,.006), "paper")
        b.box(f"Rule{i}", q, (-w*.27,y+.013,.323), (.099,.014,.009), "rules")
    return q


def emblem(b, name, centre, size, pigment="red"):
    x,y,z = centre
    w,h = size
    for i,(px, py, a,d) in enumerate(((x-w/2,y,.038,h),(x+w/2,y,.038,h),
                                        (x,y-h/2,w,.039),(x,y+h/2,w,.039))):
        b.box(f"{name}{i}", "PaperAssembly", (px,py,z), (a,d,.018), pigment)


def read(b, id, node, pos, shape, shot=None):
    look(b, "Observe", id + "_detail", pos, tuple(f"{node}/{n}" for n in shape), (node,),
         1.34, shot or (.58,.91,13,47,(0,0,0)))


def archive(b):
    # Index and carbon copy pull in different directions, even on the floor.
    for i in range(4):
        cabinet(b, f"MapCase{i}", (-3.66+.98*i,-2.99), .91, 1.68+(i%2)*.28, 6, "wood")
    for i, (x,y,w,d,angle,tone) in enumerate(((-.65,1.88,3.27,1.74,-8,"ledger"),
                            (1.27,1.96,3.31,1.56,4,"paper"),(2.62,1.38,1.74,1.64,-13,"cream"),
                            (1.50,2.10,2.64,1.04,11,"ruled"),(2.83,2.21,1.61,.67,3,"ledger"))):
        paper(b, f"ArchivePrint{i}", "PaperAssembly", (x,y,-3.327+i*.021), w,d,tone,angle,folded=True)
    emblem(b, "RegisterSquare", (1.97,1.83,-3.107), (1.29,.91))
    for i in range(6):
        b.box(f"Rule{i}", "FloorComposition", (-2.74+i*.70,.011,-.43+i*.20),
              (.095,.018,4.38-i*.29), "paper" if i%2 else "rules", rot=(0,-13,0))
    p = table(b, "IndexDesk", (1.22,0,-1.63), 2.27,.92)
    b.box("Ledger", p, (-.19,.83,.06), (.81,.096,.56), "navy", rot=(0,9,0), shadow=True)
    paper(b, "LedgerPage", p, (-.18,.883,.062), .75,.48,"ledger",10,floor=True)
    for i,(x,z,t) in enumerate(((.53,.17,"red"),(.75,-.18,"ink"),(.40,-.08,"cream"))):
        b.box(f"IndexSlip{i}", p, (x,.806,z), (.28,.018,.23),t,rot=(0,10-i*9,0))
    index_desk(b, p)
    chair(b, "ClerkSeat", (2.46,0,-2.49), 172)
    read(b,"archive",p,(1.04,.82,-1.46),("Ledger",))
    # Round 2 (2026-11-20, revised 11-21): student files, school rules and inspection dossiers.
    registry_archive(b)


def plan_room(b):
    # The same two registration marks become two sizes of the same ruled plan.
    for i, (x,z) in enumerate(((-3.82,-1.20),(-3.54,-2.82),(3.68,-2.71))):
        p=cabinet(b, "PlanFile"+str(i), (x,z), .81, 1.13+.27*i, 4, "navy")
        for k in range(2):
            b.round(f"Roll{k}",p, (-.13+.23*k,.64+.12*i,.08), .077,.64,"paper",rot=(81,13,-8),sides=10)
    for i,(x,y,w,d,a,t) in enumerate(((-1.04,1.56,4.20,1.75,5,"cyanotype"),
                        (.31,1.66,3.16,1.10,-8,"paper"),(2.35,2.00,2.94,1.66,-3,"cyanotype"),
                        (1.91,1.88,1.47,.80,-9,"ruled"))):
        paper(b,f"PlanSection{i}","PaperAssembly",(x,y,-3.31+i*.021),w,d,t,a,folded=True)
    for i in range(3):
        b.box(f"SurveyLong{i}","FloorComposition",(-1.65+i*1.62,.010,-.48-i*.23),(.053,.015,5.26),
              "white",rot=(0,-11-i*5,0))
        b.box(f"SurveyReturn{i}","FloorComposition",(-.69+i*.49,.014,1.89-i*.451),(2.13,.016,.059),"ochre",rot=(0,6+i*5,0))
    p=table(b,"TracingTable",(.30,0,-1.49),2.66,1.33,top="ink",tall=.88)
    b.box("Layout",p,(.05,.902,.033),(2.38,.043,1.03),"cyanotype",shadow=True)
    paper(b,"TracingOverlay",p,(.32,.932,.048),1.51,.76,"ruled",8,floor=True)
    b.box("ParallelRule",p,(.11,.959,.262),(1.73,.026,.111),"brass",rot=(0,-8,0))
    read(b,"plan_room",p,(.42,.89,-.89),("Layout","ParallelRule"),(.62,1.01,5,51,(0,0,-.04)))


def projection_room(b):
    # The light has a carrier, a surface and a weaker repeat. They neither light
    # the whole room nor disappear when the player walks across the paper beam.
    film = b.bind("film", "res://assets/shaders/school/after_image.gdshader", "Shader")
    for name, phase, fade in (("exposure", 0.0, 1.0), ("ghost", -1.35, .63)):
        b.local_mats[name] = f'''[sub_resource type="ShaderMaterial" id="Mat_{name}"]
shader = {film}
shader_parameter/phase_offset = {phase}
shader_parameter/fade = {fade}
'''
    b.pigments.update({"velvet": (71, 42, 58), "spill": (180, 114, 80), "sprocket": (222, 169, 102)})
    for i, x in enumerate((-3.65,-3.32,-2.93,3.69,4.02)):
        b.box(f"Baffle{i}", "PaperAssembly", (x,1.41,-3.276+i*.016), (.31,2.56,.15), "velvet",
              rot=(0, 0, -2 if i < 3 else 2), shadow=True)
    b.box("ScreenBacking", "PaperAssembly", (.42,1.44,-3.237), (5.91,2.48,.081), "ink", shadow=True)
    b.flat("FilmLoop", "PaperAssembly", quad(b, 5.72, 2.29), "exposure", (.42,1.44,-3.184))
    b.box("ScreenRoller", "PaperAssembly", (.42,2.687,-3.184), (6.06,.11,.126), "ink", shadow=True)
    b.box("LowerRod", "PaperAssembly", (.42,.245,-3.17), (5.8,.045,.073), "ink", rot=(0,0,1))
    b.flat("DelayedPrint", "PaperAssembly", quad(b, 2.19, 1.08), "ghost", (-4.262,1.64,-1.66), (0,90,-9))
    flat_mark(b,"Spill",[(-2.77,-3.08),(3.37,-3.08),(1.46,1.30),(.28,1.18)],"spill")
    flat_mark(b,"SpillShadow",[(.47,-3.04),(1.25,-3.04),(1.10,1.18),(.68,1.18)],"ink",.016)
    for i in range(7):
        b.box(f"Sprocket{i}", "FloorComposition", (-2.60+i*.36,.018,-2.86+i*.51),(.20-i*.013,.012,.16),
              "sprocket", rot=(0,-33,0))
    p=table(b,"ProjectionCart",(.94,0,.16),1.68,.84,top="navy")
    b.box("Projector",p,(-.17,.946,-.028),(.69,.316,.52),"cream",rot=(0,9,0),shadow=True)
    b.round("Housing",p,(-.15,1.00,-.31),.109,.16,"ink",rot=(90,0,0),sides=12)
    b.round("Glass",p,(-.15,1.00,-.401),.066,.035,"phosphor",rot=(90,0,0),sides=12)
    for i in range(4):
        b.box(f"Vent{i}",p,(-.35+i*.111,1.107,.039),(.028,.008,.24),"putty",rot=(0,9,0))
    for i in range(3):
        paper(b,f"Acetate{i}",p,(.46,.794+i*.006,.15),.43,.32,"ruled",8-i*10,floor=True)
    cabinet(b,"ApertureCabinet",(-3.63,-2.95),1.06,1.13,3,"navy")
    for i, (x,z,yaw) in enumerate(((-1.74,1.47,167), (-2.72,.98,151), (-2.02,-.36,214))):
        chair(b,f"ViewingSeat{i}",(x,0,z),yaw,"velvet")
    read(b,"projection_room",p,(.85,.91,.48),("Projector","Housing","Glass"),(.55,.80,16,44,(0,0,-.10)))


def phosphor(b, channel):
    name = f"phosphor{channel}"
    if name not in b.local_mats:
        shader = b.bind("crt_shader", "res://assets/shaders/school/crt_register.gdshader", "Shader")
        b.local_mats[name] = f'''[sub_resource type="ShaderMaterial" id="Mat_{name}"]
shader = {shader}
shader_parameter/phosphor = {srgb((178,221,146) if channel==2 else (98,227,179))}
shader_parameter/channel = {float(channel)}
'''
    return name


TERMINAL_PATH = "res://scenes/environment/props/computer_terminal.tscn"


def terminal_scene():
    # Six instances share the cabinet geometry; their screens keep independent
    # channels. Keyboard/Bezel remain addressable by the existing inspection.
    b = FixtureBuild("Terminal", COMMON)
    q = "."
    b.box("SwivelBase",q,(0,.032,0),(.63,.066,.49),"putty",shadow=True)
    b.box("Foot",q,(0,.091,0),(.43,.10,.34),"cream")
    # CRT tapers behind its glass. Cross-sections run down the depth axis.
    rings = [[(x, y+.454, z) for x,z,y in reversed(rounded_rect(depth, w, h, r))] for depth,w,h,r in (
        (-.481,.424,.398,.059),(-.385,.561,.479,.068),(-.122,.772,.591,.078),
        (.277,.789,.621,.080),(.354,.741,.571,.064),
    )]
    mesh = Facets().loft(rings)
    # The bevel and front plane are intentional, separate from the screen window.
    mesh.face(*reversed(rings[0]))
    mesh.face(*rings[-1])
    b.detail("TubeHousing",q,(0,0,0),mesh,"cream",shadow=True)
    b.box("Bezel",q,(0,.457,.367),(.684,.482,.046),"putty",shadow=True)
    b.box("InnerBead",q,(0,.472,.392),(.602,.413,.028),"edge")
    b.box("Power",q,(.307,.212,.389),(.037,.036,.018),"phosphor")
    for i in range(4):
        b.box(f"TubeVent{i}",q,(.038+i*.081,.737,-.033),(.028,.011,.19),"edge")
    b.box("Keyboard",q,(-.030,.027,.54),(.66,.056,.239),"putty",rot=(6,0,0),shadow=True)
    for i in range(4):
        b.box(f"Keys{i}",q,(-.055,.062,.45+i*.041),(.493,.018,.024),"paper")
    b.box("Space",q,(-.091,.057,.622),(.258,.016,.025),"cream")
    b.box("Mouse",q,(.427,.034,.493),(.092,.065,.15),"cream",shadow=True)
    b.box("MouseSplit",q,(.427,.069,.493),(.011,.011,.084),"edge")
    b.box("Tower",q,(.555,.352,-.145),(.217,.691,.511),"cream",shadow=True)
    b.box("CD",q,(.555,.592,.117),(.187,.067,.023),"putty")
    b.box("Floppy",q,(.555,.467,.122),(.165,.034,.020),"edge")
    b.box("TowerPower",q,(.523,.271,.122),(.058,.069,.018),"putty")
    for i in range(3):
        b.box(f"Intake{i}",q,(.557,.149+i*.031,.126),(.154,.014,.022),"edge")

    return b.emit()


def terminal(b, p, slot, x, channel):
    scene = b.bind("terminal", TERMINAL_PATH, "PackedScene")
    b.nodes.append(f'[node name="{slot}" parent="{p}" instance={scene}]\n'
                   f'position = {vec3((x,.785,-.098))}\n')
    b.flat("Raster", child_path(p, slot), quad(b,.562,.378), phosphor(b,channel), (0,.475,.410))


def computer_room_atmosphere(b):
    """A quiet retro-computer landscape on the west wall, not a new destination.

    The existing raster and copper trace remain the room's inspection. These
    shallow, collision-free shapes sit on the wall, above the workstations and
    clear of the doorway; the old machines stay the focus at desk height.
    """
    b.pigments.update({
        "lab_dusk": (80, 71, 102), "lab_horizon": (154, 112, 139),
        "lab_sunset": (229, 174, 151), "lab_grid": (159, 155, 178),
        "lab_frame": (78, 85, 101), "lab_mint": (152, 190, 177),
    })
    b.node("DuskMural", ".")
    p = "DuskMural"
    # A distant screen-landscape with physical depth, not an extra screen UI.
    # The west wall's interior face is at x=-4.955.
    b.box("Frame", p, (-4.92, 1.99, .50), (.045, 1.38, 3.35), "lab_frame")
    b.box("Sky", p, (-4.89, 2.00, .50), (.018, 1.24, 3.20), "lab_dusk")
    b.box("Horizon", p, (-4.875, 1.77, .50), (.012, .32, 3.20), "lab_horizon")
    b.round("Sun", p, (-4.86, 2.15, .50), .31, .018, "lab_sunset", sides=32, rot=(0, 0, 90))
    # Printed rows clip the lower sun and recede into a grid towards the horizon.
    for i, y in enumerate((1.88, 1.96, 2.04)):
        b.box(f"SunCut{i}", p, (-4.844, y, .50), (.012, .025, .66), "lab_dusk")
    for i, y in enumerate((1.45, 1.51, 1.60, 1.70)):
        b.box(f"GridRow{i}", p, (-4.84, y, .50), (.012, .012, 3.15), "lab_grid")
    for i, z in enumerate((-.9, -.2, .5, 1.2, 1.9)):
        end = .5 + (z - .5) * .18
        dz, dy = end - z, .29
        length = math.hypot(dz, dy)
        angle = -math.degrees(math.atan2(dy, dz))
        b.box(f"GridRay{i}", p, (-4.83, 1.595, (z + end) / 2),
              (.012, .011, length), "lab_grid", rot=(angle, 0, 0))
    # Small colour bars sit on the opposite end of the wall, like faded teaching
    # aids, leaving negative space between them and the workstations.
    for i, tone in enumerate(("lab_mint", "lab_sunset", "lab_horizon", "lab_dusk")):
        b.box(f"TestBar{i}", p, (-4.91, 2.29, 2.70 + i*.18), (.035, .31, .13), tone)
    b.node("DuskBounce", p, "OmniLight3D", position=vec3((-4.45, 2.12, .50)),
           light_color=srgb((208, 150, 178)), light_energy=.22, omni_range=3.8)


def computer_room(b):
    computer_room_atmosphere(b)
    for i,(x,z,w) in enumerate(((-2.65,-2.51,3.62),(2.65,-2.51,3.62),(-2.65,.48,3.62))):
        p=table(b,f"Station{i}",(x,0,z),w,1.38,top="wood_light")
        terminal(b,p,"Left",-.87,i%3)
        terminal(b,p,"Right",.87,(i+1)%3)
        chair(b,f"StationChair{i}",(x+.88,0,z+1.18),180,"putty",playable=i==1)
    b.box("PatchPanel", "PaperAssembly", (2.17,1.20,-3.457), (2.59,.705,.17),"ink")
    for i in range(6):
        b.box(f"Jack{i}", "PaperAssembly", (1.16+i*.38,1.13,-3.35),(.099,.088,.044),"putty")
    # The same CRT material is registered one row late at classroom scale.
    # Black rows and copper floor conduits make a circuit without new colliders.
    b.pigments.update({"trace": (112, 152, 127), "solder": (184, 141, 100)})
    b.box("RasterHousing", "PaperAssembly", (-1.54,1.73,-3.424), (5.49,1.82,.18), "ink", shadow=True)
    b.flat("DeferredRaster", "PaperAssembly", quad(b, 5.22,1.60), phosphor(b, 3), (-1.53,1.73,-3.324))
    b.box("LostRow", "PaperAssembly", (-1.16,2.09,-3.311), (5.63,.084,.018), "edge")
    b.box("UpperRail", "PaperAssembly", (1.79,2.697,-3.319), (5.11,.09,.082), "trace")
    for i in range(5):
        x, z = -1.24 + i*.45, -.52 + i*.56
        b.box(f"ScanStep{i}","FloorComposition",(x+1.47,.011,z),(4.47,.013,.067), "trace")
        b.box(f"Offset{i}","FloorComposition",(x+3.725,.011,z+.267),(.041,.013,.597), "solder")
    # The outline follows CRT glass and housing, supported by the station top.
    p = "Station1"
    read(b,"computer_room",p,(1.89,1.18,-1.87),("Left/Bezel","Left/Raster","Left/Keyboard"),
         (.61,1.00,0,44,(0,0,-.09)))

    station_hotspots(b)


def station_hotspots(b):
    hotspot = b.bind("station_hotspot", "res://scenes/locations/computer_room/terminal_hotspot.gd", "Script")
    control = b.bind("station_control", "res://scenes/locations/computer_room/computer_station.gd", "Script")
    shot = b.bind("camera_shot", "res://scripts/world/camera_shot.gd", "Script")
    b.subs.append(f'''[sub_resource type="Resource" id="Shot_Power"]
script = {shot}
look_offset = Vector3(-0.32, 0, 0.23)
subject_mix = 0.65
distance_scale = 0.56
height_scale = 0.92
yaw_degrees = -16.0
fov = 44.0
glide_seconds = 0.42
''')
    specs = (
        ("TerminalSeat", "terminal_seat", "prompt.sit", (3.53,.58,-1.33), 0.42,
         "StationChair1", ("StationChair1/Seat", "StationChair1/Back")),
        ("TerminalPower", "terminal_power", "prompt.terminal_power", (4.043,1.056,-2.486), .44,
         "Station1", ("Station1/Right/TowerPower", "Station1/Right/Bezel")),
    )
    for name, id, key, pos, radius, support, parts in specs:
        outline = ", ".join(f'"../../{part}"' for part in parts)
        extra = 'requires_sitter = true\ncamera_shot = SubResource("Shot_Power")\n' if id == "terminal_power" else ""
        b.nodes.append(f'''[node name="{name}" parent="Interactables" instance=ExtResource("tap_target")]
script = {hotspot}
position = {vec3(pos)}
interact_id = &"{id}"
prompt_key = "{key}"
radius = {radius}
outline_paths = PackedStringArray({outline})
support_paths = PackedStringArray("../../{support}")
{extra}''')
    b.node("BootGlow", "Station1/Right", "OmniLight3D", position=vec3((0,.46,.52)),
           light_color=srgb((144,225,196)), light_energy=.34, omni_range=1.7, visible="false")
    b.node("StationControl", ".", "Node", script=control)


def vacant_office(b):
    # A single occupied footprint on a graphite proof at room scale. Keep
    # the spot under the player's feet flat, including the folded corner.
    b.pigments.update({**POMO, "pomo_pink": (187,109,98), "pomo_mint": (156,155,144),
                       "pomo_lilac": (147,143,160), "pomo_cobalt": (64,77,123),
                       "pomo_lemon": (186,173,144), "carbon_stock": (194,188,180)})
    p=memphis_desk(b,"EmptyDesk",(.89,0,-1.71),2.47,1.15,seed=1,
                   colours=("pomo_black", "pomo_lilac", "pomo_white"))
    b.box("Blotter",p,(.19,.814,.02),(1.12,.046,.68),"hatching",shadow=True)
    paper(b,"Carbon",p,(.10,.846,.056),.93,.59,"ruled",-8,floor=True)
    b.box("Ruler",p,(.42,.856,.225),(.621,.024,.067),"red",rot=(0,17,0))
    swivel_chair(b,".","VacantChair",(.48,0,-2.87),197,seat="pomo_pink",crest="disc",collider=True)
    swivel_chair(b,".","VisitorSeat",(-2.31,0,-1.21),28,seat="pomo_mint",back="pomo_cobalt",accent="pomo_pink",
                 crest="arch",arms=False,collider=True)
    cabinet(b,"EmptyPigeonhole",(-3.2,-2.96),1.24,1.12,3,"trim")
    b.box("PaperBed", "PaperAssembly",(-.29,1.35,-3.312),(7.94,2.66,.038),"carbon_stock")
    for i, (x,y,w,h,a,tone) in enumerate(((-1.79,1.56,3.18,2.37,-3,"hatching"),
            (.16,1.34,4.00,2.26,1,"paper"), (1.85,1.84,2.94,1.23,-6,"hatching"))):
        paper(b,f"CarbonPull{i}","PaperAssembly",(x,y,-3.285+i*.022),w,h,tone,a)
    # The print crosses a crease and puts the furniture's marks somewhere the
    # furniture isn't. The real desk is kept right of this false plan.
    flat_mark(b,"FoldedProof",[(-4.22,-3.28),(.35,-3.28),(-.45,2.72),(-3.99,2.93)],"hatching")
    flat_mark(b,"SkippedPrint",[(-2.12,-3.29),(.66,-3.29),(.29,-.68),(-2.29,-.88)],"carbon_stock",.014)
    for i, (x,z,w,d) in enumerate(((-2.72,-1.07,2.43,.076),(-3.93,-.27,.075,1.65),
                                   (-2.44,-.83,2.43,.061),(-3.63,.03,.06,1.64))):
        b.box(f"DeskImprint{i}", "FloorComposition", (x,.018,z), (w,.014,d), "ink" if i < 2 else "red")
    emblem(b,"MissingCorner",(1.32,1.52,-3.217),(2.58,1.25))
    read(b,"vacant_office",p,(1.04,.816,-1.34),("Blotter","Ruler"))
    vacant_workroom(b)


def principal_office(b):
    # An apparently straight axis ends at the *side* of the desk. The enormous
    # window cross is painted into the yellow/blue division, like #196's shadows.
    flat_mark(b,"AmberField",[(-4.17,-3.30),(.47,-3.30),(3.2,3.21),(-2.43,3.21)],"ochre")
    flat_mark(b,"Perpendicular",[(-4.4,.19),(-4.4,.63),(3.52,-1.22),(3.52,-1.72)],"ink",.020)
    flat_mark(b,"FalseCross",[(1.09,3.29),(1.60,3.29),(-1.67,-3.28),(-2.16,-3.28)],"ink",.023)
    flat_mark(b,"PetrolField",[(1.7,3.25),(4.44,3.25),(4.44,-3.29),(.80,-3.29)],"teal",.014)
    # Two false frames on the existing wall: both point down separate axes,
    # neither one is an opening. The room behind the chair never gets deeper.
    b.pigments.update({**POMO, "pomo_pink": (125,66,86), "pomo_white": (200,173,121),
                       "pomo_lemon": (215,170,89), "pomo_cobalt": (53,61,100),
                       "pomo_lilac": (120,99,133), "pomo_mint": (79,111,113)})
    b.box("PaintedRecess", "PaperAssembly", (.21,1.35,-3.312), (8.37,2.64,.10), "ink")
    for i, (x,y,w,h,tone) in enumerate(((-1.09,1.47,5.65,2.27,"rules"),
                                         (-.94,1.34,4.98,2.01,"navy"),
                                         (-.46,1.45,3.92,2.22,"ochre"),
                                         (-.18,1.32,3.28,1.96,"ink"),
                                         (.82,1.54,2.04,1.67,"teal"))):
        b.box(f"CourtDepth{i}", "PaperAssembly", (x,y,-3.25+.025*i), (w,h,.020), tone)
    b.box("PaintedAxis", "PaperAssembly", (.74,1.35,-3.119), (.037,1.97,.020), "brass")
    b.box("BrokenPedimentLeft", "PaperAssembly", (-1.54,2.582,-3.131), (2.76,.103,.066), "brass", rot=(0,0,4))
    b.box("BrokenPedimentRight", "PaperAssembly", (1.82,2.482,-3.111), (2.94,.122,.072), "brass", rot=(0,0,-5))
    p=memphis_desk(b,"HeadDesk",(1.62,0,-1.91),2.83,1.15,tall=.84,seed=2,classical=True,
                   colours=("pomo_cobalt","pomo_pink","pomo_white"))
    b.box("Front",p,(0,.37,-.302),(2.71,.63,.17),"ink",shadow=True)
    b.box("Blotter",p,(-.24,.867,.031),(.99,.045,.68),"navy",shadow=True)
    paper(b,"UnstampedForm",p,(-.25,.895,.026),.68,.47,"ledger",-8,floor=True)
    b.box("Stamp",p,(.45,.933,.041),(.14,.131,.143),"red",rot=(0,24,0),shadow=True)
    swivel_chair(b,".","ChairOfOffice",(1.78,0,-2.95),0,seat="red",back="navy",accent="pomo_lemon",
                 crest="throne",collider=True)
    for i in range(4):
        swivel_chair(b,".",f"WaitingSeat{i}",(-3.26+i*.87,0,.91+i*.15),147-i*8,seat="navy",
                     back="pomo_black",accent="pomo_lemon",
                     crest=("disc","triangle","arch","disc")[i],arms=i%2==0,collider=True)
    cabinet(b,"SideCase",(3.67,-2.97),.91,1.12,3,"navy")
    read(b,"principal_office",p,(1.48,.86,-1.41),("Blotter","Stamp"))
    principal_suite(b)


ROOM_CONTENT = {f.__name__: f for f in (archive, plan_room, projection_room, computer_room, vacant_office, principal_office)}


def room(r):
    dims, door_x, plaster, lower, floor, backdrop = PALETTES[r.id]
    # Lighting follows the room's medium rather than the floor where the door
    # happens to be. The global camera and renderer don't change on arrival.
    ambient, key, strength, yaw = {
        "projection_room": ((182,160,191),(254,176,137),.49,18),
        "computer_room": ((180,173,197),(220,221,226),.60,18),
        "vacant_office": ((203,196,202),(247,235,215),.70,-40),
        "principal_office": ((177,160,191),(255,208,145),.89,-40),
    }.get(r.id, ((200,188,189),(255,220,169),.84,-40))
    b = start_room(r.id,{**COMMON,"lower":lower},ambient,backdrop,key,sun=strength,sun_yaw=yaw)
    tissue(b,"plaster",plaster,lower,3 if r.id=="vacant_office" else 0)
    tissue(b,"floor",floor,lower,2 if r.id in ("plan_room","computer_room") else (3 if r.id=="vacant_office" else 0))
    tissue(b,"ledger",(224,204,161),(112,78,71),1)
    tissue(b,"ruled",(233,221,191),(103,126,125),1)
    tissue(b,"cyanotype",(67,113,137),(168,208,204),2)
    tissue(b,"hatching",(210,202,184),(61,59,69),3)
    # These four paper stocks are two-sided in front of the walls. A shallow
    # strip rather than a ceiling permits the current camera to read them.
    walls(b,dims,r.id,door_x)
    b.node("PaperAssembly", ".")
    b.node("FloorComposition", ".")
    if r.id not in UNMARKED_ANNEXES:
        label(b,"RoomSign","WallNorth0",(dims[0]*.16,2.662,.134),r.english, .00237,ink=(232,215,172))
    b.box("SwitchPlate", ".", (door_x-1.14,1.15,dims[1]/2-.129),(.12,.22,.02), "trim")
    b.node("WorkLamp", ".", "OmniLight3D", position=vec3((-2.83,2.55,-1.92)),
           light_color=srgb(key if r.id in UNMARKED_ANNEXES else (255,229,179)),
           light_energy=.25 if r.id == "projection_room" else .46, omni_range=4.2)
    add_route(b,r.id,(door_x,0,dims[1]/2-1.27),(door_x,.84,dims[1]/2-.40),12)
    ROOM_CONTENT[r.id](b)
    return b.emit()


def corridor_exits():
    for r in THRESHOLDS:
        support = f"../../TeachingBlock/{r.parent}/{r.name}Portal/Door/Panel"
        mark = f"../../TeachingBlock/{r.parent}/{r.name}Portal"
        extra = f'required_flag = &"annex.{r.id}.aligned"\nblocked_inspection_id = &"{r.id}_threshold"\n' if r.gated else ""
        # Adjacent controls need separate pick zones. A full-leaf pick box or
        # broad anchor sphere would catch a mouse click aimed at the slide.
        door_point = r.point(.53, 1.10, .45) if r.gated else r.point(0, .83, .51)
        door_shape = ("HallLever", "HallSign") if r.gated else ("Leaf", "HallLever", "HallSign")
        outline = ", ".join(f'"{support}/{part}"' for part in door_shape)
        prompt = "door_try" if r.id in UNMARKED_ANNEXES else f"enter_{r.id}" if r.gated else "enter_restroom"
        yield f'''[node name="{r.name}Door" parent="Interactables" instance=ExtResource("12_location_exit")]
position = {vec3(door_point)}
interact_id = &"to_{r.id}"
outline_paths = PackedStringArray({outline})
support_paths = PackedStringArray("{support}")
prompt_key = "prompt.{prompt}"
radius = {.36 if r.gated else 1.38}
{extra}destination_scene = "res://scenes/locations/{r.id}/{r.id}.tscn"
destination_spawn = &"FromCorridor"
destination_id = &"{r.id}"
'''
        if r.gated:
            yield f'''[node name="{r.name}Alignment" parent="Interactables" instance=ExtResource("11_interactable")]
position = {vec3(r.point(-.64, 1.14, .40))}
interact_id = &"align_{r.id}"
conversation_route = &"align_{r.id}"
prompt_key = "prompt.annex_align"
outline_paths = PackedStringArray("{mark}/RegistrationSlide", "{mark}/SlideGrip")
support_paths = PackedStringArray("{support}")
camera_shot = ExtResource("29_annex_shot")
radius = 0.34
'''


def corridor_spawns():
    for r in THRESHOLDS:
        yield f'''[node name="From{r.name}" type="Marker3D" parent="SpawnPoints" groups=["spawn_point"]]
position = {vec3(r.point(0, 0, 1.45))}
rotation_degrees = {vec3((0,(r.yaw+180)%360,0))}
'''


def _replace_fragment(text, key, anchor, body):
    start, end = f"; BEGIN GENERATED {key}\n", f"; END GENERATED {key}\n\n"
    if start in text:
        i = text.index(start)
        j = text.index(end, i) + len(end)
    else:
        i = j = text.index(anchor)
    return text[:i]+start+"\n".join(body)+"\n"+end+text[j:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the generated layout differs")
    args = parser.parse_args()
    corridor = ROOT / "scenes/locations/corridor/corridor.tscn"
    text = _replace_fragment(corridor.read_text(), "annex exits", '[node name="SpawnPoints"', corridor_exits())
    text = _replace_fragment(text, "annex returns", '[node name="Ambience"', corridor_spawns())
    targets = {corridor: text, **{ROOT/f"scenes/locations/{r.id}/{r.id}.tscn": room(r) for r in ANNEXES}}
    targets[ROOT / TERMINAL_PATH.removeprefix("res://")] = terminal_scene()
    for path, text in targets.items():
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                parser.exit(1, f"STALE: {path.relative_to(ROOT)}\n")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8", newline="\n")
    print("School annex rooms and corridor thresholds " + ("match the builders." if args.check else "generated."))


if __name__ == "__main__":
    main()
