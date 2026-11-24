"""Rebuild a binary glTF while replacing selected primitives.

The character models carry their rig, animation, skin and material tables in one
BIN chunk. A head revision only changes two primitives, so the rest of the document
is copied byte-for-byte and only the buffer layout is rewritten. This is the same
contract `tools/character_sculpt.py` uses for its baked position/normal streams,
generalised to new vertex counts, attributes and sparse morph targets.

Only the pieces the character pipeline needs are implemented: one BIN buffer, dense
or sparse accessors, and triangle primitives. Images, cameras and extensions that
add buffers are not supported and fail loudly.
"""
from __future__ import annotations

import json
import struct

import numpy as np

COMPONENT_DTYPE = {
    5120: np.dtype('<i1'), 5121: np.dtype('<u1'),
    5122: np.dtype('<i2'), 5123: np.dtype('<u2'),
    5125: np.dtype('<u4'), 5126: np.dtype('<f4'),
}
DTYPE_COMPONENT = {v: k for k, v in COMPONENT_DTYPE.items()}
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def decode(data: bytes) -> tuple[dict, bytes]:
    if data[:4] != b'glTF':
        raise ValueError('not a binary glTF')
    version, size = struct.unpack_from('<II', data, 4)
    json_size, kind = struct.unpack_from('<II', data, 12)
    if version != 2 or size != len(data) or kind != 0x4E4F534A:
        raise ValueError('invalid glTF header')
    document = json.loads(data[20:20 + json_size])
    offset = 20 + json_size
    bin_size, kind = struct.unpack_from('<II', data, offset)
    if kind != 0x004E4942 or offset + 8 + bin_size != len(data):
        raise ValueError('expected a single embedded BIN chunk')
    return document, data[offset + 8:]


def encode(document: dict, binary: bytes) -> bytes:
    text = json.dumps(document, separators=(',', ':'), ensure_ascii=False).encode()
    text += b' ' * (-len(text) % 4)
    binary += b'\0' * (-len(binary) % 4)
    size = 12 + 8 + len(text) + 8 + len(binary)
    return (struct.pack('<4sII', b'glTF', 2, size)
            + struct.pack('<II', len(text), 0x4E4F534A) + text
            + struct.pack('<II', len(binary), 0x004E4942) + binary)


def view_bytes(document: dict, binary: bytes, index: int) -> bytes:
    view = document['bufferViews'][index]
    start = view.get('byteOffset', 0)
    return binary[start:start + view['byteLength']]


def accessor_used_views(document: dict, index: int) -> list[int]:
    item = document['accessors'][index]
    views = []
    if 'bufferView' in item:
        views.append(item['bufferView'])
    if 'sparse' in item:
        views.append(item['sparse']['indices']['bufferView'])
        views.append(item['sparse']['values']['bufferView'])
    return views


class Builder:
    """Append-only buffer/accessor builder for one BIN chunk."""

    def __init__(self) -> None:
        self.binary = bytearray()
        self.views: list[dict] = []
        self.accessors: list[dict] = []

    def _view(self, payload: bytes, target: int | None = None) -> int:
        self.binary += b'\0' * (-len(self.binary) % 4)
        offset = len(self.binary)
        self.binary += payload
        view = {'buffer': 0, 'byteOffset': offset, 'byteLength': len(payload)}
        if target is not None:
            view['target'] = target
        self.views.append(view)
        return len(self.views) - 1

    def dense(self, values: np.ndarray, component_type: int, type_name: str,
              normalized: bool = False, target: int | None = None) -> int:
        array = np.ascontiguousarray(values)
        dtype = np.dtype(COMPONENT_DTYPE[component_type]).newbyteorder('<')
        payload = array.astype(dtype).tobytes()
        view = self._view(payload, target)
        item = {
            'bufferView': view,
            'componentType': component_type,
            'count': int(array.shape[0]),
            'type': type_name,
        }
        if normalized:
            item['normalized'] = True
        self.accessors.append(item)
        return len(self.accessors) - 1

    def sparse(self, indices: np.ndarray, values: np.ndarray, count: int,
               component_type: int, type_name: str,
               index_component_type: int = 5123) -> int:
        indices = np.ascontiguousarray(indices.astype(np.dtype(COMPONENT_DTYPE[index_component_type]).newbyteorder('<')))
        index_view = self._view(indices.tobytes(), 34963)
        dtype = np.dtype(COMPONENT_DTYPE[component_type]).newbyteorder('<')
        values = np.ascontiguousarray(values).astype(dtype)
        value_view = self._view(values.tobytes(), 34962)
        self.accessors.append({
            'componentType': component_type,
            'count': int(count),
            'type': type_name,
            'sparse': {
                'count': int(len(indices)),
                'indices': {'bufferView': index_view, 'componentType': index_component_type},
                'values': {'bufferView': value_view},
            },
        })
        return len(self.accessors) - 1


