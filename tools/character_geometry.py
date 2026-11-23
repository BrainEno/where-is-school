"""Authored, deterministic geometry edits for N and the seated classroom student.

Build-time only: numpy is already pinned by tools/requirements.txt. These are actual
bind-space vertices, not a runtime smoothing modifier or a shader displacement. This
module owns the shared loft/normal math; prepare_teacher_n.py and
prepare_classroom_student.py remain the owners of their immutable sources and exports.
The figures are sewn and sculpted in their original bind frames; no skeleton, inverse
bind or animation data is edited here.
"""
from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from functools import lru_cache

import numpy as np


def smoothstep(low: float, high: float, value: np.ndarray) -> np.ndarray:
    t = np.clip((value - low) / (high - low), 0, 1)
    return t * t * (3 - 2 * t)


def bell(value: np.ndarray, center: float, width: float) -> np.ndarray:
    return np.exp(-((value - center) / width) ** 2)


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
    unit = result / lengths
    # Symmetry axes have exact zero normals in that component. SIMD summation can
    # leave platform-dependent sub-picounit remainders on an otherwise zero axis
    # (e.g. the student's centreline). Canonicalize them before serializing glTF.
    unit[np.abs(unit) < 1e-12] = 0.0
    return unit[weld].astype(np.float32)


def deform(points: np.ndarray, normal: np.ndarray, warp: Callable[[np.ndarray], np.ndarray]
           ) -> tuple[np.ndarray, np.ndarray]:
    """Inverse-transpose local Jacobian; keep source split normals on thin surfaces."""
    p = points.astype(np.float64)
    step = np.eye(3) * 1e-5
    jacobian = np.stack([(warp(p + d) - warp(p - d)) / 2e-5 for d in step], axis=2)
    n = np.linalg.solve(jacobian.transpose(0, 2, 1), normal[:, :, None])[:, :, 0]
    return warp(p), n / np.linalg.norm(n, axis=1, keepdims=True)


def deform_delta(points: np.ndarray, delta: np.ndarray,
                 warp: Callable[[np.ndarray], np.ndarray]) -> np.ndarray:
    """Re-express a morph delta after `warp`.

    A morph target stores a displacement from the base surface. When the base is
    re-sculpted, the displacement has to travel with it: warping ``base`` and
    ``base + delta`` and subtracting gives the new displacement, so a blink still
    moves the lid that moved rather than the one that used to be there.
    """
    moved = warp(points)
    return warp(points + delta) - moved


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


@dataclass(frozen=True)
class HandCut:
    # Pinky to index: centre across the knuckles, reach beyond the palm, half-width.
    digits: tuple[tuple[float, float, float], ...]
    web: float
    width: float
    scale: float
    flex: tuple[float, ...]


# N's slender, nearly extended hand and the student's shorter converging fingers.
# The silhouette, metacarpal arch and unequal curls are modelled, not inked on.
TEACHER_HAND = HandCut(((-.024, .049, .0060), (-.0085, .066, .0067),
                       (.008, .073, .0071), (.0245, .063, .0070)),
                      .081, .90, 1, (.025, .021, .016, .012))
STUDENT_HAND = HandCut(((-.024, .046, .0068), (-.0085, .063, .0075),
                       (.0085, .069, .0076), (.025, .060, .0073)),
                      .086, .99, .91, (.043, .037, .029, .024))


