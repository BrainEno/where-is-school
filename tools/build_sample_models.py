"""Writes the two glTF 2.0 sample models the asset pipeline is proved against.

The repository had no model of any kind: every 3D thing in it is Godot primitives,
either authored by hand in a `.tscn` or emitted by
`tools/build_outdoor_locations.py`. That is fine for a graybox and useless as a
contract — the first real Blender export would arrive with an unknown scale, an
unknown forward axis, an unknown pivot and no collision, and nothing in CI would
notice.

So this script writes two **placeholder** models in the format the pipeline accepts,
from boxes, deterministically:

    python3 tools/build_sample_models.py            # write the .glb files
    python3 tools/build_sample_models.py --check    # fail if the committed files differ

`--check` is what CI runs: the committed bytes must be reproducible from this
script, so the script is the provenance and the .glb is a build artefact, exactly
like `tools/generate_placeholder_audio.py` and the audio files it writes.

These are not art. They exist to be imported, wrapped, placed, measured and
replaced. See `docs/ASSET_PIPELINE.md` for the import contract and the numbers the
acceptance test holds them to.
"""

import json
import os
import struct
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "models", "sample")

# --- glTF 2.0 binary writer -------------------------------------------------

# Component types and targets, spelled out rather than imported: this file has no
# dependencies, so it runs on a clean checkout with nothing but python3.
FLOAT = 5126
UNSIGNED_SHORT = 5123
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963


def _corners(box):
    """The eight corners of an axis-aligned box, as (x, y, z) tuples."""
    x0, y0, z0, x1, y1, z1 = box
    return [
        (x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1),
        (x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1),
    ]


# Each face as an index quad into `_corners`, with the outward normal it should have.
# The winding is corrected below rather than trusted: a box with an inverted face is
# invisible in Godot (back faces are culled), which would look like a modelling
# mistake instead of a writer bug.
_FACES = [
    ((0, 1, 2, 3), (0, -1, 0)),   # bottom
    ((4, 7, 6, 5), (0, 1, 0)),    # top
    ((0, 4, 5, 1), (0, 0, -1)),   # back  (-Z, the model's forward)
    ((3, 2, 6, 7), (0, 0, 1)),    # front (+Z)
    ((0, 3, 7, 4), (-1, 0, 0)),   # left
    ((1, 5, 6, 2), (1, 0, 0)),    # right
]


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def mesh_from_boxes(boxes):
    """Flat-shaded triangles for a list of axis-aligned boxes.

    Flat shading means four separate vertices per face (twenty-four per box): a
    shared corner would average the normals and turn a chair into a pillow.
    """
    positions = []
    normals = []
    indices = []

    for box in boxes:
        corners = _corners(box)
        for quad, normal in _FACES:
            base = len(positions)
            ordered = [corners[index] for index in quad]
            # Counter-clockwise when seen from outside: the cross product of the
            # first two edges has to point the same way as the declared normal.
            winding = _cross(_sub(ordered[1], ordered[0]), _sub(ordered[2], ordered[1]))
            if _dot(winding, normal) < 0.0:
                ordered = list(reversed(ordered))
            for corner in ordered:
                positions.append(corner)
                normals.append(normal)
            indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])

    return positions, normals, indices


def _pack_floats(values):
    flat = []
    for value in values:
        flat.extend(value)
    return struct.pack("<%df" % len(flat), *flat)


def build_glb(name, boxes, material, generator_note):
    """A single-mesh, single-material GLB, Y up, metres, origin at the floor."""
    positions, normals, indices = mesh_from_boxes(boxes)
    position_bytes = _pack_floats(positions)
    normal_bytes = _pack_floats(normals)
    index_bytes = struct.pack("<%dH" % len(indices), *indices)

    binary = position_bytes + normal_bytes + index_bytes
    padding = (-len(binary)) % 4
    binary += b"\x00" * padding

    xs = [p[0] for p in positions]
    ys = [p[1] for p in positions]
    zs = [p[2] for p in positions]

    gltf = {
        "asset": {"version": "2.0", "generator": generator_note},
        "scene": 0,
        "scenes": [{"nodes": [0], "name": name}],
        "nodes": [{"mesh": 0, "name": name}],
        "meshes": [
            {
                "name": name,
                "primitives": [
                    {
                        "attributes": {"POSITION": 0, "NORMAL": 1},
                        "indices": 2,
                        "material": 0,
                        "mode": 4,
                    }
                ],
            }
        ],
        "materials": [
            {
                "name": material["name"],
                "pbrMetallicRoughness": {
                    "baseColorFactor": list(material["color"]),
                    "metallicFactor": material.get("metallic", 0.0),
                    "roughnessFactor": material.get("roughness", 0.9),
                },
                "doubleSided": False,
            }
        ],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": len(position_bytes), "target": ARRAY_BUFFER},
            {
                "buffer": 0,
                "byteOffset": len(position_bytes),
                "byteLength": len(normal_bytes),
                "target": ARRAY_BUFFER,
            },
            {
                "buffer": 0,
                "byteOffset": len(position_bytes) + len(normal_bytes),
                "byteLength": len(index_bytes),
                "target": ELEMENT_ARRAY_BUFFER,
            },
        ],
        "accessors": [
            {
                "bufferView": 0,
                "componentType": FLOAT,
                "count": len(positions),
                "type": "VEC3",
                "min": [min(xs), min(ys), min(zs)],
                "max": [max(xs), max(ys), max(zs)],
            },
            {
                "bufferView": 1,
                "componentType": FLOAT,
                "count": len(normals),
                "type": "VEC3",
            },
            {
                "bufferView": 2,
                "componentType": UNSIGNED_SHORT,
                "count": len(indices),
                "type": "SCALAR",
            },
        ],
        "buffers": [{"byteLength": len(binary)}],
    }

    json_bytes = json.dumps(gltf, separators=(",", ":"), sort_keys=True).encode("utf-8")
    json_bytes += b" " * ((-len(json_bytes)) % 4)

    total = 12 + 8 + len(json_bytes) + 8 + len(binary)
    out = struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<I4s", len(json_bytes), b"JSON")
    out += json_bytes
    out += struct.pack("<I4s", len(binary), b"BIN\x00")
    out += binary
    return out


