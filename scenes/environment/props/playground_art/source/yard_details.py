"""Authored meshes for the playable yard, in metres. No runtime geometry or collision.

The bedding, newsprint and film are shaped UV meshes; the fittings are grouped on
existing supports so they inherit the level's occlusion behaviour. The view from the
teaching block keeps its cheaper silhouettes, not these close-up pieces.
"""

from __future__ import annotations

import hashlib
import math
import sys
from pathlib import Path


def _box(b, parent, name, size, pos, material, rot=None, *, shadow=False):
    b.flat(name, parent, b.mesh("BoxMesh", size=_v3(size)), material, pos, rot, shadow=shadow)


def _v3(values):
    return "Vector3(" + ", ".join(f"{value:g}" for value in values) + ")"


def _cylinder(b, parent, name, r, height, pos, material, rot=None, *, foot=None, sides=14, shadow=False):
    mesh = b.mesh("CylinderMesh", top_radius=r, bottom_radius=r if foot is None else foot,
                  height=height, radial_segments=sides, rings=0)
    b.flat(name, parent, mesh, material, pos, rot, shadow=shadow)


def _ring(b, inner, outer):
    return b.mesh("TorusMesh", inner_radius=inner, outer_radius=outer, rings=18, ring_segments=8)


def tap(b, art):
    b.node("TapDetail", art, position=_v3((-6, 0, 14)))
    p = f"{art}/TapDetail"
    _cylinder(b, p, "Standpipe", 0.075, 1.67, (0, 0.872, 0), "tap_steel", shadow=True)
    _cylinder(b, p, "Foot", 0.121, 0.052, (0, 0.031, 0), "exit_frame", foot=0.151)
    _cylinder(b, p, "FootCollar", 0.099, 0.124, (0, 0.115, 0), "exit_steel", foot=0.111)
    _cylinder(b, p, "PipePlug", 0.087, 0.095, (0, 1.744, 0), "exit_steel", foot=0.087, sides=8)
    _cylinder(b, p, "UnionNut", 0.082, 0.115, (0.081, 1.566, 0), "exit_steel", (0, 0, -90), sides=6)
    _cylinder(b, p, "Bib", 0.055, 0.228, (0.196, 1.566, 0), "tap_steel", (0, 0, -90), foot=0.064)
    _cylinder(b, p, "Elbow", 0.055, 0.146, (0.323, 1.53, 0), "tap_steel", (0, 0, 43), foot=0.069)
    b.flat("OutletRim", p, _ring(b, 0.033, 0.062), "exit_steel", (0.365, 1.475, 0))
    _cylinder(b, p, "OutletBore", 0.041, 0.009, (0.365, 1.479, 0), "metal_ink")
    _cylinder(b, p, "Bonnet", 0.047, 0.083, (0.227, 1.613, 0), "brass", foot=0.061, sides=8)
    _cylinder(b, p, "Stem", 0.028, 0.085, (0.227, 1.670, 0), "exit_steel")
    b.node("Wheel", p, position=_v3((0.227, 1.707, 0)))
    wheel = f"{p}/Wheel"
    b.flat("Rim", wheel, _ring(b, 0.077, 0.107), "fire_door", (0, 0, 0))
    for i, angle in enumerate((0, 60, 120)):
        _box(b, wheel, f"Spoke{i}", (0.167, 0.022, 0.018), (0, 0, 0), "fire_door", (0, angle, 0))
    _cylinder(b, wheel, "Retainer", 0.026, 0.031, (0, 0.009, 0), "exit_steel", sides=8)

    # The rubber-faced brass stopper is hooked onto a collar, not set in the drain.
    _cylinder(b, p, "HookCollar", 0.085, 0.039, (0, 1.248, 0), "exit_frame")
    b.flat("HookEye", p, _ring(b, 0.022, 0.039), "exit_steel", (0.094, 1.237, 0.024), (90, 0, 0))
    link = _ring(b, 0.013, 0.021)
    for i in range(6):
        b.flat(f"Link{i}", p, link, "exit_steel", (0.11 + 0.003 * i, 1.213 - 0.03 * i, 0.034),
               (90, 83 * (i % 2), 0))
    _cylinder(b, p, "CapGasket", 0.091, 0.042, (0.143, 1.006, 0.035), "exit_frame", (0, 0, -83))
    _cylinder(b, p, "Cap", 0.086, 0.023, (0.168, 1.008, 0.035), "brass", (0, 0, -83))

    # The grating sits flush in a concrete repair. The black below the bars gives
    # the slots depth; it is not a flat metal slab or a new surface in navigation.
    b.flat("Runoff", p, b.mesh("PlaneMesh", size="Vector2(1.64, 1.22)"), "tap_runoff", (0.4, 0.011, 0.17))
    b.node("Drain", p, position=_v3((0.6, 0, 0.3)))
    drain = f"{p}/Drain"
    _box(b, drain, "Mortar", (0.8, 0.028, 0.6), (0, 0.014, 0), "concrete_patch")
    _box(b, drain, "Recess", (0.605, 0.013, 0.394), (0, 0.027, 0), "metal_ink")
    for key, side in (("Left", -1), ("Right", 1)):
        _box(b, drain, "End" + key, (0.044, 0.027, 0.463), (side * 0.305, 0.035, 0), "exit_frame")
        _box(b, drain, "Side" + key, (0.596, 0.027, 0.039), (0, 0.035, side * 0.212), "exit_frame")
    bar = b.mesh("BoxMesh", size=_v3((0.027, 0.017, 0.386)))
    for i in range(9):
        b.flat(f"Bar{i}", drain, bar, "tap_steel", (0.064 * (i - 4), 0.038, 0))


