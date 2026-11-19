#!/usr/bin/env python3
"""Editable modelling source for the off-stage Teacher B candidate.

Build with Python/NumPy and the pinned MakeHuman (CC0 data only) archive described
in README.md. No image, scan, original manuscript or other game character is
sampled. The donor's skin topology and joint masks are shaped in measure space;
its helper, clothing, UV/texture and animation assets are not exported.
"""

import argparse
import json
import math
from collections import defaultdict
from pathlib import Path

import numpy as np

from skinned_glb import GLB, Piece, batch_materials, unit

PI = np.pi
MATS = {
    'b_skin': (.86, 0., 1.), 'b_brows_and_crease': (.89, 0., 1.),
    'b_eye': (.46, 0., 1.), 'b_swept_silver': (.87, 0., 1.),
    'b_tortoiseshell': (.44, 0., 1.), 'b_optical_glass': (.25, 0., .050),
    'b_brass': (.49, .52, 1.), 'b_charcoal_wool': (.94, 0., 1.),
    'b_olive_blouse': (.87, 0., 1.), 'b_twill': (.96, 0., 1.),
    'b_leather': (.75, 0., 1.), 'b_rubber_and_horn': (.86, 0., 1.),
}


def rgb(hexcode):
    return np.array([int(hexcode[i:i + 2], 16) / 255. for i in (0, 2, 4)])


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0., 1.)
    return t * t * (3. - 2. * t)


def bump(x, center, width):
    return np.exp(-((x - center) / width) ** 2)


def trigs(p):
    x, y, z = p.T
    # Ordered strokes appear at multiple scales, not random per-vertex speckle.
    return (.55 * np.sin(x * 46. + y * 27. + np.sin(z * 51.))
            + .28 * np.sin(x * 146. - y * 61. + z * 98.)
            + .17 * np.cos(x * 257. + y * 114. - z * 114.))


def rotate_between(a, b):
    a, b = unit(a), unit(b)
    v = np.cross(a, b)
    c = np.dot(a, b)
    x, y, z = v
    k = np.array(((0, -z, y), (z, 0, -x), (-y, x, 0)))
    assert c > -.999
    return np.eye(3) + k + k @ k / (1. + c)


def curve(anchors, per=5, closed=False):
    a = np.array(anchors, dtype=float)
    n = len(a)
    out = []
    for i in range(n if closed else n - 1):
        p, q = a[i], a[(i + 1) % n]
        l = a[(i - 1) % n] if closed or i else p
        r = a[(i + 2) % n] if closed or i < n - 2 else q
        t = np.arange(per)[:, None] / per
        out.extend((2 * p + (q - l) * t + (2 * l - 5 * p + 4 * q - r) * t**2
                    + (-l + 3 * p - 3 * q + r) * t**3) * .5)
    return np.array(out if closed else [*out, a[-1]])


def rounded_contour(points):
    """In-plane chamfer that stays inside the fabric pattern (no overshoot)."""
    poly = np.array(points, dtype=float)
    before, after = np.roll(poly, 1, axis=0), np.roll(poly, -1, axis=0)
    a, b = poly + .115 * (before - poly), poly + .115 * (after - poly)
    t = np.linspace(0., 1., 4)[:, None, None]
    return np.swapaxes((1.-t)**2*a + 2*(1.-t)*t*poly + t*t*b, 0, 1).reshape(-1, 2)


def rings_faces(rows, sides, flip=False, loop=False):
    faces = []
    for j in range(rows if loop else rows - 1):
        for i in range(sides):
            a, b = j * sides + i, j * sides + (i + 1) % sides
            c, d = ((j + 1) % rows) * sides + i, ((j + 1) % rows) * sides + (i + 1) % sides
            faces.extend([(a, c, b), (b, c, d)] if flip else [(a, b, c), (b, d, c)])
    return np.array(faces, dtype=int)


def cap_ends(points, faces, rows, sides, flip):
    n = len(points)
    caps = []
    for j in range(sides):
        a, b = j, (j + 1) % sides
        c, d = a + (rows - 1) * sides, b + (rows - 1) * sides
        caps.extend([(n, a, b), (n + 1, d, c)] if flip else [(n, b, a), (n + 1, c, d)])
    return np.concatenate((points, [points[:sides].mean(0), points[-sides:].mean(0)])), np.concatenate((faces, caps))


def tube(path, radii, sides=10, depth_radii=None, closed=False, reference=None):
    n = len(path)
    t = np.roll(path, -1, axis=0) - np.roll(path, 1, axis=0)
    if not closed:
        t[0], t[-1] = path[1] - path[0], path[-1] - path[-2]
    t = np.array([unit(d) for d in t])
    # Parallel-transport the ring normal along the curve. This keeps the
    # seam/lens profile from flipping at the sleeve or spectacle temple.
    n0 = np.array((1., 0., 0.)) if reference is None else np.array(reference, dtype=float)
    if abs(np.dot(n0, t[0])) > .92:
        n0 = np.array((0., 1., 0.))
    ns = [unit(n0 - t[0] * np.dot(n0, t[0]))]
    for d in t[1:]:
        ns.append(unit(ns[-1] - d * np.dot(d, ns[-1])))
    # Closed decorative tubes are planar; use the common normal instead.
    if closed and reference is not None:
        ns = np.array([unit(n0 - d * np.dot(n0, d)) for d in t])
    ns = np.array(ns)
    bs = np.cross(t, ns)
    a = np.linspace(0, 2 * PI, sides, endpoint=False)
    rx = np.broadcast_to(radii, n)
    rz = rx if depth_radii is None else np.broadcast_to(depth_radii, n)
    p = (path[:, None, :] + rx[:, None, None] * np.cos(a)[None, :, None] * ns[:, None, :]
         + rz[:, None, None] * np.sin(a)[None, :, None] * bs[:, None, :]).reshape(-1, 3)
    f = rings_faces(n, sides, loop=closed)
    return (p, f) if closed else cap_ends(p, f, n, sides, False)