@lru_cache(maxsize=2)
def canonical_hand(teacher: bool) -> Geometry:
    """One closed five-digit hand with longer webs and differently curled digits.

    Fewer triangles are spent across each broad pad; the contour, bevel and fused
    thumb web still carry the shape. x crosses the palm, y runs from the wrist and
    z carries knuckle and palm thickness rather than making the hand a flat cutout.
    """
    cut = TEACHER_HAND if teacher else STUDENT_HAND
    outline = [[-.017, -.010], [-.020, .012], [-.026, .043], [-.031, .065]]
    for index, (x, length, radius) in enumerate(cut.digits):
        top = .073 + length
        inset = (.0032 if not teacher else .0015) * (1.5 - index)
        for fraction in (0, .32, .68, .88):
            outline.append([x + inset * fraction - radius * (1 - .27 * fraction),
                            cut.web + (top - .006 - cut.web) * fraction])
        for angle in np.linspace(np.pi, 0, 7):
            outline.append([x + inset + radius * .72 * np.cos(angle),
                            top - .006 + .006 * np.sin(angle)])
        for fraction in (.88, .68, .32, 0):
            outline.append([x + inset * fraction + radius * (1 - .27 * fraction),
                            cut.web + (top - .006 - cut.web) * fraction])
    outline += [[.035, .072], [.036, .066], [.040, .069], [.043, .079], [.046, .086],
                [.051, .088], [.056, .084], [.059, .074], [.060, .065],
                [.058, .054], [.052, .040], [.040, .027], [.024, .014], [.017, -.010]]
    contour = np.asarray(outline, np.float64)
    points = contour[::-1].copy()  # CCW front surface
    triangles = _triangulate(points)
    boundary = set(range(len(points)))
    for _ in range(12):
        triangles = _improve_triangles(points, triangles)
        edges = sorted({tuple(sorted((int(a), int(b)))) for face in triangles
                        for a, b in zip(face, np.roll(face, -1))
                        if np.linalg.norm(points[a] - points[b]) >
                        (.0059 if (points[a, 1] + points[b, 1]) * .5 > .071 else .0092)})
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
    fingers = smoothstep(.068, .097, y)
    pinch = smoothstep(.026, .054, x)
    radius = (.0138 if teacher else .016) - .0066 * fingers - .0037 * pinch
    # The dorsal plane crosses an oblique row of knuckles; each pad bends by a
    # different amount, and the opposed thumb is not coplanar with the palm.
    d = np.minimum(distance, radius)
    depth = np.sqrt(np.maximum(2 * radius * d - d ** 2, 0))
    knuckles = bell(y, .081 + .08 * x, .012) * bell(x, -.003, .031)
    depth += .0026 * knuckles * np.clip(distance / .004, 0, 1)
    tip = np.interp(x, [d[0] for d in cut.digits], [.073 + d[1] for d in cut.digits])
    curl = np.clip((y - .067) / (tip - .067), 0, 1)
    flex = np.interp(x, [d[0] for d in cut.digits], cut.flex)
    center = .001 + .10 * x * smoothstep(.010, .060, y) + flex * curl ** 1.65
    center += .009 * pinch * bell(y, .069, .024)
    # Flexion takes reach out of the rest silhouette, not just moving the tips in z.
    points = np.c_[x * cut.width, y - .22 * flex * curl ** 2]
    front = np.c_[points, center + depth * (.83 + .17 * fingers)]
    inside = np.array([i for i in range(len(points)) if i not in boundary])
    remap = np.arange(len(points))
    remap[inside] = len(points) + np.arange(len(inside))
    positions = np.r_[front, np.c_[points[inside], (center - depth)[inside]]]
    faces = np.r_[triangles, remap[triangles[:, [0, 2, 1]]]]
    # Small depth-only relaxation inside the bevel, not across the shared silhouette.
    # This removes triangulation ripples without rounding the wrist seat or the tips.
    edges = np.unique(np.vstack((faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]],
                                 faces[:, [1, 0]], faces[:, [2, 1]], faces[:, [0, 2]])), axis=0)
    degree = np.bincount(edges[:, 0], minlength=len(positions))
    interior = np.r_[inside, remap[inside]]
    interior = interior[positions[interior, 1] > .023]
    for _ in range(2):
        total = np.bincount(edges[:, 0], weights=positions[edges[:, 1], 2], minlength=len(positions))
        positions[interior, 2] = (.78 * positions[interior, 2] + .22 * total[interior] / degree[interior])
    return Geometry(positions * cut.scale, faces)



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


def _student_hair_section(theta: np.ndarray, t: float) -> np.ndarray:
    """A swept crop with a sloped crown and a single off-centre break in the fringe."""
    front = (1 + np.cos(theta)) / 2
    height, crown = 1.641, .10291
    notch = .014 * bell(theta, .42, .19) + .014 * bell(theta, 2 * np.pi + .42, .19)
    bottom = 1.531 + .103 * front ** 1.65 + front ** 3 * .022 * np.sin(theta - .36) + notch
    phi = t * np.arccos(np.clip((bottom - height) / crown, -.99, .99))
    rad = np.sin(phi) ** .85
    flow = theta - .54 * (1 - t) + .15 * np.sin(theta)
    relief = (.0031 * np.cos(flow * 4) + .0013 * np.sin(flow * 7)) * rad ** 2
    x = (.096 * rad + relief) * np.sin(theta) - .010 * (1 - t) ** 1.2
    z = -.003 + (.116 * rad + relief) * np.cos(theta)
    return np.stack([x, height + crown * np.cos(phi), z], axis=-1)


def student_hair_cap() -> Geometry:
    theta = np.arange(72) * 2 * np.pi / 72
    return grid_surface(np.array([_student_hair_section(theta, t)
                                  for t in np.linspace(.011, 1, 23)]))


def student_fringe(index: int) -> Geometry:
    """Shallow cap-following clumps; their tips end above the cap's actual edge."""
    t = np.linspace(.23, .86 + .013 * index, 8)
    theta = -.84 + .34 * index + .60 * (t - .5)
    p = np.array([_student_hair_section(angle, row) for angle, row in zip(theta, t)])
    p[:, 2] -= .0011
    r = .0016 + .009 * np.sin(np.linspace(0, np.pi, len(t))) ** 1.25
    return tube(p.tolist(), r.tolist(), 10, .34)


def _components(positions: np.ndarray, faces: np.ndarray) -> list[np.ndarray]:
    """Face groups across coincident export seams, not across nearby locks."""
    unique, weld = np.unique(np.round(positions, 6), axis=0, return_inverse=True)
    parent = np.arange(len(unique))

    def root(vertex):
        while parent[vertex] != vertex:
            parent[vertex] = parent[parent[vertex]]
            vertex = parent[vertex]
        return vertex

    for a, b, c in weld[faces]:
        parent[root(b)] = root(a)
        parent[root(c)] = root(a)
    labels = np.array([root(x) for x in weld[faces[:, 0]]])
    return [np.flatnonzero(labels == i) for i in np.unique(labels)]


