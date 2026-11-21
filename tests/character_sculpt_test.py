#!/usr/bin/env python3
"""Compare all eight sculpted exports to their exact pre-sculpt geometry."""
from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import character_sculpt as sculpt
from glb_io import accessor, decode, encode

# Guard the collar and wardrobe even on material-batched detail surfaces.
HEAD_FLOOR = dict(lead=1.458, q=1.532, n=1.419, seated=1.427, thin=1.367,
                  gentle=1.383, court=1.535, b=1.399)
HAIR = dict(lead='Protagonist_Hair', q='Q_Hair', n='ST_Hair', seated='Sphere.021',
            thin='Face and clipper scalp', gentle='hair_combed', court='hair_crest', b='b_swept_silver')
BLINK = {'Blink_L', 'Blink_R', 'Eye_Blink_L', 'Eye_Blink_R'}
MOUTH = {'MouthOpen', 'Mouth_Open', 'LipRelease'}
FACE = dict(lead='Protagonist_Head', q='Q_Head', n='ST_Head_Skin', seated='Head_Main_Mesh_Mesh',
            thin='Face and clipper scalp', gentle='Sculpted face and neck', court='Sculpted face and neck',
            b='Face and neck')
DETAIL_MESHES = {
    'lead': {HAIR['lead']},
    'q': {FACE['q'], 'Q_Eyes'},
    'n': {FACE['n'], 'ST_Eye_L', 'ST_Eye_R', 'ST_Eyebrow_L', 'ST_Eyebrow_R'},
    'seated': {FACE['seated'], 'Eyebrow_L_Curve', 'Eyebrow_R_Curve', 'Sphere.019', 'Sphere.020',
               'Upper_Eyelid_L_Curve', 'Upper_Eyelid_R_Curve', 'Mouth_Line_Curve', 'Lower_Lip_Plane_Curve'},
    'thin': {FACE['thin'], 'small_detail'},
    'gentle': {FACE['gentle'], 'small_detail'},
    'court': {FACE['court'], 'small_detail'},
    'b': {FACE['b'], 'b_brows_and_crease'},
}


def stream_bytes(doc, data, index):
    first, last = sculpt.span(doc, index)
    return data[first:last]


def view_bytes(doc, data, i):
    view = doc['bufferViews'][i]
    start = view.get('byteOffset', 0)
    return data[start:start+view['byteLength']]


def storage(acc):
    if 'bufferView' in acc:
        yield acc['bufferView']
    if 'sparse' in acc:
        for key in ('indices','values'):
            yield acc['sparse'][key]['bufferView']


def read(doc, data, index):
    return np.asarray(accessor(doc,data,index))


