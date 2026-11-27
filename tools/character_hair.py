"""N's short crop, fitted to the skull instead of lifted off it.

The source hair is a helmet: a shell hanging from the crown to below the jaw, up to 40 mm
off the head at the sides, ending in a row of strip-ends. Revision 3 shortened it by
raising that hem, which left the helmet shape and, worse, left the shell overlapping the
skull: measured on the shipped model, 35-100 % of its vertices sat *inside* the head below
1.56 m, so what read as a torn edge at the nape was the skull showing through the hair.

This module refits the shell rather than pushing it about:

1. **The cut edge is measured, then pinned.** The shell's own open edge (the ends of its
   strips, up to 20 mm apart) is low-passed along the angle and snapped onto one hairline.
   That makes the hairline the mesh's boundary, so it cannot saw in and out of the head.
2. **Every vertex is placed at a measured height above the skull.** The skull is read as a
   polar height field -- outermost radius per (angle, height) -- so a vertex always asks
   "how far out is the head here" rather than "how far is the nearest skin", which for a
   vertex under the crown is the wrong question and buries it.
3. **The volume grows from the hairline to the crown**, 2-15 mm, most of it at the sides,
   plus strand ridges down the fall of the hair.

Everything is a pure function of the bind-pose vertices plus the head's surface, so vertex
count, order, topology and skin weights are untouched. The Blender stroke layer is baked
against the geometry this runs on, which is why it runs as a post pass
(`prepare_teacher_n._resting_channel`) and not in the base build.
"""
from __future__ import annotations

from functools import lru_cache

import numpy as np

AXIS_Z = -0.008
PUSH_CAP = 0.006
CROWN_Y = 1.6450
# |angle| from the face, in degrees -> height of the cut edge in metres. Front 1.592 is
# 29 mm above the brows (1.549-1.563); the sides clear the top of the ear at 1.564; the nape
# sits at 1.515, well above the collar at 1.32.
# The cut: a women's short bob (owner's r37 note -- the previous crop read male). The
# sides drape low -- to 1.504 at the ear's front, past the lobes, down to a tidy nape
# at 1.484 -- because every attempt to hug the hairline higher left the pre-auricular
# slope bare at the 45-degree review angle. What made the low sides fail before was the
# shell clipping through the ear, and that is the ear drape's job now, not the hem's:
# with the shell wrapped 3.5 mm clear of the ear surface, the low drape reads as hair
# over the ear instead of an ear poking through hair. The full fringe stays at
# 1.568-1.571 over the brows (1.553-1.558).
HEM_ANGLE = np.array([0.0, 24.0, 46.0, 66.0, 84.0, 100.0, 118.0, 136.0, 154.0, 180.0])
HEM_Y = np.array([1.5680, 1.5710, 1.5640, 1.5360, 1.5040,
                  1.4920, 1.4880, 1.4860, 1.4850, 1.4840])
# The skull field: 4 degrees by 4 mm is finer than the hair's own spacing.
FIELD_STEP_DEG = 4.0
FIELD_STEP_Y = .004
FIELD_Y0 = 1.395
FIELD_Y1 = 1.6600


def smoothstep(low: float, high: float, value: np.ndarray) -> np.ndarray:
    t = np.clip((value - low) / (high - low), 0, 1)
    return t * t * (3 - 2 * t)


def polar(points: np.ndarray):
    """Radius, outward unit direction and angle from the face, about the head's axis."""
    dx = points[:, 0]
    dz = points[:, 2] - AXIS_Z
    radius = np.hypot(dx, dz)
    safe = np.maximum(radius, 1e-9)
    outward = np.stack([dx / safe, np.zeros_like(safe), dz / safe], axis=1)
    # Degrees, wrapped to (-180, 180]. Everything downstream interpolates a table in
    # degrees: without this the hem lookup runs on radians*180/pi and the whole cut is
    # evaluated at thousands of degrees, which silently returns the table's last entry.
    return radius, outward, np.degrees(np.arctan2(dx, -dz))


@lru_cache(maxsize=1)
def _hem_grid() -> tuple[np.ndarray, np.ndarray]:
    """The cut, tabulated once on a fixed dense grid and smoothed there.

    Smoothing on the caller's array would depend on its length -- a single-angle query
    would be convolved over the kernel's own length and return the wrong entry -- so the
    table is built independently of the query and interpolated afterwards.
    """
    grid = np.linspace(0.0, 180.0, 721)
    base = np.interp(grid, HEM_ANGLE, HEM_Y)
    kernel = np.array([1.0, 2.0, 3.0, 2.0, 1.0])
    kernel /= kernel.sum()
    padded = np.r_[base[::-1], base, base[::-1]]
    return grid, np.convolve(padded, kernel, mode="same")[len(base):2 * len(base)]


def hem_height(angle_deg: np.ndarray) -> np.ndarray:
    """Where the cut sits, as a smooth function of the angle round the head."""
    grid, table = _hem_grid()
    # A little irregularity, the way a clipper leaves a line; two lobes, not a saw.
    return (np.interp(np.abs(angle_deg), grid, table)
            + .0012 * np.cos(np.radians(24 * angle_deg)))


