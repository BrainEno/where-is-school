"""Author the original classmate performances as portable glTF channels.

Angles are in the character's rest-world axes (Y up, -Z forward). Bake absolute
local quaternions at 10/15 Hz; runtime needs neither Python nor retargeting.
The walk is IN PLACE. A movement controller may advance the actor at SPEED.
"""
from __future__ import annotations

import math

import numpy as np

from build_teacher_b_motion import Rig as PlantRig, basis, smooth, timing
from designs import ACTING
from skinned_glb import matrix_quaternion, unit

KEYS = tuple(ACTING)
SIGNATURES = {key: action[0] for key, action in ACTING.items()}
SPEED = dict(zip(KEYS, (.89, .87, 1.11)))
PERIOD = dict(zip(KEYS, (1.18, 1.28, 1.12)))
LENGTH = dict(zip(KEYS, (3.16, 3.72, 3.22)))
SIDES = ('L', 'R')


def axis_turn(axis, radians):
    return basis((*tuple(unit(axis) * math.sin(.5*radians)), math.cos(.5*radians)))


def degrees(angles):
    out = np.eye(3)
    for a, v in zip(angles, np.eye(3)):
        out = axis_turn(v, math.radians(a)) @ out
    return out


def bell(t, middle, half):
    return smooth(1. - abs(t-middle)/half)


