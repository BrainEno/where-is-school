#!/usr/bin/env python3
"""Make the editable Blender source from the split-part GLB, optionally render it.

Run with Blender 4.5 LTS or its bpy module. No add-ons / MakeHuman program needed.
The baked pose keys are checkpoints, not shipped animations.
"""

import argparse
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parents[3]
POSES = ROOT / 'scenes/dev/teacher_b/review_poses.json'
FRAMES = {'bind': 1, 'demonstrate': 24, 'stride': 48}


def group(obj):
    name = obj.name
    if name.startswith(('Tortoiseshell', 'Optical lens', 'Acetate', 'Hinge pin', 'Arched saddle', 'Old brass')):
        return '03 · Spectacles and earrings'
    if 'silver' in name:
        return '02 · Silver hair'
    if name.startswith(('Face', 'Eye ', 'Hands', 'Outer lid', 'Tapered brow')):
        return '01 · Face and hands'
    if name.startswith(('Straight pressed', 'Low outsole', 'Leather vamp', 'Moc toe')):
        return '05 · Trousers and shoes'
    return '04 · Tailoring'


def evaluated_vertices(obj, depsgraph):
    shaped = obj.evaluated_get(depsgraph)
    mesh = shaped.to_mesh()
    try:
        return [shaped.matrix_world @ v.co for v in mesh.vertices]
    finally:
        shaped.to_mesh_clear()


def make_source(glb, output):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(glb.resolve()), bone_heuristic='BLENDER')
    scene = bpy.context.scene
    rig, = (o for o in scene.objects if o.type == 'ARMATURE')
    widgets = {bone.custom_shape for bone in rig.pose.bones if bone.custom_shape is not None}
    parts = [o for o in scene.objects if o.type == 'MESH' and o not in widgets]
    if len(rig.data.bones) != 57 or len(parts) != 57:
        raise ValueError('Use the split-part GLB, not the batched Godot export')
    for obj in parts:
        if not any(m.type == 'ARMATURE' and m.object == rig for m in obj.modifiers):
            raise ValueError(f'{obj.name} lost its armature modifier')
        name = group(obj)
        col = bpy.data.collections.get(name)
        if col is None:
            col = bpy.data.collections.new(name)
            scene.collection.children.link(col)
        for previous in list(obj.users_collection):
            previous.objects.unlink(obj)
        col.objects.link(obj)
    rig.name = 'Teacher B · deform rig'
    rig.data.display_type = 'STICK'
    rig.show_in_front = True
    rig['Review'] = 'Frame 1: bind; 24: elbow and fingers; 48: stride. Keys are inspection poses.'
    rig['Source'] = 'First-party Teacher B fit and tailoring, MakeHuman CC0 topology/masks at 1f508f6083b2f823dab15de924b3bde72e08d77c'
    scene.unit_settings.system = 'METRIC'
    scene.frame_end = 48
    axes = (Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, -1, 0)))  # GLB X/Y/Z in Blender
    poses = json.loads(POSES.read_text())
    rest = {bone.name: (rig.matrix_world @ bone.bone.matrix_local).to_3x3().inverted()
            for bone in rig.pose.bones}
    shoes = [obj for obj in parts if obj.name.startswith('Low outsole')]
    rest_points = {}
    for name, frame in FRAMES.items():
        for bone in rig.pose.bones:
            bone.rotation_mode = 'QUATERNION'
            bone.rotation_quaternion = Quaternion()
            bone.location = (0., 0., 0.)
        for bone, angles in poses[name].items():
            b = rig.pose.bones[bone]
            for axis, angle in zip(axes, angles):
                b.rotation_quaternion = Quaternion((rest[bone] @ axis).normalized(), math.radians(angle)) @ b.rotation_quaternion
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        floor = min(v.z for obj in shoes for v in evaluated_vertices(obj, depsgraph))
        if abs(floor) > .10 or (name == 'bind' and abs(floor) > .0002):
            raise ValueError(f'Unexpected {name} ground height {floor:.5f}')
        print(f'{name}: raw posed ground {floor:+.5f} m')
        # The stride is a held reference, not a displacement clip. Ground only
        # this preview pose; the exported GLB stays in the untouched bind pose.
        rig.pose.bones['Root'].location = rest['Root'] @ Vector((0, 0, -floor))
        bpy.context.view_layer.update()
        for bone in rig.pose.bones:
            bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
        rig.pose.bones['Root'].keyframe_insert('location', frame=frame, group='Root')
        scene.timeline_markers.new(name.capitalize(), frame=frame)
        for key in ('Hands L', 'Set-in wool sleeve L', 'Straight pressed twill L', 'Tortoiseshell rim L'):
            vertices = evaluated_vertices(bpy.data.objects[key], depsgraph)
            if name == 'bind':
                rest_points[key] = vertices
            else:
                movement = max((a-b).length for a,b in zip(vertices, rest_points[key]))
                print(f'  {key}: max vertex displacement {movement:.4f} m')
    rig.animation_data.action.name = 'Review poses (not a runtime clip)'
    scene.frame_set(1)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                space = area.spaces.active
                space.shading.color_type = 'VERTEX'
                space.shading.light = 'STUDIO'
                space.shading.show_cavity = True
                space.shading.cavity_type = 'WORLD'
                space.overlay.show_overlays = False
                view = space.region_3d
                view.view_rotation = Vector((-.6, -2.6, -.27)).to_track_quat('-Z', 'Y')
                view.view_location = (0, .04, .84)
                view.view_distance = 2.45
                view.view_perspective = 'ORTHO'
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output.resolve()), compress=True)
    return scene


