#!/usr/bin/env python3
"""Build or bake the editable rest-space head study in Blender 4.5 LTS."""
from __future__ import annotations

import argparse
import gzip
import json
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parents[2] / 'tools')]
import character_sculpt as io
from character_geometry import teacher_bob
from glb_io import accessor, decode
from forms import (LANDMARKS, components, ease, face, facial_details, hairline,
                   lead_spikes, other_hair, q_closeup_planes, shell_relief)
from refine_bq import (b_brows_and_folds, b_cheek_and_mouth, b_chignon, q_brows,
                       q_cheek_and_mouth, q_cropped_fringe, q_cropped_relief, seat_q_orbit)
from refine_classroom import (n_bob, n_brow, n_face, student_brow, student_crop,
                              student_face, student_hair_clearance, student_lock, student_nape)

# The prepared seated GLB retains these node IDs for the two inset nostrils.
STUDENT_NOSTRILS = {'Sphere.019', 'Sphere.020'}


class Surface:
    def __init__(self, doc, blob, slot, mesh, part):
        self.doc, self.blob, self.slot = doc, blob, slot
        self.mesh, self.part = mesh, part
        self.mat = doc['materials'][part['material']]
        self.node = next(n['name'] for n in doc['nodes'] if n.get('mesh') == slot[0])
        self.p = self.read(part['attributes']['POSITION'])
        self.n = self.read(part['attributes']['NORMAL'])
        self.triangles = self.read(part['indices'], np.int32).reshape(-1,3)
        self.output = None
        self.remesh = None

    def read(self, index, dtype=np.float64):
        return np.array(accessor(self.doc,self.blob,index), dtype=dtype)


def surfaces(directory, role):
    doc, blob = decode((directory/f'{role}.glb').read_bytes())
    for slot, name, part in io.primitives(doc):
        yield Surface(doc, blob, slot, name, part)


def zone(role, s):
    n, m = s.node, s.mat['name']
    if role in ('lead','q'):
        return {'Hair':'hair','Eyes':'eye','Head':'face'}.get(n.split('_')[-1])
    if role == 'n':
        if n == 'ST_Hair': return 'hair'
        if n.startswith('ST_Ear_'): return 'ear'
        if n.startswith('ST_Eye_'): return 'eye'
        if n.startswith(('ST_Head_','ST_Eyebrow_')): return 'face'
    if role == 'seated':
        if n.startswith('Hair_'): return 'hair'
        if n.startswith('Ear_'): return 'ear'
        if n.startswith('Eye_'): return 'eye'
        if n in STUDENT_NOSTRILS or n.startswith((
                'Head_Main','Eyebrow_','Upper_Eyelid_','Mouth_Line','Lower_Lip','Nostril_')):
            return 'face'
    if role in ('thin','gentle','court','b'):
        if m.startswith('hair_') or m=='b_swept_silver': return 'hair'
        if m in ('eye_paint','b_eye'): return 'eye'
        if n.startswith('Face and ') or n=='Sculpted face and neck' or m=='b_brows_and_crease': return 'face'
        # Small detail is material-batched. Restrict the stroke in Y; other
        # surfaces of this material may be below the collar or on clothing.
        if m=='small_detail': return 'face'
    return None


def axes(p, sign):
    """glTF local -> Blender; a proper half-turn presents every study forward."""
    return np.column_stack((p[:,0]*sign, -p[:,2]*sign, p[:,1]))


def local(p, sign):
    return np.column_stack((p[:,0]*sign, p[:,2], -p[:,1]*sign))


def new_mesh(name, p, f):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(p.tolist(), [], f.tolist())
    mesh.polygons.foreach_set('use_smooth', np.ones(len(f),dtype=np.bool_))
    mesh.update()
    return mesh


