"""The stable yard behind 01 (docs/EXAM_DREAM_ART.md): round 10, refined in round 18.

`build_dream_annex.py` calls these from `dream_house()`, `yard_ground()`,
`chickens_and_smell()` and `stable_yard()`. Each shaped mesh is written as its own text
ArrayMesh under `scenes/locations/corridor/stable_meshes/` (the dream annex scene is too
close to the release's 1 MiB budget for a scene to embed them) and
`build_teaching_block.py` writes or checks those files with the scene.

Round 10 pushed the stable toward the absurd: paper horses with an ink contour, dung
everywhere, hundreds of flies, a fly the size of a dog and a knocked-out spiral. Round 18
(2026-11-11) answers the owner's note that it had become dirty, crowded and cheap, and
that the horses looked like paper and the hens like toy bricks. The horses and hens are
sculpted (`stable_animals.py`), the hen house, stall doors, bales, quilts and grain are
modelled (`stable_props.py`), and all of them are lit as matter by
`stable_coat.gdshader`. The yard is swept: a handful of droppings by the stalls, the
muck kept in a board bay, one small swarm and two faint wisps over it. What stays of the
dream is the ink shadow of a horse that is not there and the yellow-green filter near the
stalls (`scenes/locations/corridor/stench_haze.gd`, in the corridor): nothing here carries
a script.
"""
from __future__ import annotations

import math
import random
import re

import stable_animals as sa
import stable_meshes as sm
import stable_props as sp
from build_teaching_block import GROUND_Y, vec3
from dream_figures import shader_material

G = GROUND_Y
STABLE_DIR = "scenes/locations/corridor/stable_meshes"
PAINT = "res://assets/shaders/school/stable_paint.gdshader"
COAT = "res://assets/shaders/school/stable_coat.gdshader"
FLIES = "res://assets/shaders/school/stench_flies.gdshader"
PAPER = "res://assets/shaders/school/stench_paper.gdshader"
HEAP = (-31.75, G, 5.4)


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

HORSE_MOTION = {"neck_pivot": sa.NECK_PIVOT, "tail_pivot": sa.TAIL_PIVOT}
HORSE_AABB = (-.7, -.05, -1.6, 1.4, 2.6, 3.4)


def coat(b, **params):
    return _mat(b, "stable_coat", COAT, params)


def horse(b, parent, name, pos, yaw, look, *, graze, phase, swish=.32, rate=.07):
    """A sculpted, vertex-painted horse; it grazes and swishes in its material (round 18)."""
    meshes = {}

    def part(i):
        if not meshes:
            meshes["parts"] = sa.horse(look)
        return meshes["parts"][i]
    key = "BayHorse" if look is sa.BAY else "GreyHorse"
    trunk = shaped(b, key, lambda: part(0))
    limbs = shaped(b, key + "Limbs", lambda: part(1))
    motion = {**HORSE_MOTION, "graze": graze, "graze_rate": rate, "swish": swish,
              "swish_rate": .42 + phase * .2, "phase": phase}
    body = coat(b, **motion, sheen=.3)
    path = place(b, name, parent, pos, trunk, body, rot=(0, yaw, 0), shadow=True, aabb=HORSE_AABB)
    place(b, "Limbs", path, (0, 0, 0), limbs, body, shadow=True, aabb=HORSE_AABB)
    return path


def hens(b, parent, specs):
    """Sculpted hens [(name, pos, yaw, look, phase)]: each pecks on its own clock."""
    for name, pos, yaw, look, phase in specs:
        key = "WhiteHen" if look is sa.WHITE_HEN else "BrownHen"
        rid = shaped(b, key, lambda lk=look: sa.hen(lk))
        mat = coat(b, neck_pivot=sa.HEN_PIVOT, graze=.95, graze_rate=.33 + .05 * (phase * 7 % 3), phase=phase,
                   sheen=.35)
        place(b, name, parent, pos, rid, mat, rot=(0, yaw, 0), shadow=True, aabb=(-.3, -.05, -.3, .6, .6, .6))


def stall_dressing(b, body, w, d, stall_back, posts):
    """Clean bedding in the stalls and a horse's ink shadow on the empty stall's back wall."""
    floor = shaped(b, "StallBedding", lambda: sm.bedding(((-stall_back / 2 + .1, stall_back / 2 - .1),
                                                          (-d / 2 + .25, d / 2 - .25)), 320, 41, .03))
    place(b, "StallBedding", body, (w / 2 - stall_back / 2, .04, 0), floor, coat(b, sheen=.1))
    shadow = shaped(b, "HorseShadow", lambda: sm.slab_polygon(sm.horse_silhouette(), .01, sm.rgb(sm.INK),
                                                              sm.rgb(sm.INK)))
    z = (posts[1] + posts[2]) / 2
    # Painted on the back wall of the empty middle stall: a horse that is not there, grazing.
    place(b, "HorseShadow", body, (w / 2 - stall_back + .115, .05, z + .1), shadow, paint(b, stench=0.0, hatch=0.0),
          rot=(0, 90, 0), scale=(.86, .86, .86))
    door = shaped(b, "HalfDoor", lambda: sp.half_door(d / 3 - .3))
    for i in range(3):
        zc = (posts[i] + posts[i + 1]) / 2
        place(b, f"HalfDoor{i}", body, (w / 2 - .12, 0, zc), door, coat(b, sheen=.05), shadow=True)


