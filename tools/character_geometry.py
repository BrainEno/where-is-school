"""Authored, deterministic geometry edits for N and the seated classroom student.

Build-time only: numpy is already pinned by tools/requirements.txt. These are actual
bind-space vertices, not a runtime smoothing modifier or a shader displacement. This
module owns the shared loft/normal math; prepare_teacher_n.py and
prepare_classroom_student.py remain the owners of their immutable sources and exports.
No skeleton, inverse bind or animation data is edited here.
"""
from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

import numpy as np


@dataclass
class Geometry:
    positions: np.ndarray
    triangles: np.ndarray

    def transformed(self, matrix: np.ndarray) -> "Geometry":
        points = np.c_[self.positions, np.ones(len(self.positions))] @ matrix.T
        triangles = self.triangles.copy()
        if np.linalg.det(matrix[:3, :3]) < 0:
            triangles = triangles[:, [0, 2, 1]]
        return Geometry(points[:, :3], triangles)


def join(*items: Geometry) -> Geometry:
    points, faces, offset = [], [], 0
    for item in items:
        points.append(item.positions)
        faces.append(item.triangles + offset)
        offset += len(item.positions)
    return Geometry(np.concatenate(points), np.concatenate(faces))


def normals(geometry: Geometry) -> np.ndarray:
    """Area-weighted smooth normals; weld coincident export seams for shading only."""
    p, t = geometry.positions, geometry.triangles
    _unique, weld = np.unique(np.round(p, 7), axis=0, return_inverse=True)
    result = np.zeros((len(_unique), 3), np.float64)
    face = np.cross(p[t[:, 1]] - p[t[:, 0]], p[t[:, 2]] - p[t[:, 0]])
    for corner in range(3):
        np.add.at(result, weld[t[:, corner]], face)
    lengths = np.linalg.norm(result, axis=1, keepdims=True)
    if np.any(lengths < 1e-12):
        raise ValueError("a refined vertex has no non-degenerate incident face")
    return (result / lengths)[weld].astype(np.float32)


def grid_surface(points: np.ndarray, cap: bool = True) -> Geometry:
    """A sequence of closed transverse rings, with outward CCW winding."""
    rows, sides, _ = points.shape
    triangles = []
    for row in range(rows - 1):
        for col in range(sides):
            a, b = row * sides + col, row * sides + (col + 1) % sides
            c, d = a + sides, b + sides
            triangles.extend([(a, b, c), (b, d, c)])
    p = points.reshape(-1, 3).tolist()
    if cap:
        for row, flip in [(0, True), (rows - 1, False)]:
            center = len(p)
            p.append(points[row].mean(axis=0).tolist())
            for col in range(sides):
                a, b = row * sides + col, row * sides + (col + 1) % sides
                triangles.append((center, b, a) if flip else (center, a, b))
    g = Geometry(np.asarray(p), np.asarray(triangles, np.int64))
    # Authoring profiles may run either along or against their local axis. Orient each
    # closed loft once, without changing its topology or trusting source split normals.
    volume = np.einsum("ij,ij->i", g.positions[g.triangles[:, 0]],
                       np.cross(g.positions[g.triangles[:, 1]],
                                g.positions[g.triangles[:, 2]])).sum()
    if cap and volume < 0:
        g.triangles = g.triangles[:, [0, 2, 1]]
    return g


def tube(path: list, radii: list, sides: int = 12, flatten: float = 1.0) -> Geometry:
    p = np.asarray(path, np.float64)
    radius = np.asarray(radii)
    direction = np.gradient(p, axis=0)
    direction /= np.linalg.norm(direction, axis=1, keepdims=True)
    # A stable frame along the digit/lock. Avoid Frenet flips at a straight knuckle.
    reference = np.array([0.0, 0.0, 1.0])
    if abs(direction[0] @ reference) > 0.9:
        reference = np.array([1.0, 0.0, 0.0])
    side = np.cross(direction, reference)
    side /= np.linalg.norm(side, axis=1, keepdims=True)
    other = np.cross(side, direction)
    angle = np.arange(sides) * 2 * np.pi / sides
    rings = (p[:, None, :] + radius[:, None, None]
             * (np.cos(angle)[None, :, None] * side[:, None, :]
                + np.sin(angle)[None, :, None] * other[:, None, :] * flatten))
    return grid_surface(rings)


