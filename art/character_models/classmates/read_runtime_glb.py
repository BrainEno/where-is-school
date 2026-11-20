"""Read and sample the glTF subset used by the classmate deformation tests."""

import json
import math
import struct

import numpy as np

COMPONENTS = {5120: 'i1', 5121: 'u1', 5122: '<i2', 5123: '<u2', 5125: '<u4', 5126: '<f4'}
SIZES = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def quat(q):
    x,y,z,w = q
    return np.array([[1-2*(y*y+z*z), 2*(x*y-w*z), 2*(x*z+w*y)],
                     [2*(x*y+w*z), 1-2*(x*x+z*z), 2*(y*z-w*x)],
                     [2*(x*z-w*y), 2*(y*z+w*x), 1-2*(x*x+y*y)]])


def interpolate_quaternion(a, b, t):
    q = a @ b
    if q < 0.:
        q, b = -q, -b
    if q > .9995:
        out = a+(b-a)*t
        return out/np.linalg.norm(out)
    w = math.acos(np.clip(q,-1.,1.))
    return (a*math.sin((1.-t)*w)+b*math.sin(t*w))/math.sin(w)


class Gltf:
    def __init__(self, path):
        self.path = path
        data = path.read_bytes()
        magic, version, size, json_size, tag = struct.unpack_from('<4sIII4s', data)
        if (magic, version, size, tag) != (b'glTF', 2, len(data), b'JSON'):
            raise ValueError(f'Not a valid GLB: {path}')
        self.doc = json.loads(data[20:20+json_size])
        self.bin = memoryview(data)[28+json_size:]

    def arr(self, i):
        a = self.doc['accessors'][i]
        if 'sparse' in a:
            raise ValueError('Sparse GLB attributes are not part of this studio recipe')
        v = self.doc['bufferViews'][a['bufferView']]
        dt = np.dtype(COMPONENTS[a['componentType']])
        width = SIZES[a['type']]
        out = np.ndarray((a['count'], width), dtype=dt, buffer=self.bin,
                         offset=v.get('byteOffset', 0)+a.get('byteOffset', 0),
                         strides=(v.get('byteStride', width*dt.itemsize), dt.itemsize))
        if a.get('normalized') and dt.kind in 'iu':
            out = np.maximum(-1., out.astype(float)/np.iinfo(dt).max)
        return out

    def frame(self, clip, t):
        if clip is None:
            return {}
        a = next(x for x in self.doc['animations'] if x['name']==clip)
        overrides = {}
        for channel in a['channels']:
            sample = a['samplers'][channel['sampler']]
            node, attr = channel['target']['node'], channel['target']['path']
            times = self.arr(sample['input']).ravel()
            vals = self.arr(sample['output']).reshape(len(times),-1)
            k = min(len(times)-1,np.searchsorted(times,t,side='right'))
            j = max(0,k-1)
            u = np.clip((t-times[j])/(times[k]-times[j]),0.,1.) if j<k else 0.
            value = interpolate_quaternion(vals[j],vals[k],u) if attr=='rotation' else vals[j]+(vals[k]-vals[j])*u
            overrides.setdefault(node,{})[attr] = value
        return overrides

    def world(self, frame=None):
        nodes = self.doc['nodes']
        parents = {j:i for i,n in enumerate(nodes) for j in n.get('children', [])}
        w = {}
        frame = frame or {}

        def solve(i):
            if i in w:
                return w[i]
            n = {**nodes[i], **frame.get(i,{})}
            if 'matrix' in n:
                local = np.array(n['matrix'], dtype=float).reshape(4,4).T
            else:
                local = np.eye(4)
                local[:3,:3] = quat(n.get('rotation', [0.,0.,0.,1.])) @ np.diag(n.get('scale', [1.,1.,1.]))
                local[:3,3] = n.get('translation', [0.,0.,0.])
            w[i] = solve(parents[i]) @ local if i in parents else local
            return w[i]
        return [solve(i) for i in range(len(nodes))]

    def surfaces(self, clip=None, time=0., shift=0.):
        frame = self.frame(clip,time)
        world = self.world(frame)
        for i, n in enumerate(self.doc['nodes']):
            if 'mesh' not in n:
                continue
            skin = n.get('skin')
            matrix = None
            if skin is not None:
                s = self.doc['skins'][skin]
                inv = self.arr(s['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
                matrix = np.stack([world[j] for j in s['joints']]) @ inv
            for item in self.doc['meshes'][n['mesh']]['primitives']:
                a = item['attributes']
                p, norm = self.arr(a['POSITION']), self.arr(a['NORMAL'])
                if 'weights' in frame.get(i,{}):
                    for target, value in zip(item.get('targets',()),frame[i]['weights']):
                        if abs(value) > 1e-9:
                            p = p + value*self.arr(target['POSITION'])
                if matrix is not None and 'JOINTS_0' in a:
                    m = np.einsum('nijk,ni->njk', matrix[self.arr(a['JOINTS_0'])], self.arr(a['WEIGHTS_0']))
                    p = np.einsum('nij,nj->ni', m[:,:3,:3], p) + m[:,:3,3]
                    norm = np.einsum('nij,nj->ni', m[:,:3,:3], norm)
                else:
                    m = world[i]
                    p = p @ m[:3,:3].T + m[:3,3]
                    norm = norm @ np.linalg.inv(m[:3,:3])
                norm /= np.maximum(np.linalg.norm(norm,axis=1)[:,None], 1e-9)
                mat = self.doc['materials'][item['material']]
                mr = mat['pbrMetallicRoughness']
                base = np.array(mr.get('baseColorFactor', [1.]*4))
                paint = self.arr(a['COLOR_0'])[:,:3]*base[:3] if 'COLOR_0' in a else np.tile(base[:3], (len(p),1))
                f = self.arr(item['indices']).reshape(-1,3)
                yield mat['name'], p+np.array([shift,0.,0.]), norm, f, paint, mr.get('roughnessFactor',.8), base[3]
