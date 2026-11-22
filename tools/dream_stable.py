"""The stink stable behind 01, round 10 (2026-11-11; docs/EXAM_DREAM_ART.md).

`build_dream_annex.py` calls these from `dream_house()`, `yard_ground()` and
`chickens_and_smell()`. The shaped meshes come from `stable_meshes.py`; each is written
as its own text ArrayMesh under `scenes/locations/corridor/stable_meshes/` (the dream
annex scene is too close to the release's 1 MiB budget for a scene to embed them) and
`build_teaching_block.py` writes or checks those files with the scene.

The manner is the visual experiments' (#196 colour fields, #200 ink hulls and cut paper),
pushed toward the absurd: horses painted in flat fields with a drawn contour, dung with a
cartoon gloss, flies by the hundred and one the size of a dog, the smell cut out of
muted translucent wisps, and a knocked-out spiral over whoever breathes it. The yellow-green screen
filter that thickens near the stalls is `scenes/locations/corridor/stench_haze.gd`, in the
corridor: nothing here carries a script.
"""
from __future__ import annotations

import math
import random
import re

import stable_meshes as sm
from build_teaching_block import GROUND_Y, srgb, vec3
from dream_figures import shader_material

G = GROUND_Y
STABLE_DIR = "scenes/locations/corridor/stable_meshes"
PAINT = "res://assets/shaders/school/stable_paint.gdshader"
INK = "res://assets/shaders/school/stable_ink.gdshader"
FLIES = "res://assets/shaders/school/stench_flies.gdshader"
PAPER = "res://assets/shaders/school/stench_paper.gdshader"
HEAP = (-31.6, G, 5.4)


def shaped(b, name, build):
    """One `stable_meshes` mesh as its own .tres; returns the ext id (built once per name)."""
    files = b.stable_files
    file_name = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name).lower() + ".tres"
    rid = f"stable_{file_name.removesuffix('.tres')}"
    if file_name not in files:
        mesh = build()
        files[file_name] = f'[gd_resource type="ArrayMesh" format=3]\n\n[resource]\n_surfaces = {mesh.surface()}\n'
        b.ext[rid] = f'[ext_resource type="ArrayMesh" path="res://{STABLE_DIR}/{file_name}" id="{rid}"]'
    return rid


def _mat(b, kind, path, params):
    shader = b.bind(kind, path, "Shader")
    return shader_material(b, kind, shader, params)


def paint(b, **params):
    return _mat(b, "stable_paint", PAINT, params)


def ink(b, **params):
    return _mat(b, "stable_ink", INK, params)


def flies_mat(b, **params):
    return _mat(b, "stench_flies", FLIES, params)


def paper(b, **params):
    return _mat(b, "stench_paper", PAPER, params)


def place(b, name, parent, pos, rid, mat, *, rot=None, overlay=None, shadow=False, aabb=None, scale=None):
    args = {"position": vec3(pos)}
    if rot:
        args["rotation_degrees"] = vec3(rot)
    if scale:
        args["scale"] = vec3(scale)
    args["mesh"] = f'ExtResource("{rid}")'
    args["material_override"] = b.surface(mat)
    if overlay:
        args["material_overlay"] = b.surface(overlay)
    if aabb:
        args["custom_aabb"] = "AABB(" + ", ".join(f"{v:g}" for v in aabb) + ")"
    if not shadow:
        args["cast_shadow"] = 0
    b.node(name, parent, "MeshInstance3D", **args)
    return f"{parent}/{name}"


def multimesh(b, name, parent, pos, rid, mat, transforms, aabb):
    floats = []
    for (x, y, z), yaw, s in transforms:
        c, si = math.cos(yaw) * s, math.sin(yaw) * s
        floats.extend((c, 0, si, x, 0, s, 0, y, -si, 0, c, z))
    mm = b.mesh("MultiMesh", transform_format=1, instance_count=len(transforms), mesh=f'ExtResource("{rid}")',
                custom_aabb="AABB(" + ", ".join(f"{v:g}" for v in aabb) + ")",
                buffer="PackedFloat32Array(" + ", ".join(f"{v:.4f}" for v in floats) + ")")
    b.node(name, parent, "MultiMeshInstance3D", position=vec3(pos), multimesh=f'SubResource("{mm}")',
           material_override=b.surface(mat), cast_shadow=0)


# --- the horses --------------------------------------------------------------------------

HORSE_MOTION = {"neck_pivot": sm.NECK_PIVOT, "tail_pivot": sm.TAIL_PIVOT}