# --- ground: a swept yard ---------------------------------------------------------------

def yard_ground(b, y, yard_x, yard_z, house_x, house_z):
    """Round 18: the yard is swept. Three small droppings by the stalls, straw where it is used."""
    variants = [shaped(b, f"Dung{k}", lambda k=k: sm.dung_pile(k + 3, .5 + .1 * (k % 2), .45 + k / 5))
                for k in (1, 2)]
    dung = coat(b, sheen=.03, roughness=.9, fill=.22)
    for i, (x, z, k) in enumerate(((-32.6, 7.4, 0), (-32.9, 9.1, 1), (-32.1, 6.6, 1))):
        place(b, f"Dung{i}", y, (x, G + .004, z), variants[k], dung, rot=(0, i * 77 % 360, 0))
    # Straw shaken out in front of the stalls and round the bales, not over the whole yard.
    for i, (area, count, seed) in enumerate(((((0, .9), (0, 5.4)), 160, 70), (((0, 2.0), (0, 1.0)), 60, 81))):
        rid = shaped(b, f"Straw{i}", lambda a=area, n=count, s=seed: sp.straw_patch(a, n, s, .008))
        at = ((house_x[1], G, house_z[0] + .2), (-40.0, G, 16.9))[i]
        place(b, f"Straw{i}", y, at, rid, coat(b, sheen=.1))


# --- the heap, its flies and its smell ---------------------------------------------------

def heap(b, y, parent):
    rid = shaped(b, "MuckHeap", sm.heap)
    place(b, "Muck", parent, (0, 0, 0), rid, coat(b, sheen=.04, roughness=.9, fill=.24), shadow=True,
          scale=(.9, .75, .75))
    bay = shaped(b, "ManureBay", sp.manure_bay)
    place(b, "Bay", parent, (0, 0, .05), bay, coat(b, sheen=.05), shadow=True)


def flies(b, y):
    """A small swarm over the heap: you notice it, it does not fill the frame."""
    rid = shaped(b, "Fly", lambda: sm.fly(2.0))
    rng = random.Random(77)
    xs = [((rng.uniform(-.6, .6), rng.uniform(-.3, .4), rng.uniform(-.5, .5)), rng.uniform(0, math.tau),
           rng.uniform(.8, 1.2)) for _ in range(26)]
    reach = .6 + .45 * 1.5 + .1
    mat = flies_mat(b, swarm=.45, swarm_rate=2.2, phase=0.0)
    multimesh(b, "Flies0", y, (HEAP[0], G + 1.0, HEAP[2] + .1), rid, mat, xs, (-reach, -1.0, -reach, 2 * reach, 2.0,
                                                                               2 * reach))


def stink(b, y):
    """Two faint translucent wisps rise off the heap."""
    rid = shaped(b, "StinkCloud0", lambda: sm.stink_cloud(1, .3, sm.MUSTARD))
    rng = random.Random(11)
    xs = [((rng.uniform(-.6, .6), rng.uniform(0, .3), rng.uniform(-.5, .5)), rng.uniform(0, math.tau),
           rng.uniform(.55, .9)) for _ in range(2)]
    mat = _mat(b, "stench_wisp", "res://assets/shaders/school/stench_wisp.gdshader",
               dict(rise=(.25, 2.4, 0), rise_rate=.07, fade_edge=.28, spin=.22, wobble=.3, phase=0.0))
    multimesh(b, "Stink0", y, (HEAP[0], G + .7, HEAP[2] + .2), rid, mat, xs, (-1.3, -.5, -1.3, 2.6, 3.6, 2.6))


# --- the hen house and the yard's things ----------------------------------------------

def coop(b, parent):
    rid = shaped(b, "HenHouse", sp.coop)
    place(b, "HenHouse", parent, (0, 0, 0), rid, coat(b, sheen=.05), shadow=True)


def bale(b, parent, name, pos, yaw):
    rid = shaped(b, "HayBale", lambda: sp.hay_bale(5))
    place(b, name, parent, pos, rid, coat(b, sheen=.12), rot=(0, yaw, 0), shadow=True)


def quilt(b, parent, name, pos, index):
    rid = shaped(b, f"Quilt{index}", lambda: sp.quilt(sp.QUILTS[index], seed=index))
    place(b, name, parent, pos, rid, coat(b, sheen=.15, roughness=.95), shadow=True)


def grain(b, parent, name, pos, size, yaw):
    rid = shaped(b, name, lambda: sp.grain_mat(size, 9))
    place(b, name, parent, pos, rid, coat(b, sheen=.05), rot=(0, yaw, 0))