def fitted_shell(role, skull, *, line=None, shape=None):
    """Closed, smooth crown built by casting an authored hem onto the actual skull."""
    _,_,eye,ze,_ = LANDMARKS[role]
    pivot = np.array([0.,eye+.033,ze-.086])
    slices, rings = (88, 37) if role=='lead' else (96, 37)
    azimuth = np.arange(slices)*2*np.pi/slices
    a,t = np.meshgrid(azimuth,np.linspace(1/rings,1.,rings))
    theta = t*(hairline(role,a) if line is None else line(a))
    rays = np.stack((np.sin(a)*np.sin(theta),np.cos(theta),np.cos(a)*np.sin(theta)),axis=-1)
    radii = np.empty(rays.shape[:2])
    for i,v in enumerate(rays.reshape(-1,3)):
        loc, _, _, d = skull.ray_cast(Vector(pivot+.26*v),Vector(-v),.26)
        if loc is None:
            raise ValueError(f'{role}: hair guide missed the scalp at ring {i//slices} segment {i%slices}')
        radii.flat[i] = .26-d
    # Relax sampling from the old low-sided head, but not below its envelope.
    envelope = radii.copy()
    for _ in range(3):
        across = .5*(np.roll(radii,1,axis=1)+np.roll(radii,-1,axis=1))
        along = radii.copy(); along[1:-1] = .5*(radii[:-2]+radii[2:])
        radii = np.maximum(envelope-.0006, .45*radii+.35*across+.20*along)
    rest = pivot + rays*radii[...,None]
    relief, drift = shell_relief(role,rest,a,t) if shape is None else shape(rest,a,t)
    p = rest + rays*relief[...,None]
    p[...,0] += drift
    # Displace the hem just enough to bury a thin return under the skin, and
    # close the interior with an invisible fan. The crown is one manifold.
    inside = rest[-1] - .0045*rays[-1]
    tip = p[0].mean(axis=0)
    tip[1] += .0013 if role=='lead' else .00019
    base = pivot - [0.,.024,0.]
    p = np.concatenate((p.reshape(-1,3),inside,tip[None,:],base[None,:]))
    f = []
    top = (rings+1)*slices
    for j in range(slices):
        k = (j+1)%slices
        f.append((top,j,k))
        for r in range(rings):
            u,v = r*slices,(r+1)*slices
            f.extend(((u+j,v+j,v+k),(u+j,v+k,u+k)))
        f.append((top+1,rings*slices+k,rings*slices+j))
    f = np.asarray(f,dtype=np.int32)
    # The winding is checked by a signed volume, including the buried fan.
    a,b,c = p[f].transpose(1,0,2)-pivot
    if np.einsum('ij,ij->',a,np.cross(b,c)) < 0:
        f = f[:,[0,2,1]]
    return p,f


def n_bob_limits():
    """Keep N's established 13 mm envelope around the exact owner bob surface."""
    doc, data = decode((HERE.parent/'teacher-n/teacher-n_source.glb').read_bytes())
    original = {}
    for slot, name, p in io.primitives(doc):
        if name=='ST_Hair':
            s = Surface(doc,data,slot,name,p)
            _, kept = teacher_bob(s.p,s.triangles)
            original[s.mat['name']] = s.p[kept]
    return original


def keep_deforming_lids(surface, original, edited):
    """Keep the donor's moving eyelid loops and their immediate skin seam."""
    mesh = surface.doc['meshes'][surface.slot[0]]
    names = mesh.get('extras', {}).get('targetNames', ())
    frozen = np.zeros(len(original), dtype=bool)
    for name, target in zip(names, surface.part.get('targets', ()), strict=True):
        if name.startswith('Blink_'):
            frozen |= np.any(surface.read(target['POSITION']) != 0., axis=1)
    touched = frozen[surface.triangles].any(axis=1)
    frozen[surface.triangles[touched].ravel()] = True
    edited[frozen] = original[frozen]


def lid_islands(role, p, triangles):
    _, ex, ey, _, _ = LANDMARKS[role]
    lids = [ids for ids in components(p, triangles)
            if len(ids) == 88 and abs(abs(p[ids, 0].mean()) - ex) < .007
            and abs(p[ids, 1].mean() - ey) < .018]
    if len(lids) != 4:
        raise ValueError(f'{role}: expected four moving lid islands')
    return lids


def refit_marks(before, edited, skin_before, skin_after, triangles, *, relief=1.):
    """Follow the sculpted skin, optionally reducing a mark's old relief."""
    def depths(skin, marks):
        head = BVHTree.FromPolygons(skin.tolist(), triangles.tolist(), all_triangles=True)
        values = []
        for x, y, _ in marks:
            loc, _, _, _ = head.ray_cast(Vector((x, y, .30)), Vector((0., 0., -1.)), .25)
            if loc is None:
                raise ValueError('Brow or crease missed its fitted face')
            values.append(loc.z)
        return np.asarray(values)
    edited[:, 2] = depths(skin_after, edited) + relief * (edited[:, 2] - depths(skin_before, before))


