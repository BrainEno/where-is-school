#!/usr/bin/env python3
"""Build the shared, visual-only soil and railings for both schoolyard views."""
from pathlib import Path
import argparse
import math
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scenes/environment/props/playground_art/source'))
from site_mesh import Mesh, fbm  # noqa: E402

OUT = ROOT / 'scenes/environment/props/playground_art/earth_yard.tscn'


def build():
    # Subtle real relief over the unchanged walkable slab; all props and the
    # physical navigation remain owned by the playground. The shared scene has
    # no collision and can be instanced in the teaching-block window view too.
    rows = []
    for j in range(81):
        z = -20 + j * .5
        row = []
        for i in range(93):
            x = -23 + i * .5
            y = .055 + .015 * fbm(x * .23, z * .23, 47, 3)
            row.append((x, y, z))
        rows.append(row)
    mesh = Mesh().grid(rows, outward=(0, 1, 0))
    # The soil was added after the painted court and originally covered it. Cut
    # out the actual court footprint instead of lifting the court above the
    # player's feet. The 0.5 m grid aligns exactly with its four boundaries.
    visible = []
    for i in range(0, len(mesh.indices), 3):
        tri = mesh.indices[i:i + 3]
        x = sum(mesh.points[k][0] for k in tri) / 3
        z = sum(mesh.points[k][2] for k in tri) / 3
        if not (-11 < x < 11 and -15 < z < 11):
            visible.extend(tri)
    mesh.indices = visible
    parts = ['''[gd_scene load_steps=5 format=3]

[ext_resource type="Material" path="res://scenes/environment/props/playground_art/materials/yard_earth.tres" id="EarthMaterial"]
[ext_resource type="Material" path="res://scenes/environment/props/playground_art/materials/metal_ink.tres" id="Iron"]
[sub_resource type="ArrayMesh" id="EarthMesh"]
_surfaces = ''' + mesh.surface() + '''
[sub_resource type="BoxMesh" id="Bar"]
size = Vector3(0.045, 2.55, 0.045)
[node name="EarthYard" type="Node3D"]
[node name="Soil" type="MeshInstance3D" parent="."]
mesh = SubResource("EarthMesh")
material_override = ExtResource("EarthMaterial")
cast_shadow = 0
''']
    # Vertical rails reinforce the enclosure; leave existing gates and the west
    # construction-site approach clear. No collider is added to an existing route.
    for side, x in (('East', 22.6), ('West', -22.6)):
        zs = range(-17, 19) if side == 'East' else range(-17, 7)
        for i, z in enumerate(zs):
            parts.append(f'''[node name="{side}Rail{i}" type="MeshInstance3D" parent="."]
position = Vector3({x}, 1.275, {z})
mesh = SubResource("Bar")
material_override = ExtResource("Iron")
cast_shadow = 0
''')
    return '\n'.join(parts)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    text = build()
    if args.check:
        if not OUT.exists() or OUT.read_text() != text:
            parser.exit(1, 'Earth yard is stale\n')
    else:
        OUT.write_text(text, encoding='utf-8')
    print('Earth yard ' + ('matches.' if args.check else 'generated.'))


if __name__ == '__main__':
    main()