def shed(b):
    # Local +Z is out to the yard, so all this facade work follows the same wall fade.
    b.node("Facade", "ShedBody", position=_v3((3, -1.5, 0)), rotation_degrees=_v3((0, 90, 0)))
    p = "ShedBody/Facade"
    _box(b, p, "Skirt", (7.90, 0.24, 0.05), (0, 0.13, 0.018), "plinth")
    # The dark reveal and slit under the door are visual only; the existing check
    # cannot actually change the exterior wall or open a navigable room.
    _box(b, p, "DoorReveal", (1.21, 2.24, 0.080), (0, 1.12, 0.052), "exit_frame")
    _box(b, p, "Door", (1.084, 2.135, 0.056), (0, 1.125, 0.107), "door_green")
    _box(b, p, "DoorLightGap", (0.987, 0.029, 0.012), (0, 0.045, 0.111), "plinth")
    _box(b, p, "Sill", (1.22, 0.029, 0.195), (0, 0.016, 0.092), "exit_steel")
    for key, side in (("Latch", -1), ("Hinge", 1)):
        _box(b, p, key + "Jamb", (0.07, 2.24, 0.134), (side * 0.578, 1.12, 0.071), "exit_frame")
    _box(b, p, "Lintel", (1.24, 0.079, 0.148), (0, 2.215, 0.083), "exit_frame")
    for i, x in enumerate((-0.29, 0, 0.29)):
        _box(b, p, f"Pressing{i}", (0.109, 1.91, 0.025), (x, 1.145, 0.132), "door_green")
    for i, y in enumerate((0.292, 1.935)):
        _box(b, p, f"HingeLeaf{i}", (0.139, 0.12, 0.024), (0.501, y, 0.148), "exit_steel")
        _cylinder(b, p, f"HingePin{i}", 0.026, 0.152, (0.553, y, 0.167), "exit_frame", sides=10)
    _box(b, p, "OldPaintPatch", (0.252, 0.14, 0.004), (-0.402, 1.103, 0.148), "shed_clean_paint")
    _box(b, p, "Hasp", (0.237, 0.057, 0.028), (-0.449, 1.12, 0.178), "exit_steel", (0, 0, 7))
    _box(b, p, "Keeper", (0.048, 0.077, 0.035), (-0.547, 1.107, 0.188), "exit_frame")
    b.flat("Shackle", p, _ring(b, 0.030, 0.047), "exit_steel", (-0.533, 1.057, 0.212), (90, 0, -10))
    _box(b, p, "Padlock", (0.093, 0.081, 0.052), (-0.526, 1.009, 0.223), "brass", (0, 0, 9))
    _box(b, p, "Keyway", (0.013, 0.021, 0.004), (-0.526, 1, 0.25), "metal_ink", (0, 0, 9))
    _box(b, p, "SignBack", (0.85, 0.235, 0.034), (0, 2.498, 0.022), "exit_frame")
    b.flat("RoomSign", p, b.mesh("QuadMesh", size="Vector2(0.803, 0.19)"), "shed_sign", (0, 2.498, 0.041))

    # A ruled sheet remains on the visible side of the glazing. No bar across its
    # rows, or across the clipped-off copy mounted in _yard_return_details.
    _box(b, p, "WindowReveal", (1.39, 1.0, 0.061), (2.2, 1.935, 0.027), "exit_frame")
    _box(b, p, "Glazing", (1.223, 0.813, 0.040), (2.2, 1.935, 0.065), "exit_glass")
    for i, x in enumerate((1.559, 2.841)):
        _box(b, p, f"GlazingBead{i}", (0.069, 0.905, 0.059), (x, 1.934, 0.071), "exit_steel")
    _box(b, p, "WindowHead", (1.342, 0.064, 0.061), (2.2, 2.371, 0.071), "exit_steel")
    _box(b, p, "SillPan", (1.49, 0.082, 0.224), (2.2, 1.46, 0.081), "concrete")
    _box(b, p, "HighRail", (1.22, 0.025, 0.019), (2.2, 2.234, 0.085), "exit_steel")
    _box(b, p, "DutySheet", (0.009, 0.5, 0.90), (2.2, 1.963, 0.093), "rota", (0, -90, 0))
    # Dress the slab shared with the teaching-wing view, rather than drawing a
    # second roof. Its top is 0.10 m above the local origin; the seams sit into it.
    roof = "ShedRoof"
    rib = b.mesh("BoxMesh", size=_v3((6.32, 0.025, 0.037)))
    for i in range(13):
        b.flat(f"RoofSeam{i}", roof, rib, "shed_roof", (0, 0.108, 0.634 * (i - 6)))
    _box(b, roof, "Gutter", (0.125, 0.112, 8.39), (3.208, -0.062, 0), "exit_frame")
    _box(b, roof, "GutterLip", (0.042, 0.029, 8.39), (3.270, -0.006, 0), "exit_steel")
    # The wall-mounted drainpipe stays clear of the ping-pong ball and footing.
    _cylinder(b, p, "Downpipe", 0.047, 2.51, (3.69, 1.50, 0.157), "tap_steel", shadow=True)
    _cylinder(b, p, "DownpipeElbow", 0.048, 0.35, (3.69, 2.851, 0.208), "tap_steel", (26, 0, 0))
    _cylinder(b, p, "DownpipeShoe", 0.050, 0.26, (3.69, 0.177, 0.215), "exit_steel", (-44, 0, 0))
    for i, y in enumerate((0.54, 1.63, 2.62)):
        _box(b, p, f"PipeStrap{i}", (0.138, 0.052, 0.181), (3.69, y, 0.096), "exit_frame")