def polish_bq(role, parts, skull):
    if role == 'q':
        skin = next(s for s in parts if s.mat['name'] == 'Q_Mat_Skin')
        skin_before = skin.output
        skin.output = q_cheek_and_mouth(skin_before)
        for ids in lid_islands(role, skin_before, skin.triangles):
            skin.output[ids] = seat_q_orbit(skin_before[ids])
        for s in parts:
            if s.node == 'Q_Hair':
                p, faces = fitted_shell('q', skull, line=q_cropped_fringe, shape=q_cropped_relief)
                if not np.array_equal(faces, s.remesh):
                    raise ValueError('Q fringe edit must keep the existing shell indices')
                peak = p[:, 1].max()
                p[:, 1] += (s.output[:, 1].max() - peak) * ease(peak - .07, peak, p[:, 1])
                s.output = p
            elif s.node == 'Q_Eyes':
                s.output = seat_q_orbit(s.output)
            elif s.mat['name'] == 'Q_Mat_MouthInner':
                s.output = q_cheek_and_mouth(s.output)
            elif s.mat['name'] == 'Q_Mat_Hair':
                marks = q_brows(s.output)
                refit_marks(s.output, marks, skin_before, skin.output, skin.triangles, relief=.82)
                s.output = marks
    elif role == 'b':
        flip = np.array([1., 1., -1.])
        skin = next(s for s in parts if s.node == 'Face and neck')
        skin_before = skin.output * flip
        skin_after = b_cheek_and_mouth(skin_before)
        keep_deforming_lids(skin, skin_before, skin_after)
        skin.output = skin_after * flip
        for s in parts:
            if s.mat['name'] == 'b_swept_silver':
                s.output = b_chignon(s.output * flip, s.output[:, 1].max()) * flip
            elif s.mat['name'] == 'b_brows_and_crease':
                before = s.output * flip
                marks = b_brows_and_folds(before)
                refit_marks(before, marks, skin_before, skin_after, skin.triangles)
                s.output = marks * flip


def within_original_bob(p, origin):
    delta = p - origin
    return origin + delta*np.minimum(1., .0128/np.maximum(1e-12,np.linalg.norm(delta,axis=1)))[:,None]


def polish_classroom(role, parts, original_bob):
    if role not in ('n', 'seated'):
        return
    teacher = role == 'n'
    sign = LANDMARKS[role][0]
    axes = np.array([1., 1., sign])
    skin = next(s for s in parts if (s.node, s.mat['name']) == (
        ('ST_Head_Skin', 'M_ST_Skin') if teacher else ('Head_Main_Mesh', 'WIS_Protagonist_Skin')))
    face_stroke = n_face if teacher else student_face
    brow_stroke = n_brow if teacher else student_brow
    skin_before = skin.output * axes
    skin_after = face_stroke(skin_before)
    skin.output = skin_after * axes
    scalp = None if teacher else BVHTree.FromPolygons(
        skin_after.tolist(), skin.triangles.tolist(), all_triangles=True)
    for s in parts:
        if s.output is None or s is skin:
            continue
        p = s.output * axes
        if teacher and s.node == 'ST_Hair':
            q = within_original_bob(n_bob(p) * axes, original_bob[s.mat['name']]) * axes
        elif not teacher and s.node.startswith('Hair_'):
            q = student_crop(p)
            if s.node == 'Hair_Cap':
                depth = q[:, 2].copy() - .004
                for i in np.flatnonzero((q[:, 2] > .034) & (abs(q[:, 0]) < .092)):
                    x, y, _ = q[i]
                    hit, _, _, _ = scalp.ray_cast(Vector((x, y, .30)), Vector((0., 0., -1.)), .29)
                    if hit is not None:
                        depth[i] = hit.z
                q = student_hair_clearance(q, depth)
            elif s.node == 'Hair_Back':
                q = student_nape(q)
            elif s.node.startswith(('Hair_Fringe_', 'Hair_Side_')):
                q = student_lock(q, s.node.startswith('Hair_Side_'))
        elif s.node.startswith('ST_Eyebrow_' if teacher else 'Eyebrow_'):
            q = brow_stroke(face_stroke(p))
            refit_marks(p, q, skin_before, skin_after, skin.triangles, relief=.80)
        elif teacher and s.node.startswith(('ST_Head_', 'ST_Eye_')):
            q = face_stroke(p)
        elif not teacher and s.node in ('Mouth_Line', 'Lower_Lip_Plane'):
            # Coherent with the skin brush, preserving the existing lip seam.
            q = face_stroke(p)
        else:
            continue
        s.output = q * axes