def ellipsoid(center: list, radius: list, sides: int = 24, rings: int = 12) -> Geometry:
    # Do not duplicate a whole ring at the poles: tiny end rings plus caps have no
    # zero-area triangles and remain well behaved under the normal/outline pipeline.
    phi = np.linspace(0.012, np.pi - 0.012, rings)
    theta = np.arange(sides) * 2 * np.pi / sides
    p = np.stack(np.broadcast_arrays(np.sin(phi)[:, None] * np.cos(theta),
                                     np.cos(phi)[:, None],
                                     np.sin(phi)[:, None] * np.sin(theta)), axis=2)
    return grid_surface(p * radius + center)


def _cross2(a: np.ndarray, b: np.ndarray) -> float:
    return float(a[0] * b[1] - a[1] * b[0])


def _triangulate(outline: np.ndarray) -> np.ndarray:
    """Ear-clip a simple CCW contour; reject a self-intersecting authoring profile."""
    active, triangles = list(range(len(outline))), []
    while len(active) > 3:
        for index, b in enumerate(active):
            a, c = active[index - 1], active[(index + 1) % len(active)]
            u, v = outline[b] - outline[a], outline[c] - outline[a]
            denominator = _cross2(u, v)
            if denominator < 1e-12:
                continue
            others = outline[[i for i in active if i not in (a, b, c)]] - outline[a]
            v1 = (others[:, 0] * v[1] - others[:, 1] * v[0]) / denominator
            v2 = (u[0] * others[:, 1] - u[1] * others[:, 0]) / denominator
            if np.any((v1 >= -1e-10) & (v2 >= -1e-10) & (v1 + v2 <= 1 + 1e-10)):
                continue
            triangles.append((a, b, c))
            active.pop(index)
            break
        else:
            raise ValueError("hand outline cannot be triangulated; check for crossing digits")
    triangles.append(tuple(active))
    return np.asarray(triangles, np.int64)