def cabin(b):
    b.node("Cabin", ".")
    b.node("Bedding", "Cabin")
    # No bed frame. Two differently cut drapes touch the 0.22 m deck, against one
    # side only. The blanket is pushed aside; its higher edge curls over the sheet.
    b.flat("Sheet", "Cabin/Bedding", "cabin_sheet", "container_bedding", (1.30, 0.222, -0.559),
           (0, 1.8, 0), imported=True)
    b.flat("Blanket", "Cabin/Bedding", "cabin_blanket", "container_blanket", (0.98, 0.223, -0.603),
           (0, -10.5, 0), imported=True)
    b.node("Papers", "Cabin")
    for name, mesh, where, yaw, scale in (
        ("DiscardedPage", "newsprint", (1.21, 0.223, 0.63), 28, (1.0, 1.0, 1.0)),
        ("FoldedPage", "newsprint", (2.37, 0.223, 0.70), -28, (0.89, 0.60, 0.58)),
        ("ClippedPage", "newsprint_clipped", (2.21, 0.226, 0.59), 65, (1.0, 1.0, 1.0)),
    ):
        b.node(name, "Cabin/Papers", position=_v3(where), rotation_degrees=_v3((0, yaw, 0)), scale=_v3(scale))
        b.flat("Paper", f"Cabin/Papers/{name}", mesh, "old_newsprint", (0, 0, 0), imported=True)