class Performance(PlantRig):
    """Only borrows the first-party two-bone foot plant and rest math from B."""

    def __init__(self, key, doc, sole):
        self.key = key
        self.i = KEYS.index(key)
        self.ids = {doc['nodes'][j]['name']: j for j in doc['skins'][0]['joints']}
        parents = {c: n['name'] for n in doc['nodes'] for c in n.get('children', ())}
        self.parent, self.loc, self.local, self.rest, self.point = {}, {}, {}, {}, {}
        for name, j in self.ids.items():
            n = doc['nodes'][j]
            parent = parents.get(j)
            self.parent[name] = parent
            self.loc[name] = np.array(n['translation'])
            self.local[name] = basis(n['rotation'])
            self.rest[name] = self.rest[parent] @ self.local[name] if parent else self.local[name]
            self.point[name] = self.point[parent] + self.rest[parent] @ self.loc[name] if parent else self.loc[name]
        self.sole = {side: sole[sole[:, 0]*sign > .019]-self.point['Foot_'+side]
                     for side, sign in zip(SIDES, (1., -1.))}
        self.palm = {}
        for side, sign in zip(SIDES, (1., -1.)):
            palm = self.point['Index01_'+side] - self.point['Little01_'+side]
            down = self.point['Middle01_'+side] - self.point['Hand_'+side]
            self.palm[side] = self.rest['Hand_'+side].T @ unit(np.cross(palm,down)*sign)

    def foot(self, t, side, walking):
        roll = np.eye(3)
        stride = lift = 0.
        if walking:
            f = (t/PERIOD[self.key]+(.50 if side == 'R' else 0.)) % 1.
            cycle = PERIOD[self.key] * SPEED[self.key]
            half = .300*cycle
            # 60% ground contact. In-place contact runs opposite the actor's
            # matching root translation, then the shoe swings forward.
            if f < .60:
                stride = -half + cycle*f
                pitch = timing(f, [(0., -6.), (.095, 0.), (.47, 0.), (.60, 10.)])
            else:
                u = (f-.60)/.40
                stride = half - 2.*half*smooth(u)
                lift = (.042,.039,.059)[self.i]*math.sin(math.pi*u)**1.6
                pitch = timing(u, [(0., 10.), (.37, 5.), (.81, -8.), (1., -6.)])
            roll = degrees((pitch,0.,0.))
        foot = self.point['Foot_'+side]
        y = lift - np.min(self.sole[side] @ roll[1])
        return np.array([foot[0],y,foot[2]+stride]), roll @ self.rest['Foot_'+side]

    def world_rotation(self, name, pose):
        p = self.parent[name]
        local = pose.get(name,self.local[name])
        return self.world_rotation(p, pose) @ local if p else local

    def open_palm(self, side, pose, strength):
        hand = 'Hand_'+side
        fore = 'Forearm_'+side
        parent = self.world_rotation(fore, pose)
        original = parent @ pose[hand]
        axis = original[:,1]
        normal = original @ self.palm[side]
        up_and_forward = np.array([.10,.84,-.52])
        aim = unit(up_and_forward - axis * (up_and_forward @ axis))
        normal = unit(normal - axis * (normal @ axis))
        turn = math.atan2(axis @ np.cross(normal,aim), normal @ aim)
        # Limit the combined pronation. Distribute rotation between wrist and
        # forearm so both the rolled cuff and the hand stay attached.
        turn = np.clip(turn,-1.77,1.77)*strength
        grand = self.world_rotation(self.parent[fore], pose)
        new_forearm = axis_turn(parent[:,1],turn*.54) @ parent
        pose[fore] = grand.T @ new_forearm
        pose[hand] = new_forearm.T @ axis_turn(axis,turn) @ original

    def sample(self, clip, t):
        i, key = self.i, self.key
        walking, acting = clip == 'walk_in_place', clip == SIGNATURES[key]
        time = t/PERIOD[key] if walking else t/4.
        a = math.tau*time
        swing = math.cos(a)*float(walking)
        breath = (.5-.5*math.cos(math.tau*t/4.)) if not walking and not acting else 0.
        el, lift, nod, glance, smirk, speech = [0.]*6
        if acting:
            if i == 0:
                lift = timing(t, [(0.,0.),(.46,.05),(.96,.90),(1.36,1.),(1.73,.78),
                                   (2.09,.86),(2.66,0.)])
                el = .30*lift
                glance = timing(t,[(0.,0.),(.51,10.),(1.67,12.),(2.9,0.)])
                nod = 7.*lift-3.*bell(t,2.20,.49)
                speech = .60*bell(t,1.31,.29)+.42*bell(t,1.88,.26)
            elif i == 1:
                nod = timing(t,[(0.,0.),(.29,-2.2),(.67,8.3),(1.10,0.),(1.91,2.3),(2.82,0.)])
                lift = timing(t,[(0.,0.),(.64,0.),(1.31,.89),(1.75,1.),(2.21,.91),(2.75,.46),(3.37,0.)])
                el = lift
                glance = -3.8*lift
                smirk = .58*lift
                speech = .38*bell(t,1.66,.23)+.43*bell(t,2.11,.25)
            else:
                lift = timing(t,[(0.,0.),(.43,.16),(1.28,1.),(1.80,.88),(2.46,.16),(3.21,0.)])
                nod = -2.2*lift
                glance = -19.*lift+5.*bell(t,2.42,.43)
                smirk = .23*lift
        elif not walking:
            glance = (3.7,-2.9,5.3)[i]*breath
        lean = (3.6,.8,1.0)[i]
        step_width = (.011,.020,.027)[i]
        # Enough pelvis drop for both planted legs, with a subtle double beat.
        root = self.loc['Root'] + np.array([
            step_width*math.sin(a) if walking else (.006,-.009,.017)[i]*lift,
            (-.063+.012*math.cos(2.*a)) if walking else (-.010+.0032*breath),
            (-.006 if walking else -.011*lift)])
        angles = {
            'Hips': ((.8,-.4,-1.7)[i],-4.2*swing,-2.0*swing),
            'Spine': (lean+.8*breath+1.8*walking,-1.6*swing,-.8*swing),
            'Chest': (.9*breath+1.4*lift,6.0*swing-5.0*lift,-1.9*lift),
            'Neck': (-.46*lean,.31*glance,.72*lift),
            'Head': (-.73*lean+nod,.69*glance,(2.4,-1.7,-3.9)[i]*lift+.8*breath),
            'UpperArm_L': (2.2-11.5*swing+(7.,18.,1.3)[i]*lift,-3.5*el,(-3.,-2.,.6)[i]+3.*el),
            'Forearm_L': (5.7+2.1*swing+(29.,65.,9.)[i]*lift,14.0*el,-7.0*el),
            'Hand_L': (1.5-5.0*el,0.,-2.9*el),
            'UpperArm_R': (1.0+10.8*swing+(19.,1.,5.)[i]*lift,3.9*lift,(2.7,1.5,-.5)[i]+1.8*lift),
            'Forearm_R': (5.9-2.1*swing+(48.,2.1,15.)[i]*lift,2.6*lift,(7.,.3,-1.8)[i]*lift),
            'Hand_R': (-3.+(4.,1.,-8.)[i]*lift,4.5*lift,(4.,0.,-8.)[i]*lift),
        }
        for side, sign in zip(SIDES,(-1.,1.)):
            opening = el if side == 'L' and i == 1 else .16*lift
            # Different rests and curls, with the middle phalanx driving the
            # bend rather than rotating the entire finger as one segment.
            for d, base in zip(('Thumb','Index','Middle','Ring','Little'), (4.,9.,12.,15.,16.)):
                for j, portion in enumerate((.61,1.00,.58),1):
                    angles[f'{d}{j:02d}_{side}'] = (.8*el if j==1 else 0.,0.,
                                                sign*portion*base*(1.-.74*opening+.16*(i==2)))
        pose = {n:self.local_rotation(n, r) for n,r in angles.items()}
        if el > 0. and i == 1:
            self.open_palm('L', pose, el)
        shoes = {s:self.foot(t,s,walking) for s in SIDES}
        hips = self.rest['Root'] @ pose['Hips']
        for side, (ankle, _) in shoes.items():
            thigh, knee, foot = (n+'_'+side for n in ('Thigh','LowerLeg','Foot'))
            leg = (np.linalg.norm(self.point[knee]-self.point[thigh]) +
                   np.linalg.norm(self.point[foot]-self.point[knee]) - .0025)
            offset = self.rest['Root'] @ self.loc['Hips'] + hips @ self.loc[thigh]
            delta = ankle - root - offset
            allowed = math.sqrt(max(0., leg*leg-delta[0]**2-delta[2]**2))
            root[1] = min(root[1],ankle[1]+allowed-offset[1])
        self.ground_legs(pose,root,shoes)
        blink = max(bell(t,.90+0.31*i,.102), bell(t,3.18+.093*i,.095)) if not walking else 0.
        expressions = np.array([blink,blink,smirk,speech])
        return root, pose, expressions


