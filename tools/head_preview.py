#!/usr/bin/env python3
"""Write a WISP2 preview scene from a character GLB and render it with head_preview.

    python3 tools/head_preview.py assets/models/protagonist/Protagonist_Character.glb \\
        --look assets/characters/protagonist/protagonist_look.tres \\
        --out build/head_v2/after3 --views front,quarter,side,close

Offline art-review evidence. The scene carries the look's own shader parameters, read from the
.tres, and the head's local detail maps, so `head_preview` reproduces the maths of
`character_paint.gdshaderinc` with the numbers the game draws with. It has no ink outline pass
and no engine light, so its images are labelled "offline renderer" wherever they are reported:
they are not an engine capture.
"""
from __future__ import annotations

import argparse
import re
import struct
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image

import glb_numpy as glb

ROOT = Path(__file__).resolve().parents[1]
VIEWS = {
    'front': ((0.0, 1.57, 0.62), (0.0, 1.565, 0.045), 26.0),
    'quarter': ((0.38, 1.60, 0.50), (0.0, 1.565, 0.045), 26.0),
    'side': ((0.62, 1.58, 0.10), (0.0, 1.565, 0.045), 26.0),
    'back': ((0.0, 1.60, -0.62), (0.0, 1.565, 0.045), 26.0),
    'close': ((0.16, 1.585, 0.34), (0.0, 1.575, 0.085), 30.0),
    'low': ((0.22, 1.50, 0.42), (0.0, 1.565, 0.06), 28.0),
}
HEAD_MESHES = {'Protagonist_Head', 'Protagonist_Hair', 'Protagonist_Eyes'}
# The parts of the look that are painted with the three-band shader, and the one key light the
# preview stands in for the room's DirectionalLight3D with.
LIGHT_DIRECTION = (-0.42, 0.62, 0.66)
LIGHT_COLOUR = (1.0, 0.94, 0.86)
AMBIENT = (0.10, 0.10, 0.12)


# --------------------------------------------------------------------------------------
# .tres reading
# --------------------------------------------------------------------------------------

def _value(text: str):
    text = text.strip()
    if text in ('true', 'false'):
        return text == 'true'
    if text.startswith('"') and text.endswith('"'):
        return text[1:-1]
    match = re.fullmatch(r'(Color|Vector3|Vector2|Vector4|Rect2)\(([^)]*)\)', text)
    if match:
        numbers = [float(part) for part in match.group(2).split(',') if part.strip()]
        return numbers
    match = re.fullmatch(r'(ExtResource|SubResource)\("([^"]+)"\)', text)
    if match:
        return (match.group(1), match.group(2))
    try:
        return float(text)
    except ValueError:
        return text


def _blocks(text: str):
    """Every `[...]` section of a .tres as (header, body)."""
    sections = re.split(r'(?m)^\[', text)[1:]
    for section in sections:
        header, _, body = section.partition(']\n')
        yield header, body


def read_look(path: Path) -> dict:
    """The look's materials (name → shader parameters) and its detail maps (name → maps).

    Only what the preview needs is read: shader parameters of a ShaderMaterial sub-resource,
    and the albedo/normal textures of a `CharacterDetailMaps` sub-resource. Anything else in
    the file is ignored, so a new parameter in the look does not break the preview.
    """
    text = path.read_text()
    ext: dict[str, str] = {}
    sub: dict[str, dict] = {}
    for header, body in _blocks(text):
        kind = header.split(' ', 1)[0]
        attributes = dict(re.findall(r'(\w+)="([^"]*)"', header))
        if kind == 'ext_resource':
            ext[attributes['id']] = attributes.get('path', '')
        elif kind == 'sub_resource':
            resource_id = attributes.get('id', '')
            parameters = {}
            for line in body.splitlines():
                if '=' not in line or line.lstrip().startswith('shader_parameter/'):
                    key, _, raw = line.partition('=')
                    key = key.strip()
                    if key.startswith('shader_parameter/'):
                        parameters[key.split('/', 1)[1]] = _value(raw)
                    elif key in ('albedo', 'normal', 'albedo_mix', 'normal_strength'):
                        parameters[key] = _value(raw)
            sub[resource_id] = {'type': attributes.get('type', ''), 'params': parameters}
    materials: dict[str, dict] = {}
    detail_maps: dict[str, dict] = {}
    for header, body in _blocks(text):
        if not header.startswith('resource'):
            continue
        block = body
        for match in re.finditer(r'"([^"]+)"\s*:\s*SubResource\("([^"]+)"\)', block):
            name, resource_id = match.group(1), match.group(2)
            resource = sub.get(resource_id, {})
            if resource.get('type') == 'ShaderMaterial':
                materials[name] = resource['params']
            elif 'albedo' in resource.get('params', {}) or 'normal' in resource.get('params', {}):
                detail_maps[name] = resource['params']
    return {'materials': materials, 'detail_maps': detail_maps, 'ext': ext}


