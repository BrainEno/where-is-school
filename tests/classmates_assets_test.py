#!/usr/bin/env python3
"""Audit the exported assets themselves, including sampled linear skinning."""
from pathlib import Path
import sys
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'art/character_models/classmates'))
from designs import ACTING, DESIGNS
from read_runtime_glb import Gltf

MODELS = ROOT/'assets/models/classmates'


class ClassmatesAssets(unittest.TestCase):
    def test_independent_skin_paint_and_size(self):
        width = []
        for key,design in DESIGNS.items():
            with self.subTest(key=key):
                path = MODELS/f'{key}.glb'
                self.assertLessEqual(path.stat().st_size,1536*1024)
                g = Gltf(path)
                self.assertNotIn('images',g.doc)
                skin, = g.doc['skins']
                joints = [g.doc['nodes'][n]['name'] for n in skin['joints']]
                self.assertEqual(len(joints),57)
                self.assertEqual(len(set(joints)),57)
                self.assertIn('Middle02_L',joints)
                self.assertFalse(any('matrix' in n or 'scale' in n for n in g.doc['nodes']))
                inverse = g.arr(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
                bind = np.array(g.world())[skin['joints']] @ inverse
                np.testing.assert_allclose(bind,np.broadcast_to(np.eye(4),bind.shape),atol=3e-7)
                for m in g.doc['meshes']:
                    for part in m['primitives']:
                        a = part['attributes']
                        self.assertTrue(np.isfinite(g.arr(a['POSITION'])).all())
                        self.assertTrue(np.isfinite(g.arr(a['NORMAL'])).all())
                        self.assertEqual(g.arr(a['COLOR_0']).shape[1],4)
                        w = g.arr(a['WEIGHTS_0'])
                        np.testing.assert_allclose(w.sum(1),1.,atol=4e-6)
                        self.assertEqual(w.shape[1],4)
                        self.assertLess(g.arr(a['JOINTS_0']).max(),57)
                face, = [m for m in g.doc['meshes'] if 'extras' in m]
                self.assertEqual(face['extras']['targetNames'],['Blink_L','Blink_R','SoftSmile','LipRelease'])
                pos = np.concatenate([p for _,p,*_ in g.surfaces()])
                self.assertAlmostEqual(pos[:,1].min(),0.,places=5)
                self.assertAlmostEqual(pos[:,1].max(),design.height,places=5)
                self.assertLess(pos[:,2].min(),-.11)  # shoes point along -Z
                width.append(np.ptp(pos[(pos[:,1]>.75*design.height) & (pos[:,1]<.8*design.height),0]))
                mats = {m['name']:m for m in g.doc['materials']}
                if key == 'court_classmate':
                    self.assertNotIn('optics',mats)
                else:
                    self.assertEqual(mats['optics']['alphaMode'],'BLEND')
                    self.assertLess(mats['optics']['pbrMetallicRoughness']['baseColorFactor'][3],.10)
        self.assertGreater(width[1]-width[0],.021)
        self.assertGreater(width[2]-width[1],.033)

    def test_scalp_mask_keeps_face_and_head_welded(self):
        g = Gltf(MODELS/'thin_classmate.glb')
        self.assertFalse(any(m['name'].startswith('hair_') for m in g.doc['materials']))
        face, = [m for m in g.doc['meshes'] if 'extras' in m]
        part, = face['primitives']
        material = g.doc['materials'][part['material']]
        self.assertEqual(material['name'], 'clipper_skin')
        self.assertEqual(material.get('alphaMode','OPAQUE'), 'OPAQUE')
        a = part['attributes']
        p, density = g.arr(a['POSITION']), g.arr(a['COLOR_0'])[:,3]
        self.assertGreater(density[p[:,1]>1.575].min(), .70)
        self.assertLess(density[p[:,1]<1.435].max(), .01)
        self.assertGreater(np.count_nonzero((density > .05) & (density < .95)), 150)
        self.assertEqual(len(part['targets']), 4)

    def test_welded_trousers_and_continuous_hip_blend(self):
        for key in DESIGNS:
            with self.subTest(key=key):
                g = Gltf(MODELS/f'{key}.glb')
                pants, = [part for mesh in g.doc['meshes'] for part in mesh['primitives']
                          if g.doc['materials'][part['material']]['name'] == 'woven_twill']
                a = pants['attributes']
                p, weights, joints = (g.arr(a[v]) for v in ('POSITION','WEIGHTS_0','JOINTS_0'))
                tris = g.arr(pants['indices']).reshape(-1,3)
                e = np.sort(np.vstack((tris[:,[0,1]],tris[:,[1,2]],tris[:,[0,2]])),axis=1)
                e, uses = np.unique(e,axis=0,return_counts=True)
                np.testing.assert_array_equal(uses, 2)  # no unwelded crotch or waist edges
                hip_id = next(i for i in g.doc['skins'][0]['joints'] if g.doc['nodes'][i]['name']=='Hips')
                hip = g.world()[hip_id][1,3]
                hip_weight = (weights*(joints==g.doc['skins'][0]['joints'].index(hip_id))).sum(1)
                y = p[e,1]
                transition = (y>hip-.182).all(1) & (y<hip+.08).all(1)
                distance = np.linalg.norm(p[e[:,0]]-p[e[:,1]],axis=1)
                self.assertGreater(distance.min(),.0003)
                slope = np.abs(hip_weight[e[:,0]]-hip_weight[e[:,1]])/distance
                self.assertLess(slope[transition].max(),16.)
                self.assertGreater(hip_weight[e[transition]].max(),.97)
                self.assertLess(hip_weight[e[transition]].min(),.80)
                self.assertLess(hip_weight[(p[:,1]>hip-.34) & (p[:,1]<hip-.26)].min(),.2)
                print(f'{key}: closed 2-manifold trousers, peak hip-weight gradient {slope[transition].max():.2f}/m')

    def test_foot_contact_and_signature(self):
        for key,(signature,apex) in ACTING.items():
            with self.subTest(key=key):
                g = Gltf(MODELS/f'{key}.glb')
                clips = {a['name']:a for a in g.doc['animations']}
                self.assertEqual(set(clips),{'idle','walk_in_place',signature})
                for clip,a in clips.items():
                    end = max(g.arr(s['input']).max() for s in a['samplers'])
                    low, peak, drift = 0.,0.,0.
                    reference = None
                    for t in np.linspace(0.,end,37):
                        sole, = [p for mat,p,*_ in g.surfaces(clip,t) if mat=='shoe_sole']
                        if reference is None:
                            reference = sole.copy()
                        for sign in (1.,-1.):
                            y = sole[sole[:,0]*sign>0.,1].min()
                            low, peak = min(low,y), max(peak,y)
                        drift = max(drift,np.linalg.norm(sole-reference,axis=1).max())
                    np.testing.assert_allclose(sole,reference,atol=.001)
                    if clip == 'walk_in_place':
                        self.assertGreater(peak,.033)
                        self.assertGreater(low,-.0075)  # sampled IK tolerances at 15 Hz
                    else:
                        self.assertLess(drift,.0015)
                    print(f'{key}/{clip}: sole height {low:+.4f}..{peak:+.4f} m; max displacement {drift:.4f} m')
                hand_name = 'Hand_L' if key=='gentle_classmate' else 'Hand_R'
                hand = next(i for i,n in enumerate(g.doc['nodes']) if n['name']==hand_name)
                before = g.world(g.frame(signature,0.))[hand][:3,3]
                after = g.world(g.frame(signature,apex))[hand][:3,3]
                movement = np.linalg.norm(before-after)
                self.assertGreater(movement, .31 if key=='gentle_classmate' else .10)
                if key == 'gentle_classmate':
                    w, = [n['weights'] for n in g.frame(signature,apex).values() if 'weights' in n]
                    self.assertGreater(w[2],.45)


if __name__ == '__main__':
    unittest.main()
