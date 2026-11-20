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
from build_teacher_b import (Sculpt, bump, curve, rgb, rings_faces, smoothstep,
                             sphere, target, trigs, tube, unit)
from skinned_glb import GLB, batch_materials
from sculpt_hair import cap_samples, comb_field, shell_grid

from actions import bake
from designs import DESIGNS
from wardrobe import Wardrobe

MATS = {
    'skin_paint': (.91, 0., 1.), 'eye_paint': (.47, 0., 1.),
    'small_detail': (.84, 0., 1.), 'clipper_skin': (.94, 0., 1.),
    'hair_combed': (.88, 0., 1.), 'hair_crest': (.89, 0., 1.),
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
        mouth_axis = y.copy()
        if self.court:
            # Slight lateral smile on just one side of a closed mouth. Keep
            # pigment attached to the lip plane after sculpting its corner.
            corner = (.0038*bump(x, .021, .015) - .0011*bump(x, -.024, .014))
            corner *= bump(y, lip_y+.003, .016)*smoothstep(ez+.006, ez+.026, z)
            y += corner
            lip_plane = bump(x, .023, .017)*bump(y, lip_y+.007, .014)*front
            z += .0016*lip_plane
            mouth_axis = y-corner
        cheek = bump(abs(x), ex + .014, .025) * bump(y, ey - .033, .026)
        jaw = bump(abs(x), ex + .016, .020) * bump(y, ey - .066, .029) * front
        orbit = bump(abs(x), ex, .021) * bump(y, ey - .008, .013) * front
        temple = bump(abs(x), .067, .019) * bump(y, ey + .028, .038)
        forehead = bump(x, -.015, .049) * bump(y, ey + .050, .037)
        nose = bump(x, 0., .013) * bump(y, ey - .026, .030) * front
        neck_shade = 1. - smoothstep(neck + .036, neck + .115, y)
        c = rgb(d.skin) + .016 * trigs(p)[:, None]
        c += cheek[:, None] * ([.086, .020, .018] if self.gentle else [.047, .010, .016])
        c -= orbit[:, None] * ([.113, .104, .062] if self.thin else
                               [.064, .042, .031] if self.court else [.079, .062, .045])
        c -= jaw[:, None] * ([.067, .075, .046] if not self.gentle else [.013, .020, .015])
        c += temple[:, None] * [-.052, -.035, -.013]
        c += forehead[:, None] * [.057, .057, .049] + nose[:, None] * [.079, .038, .025]
        c -= neck_shade[:, None] * [.098, .099, .080]
        lip = (bump(mouth_axis, lip_y + .010, .008) * .64 + bump(mouth_axis, lip_y+.0006, .0043) * .67)
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
        if self.thin:
            c = self.clipper_stubble(p, c)
        self.add('Face and clipper scalp' if self.thin else 'Sculpted face and neck', p, fs, c,
                 'clipper_skin' if self.thin else 'skin_paint', skin, morphs)
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
            if self.court:
                key = unit(gaze + [-.130, .179, 0.])
                dot = (vv/rad) @ key
                fleck = smoothstep(.982,.998,dot)*.47
                c += (rgb('ead9c5') - c) * fleck[:,None]
            self.add(f'{side} iris and sclera', p, f, c, 'eye_paint', f'Eye_{side}')
            raised = (.0023 if self.court else .0019) if side == 'L' else -.0012
            arc = .001 if self.thin else .004 if self.gentle else .0062 if side=='L' else .001
            inner = .005 if self.thin else .001 if self.gentle else -.002 if side=='R' else -.0005
            tail = .0021 if self.court and side == 'L' else 0.
            xy = curve([(x-s*.019, y+.011+raised+inner), (x-s*.011, y+.016+raised+inner*.45),
                        (x+s*.003, y+.017+raised+arc), (x+s*.015, y+.017+raised+tail),
                        (x+s*.026, y+.009+raised+tail)], 6)
            q = self.facial_surface(xy)
            q[:, 2] += .0009
            t = np.sin(np.linspace(.16, math.pi-.16, len(q)))**.62
            p, f = tube(q, t*.00086, 8, t*(.00215 if self.thin else .00256 if self.court else .0030), reference=(0, 0, 1))
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
        back = smoothstep(-.14, -.93, front)
        if self.thin:
            # Tight temples and squared front corners. At the ears this is
            # clipped away, not a short wig rim hanging over the frames.
            return 1.48 - .389*front + .33*back + .037*np.cos(2*a+.27) + .009*np.cos(7*a+.5)
        if self.gentle:
            return 1.48 - .36*front + .30*back + .084*np.sin(3*a-.84) + .018*np.cos(6*a)
        return 1.47 - .32*front + .24*back + .070*np.cos(4*a-.2)

    def clipper_stubble(self, p, c):
        # Near-shaved hair belongs on the same scalp, not on a second cap.
        # Displace the actual crown by under 2 mm and paint a softly clipped
        # temple gradient. Alpha carries the follicle mask to Godot without
        # making the glTF material transparent.
        eye = np.mean(self.eyes, axis=0)
        center = np.array([0.,eye[1]+.015,eye[2]-.050])
        xx, yy, zz = (p-center).T
        angle = np.arctan2(zz,xx)
        reach = np.arctan2(np.hypot(xx,zz),yy)/self.hairline(angle)
        density = smoothstep(1.005,.46,reach)
        fleck = np.cos(1390*xx + 763*yy - 981*zz)*np.sin(947*xx - 567*yy + 1271*zz)
        relief = density*(.00165+.00017*fleck)
        p += (p-center)/np.maximum(np.linalg.norm(p-center,axis=1,keepdims=True),.001)*relief[:,None]
        a, b = (rgb(tone) for tone in self.design.hair)
        dark = a + (.50+.20*fleck)[:,None]*(b-a)
        amount = (.83+.065*fleck)*density
        tint = c + amount[:,None]*(dark-c)
        return np.column_stack((tint, density))

    def hair(self):
        if self.thin:
            return  # Clipper relief and pigment are part of the welded head.
        y = np.mean([e[1] for e in self.eyes])
        z = np.mean([e[2] for e in self.eyes])
        center = np.array([0., y+.015, z-.050])
        fitted = cap_samples(self, center, self.hairline, 24, 90)
        a, s, phi, rays, radius = fitted
        base = center + rays * radius[..., None]
        x, yy, zz = np.moveaxis(base, -1, 0)
        root, tip = (rgb(tone) for tone in self.design.hair)
        if self.gentle:
            ridges, fine, hatch = comb_field(rays, 14., .72, -.53, -.38)
            # A side part tilted into the forelock and lighter ridges following
            # its broad overlapping sweep, with only millimetres of relief.
            part = bump(x - .026 + .27*(zz-center[2]), 0., .0044)
            part *= smoothstep(y+.032, y+.072, yy)*smoothstep(center[2]-.024, center[2]+.027, zz)
            lift = (1.-smoothstep(.82, 1.66, phi))*smoothstep(.94, .67, s)
            volume = .0058 + lift*(.0061 + .0048*bump(a, 1.70, .65)*bump(s,.52,.37))
            relief = (ridges*.0016 + .00060*fine)*smoothstep(.038,.23,s)
            depth = -.0006 + smoothstep(1.,.922,s)*(volume + relief - .0041*part)
            tint = .28 + .22*ridges + .089*fine + .049*hatch + .089*lift
            pigment = root + tint[..., None]*(tip-root) + part[..., None]*[.035,.025,.023]
            name, material = 'Side-part crown / split comb ridges', 'hair_combed'
        else:
            # Short faded sides, brushed forward. Matched dark roots and red
            # tips inhabit the same shell so no rows of separate spikes float.
            ridges, fine, hatch = comb_field(rays, 16., -.49, .24, -.39)
            crest = bump(x - .13*(zz-center[2]) + .005, 0., .047) * smoothstep(y+.013,y+.078,yy)
            crest *= .64 + .36*smoothstep(center[2]-.075, center[2]+.074, zz)
            crest *= .78 + .22*bump(a,1.21,.65)*bump(s,.52,.38)
            relief = (ridges*.00315 + fine*.00064)*smoothstep(.02,.21,s)
            depth = -.0004 + smoothstep(1.,.931,s)*(.0028 + crest*(.030 + 1.7*relief) + .0006*ridges)
            dye = np.clip((.13+.67*smoothstep(.20,.71,crest))*(.80+.31*ridges+.11*fine) + .040*hatch, 0., .95)
            pigment = root + dye[..., None]*(tip-root)
            name, material = 'Dyed crest crown / taper and split forelocks', 'hair_crest'
        grid = shell_grid(center, fitted, depth)
        self.add_hair_shell(name, grid, pigment, material)
        if self.gentle:
            guides = [
                (((.08,.35),(.69,.43),(1.37,.59),(1.88,.81)), .0083,.0039),
                (((.14,.40),(.82,.50),(1.61,.68),(2.06,.93)), .0072,.0044),
                (((.17,.50),(.85,.57),(1.53,.77),(1.96,.98)), .0076,.0048),
                (((.30,.61),(.96,.70),(1.46,.82),(1.75,.985)), .0068,.0043),
                (((3.02,.34),(3.02,.50),(2.84,.74),(2.64,.97)), .0072,.0036),
            ]
            accent = [.074,.065,.079]
        else:
            guides = [
                (((.83,.40),(1.01,.43),(1.11,.58),(1.18,.80)), .0051,.0046),
                (((1.40,.32),(1.37,.45),(1.32,.61),(1.28,.78)), .0055,.0049),
                (((1.68,.31),(1.62,.44),(1.57,.56),(1.46,.82)), .0056,.0059),
                (((1.94,.35),(1.87,.46),(1.77,.62),(1.64,.81)), .0066,.0052),
                (((2.29,.44),(2.12,.53),(1.99,.63),(1.85,.78)), .0059,.0042),
                (((4.31,.42),(4.30,.62),(4.05,.72),(3.96,.91)), .0068,.0033),
            ]
            accent = [.14,.072,.047]
        self.add_hair_ribbons('Combed lock', center, grid, pigment, self.hairline, guides, material, accent)

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
