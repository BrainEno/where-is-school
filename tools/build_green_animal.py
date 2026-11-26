#!/usr/bin/env python3
"""Sculpt the green animal as a painted, whole-piece creature (no imported textures).

Round 35: the owner asked for the unrefined 3D models to be refined, and the animal was
the one still carrying its own admission - "deliberately built from primitives ... a
neutral blockout". It is now sculpted like the roof collector of round 21: overlapping
ellipsoids and tapered limbs blended by a smooth minimum, turned into one closed mesh
per piece by surface nets, with normals from the field and an ambient-occlusion estimate
painted into the vertex colour. It stays the same animal: a small green thing with a
smooth bill, pricked ears and four quiet feet - nothing here claims what species it is;
the dialogue does the noticing, and it keeps its conclusions open.

The rig contract is unchanged (`green_animal.gd` moves the whole animal for breathing and
sways the node named `Head`): root at the feet, front toward -Z, the head piece modelled
in the Head node's space. Two RGBA8-painted surfaces, one per piece, so the coat, bill,
ears and feet add no material passes; the eyes stay separate dark spheres, which a
surface-net pass this coarse would only blur. Pure Python and deterministic.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

from stable_meshes import mix, rgb  # noqa: F401 - imported first: it puts the kit on the path
from stable_animals import Ell, Field, Cone, surface
from site_mesh import fbm, smoothstep

OUTPUT = Path(__file__).resolve().parents[1] / "scenes/environment/fauna/green_animal.tscn"
MESH_DIR = OUTPUT.parent / "green_animal_meshes"
MESH_RES = "res://scenes/environment/fauna/green_animal_meshes"

# The coat family of assets/materials/animal_green.tres (Color(0.24, 0.42, 0.24)), given
# light and shade so one flat fill does not read as a placeholder any more.
BASE = (84, 118, 68)
BACK = (54, 84, 50)
BELLY = (150, 158, 108)
LEG = (66, 94, 58)
CLAW = (98, 88, 62)
BILL = (198, 172, 112)
NAIL = (126, 108, 76)
EAR_IN = (190, 142, 126)
MOUTH = (56, 44, 38)
EYE_RING = (44, 40, 34)

# The Head node's position in the scene; the head piece is modelled in its space.
HEAD_AT = (0, 0.66, -0.36)

STEP = 0.02


def vec3(v):
    return "Vector3(%s)" % ", ".join(f"{c:.4g}" for c in v)


class Sculpt(Field):
    """A `Field` with a surface relief (muscle bands, nostril dents, toe grooves)."""

    def __init__(self, prims, relief=None, floor=None):
        super().__init__(prims, floor)
        self.relief = relief

    def __call__(self, x, y, z):
        d = super().__call__(x, y, z)
        if self.relief is not None and d < .02:
            d += self.relief(x, y, z)
        return d


def _scale(c, s):
    return tuple(v * s for v in c)


def _shade(colour_fn):
    """colour(p, n) -> sRGB bytes, darkened in the field's creases."""
    def paint(p, n, ao):
        c = colour_fn(p, n)
        k = .56 + .44 * ao
        return rgb(tuple(max(0.0, min(255.0, v * k)) for v in c))
    return paint


def _mottle(p, seed):
    """A soft coat mottle: two patches of tone across the flank."""
    f = fbm(p[0] * 7 + seed, p[1] * 9 + p[2] * 7, seed, 3)
    return smoothstep(-.4, .7, f)


