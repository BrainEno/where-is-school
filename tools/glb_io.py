"""Single-BIN glTF 2 helpers; accessor reads preserve sparse and interleaved data."""
from __future__ import annotations

import json
import struct

COMPONENTS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def decode(data: bytes) -> tuple[dict, bytes]:
    if len(data) < 28 or data[:4] != b"glTF":
        raise ValueError("not a binary glTF")
    version, size = struct.unpack_from("<II", data, 4)
    json_size, kind = struct.unpack_from("<II", data, 12)
    if version != 2 or size != len(data) or kind != 0x4E4F534A:
        raise ValueError("invalid glTF header")
    document = json.loads(data[20:20 + json_size])
    offset = 20 + json_size
    bin_size, kind = struct.unpack_from("<II", data, offset)
    if kind != 0x004E4942 or offset + 8 + bin_size != len(data):
        raise ValueError("expected a single embedded BIN chunk")
    return document, data[offset + 8:]


def encode(document: dict, binary: bytes) -> bytes:
    text = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode()
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    size = 12 + 8 + len(text) + 8 + len(binary)
    return (struct.pack("<4sII", b"glTF", 2, size)
            + struct.pack("<II", len(text), 0x4E4F534A) + text
            + struct.pack("<II", len(binary), 0x004E4942) + binary)


def accessor(document: dict, binary: bytes, index: int) -> list[tuple]:
    item = document["accessors"][index]
    width = WIDTH[item["type"]]
    fmt = "<" + COMPONENTS[item["componentType"]] * width
    size = struct.calcsize(fmt)
    result = [(0,) * width for _ in range(item["count"])]
    if "bufferView" in item:
        view = document["bufferViews"][item["bufferView"]]
        stride = view.get("byteStride", size)
        start = view.get("byteOffset", 0) + item.get("byteOffset", 0)
        result = [struct.unpack_from(fmt, binary, start + row * stride)
                  for row in range(item["count"])]
    if "sparse" in item:
        sparse = item["sparse"]
        indices, values = sparse["indices"], sparse["values"]
        index_fmt = "<" + COMPONENTS[indices["componentType"]]
        index_size = struct.calcsize(index_fmt)
        index_start = (document["bufferViews"][indices["bufferView"]].get("byteOffset", 0)
                       + indices.get("byteOffset", 0))
        value_start = (document["bufferViews"][values["bufferView"]].get("byteOffset", 0)
                       + values.get("byteOffset", 0))
        for row in range(sparse["count"]):
            index = struct.unpack_from(index_fmt, binary, index_start + row * index_size)[0]
            result[index] = struct.unpack_from(fmt, binary, value_start + row * size)
    return result