def teacher_bob(points: np.ndarray, triangles: np.ndarray) -> tuple[Geometry, np.ndarray]:
    """Keep the supplied bob shell/back locks; remove only floating front thread tufts.

    This is the source pass, and it is now a *placement* fix only: the tucked left temple
    and the swept middle plane carry the part instead of parallel strips crossing the
    forehead. The silhouette itself is cut later, in `teacher_crop`, which runs after the
    baked Blender stroke layer. Keeping the two apart means the baked layer is baked
    against the geometry it was authored on, and the crop cannot desynchronise it.
    """
    keep = np.ones(len(triangles), bool)
    for group in _components(points, triangles):
        lock = points[triangles[group]]
        if lock[:, :, 1].min() > 1.53 and lock[:, :, 2].max() < -.046:
            keep[group] = False
    p = points.astype(np.float64).copy()
    x, y, z = p.T.copy()
    margin = 1 - smoothstep(1.575, 1.627, y)
    front = smoothstep(.032, .084, -z)
    tuck = bell(x, .071, .028) * bell(z, -.032, .051)
    p[:, 1] += margin * (.012 * tuck - .005 * bell(x, -.067, .032) * front)
    sweep = bell(x + .5 * (y - 1.583), -.035, .035) * bell(y, 1.588, .033)
    p[:, 2] -= .0045 * sweep * front * margin
    # The tucked temple is round, not a flat mask extending past the ear.
    p[:, 0] -= .004 * tuck * margin
    f = triangles[keep]
    seen, inverse = np.unique(f, return_inverse=True)
    return Geometry(p[seen], inverse.reshape(-1, 3)), seen


def teacher_face(points: np.ndarray) -> np.ndarray:
    """One deformation for face, eyes and lip attachments so nothing drifts apart."""
    p = points.astype(np.float64).copy()
    x, y, z = p.T.copy()
    frontal = smoothstep(.024, .071, -z)
    jaw = bell(y, 1.438, .033)
    eye = np.where(x < 0, 1.532, 1.5296)
    orbit = bell(np.abs(x), .032, .026) * bell(y, eye, .021)
    mouth = bell(x, 0, .031) * bell(y, 1.451, .019)
    p[:, 0] *= 1 - .061 * jaw
    p[:, 0] -= .0016 * bell(x, 0, .023) * bell(y, 1.505, .039) * frontal
    p[:, 1] += frontal * (-.40 * (y - eye) * orbit - .33 * (y - 1.451) * mouth
                           + .0025 * np.tanh(x / .020) * mouth)
    cheek = .0035 * bell(x, -.041, .027) * bell(y, 1.500, .019)
    cheek += .0020 * bell(x, .044, .024) * bell(y, 1.497, .018)
    bridge = .0035 * bell(x, -.0015, .011) * bell(y, 1.505, .025)
    p[:, 2] -= frontal * (cheek + bridge - .0012 * mouth)
    return p


