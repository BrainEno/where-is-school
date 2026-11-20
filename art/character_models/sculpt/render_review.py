#!/usr/bin/env python3
"""Render registered before/after views from the actual role GLBs in Blender."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE),str(HERE.parents[2]/'tools')]
from character_sculpt import BASE, ROOT, RUNTIME
from forms import LANDMARKS

VIEWS = dict(front=0, quarter=37, side=86, back=180)
CAMERA_DEPTH = dict(lead=.035, q=.024, n=.002, seated=.015, thin=-.058, gentle=-.036, court=-.050, b=-.087)
STATES = {
    'blink': {'Blink_L','Blink_R','Eye_Blink_L','Eye_Blink_R'},
    'mouth': {'MouthOpen','Mouth_Open','LipRelease'},
    'smile': {'Smile','SoftSmile'},
    'brow': {'BrowRaise','Brow_Raise'},
}


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path.resolve()),bone_heuristic='BLENDER',import_pack_images=True)
    scene = bpy.context.scene
    meshes = [o for o in scene.objects if o.type=='MESH']
    keys = [obj.data.shape_keys for obj in meshes if obj.data.shape_keys]
    for obj in scene.objects:
        obj.animation_data_clear()
        if obj.type=='ARMATURE':
            obj.data.pose_position = 'REST'
    for shape in keys:
        shape.animation_data_clear()
        for block in list(shape.key_blocks)[1:]:
            block.value = 0.
    scene.frame_set(1)
    return scene,meshes,keys


def studio(scene,role,size,samples):
    sign,_,eye,_,_ = LANDMARKS[role]
    target = Vector((0.,-CAMERA_DEPTH[role],eye+.024))
    scene.render.engine = 'CYCLES'
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 2
    scene.cycles.samples = samples
    scene.cycles.max_bounces = 4
    scene.cycles.transparent_max_bounces = 6
    scene.cycles.use_denoising = True
    scene.cycles.adaptive_threshold = .06
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.view_settings.exposure = -.05
    for mat in bpy.data.materials:
        if mat.use_nodes:
            shader = mat.node_tree.nodes.get('Principled BSDF')
            if shader and not any(tag in mat.name.lower() for tag in ('glass','optic')):
                shader.inputs['Specular IOR Level'].default_value = .13
    scene.world = bpy.data.worlds.new('Slate backdrop')
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (.15,.178,.224,1.)
    bg.inputs['Strength'].default_value = .65

    def lamp(name,dx,dy,dz,power,colour,width):
        data = bpy.data.lights.new(name,'AREA')
        data.shape,data.energy,data.color,data.size = 'DISK',power,colour,width
        obj = bpy.data.objects.new(name,data); scene.collection.objects.link(obj)
        obj.location = target+Vector((dx,-sign*dy,dz))
        obj.rotation_euler = (target-obj.location).to_track_quat('-Z','Y').to_euler()

    lamp('Warm key',-.48,.79,.62,65,(1.,.90,.82),.57)
    lamp('Cool fill',.56,.62,.06,27,(.79,.88,1.),.65)
    lamp('Edge',.29,-.58,.44,46,(.88,.91,1.),.47)
    data = bpy.data.cameras.new('Matched portraits')
    obj = bpy.data.objects.new('Matched portraits',data); scene.collection.objects.link(obj)
    scene.camera,data.type,data.ortho_scale,data.clip_start = obj,'ORTHO',.356,.05
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    return obj,target,sign


def frame(scene,cam,target,sign,yaw,path,lift):
    a = math.radians(yaw)
    cam.location = target+Vector((1.12*math.sin(a),-1.12*sign*math.cos(a),1.12*lift))
    cam.rotation_euler = (target-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath = str(path.resolve())
    bpy.ops.render.render(write_still=True)
    if not path.is_file() or path.stat().st_size < 4096:
        raise RuntimeError(f'Missing rendered frame {path}')
    print('FRAME',path.name,flush=True)
    return path.name


def clay(meshes):
    mat = bpy.data.materials.new('Study clay')
    mat.use_nodes = True
    shader = mat.node_tree.nodes['Principled BSDF']
    shader.inputs['Base Color'].default_value = (.31,.225,.171,1.)
    shader.inputs['Roughness'].default_value = .83
    for obj in meshes:
        for i,old in enumerate(obj.data.materials):
            if old and not any(t in old.name.lower() for t in ('optic','glass','mouthinner','pupil','iris','eye','brow','lash')):
                obj.data.materials[i] = mat


def compare(args):
    args.out.mkdir(parents=True,exist_ok=True)
    basis = subprocess.check_output(['git','rev-parse','--verify',f'{args.comparison_base}^{{commit}}'],
                                    cwd=ROOT,text=True).strip()
    manifest = dict(renderer=f'Blender {bpy.app.version_string}, Cycles CPU',basis=basis,
                    scale_m=.356,views_deg={name:VIEWS[name] for name in args.views},
                    details_at=dict(scale_m=.230,yaw=[0,37],lift=.015) if args.close else None,
                    resolution_px=args.size,samples=args.samples,
                    expressions_at=dict(yaw=10,lift=.015,weight=1.),models={})
    for role in args.roles or RUNTIME:
        manifest['models'][role] = {}
        before = args.bases/f'{role}.glb'
        expected = subprocess.check_output(['git','show',f'{basis}:{RUNTIME[role]}'],cwd=ROOT)
        if before.read_bytes() != expected:
            raise ValueError(f'{before} is not the {basis} comparison GLB')
        for state,path in (('before',before),('after',ROOT/RUNTIME[role])):
            scene,meshes,keys = load(path)
            camera,target,sign = studio(scene,role,args.size,args.samples)
            files = []

            def shoot(label,yaw,lift=.065):
                files.append(frame(scene,camera,target,sign,yaw,args.out/f'{role}-{state}-{label}.png',lift))

            for name in args.views:
                shoot(f'paint-{name}',VIEWS[name])
            if args.close:
                _, _, eye, front, _ = LANDMARKS[role]
                bust = target
                target = Vector((0.,-sign*(front-.040),eye-.032))
                camera.data.ortho_scale = .230
                shoot('detail-front',0,.015)
                shoot('detail-quarter',37,.015)
                camera.data.ortho_scale = .356
                target = bust
            expressions = []
            if args.expressions and any(item.name in targets for key in keys for item in key.key_blocks
                                        for targets in STATES.values()):
                shoot('paint-rest',10,.015)
                for expression,names in STATES.items():
                    active = set()
                    for key in keys:
                        for item in list(key.key_blocks)[1:]:
                            item.value = float(item.name in names)
                            if item.value:
                                active.add(item.name)
                    if active:
                        expressions.append(dict(state=expression,keys=sorted(active)))
                        shoot(f'paint-{expression}',10,.015)
                for key in keys:
                    for item in list(key.key_blocks)[1:]:
                        item.value = 0.
            if args.clay:
                clay(meshes)
                shoot('clay-quarter',37)
            manifest['models'][role][state] = dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                                                   frames=files,expressions=expressions)
    (args.out/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')


def main(argv):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--bases',type=Path,required=True)
    p.add_argument('--comparison-base',default=BASE,help='git revision that must match the before inputs')
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--roles',choices=list(RUNTIME),nargs='+')
    p.add_argument('--views',choices=list(VIEWS),default=list(VIEWS),nargs='+')
    p.add_argument('--size',type=int,default=416)
    p.add_argument('--samples',type=int,default=14)
    p.add_argument('--clay',action='store_true')
    p.add_argument('--close',action='store_true',help='extra matched close-ups of the face')
    p.add_argument('--expressions',action='store_true')
    compare(p.parse_args(argv))


if __name__=='__main__':
    main(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