def replace_primitives(data: bytes, replacements: dict) -> bytes:
    """Return a new GLB with `(mesh, primitive)` replaced.

    `replacements[(mesh, primitive)]` is a dict:
      attributes: {name: (array, component_type, type_name, normalized)}
      indices: array
      targets: [{name: (array, component_type, type_name)}]  (deltas, sparse)
    Every other accessor, bufferView, node, skin, animation and material is copied.
    """
    document, binary = decode(data)
    if len(document.get('buffers', [])) != 1:
        raise ValueError('only one BIN buffer is supported')
    if document.get('images'):
        raise ValueError('embedded images are not supported by this editor')

    # Which accessors belong to the replaced primitives?
    replaced_accessors: set[int] = set()
    for (mesh_index, primitive_index) in replacements:
        primitive = document['meshes'][mesh_index]['primitives'][primitive_index]
        replaced_accessors.update(primitive['attributes'].values())
        replaced_accessors.add(primitive['indices'])
        for target in primitive.get('targets', []):
            replaced_accessors.update(target.values())

    # Which views are used by an accessor that survives?
    surviving_views: set[int] = set()
    for index, _item in enumerate(document['accessors']):
        if index in replaced_accessors:
            continue
        surviving_views.update(accessor_used_views(document, index))
    # Also images (unsupported) would go here.

    builder = Builder()
    view_map: dict[int, int] = {}
    for old_index, view in enumerate(document['bufferViews']):
        if old_index not in surviving_views:
            continue
        payload = view_bytes(document, binary, old_index)
        new_index = builder._view(payload, view.get('target'))
        view_map[old_index] = new_index

    accessor_map: dict[int, int] = {}
    for old_index, item in enumerate(document['accessors']):
        if old_index in replaced_accessors:
            continue
        new_item = dict(item)
        if 'bufferView' in new_item:
            new_item['bufferView'] = view_map[new_item['bufferView']]
        if 'sparse' in new_item:
            new_item['sparse'] = json.loads(json.dumps(new_item['sparse']))
            new_item['sparse']['indices']['bufferView'] = view_map[new_item['sparse']['indices']['bufferView']]
            new_item['sparse']['values']['bufferView'] = view_map[new_item['sparse']['values']['bufferView']]
        builder.accessors.append(new_item)
        accessor_map[old_index] = len(builder.accessors) - 1

    # Rewrite every surviving accessor reference in the document.
    def remap(value):
        if isinstance(value, dict):
            return {k: remap(v) for k, v in value.items()}
        if isinstance(value, list):
            return [remap(v) for v in value]
        return value

    # Accessors are referenced by index in primitives, skins and animations.
    for mesh_index, mesh in enumerate(document['meshes']):
        for primitive_index, primitive in enumerate(mesh['primitives']):
            if (mesh_index, primitive_index) in replacements:
                continue
            if 'indices' in primitive:
                primitive['indices'] = accessor_map[primitive['indices']]
            primitive['attributes'] = {k: accessor_map[v] for k, v in primitive['attributes'].items()}
            for target in primitive.get('targets', []):
                for name in list(target):
                    target[name] = accessor_map[target[name]]
    for skin in document.get('skins', []):
        if 'inverseBindMatrices' in skin:
            skin['inverseBindMatrices'] = accessor_map[skin['inverseBindMatrices']]
    for animation in document.get('animations', []):
        for sampler in animation['samplers']:
            sampler['input'] = accessor_map[sampler['input']]
            sampler['output'] = accessor_map[sampler['output']]

    for (mesh_index, primitive_index), replacement in sorted(replacements.items()):
        primitive = document['meshes'][mesh_index]['primitives'][primitive_index]
        attributes = {}
        for name, spec in replacement['attributes'].items():
            values, component_type, type_name = spec[:3]
            normalized = spec[3] if len(spec) > 3 else False
            attributes[name] = builder.dense(values, component_type, type_name, normalized)
        primitive['attributes'] = attributes
        indices = replacement['indices']
        primitive['indices'] = builder.dense(indices, 5125 if indices.max() > 65535 else 5123, 'SCALAR')
        targets = []
        for target in replacement.get('targets', []):
            entry = {}
            for name, (values, component_type, type_name) in target.items():
                dense = np.asarray(values)
                mask = np.any(np.abs(dense) > 1e-7, axis=1)
                idx = np.nonzero(mask)[0]
                entry[name] = builder.sparse(idx, dense[idx], len(dense), component_type, type_name)
            targets.append(entry)
        primitive['targets'] = targets

    document['bufferViews'] = builder.views
    document['accessors'] = builder.accessors
    document['buffers'] = [{'byteLength': len(builder.binary)}]
    return encode(document, bytes(builder.binary))
