#!/usr/bin/env python3
"""Sculpt, paint and export three original classmates using only CC0 donor data.

See README.md for the pinned MakeHuman inputs. The wardrobe and hair are new
geometry; no mesh, texture, motion or likeness from another character is copied.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path
import sys

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent / 'teacher_b'))
from build_teacher_b import (Sculpt, bump, cap_ends, curve, rgb, rings_faces, smoothstep,
                             sphere, target, trigs, tube, unit)
from skinned_glb import GLB, batch_materials

from actions import bake
from designs import DESIGNS
from wardrobe import Wardrobe

MATS = {
    'skin_paint': (.91, 0., 1.), 'eye_paint': (.47, 0., 1.),
    'small_detail': (.84, 0., 1.), 'hair_paint': (.83, 0., 1.),
    'frames': (.54, .09, 1.), 'optics': (.23, 0., .054),
    'cotton': (.95, 0., 1.), 'ribbed_knit': (.96, 0., 1.),
    'woven_twill': (.95, 0., 1.), 'cloth_trim': (.88, 0., 1.),
    'shoe_upper': (.78, 0., 1.), 'shoe_sole': (.91, 0., 1.),
}
SIDES = ('L', 'R')
SIGNS = (1, -1)
DIGITS = ('Thumb', 'Index', 'Middle', 'Ring', 'Little')
EXPR = 'expression/units/asian/'
TAU = 2. * math.pi


class Classmate(Sculpt):
    def __init__(self, data, key):
        self.key = key
        self.design = DESIGNS[key]
        self.thin = key == 'thin_classmate'
        self.gentle = key == 'gentle_classmate'
        self.court = key == 'court_classmate'
        super().__init__(data)

    def shape(self):
        d = self.design
        self.apply('macrodetails/asian-male-young', 1.)
        for f, amount in d.body_mix:
            # The mean physique is the donor's zero-delta (empty target).
            if f != 'averagemuscle-averageweight':
                self.apply(f'macrodetails/universal-male-young-{f}', amount)
        for name, amount in d.head_targets.items():
            self.apply(name, amount)
        for side in ('l', 'r'):
            self.apply(f'cheek/{side}-cheek-{d.cheek[0]}', d.cheek[1])
            ear = 'incr' if d.ear > 0. else 'decr'
            self.apply(f'ears/{side}-ear-wing-{ear}', abs(d.ear))
        body = self.v[np.unique(self.f['body'])]
        low, high = body[:, 1].min(), body[:, 1].max()
        self.metre = (d.height - d.crown_room) / (high - low)
        self.v *= self.metre
        self.v[:, 1] += .022 - low * self.metre
        x, y, z = self.v.T
        u = y / d.height
        x *= 1. + (d.body_width - 1.) * bump(u, .728, .16)
        # A natural, close but not overlapping stance. The basketball player's
        # stance is wider at the foot, not stretched uniformly across the hips.
        x *= 1. + (-.36 if self.thin else -.40 if self.gentle else -.26) * (1. - smoothstep(.15, .56, u))
        z += d.head_lead * smoothstep(.66, .91, u)
        if self.thin:
            # Long narrow lower face, pronounced pinnae and more forward carriage.
            chin = bump(u, .882, .031) * smoothstep(.055, .147, z)
            x *= 1. - .13 * chin
            y -= .0079 * chin
        elif self.gentle:
            mass = bump(u, .92, .029) * smoothstep(.050, .083, z)
            x *= 1. + .044 * mass
            z += .0048 * mass * bump(abs(x), .047, .034)
        else:
            # Sharper cheek planes instead of a smile or a theatrical scowl.
            cheek = bump(u, .911, .020) * bump(abs(x), .058, .031)
            z += .0039 * cheek * smoothstep(.033, .098, z)
            x *= 1. - .066 * bump(u, .894, .018) * smoothstep(.047, .125, z)
        # One side of the mouth/upper cheek rests a few millimetres differently.
        asym = .0019 if self.thin else .0014 if self.gentle else .0024
        y += asym * np.tanh(88. * x) * bump(u, .90, .038) * smoothstep(.032, .087, z)
        self._neutral_arms()

    def arm_weights(self, y, side):
        sh, el, wr = (self.bones[f'{j}_{side}'][1][1] for j in ('UpperArm', 'Forearm', 'Hand'))
        w = self.weights(len(y), f'Hand_{side}')
        wrist = smoothstep(wr-.011, wr+.043, y)
        elbow = smoothstep(el-.042, el+.034, y)
        shoulder = smoothstep(sh-.027, sh+.063, y)
        w[:, self.ids[f'Hand_{side}']] = 1.-wrist
        w[:, self.ids[f'Forearm_{side}']] = wrist-elbow
        w[:, self.ids[f'UpperArm_{side}']] = elbow-shoulder
        w[:, self.ids['Chest']] = shoulder
        return w

    def skin(self):
        d = self.design
        neck = self.bones['Neck'][1][1]
        head, fs = self.extract((self.v[:, 1] > neck - .045) & (abs(self.v[:, 0]) < .113))
        p = self.v[head].copy()
        x, y, z = p.T
        # Hide the neck cut below each collar while keeping the natural jaw.
        blend = 1. - smoothstep(neck + .004, neck + .040, y)
        n = self.bones['Neck'][1]
        x[:] = x*(1. - .28*blend) * (1. - .37*blend*smoothstep(.047, .091, abs(x)))
        z[:] += (n[2] + .025 - z) * blend * .43
        self.face_points, self.face_faces = p, fs
        ex, ey, ez = np.mean(np.abs(self.eyes), axis=0)
        m = np.linalg.norm(target(self.root, 'mouth/mouth-lowerlip-volume-decr', self.n), axis=1)
        lip_y = np.average(self.v[:, 1], weights=m)
        front = smoothstep(ez - .031, ez + .001, z)
        cheek = bump(abs(x), ex + .014, .025) * bump(y, ey - .033, .026)
        jaw = bump(abs(x), ex + .016, .020) * bump(y, ey - .066, .029) * front
        orbit = bump(abs(x), ex, .021) * bump(y, ey - .008, .013) * front
        temple = bump(abs(x), .067, .019) * bump(y, ey + .028, .038)
        forehead = bump(x, -.015, .049) * bump(y, ey + .050, .037)
        nose = bump(x, 0., .013) * bump(y, ey - .026, .030) * front
        neck_shade = 1. - smoothstep(neck + .036, neck + .115, y)
        c = rgb(d.skin) + .016 * trigs(p)[:, None]
        c += cheek[:, None] * ([.086, .020, .018] if self.gentle else [.047, .010, .016])
        c -= orbit[:, None] * ([.113, .104, .062] if self.thin else [.079, .062, .045])
        c -= jaw[:, None] * ([.067, .075, .046] if not self.gentle else [.013, .020, .015])
        c += temple[:, None] * [-.052, -.035, -.013]
        c += forehead[:, None] * [.057, .057, .049] + nose[:, None] * [.079, .038, .025]
        c -= neck_shade[:, None] * [.098, .099, .080]
        lip = (bump(y, lip_y + .010, .008) * .64 + bump(y, lip_y+.0006, .0043) * .67)
        lip *= bump(x, .0016, .0225) * smoothstep(ez+.023, ez+.056, z)
        lip = np.clip(lip, 0., .80)
        c += (rgb(d.lip) - c) * lip[:, None]
        c -= (front * bump(y, lip_y - .011, .007) * bump(x, .001, .026))[:, None] * [.036, .045, .027]
        c -= (front * bump(y, ey-.034, .0038) * bump(abs(x), .0072, .0034))[:, None] * [.061,.078,.059]
        # Irregular faint cheek speckles, not a random raster pasted on the face.
        speckle = smoothstep(.69, .91, np.sin(x*435+z*222)*np.cos(y*479+z*113))
        c -= (cheek * speckle)[:, None] * [.059, .049, .032]
        skin = self.axial_weights(p, ['Chest', 'Neck', 'Head'], [neck-.047, neck+.005, neck+.069])
        j = self.masks(['jaw'])[head] * .78
        skin *= 1. - j[:, None]
        skin[:, self.ids['Jaw']] = j
        morphs = {
            name: target(self.root, EXPR + shape, self.n)[head] * self.metre * strength
            for name, shape, strength in (
                ('Blink_L', 'eye-left-closure', .89), ('Blink_R', 'eye-right-closure', .89),
                ('SoftSmile', 'mouth-corner-puller', .67), ('LipRelease', 'mouth-open', .26),
            )
        }
        self.add('Sculpted face and neck', p, fs, c, 'skin_paint', skin, morphs)
        for side in SIDES:
            shoulder, elbow, wrist = (self.bones[f'{b}_{side}'][1] for b in ('UpperArm', 'Forearm', 'Hand'))
            arm = self.masks([g for g in self.source_weights if g.endswith('.' + side) and
                              g.startswith(('upperarm', 'lowerarm', 'wrist', 'finger', 'metacarpal'))])
            cuff = (shoulder[1]-.126 if self.court else elbow[1]+.035 if self.gentle else wrist[1]-.011)
            ix, faces = self.extract((arm > .54) & (self.v[:, 1] < cuff + .038))
            q = self.v[ix]
            fingers = np.zeros((len(ix), len(self.bones)))
            for number, digit in enumerate(DIGITS, 1):
                for part in (1, 2, 3):
                    fingers[:, self.ids[f'{digit}{part:02}_{side}']] = self.masks([f'finger{number}-{part}.{side}'])[ix]
            w = self.arm_weights(q[:, 1], side) * (1. - np.minimum(1., fingers.sum(1))[:, None]) + fingers
            color = rgb(d.skin) - [.028, .025, .026] + trigs(q)[:, None] * [.025, .022, .016]
            color += bump(q[:, 1], elbow[1] - .017, .028)[:, None] * [.025, -.018, -.012]
            # Nail plates and warm knuckles are painted on the articulated donor
            # surface; the bony ridge/skin at the wrist isn't a cylindrical end.
            for digit in DIGITS:
                _, k, tip = self.bones[f'{digit}03_{side}']
                kn = self.bones[f'{digit}02_{side}'][1]
                nail = k + .64 * (tip - k)
                color += bump(np.linalg.norm(q-nail, axis=1), .0035, .0048)[:, None] * [.030, .018, .017]
                color -= bump(np.linalg.norm(q-kn, axis=1), .006, .007)[:, None] * [.016, .026, .013]
            self.add(f'{side} articulated skin', q, faces, color, 'skin_paint', w)

    def face_details(self):
        d = self.design
        for side, s, eye in zip(SIDES, SIGNS, self.eyes):
            x, y, z = eye
            rad = .0129 if self.thin else .0132 if self.gentle else .0133
            actual = eye + [s*.0002, .0004, .0021 if self.court else .0025]
            p, f = sphere(actual, [rad]*3, 17, 36)
            vv = p - actual
            gaze = unit(np.array([*d.gaze, 1.]))
            look = vv @ gaze
            r = np.sqrt(np.maximum(0., (vv*vv).sum(1) - look**2))
            iris = (1.-smoothstep(.0055, .0068, r)) * (look > .006)
            pupil = (1.-smoothstep(.0029, .0037, r)) * (look > .007)
            hue = '52382d' if self.thin else '4d3930' if self.gentle else '46312b'
            veins = .018 * np.cos(29. * np.arctan2(vv[:, 1], vv[:, 0]))
            rim = smoothstep(.0048, .0064, r)
            tint = rgb(hue) + (veins - .084*rim)[:, None]
            white = rgb('ddd2bd') + (vv[:, 1] / rad)[:, None] * .026
            c = white * (1.-iris[:, None]) + tint * iris[:, None]
            c += (rgb('1d1920') - c) * pupil[:, None]
            self.add(f'{side} iris and sclera', p, f, c, 'eye_paint', f'Eye_{side}')
            raised = .0019 if side == 'L' else -.0012
            arc = .001 if self.thin else .004 if self.gentle else .005 if side=='L' else -.001
            inner = .005 if self.thin else .001 if self.gentle else -.001
            xy = curve([(x-s*.019, y+.011+raised+inner), (x-s*.011, y+.016+raised+inner*.45),
                        (x+s*.003, y+.017+raised+arc), (x+s*.015, y+.017+raised),
                        (x+s*.026, y+.009+raised)], 6)
            q = self.facial_surface(xy)
            q[:, 2] += .0009
            t = np.sin(np.linspace(.16, math.pi-.16, len(q)))**.62
            p, f = tube(q, t*.00086, 8, t*(.00215 if self.thin else .0030), reference=(0, 0, 1))
            self.add(f'{side} individually arced brow', p, f, d.brows, 'small_detail', 'Head', grain=.035)
            # Very faint orbital relief ends before the lens rim.
            xy = curve([(x+s*.011, y-.010), (x+s*.020, y-.0116), (x+s*.023, y-.014)], 5)
            q = self.facial_surface(xy)
            q[:, 2] += .00013
            t = np.sin(np.linspace(.11, math.pi-.11, len(q)))
            p, f = tube(q, t*(.00040 if self.thin else .00028), 6)
            self.add(f'{side} lower orbital bend', p, f, rgb(d.skin)-[.11, .095, .067], 'small_detail', 'Head')
        if self.court:
            # Single aged-steel sleeper placed on the actual ear lobe.
            a = self.face_points
            ey = self.eyes[0][1]
            ear = a[(a[:, 0] > .061) & (a[:, 1] > ey-.050) & (a[:, 1] < ey-.029)]
            if not len(ear):
                raise ValueError('The earring misses its ear')
            pivot = ear[ear[:, 0].argmax()] + [.0003, -.0038, .001]
            t = np.linspace(0, TAU, 34, endpoint=False)
            p, f = tube(pivot + np.column_stack((.0018*np.cos(t), .0063*np.sin(t), .0053*np.cos(t))),
                        .00124, 8, closed=True, reference=(1, 0, 0))
            self.add('One small steel sleeper', p, f, 'aaa293', 'frames', 'Head')

    def spectacles(self):
        if self.court:
            return
        wire = self.thin
        tone, hardware = ('62605d', 'b2a38f') if wire else ('242327', '7e7370')
        rim = ([(-.024, .008), (-.017, .017), (.012, .018), (.025, .010),
                (.025, -.006), (.015, -.015), (-.012, -.016), (-.023, -.010)] if wire else
               [(-.030, .012), (-.024, .018), (.019, .019), (.031, .012),
                (.028, -.011), (.018, -.018), (-.020, -.019), (-.029, -.010)])
        ey = float(np.mean([e[1] for e in self.eyes]))
        bridge = []
        for side, s, eye in zip(SIDES, SIGNS, self.eyes):
            x = abs(eye[0]) + (.0024 if wire else .0035)
            y = ey - (.0048 if wire else .0026)
            q = curve([(s*(x+dx), y+dy+.032*dx) for dx, dy in rim], 7, True)
            z = eye[2] + .029 + (.0012 if not wire else 0.) - .094*(np.abs(q[:, 0])-x)
            outline = np.column_stack((q, z))
            r = .00140 if wire else .00269
            p, f = tube(outline, r, 9, r*.88, True, (0, 0, 1))
            self.add(f'{side} beveled spectacle rim', p, f, tone, 'frames', 'Head', grain=.023)
            mid = outline.mean(0)
            lens = np.vstack((outline - [0., 0., .0005], mid + .51*(outline-mid)+[0., 0., .0009],
                              mid+[0., 0., .00145]))
            n = len(outline)
            f = np.vstack((rings_faces(2, n), [(n+i, n+(i+1)%n, 2*n) for i in range(n)]))
            self.add(f'{side} clear optical shell', lens, f if s < 0 else f[:, ::-1],
                     'c6d3d3', 'optics', 'Head')
            bridge.append(outline[np.argmin(abs(outline[:, 0]) + 1.5*abs(outline[:, 1]-(y + .005)))])
            outer = outline[np.argmax(abs(outline[:, 0]) + .21*(outline[:, 1]-y))]
            tx = max(.070, s * outer[0] + .006)
            to = [s*(tx-.003), y-.009, eye[2]-.104]
            stem = curve([outer, outer+[s*.005, .001, -.008], [s*tx, y+.008, eye[2]-.035],
                          [s*tx, y+.004, eye[2]-.074], to], 6)
            p, f = tube(stem, np.linspace(r*1.19, r*.83, len(stem)), 8, reference=(0, 1, 0))
            self.add(f'{side} folded temple', p, f, tone, 'frames', 'Head', grain=.028)
            for i in range(2 if not wire else 1):
                q = outer + [s*(.001+i*.0024), .0009+i*.0012, r*.92]
                p, f = sphere(q, [.00092, .00086, .00063], 6, 12)
                self.add(f'{side} hinge rivet {i}', p, f, hardware, 'frames', 'Head')
            if wire:
                ct = bridge[-1] + [-s*.004, -.004, -.005]
                p, f = sphere(ct, [.0023, .0046, .0020], 9, 16)
                self.add(f'{side} saddle pad', p, f, 'ab9281', 'frames', 'Head')
        a, b = bridge
        y = ey + (.003 if wire else .006)
        z = max(self.facial_surface([[0., y]])[0, 2]+.0036, (a[2]+b[2])*.5-.0006)
        p, f = tube(curve([a, [.005, y-.001, z], [0., y, z+.0011], [-.005, y-.001, z], b], 5),
                    .00157 if wire else .00234, 9)
        self.add('Bowed spectacle bridge', p, f, tone, 'frames', 'Head', grain=.020)

    def hairline(self, a):
        front = np.sin(a)
        back = smoothstep(-.12, -.91, front)
        if self.thin:
            return 1.53 - .33*front + .33*back + .128*np.cos(2*a+.95) + .046*np.cos(7*a+.5)
        if self.gentle:
            return 1.52 - .35*front + .30*back + .09*np.sin(3*a-.88) + .019*np.cos(6*a)
        return 1.54 - .41*front + .27*back + .05*np.cos(4*a-.2)

    def hair(self):
        y = np.mean([e[1] for e in self.eyes])
        z = np.mean([e[2] for e in self.eyes])
        center = np.array([0., y+.015, z-.050])
        sides = 76
        a = np.linspace(0, TAU, sides, endpoint=False)[None, :]
        s = np.linspace(1., .014, 23)[:, None]
        phi = self.hairline(a)*s
        radius = self.scalp_rays(center, self.directions(a, phi)).reshape(phi.shape)
        phase = (24.9*phi + 16.6*np.cos(a+.55*phi) + np.sin(4*a+phi)*1.3)
        grooves = (.5+.5*np.cos(phase))**5
        top = .006 + (.006 if self.thin else .008 if self.gentle else .017) * np.cos(phi)**4
        if self.court:
            # A dark cropped underlayer becomes the red ridge rather than a wig.
            top *= .24 + .76 * smoothstep(1.21, .51, phi)
            top *= .74 + .36 * np.sin(a+.83)*np.sin(phi)
        thickness = .0016 + (top+.0018*grooves) * smoothstep(1.024, .87, s)
        xyz = center + self.directions(a, phi)*(radius+thickness).ravel()[:, None]
        p, f = cap_ends(xyz, rings_faces(len(s), sides, flip=True), len(s), sides, True)
        crest = smoothstep(1.24, .46, phi) if self.court else .48 + .34*np.cos(phi)**2
        full = np.clip(crest*(.72+.18*np.cos(phase)+.10*np.cos(2*phase)), 0., .96)
        tint = rgb(self.design.hair[0]) + np.r_[full.ravel(), .20, .62][:, None] * (
            rgb(self.design.hair[1]) - rgb(self.design.hair[0]))
        self.add('Sculpted crown with swept channels', p, f, tint, 'hair_paint', 'Head', grain=.018)
        # Separate hand-arranged tapering locks cross the cap. The shallow ends
        # bury in the cap; they are not a ring of identical exposed spikes.
        starts = ([-.18, .03, .28, .55, .82, 1.16, 1.46, 1.73] if self.thin else
                  [.42, .72, 1.02, 1.30, 1.62, 1.94] if self.gentle else
                  [-.24, .10, .36, .65, .92, 1.17, 1.47, 1.83])
        for i, start in enumerate(starts):
            if self.court:
                data = [(start-.08, .69), (start+.16, .40), (start+.40, .24), (start+.64, .55)]
                heights = [.0016, .014+.0029*(i%3), .024+.0039*(i%4), .009]
                widths = .0091+.0008*(i%3)
            elif self.thin:
                data = [(start, .42), (start+.29, .58), (start+.56, .81), (start+.81, .98+.025*(i%3))]
                heights = [.0041, .011+.002*(i%2), .0068, -.0005]
                widths = .0067+.001*(i%3)
            else:
                data = [(start, .28), (start+.17, .50), (start+.37, .69), (start+.48, .91)]
                heights = [.0052, .011, .0082, .0014]
                widths = .0084
            rows = curve([(a, t, h) for (a, t), h in zip(data, heights)], 6)
            a, s, h = rows.T
            dr = self.directions(a, self.hairline(a)*s)
            path = center + dr * (self.scalp_rays(center, dr)+h)[:, None]
            t = np.sin(np.linspace(.14, math.pi-.077, len(path)))**.7
            p, f = tube(path, t*widths*.59, 9, t*widths, reference=unit(dr[len(dr)//2]))
            shade = .44+.12*(i%3)+(.17 if self.court else 0.)
            c = rgb(self.design.hair[0]) + shade*(rgb(self.design.hair[1])-rgb(self.design.hair[0]))
            self.add(f'Combed lock {i+1:02}', p, f, c, 'hair_paint', 'Head', grain=.025)

    @staticmethod
    def directions(a, phi):
        return np.stack((np.sin(phi)*np.cos(a), np.cos(phi), np.sin(phi)*np.sin(a)), axis=-1).reshape(-1, 3)

    def build(self, output, split=None):
        self.skin()
        self.face_details()
        self.spectacles()
        self.hair()
        Wardrobe(self).build()
        for out, parts in [(output, batch_materials(self.pieces)), (split, self.pieces)]:
            if out is not None:
                materials = {m: spec for m, spec in MATS.items() if any(p.material == m for p in parts)}
                GLB().write(out, parts, self.bones, materials, self.design.height, self.design.label,
                            compact=split != out, animate=lambda writer, doc: bake(self.key, writer, doc))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--makehuman-data', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, default=ROOT/'assets/models/classmates')
    parser.add_argument('--split-dir', type=Path, help='Optional editable GLBs with named separate parts')
    parser.add_argument('--only', choices=DESIGNS)
    args = parser.parse_args()
    for key in ([args.only] if args.only else DESIGNS):
        split = args.split_dir/f'{key}_parts.glb' if args.split_dir else None
        Classmate(args.makehuman_data, key).build(args.output_dir/f'{key}.glb', split)


if __name__ == '__main__':
    main()
