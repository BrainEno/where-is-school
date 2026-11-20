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
from fixture_geometry import Facets, rounded_rect
from school_annex_layout import ANNEXES, THRESHOLDS
from postmodern_office import POMO, kettle, memphis_desk, principal_suite, swivel_chair, vacant_workroom
from trial_archive import index_desk, trial_archive


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
    "projection_room": ((8.8, 6.9), 2.86, (146, 132, 162), (71, 57, 84), (97, 79, 99), (66, 55, 80)),
    "computer_room": ((10.1, 7.2), 3.45, (155, 164, 140), (72, 99, 91), (76, 92, 84), (48, 66, 63)),
    "vacant_office": ((8.8, 6.9), 2.86, (197, 189, 165), (111, 108, 99), (193, 184, 158), (76, 70, 85)),
    "principal_office": ((9.2, 6.9), 2.86, (130, 105, 135), (61, 52, 89), (69, 88, 122), (55, 44, 73)),
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


def chair(b, name, pos, yaw=0, ink="wood_light"):
    q = b.shell(name, ".", pos, (0,yaw,0))
    b.shape("SeatStop", q, (0,.37,0), (.47,.72,.50))
    b.box("Seat", q, (0,.431,0), (.449,.073,.455), ink, shadow=True)
    b.box("Back", q, (0,.763,-.21), (.442,.227,.071), ink, rot=(-7,0,0), shadow=True)
    for i,(x,z) in enumerate(((-.179,.162),(.179,.162),(-.18,-.197),(.18,-.197))):
        h = .797 if z<0 else .421
        b.box(f"Stile{i}", q, (x,h/2,z), (.040,h,.044), "edge", shadow=True)
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
    # Round 2 (2026-11-20): the court offices of The Trial, around the same desk.
    trial_archive(b)


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
    # A scaled aperture nested three times, with the beam and scenery still
    # made of objects. The lit patches have hard paper edges, not bloom.
    for i,(x,y,w,h,axis,t) in enumerate(((-1.72,1.60,3.91,2.11,-9,"rules"),
                     (.35,1.58,4.41,2.22,4,"paper"),(1.56,1.72,2.43,1.64,-12,"navy"),
                     (1.90,1.63,1.91,1.17,5,"cyanotype"),(2.17,1.64,1.27,.77,4,"white"))):
        paper(b,f"ProjectedAperture{i}","PaperAssembly",(x,y,-3.31+i*.039),w,h,t,axis,folded=True)
    b.box("ScreenRoller", "PaperAssembly", (.46,2.715,-3.202),(4.8,.132,.121), "ink",shadow=True)
    b.box("LowerRod", "PaperAssembly", (.46,.371,-3.122),(4.3,.036,.042), "navy",rot=(0,0,5))
    flat_mark(b,"Spill",[(-2.66,-3.09),(2.98,-2.82),(1.17,1.78),(-.09,1.83)],"ochre")
    flat_mark(b,"SpillShadow",[(.67,-2.96),(1.29,-2.92),(.29,1.82),(-.12,1.85)],"navy",.016)
    p=table(b,"ProjectionCart",(.94,0,.16),1.68,.84,top="navy")
    b.box("Projector",p,(-.17,.946,-.028),(.69,.316,.52),"cream",rot=(0,9,0),shadow=True)
    b.round("Housing",p,(-.15,1.00,-.31),.109,.16,"ink",rot=(90,0,0),sides=12)
    b.round("Glass",p,(-.15,1.00,-.401),.066,.035,"phosphor",rot=(90,0,0),sides=12)
    for i in range(4):
        b.box(f"Vent{i}",p,(-.35+i*.111,1.107,.039),(.028,.008,.24),"putty",rot=(0,9,0))
    for i in range(3):
        paper(b,f"Acetate{i}",p,(.46,.794+i*.006,.15),.43,.32,"ruled",8-i*10,floor=True)
    cabinet(b,"ApertureCabinet",(-3.63,-2.95),1.06,1.13,3,"navy")
    chair(b,"ViewingSeat",(-1.74,0,1.47),180,"ochre")
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


def terminal(b, p, slot, x, channel):
    q = child_path(p, slot)
    b.node(slot,p,position=vec3((x,.785,-.098)))
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
    b.flat("Raster",q,quad(b,.562,.378),phosphor(b,channel),(0,.475,.410))
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


