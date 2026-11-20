"""Static construction meshes. The yard builder writes these OBJs, not the runtime."""

from __future__ import annotations

import math

from yard_details import write_obj_asset


def _ring_mesh(profile, point, segments, *, bottom=True, top=True):
    """Follow a section through x/z rings. An inward turn can line a recessed opening."""
    vertices, faces = [], []
    for row, (y, radius) in enumerate(profile):
        for i in range(segments):
            theta = i * math.tau / segments
            vertices.append((point(y, radius, theta), (i / segments, y)))
        if row == 0:
            continue
        low, high = (row - 1) * segments, row * segments
        for i in range(segments):
            j = (i + 1) % segments
            faces.extend(((low + i, high + i, high + j), (low + i, high + j, low + j)))

    # Separate cap vertices so the edge stays sharp without discontinuities in the wall.
    for include, row, up in ((bottom, 0, False), (top, len(profile) - 1, True)):
        if not include:
            continue
        ring = vertices[row * segments:(row + 1) * segments]
        start = len(vertices)
        vertices.extend(ring)
        centre = len(vertices)
        x, y, z = (sum(v[0][axis] for v in ring) / segments for axis in range(3))
        vertices.append(((x, y, z), (0.5, 0.5)))
        for i in range(segments):
            tri = (centre, start + i, start + (i + 1) % segments)
            faces.append(tri[::-1] if up else tri)
    return vertices, faces


def _shell(radius_at, deck, levels):
    # The cold joints are shallow channels cut *into* the closed skin, never slits.
    rings = {round(i * 0.3, 3): 0.0 for i in range(1, math.floor(deck / 0.3) + 1)}
    for y in levels:
        for p in list(rings):
            if abs(p - y) < 0.16:
                del rings[p]
        for offset, inset in ((-0.10, 0.016), (-0.036, 0.012), (-0.012, -0.052),
                              (0.037, -0.052), (0.075, 0.0), (0.14, 0.0)):
            rings[round(y + offset, 3)] = inset
    rings.update({-0.018: -0.05, 0.05: 0.0, deck - 0.09: 0.0, deck: -0.01})

    def point(y, inset, theta):
        x, z = radius_at(y)
        return (x + inset) * math.cos(theta), y, (z + inset) * math.sin(theta)

    return _ring_mesh(sorted(rings.items()), point, 64)


def _rounded_square(theta, power):
    x, z = math.cos(theta), math.sin(theta)
    factor = (abs(x) ** power + abs(z) ** power) ** (-1 / power)
    return x * factor, z * factor


def _sand_point(y, radius, theta):
    # A four-sided pile, with slightly slumped corners, not a perfect plastic frustum.
    x, z = _rounded_square(theta, 4.6 - y * 1.8)
    slip = 1 + 0.028 * math.sin(5 * theta + 1.2) + 0.018 * math.cos(9 * theta - 5 * y)
    return x * radius * slip - 0.06 * y, y, z * radius * slip + 0.04 * y


def _add_box(vertices, faces, size, centre):
    # Hard edges on folded sheet and machined parts; join repeated static details
    # into one draw surface instead of instancing a mesh node for each small bit.
    corners = [tuple(c + d * s * 0.5 for c, d, s in zip(centre, sign, size)) for sign in (
        (-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
        (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1),
    )]
    for quad in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 4, 7, 3),
                 (1, 2, 6, 5), (0, 1, 5, 4), (3, 7, 6, 2)):
        i = len(vertices)
        vertices.extend((corners[index], uv) for index, uv in zip(quad, ((0, 0), (1, 0), (1, 1), (0, 1))))
        faces.extend(((i, i + 1, i + 2), (i, i + 2, i + 3)))


def _panel():
    vertices, faces = [], []
    _add_box(vertices, faces, (1.0, 1.0, 0.071), (0, 0, 0))
    for x in (-0.25, 0, 0.25):
        _add_box(vertices, faces, (0.037, 0.93, 0.036), (x, -0.018, 0.038))
    return vertices, faces


