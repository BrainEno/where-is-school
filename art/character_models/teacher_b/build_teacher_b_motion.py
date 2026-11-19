#!/usr/bin/env python3
"""Bake Teacher B's original review performances onto her unchanged GLB rig.

The Godot tracks are absolute local bone transforms, sampled at 30 Hz. The
short walk is staged travel (−Z), not input-driven locomotion or a loop. Solve
its two legs against planted shoes here, not with a runtime IK dependency.
"""

import argparse
import json
import math
from pathlib import Path
import struct

import numpy as np

from skinned_glb import matrix_quaternion, unit

ROOT = Path(__file__).resolve().parents[3]
DEV = ROOT / 'scenes/dev/teacher_b'
FPS = 30
# (seconds, end of swing, anatomical side, landing distance in metres).
STEPS = ((.20, .74, 'L', .29), (.82, 1.36, 'R', .59),
         (1.44, 1.98, 'L', .90), (2.06, 2.60, 'R', .90))
LENGTHS = {'idle': 3.8, 'walk': 2.9, 'explain': 3.2}


def basis(q):
    x, y, z, w = q
    return np.array(((1 - 2*(y*y + z*z), 2*(x*y - z*w), 2*(x*z + y*w)),
                     (2*(x*y + z*w), 1 - 2*(x*x + z*z), 2*(y*z - x*w)),
                     (2*(x*z - y*w), 2*(y*z + x*w), 1 - 2*(x*x + y*y))))


def rotation(angle, axis):
    return basis((*tuple(axis * math.sin(math.radians(angle) / 2)), math.cos(math.radians(angle) / 2)))


def turn_between(before, after):
    a, b = unit(before), unit(after)
    # The short steps never require a 180-degree change of either leg segment.
    return basis(unit(np.r_[np.cross(a, b), 1.0 + np.dot(a, b)]))


def smooth(u):
    u = min(max(u, 0.), 1.)
    return u*u*(3. - 2.*u)


def timing(t, keys):
    """Eased performance beats, in seconds (not procedural retargeting)."""
    for (a, left), (b, right) in zip(keys, keys[1:]):
        if t <= b:
            return left + (right - left) * smooth((t - a) / (b - a))
    return keys[-1][1]


def travel(t):
    # Integrate a smooth acceleration, cruise, and deceleration. The pelvis
    # keeps moving through double support rather than stopping at every plant.
    elapsed = min(max(t - .14, 0.), 2.51)
    ramp = .40
    span = 2.51
    area = span - ramp
    if elapsed < ramp:
        p = elapsed / ramp
        integral = ramp * (p**3 - .5*p**4)
    elif elapsed > span - ramp:
        p = (span - elapsed) / ramp
        integral = area - ramp * (p**3 - .5*p**4)
    else:
        integral = elapsed - .5*ramp
    return STEPS[-1][-1] * integral / area