class HeadSculpts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bases = {role: subprocess.check_output(['git','show',f'{sculpt.BASE}:{sculpt.historic_path(role)}'],cwd=ROOT)
                     for role in sculpt.RUNTIME}
        cls.review_bases = {role: subprocess.check_output(
                                ['git','show',f'{sculpt.REVIEW_BASE}:{sculpt.historic_path(role)}'],cwd=ROOT)
                            for role in sculpt.RUNTIME}
        cls.outputs = {role:(ROOT/path).read_bytes() for role,path in sculpt.RUNTIME.items()}
        cls.layers = sculpt.read_layers()

    def test_reproducible_and_original_player_export_is_archived(self):
        self.assertEqual((sculpt.ART/'lead_basis.glb').read_bytes(),self.bases['lead'])
        for role,before in self.bases.items():
            with self.subTest(role=role):
                self.assertEqual(sculpt.apply(before,role),self.outputs[role])
                self.assertNotEqual(before,self.outputs[role])

    def test_stale_geometry_cannot_receive_the_baked_layer(self):
        doc,data = decode(self.bases['q'])
        prim = next(p for _,n,p in sculpt.primitives(doc) if n=='Q_Hair')
        start,_ = sculpt.span(doc,prim['attributes']['POSITION'])
        mutated = bytearray(data); mutated[start] ^= 2
        with self.assertRaisesRegex(ValueError,'no longer matches'):
            sculpt.apply(encode(doc,bytes(mutated)),'q')

    def test_untouched_skin_paint_morph_action_and_accessor_bytes(self):
        for role,base in self.bases.items():
            with self.subTest(role=role):
                a,ab = decode(base); b,bb = decode(self.outputs[role])
                if role=='seated':
                    self.assertNotIn('extensionsUsed',a)
                    self.assertEqual(b.pop('extensionsUsed'),['KHR_materials_specular'])
                skip = {'accessors','bufferViews','buffers'}
                self.assertEqual({k:v for k,v in a.items() if k not in skip},
                                 {k:v for k,v in b.items() if k not in skip})
                changed = {(v['mesh'],v['surface']) for v in self.layers[role]}
                streams = set()
                for slot,name,p in sculpt.primitives(a):
                    if slot in changed:
                        streams.update(p['attributes'][k] for k in ('POSITION','NORMAL'))
                        if name==sculpt.REMESH.get(role):
                            streams.update((p['indices'], p['attributes']['JOINTS_0'], p['attributes']['WEIGHTS_0']))
                for i,(x,y) in enumerate(zip(a['accessors'],b['accessors'],strict=True)):
                    if i not in streams:
                        self.assertEqual(x,y,(role,i))
                        for v in storage(x):
                            self.assertEqual(view_bytes(a,ab,v),view_bytes(b,bb,v),(role,i,v))

    def test_head_only_non_degenerate_geometry_and_unchanged_height(self):
        for role,base in self.bases.items():
            with self.subTest(role=role):
                a,ab = decode(base); b,bb = decode(self.outputs[role]); names = set()
                y_bounds = []
                for doc,data in ((a,ab),(b,bb)):
                    ys = np.concatenate([read(doc,data,p['attributes']['POSITION'])[:,1] for _,_,p in sculpt.primitives(doc)])
                    y_bounds.append((ys.min(),ys.max()))
                np.testing.assert_allclose(*y_bounds,rtol=0,atol=3e-7)
                for slot,name,p in sculpt.primitives(a):
                    x = read(a,ab,p['attributes']['POSITION']); y = read(b,bb,p['attributes']['POSITION'])
                    if np.array_equal(x,y): continue
                    names.add(name)
                    self.assertTrue(np.isfinite(y).all(),(role,name))
                    normals = read(b,bb,p['attributes']['NORMAL'])
                    np.testing.assert_allclose(np.linalg.norm(normals,axis=1),1.,rtol=0,atol=2e-5)
                    if name==sculpt.REMESH.get(role):
                        self.assertGreater(y[:,1].min(), HEAD_FLOOR[role])
                        continue
                    edited = np.linalg.norm(y-x,axis=1)>2e-7
                    self.assertGreater(x[edited,1].min(),HEAD_FLOOR[role],(role,name))
                    f = read(a,ab,p['indices']).reshape(-1,3)
                    old = np.cross(x[f[:,1]]-x[f[:,0]],x[f[:,2]]-x[f[:,0]])
                    new = np.cross(y[f[:,1]]-y[f[:,0]],y[f[:,2]]-y[f[:,0]])
                    stable = np.linalg.norm(old,axis=1)>1e-9
                    self.assertTrue((np.linalg.norm(new[stable],axis=1)>1e-11).all(),(role,name))
                    if name == FACE[role]:
                        self.assertTrue((np.sum(old[stable]*new[stable],axis=1)>0).all(),(role,name))
                self.assertIn(FACE[role],names)
                self.assertIn(HAIR[role],names)

    def test_inherited_face_keys_do_not_collapse_or_reverse_moving_triangles(self):
        active_roles = {'blink': set(), 'mouth': set()}
        for role,base in self.bases.items():
            a,ab = decode(base)
            b,bb = decode(self.outputs[role])
            for (mesh,_),_,p in sculpt.primitives(a):
                names = a['meshes'][mesh].get('extras', {}).get('targetNames', ())
                targets = dict(zip(names, p.get('targets', ()), strict=True))
                for state,expressions in (('blink', BLINK), ('mouth', MOUTH)):
                    keys = targets.keys() & expressions
                    if not keys:
                        continue
                    delta = np.sum([read(a,ab,targets[k]['POSITION']) for k in sorted(keys)], axis=0)
                    moving = np.linalg.norm(delta,axis=1) > 1e-6
                    if not moving.any():
                        continue
                    active_roles[state].add(role)
                    with self.subTest(role=role, mesh=mesh, state=state):
                        before = read(a,ab,p['attributes']['POSITION'])
                        after = read(b,bb,p['attributes']['POSITION'])
                        triangles = read(a,ab,p['indices']).reshape(-1,3)
                        triangles = triangles[moving[triangles].any(axis=1)]
                        for weight in (.25, .5, .75, 1.):
                            old,new = ((x + weight*delta)[triangles] for x in (before,after))
                            n0 = np.cross(old[:,1]-old[:,0],old[:,2]-old[:,0])
                            n1 = np.cross(new[:,1]-new[:,0],new[:,2]-new[:,0])
                            area = np.linalg.norm(n0,axis=1)
                            stable = area > 1e-9
                            self.assertTrue((np.linalg.norm(n1[stable],axis=1) > .5*area[stable]).all())
                            self.assertTrue((np.sum(n0[stable]*n1[stable],axis=1) > 0.).all())
        self.assertEqual(active_roles['blink'], {'lead','q','thin','gentle','court','b'})
        self.assertEqual(active_roles['mouth'], {'lead','q','thin','gentle','court'})

    def test_second_pass_only_touches_the_lead_hair_and_seven_faces(self):
        for role, base in self.review_bases.items():
            with self.subTest(role=role):
                a, ab = decode(base)
                b, bb = decode(self.outputs[role])
                changed = set()
                for (slot, name, p), (slot2, name2, q) in zip(
                        sculpt.primitives(a), sculpt.primitives(b), strict=True):
                    self.assertEqual((slot, name), (slot2, name2))
                    if any(stream_bytes(a, ab, p['attributes'][k]) != stream_bytes(b, bb, q['attributes'][k])
                           for k in ('POSITION', 'NORMAL')):
                        changed.add(name)
                        if role != 'lead':
                            before = read(a, ab, p['attributes']['POSITION'])
                            after = read(b, bb, q['attributes']['POSITION'])
                            self.assertEqual(before.shape, after.shape)
                            self.assertLess(np.linalg.norm(after-before, axis=1).max(), .005, (role, name))
                        if role == 'thin' and name == FACE[role]:
                            crown = before[:, 1] >= 1.528
                            np.testing.assert_array_equal(before[crown], after[crown])
                self.assertEqual(changed, DETAIL_MESHES[role])

    def test_details_keep_every_supported_expression_on_the_previous_rig(self):
        for role, base in self.review_bases.items():
            if role == 'lead':
                continue
            a, ab = decode(base)
            b, bb = decode(self.outputs[role])
            for (slot, name, p), (_, _, q) in zip(sculpt.primitives(a), sculpt.primitives(b), strict=True):
                keys = a['meshes'][slot[0]].get('extras', {}).get('targetNames', ())
                if not keys:
                    continue
                before = read(a, ab, p['attributes']['POSITION'])
                after = read(b, bb, q['attributes']['POSITION'])
                triangles = read(a, ab, p['indices']).reshape(-1, 3)
                for key, target in zip(keys, p.get('targets', ()), strict=True):
                    delta = read(a, ab, target['POSITION'])
                    moving = (np.linalg.norm(delta, axis=1) > 1e-6)[triangles].any(axis=1)
                    if not moving.any():
                        continue
                    faces = triangles[moving]
                    for weight in (.25, .5, .75, 1.):
                        with self.subTest(role=role, surface=name, key=key, weight=weight):
                            old, new = ((x + weight*delta)[faces] for x in (before, after))
                            n0 = np.cross(old[:, 1]-old[:, 0], old[:, 2]-old[:, 0])
                            n1 = np.cross(new[:, 1]-new[:, 0], new[:, 2]-new[:, 0])
                            area = np.linalg.norm(n0, axis=1)
                            stable = area > 1e-9
                            self.assertTrue((np.linalg.norm(n1[stable], axis=1) > .5*area[stable]).all())
                            self.assertTrue((np.sum(n0[stable]*n1[stable], axis=1) > 0.).all())

    def test_q_crown_is_a_single_closed_head_bound_shell(self):
        self.assertEqual(sculpt.REMESH, {'q': 'Q_Hair'})
        for role,name in sculpt.REMESH.items():
            with self.subTest(role=role):
                doc,data = decode(self.outputs[role])
                slot, _, p = next(item for item in sculpt.primitives(doc) if item[1]==name)
                a = p['attributes']; x = read(doc,data,a['POSITION'])
                f = read(doc,data,p['indices']).reshape(-1,3)
                edges = np.sort(np.concatenate((f[:,[0,1]],f[:,[1,2]],f[:,[2,0]])),axis=1)
                e,uses = np.unique(edges,axis=0,return_counts=True)
                np.testing.assert_array_equal(uses,2)
                self.assertEqual(len(x)-len(e)+len(f),2)
                reached = {int(f[0,0])}; adjacent = [set() for _ in x]
                for u,v in e:
                    adjacent[u].add(v);adjacent[v].add(u)
                pending = list(reached)
                while pending:
                    new = adjacent[pending.pop()]-reached
                    reached.update(new);pending.extend(new)
                self.assertEqual(len(reached),len(x))
                t = x[f] - x.mean(axis=0)
                c = np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0])
                self.assertGreater(np.linalg.norm(c,axis=1).min(),2e-9)
                self.assertGreater(np.sum(c*t[:,0]),0.)
                bone_ids = read(doc,data,a['JOINTS_0']); weights = read(doc,data,a['WEIGHTS_0'])
                np.testing.assert_array_equal(weights,np.tile([1.,0.,0.,0.],(len(x),1)))
                instance = next(n for n in doc['nodes'] if n.get('mesh')==slot[0])
                joints = doc['skins'][instance['skin']]['joints']
                self.assertEqual({doc['nodes'][joints[i]]['name'] for i in bone_ids[:,0]}, {'Head'})


if __name__=='__main__':
    unittest.main(verbosity=2)
