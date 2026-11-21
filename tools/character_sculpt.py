#!/usr/bin/env python3
"""Install the Blender head layers on an exact pre-sculpt runtime glTF.

Write two float3 streams on the explicitly authored primitives. Only Q has a
replacement hair shell; the protagonist uses the original indexed spike mesh.
No Blender re-export of the rig, animation, expressions or wardrobe is involved.
Blender authoring and export instructions are under art/character_models/sculpt.
"""
from __future__ import annotations

import argparse
import base64
from collections import Counter
import gzip
import hashlib
import json
import struct
from pathlib import Path

from glb_io import COMPONENTS, WIDTH, accessor, decode, encode

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'art/character_models/sculpt'
LAYERS = ART / 'layers.json.gz'
BASE = '25c3410c90a1825337f671648d42c344dbeb1416'
# First sculpt pass as it actually shipped, for revision-specific regression and review.
REVIEW_BASE = 'fd11c183249ef43730fc2fdf36be77cf10669974'
RUNTIME = {
    'lead': 'assets/models/protagonist/Protagonist_Character.glb',
    'q': 'assets/models/q/new-Q.glb',
    'n': 'assets/models/teacher-n/teacher-n.glb',
    'seated': 'assets/models/protagonist/protagonist.glb',
    'thin': 'assets/models/classmates/thin_classmate.glb',
    'gentle': 'assets/models/classmates/gentle_classmate.glb',
    'court': 'assets/models/classmates/court_classmate.glb',
    'b': 'assets/models/teacher_b/teacher_b.glb',
}
# Where each GLB was at BASE and REVIEW_BASE, when it has moved since: B's shipped with the
# imagined lesson and left scenes/dev/ (excluded from exports) with its bytes unchanged.
HISTORIC_PATHS = {'b': 'scenes/dev/teacher_b/teacher_b.glb'}
REMESH = {'q': 'Q_Hair'}


def historic_path(role):
    """The repository path of `role`'s GLB at BASE and REVIEW_BASE."""
    return HISTORIC_PATHS.get(role, RUNTIME[role])


def primitives(document):
    """Iterate in glTF mesh/surface order; the layer uses those unambiguous IDs."""
    for mesh_index, mesh in enumerate(document['meshes']):
        for surface, primitive in enumerate(mesh['primitives']):
            yield (mesh_index, surface), mesh['name'], primitive


def span(document, index):
    """The exact dense accessor's byte range (not the whole bufferView)."""
    item = document['accessors'][index]
    size = struct.calcsize('<' + COMPONENTS[item['componentType']] * WIDTH[item['type']])
    if 'sparse' in item or 'bufferView' not in item:
        raise ValueError('sculpt input must have dense geometry')
    view = document['bufferViews'][item['bufferView']]
    start = view.get('byteOffset', 0) + item.get('byteOffset', 0)
    end = start + item['count'] * size
    if (view['buffer'] != 0 or view.get('byteStride', size) != size
            or end > view.get('byteOffset', 0) + view['byteLength']):
        raise ValueError('unsupported geometry buffer layout')
    return start, end


def fingerprint(document, binary, primitive):
    """Pin indexed rest positions, connectivity and vertex count before transfer."""
    digest = hashlib.sha256()
    for index in (primitive['attributes']['POSITION'], primitive['indices']):
        first, last = span(document, index)
        digest.update(struct.pack('<I', last-first))
        digest.update(binary[first:last])
    return digest.hexdigest()


def record(location, name, base_sha, positions, normals, indices=None):
    data = dict(mesh=location[0], surface=location[1], name=name, rest_sha256=base_sha,
                position=base64.b64encode(positions).decode('ascii'),
                normal=base64.b64encode(normals).decode('ascii'))
    if indices is not None:
        data['indices'] = base64.b64encode(indices).decode('ascii')
    return data


def read_layers(path=LAYERS):
    payload = json.loads(gzip.decompress(path.read_bytes()))
    if payload['version'] != 1 or payload['base'] != BASE or payload['roles'].keys() != RUNTIME.keys():
        raise ValueError('sculpt layer does not cover the reviewed character library')
    return payload['roles']