def _gate():
    vertices, faces = [], []
    for i in range(8):
        _add_box(vertices, faces, (0.055, 2.02, 0.031), (0, 1.18, i / 7 - 0.5))
    for h in (0.22, 1.12, 2.19):
        _add_box(vertices, faces, (0.092, 0.084, 1.032), (0, h, 0))
    return vertices, faces


def _case_point(y, radius, theta):
    x, z = _rounded_square(theta, 8)
    return x * radius * 0.5, y, z * radius * 0.5


def _beveled_case():
    return _ring_mesh(((-0.5, 0.85), (-0.39, 1.0), (0.31, 1.0), (0.5, 0.77)), _case_point, 32)


def _track():
    vertices, faces = _beveled_case()
    vertices = [((2.95 * x, 0.66 * y + 0.355, 0.56 * z), uv) for (x, y, z), uv in vertices]
    for i in range(10):
        # The shoes sit into the shoulder and turn down towards the drive wheels.
        y = 0.66 if i in (0, 9) else 0.675
        _add_box(vertices, faces, (0.108, 0.048, 0.56), (0.243 * (i - 4.5), y, 0))
    return vertices, faces


def _scoop():
    # The thin inner plate follows the curved outer plate. No face spans the opening.
    outer = ((-0.30, 0.28), (-0.42, 0.14), (-0.43, -0.09), (-0.34, -0.28),
             (-0.18, -0.34), (0.10, -0.34), (0.37, -0.22))
    inner = ((-0.28, 0.23), (-0.37, 0.12), (-0.38, -0.08), (-0.30, -0.23),
             (-0.16, -0.29), (0.09, -0.29), (0.37, -0.17))
    vertices, faces = [], []

    def strip(section, half_width):
        start = len(vertices)
        for i, (x, y) in enumerate(section):
            vertices.extend((((x, y, -half_width), (i / len(section), 0)),
                             ((x, y, half_width), (i / len(section), 1))))
        for i in range(len(section) - 1):
            a = start + i * 2
            faces.extend(((a, a + 2, a + 3), (a, a + 3, a + 1)))

    strip(outer, 0.39)
    strip(inner[::-1], 0.35)
    strip((outer[-1], inner[-1]), 0.39)
    strip((inner[0], outer[0]), 0.39)
    for z, forward in ((0.39, True), (-0.39, False), (0.35, False), (-0.35, True)):
        start = len(vertices)
        vertices.extend(((x, y, z), (x, y)) for x, y in outer)
        for i in range(1, len(outer) - 1):
            tri = (start, start + i, start + i + 1)
            faces.append(tri if forward else tri[::-1])
    return vertices, faces


def write_assets(art_dir, res_prefix, radius_at, deck, levels):
    shoulder = (1.0, 0.264)
    meshes = {
        "site_cast_shell": _shell(radius_at, deck, levels),
        "site_sand_body": _ring_mesh(
            ((0.0, 0.99), (0.055, 1.0), (0.14, 0.94), (0.32, 0.79),
             (0.61, 0.57), (0.85, 0.39), (0.96, 0.305), shoulder),
            _sand_point, 36, top=False),
        "site_sand_basin": _ring_mesh(
            (shoulder, (0.994, 0.223), (0.93, 0.205), (0.75, 0.194), (0.65, 0.16)),
            _sand_point, 36, bottom=False),
        "site_beveled_case": _beveled_case(),
        "site_bucket": _scoop(),
        "site_panel": _panel(),
        "site_gate_leaf": _gate(),
        "site_track_belt": _track(),
    }
    for name, (vertices, faces) in meshes.items():
        # All site textures are triplanar. The render mesh is already low-poly;
        # a second, welded mesh just for shadows would duplicate the geometry on disk.
        write_obj_asset(art_dir, res_prefix, name, vertices, faces, source="site_meshes.py",
                        uvs=False, shadow_mesh=False)