class Rig:
    def __init__(self, path):
        data = path.read_bytes()
        size, tag = struct.unpack_from('<I4s', data, 12)
        if data[:4] != b'glTF' or tag != b'JSON':
            raise ValueError(f'Not a GLB: {path}')
        gltf = json.loads(data[20:20+size])
        nodes = gltf['nodes']
        joints = gltf['skins'][0]['joints']
        self.names = [nodes[i]['name'] for i in joints]
        if len(self.names) != 57 or len(set(self.names)) != 57 or self.names[0] != 'Root':
            raise ValueError('Motion requires the 57-joint Teacher B rig')
        self.parent, self.loc, self.local, self.rest, self.point = {}, {}, {}, {}, {}
        parents = {c: n['name'] for n in nodes for c in n.get('children', ())}
        for i in joints:
            n = nodes[i]
            name, parent = n['name'], parents.get(i)
            self.parent[name] = parent
            self.loc[name] = np.array(n['translation'])
            self.local[name] = basis(n['rotation'])
            self.rest[name] = self.rest[parent] @ self.local[name] if parent else self.local[name]
            self.point[name] = self.point[parent] + self.rest[parent] @ self.loc[name] if parent else self.loc[name]

        # Actual sole vertices, not a guessed ankle height. Shoes have rigid
        # foot/toe weights and the toes keep their rest angle for these clips.
        shoe = next(p for m in gltf['meshes'] for p in m['primitives']
                    if gltf['materials'][p['material']]['name'] == 'b_rubber_and_horn')
        access = gltf['accessors'][shoe['attributes']['POSITION']]
        view = gltf['bufferViews'][access['bufferView']]
        verts = np.frombuffer(data, '<f4', 3*access['count'], 28+size+view['byteOffset']).reshape(-1, 3)
        self.sole = {side: verts[(verts[:, 0]*sign > .05) & (verts[:, 1] < .025)] - self.point['Foot_'+side]
                     for side, sign in [('L', 1), ('R', -1)]}
        if any(not len(points) for points in self.sole.values()):
            raise ValueError('Teacher B walk needs both shaped soles')

    def local_rotation(self, name, angles):
        transform = np.eye(3)
        for angle, axis in zip(angles, np.eye(3)):
            if angle:
                transform = rotation(angle, axis) @ transform
        rest = self.rest[name]
        return self.local[name] @ rest.T @ transform @ rest

    def shoe(self, t, side, walking):
        landing, pitch, lift = 0., 0., 0.
        if walking:
            for start, end, foot, distance in STEPS:
                if foot != side or t < start:
                    continue
                if t >= end:
                    landing = distance
                    continue
                u = (t - start) / (end - start)
                landing += (distance - landing) * smooth(u)
                lift = (.035 if distance == STEPS[-1][-1] and side == 'R' else .049) * math.sin(math.pi*u)**2
                pitch = timing(u, ((0., 0.), (.25, -11.), (.68, 10.), (1., 0.)))
                break
        roll = rotation(pitch, np.array((1., 0., 0.)))
        floor = np.min(self.sole[side] @ roll[1])
        foot = 'Foot_' + side
        return np.array((self.point[foot][0], lift - floor, self.point[foot][2] - landing)), roll @ self.rest[foot]

    def ground_legs(self, pose, root, shoes):
        """Analytic two-link solve. The rest knees determine the bend plane."""
        hips = self.rest['Root'] @ pose['Hips']
        hips_at = root + self.rest['Root'] @ self.loc['Hips']
        for side, (ankle, foot_rot) in shoes.items():
            thigh, shin, foot = [name+'_'+side for name in ('Thigh', 'LowerLeg', 'Foot')]
            hip = hips_at + hips @ self.loc[thigh]
            upper = self.point[shin] - self.point[thigh]
            lower = self.point[foot] - self.point[shin]
            a, b = np.linalg.norm(upper), np.linalg.norm(lower)
            line = ankle - hip
            d = np.linalg.norm(line)
            if not abs(a - b) < d < a + b:
                raise ValueError(f'{side} foot unreachable at root {root}, ankle {ankle}')
            axis = line / d
            rest_axis = unit(upper + lower)
            pole = upper - rest_axis * np.dot(upper, rest_axis)
            # Follow the measured rest bend as the leg aims at its target.
            pole = turn_between(rest_axis, axis) @ unit(pole)
            distance = (a*a - b*b + d*d) / (2*d)
            knee = hip + axis * distance + pole * math.sqrt(max(0., a*a - distance*distance))
            upper_rot = turn_between(upper, knee - hip) @ self.rest[thigh]
            lower_rot = turn_between(lower, ankle - knee) @ self.rest[shin]
            pose[thigh] = hips.T @ upper_rot
            pose[shin] = upper_rot.T @ lower_rot
            pose[foot] = lower_rot.T @ foot_rot

    def sample(self, clip, t):
        breath = .5 - .5*math.cos(2*math.pi*t/LENGTHS['idle']) if clip == 'idle' else 0.
        glance = timing(t, ((0., 0.), (.8, 0.), (1.6, 4.), (2.3, 3.), (3.8, 0.))) if clip == 'idle' else 0.
        shoes = {side: self.shoe(t, side, clip == 'walk') for side in ('L', 'R')}
        advance = travel(t) if clip == 'walk' else 0.
        activity = (smooth((t - .04) / .42) * smooth((2.9 - t) / .43)) if clip == 'walk' else 0.
        step = (shoes['R'][0][2] - shoes['L'][0][2]) / .30
        sway = 0.
        if clip == 'walk':
            for a, b, side, _ in STEPS:
                sway += (-1. if side == 'L' else 1.) * smooth((t - a + .13)/.28) * smooth((b + .12 - t)/.28)
        gesture = timing(t, ((0., 0.), (.24, -.055), (.81, .94), (1.22, 1.),
                             (1.57, .84), (1.87, .96), (2.16, .78), (2.86, 0.), (3.2, 0.))) if clip == 'explain' else 0.
        lift = max(0., gesture)
        nod = timing(t, ((0., 0.), (.32, -3.), (.94, 0.), (1.33, 1.), (1.62, -2.8),
                         (2.05, 1.1), (2.94, 0.))) if clip == 'explain' else 0.
        root = self.loc['Root'] + np.array((-.009 + .007*breath + .022*sway - .007*lift,
                                          -.006 - activity*(.007 + .014*abs(step)), -advance))
        angles = {
            'Hips': (-.9, 2.7*step, -1.1*sway),
            'Spine': (-1.6 - 2.7*activity - .5*breath, -.7*step, 1.6*sway),
            'Chest': (-.7 - 1.1*breath, -2.9*step - 5.8*lift, -1.7*lift),
            'Neck': (1.7 + .7*breath, glance*.35, .5),
            'Head': (-1.3 + nod + 1.6*activity, glance*.65 + 3.4*lift, -1.4 - 1.1*lift),
            'Shoulder_L': (2.1*lift, 0., 1.3*lift),
            'UpperArm_L': (1.5 - 8.4*step + 24.*gesture, -8.*lift, -1.8 + 5.4*lift),
            'Forearm_L': (6.4 + 2.4*step + 52.*lift, -1.8*lift, 0.),
            'Hand_L': (-1.1 - 7.*lift, -7.5*lift, 3.1*lift),
            'UpperArm_R': (2. + 9.5*step + 2.7*lift, 2.5*lift, 2.4),
            'Forearm_R': (6.7 - 2.9*step + 4.*lift, 0., 0.),
            'Hand_R': (-1.4, 0., 0.),
        }
        # Differentiated knuckle timing: the index opens while lesser fingers
        # curl inward. Both relaxed hands have their own small resting curls.
        for side, sign in [('L', -1.), ('R', 1.)]:
            strength = lift if side == 'L' else .10*lift
            for digit, base, emphasis in [('Thumb', 4., 9.), ('Index', 7., -5.), ('Middle', 9., 19.),
                                          ('Ring', 11., 21.), ('Little', 13., 19.)]:
                for joint, factor in enumerate((.80, 1., .53), 1):
                    angles[f'{digit}{joint:02d}_{side}'] = (0., 0., sign*factor*(base + emphasis*strength))
        pose = {name: self.local_rotation(name, d) for name, d in angles.items()}
        self.ground_legs(pose, root, shoes)
        return root, pose


