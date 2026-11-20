#!/usr/bin/env python3
"""Make editable 4.5 LTS sources or photograph the exact runtime exports.

The source has individually selectable clothing pieces, optics, locks and
face shapes. Three native NLA clips share the real skeleton and face keys.
The review command imports the *batched runtime GLBs*, never the .blend files.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from designs import ACTING, DESIGNS

ROOT = HERE.parents[2]
FPS = 24
VIEWS = (('01-front',0),('02-front-quarter',36),('03-left',90),('05-back',180),('07-right',270))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.render.fps = FPS
    return scene


def collection(scene,name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


def put(obj, col):
    for other in list(obj.users_collection):
        other.objects.unlink(obj)
    col.objects.link(obj)


def clear_direct_animation(rig, keys):
    for obj in (rig,keys):
        if obj.animation_data:
            obj.animation_data.action = None
            for track in obj.animation_data.nla_tracks:
                track.mute = True
    for b in rig.pose.bones:
        b.matrix_basis = Matrix.Identity(4)
    for block in list(keys.key_blocks)[1:]:
        block.value = 0.


def load(path):
    previous = set(bpy.context.scene.objects)
    result = bpy.ops.import_scene.gltf(filepath=str(path.resolve()), bone_heuristic='BLENDER')
    if 'FINISHED' not in result:
        raise RuntimeError(f'Could not open {path}')
    added = set(bpy.context.scene.objects) - previous
    rig, = (o for o in added if o.type == 'ARMATURE')
    widgets = {p.custom_shape for p in rig.pose.bones if p.custom_shape}
    parts = sorted((o for o in added-widgets if o.type=='MESH'), key=lambda o:o.name)
    keys, = (p.data.shape_keys for p in parts if p.data.shape_keys)
    if len(rig.data.bones) != 57 or set(keys.key_blocks.keys()) != {'Basis','Blink_L','Blink_R','SoftSmile','LipRelease'}:
        raise RuntimeError(f'Skin or face channels missing from {path}')
    for p in parts:
        if not any(m.type=='ARMATURE' and m.object==rig for m in p.modifiers) or not p.data.color_attributes:
            raise RuntimeError(f'{p.name} has no skin or vertex paint')
    clear_direct_animation(rig,keys)
    bpy.context.view_layer.update()
    return rig, parts, keys


def part_group(p):
    name = p.name.lower()
    if 'crown' in name or 'combed lock' in name:
        return '02 · Hair'
    if any(s in name for s in ('spectacle', 'optical', 'temple', 'rivet', 'saddle pad','sleeper')):
        return '03 · Eyewear and hardware'
    if any(s in name for s in ('face', 'skin', 'sclera', 'brow', 'orbital')):
        return '01 · Face and hands'
    if any(s in name for s in ('trousers', 'twill welt', 'sneaker', 'outsole', 'lace', 'toe cap')):
        return '05 · Trousers and shoes'
    return '04 · Tailoring and seams'


def arrange_clips(scene, rig, keys, signature):
    start = 8
    for clip in ('idle','walk_in_place',signature):
        extent = start
        for obj in (rig,keys):
            for track in obj.animation_data.nla_tracks:
                if track.name != clip:
                    continue
                strip, = track.strips
                strip.action.use_fake_user = True
                length = strip.action_frame_end - strip.action_frame_start
                strip.frame_start = start
                strip.frame_end = start + length
                strip.extrapolation = 'NOTHING'
                track.mute = False
                extent = max(extent, math.ceil(strip.frame_end))
        scene.timeline_markers.new(clip, frame=start)
        start = extent + 10
    scene.timeline_markers.new('Bind · no clip', frame=1)
    scene.frame_end = start - 4
    scene.frame_set(1)


def source(key, path, out):
    scene = reset()
    rig, parts, keys = load(path)
    if len(parts) < 50:
        raise RuntimeError('Editing requires the split-part GLB, not the batched runtime copy')
    groups = {name:collection(scene,name) for name in sorted({part_group(p) for p in parts})}
    for p in parts:
        put(p, groups[part_group(p)])
    put(rig, collection(scene,'00 · Armature'))
    rig.data.display_type = 'STICK'
    rig.show_in_front = True
    rig['Source'] = 'Where Is School original classmate; fitted to CC0 MakeHuman base/targets/masks at 1f508f6083b2f823dab15de924b3bde72e08d77c'
    rig['Workflow'] = 'Frame 1: bind. Three labeled NLA ranges. Edit source and rebuild GLB for the game.'
    arrange_clips(scene,rig,keys,ACTING[key][0])
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space = area.spaces.active
                space.overlay.show_overlays = False
                space.shading.color_type = 'VERTEX'
                space.shading.show_cavity = True
                space.shading.cavity_type = 'WORLD'
                view = space.region_3d
                view.view_perspective = 'ORTHO'
                view.view_location = (0.,.045,DESIGNS[key].height*.51)
                view.view_rotation = Vector((-.61,-3.52,-.26)).to_track_quat('-Z','Y')
                view.view_distance = 2.42
    out.parent.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(out.resolve()), compress=True)
    print(f'SOURCE {key}: {len(rig.data.bones)} joints, {len(parts)} fitted pieces, {len(bpy.data.actions)} actions', flush=True)


def studio(scene, samples):
    scene.render.engine = 'CYCLES'
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 2
    scene.cycles.samples = samples
    scene.cycles.max_bounces = 5
    scene.cycles.transparent_max_bounces = 6
    scene.cycles.use_denoising = True
    scene.cycles.denoiser = 'OPENIMAGEDENOISE'
    scene.cycles.adaptive_threshold = .035
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.view_settings.exposure = -.31
    # Let the vertex pigment, not a white specular veil, read in the photos.
    # This only adjusts imported *studio* materials; neither export is changed.
    for mat in bpy.data.materials:
        if mat.use_nodes:
            surface = mat.node_tree.nodes.get('Principled BSDF')
            if surface is not None:
                surface.inputs['Specular IOR Level'].default_value = .20 if mat.name.startswith(('eye_paint','frames')) else .085
    scene.world = bpy.data.worlds.new('Paper-grey ambient')
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes['Background']
    background.inputs['Color'].default_value = (.49,.54,.60,1.)
    background.inputs['Strength'].default_value = .40

    def softbox(name, loc, energy, color, size):
        data = bpy.data.lights.new(name,'AREA')
        data.energy, data.color, data.shape, data.size = energy, color, 'DISK', size
        obj = bpy.data.objects.new(name,data)
        scene.collection.objects.link(obj)
        obj.location = loc
        obj.rotation_euler = (Vector((0.,.04,1.08))-obj.location).to_track_quat('-Z','Y').to_euler()

    softbox('Warm broad key',(-2.15,3.75,3.25),272,(1.,.872,.775),2.6)
    softbox('Cool bounce',(2.40,2.58,2.65),154,(.785,.865,1.),2.65)
    softbox('Broad back edge',(.73,-2.53,2.92),204,(1.,.917,.816),3.1)
    bpy.ops.mesh.primitive_plane_add(size=2000)
    floor = bpy.context.object
    floor.name = 'Review paper stage'
    floor.location.z = -.0011
    material = bpy.data.materials.new('Neutral paper sweep')
    material.use_nodes = True
    shader = material.node_tree.nodes['Principled BSDF']
    shader.inputs['Base Color'].default_value = (.30,.329,.336,1.)
    shader.inputs['Roughness'].default_value = .96
    floor.data.materials.append(material)
    data = bpy.data.cameras.new('Orthographic review')
    camera = bpy.data.objects.new('Orthographic review',data)
    scene.collection.objects.link(camera)
    scene.camera, camera.data.type = camera,'ORTHO'
    # A very long floor sweep keeps the horizon outside near-horizontal crops.
    camera.data.clip_end = 550.
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.image_settings.compression = 18
    return camera


def shoot(scene,camera,out,target,yaw,tilt,vertical,w,h):
    heading = math.radians(yaw)
    d = 3.75
    eye = Vector(target) + Vector((math.sin(heading)*d,math.cos(heading)*d,d*tilt))
    camera.location = eye
    camera.rotation_euler = (Vector(target)-eye).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale = vertical*max(1.,w/h)
    scene.render.resolution_x,scene.render.resolution_y = w,h
    scene.render.resolution_percentage = 100
    out.parent.mkdir(parents=True,exist_ok=True)
    scene.render.filepath = str(out.resolve())
    bpy.ops.render.render(write_still=True)
    if not out.is_file() or out.stat().st_size < 4096:
        raise RuntimeError(f'Render did not produce {out}')
    print('FRAME',out,flush=True)


def pose(scene,rig,keys,clip,seconds):
    clear_direct_animation(rig,keys)
    for obj in (rig,keys):
        if not obj.animation_data:
            continue
        for track in obj.animation_data.nla_tracks:
            if track.name==clip:
                track.mute = False
                for strip in track.strips:
                    strip.extrapolation = 'NOTHING'
    frame = 1+seconds*FPS
    scene.frame_set(int(frame),subframe=frame%1.)


def review(key,path,out,samples,quick):
    scene = reset()
    rig, _, keys = load(path)
    camera = studio(scene,samples)
    h = DESIGNS[key].height
    w, tall = (460,690) if quick else (700,1050)
    close = 460 if quick else 800
    take = (VIEWS[1],VIEWS[3]) if quick else VIEWS
    for name,yaw in take:
        shoot(scene,camera,out/f'{name}.png',(0.,.044,h*.505),yaw,.077,h+.235,w,tall)
    for name,yaw in [('09-face-front',0),('10-face-quarter',32)][1 if quick else 0:]:
        shoot(scene,camera,out/f'{name}.png',(0.,.069,h-.162),yaw,.045,.412,close,close)
    clip, t = ACTING[key]
    pose(scene,rig,keys,clip,t)
    x = .082 if key=='gentle_classmate' else -.045 if key=='thin_classmate' else .0
    shoot(scene,camera,out/f'11-{clip}.png',(x,.12,h*.756),24 if key=='gentle_classmate' else -30,
          .092,1.02,close,close)
    if key=='gentle_classmate' and not quick:
        pose(scene,rig,keys,clip,.66)
        shoot(scene,camera,out/'12-listen_nod.png',(0.,.085,1.27),28,.049,.70,w,w)


def lineup(models,out,samples):
    scene = reset()
    for key,x in zip(DESIGNS,(.68,0.,-.70)):
        armature, _, _ = load(models/f'{key}.glb')
        armature.location.x = x
    bpy.context.view_layer.update()
    shoot(scene,studio(scene,samples),out/'00-trio-at-scale.png',(0.,.06,.914),0.,.050,2.04,1450,1040)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parts', type=Path, help='Split GLB directory for editable sources')
    parser.add_argument('--source-dir',type=Path,default=HERE)
    parser.add_argument('--models', type=Path,default=ROOT/'assets/models/classmates')
    parser.add_argument('--review-dir',type=Path)
    parser.add_argument('--samples',type=int,default=32)
    parser.add_argument('--only',choices=DESIGNS)
    parser.add_argument('--quick',action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if bpy.app.version[:2] != (4,5) or not (args.parts or args.review_dir):
        parser.error('Use Blender 4.5 LTS and specify --parts and/or --review-dir')
    keys = [args.only] if args.only else list(DESIGNS)
    manifest = {}
    for key in keys:
        if args.parts:
            source(key,args.parts/f'{key}_parts.glb', args.source_dir/f'{key}.blend')
        if args.review_dir:
            path = args.models/f'{key}.glb'
            output = args.review_dir/key
            review(key,path,output,args.samples,args.quick)
            manifest[key] = {'sha256':hashlib.sha256(path.read_bytes()).hexdigest(), 'height_m':DESIGNS[key].height,
                             'views':[p.name for p in sorted(output.glob('*.png'))]}
    if args.review_dir:
        if len(keys)==3 and not args.quick:
            lineup(args.models,args.review_dir,args.samples)
        (args.review_dir/'MANIFEST.json').write_text(json.dumps({'renderer':f'Blender {bpy.app.version_string} / Cycles CPU',
           'source':'exact runtime GLBs, with their embedded actions', 'models':manifest},indent=2)+'\n')


if __name__=='__main__':
    main()