def _improve_triangles(p: np.ndarray, t: np.ndarray) -> np.ndarray:
    """Local, constrained edge flips prevent long wrist-to-finger shading slivers."""
    def quality(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
        u, v, w = b - a, c - a, c - b
        return abs(_cross2(u, v)) / float(u @ u + v @ v + w @ w)
    for _ in range(16):
        edges: dict[tuple, list] = {}
        for index, (a, b, c) in enumerate(t):
            for u, v, w in [(a, b, c), (b, c, a), (c, a, b)]:
                edges.setdefault(tuple(sorted((u, v))), []).append((index, w))
        used, changes = set(), 0
        for (a, b), adjacent in sorted(edges.items()):
            if len(adjacent) != 2:
                continue
            (i, c), (j, d) = adjacent
            if i in used or j in used or tuple(sorted((c, d))) in edges:
                continue
            if _cross2(p[d] - p[c], p[a] - p[c]) * _cross2(p[d] - p[c], p[b] - p[c]) >= -1e-18:
                continue
            before = min(quality(p[a], p[b], p[c]), quality(p[a], p[b], p[d]))
            after = min(quality(p[c], p[d], p[a]), quality(p[c], p[d], p[b]))
            if after < before * 1.01:
                continue
            first, second = [c, d, a], [d, c, b]
            for face in (first, second):
                if _cross2(p[face[1]] - p[face[0]], p[face[2]] - p[face[0]]) < 0:
                    face[1], face[2] = face[2], face[1]
            t[i], t[j] = first, second
            used.update((i, j))
            changes += 1
        if not changes:
            break
    return t


# Canonical x, fingertip distance beyond the metacarpus, half width; pinky -> index.
HAND_DIGITS = ((-.024, .052, .0063), (-.0085, .069, .0074),
               (.0085, .074, .0075), (.0245, .064, .0073))


@lru_cache(maxsize=2)
def canonical_hand(teacher: bool) -> Geometry:
    """One closed connected hand, not intersecting capped finger cylinders.

    A five-digit contour is triangulated with constrained edge flips and conforming
    bisection; dorsal/palmar depth is a rounded distance field over that contour. Both
    sides share their border indices. This gives real thumb webs and welded knuckles
    without a new CSG/meshing dependency or a hidden topology repair in Blender.
    x crosses the palm; y runs wrist -> fingertips; z is thickness and relaxed curl.
    """
    outline = [[-.016, -.007], [-.023, .014], [-.030, .040], [-.031, .067]]
    for x, length, radius in HAND_DIGITS:
        top = .073 + length
        for fraction in (0, .35, .65, .88):
            outline.append([x - radius * (1 - .18 * fraction),
                            .078 + (top - .006 - .078) * fraction])
        for angle in np.linspace(np.pi, 0, 9):
            outline.append([x + radius * .82 * np.cos(angle), top - .006 + .006 * np.sin(angle)])
        for fraction in (.88, .65, .35, 0):
            outline.append([x + radius * (1 - .18 * fraction),
                            .078 + (top - .006 - .078) * fraction])
    outline += [[.035, .067], [.037, .062], [.041, .071], [.042, .082], [.044, .089],
                [.048, .092], [.052, .091], [.055, .087], [.058, .079], [.060, .066],
                [.058, .054], [.052, .040], [.040, .027], [.024, .014], [.016, -.007]]
    contour = np.asarray(outline, np.float64)
    points = contour[::-1].copy()  # CCW front surface
    triangles = _triangulate(points)
    boundary = set(range(len(points)))
    for _ in range(12):
        triangles = _improve_triangles(points, triangles)
        edges = sorted({tuple(sorted((int(a), int(b)))) for face in triangles
                        for a, b in zip(face, np.roll(face, -1))
                        if np.linalg.norm(points[a] - points[b]) > .0052})
        if not edges:
            break
        mid = {edge: len(points) + index for index, edge in enumerate(edges)}
        uses, faces = dict.fromkeys(edges, 0), []
        for a, b, c in triangles:
            es = [tuple(sorted(e)) for e in ((a, b), (b, c), (c, a))]
            for edge in es:
                if edge in mid:
                    uses[edge] += 1
            ab, bc, ca = [mid.get(edge) for edge in es]
            count = sum(v is not None for v in (ab, bc, ca))
            if count == 0:
                faces.append((a, b, c))
            elif count == 3:
                faces.extend(((a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)))
            elif count == 1:
                if ab is None:
                    if bc is not None:
                        a, b, c, ab = b, c, a, bc
                    else:
                        a, b, c, ab = c, a, b, ca
                faces.extend(((a, ab, c), (ab, b, c)))
            else:
                if ca is not None:
                    if ab is None:
                        a, b, c, ab, bc = b, c, a, bc, ca
                    else:
                        a, b, c, ab, bc = c, a, b, ca, ab
                faces.extend(((b, bc, ab), (a, ab, c), (ab, bc, c)))
        boundary.update(mid[edge] for edge in edges if uses[edge] == 1)
        points = np.r_[points, [(points[a] + points[b]) * .5 for a, b in edges]]
        triangles = np.asarray(faces, np.int64)
    else:
        raise ValueError("hand triangulation did not converge")
    edge = np.roll(contour, -1, axis=0) - contour
    delta = points[:, None, :] - contour
    fraction = np.clip((delta * edge).sum(2) / (edge * edge).sum(1), 0, 1)
    distance = np.sqrt(((delta - fraction[:, :, None] * edge) ** 2).sum(2).min(1))
    x, y = points.T
    radius = .0075 + .0055 * (1 - np.clip((y - .065) / .015, 0, 1))
    d = np.minimum(distance, radius)
    depth = np.sqrt(np.maximum(2 * radius * d - d ** 2, 0))
    center = .002 + (.010 if teacher else .022) * np.clip((y - .074) / .074, 0, 1) ** 1.6
    depth += .0005 * np.exp(-((y - .090) / .008) ** 2) * (d / radius)
    front = np.c_[points, center + depth]
    inside = np.array([i for i in range(len(points)) if i not in boundary])
    remap = np.arange(len(points))
    remap[inside] = len(points) + np.arange(len(inside))
    positions = np.r_[front, np.c_[points[inside], (center - depth)[inside]]]
    faces = np.r_[triangles, remap[triangles[:, [0, 2, 1]]]]
    return Geometry(positions * (1 if teacher else .91), faces)


def hand_matrix(inverse_bind: np.ndarray, teacher: bool, right: bool) -> np.ndarray:
    """Keep each wrist/rig exactly where it was, including its handed rest orientation."""
    local = np.eye(4)
    if teacher:
        # N's palms face her thighs, unlike the student's front-facing blockout palms.
        local[:3, :3] = np.array([[0, 0, -1 if right else 1], [0, 1, 0], [1, 0, 0]])
    else:
        local[0, 0] = -1 if right else 1
        local[2, 3] = -.002
    return np.linalg.inv(inverse_bind) @ local


def hand_geometry(inverse_bind: np.ndarray, teacher: bool, right: bool) -> Geometry:
    matrix = hand_matrix(inverse_bind, teacher, right)
    return canonical_hand(teacher).transformed(matrix)


def skin_arrays(count: int, joint: int) -> tuple[np.ndarray, np.ndarray]:
    j = np.zeros((count, 4), np.uint8)
    j[:, 0] = joint
    w = np.zeros((count, 4), np.float32)
    w[:, 0] = 1
    return j, w


def student_hair_cap() -> Geometry:
    """A short, high, swept crop, different from N's supplied jaw-length bob."""
    columns, rows = 80, 24
    theta = np.arange(columns) * 2 * np.pi / columns
    front = (1 + np.cos(theta)) / 2
    center_y, half_height = 1.640, .1039
    bottom = 1.541 + .103 * front ** 1.4 + .006 * np.sin(theta + .4) * front
    points = []
    end_phi = np.arccos(np.clip((bottom - center_y) / half_height, -.99, .99))
    for t in np.linspace(.012, 1, rows):
        phi = t * end_phi
        y = center_y + half_height * np.cos(phi)
        radial = np.sin(phi) ** .86
        flow = theta + .18 * (1 - t) + .045 * np.sin(theta * 2)
        relief = .0018 * np.sin(flow * 8) * np.sin(phi) ** 2
        x = (.097 * radial + relief) * np.sin(theta) - .001 * radial * front
        z = -.002 + (.116 * radial + relief) * np.cos(theta)
        points.append(np.c_[x, y, z])
    return grid_surface(np.array(points))


def student_hair_front(x: float, y: float) -> float:
    radial = max(1 - ((y - 1.640) / .1039) ** 2, .008) ** (.86 / 2)
    z = .116 * radial * np.sqrt(max(1 - (x / (.097 * radial)) ** 2, .025))
    return -.002 + z + .0015


def teacher_hair(points: np.ndarray, triangles: np.ndarray) -> Geometry:
    """Locally soften N's supplied bob and offset its hem, retaining its own silhouette."""
    p, weld = np.unique(np.round(points, 7), axis=0, return_inverse=True)
    adjacent = [set() for _ in p]
    for a, b, c in weld[triangles]:
        adjacent[a].update((b, c))
        adjacent[b].update((a, c))
        adjacent[c].update((a, b))
    shift = np.array([p[list(neighbors)].mean(0) - v if neighbors else v * 0
                      for v, neighbors in zip(p, adjacent)]) * .4
    shift *= np.minimum(1, .0015 / np.maximum(np.linalg.norm(shift, axis=1, keepdims=True), 1e-12))
    p += shift
    p[:, 1] += .0025 * np.tanh(p[:, 0] / .035) * np.exp(-((p[:, 1] - 1.466) / .025) ** 2)
    return Geometry(p[weld], triangles)


def teacher_face(points: np.ndarray) -> np.ndarray:
    p = points.copy().astype(np.float64)
    x, y, z = p.T.copy()
    frontal = np.clip((-z - .025) / .06, 0, 1)
    lower = np.exp(-((y - 1.438) / .032) ** 2)
    # Retain N's long, fine face, not the student's broader jaw. Deliberate millimetric
    # asymmetry keeps a human plane change without random vertex noise.
    p[:, 0] *= 1 - .045 * lower
    p[:, 0] += -.0012 * np.exp(-(x / .021) ** 2 - ((y - 1.50) / .045) ** 2) * frontal
    p[:, 2] -= .0018 * np.exp(-((x + .045) / .025) ** 2 - ((y - 1.49) / .028) ** 2) * frontal
    return p


STUDENT_HEAD_LEVELS = np.array([
    [1.4275, .020, .033, .036], [1.438, .040, .028, .058],
    [1.454, .057, .024, .073], [1.477, .071, .020, .083],
    [1.505, .082, .014, .094], [1.535, .091, .009, .103],
    [1.560, .091, .004, .108], [1.584, .086, .001, .111],
    [1.611, .084, -.002, .112], [1.640, .086, -.003, .110],
    [1.670, .077, -.004, .100], [1.692, .056, -.008, .078],
    [1.706, .006, -.010, .012],
])


def student_front(x: np.ndarray, y: np.ndarray) -> np.ndarray:
    """The authored front skin surface; eye rims, nose and features share this datum."""
    rx, cz, rz = [np.interp(y, STUDENT_HEAD_LEVELS[:, 0], STUDENT_HEAD_LEVELS[:, k])
                  for k in (1, 2, 3)]
    c = np.sqrt(np.maximum(1 - (x / rx) ** 2, 0))
    def g(cx: float, cy: float, sx: float, sy: float) -> np.ndarray:
        return np.exp(-((x - cx) / sx) ** 2 - ((y - cy) / sy) ** 2)
    planes = (-.008 * (g(-.043, 1.583, .025, .019) + g(.043, 1.581, .025, .019))
              + .007 * (g(-.043, 1.606, .030, .010) + g(.043, 1.604, .030, .010))
              + .007 * g(-.063, 1.543, .025, .019) + .005 * g(.061, 1.540, .025, .019)
              - .004 * (g(-.061, 1.505, .022, .024) + g(.061, 1.505, .022, .024))
              + .006 * g(0, 1.487, .030, .016) + .006 * g(0, 1.452, .031, .014)
              + .014 * g(-.0008, 1.577, .011, .039)
              + .021 * g(-.0008, 1.546, .014, .012)
              + .008 * (g(-.013, 1.540, .006, .008) + g(.012, 1.540, .006, .008)))
    return cz + rz * c ** .56 + np.clip(c * 2, 0, 1) * planes


def student_face() -> Geometry:
    # More samples at the bridge/eye socket, not global subdivision of every rigid part.
    y = np.linspace(STUDENT_HEAD_LEVELS[0, 0], STUDENT_HEAD_LEVELS[-1, 0], 64)
    theta = np.arange(128) * 2 * np.pi / 128
    points = []
    for height in y:
        rx, cz, rz = [np.interp(height, STUDENT_HEAD_LEVELS[:, 0], STUDENT_HEAD_LEVELS[:, k])
                      for k in (1, 2, 3)]
        x = rx * np.sin(theta)
        c = np.cos(theta)
        z = np.where(c >= 0, student_front(x, height), cz + rz * c)
        x += -.0015 * np.exp(-((height - 1.49) / .06) ** 2) * np.clip(c * 2, 0, 1)
        points.append(np.c_[x, np.full(len(theta), height), z])
    return grid_surface(np.array(points))


def student_torso() -> Geometry:
    levels = np.array([[.860, .150, .102], [.890, .154, .112], [1.01, .155, .120],
                       [1.15, .159, .124], [1.27, .168, .119], [1.34, .171, .100],
                       [1.375, .144, .078], [1.395, .083, .055], [1.405, .055, .043]])
    theta = np.arange(64) * 2 * np.pi / 64
    rows = []
    for y in np.linspace(.860, 1.405, 38):
        rx = np.interp(y, levels[:, 0], levels[:, 1])
        rz = np.interp(y, levels[:, 0], levels[:, 2])
        relief = .0025 * np.sin(theta * 5 + (y - .9) * 7) * np.exp(-((y - 1.02) / .17) ** 2)
        cz = .014 + .024 * np.clip((y - 1.34) / .065, 0, 1)
        rows.append(np.c_[(rx + relief) * np.sin(theta),
                          np.full(len(theta), y), cz + (rz + relief) * np.cos(theta)])
    return grid_surface(np.array(rows))


def student_garment_front(x: np.ndarray, y: np.ndarray) -> np.ndarray:
    rx = np.interp(y, [.86, 1.15, 1.27, 1.34, 1.375, 1.395, 1.405],
                   [.15, .159, .168, .171, .144, .083, .055])
    rz = np.interp(y, [.86, 1.01, 1.15, 1.27, 1.34, 1.375, 1.395, 1.405],
                   [.102, .120, .124, .119, .100, .078, .055, .043])
    return .014 + .024 * np.clip((y - 1.34) / .065, 0, 1) + rz * np.sqrt(np.maximum(1 - (x / rx) ** 2, .01))


def garment_panel(outline: np.ndarray, relief: float = .004) -> Geometry:
    """A closed curved quad, sampled against the torso rather than cutting through it."""
    rows, columns = 14, 8
    points = []
    for v in np.linspace(0, 1, rows):
        for u in np.linspace(0, 1, columns):
            xy = ((1 - v) * ((1 - u) * outline[0] + u * outline[1])
                  + v * ((1 - u) * outline[3] + u * outline[2]))
            z = float(student_garment_front(xy[0], xy[1])) + relief
            z += .0015 * np.sin(np.pi * u) * np.sin(np.pi * v)
            points.append([*xy, z])
    front = np.asarray(points)
    back = front - [0, 0, .003]
    faces = []
    for row in range(rows - 1):
        for col in range(columns - 1):
            a, b = row * columns + col, row * columns + col + 1
            c, d = a + columns, b + columns
            faces.extend(((a, b, c), (b, d, c)))
    faces = np.asarray(faces, np.int64)
    if np.cross(front[faces[0, 1]] - front[faces[0, 0]],
                front[faces[0, 2]] - front[faces[0, 0]])[2] < 0:
        faces = faces[:, [0, 2, 1]]
    count = len(front)
    edges: dict[tuple, list] = {}
    for a, b, c in faces:
        for u, v in ((a, b), (b, c), (c, a)):
            edges.setdefault(tuple(sorted((u, v))), []).append((u, v))
    sides = []
    for uses in edges.values():
        if len(uses) == 1:
            a, b = uses[0]
            sides.extend(((a, a + count, b), (b, a + count, b + count)))
    return Geometry(np.r_[front, back], np.r_[faces, faces[:, [0, 2, 1]] + count, sides])


def student_sleeve(points: np.ndarray, inverse_bind: np.ndarray, upper: bool) -> Geometry:
    """A rolled deltoid and elbow/cuff overlap, in the original bone's bind frame."""
    local = (np.c_[points, np.ones(len(points))] @ inverse_bind.T)[:, :3]
    low, high = local.min(0), local.max(0)
    center = (low + high) * .5
    levels = ([[-.015, .15], [.00, .57], [.07, .88], [.20, 1], [.48, .94], [.80, .82], [1.02, .77]]
              if upper else [[-.02, .90], [.08, 1], [.35, .93], [.66, .79], [.90, .65], [1.02, .63]])
    levels = np.array(levels)
    theta = np.arange(32) * 2 * np.pi / 32
    rows = []
    for t in np.linspace(levels[0, 0], levels[-1, 0], 22):
        radius = np.interp(t, levels[:, 0], levels[:, 1])
        fold = .0014 * np.sin(theta * 3 + t * 8) * np.exp(-((t - .84) / .17) ** 2)
        x = center[0] + ((high[0] - low[0]) * .5 * radius + fold) * np.cos(theta)
        z = center[2] + ((high[2] - low[2]) * .5 * radius + fold) * np.sin(theta)
        rows.append(np.c_[x, np.full(len(theta), low[1] + (high[1] - low[1]) * t), z])
    return grid_surface(np.array(rows)).transformed(np.linalg.inv(inverse_bind))


def eye_patch(side: int, role: str) -> Geometry:
    cx, cy = side * .043, 1.581 - (0.0015 if side > 0 else 0)
    if role == "sclera":
        # Low-relief almond patch, rather than a complete protruding cartoon eyeball.
        rows, columns = 10, 48
        theta = np.arange(columns) * 2 * np.pi / columns
        rings = []
        for radius in np.linspace(.035, 1, rows):
            x = .025 * np.cos(theta) * radius
            yy = .012 * np.sin(theta) * (.74 + .26 * np.abs(np.sin(theta))) * radius
            yy += side * x * .055
            z = student_front(cx + x, cy + yy) + .0004 + .010 * np.sqrt(1 - radius ** 2)
            rings.append(np.c_[cx + x, cy + yy, z])
        g = grid_surface(np.array(rings), cap=False)
        # Its rings run outwards, rather than axially along a tube.
        g.triangles = g.triangles[:, [0, 2, 1]]
        return g
    specs = {"iris": (.0065, .0072, .0009, .0104),
             "pupil": (.0028, .0036, .0005, .0112),
             "glint": (.0008, .0010, .0003, .0117)}
    rx, ry, rz, relief = specs[role]
    z = student_front(np.asarray(cx), np.asarray(cy)) + relief
    offset = [-.0025, .0027] if role == "glint" else [0, 0]
    return ellipsoid([cx + offset[0], cy + offset[1], z], [rx, ry, rz], 28, 12)


def eyelid(side: int, lower: bool = False) -> Geometry:
    cx, cy = side * .043, 1.581 - (0.0015 if side > 0 else 0)
    theta = np.linspace(np.pi, 0, 18)
    x = .0255 * np.cos(theta)
    yy = .012 * np.sin(theta) * (.74 + .26 * np.abs(np.sin(theta)))
    if lower:
        yy *= -.91
    y = cy + yy + side * x * .055
    z = student_front(cx + x, y) + .0008 + .0018 * np.sin(theta)
    radius = .0010 + (.0012 if lower else .0018) * np.sin(theta)
    return tube(np.c_[cx + x, y, z].tolist(), radius.tolist(), 8, .8)


def brow(side: int) -> Geometry:
    x = np.linspace(.016, .074, 14)
    y = 1.607 + .004 * np.sin(np.linspace(0, np.pi, len(x))) - .006 * (x / .074) ** 2
    if side > 0:
        y -= .0018
    z = .113 - .010 * (x / .074) ** 2
    radius = .0008 + .0022 * np.sin(np.linspace(.2, np.pi - .1, len(x)))
    return tube(np.c_[x * side, y, z].tolist(), radius.tolist(), 8, .50)


def rounded_source(points: np.ndarray, triangles: np.ndarray, subdivisions: int = 1) -> Geometry:
    """Loop subdivision of selected closed low-sided source forms, with seams welded.

    Not used on eyelids, garment panels, the rig, or the already-dense teacher's face.
    Bounds are restored after the pass so a cuff or shoe does not shrink off its joint.
    """
    low, high = points.min(0), points.max(0)
    p, inverse = np.unique(np.round(points, 7), axis=0, return_inverse=True)
    t = inverse[triangles]
    for _ in range(subdivisions):
        edges: dict[tuple, list[int]] = {}
        neighbors = [set() for _ in p]
        for a, b, c in t:
            for u, v, opposite in [(a, b, c), (b, c, a), (c, a, b)]:
                edges.setdefault(tuple(sorted((u, v))), []).append(int(opposite))
                neighbors[u].add(v)
                neighbors[v].add(u)
        creases = set()
        locked = set()
        for (a, b), opp in edges.items():
            if len(opp) == 2:
                n0 = np.cross(p[b] - p[a], p[opp[0]] - p[a])
                n1 = np.cross(p[opp[1]] - p[a], p[b] - p[a])
                denominator = np.linalg.norm(n0) * np.linalg.norm(n1)
                if denominator > 1e-15 and abs(n0 @ n1) / denominator < .56:
                    creases.add((a, b))
                    locked.update((a, b))
        boundary = [set() for _ in p]
        for (a, b), opp in edges.items():
            if len(opp) == 1:
                boundary[a].add(b)
                boundary[b].add(a)
        updated = p.copy()
        for index, adjacent in enumerate(neighbors):
            if index in locked:
                continue
            if len(boundary[index]) == 2:
                updated[index] = p[index] * .75 + p[list(boundary[index])].sum(0) * .125
            elif len(adjacent) >= 3:
                n = len(adjacent)
                beta = 3 / (8 * n) if n > 3 else 3 / 16
                updated[index] = p[index] * (1 - n * beta) + p[list(adjacent)].sum(0) * beta
        added, mapping = [], {}
        for (a, b), opp in sorted(edges.items()):
            value = ((p[a] + p[b]) * .375 + p[opp].sum(0) * .125
                     if len(opp) == 2 and (a, b) not in creases else (p[a] + p[b]) * .5)
            mapping[(a, b)] = len(updated) + len(added)
            added.append(value)
        faces = []
        for a, b, c in t:
            ab, bc, ca = [mapping[tuple(sorted(e))] for e in [(a, b), (b, c), (c, a)]]
            faces.extend([(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)])
        p, t = np.r_[updated, added], np.asarray(faces, np.int64)
    span = p.max(0) - p.min(0)
    p = low + (p - p.min(0)) / np.maximum(span, 1e-12) * (high - low)
    return Geometry(p, t)