def computer_room(b):
    for i,(x,z,w) in enumerate(((-2.65,-2.51,3.62),(2.65,-2.51,3.62),(-2.65,.48,3.62))):
        p=table(b,f"Station{i}",(x,0,z),w,1.38,top="wood_light")
        terminal(b,p,"Left",-.87,i%3)
        terminal(b,p,"Right",.87,(i+1)%3)
        chair(b,f"StationChair{i}",(x+.88,0,z+1.18),180,"putty")
    b.box("PatchPanel", "PaperAssembly", (2.17,1.20,-3.457), (2.59,.705,.17),"ink")
    for i in range(6):
        b.box(f"Jack{i}", "PaperAssembly", (1.16+i*.38,1.13,-3.35),(.099,.088,.044),"putty")
    # The scale error is a giant offset raster across the back, not an extra
    # monitor to be clicked or a copy of a real operating system.
    for i,(x,y,w,h,a,t) in enumerate(((-2.66,1.86,3.68,1.44,-4,"navy"),(-1.33,2.08,3.30,.89,5,"cyanotype"),
                        (.23,1.95,1.81,1.21,-6,"ledger"))):
        paper(b,f"RasterPrint{i}","PaperAssembly",(x,y,-3.473+i*.022),w,h,t,a)
    for i in range(7):
        b.box(f"ScanStep{i}","FloorComposition",(1.54+i*.295,.011,-.59+i*.364),(3.84-i*.34,.013,.041),
              "phosphor" if i%3 else "paper")
    # The outline follows CRT glass and housing, supported by the station top.
    p = "Station1"
    read(b,"computer_room",p,(1.89,1.18,-1.87),("Left/Bezel","Left/Raster","Left/Keyboard"),
         (.61,1.00,0,44,(0,0,-.09)))


def vacant_office(b):
    # Registration without the person: flat graphite imprints disagree with
    # familiar, solid desk and chair shapes, without adding a teacher or ghost.
    b.pigments.update(POMO)
    # Round 2 (2026-11-20): the same footprints, rebuilt as postmodern office furniture.
    p=memphis_desk(b,"EmptyDesk",(.89,0,-1.71),2.47,1.15,seed=1)
    b.box("Blotter",p,(.19,.814,.02),(1.12,.046,.68),"hatching",shadow=True)
    paper(b,"Carbon",p,(.10,.846,.056),.93,.59,"ruled",-8,floor=True)
    b.box("Ruler",p,(.42,.856,.225),(.621,.024,.067),"red",rot=(0,17,0))
    swivel_chair(b,".","VacantChair",(.48,0,-2.87),197,seat="pomo_pink",crest="disc",collider=True)
    swivel_chair(b,".","VisitorSeat",(-2.31,0,-1.21),28,seat="pomo_mint",back="pomo_cobalt",accent="pomo_pink",
                 crest="arch",arms=False,collider=True)
    cabinet(b,"EmptyPigeonhole",(-3.2,-2.96),1.24,1.12,3,"trim")
    for i,(x,y,w,d,angle,t) in enumerate(((-2.85,1.81,1.84,1.47,-8,"hatching"),
                        (-1.09,1.49,3.18,1.81,2,"paper"),(.35,1.65,2.69,1.40,-9,"hatching"),
                        (1.59,2.124,1.58,.90,-4,"ruled"),(3.21,1.56,1.40,1.30,6,"hatching"))):
        paper(b,f"CarbonPull{i}","PaperAssembly",(x,y,-3.336+i*.021),w,d,t,angle,folded=True)
    for i in range(4):
        paper(b,f"FloorPull{i}","FloorComposition",(-2.32+i*.96,.016+i*.001,.169-i*.22),
              1.31,2.01,"hatching",28-i*11,floor=True)
    emblem(b,"MissingCorner",(1.39,1.76,-3.093),(2.24,1.08))
    read(b,"vacant_office",p,(1.04,.816,-1.34),("Blotter","Ruler"))
    vacant_workroom(b)