def _maps_textures(maps: dict, ext: dict[str, str], root: Path) -> tuple[Path | None, Path | None]:
    def resolve(value):
        if not isinstance(value, tuple) or value[0] != 'ExtResource':
            return None
        relative = ext.get(value[1], '')
        if not relative.startswith('res://'):
            return None
        return root / relative[len('res://'):]

    return resolve(maps.get('albedo')), resolve(maps.get('normal'))


# --------------------------------------------------------------------------------------
# Parameters the preview renderer takes
# --------------------------------------------------------------------------------------

def parameter_slots(params: dict) -> list[float]:
    """The 56 floats `head_preview.c` reads, in its slot order."""
    def colour(name, default):
        value = params.get(name, default)
        return list(value[:3]) if isinstance(value, list) else list(default)

    def vector(name, default):
        value = params.get(name, default)
        return list(value[:3]) if isinstance(value, list) else list(default)

    def number(name, default):
        value = params.get(name, default)
        return float(value) if isinstance(value, (int, float)) else float(default)

    slots = [0.0] * 56
    slots[0] = number('pigment_scale', 9.0)
    slots[1:4] = vector('pigment_stretch', (1.0, 2.2, 1.0))
    slots[4] = number('pigment_steps', 4.0)
    slots[5] = number('pigment_value', 0.14)
    slots[6] = number('pigment_mix', 0.3)
    slots[7] = number('pigment_seed', 0.0)
    slots[8] = number('pigment_blend', 0.0)
    slots[9:12] = colour('shade_tint', (0.55, 0.55, 0.7))
    slots[12:15] = colour('light_tint', (1.0, 1.0, 1.0))
    slots[15] = number('shadow_fill', 0.28)
    slots[16] = number('half_tone', 0.62)
    slots[17] = number('shadow_edge', -0.05)
    slots[18] = number('light_edge', 0.42)
    slots[19] = number('edge_softness', 0.05)
    slots[20] = number('light_strength', 0.76)
    slots[21] = number('edge_break', 0.18)
    slots[22] = number('detail_albedo_mix', 1.0)
    slots[23] = number('detail_normal_strength', 1.0)
    slots[24:27] = vector('patch_center', (0.0, 0.0, 0.0))
    slots[27:30] = vector('patch_radius', (0.0, 0.0, 0.0))
    slots[30] = number('patch_strength', 0.0)
    slots[31] = 1.0 if params.get('patch_mirror_x', True) else 0.0
    slots[32:35] = colour('patch_color', (0.4, 0.3, 0.45))
    slots[35:38] = vector('patch2_center', (0.0, 0.0, 0.0))
    slots[38:41] = vector('patch2_radius', (0.0, 0.0, 0.0))
    slots[41] = number('patch2_strength', 0.0)
    slots[42:45] = colour('patch2_color', (0.6, 0.3, 0.25))
    slots[45] = number('mirror_center_x', 0.0)
    slots[46] = number('patch_feather', 0.0)
    slots[47] = 1.0
    slots[48:51] = colour('pigment_a', (0.5, 0.5, 0.5))
    slots[51:54] = colour('pigment_b', (0.5, 0.5, 0.5))
    return slots