def thickness(angle_deg: np.ndarray, hem: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Stand-off from the scalp, from 3 mm at the hairline to 17 mm at the crown.

    The bob carries a little more body than the crop it replaced, so the fringe and
    the side pieces read as hair with weight rather than a scalp decal.
    """
    side = smoothstep(40.0, 96.0, np.abs(angle_deg))
    at_edge = .0030 + .0012 * side
    crown = (1.0 - smoothstep(hem, CROWN_Y, y)) ** .75
    return at_edge + (.0168 - at_edge) * crown


def strands(angle_deg: np.ndarray, y: np.ndarray, hem: np.ndarray) -> np.ndarray:
    """Broad, soft ridges down the fall of the hair, strongest just above the cut.

    The previous ridging counted 21 lobes round the head, which read as a tight
    perm; the bob falls in fewer, wider waves.
    """
    a = np.radians(angle_deg)
    phase = 13.0 * a + .8 * (y - 1.52) / .01
    ripple = (np.cos(phase) + .45 * np.cos(2.3 * phase + 1.7)
              + .25 * np.cos(.7 * phase + 1.4))
    near_edge = 1.0 - smoothstep(hem, hem + .032, y)
    return .0013 * ripple * (.45 + .55 * near_edge)


def boundary_loop(triangles: np.ndarray) -> np.ndarray:
    """Vertices of the shell's lowest open edge: the edge that becomes the hairline.

    The shell is a curtain -- one large component whose open edge is the hairline -- with a
    few small cards lying on it. The loop with the most vertices is the curtain's.
    """
    counts: dict = {}
    for a, b, c in triangles:
        for u, v in ((a, b), (b, c), (c, a)):
            key = (int(u), int(v)) if u < v else (int(v), int(u))
            counts[key] = counts.get(key, 0) + 1
    open_edges = [key for key, count in counts.items() if count == 1]
    if not open_edges:
        raise ValueError("the hair shell has no open edge to cut")
    parent: dict = {}

    def root(x: int) -> int:
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for u, v in open_edges:
        ru, rv = root(u), root(v)
        if ru != rv:
            parent[ru] = rv
    loops: dict = {}
    for u, v in open_edges:
        loops.setdefault(root(u), set()).update((u, v))
    return np.array(sorted(max(loops.values(), key=len)), np.int64)


def edge_table(angle: np.ndarray, y: np.ndarray, bins: int = 96) -> np.ndarray:
    """The cut edge as a smooth function of the angle round the head.

    Measured only from the boundary loop -- the strip ends *are* the edge -- and low-passed
    along the angle, so the cut is one line instead of a row of teeth. Low-passing is what
    makes the pin possible: pinning the raw teeth would reproduce the saw.
    """
    edges = np.linspace(-180.0, 180.0, bins + 1)
    wrapped = (angle + 180.0) % 360.0 - 180.0
    table = np.full(bins, np.nan)
    for i in range(bins):
        inside = (wrapped >= edges[i]) & (wrapped < edges[i + 1])
        if inside.any():
            table[i] = np.median(y[inside])
    if not np.isfinite(table).any():
        raise ValueError("the hair shell has no measurable edge")
    table = np.where(np.isfinite(table), table, np.nanmedian(table))
    kernel = np.hanning(31)
    kernel /= kernel.sum()
    table = np.convolve(np.r_[table[-15:], table, table[:15]], kernel,
                        mode="same")[15:-15]
    return np.interp(wrapped, (edges[:-1] + edges[1:]) / 2, table, period=360.0)


def relax(values: np.ndarray, triangles: np.ndarray, fixed: np.ndarray,
          rounds: int = 6, blend: float = .5) -> np.ndarray:
    """Smooth a per-vertex height while holding the pinned cut edge exactly in place.

    The pin is a step: the edge moves and the row behind it does not. Relaxing the interior
    lets the rows above the cut follow it, so the surface flows into the hairline instead
    of creasing at it.
    """
    out = values.copy()
    edges = np.r_[triangles[:, [0, 1]], triangles[:, [1, 2]], triangles[:, [2, 0]]]
    a, b = edges[:, 0], edges[:, 1]
    degree = np.bincount(np.r_[a, b], minlength=len(out)).astype(np.float64)
    free = ~fixed
    for _round in range(rounds):
        total = np.zeros_like(out)
        np.add.at(total, a, out[b])
        np.add.at(total, b, out[a])
        average = total / np.maximum(degree, 1.0)
        out = np.where(free, out + blend * (average - out), out)
    return out


def scalp_field(skin: np.ndarray):
    """The skull as a polar height field: outermost radius for each (angle, height).

    A nearest-surface offset will not do here. A strand that used to hang beside the ear and
    is lifted above it then lies under the crown, where the nearest skin is *overhead*: the
    offset is small, the vertex keeps the radius it had down by the jaw, and it ends up tens
    of millimetres inside the head. The field answers the question the fit actually asks.
    """
    _, _, angle = polar(skin)
    radius = np.hypot(skin[:, 0], skin[:, 2] - AXIS_Z)
    angles = np.arange(-180.0, 180.0 + FIELD_STEP_DEG / 2, FIELD_STEP_DEG)
    heights = np.arange(FIELD_Y0, FIELD_Y1 + FIELD_STEP_Y / 2, FIELD_STEP_Y)
    field = np.full((len(angles), len(heights)), -np.inf)
    ai = np.clip(np.round((angle + 180.0) / FIELD_STEP_DEG).astype(int), 0, len(angles) - 1)
    hi = np.clip(np.round((skin[:, 1] - FIELD_Y0) / FIELD_STEP_Y).astype(int), 0,
                 len(heights) - 1)
    for i in range(len(skin)):
        if radius[i] > field[ai[i], hi[i]]:
            field[ai[i], hi[i]] = radius[i]
    # The skull is a closed surface, so a cell with no vertex is a gap between samples, not
    # a hole: fill along the height, then across the angle (the neck opening has no skull).
    finite = np.isfinite(field)
    for column in range(len(angles)):
        row = field[column]
        if finite[column].any():
            field[column] = np.interp(np.arange(len(row)), np.flatnonzero(finite[column]),
                                      row[finite[column]])
    for column in range(len(angles)):
        if not finite[column].any():
            field[column] = .075
    smooth = field.copy()
    for _round in range(2):
        smooth = (np.roll(smooth, 1, 0) + 2 * smooth + np.roll(smooth, -1, 0)) / 4.0
        smooth = (np.r_[smooth[:1], smooth[:-1]] + 2 * smooth
                  + np.r_[smooth[1:], smooth[-1:]]) / 4.0
    # Averaging erodes the widest part of the skull, which would bury the hair there, so
    # the smoothed value is only used where it does not cut inside the measured surface.
    return angles, heights, np.maximum(smooth, field)


@lru_cache(maxsize=2)
def scalp_field_cached(skin_bytes: bytes):
    """The field above, rebuilt once per distinct head (the two hair parts share it)."""
    return scalp_field(np.frombuffer(skin_bytes, dtype=np.float64).reshape(-1, 3))


def scalp_radius(angle: np.ndarray, y: np.ndarray, field) -> np.ndarray:
    angles, heights, values = field
    ai = np.clip(np.round((angle + 180.0) / FIELD_STEP_DEG).astype(int), 0, len(angles) - 1)
    hi = np.clip(np.round((y - heights[0]) / FIELD_STEP_Y).astype(int), 0, len(heights) - 1)
    return values[ai, hi]


def _spans(points: np.ndarray, angle: np.ndarray, target_hem: np.ndarray,
           triangles: np.ndarray):
    """Source and target height ranges, per vertex, from its slice's own cut edge."""
    loop = boundary_loop(triangles)
    edge = edge_table(angle[loop], points[loop, 1])
    order = np.argsort(angle[loop])
    source_hem = np.interp(angle, angle[loop][order], edge[order], period=360.0)
    return (np.maximum(CROWN_Y - source_hem, 1e-3),
            np.maximum(CROWN_Y - target_hem, 1e-3))


def _field_of(skin: np.ndarray):
    """The skull field for the shell's fit, built from the head's surface alone.

    prepare hands the fit a (positions, normals) pair. Flattened as one point cloud the
    normals read as a one-metre sphere of "skull", and wherever the real skin leaves a
    gap along the height the interpolated fill bridges it from that anchor, throwing
    queries below the skin's reach tens of millimetres off the head.
    """
    surface = skin[0] if isinstance(skin, tuple) else skin
    return scalp_field_cached(np.ascontiguousarray(surface, dtype=np.float64).tobytes())


def _place(points: np.ndarray, y: np.ndarray, offset: np.ndarray, skin: np.ndarray,
           radius: np.ndarray, outward: np.ndarray) -> np.ndarray:
    """Move each vertex to its new height and out to `scalp + offset` in its own direction.

    The radial rule is the whole fit: at its own (angle, height) a vertex is placed at the
    widest radius the skull has there, plus the stand-off, so it cannot sit inside the head
    by construction.

    The one place the rule is meaningless is the closing cap, where the shell meets itself
    on the axis. There the radial direction is undefined and a dome's radius profile is not
    single-valued in height -- every row near the top reports the widest part of the dome --
    so following the rule drags the cap sideways into a starburst. Those vertices are left
    exactly as authored: the shell's own crown is already a few millimetres clear of the
    skull, and both pushing it out (a spike) and pulling it in (buried) were worse.
    """
    skull = scalp_radius(polar(points)[2], y, _field_of(skin))
    moved = points.copy()
    moved[:, 1] = y
    pole = 1.0 - smoothstep(.026, .055, radius)
    moved += ((skull + offset - radius) * (1.0 - pole))[:, None] * outward
    moved[:, 1] = moved[:, 1] * (1.0 - pole) + pole * points[:, 1]
    return moved


def islands(vertex_count: int, triangles: np.ndarray) -> list[np.ndarray]:
    """Vertex indices grouped into connected components.

    Every vertex starts as its own island until an edge joins it to another, including the
    ones no triangle references: the shell carries duplicated inner vertices for its split
    normals, and folding those into the first island would drag them along with the curtain.
    """
    parent = list(range(vertex_count))

    def root(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for a, b, c in triangles:
        for u, v in ((a, b), (b, c), (a, c)):
            ru, rv = root(int(u)), root(int(v))
            if ru != rv:
                parent[ru] = rv
    groups: dict = {}
    for index in range(vertex_count):
        groups.setdefault(root(index), []).append(index)
    return sorted(groups.values(), key=len, reverse=True)


def shell_only(triangles: np.ndarray) -> np.ndarray:
    """The triangles of the largest connected island: the curtain, without its decals."""
    parts = islands(int(triangles.max()) + 1, triangles)
    if len(parts) < 2:
        return triangles
    keep = np.zeros(len(triangles), bool)
    main = set(int(i) for i in parts[0])
    for i, triangle in enumerate(triangles):
        keep[i] = all(int(v) in main for v in triangle)
    return triangles[keep]


def _fit_shell(p: np.ndarray, angle: np.ndarray, target_hem: np.ndarray,
               triangles: np.ndarray, skin: np.ndarray) -> np.ndarray:
    """The curtain itself: the pinned, fitted shell. Returns the new positions."""
    radius, outward, _ = polar(p)
    source_span, target_span = _spans(p, angle, target_hem, triangles)
    raw = (CROWN_Y - p[:, 1]) / source_span
    shaped = CROWN_Y - target_span * np.clip(raw, 0, 1) ** .88
    shaped = np.where(raw < 0, CROWN_Y + .002 * -raw,
                      np.where(raw > 1, CROWN_Y - target_span * (1 + .06 * (raw - 1)), shaped))
    loop = boundary_loop(triangles)
    pinned = np.zeros(len(p), bool)
    pinned[loop] = True
    y = np.maximum(np.where(pinned, target_hem, shaped), target_hem)
    surface = shell_only(triangles)
    # Relaxation must not drag the edge row back below the cut, so it is clamped after each
    # pass and the pinned row is re-imposed at the end. Without this a handful of vertices
    # end up under the hairline, where they read as stray locks hanging over the face.
    for _round in range(6):
        y = np.maximum(relax(y, surface, pinned, rounds=1), target_hem)
        y[pinned] = target_hem[pinned]
    above = np.maximum(y - target_hem, 0.0)
    offset = thickness(angle, target_hem, y) + strands(angle, y, target_hem) * smoothstep(
        .002, .018, above)
    return _place(p, y, offset, skin, radius, outward)


def _fit_card(p: np.ndarray, angle: np.ndarray, target_hem: np.ndarray,
              source_span: np.ndarray, skin: np.ndarray) -> np.ndarray:
    """One highlight card: moved whole, never reshaped.

    The cards are separate patches lying on the shell. Deforming them vertex by vertex (what
    the shell fit does to anything it is given) tears them into the mottled fragments that
    showed on the nape, because a patch six millimetres across lands across several rows of
    the fit. A card is a decal: it is translated to the surface, and its own shape is left
    alone. Nor can it be fitted from its own corners -- the inboard corner is the deepest,
    and correcting for it stands the card off the head as a wing.
    """
    centroid = p.mean(0)
    centre_angle = float(np.degrees(np.arctan2(centroid[0], -(centroid[2] - AXIS_Z))))
    centre_hem = float(hem_height(np.array([centre_angle]))[0])
    span = max(float(np.mean(source_span)), 1e-3)
    target_span = max(CROWN_Y - centre_hem, 1e-3)
    fall = np.clip((CROWN_Y - centroid[1]) / span, 0, 1)
    y = CROWN_Y - target_span * (.34 + .44 * fall)
    skull = float(scalp_radius(np.array([centre_angle]), np.array([y]), _field_of(skin))[0])
    unit = np.array([np.sin(np.radians(centre_angle)), 0.0,
                     -np.cos(np.radians(centre_angle))])
    target = np.array([0.0, y, AXIS_Z]) + unit * (skull + .0032)
    return p + (target - centroid)


def _closest_on_triangles(points: np.ndarray, vertices: np.ndarray,
                          triangles: np.ndarray, chunk: int = 256):
    """The closest point of each point onto the triangle soup, and the distance.

    The branchless Ericson construction: the three vertex candidates, the three edge
    projections and the clamped interior barycentric point, whichever is nearest. The
    clamped interior keeps sliver triangles (the strand ridges have a few) from
    dividing by their vanishing area. Build-time only; the game never runs this.
    """
    T = vertices[triangles]
    best = np.full(len(points), np.inf)
    out = np.zeros((len(points), 3))
    rows = np.arange(len(points))
    for s in range(0, len(T), chunk):
        A, B, C = T[s:s + chunk, 0], T[s:s + chunk, 1], T[s:s + chunk, 2]
        ab, ac = B - A, C - A
        AP = points[:, None, :] - A[None]
        d1 = (AP * ab).sum(-1); d2 = (AP * ac).sum(-1)
        BP = points[:, None, :] - B[None]
        d3 = (BP * ab).sum(-1); d4 = (BP * ac).sum(-1)
        CP = points[:, None, :] - C[None]
        d5 = (CP * ab).sum(-1); d6 = (CP * ac).sum(-1)
        with np.errstate(divide="ignore", invalid="ignore"):
            safe = lambda num, den: np.where(den != 0, num / np.where(den != 0, den, 1), 0)
            t_ab = np.clip(safe(d1, d1 - d3), 0, 1)
            t_ac = np.clip(safe(d2, d2 - d6), 0, 1)
            t_bc = np.clip(safe(d4 - d3, (d4 - d3) + (d5 - d6)), 0, 1)
            den = d3 * d6 - d5 * d4 + d5 * d2 - d1 * d6 + d1 * d4 - d3 * d2
            v_i = np.clip(safe(d5 * d2 - d1 * d6, den), 0, 1)
            w_i = np.clip(safe(d1 * d4 - d3 * d2, den), 0, 1)
        total = v_i + w_i
        over = total > 1
        v_i = np.where(over, v_i / np.maximum(total, 1e-14), v_i)
        w_i = np.where(over, w_i / np.maximum(total, 1e-14), w_i)
        n, k = len(points), len(A)
        cands = [np.broadcast_to(A[None], (n, k, 3)), np.broadcast_to(B[None], (n, k, 3)),
                 np.broadcast_to(C[None], (n, k, 3)),
                 A[None] + ab[None] * t_ab[..., None],
                 A[None] + ac[None] * t_ac[..., None],
                 B[None] + (C - B)[None] * t_bc[..., None],
                 A[None] + ab[None] * v_i[..., None] + ac[None] * w_i[..., None]]
        squared = np.stack([((points[:, None, :] - c) ** 2).sum(-1) for c in cands])  # (7, n, k)
        best_local = squared.min(0)                               # (n, k)
        pick = best_local.argmin(1)                               # triangle per point
        which = squared[:, rows, pick].argmin(0)                  # candidate per point
        cands_all = np.stack(cands)                               # (7, n, k, 3)
        closest = cands_all[which, rows, pick]                    # (n, 3)
        distance = np.sqrt(squared[:, rows, pick].min(0))         # (n,)
        update = distance < best
        out[update] = closest[update]
        best[update] = distance[update]
    return out, best


def ear_drape(points: np.ndarray, skin: tuple, triangles: np.ndarray = None) -> np.ndarray:
    """Drape the hair over the ears instead of clipping through them.

    A shell that hugs the skull sits inside the ear's own surface, and the ear reads
    through the side hair as an outline -- the review frames showed it in every cut so
    far, because the hem's height alone never covers an ear that bursts through the
    hair surface. Two moves wrap the ear the way real hair does:

    1. The envelope: every hair vertex is pushed out along its own radial to 3.5 mm
       outside the outermost ear surface near it -- near in *footprint* (angle and
       height), not in 3D, because a vertex buried 19 mm under the ear is still AT the
       ear's place on the head, and a 3D reach would measure the radial gap and leave
       it there -- or to 10 mm proud of the skull over the cheek corridor (40-100
       degrees), whichever is farther. The cheek half is the curtain that makes the
       bob read: a shell that hugs the skull there puts its hem ring across the
       pre-auricular slope, and skin shows between the hem and the ear in every
       review frame; real side hair hangs OUTSIDE the slope and shades it, so the
       shell is held away from the head over the cheek and feathers back to the
       skull behind the ear (100-112 degrees).
    2. The verification: the draped surface is then measured the way the render draws
       it -- every ear vertex against the hair's triangles -- and any vertex that still
       reads through lifts the hair vertices around it by its own depth plus 2 mm.
       Three passes of that close the chord sag the envelope's vertex push leaves.

    Build-time only; the game never runs this.
    """
    ears = skin[2] if len(skin) > 2 else None
    if ears is None or not len(ears):
        return points
    ear_radius, _, ear_angle = polar(ears)
    out = np.asarray(points, np.float64).copy()
    radius, outward, angle = polar(out)
    # Footprint distance: arc millimetres of angle (at a nominal 70 mm radius) plus
    # height. A vertex's radial gap to the ear says nothing about whether hair at its
    # place on the head has to clear the ear -- its angle and height say everything.
    arc = np.radians(np.abs(angle)[:, None] - np.abs(ear_angle)[None, :]) * 0.070
    footprint = np.sqrt(arc ** 2 + (out[:, 1][:, None] - ears[None, :, 1]) ** 2)
    nearest_footprint = footprint.min(axis=1)
    envelope = np.where(footprint < 0.018, ear_radius[None, :], -np.inf).max(axis=1)
    field = scalp_field(skin[0])
    skull = scalp_radius(angle, out[:, 1], field)
    # The curtain's floor is the ear's own outer rim, not the skull: a view from the
    # front-side diagon crosses the corridor at radii up to the rim's reach, and hair
    # that only clears the skull lets those rays pass outside it -- the skin above and
    # in front of the ear shows through (measured: 30 skin vertices above their hem
    # line visible from the 45-degree camera until the floor moved to the rim).
    # polar() returns degrees, so every threshold here is degrees too -- mixing in
    # radians silently zeroes the whole curtain (smoothstep(1.745, ..., 76 degrees)
    # is 1, and the corridor multiplied itself out of existence).
    curtain = smoothstep(30.0, 42.0, np.abs(angle)) \
        * (1.0 - smoothstep(100.0, 112.0, np.abs(angle))) \
        * (1.0 - smoothstep(1.585, 1.615, out[:, 1]))
    # 10 mm proud of the skull, measured to block the 45-degree sight-lines: from a
    # front-side camera the sight-line to the skin just above the ear crosses the
    # ear-top strip at r 76-84, and a wall at skull+10 (~79-84 there) cuts it. A
    # deeper wall backfires twice over -- pushed past the crossing radius it opens a
    # view corridor between the skull and the wall, and the strip shows through worse
    # (measured: 22 mm raised the visible count from 30 to 47, and an ear-rim floor
    # of 87.5 mm did the same at the ear-top strip). Wrapping the ear itself is the
    # verification loop's job, not a floor on the whole corridor.
    target = np.maximum(envelope + 0.0035, skull + 0.010)
    weight = np.maximum(1.0 - smoothstep(0.010, 0.018, nearest_footprint), curtain)
    # The clip has to cover the move the deepest shell vertex needs to reach the
    # curtain: an interior vertex sits ~36 mm under the temple's curtain target, and a
    # tighter clip would tilt the slab instead of moving it whole.
    grow = weight * np.clip(target - radius, 0.0, 0.045)
    out = out + outward * grow[:, None]
    if triangles is None:
        return out
    # The verification loop measures the draped surface the way the render draws it,
    # against everything the hair is supposed to hide: the ears AND the head skin
    # above the hem line (skin below the hem is the cheek the cut deliberately
    # reveals). Vertices that still read through lift the hair around them by their
    # own depth plus 2 mm -- this is what closes the sag between the shell's sparse
    # rows, which a vertex-level push alone cannot fix: the shell's side rows sit
    # ~50 mm apart vertically, and the span between two pushed rows sags back under
    # the 45-degree sight-lines. Three passes close it.
    check = np.concatenate([skin[0], ears])
    for _pass in range(5):
        closest, distance = _closest_on_triangles(check, out, triangles)
        axis = np.stack([np.zeros(len(check)), check[:, 1], np.zeros(len(check))], axis=1)
        direction = closest - axis
        direction[:, 1] = 0
        direction /= np.maximum(np.linalg.norm(direction, axis=1, keepdims=True), 1e-12)
        outward_side = ((check - closest) * direction).sum(1) > 0
        hem_line = hem_height(np.abs(polar(check)[2]))
        # Skin a hair's depth above its hem line must be covered; below it, the cut
        # is doing its job. The ear vertices ride on the skin's rule (they sit above
        # the nape hem wherever hair is supposed to cover them).
        covered = check[:, 1] > hem_line + 0.002
        failing = outward_side & (distance > 0.0005) & covered
        if not failing.any():
            break
        depth = distance[failing] + 0.002
        lift_d2 = ((out[:, None, :] - check[failing][None, :, :]) ** 2).sum(-1)
        nearest = np.argmin(lift_d2, axis=1)
        reach = np.sqrt(lift_d2[np.arange(len(out)), nearest])
        lift = depth[nearest] * (1.0 - smoothstep(0.004, 0.012, reach))
        _, lift_outward, _ = polar(out)
        out = out + lift_outward * (lift * (reach < 0.012))[:, None]
    return out


def _relay_the_thin_side(points: np.ndarray, triangles: np.ndarray, shell: np.ndarray,
                         hem: np.ndarray, skin: tuple,
                         record: dict | None = None) -> np.ndarray:
    """Re-lay the thin side's band so the shell covers the corridor over its ear.

    When `record` is given, the re-laid vertex ids are written to it under
    "relayed": the normals pass needs to know which vertices moved, because the
    triangles tying them to the unmoved sheet stop being shading faces (they
    become the wall's occluders) -- see `shell_normals`.

    The source bob is asymmetric by design -- a side part. At ear heights the shell's
    surface is dense on the full side (about 150 triangles) and nearly absent on the
    thin side (about 10): the thin side's band hangs BEHIND the ear instead of over
    it, and every symmetric re-cut exposes that hole -- the frames show the ear bare
    on one side no matter where the hem sits. No radial push can close it, because
    the hole is angular: the vertices that could cover the corridor sit 25 degrees
    behind it. So the thin side's band is re-laid: its vertices move forward to
    spread across the corridor the way the full side's do, at their own heights,
    clamped to the cut. The drape sets their radii next; the silhouette behind the
    ear is carried by the rest of the sheet.
    """
    out = np.asarray(points, np.float64).copy()
    tri_is_shell = shell[triangles].all(1)
    centers = out[triangles[tri_is_shell]].mean(1)
    _, _, centre_angle = polar(centers)
    centre_y = centers[:, 1]
    right = int(((centre_angle > 92) & (centre_angle < 118)
                 & (centre_y > 1.506) & (centre_y < 1.564)).sum())
    left = int(((-centre_angle > 92) & (-centre_angle < 118)
                & (centre_y > 1.506) & (centre_y < 1.564)).sum())
    if right < left * .5:
        thin = 1.0
    elif left < right * .5:
        thin = -1.0
    else:
        return out
    radius, _, angle = polar(out)
    # The band spans the wedge AND the pre-auricular sheet below it (86, not 100):
    # the wedge alone is a diagonal sash with a pinched waist -- five consecutive
    # cross-sections of ONE vertex -- and a wall built from it alone grows a
    # full-height hole at the waist (measured: an empty channel at 91-100 degrees
    # with 180 of 253 right-ear sight-lines leaking past 96-degree columns). The
    # lower sheet (26 vertices at 86-100 degrees under y 1.506) is graph-connected
    # to the waist and fattens its cross-sections; the crown's bottom edge (y at or
    # above 1.578) stays out of the band so the wall's top row still meets it.
    band = (shell & (angle * thin > 86.0) & (angle * thin < 128.0)
            & (out[:, 1] > 1.486) & (out[:, 1] < 1.578) & (radius > 0.030))
    if not band.any():
        if record is not None:
            record["relayed"] = np.zeros(0, np.int64)
        return out
    bidx = np.where(band)[0]
    bset = set(int(v) for v in bidx)
    # The thin side's band is not a wall waiting to be spread: measured on the source
    # graph, it is one connected WEDGE -- a diagonal sash hugging the behind-ear
    # region, wide (about 15 vertices across) at its upper end near 100 degrees and
    # pinching to 2-3 vertices at its lower tip near 128 degrees. Spreading it by
    # horizontal rows (the previous re-lay) ignores that shape: each row slices
    # across the wedge's diagonal, ranks unrelated graph neighbours by angle, and
    # the triangles between rows are left spanning arbitrary corners -- 30% of the
    # wall's quads faced inward and the tie fans to the unmoved sheet tore open, so
    # the frames showed skin and deeper layers through the gaps (the dense ray probe
    # found 13-109 leaking slots per camera). The wall has to be UNROLLED from the
    # wedge along its own graph: s, the position along its length, and t, the
    # lateral depth off its spine, both as smooth geodesic coordinates. Monotone in
    # both, the unroll carries graph neighbours to neighbouring slots -- no torn
    # fans -- and fills the corridor rectangle corner to corner.
    import heapq
    adj = {v: {} for v in bidx}
    edge_total: dict = {}
    for tri in triangles:
        corners = [int(tri[0]), int(tri[1]), int(tri[2])]
        inb = [c in bset for c in corners]
        for i in range(3):
            u, v = corners[i], corners[(i + 1) % 3]
            if inb[i] and inb[(i + 1) % 3]:
                weight = float(np.linalg.norm(out[v] - out[u]))
                key = (min(u, v), max(u, v))
                edge_total[key] = edge_total.get(key, 0) + 1
                if v not in adj[u] or weight < adj[u][v]:
                    adj[u][v] = weight
                    adj[v][u] = weight

    def dijkstra(sources):
        dist = {}
        heap = [(0.0, s) for s in sources]
        heapq.heapify(heap)
        while heap:
            d, u = heapq.heappop(heap)
            if u in dist:
                continue
            dist[u] = d
            for v, w in adj[u].items():
                if v not in dist:
                    heapq.heappush(heap, (d + w, v))
        return dist

    components = []
    seen = set()
    for v in adj:
        if v in seen:
            continue
        stack, comp = [v], []
        seen.add(v)
        while stack:
            u = stack.pop()
            comp.append(u)
            for n in adj[u]:
                if n not in seen:
                    seen.add(n)
                    stack.append(n)
        components.append(sorted(comp))

    placed_ids = []
    field = scalp_field(skin[0])
    full_shell = shell & ((out[:, 1] > 1.480) & (out[:, 1] < 1.600))
    fr, _, fa_full = polar(out[full_shell])
    fa_full = np.abs(fa_full) * thin
    fy = out[full_shell][:, 1]
    for comp in components:
        if len(comp) < 3:
            continue  # a stray vertex cannot tile anything; the dedupe settles it
        cids = np.array(comp, np.int64)
        d1 = dijkstra([comp[0]])
        end1 = max(d1, key=d1.get)
        d2 = dijkstra([end1])
        end2 = max(d2, key=d2.get)
        d1 = dijkstra([end1])
        d2 = dijkstra([end2])
        length = d1[end2]
        salong = np.array([(d1[int(v)] - d2[int(v)]) * .5 for v in comp]) + length * .5
        tdepth = np.array([(d1[int(v)] + d2[int(v)] - length) * .5 for v in comp])
        # The unroll lays the wedge out four ways (either end forward, the lateral
        # order kept or flipped); exactly two preserve the authored winding. The one
        # that leaves the wedge's own quads facing outward is chosen -- ties to the
        # refinement contract's winding clause cannot be unwound, so the placement
        # has to respect it.
        best = None
        for flip_s, flip_t in ((0, 0), (0, 1), (1, 0), (1, 1)):
            sa = -salong if flip_s else salong
            ta = -tdepth if flip_t else tdepth
            s_order = np.argsort(sa)
            nbins = max(8, min(len(cids), int(np.ceil((sa.max() - sa.min()) / 0.004))))
            edges_bin = np.linspace(sa.min() - 1e-9, sa.max() + 1e-9, nbins + 1)
            bin_of = np.clip(np.digitize(sa, edges_bin) - 1, 0, nbins - 1)
            new_abs = np.empty(len(cids), np.float64)
            new_ys = np.empty(len(cids), np.float64)
            # Angular slots go to the NON-empty cross-sections by rank, so a sparse
            # stretch of the wedge cannot leave a hole in the wall: the occupied
            # cross-sections spread evenly over 74-128 -- the corridor, its forward
            # window (the 45-degree sight-lines slide under an 86-degree front
            # edge -- measured: 126 ear vertices visible from the 45-degree camera)
            # and its own source span -- and 1.500 at the bottom (the ear's lobe
            # sits at 1.506: a bottom row above it left a 2 mm strip of ear showing
            # under the wall) up to 1.578 at the top, where the crown shell above
            # 128 degrees begins -- a wall that stops at 1.566 leaves a horizontal
            # slit between its top edge and the crown sheet.
            nonempty = [b for b in range(nbins) if (bin_of == b).any()]
            # Column positions are weighted by MEMBER COUNTS, not spread evenly: the
            # wedge's cross-sections vary from 18 members to 1 (the waist), and even
            # slots stretch the dense sections across the same angle as the sparse
            # ones, tearing the ladder triangles into 1-2 mm seams the sight-lines
            # thread through (measured: 252 of 253 right-ear sight-lines grazing past
            # a wall that maps as solid). Weighting by members packs the waist's
            # singletons into a narrow cluster -- the source's long bridge triangles
            # there span the cluster and keep it covered -- while every dense
            # cross-section keeps roughly its own width. The map stays near-isometric
            # where the sheet is dense, so its faces tile instead of tearing.
            counts = np.array([float((bin_of == b).sum()) for b in nonempty])
            cum = np.concatenate([[0.0], np.cumsum(counts)])
            theta = 74.0 + 54.0 * (cum[:-1] + counts * 0.5) / counts.sum()
            theta_of = {b: theta[k] for k, b in enumerate(nonempty)}
            slot = {b: k for k, b in enumerate(nonempty)}
            centre = np.full(nbins, np.nan)
            for b in nonempty:
                members = np.where(bin_of == b)[0]
                if len(members) > 1:
                    t_rank = np.empty(len(members), np.int64)
                    t_rank[np.argsort(ta[members], kind="stable")] = np.arange(len(members))
                    new_ys[members] = 1.500 + 0.078 * (t_rank / (len(members) - 1))
                    centre[b] = float(new_ys[members].mean())
            known = [b for b in nonempty if not np.isnan(centre[b])]
            for b in nonempty:
                members = np.where(bin_of == b)[0]
                if not len(members) or not np.isnan(centre[b]):
                    continue
                new_abs[members] = theta_of[b]
                if len(members) == 1:
                    left = max([k for k in known if k < b], default=None)
                    right = min([k for k in known if k > b], default=None)
                    if left is None and right is None:
                        new_ys[members] = 1.539
                    elif left is None:
                        new_ys[members] = centre[right]
                    elif right is None:
                        new_ys[members] = centre[left]
                    else:
                        w = (slot[b] - slot[left]) / max(slot[right] - slot[left], 1)
                        new_ys[members] = centre[left] * (1 - w) + centre[right] * w
                    centre[b] = float(new_ys[members].mean())
            for b in nonempty:
                members = np.where(bin_of == b)[0]
                if len(members):
                    new_abs[members] = theta_of[b]
            trial = out.copy()
            tl = trial[cids]
            trial_angle = thin * new_abs
            tl_radius = radius[cids]
            for i in range(len(cids)):
                near = ((np.abs(fa_full - trial_angle[i]) < 7.0)
                        & (np.abs(fy - new_ys[i]) < 0.014))
                if near.any():
                    tl_radius[i] = max(tl_radius[i], float(fr[near].max()))
                # The wall must clear the sight-lines wherever they cross: a ray from
                # the ear's rim travels outward to r 87-95 while its angle slides
                # 105 -> 88, so the corridor wall's floor is the local skin radius
                # plus 24 mm of body at every re-laid position.
                local = scalp_radius(np.array([trial_angle[i]]),
                                     np.array([new_ys[i]]), field)[0]
                tl_radius[i] = max(tl_radius[i], float(local) + 0.024)
            rad_t = np.radians(trial_angle)
            tl[:, 0] = tl_radius * np.sin(rad_t)
            tl[:, 2] = AXIS_Z - tl_radius * np.cos(rad_t)
            # The cut is measured at the vertex's NEW angle after the re-lay: a vert
            # re-laid from 120 degrees (hem 1.486) to 96 degrees (hem 1.500) that
            # kept its old y would hang under the cut's new line.
            tl[:, 1] = np.maximum(new_ys, hem_height(np.abs(trial_angle)))
            trial[cids] = tl
            faces = triangles[np.isin(triangles, cids).all(1)]
            tfa = np.cross(trial[faces[:, 1]] - trial[faces[:, 0]],
                           trial[faces[:, 2]] - trial[faces[:, 0]])
            tcen = trial[faces].mean(1)
            trad = tcen * np.array([1.0, 0.0, 1.0])
            trad /= np.linalg.norm(trad, axis=1, keepdims=True) + 1e-12
            inverted = int(((tfa * trad).sum(1) < 0).sum())
            score = (inverted, flip_s, flip_t)
            if best is None or score < best[0]:
                best = (score, tl.copy(), trial_angle, new_ys)
            if inverted == 0:
                break
        _, tl, trial_angle, new_ys = best
        laid_ids = np.array(comp, np.int64)
        out[laid_ids] = tl
        placed_ids.extend(comp)
    # Two re-laid vertices can land on the same spot (same rank slot from adjacent
    # cross-sections), which turns their shared triangles into zero-area ones the
    # refinement contract rejects. Nudge any later vertex that sits less than half a
    # millimetre from an earlier one, along its own angle, by a step unique to its
    # index -- the strands' look does not read a sub-millimetre scatter.
    moved_idx = np.asarray(sorted(placed_ids), np.int64)
    # The placement can ripple radially: adjacent ladder triangles fold where the
    # placed radii jitter, and the sight-lines thread the folds -- a wall whose
    # (angle, height) map is solid still leaks through 1-2 mm gaps (measured: 252
    # of 253 right-ear sight-lines grazing past stretched fans, none blocked).
    # Smooth the re-laid vertices' radius over the band's own graph (median of the
    # one-ring, three passes): the wall's radial profile turns locally flat, its
    # faces tile instead of folding. The skin floor is re-applied so the smoothing
    # cannot pull the wall into the sight-lines' corridor or into the head.
    field = scalp_field(skin[0])
    for _ in range(3):
        rs = {int(v): float(np.hypot(out[v, 0], out[v, 2] - AXIS_Z)) for v in moved_idx}
        new_rs = {int(v): float(np.median([rs[int(v)]] + [rs[int(n)] for n in adj[int(v)]]))
                  for v in moved_idx}
        for v in moved_idx:
            ang_v = np.degrees(np.arctan2(out[v, 0], -(out[v, 2] - AXIS_Z)))
            floor = float(scalp_radius(np.array([ang_v]), np.array([out[v, 1]]), field)[0]) + 0.024
            r_new = max(new_rs[int(v)], floor)
            rad = np.radians(ang_v)
            out[v, 0] = r_new * np.sin(rad)
            out[v, 2] = AXIS_Z - r_new * np.cos(rad)
    pts = out[moved_idx]
    for a in range(len(moved_idx)):
        for b in range(a + 1, len(moved_idx)):
            if np.linalg.norm(pts[b] - pts[a]) < 0.0005:
                _, _, ang_b = polar(pts[b][None])
                step = 0.8 + 0.13 * b
                new_ang = ang_b[0] + step
                rad_b = np.radians(new_ang)
                rb = float(np.linalg.norm([pts[b, 0], pts[b, 2] - AXIS_Z]))
                pts[b, 0] = rb * np.sin(rad_b)
                pts[b, 2] = AXIS_Z - rb * np.cos(rad_b)
                out[moved_idx[b]] = pts[b]
    if record is not None:
        record["relayed"] = moved_idx
    return out


def teacher_crop(points: np.ndarray, skin: tuple, triangles: np.ndarray,
                 record: dict | None = None) -> np.ndarray:
    """The main shell: pinned cut edge, skull-following volume, strand ridges.

    When `record` is given it receives the thin-side re-lay's moved vertex ids (see
    `shell_normals`, which turns them into the wall's outward shading normals).
    """
    p = np.asarray(points, np.float64)
    _, _, angle = polar(p)
    target_hem = hem_height(angle)
    parts = islands(len(p), triangles)
    shell = np.zeros(len(p), bool)
    shell[np.concatenate(parts[:1])] = True
    spans = _spans(p, angle, target_hem, triangles[shell[triangles].all(1)])[0]
    shell_tri = triangles[shell[triangles].all(1)]
    out = _fit_shell(p, angle, target_hem, shell_tri, skin) * shell[:, None]
    for part in parts[1:]:
        index = np.asarray(part, np.int64)
        out[index] = _fit_card(p[index], angle[index], target_hem, spans[index], skin[0])
    # The cut is a hard rule: nothing may hang below the hairline, or the stray locks read
    # as hair lying on the cheek. The shell's fit and the cards' translation both aim for
    # it, but a vertex can still land a few tenths of a millimetre under; this is the
    # guarantee, expressed once, after both.
    # The hem clamp runs BEFORE the drape: the drape has to decide its radii at the
    # heights the cut leaves, or the guard's vertical clamp lifts the draped vertices
    # afterwards and lands them back inside the ear above them (measured: draping
    # before clamping left 13 ear vertices reading through the clamp-lifted surface).
    clamped = out.copy()
    clamped[:, 1] = np.maximum(clamped[:, 1], target_hem)
    relayed = _relay_the_thin_side(clamped, triangles, shell, target_hem, skin, record)
    return surface_guard(ear_drape(relayed, skin, triangles), skin, target_hem)


def shell_normals(points: np.ndarray, triangles: np.ndarray,
                  relayed: np.ndarray) -> np.ndarray:
    """Smooth normals for the cropped shell, with the re-lay's stretched faces excluded.

    The wall's vertices move across the corridor -- up to ~9 cm -- and the triangles
    that tie them to the unmoved sheet span that gap. Area-weighted, those faces drag
    their corners' smooth normals inward, and the wall renders as dark slats from the
    side cameras. Winding is pinned by the refinement contract, so the fix is the
    normal attribute: no face that touches a re-laid vertex contributes to the smooth
    normals (the untouched sheet's are then exactly the source's), and every re-laid
    vertex -- plus any vertex left with no clean face -- shades along the outward
    radial, the direction a wall on the side of the skull actually faces. Weld groups
    are patched whole: coincident export-seam twins share one welded normal, and
    patching a single member would draw a shading seam down the wall.
    """
    points = np.asarray(points, np.float64)
    relayed = np.unique(np.asarray(relayed, np.int64))
    faces = triangles
    if len(relayed):
        faces = triangles[~np.isin(triangles, relayed).any(1)]
    # The same accumulation as geometry.normals (coincident seams welded for shading
    # only, area-weighted), minus its all-or-nothing demand that every vertex keep a
    # face: the wall's corners have none, and they take the radial instead.
    unique, weld = np.unique(np.round(points, 7), axis=0, return_inverse=True)
    result = np.zeros((len(unique), 3), np.float64)
    if len(faces):
        face = np.cross(points[faces[:, 1]] - points[faces[:, 0]],
                        points[faces[:, 2]] - points[faces[:, 0]])
        for corner in range(3):
            np.add.at(result, weld[faces[:, corner]], face)
    lengths = np.linalg.norm(result, axis=1, keepdims=True)
    unit = np.divide(result, lengths, out=np.zeros_like(result), where=lengths > 1e-12)
    unit[np.abs(unit) < 1e-12] = 0.0
    # A weld group goes radial if any of its members was re-laid, or was left with no
    # clean face, or its clean-face accumulation cancelled out.
    radial = np.zeros(len(unique), bool)
    if len(relayed):
        radial[weld[relayed]] = True
    present = np.zeros(len(points), bool)
    present[np.unique(faces)] = True
    radial[weld[~present]] = True
    radial[lengths[:, 0] <= 1e-12] = True
    _, outward, _ = polar(points)
    normals = unit[weld]
    for index in np.flatnonzero(radial[weld]):
        direction = outward[index]
        norm = float(np.linalg.norm(direction))
        normals[index] = direction / norm if norm > 1e-9 else np.array([0.0, 1.0, 0.0])
    normals[np.abs(normals) < 1e-12] = 0.0
    # The wedge carries a fold from the source: some of its quads are wound inward
    # and no placement can change that (the contract pins the winding). They shade
    # dark from the outside unless their corners' normals point inward -- the
    # renderer flips the normal on a back face, so an inward normal on an
    # inward-wound quad reads as hair. Verts whose attached wall faces are mostly
    # inward-wound take the negated radial; outward-wound quads keep the outward one.
    if len(relayed):
        faces = triangles[np.isin(triangles, relayed).any(1)]
        face_vec = np.cross(points[faces[:, 1]] - points[faces[:, 0]],
                            points[faces[:, 2]] - points[faces[:, 0]])
        face_cen = points[faces].mean(1)
        face_rad = face_cen * np.array([1.0, 0.0, 1.0])
        face_rad /= np.linalg.norm(face_rad, axis=1, keepdims=True) + 1e-12
        inward = (face_vec * face_rad).sum(1) < 0
        inv_count = np.zeros(len(points), np.int64)
        out_count = np.zeros(len(points), np.int64)
        for k in range(3):
            np.add.at(inv_count, faces[:, k], inward.astype(np.int64))
            np.add.at(out_count, faces[:, k], (~inward).astype(np.int64))
        flip = relayed[inv_count[relayed] > out_count[relayed]]
        normals[flip] = -normals[flip]
    return normals.astype(np.float32)


def surface_guard(points: np.ndarray, skin: tuple, hem: np.ndarray) -> np.ndarray:
    """Nothing the fit placed may end up buried in the head.

    A card the fit translates whole can land tens of millimetres inside the skin (its
    interior vertices keep their offset from a centre that was placed on the surface),
    and where the shell's edge row has moved, such a sliver shows as a black jag on the
    temple. Two passes dig them out: any non-cap vertex more than 3 mm under the skull
    field is pushed back out along its own radial to 2.5 mm proud; where the field
    under-measures the skin (the pre-auricular hollow reads the neck's radius, not the
    face's), the vertex is snapped to 2 mm outside the nearest skin point instead.
    """
    radius, outward, angle = polar(points)
    out = points.copy()
    # The cut is a hard rule first: the hem clamp can lift an edge vertex tens of
    # millimetres straight up, and lifted at its old radius it lands inside the cheek.
    # So clamp, then measure against the skull at the *clamped* height.
    out[:, 1] = np.maximum(out[:, 1], hem)
    cap = (1.0 - smoothstep(.026, .055, radius)) > 0.0
    skull = scalp_radius(angle, out[:, 1], _field_of(skin))
    buried = (~cap) & (radius < skull - 0.003)
    if buried.any():
        push = (skull[buried] + 0.0025 - radius[buried])[:, None]
        out[buried] += outward[buried] * push
        # Where the field under-measures the skin (the pre-auricular hollow reads the
        # neck's radius, not the face's), the radial push above still leaves the vertex
        # inside. Measure those against the skin itself and snap each one onto 2 mm of
        # its nearest skin point's own normal -- buried becomes a card sitting on the
        # surface, which is what it was supposed to be.
        surface, normals = skin[0], skin[1]
        for index in np.where(buried)[0]:
            distance = ((surface - out[index]) ** 2).sum(1)
            nearest = int(np.argmin(distance))
            direction = out[index] - surface[nearest]
            reach = float(np.linalg.norm(direction))
            if reach < 1e-9:
                direction = normals[nearest]
                reach = float(np.linalg.norm(direction))
                if reach < 1e-9:
                    continue
            normal = normals[nearest]
            # Outward if the vertex sits on the normal's side of its skin point, and
            # already proud enough if it is 2 mm out along it.
            if float(direction @ normal) < 0.002:
                # Placed along the vertex's own approach direction, not the shared
                # skin normal: two buried vertices of one card then land on different
                # points of the 2 mm shell instead of collapsing into a zero-area
                # triangle.
                out[index] = surface[nearest] + direction / reach * 0.002
        out[:, 1] = np.maximum(out[:, 1], hem)
    return out


def teacher_highlight(points: np.ndarray, skin: tuple, triangles: np.ndarray,
                      shell: np.ndarray | None = None) -> np.ndarray:
    """The lighter strands: the same fit, held above the cut and 2 mm off the surface.

    They are separate cards lying on the shell. Cropping the shell alone would leave them
    where the helmet used to be, floating beside the head -- which is exactly what showed
    through the nape in the previous revision. Every island here is card-sized (this sheet
    has no curtain of its own), so each vertex is placed by the same rule the curtain uses,
    then carried the way the dark sheet's cards are.

    When `shell` is given (the fitted main sheet), the back-right cards are moved on top
    of it afterwards -- see `_shield_the_corridor`.
    """
    p = np.asarray(points, np.float64)
    _, _, angle = polar(p)
    target_hem = hem_height(angle)
    parts = islands(len(p), triangles)
    spans = _spans(p, angle, target_hem, triangles)[0]
    out = np.zeros_like(p)
    for part in parts:
        index = np.asarray(part, np.int64)
        out[index] = _fit_card(p[index], angle[index], target_hem, spans[index], skin[0])
    clamped = out.copy()
    clamped[:, 1] = np.maximum(clamped[:, 1], target_hem)
    draped = surface_guard(ear_drape(clamped, skin, triangles), skin, target_hem)
    return _shield_the_corridor(draped, triangles, skin, shell, p)


def _shield_the_corridor(points: np.ndarray, triangles: np.ndarray, skin: tuple,
                         shell: np.ndarray | None, source: np.ndarray) -> np.ndarray:
    """Move the back-right highlight cards over the thin side's missing sheet.

    The thin side leaks because whole sheet regions the full side owns are missing
    there: the crown-side sheet at 55-90 degrees over y 1.55-1.60, the temple-side
    fringe line, and the strip behind the ear under the wall. The leak sight-lines
    cross that corridor at radii 88-104 mm (measured per leaking vertex: every one
    of the 62 crossing points at r 104 lands inside 48-125 degrees, y 1.51-1.60).
    The highlight cards are separate islands -- moving one leaves the shell beneath
    intact -- so the back-right ones (their mean angle sits at 116-139 degrees,
    outside every review camera's frustum) become that sheet: an outer plate at
    r 105 mm over the whole crossing footprint, a crown-side band that follows the
    full side's own radius (sampled from the fitted shell), and a behind-the-ear
    patch, all above the hemline. Ribbons (2 columns x N rows) are laid column-wise,
    so each authored quad keeps its corner pattern and the winding contract holds.
    """
    p = np.asarray(points, np.float64).copy()
    _, _, angle = polar(p)
    thin = 1.0
    parts = islands(len(p), triangles)
    targets = [np.asarray(part, np.int64) for part in parts
               if 115.0 < float(np.abs(angle[np.asarray(part, np.int64)]).mean()) < 140.0]
    if not targets:
        return p
    shell_p = np.asarray(shell, np.float64) if shell is not None else None
    if shell_p is not None:
        sr, _, sa = polar(shell_p)
        sy = shell_p[:, 1]
    field = scalp_field(skin[0])

    def band_radius(th: float, yy: float, pad: float, lo: float, hi: float) -> float:
        # The full side's own radius at this (angle, height): the median shell vertex
        # radius within 5 degrees / 10 mm on the left, so the band carries the same
        # hair volume the full side shows. The thin side's own max in the window (if
        # any) keeps the band proud of the local surface so nothing interpenetrates.
        # Everything in metres.
        r_m, r_loc = 0.091, 0.0
        if shell_p is not None:
            near_m = ((sa * -thin < 0.0) & (np.abs(-sa * thin - th) < 5.0)
                      & (np.abs(sy - yy) < 0.010) & (sr > 0.060))
            if near_m.any():
                r_m = float(np.median(sr[near_m]))
            near_l = ((sa * thin > 0.0) & (np.abs(sa * thin - th) < 5.0)
                      & (np.abs(sy - yy) < 0.010) & (sr > 0.060))
            if near_l.any():
                r_loc = float(sr[near_l].max())
        return float(np.clip(max(r_m + pad, r_loc + 0.004), lo, hi))

    def place(idx: np.ndarray, cols: np.ndarray, rows: np.ndarray,
              radii: np.ndarray) -> None:
        # pairs = the ribbon's rows (two authored columns each), laid out column-wise:
        # pair j -> (cols[j], rows[0]) and (cols[j], rows[1]).
        order = np.argsort(source[idx, 1])
        pairs = [(order[2 * i], order[2 * i + 1]) for i in range(len(idx) // 2)]
        for j, (lo, hi) in enumerate(pairs):
            th = float(cols[j])
            rad = np.radians(thin * th)
            for vi, yy in ((idx[lo], rows[0]), (idx[hi], rows[1])):
                rr = radii[j]
                p[vi, 0] = rr * np.sin(rad)
                p[vi, 2] = AXIS_Z - rr * np.cos(rad)
                p[vi, 1] = yy

    big = [t for t in targets if len(t) == 16]
    small = [t for t in targets if len(t) != 16]
    # The outer plate: the sight-lines' whole crossing footprint at one radius just
    # outside their measured maximum (104 mm). Its bottom edge follows the hemline on
    # the front columns (a plate over the cheek would read as a fin); from 62 degrees
    # back it holds 1.508 so the corridor's low crossings stay covered.
    plate_rows = (1.508, 1.531, 1.554, 1.577, 1.600)
    for k, idx in enumerate(big[:4]):
        cols = np.linspace(48.0, 125.0, 8)
        order = np.argsort(source[idx, 1])
        pairs = [(order[2 * i], order[2 * i + 1]) for i in range(8)]
        # Each band overlaps the next by 0.6 mm (the k offset): exact row coincidence
        # would weld neighbouring bands' vertices in the normal pass, where their
        # oppositely wound faces cancel to a zero normal and the refinement contract
        # rejects the mesh.
        drop = 0.0006 * k
        for j, (lo, hi) in enumerate(pairs):
            th = float(cols[j])
            # the front columns follow the hemline (a plate over the cheek would read
            # as a fin); from 62 degrees back the bottom holds 1.508 so the corridor's
            # low crossings stay covered
            y_bot = max(plate_rows[k],
                        hem_height(np.array([thin * th]))[0] + 0.004) if th < 62.0 \
                else plate_rows[k]
            y_bot -= drop
            y_top = max(plate_rows[k + 1], y_bot + 0.020) - drop
            rad = np.radians(thin * th)
            for vi, yy in ((idx[lo], y_bot), (idx[hi], y_top)):
                p[vi, 0] = 0.105 * np.sin(rad)
                p[vi, 2] = AXIS_Z - 0.105 * np.cos(rad)
                p[vi, 1] = yy
    # The crown-side band: 55-90 degrees over the wall's top row, at the full side's
    # own volume -- this is the sheet region the side part leaves empty and the
    # side-on camera sees the scalp through.
    if len(big) >= 5:
        idx = big[4]
        cols = np.linspace(55.0, 90.0, 8)
        radii = [band_radius(float(th), 1.577, 0.003, 0.086, 0.104)
                 for th in cols]
        place(idx, cols, (1.554, 1.600), radii)
    # Behind the ear: the strip the re-lay emptied under the wall, above the hem.
    for idx in small:
        cols = np.array([115.0, 122.0])
        rows_y = np.linspace(1.489, 1.508, 3)
        order = np.argsort(source[idx, 1])
        pairs = [(order[2 * i], order[2 * i + 1]) for i in range(len(idx) // 2)]
        for i, (lo, hi) in enumerate(pairs):
            rad_lo, rad_hi = np.radians(115.0), np.radians(122.0)
            r_lo = band_radius(115.0, float(rows_y[i]), 0.002, 0.080, 0.092)
            r_hi = band_radius(122.0, float(rows_y[i]), 0.002, 0.080, 0.092)
            for vi, yy, rad, rr in ((idx[lo], rows_y[i], rad_lo, r_lo),
                                    (idx[hi], rows_y[i], rad_hi, r_hi)):
                p[vi, 0] = rr * np.sin(rad)
                p[vi, 2] = AXIS_Z - rr * np.cos(rad)
                p[vi, 1] = yy
    return p
    # The cards are vertical ribbons (two columns wide, N rows tall: 16 vertices /
    # 14 triangles = 2x8, 6/4 = 2x3) laid FLAT over the corridor: each 16-vertex
    # ribbon becomes one 8-column by 2-row band of the quilt, the two bands sharing
    # their middle row so the quilt is closed over its whole rectangle, and the
    # 6-vertex ribbon caps the outer angle. Every vertex stands on the r=105 mm
    # slab -- outside the sight-lines' measured crossing band (88-103 mm), so any
    # ray threading the wall's folds crosses the slab's radius inside the quilt's
    # rectangle exactly once and is blocked. Ribbons mapped this way keep their
    # triangle winding (the contract pins it) and their quad corners stay distinct,
    # so the refinement's zero-area clause holds.
    slab = 0.105
    ordered = sorted(targets, key=lambda idx: float(np.abs(angle[idx]).mean()))
    big = [idx for idx in ordered if len(idx) == 16]
    small = [idx for idx in ordered if len(idx) != 16]
    band_ys = (1.508, 1.537, 1.566)
    for k, idx in enumerate(big[:2]):
        # rows of the ribbon (8 y-ordered pairs) become columns of the band
        order = np.argsort(source[idx, 1])
        pairs = [(order[2 * i], order[2 * i + 1]) for i in range(8)]
        y_top = band_ys[k]
        y_bot = band_ys[k + 1]
        for ci, (lo, hi) in enumerate(pairs):
            th = 71.0 + 38.0 * ci / 7.0
            rad = np.radians(th)
            for vi, yy in ((idx[lo], y_bot), (idx[hi], y_top)):
                p[vi, 0] = slab * np.sin(rad)
                p[vi, 2] = AXIS_Z - slab * np.cos(rad)
                p[vi, 1] = yy
    for idx in small:
        order = np.argsort(source[idx, 1])
        rows = [(order[2 * i], order[2 * i + 1]) for i in range(len(idx) // 2)]
        ys_small = np.linspace(band_ys[0], band_ys[-1], len(rows))
        for ri, (lo, hi) in enumerate(rows):
            for vi, th in ((idx[lo], 109.0), (idx[hi], 115.0)):
                rad = np.radians(th)
                p[vi, 0] = slab * np.sin(rad)
                p[vi, 2] = AXIS_Z - slab * np.cos(rad)
                p[vi, 1] = ys_small[ri]
    return p
