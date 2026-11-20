"""Small glTF writer for the Teacher B source. All points and joints use metres.

The sculpting coordinates are X across, Y up and +Z forward. Only the export
reflects Z to match the game's -Z convention. Neither the skin nor its parent
carries scale. Embedded weights and inverse binds are real glTF skin data.
"""

import json
import math
import struct
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np


@dataclass
class Piece:
    name: str
    points: np.ndarray
    faces: np.ndarray
    color: np.ndarray  # sRGB RGB, optional fourth channel is a linear paint mask
    material: str
    weights: np.ndarray
    morphs: dict[str, np.ndarray] = field(default_factory=dict)


def batch_materials(pieces):
    """One draw surface per material, with the morph-ready face kept separate."""
    groups = {}
    for p in pieces:
        key = (p.material, p.name if p.morphs else '')
        groups.setdefault(key, []).append(p)
    result = []
    for (material, _name), group in groups.items():
        if len(group) == 1:
            result.append(group[0])
            continue
        offset = 0
        faces = []
        for p in group:
            faces.append(p.faces + offset)
            offset += len(p.points)
        result.append(Piece(material, np.concatenate([p.points for p in group]), np.concatenate(faces),
                            np.concatenate([p.color for p in group]), material,
                            np.concatenate([p.weights for p in group])))
    return result


def unit(v):
    return v / max(float(np.linalg.norm(v)), 1e-12)


def matrix_quaternion(m):
    """Return glTF's XYZW rotation for a proper orthonormal matrix."""
    t = np.trace(m)
    if t > 0:
        s = 2 * math.sqrt(1 + t)
        return [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s,
                (m[1, 0] - m[0, 1]) / s, s * 0.25]
    i = int(np.argmax(m.diagonal()))
    j, k = (i + 1) % 3, (i + 2) % 3
    s = 2 * math.sqrt(1 + m[i, i] - m[j, j] - m[k, k])
    q = np.zeros(4)
    q[i], q[j], q[k], q[3] = s * .25, (m[i, j] + m[j, i]) / s, (m[i, k] + m[k, i]) / s, (m[k, j] - m[j, k]) / s
    return q.tolist()


def normals(points, faces):
    n = np.zeros_like(points)
    tri = points[faces]
    cross = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    for column in faces.T:
        np.add.at(n, column, cross)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    return n


def linear_rgb(srgb):
    return np.where(srgb < .04045, srgb / 12.92, ((srgb + .055) / 1.055) ** 2.4)