def number(x):
    return f'{0. if abs(x) < 5.e-9 else x:.8g}'


def reduced_keys(values, rotational):
    # Keep the native resource small while bounding interpolation error at
    # each sampled pose (0.075 degrees / 0.20 mm before skinning).
    keep = {0, len(values)-1}
    ranges = [(0, len(values)-1)]
    limit = math.radians(.075) if rotational else .00020
    while ranges:
        a, b = ranges.pop()
        if b-a < 2:
            continue
        u = np.arange(1, b-a)[:, None] / (b-a)
        left, right = values[a], values[b]
        if rotational:
            cosine = np.clip(left @ right, -1., 1.)
            if cosine < 0.:
                right, cosine = -right, -cosine
            theta = math.acos(cosine)
            if theta < 1.e-6:
                estimate = (1-u)*left + u*right
            else:
                estimate = (np.sin((1-u)*theta)*left + np.sin(u*theta)*right) / math.sin(theta)
            error = 2*np.arccos(np.clip(np.abs((estimate*values[a+1:b]).sum(axis=1)), 0., 1.))
        else:
            error = np.linalg.norm((1-u)*left + u*right - values[a+1:b], axis=1)
        worst = int(error.argmax())
        if error[worst] > limit:
            point = a + worst + 1
            keep.add(point)
            ranges.extend(((a, point), (point, b)))
    return sorted(keep)


def write_track(lines, i, bone, kind, times, values):
    values = np.array(values)
    if kind == 'rotation_3d':
        for j in range(1, len(values)):
            if np.dot(values[j-1], values[j]) < 0.:
                values[j] *= -1.
    indexes = reduced_keys(values, kind == 'rotation_3d')
    keys = ', '.join(number(x) for j in indexes for x in (times[j], 1., *values[j]))
    lines += [f'tracks/{i}/type = "{kind}"', f'tracks/{i}/path = NodePath(".:{bone}")',
              f'tracks/{i}/interp = 1', f'tracks/{i}/loop_wrap = false',
              f'tracks/{i}/keys = PackedFloat32Array({keys})']


def build(rig):
    lines = ['[gd_resource type="AnimationLibrary" load_steps=4 format=3]', '',
             '; Generated by art/character_models/teacher_b/build_teacher_b_motion.py.',
             '; Bind the player root to the imported Teacher B Skeleton3D.', '']
    for clip, duration in LENGTHS.items():
        times = np.arange(round(duration*FPS)+1) / FPS
        sampled = [rig.sample(clip, t) for t in times]
        lines += [f'[sub_resource type="Animation" id="{clip}"]', f'resource_name = "{clip}"',
                  f'length = {duration}', f'loop_mode = {int(clip == "idle")}', f'step = {1/FPS:.8g}']
        write_track(lines, 0, 'Root', 'position_3d', times, [p for p, _ in sampled])
        animated = [name for name in rig.names if name in sampled[0][1]]
        for i, name in enumerate(animated, 1):
            write_track(lines, i, name, 'rotation_3d', times,
                        [matrix_quaternion(pose[name]) for _, pose in sampled])
        lines.append('')
    lines += ['[resource]', '_data = {', ',\n'.join(f'&"{name}": SubResource("{name}")' for name in LENGTHS), '}', '']
    return '\n'.join(lines)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--check', action='store_true', help='compare a rebuild without writing')
    p.add_argument('--model', type=Path, default=DEV / 'teacher_b.glb')
    p.add_argument('--output', type=Path, default=DEV / 'teacher_b_motion.tres')
    args = p.parse_args()
    result = build(Rig(args.model))
    if args.check:
        if args.output.read_text(encoding='utf-8') != result:
            p.exit(1, f'Rebuild {args.output} using this script\n')
    else:
        args.output.write_text(result, encoding='utf-8')
    print(f'Teacher B animation library: {len(LENGTHS)} original clips, {len(result)} bytes; 0.90 m walk')


if __name__ == '__main__':
    main()