def _storage_usage(document):
    refs = [p['indices'] for _, _, p in primitives(document)]
    for _, _, p in primitives(document):
        refs.extend(p['attributes'].values())
        refs.extend(i for t in p.get('targets', ()) for i in t.values())
    refs.extend(s['inverseBindMatrices'] for s in document.get('skins', ()))
    refs.extend(s[k] for a in document.get('animations', ()) for s in a['samplers'] for k in ('input', 'output'))
    # Dense/sparse storage otherwise shared is never legal to overwrite.
    views = []
    for item in document['accessors']:
        if 'bufferView' in item:
            views.append(item['bufferView'])
        if 'sparse' in item:
            views.extend(item['sparse'][k]['bufferView'] for k in ('indices', 'values'))
    views.extend(i['bufferView'] for i in document.get('images', ()) if 'bufferView' in i)
    return Counter(refs), Counter(views)


def _install(document, binary, writes):
    out = bytearray(binary)
    refs, views = _storage_usage(document)
    touched = set()
    resized = {}

    def replace(index, payload, *, allow_resize=False):
        item = document['accessors'][index]
        size = struct.calcsize('<' + COMPONENTS[item['componentType']] * WIDTH[item['type']])
        view_id = item['bufferView']
        if refs[index] != 1 or views[view_id] != 1 or index in touched:
            raise ValueError('sculpt cannot replace shared accessor storage')
        start,end = span(document,index)
        if any(other != view_id and v['buffer'] == 0 and v.get('byteOffset', 0) < end
               and v.get('byteOffset', 0)+v['byteLength'] > start
               for other,v in enumerate(document['bufferViews'])):
            raise ValueError('sculpt cannot replace overlapping storage')
        if not allow_resize:
            if len(payload)!=end-start:
                raise ValueError('sculpt point count changed')
            out[start:end] = payload
        else:
            if not payload or len(payload)%size:
                raise ValueError('invalid replacement stream size')
            item['count'] = len(payload)//size
            item.pop('byteOffset',None)
            resized[view_id] = payload
        touched.add(index)
        if 'min' in item or 'max' in item:
            columns = list(zip(*struct.iter_unpack('<'+COMPONENTS[item['componentType']]*WIDTH[item['type']],payload)))
            item['min'] = [min(col) for col in columns]
            item['max'] = [max(col) for col in columns]

    for primitive, position, normal, new_index in writes:
        a = primitive['attributes']
        for attr in ('POSITION','NORMAL'):
            item = document['accessors'][a[attr]]
            if item['componentType'] != 5126 or item['type'] != 'VEC3':
                raise ValueError(f'sculpt expected float3 {attr} data')
        if new_index is not None:
            count = len(position)//12
            ids = primitive['indices']
            if (len(normal)!=len(position) or set(a)!={'POSITION','NORMAL','JOINTS_0','WEIGHTS_0'}
                    or primitive.get('targets') or document['accessors'][ids]['componentType']!=5123
                    or len(new_index)%6 or max(struct.iter_unpack('<H',new_index))[0]>=count):
                raise ValueError('hair replacement requires triangles and a single rigid skin')
            for attr in ('JOINTS_0','WEIGHTS_0'):
                values = accessor(document,binary,a[attr])
                if not values or any(row!=values[0] for row in values[1:]):
                    raise ValueError('refusing to remesh a non-rigid hair surface')
                if attr=='WEIGHTS_0' and values[0]!=(1.,0.,0.,0.):
                    raise ValueError('hair must have one unit joint weight')
                start,end = span(document,a[attr])
                replace(a[attr],binary[start:start+(end-start)//len(values)]*count,allow_resize=True)
            replace(ids,new_index,allow_resize=True)
        replace(a['POSITION'],position,allow_resize=new_index is not None)
        replace(a['NORMAL'],normal,allow_resize=new_index is not None)

    if resized:
        # Update view offsets for the resized shell; copy all other bytes as-is.
        packed = bytearray()
        for i,view in enumerate(document['bufferViews']):
            start = view.get('byteOffset',0)
            block = resized.get(i,out[start:start+view['byteLength']])
            packed.extend(bytes(-len(packed)%4))
            view['byteOffset'],view['byteLength'] = len(packed),len(block)
            packed.extend(block)
        out = packed
        document['buffers'][0]['byteLength'] = len(out)
    return encode(document,bytes(out))


def _writes(document, binary, layers, role):
    lookup = dict((i,(n,p)) for i,n,p in primitives(document))
    used = set()
    for layer in layers:
        i = layer['mesh'], layer['surface']
        name, primitive = lookup[i]
        if (i in used or name != layer['name']
                or fingerprint(document, binary, primitive) != layer['rest_sha256']):
            raise ValueError(f'{name} [{i[1]}] no longer matches the Blender sculpt basis')
        used.add(i)
        replacement = base64.b64decode(layer['indices'],validate=True) if 'indices' in layer else None
        if (replacement is not None) != (name == REMESH.get(role)):
            raise ValueError(f'{role}: topology changes are permitted only on the standalone hair shell')
        yield primitive, base64.b64decode(layer['position'],validate=True), base64.b64decode(layer['normal'],validate=True), replacement
    if not used:
        raise ValueError('empty sculpt layer')


def apply(data: bytes, role: str, path: Path = LAYERS) -> bytes:
    document, binary = decode(data)
    if role == 'seated':
        # The existing student materials use this extension without declaring
        # it. Register it without changing any material fields or requiring it.
        extensions = {k for m in document['materials'] for k in m.get('extensions',())}
        if extensions != {'KHR_materials_specular'}:
            raise ValueError('student material extension set changed')
        document['extensionsUsed'] = sorted(extensions)
    return _install(document, binary, _writes(document, binary, read_layers(path)[role], role))


def apply_split(base: bytes, split: bytes, role: str) -> bytes:
    """Apply exactly the same edits to the B/classmate builders' unbatched source.

    Batch concatenates parts before serialization, so each split part's vertices
    still have identical rest positions and material names; it just has its own
    glTF mesh. All occurrences of a rest position must get the same displacement.
    Normals are paired as well to retain deliberate hard seams.
    """
    doc, binary = decode(base)
    material_maps = {}
    pack = struct.Struct('<fff').pack
    for p, position, normal, _ in _writes(doc, binary, read_layers()[role],role):
        material = doc['materials'][p['material']]['name']
        table = material_maps.setdefault(material,{})
        a = p['attributes']
        for old_p, old_n, new_p, new_n in zip(accessor(doc,binary,a['POSITION']), accessor(doc,binary,a['NORMAL']),
                                              struct.iter_unpack('<fff',position),struct.iter_unpack('<fff',normal), strict=True):
            key = (*old_p, *old_n)
            previous = table.setdefault(key, (pack(*new_p),pack(*new_n)))
            if previous != (pack(*new_p), pack(*new_n)):
                raise ValueError(f'{role}: ambiguous split normal/position in {material}')
    split_doc, split_binary = decode(split)
    writes = []
    seen = {name:set() for name in material_maps}
    for _,_,p in primitives(split_doc):
        material = split_doc['materials'][p['material']]['name']
        table = material_maps.get(material)
        if table is None:
            continue
        a = p['attributes']
        rows = []
        matched = 0
        for pos,norm in zip(accessor(split_doc,split_binary,a['POSITION']),
                            accessor(split_doc,split_binary,a['NORMAL']),strict=True):
            key = (*pos,*norm)
            value = table.get(key)
            rows.append(value or (pack(*pos),pack(*norm)))
            if value is not None:
                matched += 1
                seen[material].add(key)
        if matched:
            position,normal = zip(*rows)
            writes.append((p,b''.join(position),b''.join(normal),None))
    if any(seen[name]!=table.keys() for name,table in material_maps.items()):
        raise ValueError(f'{role}: split parts no longer match the reviewed sculpt vertices')
    return _install(split_doc, split_binary, writes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('role', choices=RUNTIME)
    parser.add_argument('base', type=Path, help='pre-sculpt runtime GLB')
    parser.add_argument('output', type=Path, help='output path; must differ from base')
    args = parser.parse_args()
    if args.base.resolve() == args.output.resolve():
        parser.error('use separate basis and output paths')
    args.output.write_bytes(apply(args.base.read_bytes(), args.role))


if __name__ == '__main__':
    main()
