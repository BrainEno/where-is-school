"""Offline GLB rasteriser for character review.

No Blender and no GPU on this machine, so review images are made by a small
z-buffered scanline rasteriser: read the GLB, apply the node hierarchy, project
with a perspective camera, shade with one key light plus a fill and ambient.

This exists so character work can be *looked at* rather than inferred from
vertex statistics. It renders the same file the game imports.
"""
from __future__ import annotations

import json
import struct

import numpy as np

COMPONENT = {5120: 'i1', 5121: 'u1', 5122: '<i2', 5123: '<u2', 5125: '<u4', 5126: '<f4'}
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


class Glb:
    def __init__(self, path):
        data = open(path, 'rb').read()
        magic, version, length = struct.unpack('<III', data[:12])
        if magic != 0x46546C67:
            raise ValueError('not a GLB')
        offset, chunks = 12, []
        while offset < length:
            size, kind = struct.unpack('<II', data[offset:offset + 8])
            offset += 8
            chunks.append((kind, data[offset:offset + size]))
            offset += size
        self.json = json.loads(chunks[0][1].decode('utf-8'))
        self.bin = chunks[1][1] if len(chunks) > 1 else b''

    def accessor(self, index):
        acc = self.json['accessors'][index]
        view = self.json['bufferViews'][acc['bufferView']]
        width = WIDTH[acc['type']]
        dtype = np.dtype(COMPONENT[acc['componentType']]).newbyteorder('<')
        start = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
        stride = view.get('byteStride') or width * dtype.itemsize
        if stride == width * dtype.itemsize:
            flat = np.frombuffer(self.bin, dtype=dtype, count=acc['count'] * width,
                                 offset=start)
            return flat.reshape(acc['count'], width)
        rows = np.frombuffer(self.bin, dtype=np.uint8,
                             count=stride * acc['count'], offset=start)
        rows = rows.reshape(acc['count'], stride)[:, :width * dtype.itemsize]
        return np.ascontiguousarray(rows).view(dtype).reshape(acc['count'], width)

    # --- scene graph -------------------------------------------------------
    def world_nodes(self):
        """Every mesh instance with its world matrix (rest pose; skins ignored)."""
        nodes = self.json['nodes']
        out = []

        def walk(i, parent):
            node = nodes[i]
            m = np.eye(4)
            if 'matrix' in node:
                m = np.array(node['matrix'], float).reshape(4, 4).T
            elif any(k in node for k in ('translation', 'rotation', 'scale')):
                t = node.get('translation', [0, 0, 0])
                s = node.get('scale', [1, 1, 1])
                x, y, z, w = node.get('rotation', [0, 0, 0, 1])
                r = np.array([
                    [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                    [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                    [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
                m = np.eye(4)
                m[:3, :3] = r * np.array(s)
                m[:3, 3] = t
            world = parent @ m
            if 'mesh' in node:
                out.append((node['mesh'], world, node.get('name', '')))
            for child in node.get('children', []):
                walk(child, world)

        for scene in self.json.get('scenes', []):
            for root in scene['nodes']:
                walk(root, np.eye(4))
        return out

    def instances(self):
        """Yield (mesh_name, material_name, positions, triangles, base_color)."""
        materials = self.json.get('materials', [])
        for mesh_index, world, node_name in self.world_nodes():
            mesh = self.json['meshes'][mesh_index]
            for prim in mesh['primitives']:
                pos = self.accessor(prim['attributes']['POSITION']).astype(np.float64)
                pos = np.c_[pos, np.ones(len(pos))] @ world.T
                if 'indices' in prim:
                    idx = self.accessor(prim['indices']).reshape(-1, 3).astype(np.int64)
                else:
                    idx = np.arange(len(pos)).reshape(-1, 3)
                mat = materials[prim['material']] if 'material' in prim else {}
                pbr = mat.get('pbrMetallicRoughness', {})
                colour = pbr.get('baseColorFactor', [0.8, 0.8, 0.8, 1])
                if 'NORMAL' in prim['attributes']:
                    nrm = self.accessor(prim['attributes']['NORMAL']).astype(np.float64)
                    nrm = nrm @ np.linalg.inv(world[:3, :3]).T
                else:
                    nrm = None
                yield (mesh['name'], mat.get('name', '-'), pos[:, :3], idx,
                       np.array(colour[:3], float), pbr.get('roughnessFactor', .5), nrm)


def look_at(eye, target, up=(0, 1, 0)):
    eye = np.asarray(eye, float)
    target = np.asarray(target, float)
    fwd = target - eye
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, np.asarray(up, float))
    if np.linalg.norm(right) < 1e-9:
        right = np.cross(fwd, np.array([0, 0, 1.0]))
    right /= np.linalg.norm(right)
    upv = np.cross(right, fwd)
    m = np.eye(4)
    m[0, :3], m[1, :3], m[2, :3] = right, upv, -fwd
    m[:3, 3] = -m[:3, :3] @ eye
    return m


def perspective(fov_deg, aspect, near, far):
    f = 1 / np.tan(np.radians(fov_deg) / 2)
    m = np.zeros((4, 4))
    m[0, 0] = f / aspect
    m[1, 1] = f
    m[2, 2] = (far + near) / (near - far)
    m[2, 3] = 2 * far * near / (near - far)
    m[3, 2] = -1
    return m


def render(glb, eye, target, size=(900, 900), fov=30, near=.02, far=20,
           key=np.array([-.45, .62, -.65]), fill=.32, ambient=.26, bg=(.10, .10, .12),
           material_filter=None, occlusion=True):
    """Z-buffered render. Returns float RGB image in 0..1."""
    w, h = size
    view = look_at(eye, target)
    proj = perspective(fov, w / h, near, far)
    mvp = proj @ view
    image = np.zeros((h, w, 3), np.float32) + np.array(bg, np.float32)
    zbuf = np.full((h, w), np.inf, np.float32)

    # Camera-space normals and positions are needed for shading.
    normal_matrix = np.linalg.inv(view)[:3, :3]
    light = np.asarray(key, float)
    light /= np.linalg.norm(light)
    light_view = normal_matrix.T @ light
    light_view /= np.linalg.norm(light_view)
    fill_dir = np.array([0.7, -0.15, 0.7])
    fill_dir /= np.linalg.norm(fill_dir)

    for name, material, pos, idx, colour, rough, nrm in glb.instances():
        if material_filter and not material_filter(name, material):
            continue
        if indices_skip := (len(idx) == 0):
            continue
        clip = np.c_[pos, np.ones(len(pos))] @ mvp.T
        wcomp = clip[:, 3]
        vis = wcomp > near * .5
        clip = clip[vis]
        wcomp = wcomp[vis]
        ndc = clip[:, :3] / wcomp[:, None]
        screen = np.empty((len(ndc), 2))
        screen[:, 0] = (ndc[:, 0] * .5 + .5) * w
        screen[:, 1] = (1 - (ndc[:, 1] * .5 + .5)) * h
        depth = ndc[:, 2]

        # Vertex normals carried to view space; they are interpolated per pixel.
        if nrm is not None:
            vn = nrm.copy()
        else:
            p0, p1, p2 = pos[idx[:, 0]], pos[idx[:, 1]], pos[idx[:, 2]]
            fn = np.cross(p1 - p0, p2 - p0)
            vn = np.zeros_like(pos)
            for corner in range(3):
                np.add.at(vn, idx[:, corner], fn)
        vn = vn @ view[:3, :3].T
        vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)
        tone = np.clip(colour, 0, 1)  # baseColorFactor is already linear

        remap = np.full(len(pos), -1, np.int64)
        remap[vis] = np.arange(vis.sum())
        tri = idx[(remap[idx] >= 0).all(1)]
        tri = remap[tri]
        # Keep triangles that survive the near plane.
        tri = tri[(depth[tri] > -1).all(1)]
        if not len(tri):
            continue
        face_vis = (remap[idx] >= 0).all(1)
        fnorm = vn[tri]
        order = np.argsort(-(depth[tri].mean(1)))
        _rasterise(image, zbuf, screen[tri][order], depth[tri][order],
                   fnorm[order], tone, w, h, light_view, fill_dir @ view[:3, :3].T,
                   ambient, fill)
    return image


def _rasterise(image, zbuf, tris, depths, normals, tone, w, h, light, fill_dir,
               ambient, fill):
    for tri, dz, normal in zip(tris, depths, normals):
        x = tri[:, 0]
        y = tri[:, 1]
        xmin, xmax = int(np.floor(x.min())), int(np.ceil(x.max()))
        ymin, ymax = int(np.floor(y.min())), int(np.ceil(y.max()))
        if xmax < 0 or ymax < 0 or xmin >= w or ymin >= h:
            continue
        xmin, ymin = max(xmin, 0), max(ymin, 0)
        xmax, ymax = min(xmax, w - 1), min(ymax, h - 1)
        if xmax < xmin or ymax < ymin:
            continue
        px, py = np.meshgrid(np.arange(xmin, xmax + 1) + .5,
                             np.arange(ymin, ymax + 1) + .5)
        d = (x[1] - x[0]) * (y[2] - y[0]) - (x[2] - x[0]) * (y[1] - y[0])
        if abs(d) < 1e-12:
            continue
        a = ((x[1] - px) * (y[2] - py) - (x[2] - px) * (y[1] - py)) / d
        b = ((x[2] - px) * (y[0] - py) - (x[0] - px) * (y[2] - py)) / d
        c = 1 - a - b
        inside = (a >= 0) & (b >= 0) & (c >= 0)
        if not inside.any():
            continue
        z = a * dz[0] + b * dz[1] + c * dz[2]
        sub = zbuf[ymin:ymax + 1, xmin:xmax + 1]
        hit = inside & (z < sub)
        if not hit.any():
            continue
        sub[hit] = z[hit]
        # Interpolate the vertex normals, then shade each covered pixel.
        n = (a[..., None] * normal[0] + b[..., None] * normal[1]
             + c[..., None] * normal[2])
        n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-12)
        lam = np.abs(n @ light)
        lam2 = np.abs(n @ fill_dir)
        shade = np.clip(ambient + (1 - ambient) * (lam * .80 + lam2 * fill), 0, 1.35)
        pixel = np.clip(tone[None, None, :] * shade[..., None], 0, 1)
        image[ymin:ymax + 1, xmin:xmax + 1][hit] = pixel[hit]


def save(image, path, gamma=True):
    from PIL import Image
    rgb = np.clip(image, 0, 1)
    if gamma:
        rgb = rgb ** (1 / 2.2)
    Image.fromarray((rgb * 255).astype(np.uint8)).save(path)