class GLB:
    def __init__(self):
        self.data = bytearray()
        self.views = []
        self.accessors = []

    def accessor(self, array, kind, component=5126, bounds=False, normalized=False):
        dtype = {5126: '<f4', 5123: '<u2', 5121: 'u1'}[component]
        packed = np.ascontiguousarray(array, dtype=dtype)
        start = len(self.data)
        b = packed.tobytes()
        self.data.extend(b)
        self.data.extend(bytes((-len(b)) % 4))
        view = len(self.views)
        self.views.append({'buffer': 0, 'byteOffset': start, 'byteLength': len(b)})
        if kind != 'MAT4':
            self.views[-1]['target'] = 34963 if kind == 'SCALAR' else 34962
        a = {'bufferView': view, 'componentType': component, 'count': len(packed), 'type': kind}
        if bounds:
            a.update(min=packed.min(axis=0).tolist(), max=packed.max(axis=0).tolist())
        if normalized:
            a['normalized'] = True
        self.accessors.append(a)
        return len(self.accessors) - 1

    def write(self, path, pieces, bones, materials, height, character='Teacher B', *,
              compact=False, animate=None):
        ground = min(float(p.points[:, 1].min()) for p in pieces)
        ceiling = max(float(p.points[:, 1].max()) for p in pieces)
        depth_axis = .5 * (bones['Foot_L'][1][2] + bones['Foot_R'][1][2])
        center = np.array((0., ground, depth_axis))
        scale = height / (ceiling - ground)
        flip = np.array((1., 1., -1.))
        nodes, world = [], []
        ids = {name: i for i, name in enumerate(bones)}
        for name, (parent, head, tail) in bones.items():
            up = unit((tail - head) * flip)
            across = np.array((1., 0., 0.))
            if abs(np.dot(up, across)) > .92:
                across = np.array((0., 0., 1.))
            side = unit(across - np.dot(up, across) * up)
            mat = np.eye(4)
            mat[:3, :3] = np.stack((side, up, np.cross(side, up)), axis=1)
            mat[:3, 3] = (head - center) * flip * scale
            world.append(mat)
            local = mat if parent is None else np.linalg.solve(world[ids[parent]], mat)
            node = {'name': name, 'translation': local[:3, 3].tolist(), 'rotation': matrix_quaternion(local[:3, :3])}
            nodes.append(node)
            if parent is not None:
                nodes[ids[parent]].setdefault('children', []).append(ids[name])
        inverse = np.linalg.inv(np.stack(world)).transpose(0, 2, 1).reshape(-1, 16)
        inv = self.accessor(inverse, 'MAT4')
        primitive_meshes = []
        for p in pieces:
            points = (p.points - center) * flip * scale
            faces = p.faces[:, [0, 2, 1]]
            order = np.argsort(-p.weights, axis=1, kind='stable')[:, :4]
            weight = np.take_along_axis(p.weights, order, axis=1)
            weight /= np.maximum(weight.sum(axis=1, keepdims=True), 1e-12)
            if (weight.sum(axis=1) < .99).any():
                raise ValueError(f'{p.name} contains unskinned vertices')
            # Keep fine face/hair gradients at 16 bits in the compact variant.
            # Four components keep byte attributes aligned. Quantized weights
            # sum to exactly the integer max; zero-weight joints are cleared.
            color16 = not compact or p.morphs or (p.material.startswith('hair_') or p.material == 'eye_paint')
            color_max, color_type = (65535, 5123) if color16 else (255, 5121)
            weight_max, weight_type = (255, 5121) if compact else (65535, 5123)
            color = np.round(color_max * linear_rgb(np.clip(p.color[:, :3], 0., 1.)))
            mask = np.round(color_max*np.clip(p.color[:, 3], 0., 1.)) if p.color.shape[1] == 4 else np.full(len(p.points), color_max)
            color = np.column_stack((color, mask))
            weight = np.rint(weight_max * weight).astype(np.int32)
            weight[:, 0] += weight_max - weight.sum(axis=1)
            order[weight == 0] = 0
            if len(points) > 65535:
                raise ValueError(f'Split {p.name} to keep 16-bit indices')
            prim = {
                'attributes': {
                    'POSITION': self.accessor(points, 'VEC3', bounds=True),
                    'NORMAL': self.accessor(normals(points, faces), 'VEC3'),
                    'COLOR_0': self.accessor(color, 'VEC4', color_type, normalized=True),
                    'JOINTS_0': self.accessor(order, 'VEC4', 5121),
                    'WEIGHTS_0': self.accessor(weight, 'VEC4', weight_type, normalized=True),
                },
                'indices': self.accessor(faces.ravel(), 'SCALAR', 5123),
                'material': list(materials).index(p.material),
            }
            mesh = {'name': p.name, 'primitives': [prim]}
            if p.morphs:
                prim['targets'] = [{'POSITION': self.accessor(d * flip * scale, 'VEC3', bounds=True)} for d in p.morphs.values()]
                mesh['extras'] = {'targetNames': list(p.morphs)}
                mesh['weights'] = [0.0] * len(p.morphs)
            nodes.append({'name': p.name, 'mesh': len(primitive_meshes), 'skin': 0})
            primitive_meshes.append(mesh)
        out_mats = []
        for name, (rough, metal, alpha) in materials.items():
            entry = {'name': name, 'pbrMetallicRoughness': {'baseColorFactor': [1., 1., 1., alpha],
                                                          'roughnessFactor': rough, 'metallicFactor': metal}}
            if alpha < 1.:
                entry.update(alphaMode='BLEND', doubleSided=True)
            out_mats.append(entry)
        document = {
            'asset': {'version': '2.0', 'generator': f'Where Is School — {character} modelling source'},
            'scene': 0, 'scenes': [{'name': character, 'nodes': [0, *range(len(bones), len(nodes))]}],
            'nodes': nodes, 'meshes': primitive_meshes, 'materials': out_mats,
            'skins': [{'name': f'{character} deform rig', 'skeleton': 0, 'joints': list(ids.values()), 'inverseBindMatrices': inv}],
            'buffers': [{'byteLength': len(self.data)}], 'bufferViews': self.views, 'accessors': self.accessors,
        }
        if animate is not None:
            document['animations'] = animate(self, document)
            document['buffers'][0]['byteLength'] = len(self.data)
        js = json.dumps(document, ensure_ascii=False, separators=(',', ':')).encode()
        js += b' ' * ((-len(js)) % 4)
        binary = self.data
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(struct.pack('<4sII', b'glTF', 2, 28 + len(js) + len(binary))
                         + struct.pack('<I4s', len(js), b'JSON') + js
                         + struct.pack('<I4s', len(binary), b'BIN\0') + binary)
        print(f'{path}: {len(bones)} joints, {sum(len(p.faces) for p in pieces)} triangles, '
              f'{len(out_mats)} materials, {len(pieces)} surfaces, {scale:.5f} stature scale, {path.stat().st_size} bytes')