# --- the two samples --------------------------------------------------------

# A plastic stackable chair: 0.52 m square, 0.92 m to the top of the back, origin on
# the floor at the centre of the footprint, back towards +Z so the seat faces -Z
# (the forward axis the contract documents).
CHAIR_BOXES = [
    (-0.26, 0.42, -0.26, 0.26, 0.47, 0.26),    # seat
    (-0.26, 0.47, 0.21, 0.26, 0.92, 0.26),     # back rest
    (-0.26, 0.0, -0.26, -0.21, 0.42, -0.21),   # front left leg
    (0.21, 0.0, -0.26, 0.26, 0.42, -0.21),     # front right leg
    (-0.26, 0.0, 0.21, -0.21, 0.42, 0.26),     # back left leg
    (0.21, 0.0, 0.21, 0.26, 0.42, 0.26),       # back right leg
]

# A standing figure at the game's scale: 1.72 m tall, 0.44 m across the shoulders,
# origin between the feet, facing -Z.
FIGURE_BOXES = [
    (-0.16, 0.0, -0.09, -0.02, 0.84, 0.09),    # left leg
    (0.02, 0.0, -0.09, 0.16, 0.84, 0.09),      # right leg
    (-0.22, 0.84, -0.13, 0.22, 1.40, 0.13),    # torso
    (-0.30, 0.90, -0.07, -0.22, 1.38, 0.07),   # left arm
    (0.22, 0.90, -0.07, 0.30, 1.38, 0.07),     # right arm
    (-0.11, 1.40, -0.11, 0.11, 1.62, 0.11),    # neck and jaw
    (-0.13, 1.62, -0.13, 0.13, 1.72, 0.13),    # head
]

SAMPLES = [
    {
        "file": "chair.glb",
        "name": "SampleChair",
        "boxes": CHAIR_BOXES,
        "material": {"name": "sample_chair_plastic", "color": (0.42, 0.47, 0.44, 1.0),
                     "roughness": 0.75},
        "note": "where-is-school sample chair (placeholder, tools/build_sample_models.py)",
        "expected": {"height": 0.92, "width": 0.52, "depth": 0.52},
    },
    {
        "file": "figure.glb",
        "name": "SampleFigure",
        "boxes": FIGURE_BOXES,
        "material": {"name": "sample_figure_cloth", "color": (0.55, 0.52, 0.47, 1.0),
                     "roughness": 0.9},
        "note": "where-is-school sample figure (placeholder, tools/build_sample_models.py)",
        "expected": {"height": 1.72, "width": 0.60, "depth": 0.26},
    },
]


def write(target_dir):
    os.makedirs(target_dir, exist_ok=True)
    written = []
    for sample in SAMPLES:
        data = build_glb(sample["name"], sample["boxes"], sample["material"], sample["note"])
        path = os.path.join(target_dir, sample["file"])
        with open(path, "wb") as handle:
            handle.write(data)
        written.append((path, len(data)))
    return written


def main(argv):
    if "--check" in argv:
        with tempfile.TemporaryDirectory() as tmp:
            written = write(tmp)
            drift = []
            for path, size in written:
                name = os.path.basename(path)
                committed = os.path.join(OUT_DIR, name)
                if not os.path.exists(committed):
                    drift.append("%s is missing from assets/models/sample" % name)
                    continue
                with open(path, "rb") as fresh, open(committed, "rb") as old:
                    if fresh.read() != old.read():
                        drift.append(
                            "%s differs from what this script writes (%d bytes)"
                            % (name, size)
                        )
            if drift:
                for line in drift:
                    print("SAMPLE_MODEL_DRIFT: " + line)
                print("Re-run python3 tools/build_sample_models.py and commit the result.")
                return 1
            print("SAMPLE_MODELS_OK: both committed models are byte-identical to a fresh build.")
            return 0

    for path, size in write(OUT_DIR):
        print("wrote %s (%d bytes)" % (path.replace(ROOT + "/", ""), size))
    for sample in SAMPLES:
        expected = sample["expected"]
        print(
            "  %s: %.2f x %.2f x %.2f m (w x h x d), %d boxes"
            % (
                sample["file"],
                expected["width"],
                expected["height"],
                expected["depth"],
                len(sample["boxes"]),
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