def bake(key, writer, doc):
    def accessor(values, kind, bounds=False):
        if kind=='SCALAR':
            values = values.reshape(-1,1)
        index = writer.accessor(values,kind,bounds=bounds)
        writer.views[writer.accessors[index]['bufferView']].pop('target',None)
        return index

    node = next(i for i,n in enumerate(doc['nodes']) if 'mesh' in n and
                doc['meshes'][n['mesh']].get('extras',{}).get('targetNames'))
    # Batched and editable geometry use the same shoes. Read the actual sole
    # and its extremal vertices from the position accessor written above.
    mats = doc['materials']
    views = []
    for m in doc['meshes']:
        for p in m['primitives']:
            if mats[p['material']]['name'] != 'shoe_sole':
                continue
            a = doc['accessors'][p['attributes']['POSITION']]
            off = doc['bufferViews'][a['bufferView']]['byteOffset']
            views.append(np.frombuffer(writer.data,dtype='<f4',count=a['count']*3,offset=off).reshape(-1,3).copy())
    sole = np.concatenate(views)
    rig = Performance(key, doc, sole)
    clips = []
    for name, duration, fps in [('idle',4.,9),('walk_in_place',PERIOD[key],15),
                                 (SIGNATURES[key],LENGTH[key],12)]:
        samples = round(duration*fps)+1
        t = sorted(set([*np.linspace(0.,duration,samples), *([.9+.31*rig.i,3.18+.093*rig.i]
                       if name=='idle' else [.9+.31*rig.i] if name==SIGNATURES[key] else [])]))
        frames = [rig.sample(name,time) for time in t]
        time = accessor(np.array(t),'SCALAR',bounds=True)
        start = accessor(np.array([0.]),'SCALAR',bounds=True)
        channels, samplers = [], []

        def channel(j, path, values, kind, constant=False):
            index = accessor(np.asarray(values[:1] if constant else values),kind)
            channels.append({'sampler':len(samplers),'target':{'node':j,'path':path}})
            samplers.append({'input':start if constant else time,'output':index,'interpolation':'LINEAR'})

        channel(rig.ids['Root'],'translation',[f[0] for f in frames],'VEC3')
        for n in frames[0][1]:
            r = np.stack([f[1][n] for f in frames])
            constant = np.max(np.abs(r-r[0])) < 5e-7
            if constant and np.max(np.abs(r[0]-rig.local[n])) < 5e-7:
                continue
            q = np.array([matrix_quaternion(m) for m in r])
            for j in range(1,len(q)):
                if q[j] @ q[j-1] < 0.:
                    q[j] *= -1.
            channel(rig.ids[n],'rotation',q,'VEC4',constant=constant)
        if name != 'walk_in_place':
            channel(node,'weights',np.stack([f[2] for f in frames]).ravel(),'SCALAR')
        clips.append({'name':name,'samplers':samplers,'channels':channels})
    return clips