def body():
    """Root-local: origin at the ground under the chest, front toward -Z."""
    prims = [
        # The trunk: chest low at the front, rump high at the back, one smooth volume.
        Ell((0, .40, -.12), (.235, .255, .27)),
        Ell((0, .375, .08), (.25, .265, .28)),
        Ell((0, .44, .30), (.235, .275, .23), k=.05),
        # Shoulders, read as soft humps rather than bones.
        Ell((-.125, .54, -.04), (.085, .08, .13), k=.05),
        Ell((.125, .54, -.04), (.085, .08, .13), k=.05),
        # The neck rising to the Head node's socket.
        Cone((0, .50, -.22), (0, .64, -.34), .12, .092, k=.05),
        # Four legs, splayed just enough to read as standing, not stuck on.
        Cone((-.125, .34, -.20), (-.155, .105, -.235), .078, .056, k=.03),
        Cone((.125, .34, -.20), (.155, .105, -.235), .078, .056, k=.03),
        Cone((-.135, .36, .24), (-.165, .105, .275), .086, .06, k=.03),
        Cone((.135, .36, .24), (.165, .105, .275), .086, .06, k=.03),
        # Feet: flattened pads, the front pair a shade longer than the back.
        Ell((-.155, .05, -.245), (.078, .05, .10), k=.03),
        Ell((.155, .05, -.245), (.078, .05, .10), k=.03),
        Ell((-.165, .05, .285), (.078, .05, .095), k=.03),
        Ell((.165, .05, .285), (.078, .05, .095), k=.03),
        # The tail: a tapered sweep off the rump, lifted and tipped.
        Cone((0, .46, .50), (0, .585, .66), .09, .036, k=.04),
        Ell((0, .60, .685), (.038, .038, .05), k=.025),
    ]

    def relief(x, y, z):
        r = 0.0
        # Two soft ribs over the belly, as if it had just eaten.
        if -.06 < z < .22 and y < .42:
            r += .0035 * math.sin((z + .06) * 40) * smoothstep(.24, .1, abs(x))
        # Toe grooves on each pad, running forward.
        ax, az = abs(x), abs(z - .27) if z > 0 else abs(z + .245)
        if ax > .07 and az < .1 and y < .08:
            r += .0022 * math.cos(ax * 90)
        return r

    field = Sculpt(prims, relief, floor=.012)
    seed = 19

    def colour(p, n):
        x, y, z = p
        t = _mottle(p, seed)
        base = mix(BASE, BACK, smoothstep(.30, .62, y + z * .12) * .7)
        base = mix(base, BELLY, smoothstep(.34, .12, y) * smoothstep(.02, -.18, z + .1) * .8)
        base = mix(base, BASE, t * .35)
        # The legs and feet tone down into the ground colour, claws horn.
        if y < .16:
            base = mix(base, LEG, smoothstep(.16, .05, y) * .6)
        if y < .095 and abs(x) > .06:
            base = mix(base, CLAW, smoothstep(.09, .02, y) * .55)
        # The tail tip darkens like the back.
        if z > .62 and y > .5:
            base = mix(base, BACK, smoothstep(.62, .72, z) * .7)
        # A paler edge where the coat turns to the light, from the normal, for free.
        if n[2] < -.5 and n[1] > .2:
            base = mix(base, BELLY, .18)
        return base

    return surface(field, STEP, _shade(colour))


def head():
    """Head-local: origin at the neck socket, front toward -Z, up +Y."""
    prims = [
        # The skull, a rounded wedge wider at the cheeks than at the brow.
        Ell((0, .02, .02), (.145, .135, .155)),
        Ell((0, .115, -.05), (.115, .05, .09), k=.03),
        Ell((-.095, -.02, -.05), (.062, .062, .075), k=.03),
        Ell((.095, -.02, -.05), (.062, .062, .075), k=.03),
        # The muzzle carrying the plate bill, the one shape the old blockout had.
        Cone((0, .01, -.06), (0, -.025, -.17), .105, .088, k=.04),
        Ell((0, .015, -.20), (.10, .055, .075), k=.03),
        Ell((0, .0, -.262), (.052, .03, .032), k=.02),
        # The chin, paler, and the two pricked ears.
        Ell((0, -.06, -.07), (.085, .05, .07), k=.03),
        Cone((-.10, .10, .04), (-.128, .205, .055), .045, .02, k=.02),
        Cone((.10, .10, .04), (.128, .205, .055), .045, .02, k=.02),
    ]

    def relief(x, y, z):
        r = 0.0
        # Nostril dents on the top of the bill.
        if abs(x) < .06 and -.26 < z < -.17 and y > .045:
            r -= .0035 * math.exp(-((abs(x) - .034) ** 2 + (z + .215) ** 2) * 2200)
        # The gape: a shallow groove where the bill meets the muzzle underneath.
        if abs(x) < .07 and -.16 < z < -.24 and -.05 < y < -.01:
            r -= .0025 * math.exp(-((y + .028) ** 2) * 3000)
        return r

    field = Sculpt(prims, relief)
    seed = 47

    def colour(p, n):
        x, y, z = p
        base = mix(BASE, BACK, smoothstep(.02, .14, y) * .5)
        base = mix(base, BASE, _mottle(p, seed) * .3)
        # The muzzle, bill and chin pale like the belly; the nail horn.
        if z < -.12 and y > -.06:
            base = mix(base, BILL, smoothstep(-.12, -.2, z) * .85)
        if z < -.235 and y < .03:
            base = mix(base, NAIL, smoothstep(-.235, -.27, z) * .8)
        if y < -.045 and z > -.14:
            base = mix(base, BELLY, .7)
        # The gape line, dark, along the underside of the bill.
        if abs(x) < .05 and -.17 < z < -.23 and -.045 < y < -.012:
            base = mix(base, MOUTH, .8)
        # An eye ring: dark fur round where the eyeballs sit (the eyes are separate).
        ring = (abs(x) - .085) ** 2 + (y - .06) ** 2 + ((z + .115) * 1.6) ** 2
        if ring < .006 and z < -.06:
            base = mix(base, EYE_RING, smoothstep(.006, .002, ring) * .9)
        # Ear inner surface, rose: the inner face of each ear cone.
        if abs(x) > .095 and y > .08:
            base = mix(base, EAR_IN, smoothstep(.095, .12, abs(x)) * .55 * smoothstep(.08, .14, y))
        return base

    return surface(field, STEP, _shade(colour))