def load_texture(path: Path | None) -> tuple[int, int, np.ndarray] | None:
    if path is None or not path.exists():
        return None
    image = Image.open(path).convert('RGB')
    array = np.asarray(image, dtype=np.float32) / 255.0
    return image.width, image.height, array


# --------------------------------------------------------------------------------------
# Geometry
# --------------------------------------------------------------------------------------

def tangents(positions: np.ndarray, normals: np.ndarray, uvs: np.ndarray,
             triangles: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Per-vertex tangent and bitangent from the UV atlas, the way an importer derives them."""
    tangent = np.zeros_like(positions)
    bitangent = np.zeros_like(positions)
    for tri in triangles:
        a, b, c = (int(tri[0]), int(tri[1]), int(tri[2]))
        e1 = positions[b] - positions[a]
        e2 = positions[c] - positions[a]
        du1 = uvs[b, 0] - uvs[a, 0]
        dv1 = uvs[b, 1] - uvs[a, 1]
        du2 = uvs[c, 0] - uvs[a, 0]
        dv2 = uvs[c, 1] - uvs[a, 1]
        det = du1 * dv2 - du2 * dv1
        if abs(det) < 1e-12:
            continue
        factor = 1.0 / det
        direction = (e1 * dv2 - e2 * dv1) * factor
        across = (e2 * du1 - e1 * du2) * factor
        tangent[a] += direction
        tangent[b] += direction
        tangent[c] += direction
        bitangent[a] += across
        bitangent[b] += across
        bitangent[c] += across
    for array in (tangent, bitangent):
        length = np.linalg.norm(array, axis=1, keepdims=True)
        array /= np.maximum(length, 1e-12)
    # Gram-Schmidt against the normal, so a stretched UV island cannot tilt the basis.
    tangent -= normals * np.sum(tangent * normals, axis=1, keepdims=True)
    length = np.linalg.norm(tangent, axis=1, keepdims=True)
    tangent /= np.maximum(length, 1e-12)
    bitangent = np.cross(normals, tangent)
    return tangent, bitangent


def write_scene(path: Path, document: dict, binary: bytes, node_names: set[str], view: str,
                look: dict, detail_maps: bool, size=(640, 640)) -> None:
    eye, target, fov = VIEWS[view]
    objects = []
    for node in document['nodes']:
        if 'mesh' not in node or node.get('name') not in node_names:
            continue
        mesh = document['meshes'][node['mesh']]
        for primitive in mesh['primitives']:
            arrays = glb.primitive_arrays(document, binary, primitive)
            material = document['materials'][primitive['material']]
            name = material.get('name', '')
            key = name.lower()
            params = look['materials'].get(key, {})
            pos = arrays['POSITION']
            normal = arrays['NORMAL']
            uv = arrays.get('TEXCOORD_0', np.zeros((len(pos), 2), dtype=np.float32))
            triangles = arrays['indices'].reshape(-1, 3).astype(np.int64)
            if uv.any():
                tangent, bitangent = tangents(pos, normal, uv, triangles)
            else:
                tangent = np.zeros_like(pos)
                bitangent = np.zeros_like(pos)
            albedo = params.get('albedo', (0.5, 0.5, 0.5))
            colour = (*[float(c) for c in albedo[:3]], 1.0)
            color0 = arrays.get('COLOR_0')
            vertex_colour = np.ones((len(pos), 4), dtype=np.float32)
            if color0 is not None:
                vertex_colour[:, :min(3, color0.shape[1])] = color0[:, :min(3, color0.shape[1])]
            objects.append({
                'name': name, 'colour': colour, 'positions': pos, 'normals': normal,
                'tangent': tangent, 'bitangent': bitangent, 'uvs': uv,
                'vertex_colour': vertex_colour, 'triangles': triangles,
                'params': parameter_slots(params), 'material': key,
            })
    width, height = size
    with path.open('wb') as handle:
        handle.write(b'WISP2')
        handle.write(struct.pack('<II', 2, len(objects)))
        for obj in objects:
            name = obj['name'].encode()[:63]
            handle.write(name.ljust(64, b'\0'))
            handle.write(struct.pack('<4f', *obj['colour']))
            handle.write(struct.pack('<II', len(obj['positions']), len(obj['triangles'])))
            vertices = np.zeros(len(obj['positions']), dtype=[
                ('p', '<f4', 3), ('n', '<f4', 3), ('t', '<f4', 3), ('b', '<f4', 3),
                ('u', '<f4'), ('v', '<f4'), ('c', '<f4', 4)])
            vertices['p'] = obj['positions']
            vertices['n'] = obj['normals']
            vertices['t'] = obj['tangent']
            vertices['b'] = obj['bitangent']
            vertices['u'] = obj['uvs'][:, 0]
            vertices['v'] = obj['uvs'][:, 1]
            vertices['c'] = obj['vertex_colour']
            handle.write(vertices.tobytes())
            handle.write(obj['triangles'].astype('<u4').tobytes())
            handle.write(np.asarray(obj['params'], dtype='<f4').tobytes())
            flags = 0
            albedo_image = normal_image = None
            maps = look['detail_maps'].get(obj['material']) if detail_maps else None
            if maps and obj['uvs'].any():
                albedo_path, normal_path = _maps_textures(maps, look['ext'], ROOT)
                albedo_image = load_texture(albedo_path)
                normal_image = load_texture(normal_path)
                flags |= 1 if albedo_image else 0
                flags |= 2 if normal_image else 0
            handle.write(struct.pack('<I', flags))
            handle.write(struct.pack('<II',
                                     albedo_image[0] if albedo_image else 0,
                                     albedo_image[1] if albedo_image else 0))
            if albedo_image:
                handle.write(albedo_image[2].astype('<f4').tobytes())
            if normal_image:
                handle.write(normal_image[2].astype('<f4').tobytes())
        handle.write(struct.pack('<II', width, height))
        handle.write(struct.pack('<3f', *eye))
        handle.write(struct.pack('<3f', *target))
        handle.write(struct.pack('<3f', 0.0, 1.0, 0.0))
        handle.write(struct.pack('<f', fov))
        handle.write(struct.pack('<3f', *LIGHT_DIRECTION))
        handle.write(struct.pack('<3f', *LIGHT_COLOUR))
        handle.write(struct.pack('<3f', *AMBIENT))


def render(scene: Path, ppm: Path, binary: Path) -> None:
    subprocess.run([str(binary), str(scene), str(ppm)], check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('glb', type=Path)
    parser.add_argument('--look', type=Path, default=None)
    parser.add_argument('--out', type=Path, default=ROOT / 'build/head_v2/preview')
    parser.add_argument('--views', default='front,quarter,side,close')
    parser.add_argument('--no-detail-maps', action='store_true',
                        help='draw the look without its local detail maps (the A/B)')
    parser.add_argument('--width', type=int, default=640)
    parser.add_argument('--height', type=int, default=640)
    args = parser.parse_args()

    document, binary = glb.load(args.glb)
    look = read_look(args.look) if args.look else {'materials': {}, 'detail_maps': {}, 'ext': {}}
    binary_path = ROOT / 'build/head_v2/head_preview'
    if not binary_path.exists():
        binary_path.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['cc', '-O2', '-o', str(binary_path),
                        str(ROOT / 'tools/head_preview.c'), '-lm'], check=True)
    args.out.mkdir(parents=True, exist_ok=True)
    for view in args.views.split(','):
        scene = args.out / f'{view}.wisp2'
        ppm = args.out / f'{view}.ppm'
        write_scene(scene, document, binary, HEAD_MESHES, view, look,
                    detail_maps=not args.no_detail_maps, size=(args.width, args.height))
        render(scene, ppm, binary_path)
        Image.open(ppm).save(args.out / f'{view}.png')
        scene.unlink()
        ppm.unlink()
        print(args.out / f'{view}.png')


if __name__ == '__main__':
    main()
