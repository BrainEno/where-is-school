"""Project-authored wear and fittings used only in the three washrooms."""
from __future__ import annotations

import math
import random

from fixture_geometry import Facets, basin, pipe, rounded_rect
from build_teaching_block import srgb, vec3


def paint_wear(b, phase, *, only):
    shader = b.bind("wear", "res://assets/shaders/school/restroom_wear.gdshader", "Shader")
    wash = [
        ((127, 133, 105), (73, 79, 56), (106, 76, 47)),
        ((133, 124, 93), (74, 75, 53), (112, 79, 50)),
        ((124, 117, 113), (71, 69, 70), (110, 75, 56)),
    ][phase]
    for name, field, base, damp, rust in (
        ("floor", 0, wash[0], wash[1], wash[2]),
        ("plaster", 1, (183, 169, 125), (87, 95, 66), (115, 79, 45)),
        ("lower", 1, (148, 153, 120), (74, 88, 67), (113, 73, 46)),
        ("stall", 1, (111, 118, 94), (68, 77, 55), (113, 65, 35)),
        ("ceramic", 2, (226, 216, 159), (102, 106, 60), (137, 93, 54)),
        ("wet", 3, (150, 157, 108), (62, 72, 54), (83, 78, 53)),
    ):
        if name not in only:
            continue
        b.local_mats[name] = f'''[sub_resource type="ShaderMaterial" id="Mat_{name}"]
shader = {shader}
shader_parameter/base_ink = {srgb(base)}
shader_parameter/damp_ink = {srgb(damp)}
shader_parameter/rust_ink = {srgb(rust)}
shader_parameter/field = {field}
shader_parameter/phase = {float(phase)}
'''


def squat_pan(b, parent):
    # The deck is four supported pieces, not a solid box through the bowl.
    # At y=.22 the inset is .166 m deep, still above the room's main slab.
    x, z, deck_y = .40, -2.46, .217
    b.node("SquatPan", parent, position=vec3((x, 0, z)))
    q = f"{parent}/SquatPan"
    slab = b.shell("RaisedBed", q)
    for name, px, pz, w, d in (
        ("Left", -.489, 0, .44, 1.32), ("Right", .489, 0, .44, 1.32),
        ("Rear", 0, -.532, .538, .256), ("Front", 0, .532, .538, .256),
    ):
        b.box(name, slab, (px, deck_y/2, pz), (w, deck_y, d), "lower", shadow=True)
        b.shape(name + "Solid", slab, (px, deck_y/2, pz), (w, deck_y, d))
    b.detail("Recess", q, (0, deck_y, 0), basin(.58, .865, .166, .19, drain=.046), "ceramic", shadow=True)
    b.round("Outlet", q, (0, .024, 0), .068, .022, "edge", sides=14)
    b.round("StandingWater", q, (0, .058, 0.009), .086, .008, "wet", sides=16)
    for side, px in enumerate((-.43, .43)):
        b.box(f"Footrest{side}", q, (px, deck_y+.021, .13), (.231, .042, .615), "ceramic")
        for i in range(7):
            b.box(f"Tread{side}_{i}", q, (px, deck_y+.045, -.10+i*.073), (.19, .013, .019), "deck")
    b.box("HighCistern", q, (0, 1.830, -.53), (.50, .29, .237), "ceramic", shadow=True)
    b.box("CisternTop", q, (0, 1.991, -.53), (.54, .044, .253), "trim")
    b.detail("Flush", q, (0, 0, -.43), pipe(((0, 1.72), (0, .60), (.025, .36),
             (.032, .246)), .019), "valve", shadow=True)
    b.detail("PullChain", q, (.292, 1.74, -.43), pipe(((0, .23), (.021, .10), (.019, -.332)), .005, sides=6), "steel")
    b.round("Pull", q, (.31, 1.38, -.43), .025, .069, "edge")


def urinal(b, parent, x, style):
    b.node(f"Urinal{style}", parent, position=vec3((x, .57, -2.83)))
    q = f"{parent}/Urinal{style}"
    ysz = ((0,.25,.19,.09,-.046), (.045,.32,.25,.12,-.019),
           (.207,.455,.40,.145,.027), (.235,.467,.412,.15,.028),
           (.231,.398,.344,.132,.033), (.194,.362,.311,.124,.026),
           (.092,.24,.187,.078,-.015), (.073,.117,.111,.042,-.047))
    rings = [[(xx, yy, zz+z) for xx, yy, zz in rounded_rect(y, w, d, r)] for y,w,d,r,z in ysz]
    b.detail("Pocket", q, (0,0,0), Facets().loft(rings), "ceramic", shadow=True)
    b.round("Sump", q, (0,.073,-.047), .068,.011,"edge", sides=14)
    b.round("Sieve", q, (0,.078,-.042), .037,.014,"steel", sides=12)
    b.box("Splash", q, (0,.35,-.145), (.402,.583,.135), "ceramic", shadow=True)
    b.box("Shoulder", q, (0,.62,-.133), (.41,.053,.151), "deck")
    b.round("Valve", q, (0,.714,-.11), .044,.112,"steel", sides=10)
    b.detail("Feed", q, (0, .53, -.176), pipe(((0,.03),(0,.44),(.047,.52),(.30,.52)), .014), "valve")
    b.round("Tail", q, (0,-.051,-.062), .035,.132,"edge", sides=10)
    body = b.shell("Footprint", q)
    b.shape("Bowl", body, (0,.2,0), (.46,.49,.42))