def sculpt(role, parts):
    sign = LANDMARKS[role][0]
    skull = None
    original_bob = n_bob_limits() if role=='n' else None
    if role in ('lead','q'):
        skin = next(s for s in parts if s.mat['name'].endswith('_Mat_Skin'))
        shaped = face(role,skin.p,'face')
        skull = BVHTree.FromPolygons(shaped.tolist(),skin.triangles.tolist(),all_triangles=True)
    for s in parts:
        kind = zone(role,s)
        if kind is None: continue
        p = s.p.copy(); p[:,2] *= sign
        density = None
        if s.mat['name']=='clipper_skin':
            c = s.part['attributes']['COLOR_0']
            density = s.read(c)[:,3]
            if s.doc['accessors'][c].get('normalized'):
                density /= {5121:255,5123:65535}[s.doc['accessors'][c]['componentType']]
        if kind=='hair' and skull is not None:
            q,s.remesh = fitted_shell(role,skull)
        elif kind=='hair':
            label = s.node if role=='seated' else s.mat['name']
            q = p.copy()
            for i, ids in enumerate(components(p,s.triangles)):
                q[ids] = other_hair(role,p[ids],label,i)
        else:
            # Inset student nostrils were not part of the first broad pass.
            q = p.copy() if role == 'seated' and s.node in STUDENT_NOSTRILS else face(role,p,kind,density)
            if role in ('lead','q') and s.mat['name'].endswith('_Mat_Skin'):
                for ids in lid_islands(role, p, s.triangles):
                    q[ids] = face(role,p[ids],'eye')
            elif role in ('thin','gentle','court','b'):
                keep_deforming_lids(s,p,q)
        q[:,2] *= sign
        if original_bob is not None and kind=='hair':
            q = within_original_bob(q, original_bob[s.mat['name']])
        s.output = q
    # Reproduce the earlier height correction before this pass. In particular,
    # it reached the upper scalp on the lead; editing only his hair must keep
    # all non-hair streams byte-identical to that study.
    old_peak = max(s.p[:,1].max() for s in parts)
    new_peak = max((s.p if s.output is None else s.output)[:,1].max() for s in parts)
    for s in parts:
        if s.output is not None and abs(new_peak-old_peak) > 1e-7:
            y = s.output[:,1]
            y += (old_peak-new_peak)*ease(new_peak-.070,new_peak,y)

    for s in parts:
        kind = zone(role,s)
        if role == 'lead':
            if s.node == 'Protagonist_Hair':
                s.output = lead_spikes(s.p,s.triangles)
                s.remesh = None
        elif kind in ('face','eye'):
            p = s.output.copy(); p[:,2] *= sign
            q = facial_details(role,p,kind)
            if role == 'q' and kind == 'face':
                q = q_closeup_planes(q, s.triangles, s.mat['name'] == 'Q_Mat_Skin')
            if role in ('thin','gentle','court','b'):
                keep_deforming_lids(s,p,q)
            q[:,2] *= sign
            s.output = q
    polish_bq(role, parts, skull)
    polish_classroom(role, parts, original_bob)


def material(s):
    info = s.mat['pbrMetallicRoughness']
    col = info.get('baseColorFactor',[1.,1.,1.,1.])
    key = s.mat['name']
    old = bpy.data.materials.get(key)
    if old: return old
    mat = bpy.data.materials.new(key)
    mat.diffuse_color = col
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = col
    bsdf.inputs['Roughness'].default_value = info.get('roughnessFactor',.78)
    bsdf.inputs['Alpha'].default_value = col[3]
    bsdf.inputs['Specular IOR Level'].default_value = .17
    if 'COLOR_0' in s.part['attributes']:
        v = mat.node_tree.nodes.new('ShaderNodeVertexColor')
        v.layer_name = 'Original pigment (linear)'
        mat.node_tree.links.new(v.outputs['Color'],bsdf.inputs['Base Color'])
    return mat