def loft(anchors, sides=36, per=3, wrinkle=0.):
    """Horizontal rings (height, x, depth, half-width, half-depth, squareness)."""
    rings = curve(anchors, per)
    y, x, z, rx, rz, power = rings.T
    a = np.linspace(0, 2 * PI, sides, endpoint=False)
    cs, sn = np.cos(a), np.sin(a)
    pleat = 1. + wrinkle * (np.cos(4 * a + y[:, None] * 47.) + .55 * np.sin(7 * a + y[:, None] * 68.))
    p = np.stack((x[:, None] + rx[:, None] * pleat * np.sign(cs) * np.abs(cs)**power[:, None],
                  np.broadcast_to(y[:, None], (len(y), sides)),
                  z[:, None] + rz[:, None] * pleat * np.sign(sn) * np.abs(sn)**power[:, None]), axis=2).reshape(-1, 3)
    return cap_ends(p, rings_faces(len(y), sides, flip=True), len(y), sides, True)


def sphere(center, sizes, rings=15, sides=30):
    y = np.linspace(-.5 * PI + .05, .5 * PI - .05, rings)
    a = np.linspace(0, 2. * PI, sides, endpoint=False)
    xz = np.cos(y)[:, None]
    co = np.stack((xz * np.cos(a), np.broadcast_to(np.sin(y)[:, None], (rings, sides)), xz * np.sin(a)), axis=2)
    p = (co * sizes + center).reshape(-1, 3)
    return cap_ends(p, rings_faces(rings, sides, flip=True), rings, sides, True)


def read_topology(root):
    verts, faces = [], defaultdict(list)
    group = ''
    for line in (root / '3dobjs/base.obj').read_text().splitlines():
        if line.startswith('v '):
            verts.append(tuple(map(float, line.split()[1:4])))
        elif line.startswith('g '):
            group = line[2:]
        elif line.startswith('f '):
            ids = [int(col.split('/')[0]) - 1 for col in line.split()[1:]]
            faces[group].extend((ids[0], ids[i], ids[i + 1]) for i in range(1, len(ids) - 1))
    return np.array(verts), {key: np.array(tris, dtype=int) for key, tris in faces.items()}


def target(root, path, n):
    a = np.loadtxt(root / 'targets' / f'{path}.target')
    out = np.zeros((n, 3))
    out[a[:, 0].astype(int)] = a[:, 1:]
    return out