# Each mesh is a little draped grid, so actual silhouettes, folds and cut edges
# read before any texture. The loops below produce stable UVs and smooth normals.
def _grid(vertices, faces, cols, rows, point, *, clip=None, reverse=False):
    start = len(vertices)
    for j in range(rows + 1):
        for i in range(cols + 1):
            u, v = i / cols, j / rows
            vertices.append((point(u, v), (u, 1 - v)))
    stride = cols + 1
    for j in range(rows):
        for i in range(cols):
            if clip and clip(i, j):
                continue
            a = start + j * stride + i
            for tri in ((a, a + stride, a + stride + 1), (a, a + stride + 1, a + 1)):
                faces.append(tri[::-1] if reverse else tri)


def _ridge(x, at, width):
    return math.exp(-((x - at) / width) ** 2)


def _sheet(u, v):
    x = (u - 0.5) * (1.87 - 0.045 * math.sin(v * 4)) + 0.08 * math.sin(v * 5 + 0.3)
    z = (v - 0.5) * 0.83 + 0.051 * math.sin(u * 7 + 1.1) + 0.047 * u
    fold = 0.029 * _ridge(v, 0.69 - 0.28 * u, 0.085) + 0.040 * _ridge(v, 0.91 + 0.13 * math.sin(u * 5), 0.13)
    y = 0.007 * (1 + math.sin(u * 21 - v * 11)) + fold * (0.62 + 0.38 * math.cos(u * 7))
    y += 0.030 * _ridge(u, 0.92, 0.10) * _ridge(v, 0.84, 0.16)
    return x, y, z


def _blanket(u, v):
    x = (u - 0.5) * (1.29 - 0.11 * math.sin(v * 5.6)) + 0.125 * math.sin(v * 4.9 - 0.6)
    z = (v - 0.5) * (0.713 - 0.104 * math.cos(u * 6)) + 0.074 * math.sin(u * 7.6)
    ridge = 0.105 * _ridge(v, 0.64 + 0.21 * math.sin(u * 3.8), 0.118)
    ridge += 0.066 * _ridge(v, 0.29 - 0.13 * math.sin(u * 5), 0.13)
    edge = 0.043 * _ridge(u, 0.95, 0.16) * _ridge(v, 0.73, 0.20)
    y = 0.022 + ridge * (0.78 + 0.22 * math.cos(6 * u)) + edge + 0.006 * math.sin(u * 15 + v * 7)
    return x, y, z


def _paper(u, v):
    return ((u - 0.5) * 0.42 + 0.011 * math.sin(8 * v),
            0.003 + 0.016 * _ridge(u, 0.48 + v * 0.06, 0.09) + 0.025 * (u * v) ** 4,
            (v - 0.5) * 0.35 + 0.011 * math.sin(u * 6 + 0.6))