def mesh_study(role, s, col):
    sign = LANDMARKS[role][0]
    name = f'{role} | {s.node} · {s.mat["name"]}'
    coords, result = axes(s.p,sign), axes(s.output,sign)
    replacement = s.remesh is not None
    mesh = new_mesh(name,result if replacement else coords,s.remesh if replacement else s.triangles)
    obj = bpy.data.objects.new(name,mesh); col.objects.link(obj)
    mesh.materials.append(material(s))
    if 'COLOR_0' in s.part['attributes']:
        c = s.part['attributes']['COLOR_0']
        rgba = s.read(c)
        item = s.doc['accessors'][c]
        if item.get('normalized'):
            rgba /= {5121:255,5123:65535}[item['componentType']]
        if rgba.shape[1]==3:
            rgba = np.c_[rgba,np.ones(len(rgba))]
        attr = mesh.color_attributes.new('Original pigment (linear)','FLOAT_COLOR','POINT')
        attr.data.foreach_set('color', rgba.astype(np.float32).ravel())
    obj['role'],obj['mesh_index'],obj['surface'] = role,*s.slot
    obj['base_fingerprint'] = io.fingerprint(s.doc,s.blob,s.part)
    obj.location.z = 1.60 - LANDMARKS[role][2]
    if replacement:
        obj['remesh'] = True
        old_mesh = new_mesh(f'{name} | original',coords,s.triangles)
        old_mesh.materials.append(material(s))
        old = bpy.data.objects.new(old_mesh.name,old_mesh)
        col.objects.link(old)
        old.location = obj.location
        old.hide_set(True)
        old.hide_render = True
        return obj
    obj.shape_key_add(name='Basis',from_mix=False)
    brush = obj.shape_key_add(name='Sculpt',from_mix=False)
    brush.data.foreach_set('co',result.astype(np.float32).ravel())
    brush.value = 1.
    for target, channels in zip(s.doc['meshes'][s.slot[0]].get('extras',{}).get('targetNames',()),
                               s.part.get('targets',()), strict=True):
        layer = obj.shape_key_add(name=target,from_mix=False)
        # Store original offsets relative to Basis so Sculpt remains freely
        # editable without shifting expression deltas.
        layer.data.foreach_set('co',(coords+axes(s.read(channels['POSITION']),sign)).astype(np.float32).ravel())
    obj.active_shape_key_index = 1
    return obj


def make(directory, blend):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene['Workflow'] = 'Show one collection. Sculpt its Sculpt key (Basis stays untouched). Other keys preview the original expression deltas.'
    notes = bpy.data.texts.new('START HERE • Head geometry studies')
    notes.write('Where Is School — eight head studies\n\n'
                'Each performer has a collection with editable native mesh surfaces.\n'
                'Sculpt at 1 = revision; at 0 = original. Keep indexed topology.\n'
                'Lead uses the archived irregular spikes; Sculpt changes only the tip sweep.\n'
                'Q alone keeps the rebuilt shell; unhide the original for comparison.\n'
                'Expression keys are inherited offsets, not new actions. The game rigs live in the GLBs.\n'
                'Use make_sculpt.py --export after editing; see the versioned README.\n')
    active = None
    for role in io.RUNTIME:
        col = bpy.data.collections.new(role.upper())
        scene.collection.children.link(col)
        buckets = {}
        for kind in ('hair','face','eye','ear'):
            group = bpy.data.collections.new(f'{role.upper()} / {kind.title()}')
            col.children.link(group)
            buckets[kind] = group
        src = list(surfaces(directory,role))
        sculpt(role,src)
        for s in src:
            if s.output is not None:
                obj = mesh_study(role,s,buckets[zone(role,s)])
                if role=='lead' and s.node=='Protagonist_Hair':
                    active = obj
        for group in buckets.values():
            if not group.objects:
                bpy.data.collections.remove(group)
        bpy.context.view_layer.layer_collection.children[col.name].hide_viewport = role!='lead'
    if active:
        active.select_set(True); bpy.context.view_layer.objects.active = active
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type!='VIEW_3D': continue
            space = area.spaces.active
            space.overlay.show_overlays = False
            space.shading.color_type = 'MATERIAL'
            space.shading.show_cavity = True
            space.shading.cavity_type = 'WORLD'
            space.region_3d.view_location = (0.,-.038,1.623)
            space.region_3d.view_rotation = Vector((-.38,1.,-.094)).to_track_quat('-Z','Y')
            space.region_3d.view_distance = .46
            space.region_3d.view_perspective = 'ORTHO'
    bpy.context.preferences.filepaths.save_version = 0
    blend.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend.resolve()),compress=True)


def coords(vertices):
    values = np.empty(len(vertices)*3,dtype=np.float32)
    vertices.foreach_get('co',values)
    return values.reshape(-1,3)