def render_review(scene, out, samples):
    out.mkdir(parents=True, exist_ok=True)
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 5
    scene.cycles.transparent_max_bounces = 4
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 2
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.world = bpy.data.worlds.new('Grey-green studio ambient')
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes['Background']
    background.inputs['Color'].default_value = (.30, .33, .35, 1)
    background.inputs['Strength'].default_value = .69

    def light(name, loc, target, watts, tint, size):
        data = bpy.data.lights.new(name, 'AREA')
        data.energy, data.color, data.shape, data.size = watts, tint, 'DISK', size
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = loc
        obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()

    light('Warm key', (-2.2, 2.5, 3.3), (0, 0, 1.22), 230, (1, .86, .71), 1.9)
    light('Cool fill', (2.2, 2.1, 2.4), (0, 0, 1.34), 122, (.77, .86, 1), 2.2)
    light('Crown rim', (.1, -2.4, 2.9), (0, 0, 1.25), 184, (1, .92, .79), 1.6)
    bpy.ops.mesh.primitive_plane_add(size=200)
    floor = bpy.context.object
    floor.location.z = -.001
    slate = bpy.data.materials.new('Neutral slate')
    slate.use_nodes = True
    bsdf = slate.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (.13, .16, .145, 1)
    bsdf.inputs['Roughness'].default_value = .95
    floor.data.materials.append(slate)
    data = bpy.data.cameras.new('Inspection camera')
    camera = bpy.data.objects.new('Inspection camera', data)
    scene.collection.objects.link(camera)
    scene.camera, data.type = camera, 'ORTHO'
    shots = {
        'front': ('bind', (.10, 3.7, 1.48), (0, .06, .82), 1.96, (600, 854)),
        'side': ('bind', (3.65, .64, 1.48), (0, .05, .82), 1.96, (600, 854)),
        'back': ('bind', (.91, -3.3, 1.50), (0, .05, .82), 1.96, (600, 854)),
        'face': ('bind', (.82, 1.48, 1.66), (0, .084, 1.492), .367, (722, 768)),
        'demonstrate': ('demonstrate', (-.82, 2.45, 1.60), (0, .067, 1.197), 1.02, (668, 760)),
        'stride': ('stride', (-2.90, 2.02, 1.33), (0, .04, .814), 1.91, (760, 854)),
    }
    for name, (pose, eye, target, scale, size) in shots.items():
        scene.frame_set(FRAMES[pose])
        camera.location = eye
        camera.rotation_euler = (Vector(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()
        data.ortho_scale = scale
        scene.render.resolution_x, scene.render.resolution_y = size
        scene.render.resolution_percentage = 100
        scene.render.image_settings.color_mode = 'RGB'
        scene.render.image_settings.file_format = 'PNG'
        scene.render.filepath = str((out / f'{name}.png').resolve())
        bpy.ops.render.render(write_still=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parts', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path(__file__).with_name('teacher_b.blend'))
    parser.add_argument('--render-dir', type=Path)
    parser.add_argument('--samples', default=24, type=int)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:])
    scene = make_source(args.parts, args.output)
    if args.render_dir:
        render_review(scene, args.render_dir, args.samples)


if __name__ == '__main__':
    main()