def horse(b, parent, name, pos, yaw, look, *, graze, phase, swish=.32, dazed=False):
    """A shaped, painted horse with an ink contour; it grazes and swishes in its material."""
    key = "BayHorse" if look is sm.BAY else "GreyHorse"
    rid = shaped(b, key, lambda: sm.horse(look, 1 if look is sm.BAY else 2))
    motion = {**HORSE_MOTION, "graze": graze, "graze_rate": .07 if not dazed else .19, "swish": swish,
              "swish_rate": .42 + phase * .2, "phase": phase}
    body = paint(b, **motion, stench=.24)
    line = ink(b, **motion, width=.013)
    path = place(b, name, parent, pos, rid, body, rot=(0, yaw, 0), overlay=line, shadow=True,
                 aabb=(-.6, -.05, -1.4, 1.2, 2.4, 3.2))
    if dazed:
        halo = shaped(b, "DazeHalo", sm.daze_halo)
        place(b, "DazeHalo", path, (0, 2.32, 1.12), halo, paper(b, spin=1.4, wobble=.18, wobble_rate=.6, phase=phase))
    return path


def stall_dressing(b, body, w, d, stall_back, posts):
    """The bedding in the stalls and a horse's ink shadow painted on the empty stall's back wall."""
    floor = shaped(b, "StallBedding", lambda: sm.bedding(((-stall_back / 2 + .1, stall_back / 2 - .1),
                                                          (-d / 2 + .25, d / 2 - .25)), 520, 41, .03))
    place(b, "StallBedding", body, (w / 2 - stall_back / 2, .04, 0), floor, paint(b, stench=.32))
    shadow = shaped(b, "HorseShadow", lambda: sm.slab_polygon(sm.horse_silhouette(), .01, sm.rgb(sm.INK),
                                                              sm.rgb(sm.INK)))
    z = (posts[1] + posts[2]) / 2
    # Painted on the back wall of the empty middle stall: a horse that is not there, grazing.
    place(b, "HorseShadow", body, (w / 2 - stall_back + .115, .05, z + .1), shadow, paint(b, stench=0.0, hatch=0.0),
          rot=(0, 90, 0), scale=(.86, .86, .86))
    for i, (dz, colour) in enumerate(((-.5, sm.ACID), (.55, sm.MUSTARD))):
        stain = shaped(b, f"WallStain{i}", lambda c=colour, s=i: sm.stain(30 + s, .34, c))
        place(b, f"WallStain{i}", body, (w / 2 - stall_back + .12, 1.4 + .5 * i, z + dz), stain, paper(b),
              rot=(0, 0, 90))


# --- ground: dung, straw, stains ---------------------------------------------------------

def yard_ground(b, y, yard_x, yard_z, house_x, house_z):
    """Shaped droppings and loose straw over the yard and lane, with acid stains of smell."""
    rng = random.Random(2026)
    variants = [shaped(b, f"Dung{k}", lambda k=k: sm.dung_pile(k + 3, 1.0 + .25 * (k % 2), k / 4))
                for k in range(4)]
    fresh = paint(b, stench=.3, gloss=.85)
    old = paint(b, stench=.3, gloss=.25)
    placed = 0
    for i in range(40):
        x, z = rng.uniform(-39.5, -21.5), rng.uniform(5.0, 18.0)
        if house_x[0] < x < house_x[1] and z < house_z[1]:
            continue
        k = i % 4
        place(b, f"Dung{placed}", y, (x, G + .004, z), variants[k], fresh if k < 2 else old,
              rot=(0, rng.uniform(0, 360), 0))
        placed += 1
    strands = paint(b, stench=.28)
    chunks = (((-40.0, -33.4), (10.6, 14.6)), ((-33.4, -27.0), (4.8, 14.6)), ((-40.0, -30.4), (14.7, 18.3)),
              ((-30.4, -21.0), (14.7, 18.3)))
    for i, (cx, cz) in enumerate(chunks):
        area = ((0, cx[1] - cx[0]), (0, cz[1] - cz[0]))
        count = int((cx[1] - cx[0]) * (cz[1] - cz[0]) * 9)
        rid = shaped(b, f"Straw{i}", lambda a=area, n=count, s=i: sm.bedding(a, n, 70 + s * 11, .012))
        place(b, f"Straw{i}", y, (cx[0], G, cz[0]), rid, strands)
    colours = (sm.ACID, sm.BILE, sm.MUSTARD)
    for i, (x, z, r) in enumerate(((-31.0, 6.7, .9), (-33.6, 7.0, .55), (-33.6, 9.0, .6), (-29.6, 11.6, .4),
                                   (-36.4, 12.4, .5), (-25.4, 15.6, .45), (-31.8, 4.95, .7))):
        rid = shaped(b, f"Stain{i}", lambda s=i, rr=r: sm.stain(s + 3, rr, colours[s % 3]))
        place(b, f"Stain{i}", y, (x, G + .006 + .001 * i, z), rid, paper(b), rot=(0, i * 53 % 360, 0))