def carried_normals(before, after, faces, authored):
    """Rotate authored split normals by Blender's actual local surface change."""
    a,b = (new_mesh('normal transport',p,faces) for p in (before,after))
    base = np.array([v.vector for v in a.vertex_normals])
    sculpted = np.array([v.vector for v in b.vertex_normals])
    out = authored.copy()
    changed = np.linalg.norm(base-sculpted,axis=1) > 2e-6
    for i in np.flatnonzero(changed):
        if min(np.linalg.norm(base[i]),np.linalg.norm(sculpted[i])) < .5:
            continue
        rotation = Vector(base[i]).rotation_difference(Vector(sculpted[i]))
        out[i] = rotation @ Vector(authored[i])
    bpy.data.meshes.remove(a); bpy.data.meshes.remove(b)
    return out


def export(directory, blend, layer_file):
    bpy.ops.wm.open_mainfile(filepath=str(blend.resolve()))
    layers = {}
    for role in io.RUNTIME:
        src = {s.slot:s for s in surfaces(directory,role) if zone(role,s)}
        edited = sorted((o for o in bpy.context.scene.objects if o.get('role')==role),
                        key=lambda o:(o['mesh_index'],o['surface']))
        slots = [(o['mesh_index'],o['surface']) for o in edited]
        if len(set(slots)) != len(slots) or set(slots) != src.keys():
            raise ValueError(f'{role}: missing or duplicated surfaces in Blender')
        layers[role] = []
        sign = LANDMARKS[role][0]
        for obj,slot in zip(edited,slots,strict=True):
            s = src[slot]
            basis_sha = io.fingerprint(s.doc,s.blob,s.part)
            if basis_sha!=obj['base_fingerprint']:
                raise ValueError(f'{obj.name} was authored against another basis')
            if obj.get('remesh'):
                obj.data.calc_loop_triangles()
                points = local(coords(obj.data.vertices),sign).astype('<f4')
                normal = local(np.array([v.vector for v in obj.data.vertex_normals]),sign).astype('<f4')
                indices = np.array([tuple(f.vertices) for f in obj.data.loop_triangles],dtype='<u2')
                if not np.isfinite(points).all() or len(points)>=65536 or len(indices)*3 != len(obj.data.loops):
                    raise ValueError(f'{obj.name}: hair shell must be finite indexed triangles')
                layers[role].append(io.record(s.slot,s.mesh,basis_sha,points.tobytes(),normal.tobytes(),indices.tobytes()))
                continue
            keys = obj.data.shape_keys.key_blocks
            before, after = (coords(keys[k].data) for k in ('Basis','Sculpt'))
            indices = np.empty(len(obj.data.loops),dtype=np.int32)
            obj.data.loops.foreach_get('vertex_index',indices)
            if not np.array_equal(before,axes(s.p,sign)) or not np.array_equal(indices,s.triangles.ravel()):
                raise ValueError(f'{obj.name}: Blender basis positions or triangles changed')
            if not np.isfinite(after).all():
                raise ValueError(f'{obj.name}: nonfinite vertex')
            if np.array_equal(before,after): continue
            normal = carried_normals(before,after,s.triangles,axes(s.n,sign))
            layers[role].append(io.record(s.slot,s.mesh,basis_sha,local(after,sign).astype('<f4').tobytes(),
                                          local(normal,sign).astype('<f4').tobytes()))
        print(f'Sculpted {role}: {len(layers[role])} indexed surfaces', flush=True)
    payload = json.dumps(dict(version=1,base=io.BASE,roles=layers),separators=(',',':')).encode('utf-8')
    with layer_file.open('wb') as output, gzip.GzipFile(filename='',fileobj=output,mode='wb',mtime=0) as gz:
        gz.write(payload)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bases',type=Path,required=True,help='directory of exact pre-sculpt role.glb inputs')
    parser.add_argument('--blend',type=Path,default=HERE/'Head_Studies.blend')
    parser.add_argument('--layers',type=Path,default=io.LAYERS)
    parser.add_argument('--export',action='store_true',help='bake existing Blender file instead of recreating brushes')
    args = parser.parse_args(argv)
    if bpy.app.version[:2] != (4,5):
        parser.error('Use Blender 4.5 LTS to bake reproducible sculpt normals')
    if not args.export:
        make(args.bases,args.blend)
    export(args.bases,args.blend,args.layers)


if __name__=='__main__':
    main(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