def outputs():
    """{path: text}: the scene, plus one text ArrayMesh per piece under MESH_DIR."""
    body_mesh, head_mesh = body(), head()
    files = {
        MESH_DIR / "animal_body.tres": (
            f'[gd_resource type="ArrayMesh" format=3]\n\n[resource]\n'
            f'resource_name = "animal_body"\n_surfaces = {body_mesh.surface()}\n'
        ),
        MESH_DIR / "animal_head.tres": (
            f'[gd_resource type="ArrayMesh" format=3]\n\n[resource]\n'
            f'resource_name = "animal_head"\n_surfaces = {head_mesh.surface()}\n'
        ),
    }
    header = f'''[gd_scene load_steps=7 format=3]

[ext_resource type="Script" path="res://scripts/environment/green_animal.gd" id="1_animal"]
[ext_resource type="ArrayMesh" path="{MESH_RES}/animal_body.tres" id="2_body"]
[ext_resource type="ArrayMesh" path="{MESH_RES}/animal_head.tres" id="3_head"]
[ext_resource type="StandardMaterial3D" path="res://assets/materials/metal_dark.tres" id="4_eye"]

[sub_resource type="StandardMaterial3D" id="Coat"]
vertex_color_use_as_albedo = true
vertex_color_is_srgb = true
roughness = 0.82

[sub_resource type="SphereMesh" id="Eye"]
radius = 0.034
height = 0.068
radial_segments = 16
rings = 8

[node name="GreenAnimal" type="Node3D"]
script = ExtResource("1_animal")

[node name="Body" type="MeshInstance3D" parent="."]
mesh = ExtResource("2_body")
material_override = SubResource("Coat")

[node name="Head" type="Node3D" parent="."]
position = {vec3(HEAD_AT)}

[node name="Skull" type="MeshInstance3D" parent="Head"]
mesh = ExtResource("3_head")
material_override = SubResource("Coat")

[node name="EyeLeft" type="MeshInstance3D" parent="Head"]
position = Vector3(-0.085, 0.06, -0.115)
mesh = SubResource("Eye")
material_override = ExtResource("4_eye")

[node name="EyeRight" type="MeshInstance3D" parent="Head"]
position = Vector3(0.085, 0.06, -0.115)
mesh = SubResource("Eye")
material_override = ExtResource("4_eye")
'''
    files[OUTPUT] = header
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    files = outputs()
    stale = sorted(set(MESH_DIR.glob("*.tres")) - set(files)) if MESH_DIR.is_dir() else []
    if args.check:
        bad = [f for f, text in files.items() if not f.is_file() or f.read_text() != text]
        if bad or stale:
            parser.error("the green animal is stale; run tools/build_green_animal.py")
    else:
        MESH_DIR.mkdir(parents=True, exist_ok=True)
        for f in stale:
            f.unlink()
        for f, text in files.items():
            f.write_text(text)
    total = sum(len(text) for text in files.values())
    print(f"Sculpted green animal: {len(files)} files, {total:,} bytes; no imported images.")


if __name__ == "__main__":
    main()