# --- the heap, its flies and its smell ---------------------------------------------------

def heap(b, y, parent):
    rid = shaped(b, "MuckHeap", sm.heap)
    place(b, "Muck", parent, (0, 0, 0), rid, paint(b, stench=.36, gloss=.7), overlay=ink(b, width=.016),
          shadow=True)
    b.node("HeapGlow", y, "OmniLight3D", position=vec3((HEAP[0] + .3, G + 1.6, HEAP[2] + 1.0)),
           light_color=srgb((196, 232, 74)), light_energy=.75, omni_range=5.5)


def flies(b, y):
    """Swarms over the heap, the stall fronts and the yard's dung; one fly the size of a dog."""
    rid = shaped(b, "Fly", lambda: sm.fly(2.6))
    rng = random.Random(77)
    swarms = (((HEAP[0], G + 1.15, HEAP[2] + .1), 70, .8, .5), ((-33.2, G + 1.7, 7.5), 46, .9, .45),
              ((-33.0, G + 1.4, 5.6), 28, .5, .4), ((-30.6, G + .7, 11.4), 30, 1.0, .5),
              ((-35.6, G + .8, 13.0), 24, .8, .45), ((-25.2, G + .8, 16.0), 22, .9, .5))
    for c, (centre, count, spread, amp) in enumerate(swarms):
        xs = [((rng.uniform(-spread, spread), rng.uniform(-.4, .45), rng.uniform(-spread, spread)),
               rng.uniform(0, math.tau), rng.uniform(.8, 1.25)) for _ in range(count)]
        reach = spread + amp * 1.5 + .1
        mat = flies_mat(b, swarm=amp, swarm_rate=2.2 + .3 * c, phase=c * .17)
        multimesh(b, f"Flies{c}", y, centre, rid, mat, xs, (-reach, -1.0, -reach, 2 * reach, 2.0, 2 * reach))
    giant = shaped(b, "GiantFly", sm.giant_fly)
    place(b, "GiantFly", y, (HEAP[0], G + 1.55, HEAP[2] + .5), giant,
          flies_mat(b, orbit_radius=1.25, orbit_rate=.055, bob=.22, flap=.42, flap_rate=34.0),
          aabb=(-1.9, -.5, -1.9, 3.8, 1.6, 3.8))


def stink(b, y):
    """Sparse translucent wisps rise off the heap, stalls and droppings."""
    clouds = [shaped(b, f"StinkCloud{k}", lambda k=k: sm.stink_cloud(k + 1, .3 + .05 * k,
                                                                     (sm.ACID, sm.MUSTARD, sm.BILE)[k]))
              for k in range(3)]
    rng = random.Random(11)
    sources = (((HEAP[0], G + .7, HEAP[2] + .2), 3, .7, 2.6), ((-33.0, G + 1.0, 7.4), 3, .9, 2.3),
               ((-30.4, G + .2, 11.6), 2, .8, 1.8), ((-35.8, G + .2, 12.8), 2, .7, 1.8),
               ((-25.4, G + .2, 15.8), 2, .6, 1.6))
    for c, (centre, count, spread, lift) in enumerate(sources):
        rid = clouds[c % 3]
        xs = [((rng.uniform(-spread, spread), rng.uniform(0, .3), rng.uniform(-spread, spread)),
               rng.uniform(0, math.tau), rng.uniform(.55, 1.0)) for _ in range(count)]
        mat = _mat(b, "stench_wisp", "res://assets/shaders/school/stench_wisp.gdshader", dict(rise=(.25, lift, 0), rise_rate=.07 + .01 * c, fade_edge=.28, spin=.22, wobble=.3,
                    phase=c * .31))
        reach = spread + .7
        multimesh(b, f"Stink{c}", y, centre, rid, mat, xs, (-reach, -.5, -reach, 2 * reach, lift + 1.2, 2 * reach))
    halo = shaped(b, "DazeHalo", sm.daze_halo)
    # The old woman on her stool has been knocked out by it: the spiral turns over her scarf.
    place(b, "DazeHaloOldWoman", y, (-33.1, G + 1.36, 12.45), halo, paper(b, spin=-1.1, wobble=.2, phase=.4),
          scale=(.8, .8, .8))