class Sculpt:
    def __init__(self, root):
        self.root = root
        self.v, self.f = read_topology(root)
        self.n = len(self.v)
        self.orig = self.v.copy()
        self.source_rig = json.loads((root / 'rigs/default.mhskel').read_text())
        self.source_weights = json.loads((root / 'rigs/default_weights.mhw').read_text())['weights']
        self.pieces, self.bones = [], {}
        self.shape()
        self.rig()

    def apply(self, name, value):
        self.v += value * target(self.root, name, self.n)

    def shape(self):
        # Mix mesh offsets, not an off-the-shelf ready character. The contour
        # around the mouth, temples and cheeks is adjusted independently below.
        for name, value in {
            'macrodetails/caucasian-female-old': .48,
            'macrodetails/asian-female-old': .52,
            'macrodetails/universal-female-old-minmuscle-minweight': .74,
            'macrodetails/universal-female-old-averagemuscle-minweight': .26,
            'head/head-age-incr': .62, 'chin/chin-width-incr': -.30,
            'chin/chin-prominent-incr': .21, 'nose/nose-hump-incr': .29,
            'nose/nose-scale-vert-incr': .30, 'nose/nose-scale-depth-incr': .27,
            'nose/nose-point-width-incr': -.32,
            'mouth/mouth-lowerlip-volume-decr': .57, 'mouth/mouth-upperlip-volume-incr': -.28,
            'expression/units/asian/mouth-compression': .44,
            'expression/units/asian/mouth-depression': .27,
            'torso/torso-scale-depth-decr': .32, 'torso/torso-scale-horiz-decr': .18,
            'neck/neck-scale-horiz-decr': .24,
        }.items():
            if value:
                self.apply(name, value)
        for s in ('l', 'r'):
            for group, suffix, value in [('cheek', 'cheek-volume-decr', .64), ('cheek', 'cheek-bones-incr', .32),
                                         ('eyes', 'eye-bag-incr', .38), ('eyes', 'eye-bag-height-incr', .17)]:
                self.apply(f'{group}/{s}-{suffix}', value)
        self.apply('expression/units/asian/eye-left-slit', .15)
        self.apply('expression/units/asian/eye-right-slit', .23)
        # Body proportions: neck/head carried subtly ahead of a narrow back,
        # closer foot placement, softly narrowed waist, no bust emphasis.
        y0 = float(self.v[np.unique(self.f['body']), 1].min())
        height = float(self.v[np.unique(self.f['body']), 1].max()) - y0
        self.metre = 1.600 / height
        self.v *= self.metre
        self.v[:, 1] += .015 - y0 * self.metre
        x, y, z = self.v.T
        x *= 1. - .37 * (1. - smoothstep(.26, .85, y))
        x *= 1. - .06 * bump(y, 1.24, .15)
        z += .030 * smoothstep(1.06, 1.48, y)
        # A few millimetres of natural asymmetry, without slanting the skull.
        z += .0027 * np.tanh(84. * x) * bump(y, 1.46, .075) * smoothstep(.06, .11, z)
        self._neutral_arms()

    def joint(self, name, end='head'):
        label = self.source_rig['bones'][name][end]
        return self.v[self.source_rig['joints'][label]].mean(0)

    def masks(self, names):
        out = np.zeros(self.n)
        for name in names:
            rows = np.array(self.source_weights.get(name, []))
            if len(rows):
                out[rows[:, 0].astype(int)] += rows[:, 1]
        return np.clip(out, 0., 1.)

    def _neutral_arms(self):
        before = self.v.copy()
        for s in ('L', 'R'):
            sign = 1 if s == 'L' else -1
            top, elbow, wrist = [self.joint(f'{b}.{s}') for b in ('upperarm01', 'lowerarm01', 'wrist')]
            m1 = rotate_between(elbow - top, np.array((.245 * sign, -.962, -.105)))
            m2 = rotate_between(wrist - elbow, np.array((.210 * sign, -.969, .127)))
            down = top + m1 @ (elbow - top)
            fore = self.masks([b for b in self.source_weights if b.endswith('.' + s) and
                              b.startswith(('lowerarm', 'wrist', 'finger', 'metacarpal'))])
            arm = self.masks([f'upperarm01.{s}', f'upperarm02.{s}']) + fore
            # Joint locator geometry has no skin weights. Carry the locators by
            # the same arm transforms so the fitted rig follows the skin.
            joint_sets = self.source_rig['joints']
            for name, ids in joint_sets.items():
                if name.startswith(('wrist', 'finger', 'metacarpal')) and f'.{s}_' in name:
                    arm[ids], fore[ids] = 1., 1.
            for name, ratio in [(f'upperarm01.{s}', 0.), (f'upperarm02.{s}', 0.),
                                (f'lowerarm01.{s}', 1.), (f'lowerarm02.{s}', 1.)]:
                for end in ('head', 'tail'):
                    ids = joint_sets[self.source_rig['bones'][name][end]]
                    arm[ids], fore[ids] = 1., ratio
            arm = np.clip(arm, 0., 1.)
            moved1 = (before - top) @ m1.T + top
            moved2 = (before - elbow) @ m2.T + down
            self.v += (moved1 - before) * (arm - fore)[:, None] + (moved2 - before) * fore[:, None]

    def add_bone(self, name, parent, p, q):
        self.bones[name] = (parent, np.array(p, dtype=float), np.array(q, dtype=float))

    def rig(self):
        b = self.add_bone
        b('Root', None, [0., 0., 0.], [0., .17, 0.])
        spine = [('Hips', 'spine05'), ('Spine', 'spine04'), ('Spine_01', 'spine03'),
                 ('Spine_02', 'spine02'), ('Chest', 'spine01'), ('Neck', 'neck01'), ('Head', 'head')]
        parent = 'Root'
        for name, source in spine:
            b(name, parent, self.joint(source), self.joint(source, 'tail'))
            parent = name
        b('Jaw', 'Head', self.joint('jaw'), self.joint('jaw', 'tail'))
        # These stem names resolve via CharacterAnimation's existing aliases,
        # including its lowercase fallback for names with _L/_R.
        for side in ('L', 'R'):
            def pair(name, parent, source, tail=None):
                h = self.joint(f'{source}.{side}')
                t = self.joint(f'{source}.{side}', 'tail') if tail is None else self.joint(f'{tail}.{side}')
                b(f'{name}_{side}', parent, h, t)
            pair('Eye', 'Head', 'eye')
            pair('Shoulder', 'Chest', 'clavicle', 'upperarm01')
            pair('UpperArm', f'Shoulder_{side}', 'upperarm01', 'lowerarm01')
            pair('Forearm', f'UpperArm_{side}', 'lowerarm01', 'wrist')
            pair('Hand', f'Forearm_{side}', 'wrist', 'finger3-1')
            for i, digit in enumerate(('Thumb', 'Index', 'Middle', 'Ring', 'Little'), 1):
                prev = f'Hand_{side}'
                for n in (1, 2, 3):
                    pair(f'{digit}{n:02}', prev, f'finger{i}-{n}')
                    prev = f'{digit}{n:02}_{side}'
            pair('Thigh', 'Hips', 'upperleg01', 'lowerleg01')
            pair('LowerLeg', f'Thigh_{side}', 'lowerleg01', 'foot')
            pair('Foot', f'LowerLeg_{side}', 'foot', 'toe2-1')
            pair('Toes', f'Foot_{side}', 'toe2-1', 'toe2-3')
        self.ids = {n: i for i, n in enumerate(self.bones)}
        self.eyes = [self.bones[f'Eye_{side}'][1] for side in ('L', 'R')]

    def weights(self, count, bone):
        w = np.zeros((count, len(self.bones)))
        w[:, self.ids[bone]] = 1.
        return w

    def axial_weights(self, v, joints, heights):
        w = np.zeros((len(v), len(self.bones)))
        bands = np.maximum(np.diff(heights), 1e-5)
        t = np.clip((v[:, 1, None] - np.array(heights[:-1])) / bands, 0., 1.)
        t = t * t * (3. - 2. * t)
        padded = np.column_stack((np.ones(len(v)), t, np.zeros(len(v))))
        w[:, [self.ids[j] for j in joints]] = padded[:, :-1] - padded[:, 1:]
        return w

    def add(self, name, p, f, color, material, weight, morphs=None, grain=0.):
        c = rgb(color) if isinstance(color, str) else color
        if c.shape == (3,):
            c = np.broadcast_to(c, (len(p), 3)).copy()
        if grain:
            c = c + trigs(p)[:, None] * grain
        self.pieces.append(Piece(name, p, f, c, material,
                                 self.weights(len(p), weight) if isinstance(weight, str) else weight, morphs or {}))

    def extract(self, mask):
        f = self.f['body'][np.all(mask[self.f['body']], axis=1)]
        ids, local = np.unique(f, return_inverse=True)
        return ids, local.reshape(-1, 3)

    def skin(self):
        y0 = self.bones['Neck'][1][1] - .027
        head, faces = self.extract((self.v[:, 1] > y0) & (abs(self.v[:, 0]) < .105))
        p = self.v[head].copy()
        x, y, z = p.T
        # The cropped neck skin tucks into the closed stand collar. The
        # wider shoulder polygons are not an exposed edge of the face part.
        collar = 1. - smoothstep(1.357, 1.412, y)
        x *= 1. - .60 * collar
        z[:] = z * (1. - .20 * collar) + .073 * .20 * collar
        self.face_points, self.face_faces = p, faces
        eye_y = float(np.mean([e[1] for e in self.eyes]))
        eye_x = float(np.mean([abs(e[0]) for e in self.eyes]))
        front = smoothstep(.040, .094, z)
        warm = (bump(abs(x), .053, .029) * bump(y, eye_y - .036, .032)
                + .65 * bump(abs(x), .073, .016) * bump(y, eye_y - .010, .027))
        tired = bump(abs(x), eye_x, .024) * bump(y, eye_y - .010, .011) * front
        hollow = bump(abs(x), .051, .016) * bump(y, eye_y - .061, .028) * front
        light = bump(x, -.013, .039) * bump(y, eye_y + .056, .044)
        nose = bump(x, .003, .014) * bump(y, eye_y - .031, .024) * front
        c = np.tile(rgb('a0805e'), (len(p), 1))
        c += warm[:, None] * np.array((.071, .023, .022))
        c += tired[:, None] * np.array((-.155, -.128, -.084))
        c += hollow[:, None] * np.array((-.126, -.116, -.084))
        c += light[:, None] * np.array((.097, .095, .087))
        c += nose[:, None] * np.array((.085, .060, .042))
        orbit = bump(abs(x), eye_x, .022) * bump(y, eye_y+.007, .005) * front
        c -= orbit[:, None] * [.14, .132, .092]
        neck_shade = (1. - smoothstep(eye_y - .139, eye_y - .079, y))
        c -= neck_shade[:, None] * np.array((.105, .113, .094))
        mouth = 1.446
        mouth_mask = bump(y, mouth, .0065) * bump(x, 0., .024) * smoothstep(.131, .159, z)
        c = c * (1. - mouth_mask[:, None] * .69) + rgb('80594e') * mouth_mask[:, None] * .69
        # Small old skin marks and modeled folds sit inside the shading of
        # the age morph, rather than substituting painted lines for the form.
        for i, lift in enumerate((.031, .042, .051)):
            curve_y = eye_y + lift + .18 * abs(x) + .0017 * np.sin(54*x + i)
            fold = bump(y, curve_y, .0018) * bump(x, -.006, .043) * front
            p[:, 2] -= .00067 * fold
            c -= fold[:, None] * [.043, .043, .030]
        frown = bump(abs(x) + .12*(y-eye_y), .0074, .0024) * bump(y, eye_y + .025, .015) * front
        p[:, 2] -= .00115 * frown
        c -= frown[:, None] * [.054, .063, .047]
        marionette = bump(abs(x) - .14*(y-mouth), .028, .005) * bump(y, mouth - .009, .021) * front
        c -= marionette[:, None] * [.058, .064, .049]
        spots = smoothstep(.68, .86, np.sin(384*x+53*z)*np.sin(415*y+63*z))
        c -= (spots * warm)[:, None] * [.052, .043, .032]
        c += .018 * trigs(p)[:, None]
        # Head/neck and small jaw weights maintain a continuous neckline before
        # the collar. Expression targets are deliberately kept at zero at rest.
        w = self.axial_weights(p, ['Chest', 'Neck', 'Head'], [y0, y0 + .046, y0 + .105])
        jaw = self.masks(['jaw'])[head] * .78
        w *= (1. - jaw[:, None])
        w[:, self.ids['Jaw']] = jaw
        morphs = {}
        for name, asset in [('Blink_L', 'eye-left-closure'), ('Blink_R', 'eye-right-closure')]:
            morphs[name] = target(self.root, f'expression/units/asian/{asset}', self.n)[head] * self.metre * .91
        self.add('Face and neck', p, faces, c, 'b_skin', w, morphs)
        for side in ('L', 'R'):
            sign = 1 if side == 'L' else -1
            m = self.orig[:, 0] * sign > 3.95
            wrist = self.bones[f'Hand_{side}'][1]
            m &= self.v[:, 1] < wrist[1] + .026
            ids, f = self.extract(m)
            w = np.zeros((len(ids), len(self.bones)))
            for i, d in enumerate(('Thumb', 'Index', 'Middle', 'Ring', 'Little'), 1):
                for j in range(1, 4):
                    w[:, self.ids[f'{d}{j:02}_{side}']] = self.masks([f'finger{i}-{j}.{side}'])[ids]
            w[:, self.ids[f'Forearm_{side}']] = .85 * self.masks([f'lowerarm02.{side}'])[ids]
            w[:, self.ids[f'Hand_{side}']] = np.clip(1. - w.sum(1), .0, 1.)
            pos = self.v[ids]
            tint = rgb('a58465') + .030 * trigs(pos)[:, None]
            for bone in [f'{d}02_{side}' for d in ('Index', 'Middle', 'Ring', 'Little')]:
                center = self.bones[bone][1]
                tint -= bump(np.linalg.norm(pos - center, axis=1), .009, .008)[:, None] * [.021, .028, .024]
            self.add(f'Hands {side}', pos, f, tint, 'b_skin', w)

    def facial_surface(self, xy):
        """Front-most projected surface point at a given X and height."""
        tri = self.face_points[self.face_faces]
        a, b, c = tri.transpose(1, 0, 2)
        u, v = b - a, c - a
        det = u[:, 0] * v[:, 1] - u[:, 1] * v[:, 0]
        det = np.where(abs(det) > 1e-12, det, 1e-16)
        out = []
        for x, y in xy:
            xx, yy = x - a[:, 0], y - a[:, 1]
            r = (xx * v[:, 1] - yy * v[:, 0]) / det
            s = (u[:, 0] * yy - u[:, 1] * xx) / det
            hit = (r >= -.00001) & (s >= -.00001) & (r + s < 1.00001)
            d = a[:, 2] + r * u[:, 2] + s * v[:, 2]
            out.append(d[hit].max() if hit.any() else 0.10)
        return np.column_stack((xy, out))

    def face_details(self):
        for side, eye in zip(('L', 'R'), self.eyes):
            sign = 1 if side == 'L' else -1
            x, y, z = eye
            # The eyeball sits inside the eyelid topology. Iris is painted over
            # the actual sphere, so a posed eye never separates from its iris.
            rad = .0128
            p, f = sphere(eye + [0., .0004, .0014], [rad, rad, rad], 18, 36)
            d = p - eye
            gaze = unit(np.array((-.16, .034, 1.)))
            front = d @ gaze
            rr = np.sqrt(np.maximum(0., (d * d).sum(1) - front**2))
            a = np.arctan2(d[:, 1], d[:, 0])
            iris = (1. - smoothstep(.0052, .0065, rr)) * (front > .006)
            pupil = (1. - smoothstep(.0028, .0037, rr)) * (front > .007)
            inner = (1. - smoothstep(.0033, .0063, rr)) * (front > .006)
            white = rgb('b9afa1') + .027 * (d[:, 1] / rad)[:, None]
            iris_tone = rgb('463426') + inner[:, None] * [.094, .064, .027] + .018 * np.sin(31 * a)[:, None]
            tint = white * (1. - iris[:, None]) + iris_tone * iris[:, None]
            tint = tint * (1. - pupil[:, None]) + rgb('181614') * pupil[:, None]
            self.add(f'Eye {side}', p, f, tint, 'b_eye', f'Eye_{side}')
            # Asymmetric brush-tapered lids and arched eyebrows, fitted to
            # anatomical surface rather than floating on a generic face plane.
            adj = .0009 if side == 'L' else -.0009
            xy = curve([(x - sign*.025, y + .014 + adj), (x - sign*.013, y + .020 + adj),
                        (x + sign*.001, y + .029 + adj), (x + sign*.014, y + .028 + adj),
                        (x + sign*.025, y + .021 + adj), (x + sign*.033, y + .013)], 6)
            line = self.facial_surface(xy)
            line[:, 2] += .00085
            bump_r = np.sin(np.linspace(.09, PI - .09, len(line))) ** .74
            p, f = tube(line, .00065 * bump_r, 8, .0024 * bump_r, reference=(0., 0., 1.))
            self.add(f'Tapered brow {side}', p, f, '41342c', 'b_brows_and_crease', 'Head', grain=.032)
            for n in range(2):
                x0 = x + sign * (.017 + .0011 * n)
                anchors = [(x0, y - .006 - .005 * n), (x0 + sign*.010, y - .008 - .004*n),
                           (x0 + sign*.017, y - .013 - .003*n)]
                q = self.facial_surface(curve(anchors, 5))
                q[:, 2] += .00003
                r = (.00040 - .000085 * n) * np.sin(np.linspace(.12, PI - .12, len(q)))
                p, f = tube(q, r, 6)
                self.add(f'Outer lid fold {side} {n + 1}', p, f, '957c61', 'b_brows_and_crease', 'Head', grain=.015)
        # Gold hoops: fitted to the low lobe, not face-front studs.
        p0 = self.face_points
        for side, sign in [('L', 1), ('R', -1)]:
            ix = (p0[:, 0] * sign > .065) & (p0[:, 1] > self.eyes[0][1] - .059) & (p0[:, 1] < self.eyes[0][1] - .027)
            ear = p0[ix]
            if not len(ear):
                continue
            c = ear[np.argmax(ear[:, 0] * sign)] + [sign*.0001, -.007, .003]
            a = np.linspace(0, 2 * PI, 32, endpoint=False)
            pos = c + np.column_stack((.003*np.cos(a), .007*np.sin(a), .0027*sign*np.cos(a)))
            p, f = tube(pos, .00122, 8, closed=True, reference=(.65, 0., -.76*sign))
            self.add(f'Old brass hoop {side}', p, f, 'b3945c', 'b_brass', 'Head', grain=.052)

    def glasses(self):
        top_inner, outer = [], []
        ymid = float(np.mean([e[1] for e in self.eyes]))
        for s, eye in zip(('L', 'R'), self.eyes):
            sign = 1 if s == 'L' else -1
            center = abs(eye[0]) + .0017
            plane = float(eye[2]) + .030
            # Hand-rounded, slightly tapered oblong frames. Eye sits above the
            # bridge center; the lens descends far enough to read in the game.
            shell = [(-.028, .0138), (-.020, .019), (.016, .0195), (.029, .015),
                     (.027, -.008), (.0185, -.0168), (-.014, -.0185), (-.025, -.011)]
            xy = curve([(sign*(center+u), ymid + dz - .006 + .08*u) for u, dz in shell], 7, True)
            dep = plane - .20 * (abs(xy[:, 0]) - center) - 1.3 * (abs(xy[:, 0]) - center)**2
            pts = np.column_stack((xy, dep))
            radius = np.interp(pts[:, 1], [ymid - .025, ymid + .015], [.0015, .00225])
            p, f = tube(pts, radius * .93, 10, radius, True, (0., 0., 1.))
            x, y, z = p.T
            flake = smoothstep(-.06, .56, .62*np.sin(x*540 + y*259) + .37*np.sin(y*890-z*233) + .15*np.cos(z*238))
            c = rgb('3b2923') + flake[:, None] * (rgb('a36537') - rgb('3b2923'))
            self.add(f'Tortoiseshell rim {s}', p, f, c, 'b_tortoiseshell', 'Head')
            # Convex tinted optics behind the rim. No bright opaque strip in
            # the sight line; the eyelids and painted iris remain visible.
            middle = pts.mean(0)
            lens = np.concatenate(((pts - middle) * .991 + middle - [0., 0., .0006],
                                   (pts - middle)*.48 + middle + [0., 0., .0007],
                                   [middle + [0., 0., .00155]]))
            nn = len(pts)
            faces = rings_faces(2, nn)
            fan = [(nn+i, nn+(i+1)%nn, 2*nn) for i in range(nn)]
            f = np.concatenate((faces, fan))
            self.add(f'Optical lens {s}', lens, f if sign < 0 else f[:, ::-1], 'c2c2ac', 'b_optical_glass', 'Head')
            top_inner.append(pts[np.argmin(abs(pts[:, 0]) + 1.8 * abs(pts[:, 1] - ymid))])
            outer.append(pts[np.argmax(abs(pts[:, 0]) + .16*(pts[:, 1] - ymid))])
            front = outer[-1]
            ear_x = max(.072, abs(front[0]) + .005)
            end = np.array([sign*(ear_x - .003), ymid - .013, eye[2] - .117])
            mid = curve([front, front + [sign*.006, .0017, -.005], [sign*ear_x, ymid + .008, eye[2] - .037],
                         [sign*ear_x, ymid + .004, eye[2] - .077], end], 5)
            p, f = tube(mid, np.linspace(.0025, .00175, len(mid)), 8, reference=(0., 1., 0.))
            self.add(f'Acetate temple {s}', p, f, '55382a', 'b_tortoiseshell', 'Head', grain=.05)
            for i in range(2):
                p, f = sphere(front + [sign * (.001 + .0032*i), .001, .00155], [.00087, .00089, .00049], 6, 10)
                self.add(f'Hinge pin {s} {i}', p, f, 'b1a282', 'b_brass', 'Head')
        l, r = top_inner
        xy = np.array([[0., ymid + .0035]])
        d = max(self.facial_surface(xy)[0, 2] + .0038, .5 * (l[2] + r[2]) - .001)
        p, f = tube(curve([l, [.006, ymid + .003, d], [0., ymid + .0041, d+.0007], [-.006, ymid + .003, d], r]), .00172, 10)
        self.add('Arched saddle bridge', p, f, '613c28', 'b_tortoiseshell', 'Head', grain=.047)

    def scalp_rays(self, center, directions):
        tri = self.face_points[self.face_faces]
        a, b, c = tri.transpose(1, 0, 2)
        e, f, v = b - a, c - a, center - a
        q = np.cross(v, e)
        num = np.einsum('ij,ij->i', f, q)
        values = []
        for d in np.array_split(directions, math.ceil(len(directions) / 48)):
            h = np.cross(d[:, None, :], f[None, :, :])
            det = np.einsum('dij,ij->di', h, e)
            inv = 1. / np.where(abs(det) < 1e-10, 1e-10, det)
            u = np.einsum('dij,ij->di', h, v) * inv
            k = (d @ q.T) * inv
            t = num * inv
            values.extend(np.where((u >= -1e-7) & (k >= -1e-7) & (u+k <= 1.0000001) & (t > 0.), t, 0.).max(axis=1))
        radii = np.array(values)
        if radii.min() <= .009:
            raise ValueError('Scalp did not close over the fitted skull')
        return radii

    def hair(self):
        eye_y = self.eyes[0][1]
        center = np.array([0., eye_y + .012, self.eyes[0][2] - .053])
        a = np.linspace(0, 2*PI, 84, endpoint=False)
        line = (1.56 - .45 * np.sin(a) + .21 * smoothstep(-.16, -.92, np.sin(a))
                + .078*np.sin(2*a + .25) + .025*np.sin(7*a + .1))
        # Hairline at the entire forehead, not a painted flat cap. Sweep the
        # grain across the crown from an off-center part into the back roll.
        s = np.linspace(1, .019, 30)[:, None]
        phi = line[None, :] * s
        directions = np.stack((np.sin(phi)*np.cos(a), np.cos(phi), np.sin(phi)*np.sin(a)), axis=2).reshape(-1, 3)
        base = self.scalp_rays(center, directions).reshape(phi.shape)
        phase = 19.5 * phi + 17.8 * np.cos(a + .67*phi) + np.sin(4*a + phi) * 1.4
        groove = (.5 + .5 * np.cos(phase)) ** 4
        crest = .0018 * groove * smoothstep(.22, .78, s) + .0027*np.cos(a + 1.6)*np.sin(phi)**2
        thick = (.0034 + .0049 * np.sin(PI*.78 * s)**.72 + crest) * smoothstep(1.032, .86, s)
        # A compact patch at the silver side-part separates broad locks.
        xyz = center + directions * (base + thick).reshape(-1, 1)
        p, f = cap_ends(xyz, rings_faces(len(s), len(a), flip=True), len(s), len(a), True)
        x, y, z = p.T
        silver = .13 + .43 * smoothstep(eye_y+.012, eye_y+.099, y) + .18 * bump(x, -.026, .042)
        silver *= .67 + .33 * smoothstep(eye_y+.020, eye_y+.076, y)
        pigment = .13*np.cos(phase) + .050*np.cos(2.*phase + .5*np.sin(phi))
        pigment *= smoothstep(.02, .28, s) * (.59 + .41*smoothstep(-.45, .68, np.sin(a)))
        strokes = np.concatenate(((pigment).ravel(), [0., 0.]))
        part = bump(x + .022 - .20*(z - center[2]), 0., .003) * smoothstep(eye_y+.045, eye_y+.082, y)
        c = rgb('302d32') + np.clip(silver + strokes - .17*part, 0., .93)[:, None] * (rgb('94968f') - rgb('302d32'))
        self.add('Swept silver scalp', p, f, c, 'b_swept_silver', 'Head', grain=.022)
        # Tucked rather than spherical bun. The grooves turn continuously
        # into a few soft rolls with a matte dark nape.
        bun_center = np.array([.012, eye_y-.037, center[2]-.087])
        p, f = sphere(bun_center, [.057, .038, .032], 19, 42)
        bx, by, bz = (p - bun_center).T
        theta = np.arctan2(by/.038, bx/.057)
        d = np.hypot(by/.038, bx/.057)
        waves = .5 + .5*np.cos(5.0*theta + 10.8*d + 30.*bz)
        p[:, 2] -= .0021 * waves**3 * smoothstep(.005, -.03, bz)
        c = rgb('38363a') + (.13 + .18*waves + .14*smoothstep(-.028, .037, by))[:, None]*(rgb('8f908d')-rgb('38363a'))
        self.add('Low rolled silver bun', p, f, c, 'b_swept_silver', 'Head', grain=.028)

    def cloth_weights(self, p):
        return self.axial_weights(p, ['Hips', 'Spine', 'Spine_01', 'Spine_02', 'Chest'],
                                  [.867, .965, 1.053, 1.164, 1.262])

    def tailoring(self):
        cut = [(.812, 0., .019, .164, .097, .86),
               (.824, 0., .019, .164, .097, .87),
               (.893, 0., .016, .153, .094, .86),
               (.978, 0., .019, .130, .080, .88),
               (1.064, 0., .026, .122, .075, .90),
               (1.145, 0., .045, .124, .079, .87),
               (1.232, 0., .048, .144, .078, .85),
               (1.276, 0., .051, .150, .073, .82),
               (1.311, 0., .053, .145, .069, .86),
               (1.332, 0., .060, .121, .055, .91),
               (1.364, 0., .074, .052, .052, 1.),
               (1.371, 0., .078, .045, .047, 1.)]
        coat, coat_faces = loft(cut, 48, 3, .013)
        x, y, z = coat.T
        c = rgb('3e4340') + trigs(coat)[:, None] * [.025, .032, .033]
        muted = bump(y, 1.121, .181)*bump(x, -.092, .042)*smoothstep(.042, .10, z)
        c += muted[:, None] * [.051, .031, .007]
        back = smoothstep(.052, -.037, z)
        c += back[:, None] * [-.019, -.011, .012]
        self.add('Wool jacket body', coat, coat_faces, c, 'b_charcoal_wool', self.cloth_weights(coat))
        # Closed shirt stand: the return turns under at the neck instead of
        # bridging the hole with a cap. Its bottom is trapped inside the coat.
        collar = np.array([(1.350, .048, .043), (1.369, .053, .049),
                           (1.385, .043, .046), (1.389, .0415, .044),
                           (1.386, .037, .040), (1.371, .043, .046)])
        a = np.linspace(0, 2*PI, 42, endpoint=False)
        yp, rx, rz = collar.T[:, :, None]
        yp = yp - .004*np.sin(a) + .0012*np.cos(2*a)
        p = np.stack((rx*np.cos(a), yp, .077+rz*np.sin(a)), axis=-1).reshape(-1, 3)
        f = rings_faces(len(collar), len(a), flip=True)
        # The turnover sits nearly on the neck joint; carry its rim with the
        # same chest-to-neck ramp as the skin hidden underneath it.
        w = self.axial_weights(p, ['Chest', 'Neck'], [self.bones['Neck'][1][1]-.027,
                                                      self.bones['Neck'][1][1]+.019])
        self.add('Olive stand collar', p, f, '575744', 'b_olive_blouse', w, grain=.017)
        face_p, face_f = self.face_points, self.face_faces
        # The same front-ray fitter is useful for the surface following trim.
        self.face_points, self.face_faces = coat, coat_faces

        def front(pts, offset=0.):
            q = self.facial_surface(np.asarray(pts))
            q[:, 2] += offset
            return q

        def front_line(name, pts, tone, radius, off=.00055, mat='b_charcoal_wool'):
            p, f = tube(front(curve(pts, 7), off), radius, 7, reference=(0, 0, 1))
            self.add(name, p, f, tone, mat, self.cloth_weights(p), grain=.018)

        yy = np.linspace(.824, 1.365, 38)
        width = np.interp(yy, [.824, .976, 1.070, 1.195, 1.301, 1.365], [.007, .013, .019, .031, .048, .032])
        xx = np.linspace(-1, 1, 9)
        grid = np.stack((width[:, None]*xx, np.broadcast_to(yy[:, None], (len(yy), len(xx)))), axis=2).reshape(-1, 2)
        p = front(grid, .0025)
        i, j = np.meshgrid(np.arange(len(yy)-1), np.arange(len(xx)-1), indexing='ij')
        a = (i*len(xx) + j).ravel()
        n = len(xx)
        tris = np.concatenate((np.column_stack((a, a+1, a+n)), np.column_stack((a+1, a+n+1, a+n))))
        c = rgb('555743') + trigs(p)[:, None]*[.037, .034, .025]
        c += bump(p[:, 0], .006, .011)[:, None]*[.032, .022, .010]
        self.add('Olive blouse inset', p, tris, c, 'b_olive_blouse', self.cloth_weights(p))
        front_line('Blouse placket', [(0.005, .832), (.007, 1.027), (.004, 1.214), (.007, 1.352)],
                   '6d6954', .0016, .0026, 'b_olive_blouse')

        def panel(name, poly, tone, height, mat):
            rim = rounded_contour(poly)
            middle = rim.mean(0)
            rows = 6
            b = np.linspace(0.034, 1., rows)[:, None, None]
            p = front(((rim - middle) * b + middle).reshape(-1, 2))
            p[:, 2] += np.repeat((1.-b.ravel())**.9 * height + .0041, len(rim))
            f = rings_faces(rows, len(rim))
            # Close only the small center aperture. A fan across the outer
            # concave contour would overlap and shadow the notch itself.
            k = len(p)
            p = np.concatenate((p, front([middle], height + .0042)))
            f = np.concatenate((f, [(k, (i + 1) % len(rim), i) for i in range(len(rim))]))
            face_n = np.cross(p[f[0, 1]] - p[f[0, 0]], p[f[0, 2]] - p[f[0, 0]])
            if face_n[2] < 0.:
                f = f[:, ::-1]
            self.add(name, p, f, tone, mat, self.cloth_weights(p), grain=.029)

        for side in ('L', 'R'):
            sign = 1 if side == 'L' else -1
            lapel = [(sign*x, y) for x, y in [(.039, 1.345), (.083, 1.304), (.069, 1.281), (.085, 1.274),
                                              (.025, 1.101), (.021, 1.144), (.043, 1.280)]]
            panel(f'Notched lapel {side}', lapel, '4f5151', .0052, 'b_charcoal_wool')
            collar = [(sign*x, y) for x, y in [(.014, 1.360), (.031, 1.359), (.042, 1.324),
                                               (.024, 1.302), (.016, 1.324)]]
            panel(f'Pressed shirt collar {side}', collar, '625f48', .003, 'b_olive_blouse')
            front_line(f'Wool dart {side}', [(sign*.101, 1.252), (sign*.085, 1.116), (sign*.077, .977),
                                             (sign*.100, .856)], '454642', .00078, .00036)
            pocket = [(sign*x, y) for x, y in [(.066, .938), (.123, .928), (.122, .914), (.066, .920)]]
            panel(f'Patch pocket welt {side}', pocket, '4a4b45', .0026, 'b_charcoal_wool')
        for j, at in enumerate([(.021, 1.067), (.018, .978), (.016, .888)]):
            ct = front([at], .0032)[0]
            p, f = sphere(ct, [.0050, .0050, .0028], 8, 20)
            self.add(f'Dark horn front button {j + 1}', p, f, '514638', 'b_rubber_and_horn', self.cloth_weights(p), grain=.036)
        self.face_points, self.face_faces = face_p, face_f

        # Separate fitted sleeve cuts at each seam with matching blend bands.
        # The shoulder pieces share the chest weight at the root, and the cuff
        # follows some of the hand at its open edge instead of exposing a gap.
        for side in ('L', 'R'):
            sign = 1 if side == 'L' else -1
            sh, el, wr = [self.bones[f'{b}_{side}'][1] for b in ('UpperArm', 'Forearm', 'Hand')]
            p, f = loft([
                (wr[1]-.014, wr[0] + .003*sign, wr[2] + .006, .0220, .0340, .91),
                (wr[1]-.010, wr[0] + .003*sign, wr[2] + .005, .0230, .0335, .91),
                (wr[1]+.032, wr[0] - .006*sign, wr[2]-.004, .0260, .0310, .95),
                (el[1]-.060, el[0] + .014*sign, el[2]+.006, .0290, .0340, .89),
                (el[1]-.016, el[0] + .004*sign, el[2]+.003, .0310, .0360, .87),
                (el[1]+.025, el[0] - .006*sign, el[2]+.002, .0350, .0380, .87),
                (sh[1]-.070, sh[0] + .024*sign, sh[2]-.008, .0380, .0420, .91),
                (sh[1]-.026, sh[0] + .017*sign, sh[2]-.009, .0440, .0440, .92),
                (sh[1]+.006, sh[0] + .008*sign, sh[2]-.007, .0430, .0450, .9),
                (sh[1]+.024, sh[0] - .008*sign, sh[2]-.009, .0360, .0370, .94),
                (sh[1]+.036, sh[0] - .017*sign, sh[2]-.013, .0190, .0230, 1.),
            ], 32, 2, .027)
            def sleeve_weights(points):
                return self.axial_weights(points, [f'Hand_{side}', f'Forearm_{side}', f'UpperArm_{side}', 'Chest'],
                                          [wr[1]-.034, wr[1]+.044, el[1]+.017, sh[1]+.067])
            shade = rgb('3e4340') + trigs(p)[:, None]*[.023, .032, .031]
            shade += smoothstep(.025, .112, p[:, 2])[:, None]*[.030, .024, .007]
            self.add(f'Set-in wool sleeve {side}', p, f, shade, 'b_charcoal_wool', sleeve_weights(p))
            p, f = loft([
                (wr[1]-.018, wr[0]+.001*sign, wr[2]+.006, .0198, .0295, .97),
                (wr[1]-.015, wr[0], wr[2]+.006, .0208, .032, .96),
                (wr[1]-.006, wr[0], wr[2]+.004, .0205, .033, .91),
            ], 24, 2)
            self.add(f'Olive turnback cuff {side}', p, f, '5d5c49', 'b_olive_blouse', sleeve_weights(p), grain=.022)
            for i in range(2):
                p, f = sphere(wr + [sign*(.023-i*.002), .013+i*.011, -.007], [.0018, .0034, .0033], 6, 14)
                self.add(f'Horn sleeve button {side} {i + 1}', p, f, '544b3e', 'b_rubber_and_horn', sleeve_weights(p))

    def lower_body(self):
        for side in ('L', 'R'):
            sign = 1 if side == 'L' else -1
            hip, knee, ankle, toe = [self.bones[f'{b}_{side}'][1] for b in ('Thigh', 'LowerLeg', 'Foot', 'Toes')]
            p, f = loft([
                (ankle[1]-.023, ankle[0], ankle[2]+.012, .039, .044, .86),
                (ankle[1]-.011, ankle[0], ankle[2]+.012, .040, .046, .83),
                (ankle[1]+.033, ankle[0]-.004*sign, ankle[2]+.007, .042, .047, .89),
                (ankle[1]+.12, ankle[0]-.014*sign, ankle[2]+.003, .041, .047, .91),
                (knee[1]-.135, knee[0]+.005*sign, knee[2]-.021, .045, .047, .87),
                (knee[1]-.050, knee[0]+.001*sign, knee[2]-.011, .051, .053, .88),
                (knee[1]+.016, knee[0], knee[2]-.011, .051, .057, .88),
                (knee[1]+.12, knee[0]-.005*sign, knee[2]-.019, .063, .059, .88),
                (hip[1]-.15, hip[0]-.015*sign, hip[2]-.005, .063, .066, .86),
                (hip[1]-.046, hip[0]-.018*sign, hip[2], .063, .077, .86),
                (hip[1]+.063, hip[0]-.022*sign, hip[2]-.006, .057, .075, .90),
            ], 32, 3, .023)
            c = rgb('4c4944') + trigs(p)[:, None]*[.025, .023, .018]
            center = np.interp(p[:, 1], [ankle[1], knee[1], hip[1]], [ankle[0], knee[0], hip[0]-.015*sign])
            pleat = bump(p[:, 0], center, .0075) * smoothstep(.033, .075, p[:, 2])
            p[:, 2] += pleat*.0039
            c += pleat[:, None] * [.033, .031, .025]
            w = self.axial_weights(p, [f'Foot_{side}', f'LowerLeg_{side}', f'Thigh_{side}', 'Hips'],
                                   [ankle[1]-.104, ankle[1]+.039, knee[1]+.042, hip[1]+.113])
            self.add(f'Straight pressed twill {side}', p, f, c, 'b_twill', w)
            # Hand-shaped square-toe slip-ons. Upper, saddle and inset outsole
            # bend across the real forefoot weights; soles establish Y = 0.
            xc = ankle[0] - sign*.002
            zc = .079
            def shoe_weights(points):
                w = self.weights(len(points), f'Foot_{side}')
                mix = smoothstep(toe[2]-.027, toe[2]+.023, points[:, 2])
                w[:, self.ids[f'Toes_{side}']] = mix
                w[:, self.ids[f'Foot_{side}']] -= mix
                return w
            for name, params, mat, color in [
                ('Low outsole', [(0.0, xc, zc, .037, .113, .71), (.005, xc, zc, .040, .117, .71),
                                  (.014, xc, zc, .039, .118, .72), (.019, xc, zc, .037, .115, .73)],
                 'b_rubber_and_horn', '38332f'),
                ('Leather vamp', [(.014, xc, zc, .037, .114, .75), (.026, xc, zc, .039, .116, .74),
                                  (.038, xc-.002*sign, zc-.003, .038, .108, .78),
                                  (.052, xc-.001*sign, zc-.013, .034, .089, .80),
                                  (.068, xc, zc-.034, .028, .058, .84),
                                  (.092, xc, zc-.051, .025, .034, .92)],
                 'b_leather', '483b34'),
            ]:
                p, f = loft(params, 36, 2, .009)
                self.add(f'{name} {side}', p, f, color, mat, shoe_weights(p), grain=.025)
            welt = curve([(xc-.032, .040, .120), (xc-.026, .042, .155), (xc-.014, .043, .174),
                          (xc+.010, .044, .177), (xc+.026, .042, .156), (xc+.033, .041, .121)], 5)
            p, f = tube(welt, .0012, 7, reference=(0, 1, 0))
            self.add(f'Moc toe seam {side}', p, f, '5a4a3f', 'b_leather', shoe_weights(p), grain=.026)

    def build(self, output, split_parts=False):
        self.skin()
        self.face_details()
        self.glasses()
        self.hair()
        self.tailoring()
        self.lower_body()
        GLB().write(output, self.pieces if split_parts else batch_materials(self.pieces), self.bones, MATS, 1.640)


def main():
    root = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--makehuman-data', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=root / 'scenes/dev/teacher_b/teacher_b.glb')
    parser.add_argument('--split-parts', action='store_true', help='Keep editable subparts for the Blender source')
    args = parser.parse_args()
    Sculpt(args.makehuman_data).build(args.output, args.split_parts)


if __name__ == '__main__':
    main()