def principal_office(b):
    # An apparently straight axis ends at the *side* of the desk. The enormous
    # window cross is painted into the yellow/blue division, like #196's shadows.
    flat_mark(b,"AmberField",[(-4.17,-3.30),(.47,-3.30),(3.2,3.21),(-2.43,3.21)],"ochre")
    flat_mark(b,"Perpendicular",[(-4.4,.19),(-4.4,.63),(3.52,-1.22),(3.52,-1.72)],"ink",.020)
    flat_mark(b,"FalseCross",[(1.09,3.29),(1.60,3.29),(-1.67,-3.28),(-2.16,-3.28)],"ink",.023)
    flat_mark(b,"PetrolField",[(1.7,3.25),(4.44,3.25),(4.44,-3.29),(.80,-3.29)],"teal",.014)
    # Mount a coloured, flat architectural perspective drawing well above the
    # real floor. It reads as an institution, not a second exit.
    for i,(x,y,w,h,a,t) in enumerate(((-2.67,1.57,2.67,2.18,-12,"navy"),(-1.52,1.63,3.56,2.22,4,"ochre"),
                        (-.49,1.63,2.25,1.77,-9,"teal"),(-.63,1.54,.48,1.68,-11,"ink"),
                        (-.61,1.50,2.42,.34,2,"ink"))):
        paper(b,f"FalseWindow{i}","PaperAssembly",(x,y,-3.320+i*.025),w,h,t,a,folded=True)
    b.pigments.update(POMO)
    p=memphis_desk(b,"HeadDesk",(1.62,0,-1.91),2.83,1.15,tall=.84,seed=2,classical=True,
                   colours=("pomo_cobalt","pomo_pink","pomo_white"))
    b.box("Front",p,(0,.37,-.302),(2.71,.63,.17),"ink",shadow=True)
    b.box("Blotter",p,(-.24,.867,.031),(.99,.045,.68),"navy",shadow=True)
    paper(b,"UnstampedForm",p,(-.25,.895,.026),.68,.47,"ledger",-8,floor=True)
    b.box("Stamp",p,(.45,.933,.041),(.14,.131,.143),"red",rot=(0,24,0),shadow=True)
    swivel_chair(b,".","ChairOfOffice",(1.78,0,-2.95),0,seat="red",back="navy",accent="pomo_lemon",
                 crest="throne",collider=True)
    for i in range(4):
        swivel_chair(b,".",f"WaitingSeat{i}",(-3.26+i*.87,0,.91+i*.15),147-i*8,seat="teal" if i%2 else "cream",
                     back=("pomo_black","pomo_lilac")[i%2],accent=("pomo_lemon","pomo_pink","pomo_mint","pomo_red")[i],
                     crest=("disc","triangle","arch","disc")[i],arms=i%2==0,collider=True)
    cabinet(b,"SideCase",(3.67,-2.97),.91,1.12,3,"navy")
    read(b,"principal_office",p,(1.48,.86,-1.41),("Blotter","Stamp"))
    kettle(b,"Kettle",p,(1.05,.84,-.22),-25)
    principal_suite(b)


ROOM_CONTENT = {f.__name__: f for f in (archive, plan_room, projection_room, computer_room, vacant_office, principal_office)}


def room(r):
    dims, door_x, plaster, lower, floor, backdrop = PALETTES[r.id]
    # Eyes adapt across the threshold, but nothing changes the player's lens
    # globally or affects the hallway. All scenes use the existing follow rig.
    b = start_room(r.id,{**COMMON,"lower":lower},(200,188,189),backdrop,(255,220,169),
                   sun=.84 if r.id != "principal_office" else .97,
                   sun_yaw=-40 if r.floor != "02" else 18)
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
    label(b,"RoomSign","WallNorth0",(dims[0]*.16,2.662,.134),r.english, .00237,ink=(232,215,172))
    b.box("SwitchPlate", ".", (door_x-1.14,1.15,dims[1]/2-.129),(.12,.22,.02), "trim")
    b.node("WorkLamp", ".", "OmniLight3D", position=vec3((-2.83,2.55,-1.92)),
           light_color=srgb((255,229,179)), light_energy=.46, omni_range=4.2)
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
        yield f'''[node name="{r.name}Door" parent="Interactables" instance=ExtResource("12_location_exit")]
position = {vec3(door_point)}
interact_id = &"to_{r.id}"
outline_paths = PackedStringArray({outline})
support_paths = PackedStringArray("{support}")
prompt_key = "prompt.{f'enter_{r.id}' if r.gated else 'enter_restroom'}"
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
