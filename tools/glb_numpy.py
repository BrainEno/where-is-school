"""NumPy readers for the binary glTF files in the repository.

The repository's `glb_io.py` is the canonical stdlib reader and stays the source of
truth for byte-level contracts. This module only turns an accessor into a NumPy array
for geometry work; it preserves normalized-component scaling, sparse storage and
byteStride, which is everything the character models use.
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


def accessor(document: dict, binary: bytes, index: int) -> np.ndarray:
    item = document['accessors'][index]
    width = WIDTH[item['type']]
    dtype = np.dtype(COMPONENT_DTYPE[item['componentType']]).newbyteorder('<')
    count = item['count']
    result = np.zeros((count, width), dtype=np.float64)
    if 'bufferView' in item:
        view = document['bufferViews'][item['bufferView']]
        size = dtype.itemsize * width
        stride = view.get('byteStride', size)
        start = view.get('byteOffset', 0) + item.get('byteOffset', 0)
        if stride == size:
            result = np.frombuffer(binary, dtype=dtype, count=count * width, offset=start).reshape(count, width).astype(np.float64)
        else:
            raw = np.frombuffer(binary, dtype=np.uint8, count=stride * count, offset=start).reshape(count, stride)
            packed = raw[:, :size].copy().view(dtype).reshape(count, width)
            result = packed.astype(np.float64)
        if item.get('normalized'):
            info = np.iinfo(dtype)
            result = np.maximum(result / info.max, -1.0) if info.min < 0 else result / info.max
    if 'sparse' in item:
        sparse = item['sparse']
        idx_dtype = np.dtype(COMPONENT_DTYPE[sparse['indices']['componentType']]).newbyteorder('<')
        val_dtype = dtype
        idx_view = document['bufferViews'][sparse['indices']['bufferView']]
        val_view = document['bufferViews'][sparse['values']['bufferView']]
        idx_start = idx_view.get('byteOffset', 0) + sparse['indices'].get('byteOffset', 0)
        val_start = val_view.get('byteOffset', 0) + sparse['values'].get('byteOffset', 0)
        indices = np.frombuffer(binary, dtype=idx_dtype, count=sparse['count'], offset=idx_start).astype(np.int64)
        size = val_dtype.itemsize * width
        stride = val_view.get('byteStride', size)
        if stride == size:
            values = np.frombuffer(binary, dtype=val_dtype, count=sparse['count'] * width, offset=val_start).reshape(-1, width).astype(np.float64)
        else:
            raw = np.frombuffer(binary, dtype=np.uint8, count=stride * sparse['count'], offset=val_start).reshape(sparse['count'], stride)
            values = raw[:, :size].copy().view(val_dtype).reshape(-1, width).astype(np.float64)
        if item.get('normalized'):
            info = np.iinfo(val_dtype)
            values = np.maximum(values / info.max, -1.0) if info.min < 0 else values / info.max
        result[indices] = values
    return result


def primitive_arrays(document: dict, binary: bytes, primitive: dict) -> dict:
    arrays = {name: accessor(document, binary, index) for name, index in primitive['attributes'].items()}
    arrays['indices'] = accessor(document, binary, primitive['indices']).astype(np.int64).reshape(-1)
    arrays['targets'] = [
        {name: accessor(document, binary, index) for name, index in target.items()}
        for target in primitive.get('targets', [])
    ]
    return arrays


def load(path) -> tuple[dict, bytes]:
    data = open(path, 'rb').read()
    return decode(data)