def teacher_expression(positions: np.ndarray, normals: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """The resting face of a person who expects to be interrupted.

    This runs *after* the baked Blender stroke layer, on whatever geometry that leaves,
    and it changes no topology: same vertices, same order, same skin weights. That is
    why it can be a channel of its own instead of another edit to the sculpt basis.
    Callers that need normals follow the field with `deform` (see prepare_teacher_n).

    What it changes, and why each one is a shape rather than a decoration:

      - **The upper lid comes down 5 mm over the pupil** and the skin above the lash
        line is thickened 2.6 mm, so the lid reads as a fold with an edge instead of
        the rim of a hole. Measured, her eye was 24.3 mm wide on a 148 mm face -- 5.4
        eyes across where the count should be about 5 -- so the aperture also opens
        2.2 mm at the corners.
      - **The brows tilt.** Inner heads up 3.8 mm, tails down. The skew is the whole
        signal: a symmetric brow at the same height reads as nothing, a brow that climbs
        toward the nose reads as worry, and the face is a strong enough category cue that
        this is what makes her read as a woman rather than a boy on a low-poly head.
      - **The mouth corners drop 3 mm** and the mouth line shortens, so the mouth is
        held rather than set. The lower lip is left alone: pulling the whole mouth down
        would push it into a pout, which reads as sulking.
      - **The jaw narrows 9 % at the angle and the cheeks flatten**, softening a jaw
        that measured 0.72 of the cranium width (fine for a man, hard for her).
    """
    p = positions.astype(np.float64).copy()
    n = normals.astype(np.float64).copy()
    x, y, z = p.T.copy()
    frontal = smoothstep(.018, .062, -z)
    ax = np.abs(x)

    # --- eyes -------------------------------------------------------------
    # The lid is measured *away from its own edge*, not by "above a line": the previous
    # form dropped every vertex above the lash line, which turned the brow ridge into a
    # lid and left the eye a slit under a bulge.
    lid_y = np.where(x < 0, 1.5335, 1.5325)
    above = y - lid_y
    orbit_x = bell(ax, .0312, .0195)
    # A band of skin 0.5-5 mm above the lash line is the lid; above 5 mm the brow ridge
    # is left alone.
    upper = orbit_x * smoothstep(-.0004, .0022, above) * (1 - smoothstep(.0062, .0080, above)) * frontal
    # And the same band below it is the lower lid, which also comes up a little.
    lower = orbit_x * (1 - smoothstep(-.0060, -.0035, above)) * smoothstep(-.0075, -.0065, above) * frontal
    rim = orbit_x * bell(above, .0052, .0022) * frontal
    p[:, 1] -= .0022 * upper
    p[:, 1] += .0015 * rim
    p[:, 1] += .0007 * lower
    p[:, 2] -= .0014 * rim
    p[:, 2] += .0012 * bell(ax, .0335, .0152) * bell(y, lid_y - .0120, .0040) * frontal

    # --- brows: inner head up, tail down ----------------------------------
    brow_y = np.where(x < 0, 1.5550, 1.5542)
    brow = bell(y, brow_y, .0080)
    inner = bell(ax, .0150, .0105)
    outer = bell(ax, .0500, .0120)
    p[:, 1] += .0038 * (inner - 1.05 * outer) * brow * frontal
    p[:, 1] -= .0022 * brow * frontal
    p[:, 2] -= .0026 * brow * frontal
    p[:, 1] += .0010 * brow * (1 - smoothstep(-.012, .004, x))

    # --- mouth: corners down, line shortened ------------------------------
    mouth_y = 1.4515
    p[:, 1] -= .0030 * smoothstep(.0135, .0250, ax) * bell(y, mouth_y, .0125) * frontal
    p[:, 0] *= 1 - .070 * bell(y, mouth_y, .0110) * smoothstep(.014, .030, ax) * frontal

    # --- jaw and cheeks ---------------------------------------------------
    jaw = bell(y, 1.4400, .0230) * smoothstep(.010, .042, ax)
    p[:, 0] *= 1 - .090 * jaw
    p[:, 2] += .0020 * bell(ax, .0455, .0175) * bell(y, 1.4930, .0165) * frontal

    return p, n


def teacher_crop(points: np.ndarray) -> np.ndarray:
    """Cut a short crop out of the source bob.

    The supplied hair is a bell: a shell whose front edge hangs to 1.436 m over the
    brows, a pinwheel crown with no part, some long flat planes down one side and a few
    rectangles floating at the nape. It reads as long and shapeless, which is the
    opposite of the short, disciplined hair this character needs.

    Three things happen, all on the bind-pose vertices so the rig and its single Head
    weight are untouched:

    1. **The front comes up.** The fringe is pulled back to 1.559-1.572 m, clear of the
       brows at 1.549-1.563 and above the eye line at 1.532, so the face is not framed by
       hair. That is the difference between a crop and a curtain.
    2. **Locks are grouped.** Rather than leave the shell smooth, strands are pulled in
       bands along their length (`phases`), displaced along the surface normal so the cut
       has grooves. A groove that follows the fall of the hair reads as cut hair; an even
       surface reads as a moulded helmet.
    3. **The back is tapered.** The shell is drawn in toward the neck below 1.52 m, so the
       crop ends on the nape instead of hanging beside the jaw.

    The crown part is left as authored: the source's sweep is a real part, not a defect.
    """
    p = points.astype(np.float64).copy()
    x, y, z = p.T.copy()
    front = smoothstep(.030, .085, -z)
    top = smoothstep(1.560, 1.600, y)

    # 1. Raise the front edge from the brow to just above it, and shape a side part.
    edge = (1.5720 - .0125 * smoothstep(-.02, .085, x)     # higher on her right
            + .0042 * np.cos(78 * x) + .0021 * np.sin(41 * x + 1.3))
    lift = np.clip(edge - y, 0, None) * front ** 1.35
    p[:, 1] += lift * .92
    p[:, 2] += lift * .34                                   # and back off the forehead
    p[:, 0] += lift * .18 * np.sign(x)

    # 2. Cut grooves: bands that run down the fall of the hair, fading at the crown.
    flow = np.arctan2(x, -z)
    phases = 5.2 * flow + 2.6 * (y - 1.50)
    groove = np.cos(phases)
    band = smoothstep(.55, .95, groove)                      # narrow crests, wide flats
    amount = (.0021 * band) * (1 - top) * (1 - .35 * front)
    radius = np.sqrt(x ** 2 + z ** 2)
    radius[radius < 1e-6] = 1e-6
    p[:, 0] += amount * (x / radius)
    p[:, 2] += amount * (z / radius)

    # 3. Take the length off the sides and the back, not just the fringe. A bob ends at
    #    the jaw; a crop ends above the ear lobe. Everything below 1.545 m is lifted by
    #    up to 34 mm (more the lower it hangs) and drawn in behind the ear line, so the
    #    silhouette is a cap over the skull rather than a bell around it.
    short = np.clip(1.545 - y, 0, None)
    lift = np.minimum(short, .045) * .78
    p[:, 1] += lift
    p[:, 0] *= 1 - np.clip(.30 * short / .045, 0, .30)
    p[:, 2] += np.clip(.012 * short / .045, 0, .012) * smoothstep(-.02, .06, z)

    # 4. Taper the nape in toward the neck.
    nape = (1 - smoothstep(1.470, 1.530, y)) * smoothstep(-.02, .05, z)
    p[:, 0] *= 1 - .10 * nape
    p[:, 2] -= .005 * nape

    return p


def teacher_eyeball(points: np.ndarray) -> np.ndarray:
    """Flatten each eyeball slightly about its own centre.

    The sclera is a sphere and the lid is skin. Lowering the lid over an unsquashed
    sphere leaves a white band above the iris, which is exactly what "swollen shut"
    looks like. Squashing the ball by 8 % into the aperture keeps the iris filling the
    opening, and the iris/pupil discs are squashed with it so nothing drifts.
    """
    p = points.astype(np.float64).copy()
    for centre in (np.array([-.0317, 1.5324, -.0786]), np.array([.0313, 1.5300, -.0783])):
        near = np.linalg.norm(p - centre, axis=1) < .030
        p[near, 1] = centre[1] + (p[near, 1] - centre[1]) * .90
        p[near, 2] = centre[2] + (p[near, 2] - centre[2]) * .97
    return p


def teacher_ear(points: np.ndarray) -> np.ndarray:
    """Cut the concha into the ear.

    Measured off the source, the ear is one smooth convex dome: frontmost at its rim
    (|x| = 80 mm) and shallowing towards the middle, with no bowl anywhere. That is why it
    reads as a flat oval pasted on the skull -- the concha, the one feature that makes an
    ear an ear and the only part of it that catches shadow, is simply absent.

    The bowl is cut about the region the source already treats as its middle: centred at
    y 1.5335, z 0.0140, about 9 mm across, pressed inward toward the skull by up to 6 mm and
    fading out before the rim so the helix is left standing as a lip. It is applied to the
    outward half of the shell only; the flat plate on the skull side stays where it is.
    """
    p = points.astype(np.float64).copy()
    x, y, z = p.T.copy()
    xr = np.abs(x)
    # The bowl's floor, in the ear's own (y, z): a radial falloff, not a separable one,
    # because the concha is round and a product of two bells puts its corners back up.
    r = np.hypot((y - 1.5335) / .0092, (z - .0140) / .0082)
    floor = np.clip(1.0 - r * r, 0.0, 1.0) ** 1.5
    # Only the outward half of the shell: the back plate is flat against the skull and
    # moving it would open a gap at the jaw. Within that half the bowl's own falloff decides
    # where the cut lands, so this gate stays well outside it and only the *back* is spared.
    out = smoothstep(.0680, .0700, xr)
    p[:, 0] -= np.sign(x) * .0060 * floor * out
    return p


def teacher_expression_field(points: np.ndarray) -> np.ndarray:
    """The resting-face field as positions only, for warping a morph delta.

    `teacher_expression` returns positions and normals because the mesh pass needs both.
    A shape key only needs the displacement, so it goes through this.
    """
    return teacher_expression(points, np.zeros_like(points, dtype=np.float64))[0]


def teacher_tailoring(points: np.ndarray, knit: bool) -> np.ndarray:
    """Shape the cut in the actual garment; preserve the source skin weights."""
    p = points.astype(np.float64).copy()
    x, y, z = p.T.copy()
    torso = 1 - smoothstep(.136, .174, np.abs(x))
    front = smoothstep(.034, .094, -z) * torso
    # A broad belly fold makes the placket stand clear of the underlying trousers.
    overlap = .014 * bell(y, .949, .075) + .006 * bell(y, 1.030, .095)
    p[:, 2] -= overlap * front
    if not knit:
        # A tucked shirt continues underneath the trouser waist instead of leaving an
        # irregular gap where both source surfaces met at y~.93.
        p[:, 1] -= .014 * bell(y, .921, .033) * torso * front
    if knit:
        p[:, 0] *= 1 - .052 * bell(y, 1.054, .171) * torso
        # Pressed vertical facing and fabric gathered diagonally into each hip.
        lapel = bell(np.abs(x), .073 - .037 * (y - 1.1), .017) * bell(y, 1.202, .147)
        crease = y - .987 + .25 * x
        lower_fold = .0047 * bell(crease, 0, .017) - .0032 * bell(crease, .034, .012)
        p[:, 2] -= front * (.0065 * lapel + lower_fold)
        p[:, 1] += .005 * np.tanh(x / .068) * bell(y, .855, .067) * torso
        # Heavy sleeve creases have one main ridge, not noise across the cloth.
        sleeve = smoothstep(.189, .245, np.abs(x))
        elbow = y - (1.054 + .12 * z) + .011 * np.sign(x)
        p[:, 2] += smoothstep(.009, .048, np.abs(z)) * np.sign(z) * sleeve * (
            .004 * bell(elbow, 0, .024) - .0025 * bell(elbow, .032, .019))
    return p


def teacher_collar(side: int) -> Geometry:
    """Two turned blouse leaves replace the disconnected neck rings.

    Columns are y, inner/outer x, inner/outer z on the pinned -Z blouse. The
    fold begins by the neck and is sewn into the shirt front, not the cardigan.
    """
    levels = np.array([
        [1.373, .028, .043, -.047, -.038],
        [1.367, .018, .055, -.068, -.051],
        [1.355, .008, .064, -.084, -.073],
        [1.343, .016, .066, -.094, -.084],
        [1.333, .027, .058, -.100, -.091],
        [1.325, .039, .045, -.101, -.098],
    ])
    u = np.linspace(0, 1, 9)
    rows = []
    for y in np.linspace(levels[0, 0], levels[-1, 0], 14):
        x0, x1, z0, z1 = [np.interp(y, levels[::-1, 0], col[::-1]) for col in levels[:, 1:].T]
        x = side * (x0 + (x1 - x0) * u)
        z = z0 + (z1 - z0) * u - .0038 * np.sin(np.pi * u) * bell(y, 1.348, .017)
        vy = y + side * .0027 * u * bell(y, 1.336, .022)
        rows.append(np.c_[x, vy, z])
    return panel_volume(np.asarray(rows), -.008)


def teacher_welt(body: Geometry) -> Geometry:
    """A slanted knit welt fitted to the deformed -Z chest, not a decal or cube."""
    v, u = np.mgrid[0:1:8j, 0:1:13j]
    x = -.134 + .055 * u + .005 * v
    y = 1.082 + .014 * v + .014 * u
    facets = body.positions[body.triangles]
    a, b, c = facets[:, 0], facets[:, 1] - facets[:, 0], facets[:, 2] - facets[:, 0]
    area = b[:, 0] * c[:, 1] - b[:, 1] * c[:, 0]
    valid = np.abs(area) > 1e-11
    a, b, c, area = a[valid], b[valid], c[valid], area[valid]
    query = np.stack((x, y), axis=2)[:, :, None, :] - a[:, :2]
    beta = (query[..., 0] * c[:, 1] - query[..., 1] * c[:, 0]) / area
    gamma = (b[:, 0] * query[..., 1] - b[:, 1] * query[..., 0]) / area
    is_inside = (beta >= 0) & (gamma >= 0) & (beta + gamma <= 1)
    depth = np.min(np.where(is_inside, a[:, 2] + beta * b[:, 2] + gamma * c[:, 2], np.inf), axis=2)
    if not np.all(depth < -.028):
        raise ValueError("teacher's welt must remain over the front of the cardigan")
    # The corners sink into the knit; the middle rolls out over the opening.
    lift = -.001 - .003 * np.sin(u * np.pi) ** .65 * np.sin(v * np.pi) ** .55
    return panel_volume(np.stack((x, y, depth + lift), axis=2), -.005)


def teacher_cuff(inverse_bind: np.ndarray, right: bool) -> Geometry:
    """A closed, rounded rim, open around the skin rather than capped with a disk."""
    theta = np.arange(28) * 2 * np.pi / 28
    # x/y/z here are in the wrist joint's coordinates. The last row is welded to
    # the first by wrapping triangle indices; the opening straddles the buried wrist.
    profile = [(-.038, .028, .032), (-.028, .030, .034), (-.014, .028, .031),
               (-.007, .025, .029), (-.006, .021, .025), (-.012, .020, .024),
               (-.032, .022, .027), (-.038, .025, .029)]
    rings = [np.c_[a * np.cos(theta), y + (.0018 if right else -.0018) * np.sin(theta),
                   b * np.sin(theta)] for y, a, b in profile]
    g = grid_surface(np.array(rings + [rings[0]]), cap=False)
    g.triangles[g.triangles >= len(theta) * len(profile)] -= len(theta) * len(profile)
    g.positions = g.positions[:-len(theta)]
    # First and last rings now share the same vertices; orient the toroidal section.
    tri = g.positions[g.triangles]
    if np.einsum("ij,ij->i", tri[:, 0], np.cross(tri[:, 1], tri[:, 2])).sum() < 0:
        g.triangles = g.triangles[:, [0, 2, 1]]
    return g.transformed(np.linalg.inv(inverse_bind))


STUDENT_HEAD_LEVELS = np.array([
    [1.4275, .019, .027, .037], [1.438, .038, .025, .058],
    [1.454, .057, .019, .076], [1.477, .073, .016, .086],
    [1.505, .084, .012, .093], [1.535, .091, .008, .104],
    [1.560, .091, .004, .108], [1.584, .086, .001, .111],
    [1.611, .084, -.002, .111], [1.640, .086, -.003, .109],
    [1.670, .077, -.004, .099], [1.692, .056, -.008, .078],
    [1.706, .006, -.010, .012],
])


def _student_head_section(y: np.ndarray) -> list[np.ndarray]:
    return [np.interp(y, STUDENT_HEAD_LEVELS[:, 0], axis)
            for axis in STUDENT_HEAD_LEVELS[:, 1:].T]


def student_front(x: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Plane-broken face datum; lid, lip, brow and iris geometry sit on this surface."""
    rx, cz, rz = _student_head_section(y)
    c = np.sqrt(np.maximum(1 - (x / rx) ** 2, 0))

    def plane(cx, cy, sx, sy):
        return bell(x, cx, sx) * bell(y, cy, sy)

    # Broader cheek shelves and chin than N. Keep the nose and upper lip separate in
    # section, with asymmetric cheeks and a small break under the resting lower lip.
    planes = (-.010 * (plane(-.044, 1.582, .024, .017) + plane(.044, 1.580, .024, .016))
              + .006 * (plane(-.042, 1.604, .026, .013) + plane(.044, 1.601, .026, .012))
              + .008 * plane(-.063, 1.548, .024, .013) + .0062 * plane(.062, 1.545, .024, .013)
              - .004 * (plane(-.066, 1.510, .021, .022) + plane(.066, 1.506, .022, .024))
              + .005 * plane(0, 1.494, .025, .014) - .0035 * plane(0, 1.472, .023, .007)
              + .007 * plane(0, 1.452, .032, .014) + .017 * plane(-.0018, 1.575, .010, .035)
              + .022 * plane(-.0024, 1.547, .013, .014)
              + .006 * (plane(-.014, 1.542, .006, .010) + plane(.011, 1.542, .006, .010)))
    return cz + rz * c ** .58 + smoothstep(0, .52, c) * planes


def student_face() -> Geometry:
    # More rings in the expressive lower/front face and fewer across the cranium.
    y = np.unique(np.r_[np.linspace(1.4275, 1.625, 42), np.linspace(1.625, 1.706, 12)])
    theta = np.arange(88) * 2 * np.pi / 88
    points = []
    for height in y:
        rx, cz, rz = _student_head_section(height)
        x = rx * np.sin(theta)
        c = np.cos(theta)
        z = np.where(c >= 0, student_front(x, height), cz + rz * c)
        points.append(np.c_[x, np.full(len(theta), height), z])
    return grid_surface(np.array(points))


STUDENT_KNIT_LEVELS = np.array([
    [.860, .150, .104], [.884, .153, .110], [.930, .151, .119], [1.010, .153, .126],
    [1.15, .158, .123], [1.27, .167, .116], [1.34, .171, .098],
    [1.375, .140, .077], [1.395, .081, .055], [1.405, .055, .043],
])


def _knit_section(y: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    rx, rz = (np.interp(y, STUDENT_KNIT_LEVELS[:, 0], a) for a in STUDENT_KNIT_LEVELS[:, 1:].T)
    return rx, rz, .014 + .024 * np.clip((y - 1.34) / .065, 0, 1)


def _knit_folds(x: np.ndarray, y: np.ndarray) -> np.ndarray:
    # Diagonal compression around the lap, broader folds at the side seams. Use
    # the same surface for collars, pocket and buttons so they never float.
    hip = smoothstep(.86, .885, y) * (1 - smoothstep(.96, 1.09, y))
    crease = y - .978 + .27 * x
    drape = .0052 * bell(crease, 0, .023) - .0034 * bell(crease, .032, .019)
    tuck = -.0053 * bell(x, .092, .031) * bell(y, 1.180, .091)
    return hip * drape + tuck


def student_garment_front(x: np.ndarray, y: np.ndarray) -> np.ndarray:
    rx, rz, cz = _knit_section(y)
    c = np.sqrt(np.maximum(1 - (x / rx) ** 2, 0))
    return cz + rz * c + _knit_folds(x, y) * smoothstep(0, .65, c)


def student_torso() -> Geometry:
    theta = np.arange(52) * 2 * np.pi / 52
    heights = np.unique(np.r_[STUDENT_KNIT_LEVELS[:, 0], np.linspace(.87, 1.404, 29)])
    rows = []
    for y in heights:
        rx, rz, cz = _knit_section(y)
        x = rx * np.sin(theta)
        c = np.cos(theta)
        z = np.where(c >= 0, student_garment_front(x, y), cz + rz * c)
        rows.append(np.c_[x, np.full(len(theta), y), z])
    return grid_surface(np.array(rows))


def garment_panel(outline: np.ndarray, relief: float = .004) -> Geometry:
    """A closed curved quad, sampled against the torso rather than cutting through it."""
    rows, columns = 11, 7
    points = []
    for v in np.linspace(0, 1, rows):
        for u in np.linspace(0, 1, columns):
            xy = ((1 - v) * ((1 - u) * outline[0] + u * outline[1])
                  + v * ((1 - u) * outline[3] + u * outline[2]))
            z = float(student_garment_front(xy[0], xy[1])) + relief
            z += .0015 * np.sin(np.pi * u) * np.sin(np.pi * v)
            points.append([*xy, z])
    return panel_volume(np.asarray(points).reshape(rows, columns, 3), relief + .002)


def panel_volume(grid: np.ndarray, thickness: float) -> Geometry:
    """Sew a curved open grid to its backing with consistent winding (+/-Z)."""
    rows, columns, _ = grid.shape
    front = grid.reshape(-1, 3)
    back = front - [0, 0, thickness]
    faces = []
    for row in range(rows - 1):
        for col in range(columns - 1):
            a, b = row * columns + col, row * columns + col + 1
            c, d = a + columns, b + columns
            faces.extend(((a, b, c), (b, d, c)))
    faces = np.asarray(faces, np.int64)
    if np.cross(front[faces[0, 1]] - front[faces[0, 0]],
                front[faces[0, 2]] - front[faces[0, 0]])[2] * thickness < 0:
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


def student_sleeve(points: np.ndarray, inverse_bind: np.ndarray, upper: bool, right: bool) -> Geometry:
    """A rolled deltoid and elbow/cuff overlap, in the original bone's bind frame."""
    local = (np.c_[points, np.ones(len(points))] @ inverse_bind.T)[:, :3]
    low, high = local.min(0), local.max(0)
    center = (low + high) * .5
    levels = ([[-.015, .15], [.00, .57], [.07, .88], [.20, 1], [.48, .94], [.80, .82], [1.02, .77]]
              if upper else [[-.02, .90], [.08, 1], [.35, .93], [.66, .79], [.90, .65], [1.02, .63]])
    levels = np.array(levels)
    theta = np.arange(28) * 2 * np.pi / 28
    rows = []
    for t in np.unique(np.round(np.r_[levels[:, 0], np.linspace(.04, .99, 16)], 8)):
        radius = np.interp(t, levels[:, 0], levels[:, 1])
        # The elbow bends into one broad crease, not alternating bumps or an entire
        # straight polygon tube. The differently angled left fold is intentional.
        axis = theta + (.38 if right else -.53)
        fold = .0032 * np.cos(axis) * bell(t - .08 * np.sin(axis), .78 if upper else .24, .12)
        fold -= .0027 * np.cos(axis + .52) * bell(t, .91 if upper else .38, .11)
        x = center[0] + ((high[0] - low[0]) * .5 * radius + fold) * np.cos(theta)
        z = center[2] + ((high[2] - low[2]) * .5 * radius + fold) * np.sin(theta)
        rows.append(np.c_[x, np.full(len(theta), low[1] + (high[1] - low[1]) * t), z])
    return grid_surface(np.array(rows)).transformed(np.linalg.inv(inverse_bind))


@dataclass(frozen=True)
class EyeCut:
    x: float
    y: float
    width: float
    upper: float
    lower: float
    tilt: float

    def level(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        dy = y - self.y - (x - self.x) * self.tilt
        return ((x - self.x) / self.width) ** 2 + (dy / np.where(dy >= 0, self.upper, self.lower)) ** 2

    def surface(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        return student_front(x, y) + .00052 + .0044 * np.maximum(1 - self.level(x, y), 0)


def student_eye(side: int) -> EyeCut:
    return (EyeCut(-.043, 1.581, .0197, .0068, .0061, -.078) if side < 0 else
            EyeCut(.0445, 1.5798, .0192, .0060, .0064, .065))


def _lens_patch(x: np.ndarray, y: np.ndarray, radius: np.ndarray,
                depth: Callable, rings: int = 6) -> Geometry:
    """A front-facing radial patch with one centre, no floating shell or pole hole."""
    px = np.linspace(0, 1, rings + 1)[1:, None] * radius * x
    py = np.linspace(0, 1, rings + 1)[1:, None] * radius * y
    xx, yy, zz = depth(px, py)
    patch = grid_surface(np.stack([xx, yy, zz], axis=2), cap=False)
    count = len(x)
    center = len(patch.positions)
    t = np.c_[np.full(count, center), np.arange(count), np.roll(np.arange(count), -1)]
    return Geometry(np.r_[patch.positions, np.asarray(depth(0, 0))[None, :]],
                    np.r_[patch.triangles[:, [0, 2, 1]], t])


def eye_patch(side: int, role: str) -> Geometry:
    eye = student_eye(side)
    sides = 40 if role == "sclera" else 24
    theta = np.arange(sides) * 2 * np.pi / sides
    u, v = np.cos(theta), np.sin(theta)
    if role == "sclera":
        x = eye.width * u
        y = np.where(v >= 0, eye.upper, eye.lower) * v + x * eye.tilt
        return _lens_patch(x, y, np.ones(len(x)),
                           lambda x, y: (x + eye.x, y + eye.y, eye.surface(x + eye.x, y + eye.y)))
    rx, ry, inset, ox, oy = {"iris": (.0073, .0078, .00026, -.0026, .0008),
                             "pupil": (.0031, .0038, .00052, -.0026, .0008),
                             "glint": (.00068, .00088, .00078, -.0047, .0027)}[role]
    x, y = rx * u, ry * v
    # Where an iris meets a lid it terminates at the lens rim. Projection and tint do
    # not hide geometry sticking through the skin in a three-quarter view.
    low, high = np.zeros(len(x)), np.ones(len(x))
    for _ in range(12):
        mid = (low + high) * .5
        inside = eye.level(eye.x + ox + mid * x, eye.y + oy + mid * y) <= .975
        low, high = np.where(inside, mid, low), np.where(inside, high, mid)
    return _lens_patch(x, y, low, lambda a, b: (a + eye.x + ox, b + eye.y + oy,
                        eye.surface(a + eye.x + ox, b + eye.y + oy) + inset), rings=4)


def eyelid(side: int) -> Geometry:
    eye = student_eye(side)
    theta = np.linspace(np.pi, 0, 21)
    x = eye.x + eye.width * np.cos(theta)
    y = eye.y + eye.upper * np.sin(theta) + (x - eye.x) * eye.tilt
    z = eye.surface(x, y) + .00005
    radius = .00065 + .0015 * np.sin(theta) ** .65
    return tube(np.c_[x, y, z].tolist(), radius.tolist(), 9, .76)


def brow(side: int) -> Geometry:
    x = np.linspace(.017, .068, 17) * side
    t = np.linspace(0, 1, len(x))
    y = 1.5998 + .0049 * np.sin(t * np.pi * 1.07) - .0038 * t ** 2
    y -= .0018 if side > 0 else 0
    r = .00055 + .00155 * np.sin(np.pi * t ** .8)
    return tube(np.c_[x, y, student_front(x, y) + .00045].tolist(), r.tolist(), 9, .67)


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