def _blotches(b, name, ellipses, ink, *, on_wall=False):
    """Small layered polygons with ragged edges, batched by pigment."""
    rng = random.Random(sum(ord(c) for c in name))
    mesh = Facets()
    for x, y, a, d, offset in ellipses:
        rim = []
        for i in range(18):
            angle = math.tau * i / 18
            r = rng.uniform(.63, 1.14)
            px, py = x+a*r*math.cos(angle), y+d*r*math.sin(angle)
            rim.append((px, py, offset) if on_wall else (px, offset, py))
        c = (x, y, offset) if on_wall else (x, offset, y)
        for i in range(len(rim)):
            a, d = rim[i], rim[(i+1) % len(rim)]
            mesh.face(c, d, a) if on_wall else mesh.face(c, a, d)
    b.detail(name, "WallWest0" if on_wall else ".", (0,0,0), mesh, ink)


def grime(b, phase):
    b.pigments.update({"water_edge": (81, 89, 59), "old_rust": (105, 72, 42),
                       "peel": (206, 182, 132), "discard": (154, 138, 105), "joint": (58, 64, 52)})
    _blotches(b, "DampEdges", [(-2.35,-1.82,.96,.65,.008), (-1.31,.89,.62,.42,.007),
              (-1.79,-2.39,.47,.66,.008), (1.23,-.48,.37,.47,.008), (3.55,2.20,.39,.65,.008)], "water_edge")
    _blotches(b, "PooledWater", [(-2.44,-1.79,.73,.42,.010),(-1.42,.91,.32,.26,.010),
              (-1.86,-2.42,.34,.45,.010),(3.55,2.26,.28,.45,.010)], "wet")
    _blotches(b, "PeelingPlaster", [(-2.67,1.75,.34,.52,.099),(-2.45,1.47,.49,.29,.099),
              (2.08,1.95,.57,.21,.099),(2.82,1.32,.27,.16,.099)], "peel", on_wall=True)
    _blotches(b, "RustUnderPipes", [(-2.64,1.015,.12,.38,.106),(-2.63,.347,.22,.27,.106),
              (.46,.55,.06,.18,.103)], "old_rust", on_wall=True)
    for i, (x,z,angle) in enumerate(((-2.14,-2.28,-13),(-.97,-2.68,28),(1.16,-.31,43),(2.74,2.81,-9),(3.56,1.88,21))):
        b.box(f"Discard{i}", ".", (x,.013,z), (.13+i%2*.09,.008,.145), "discard", rot=(0,angle+phase*4,0))
        b.box(f"Fold{i}", ".", (x+.047,.018,z+.017), (.078,.009,.11), "paper", rot=(0,angle-5,6))


def fly_clouds(b, phase):
    shader = b.bind("flies", "res://assets/shaders/school/restroom_flies.gdshader", "Shader")
    b.local_mats["flies"] = f'''[sub_resource type="ShaderMaterial" id="Mat_flies"]
shader = {shader}
'''
    fly = Facets()
    # A chunky black thorax and a pair of angled, semigrey wing planes. These
    # read in the production camera without giving every fly a large billboard.
    fly.face((0,.003,-.030),(-.007,.006,.007),(0,.003,.023),(.007,.006,.007))
    fly.face((0,.0,-.021),(-.009,.0,.011),(.009,.0,.011))
    fly.face((-.004,.007,-.005),(-.033,.016,.020),(-.018,.005,.036))
    fly.face((.004,.007,-.005),(.018,.005,.036),(.033,.016,.020))
    mesh = b.mesh("ArrayMesh", **{"_surfaces": fly.surface()})
    b.node("FlyClouds", ".")
    rng = random.Random(55084+phase)
    for i, (centre, bounds, count) in enumerate((
        ((-2.74, 1.24, -1.73), (.51,.48,.64), 22),
        ((-1.70, .96, -2.49), (.58,.45,.36), 22),
        ((.18, .69, -.94), (.68,.41,.52), 18),
    )):
        floats = []
        for _ in range(count):
            x,y,z = [rng.uniform(-a,a) for a in bounds]
            scale = rng.uniform(.70, 1.24)
            floats.extend((scale,0,0,x, 0,scale,0,y, 0,0,scale,z))
        mm = b.mesh("MultiMesh", transform_format=1, instance_count=count,
                    mesh=f'SubResource("{mesh}")', custom_aabb='AABB(-1, -0.82, -1, 2, 1.64, 2)',
                    buffer='PackedFloat32Array('+', '.join(f'{a:.4f}' for a in floats)+')')
        b.node(f"Cloud{i}", "FlyClouds", "MultiMeshInstance3D", position=vec3(centre),
               multimesh=f'SubResource("{mm}")', material_override=b.surface("flies"), cast_shadow=0)