def _film(u, v, *, underside=False):
    # A split seal at v=1. The torn edge lifts clear of the foil beneath it.
    edge = v ** 9
    x = (u - 0.5) * (0.245 - 0.012 * math.sin(9 * v)) + 0.005 * math.sin(7 * v)
    z = (v - 0.5) * 0.164 + 0.004 * math.sin(17 * u) + edge * 0.005 * math.sin(52 * u)
    if underside:
        return x, 0.001 + 0.005 * (1 + math.sin(21 * u + 14 * v)), z + 0.011 * edge
    ridge = 0.011 * _ridge(v, 0.29 + 0.24 * u, 0.14) + 0.006 * _ridge(u, 0.83 - 0.3 * v, 0.12)
    return x, 0.006 + ridge + 0.007 * (1 + math.sin(22 * u - 14 * v)) + edge * 0.015, z


def _mesh_obj(vertices, faces):
    normals = [[0.0, 0.0, 0.0] for _ in vertices]
    for a, b, c in faces:
        p, q, r = (vertices[i][0] for i in (a, b, c))
        e, f = tuple(q[i] - p[i] for i in range(3)), tuple(r[i] - p[i] for i in range(3))
        for i in range(3):
            j, k = (i + 1) % 3, (i + 2) % 3
            n = e[j] * f[k] - e[k] * f[j]
            for index in (a, b, c):
                normals[index][i] += n
    lines = ["# Generated by source/yard_details.py; metres, +Y up."]
    lines.extend("v %.6f %.6f %.6f" % v[0] for v in vertices)
    lines.extend("vt %.6f %.6f" % v[1] for v in vertices)
    for normal in normals:
        length = math.sqrt(sum(n * n for n in normal))
        lines.append("vn %.6f %.6f %.6f" % (tuple(n / length for n in normal) if length else (0, 1, 0)))
    lines.append("s 1")
    lines.extend("f " + " ".join(f"{i + 1}/{i + 1}/{i + 1}" for i in face) for face in faces)
    return "\n".join(lines) + "\n"


def write_detail_meshes(art_dir: Path, res_prefix: str):
    # Use the same UID alphabet as the repository's import audit.
    sys.path.insert(0, str(Path(__file__).resolve().parents[5] / "tools"))
    from godot_sidecars import encode

    output = art_dir / "meshes"
    output.mkdir(exist_ok=True)
    for name, surface, cols, rows, clip in (
        ("cabin_sheet", _sheet, 22, 14, None),
        ("cabin_blanket", _blanket, 22, 15, None),
        ("newsprint", _paper, 9, 9, None),
        ("newsprint_clipped", _paper, 10, 8, lambda i, j: i >= 8 and j < 2),
        ("noodle_wrapper", _film, 16, 12, None),
    ):
        vertices, faces = [], []
        _grid(vertices, faces, cols, rows, surface, clip=clip)
        if name == "noodle_wrapper":
            _grid(vertices, faces, cols, rows, lambda u, v: _film(u, v, underside=True), reverse=True)
        path = output / f"{name}.obj"
        path.write_text(_mesh_obj(vertices, faces))
        res = f"{res_prefix}/meshes/{path.name}"
        digest = hashlib.md5(res.encode()).hexdigest()
        dest = f"res://.godot/imported/{path.name}-{digest}.mesh"
        uid = encode(int.from_bytes(hashlib.sha256(res.encode()).digest()[:8], "little") & ((1 << 63) - 1))
        (output / f"{path.name}.import").write_text(f'''[remap]

importer="wavefront_obj"
type="Mesh"
uid="{uid}"
path="{dest}"

[deps]

source_file="{res}"
dest_files=["{dest}"]

[params]

generate_tangents=false
generate_lods=false
generate_shadow_mesh=true
generate_lightmap_uv2=false
generate_lightmap_uv2_texel_size=0.2
scale_mesh=Vector3(1, 1, 1)
offset_mesh=Vector3(0, 0, 0)
force_disable_mesh_compression=false
''')
