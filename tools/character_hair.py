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
       it there. The push feathers out over 10-18 mm of footprint, so the drape starts
       slightly in front of the ear and dies out behind and below it, no step.
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
    target = np.where(np.isfinite(envelope), envelope + 0.0035, radius)
    weight = 1.0 - smoothstep(0.010, 0.018, nearest_footprint)
    grow = weight * np.clip(target - radius, 0.0, 0.03)
    out = out + outward * grow[:, None]
    if triangles is None:
        return out
    for _pass in range(3):
        closest, distance = _closest_on_triangles(ears, out, triangles)
        axis = np.stack([np.zeros(len(ears)), ears[:, 1], np.zeros(len(ears))], axis=1)
        direction = closest - axis
        direction[:, 1] = 0
        direction /= np.maximum(np.linalg.norm(direction, axis=1, keepdims=True), 1e-12)
        outward_side = ((ears - closest) * direction).sum(1) > 0
        failing = outward_side & (distance > 0.0005)
        if not failing.any():
            break
        depth = distance[failing] + 0.002
        lift_d2 = ((out[:, None, :] - ears[failing][None, :, :]) ** 2).sum(-1)
        nearest = np.argmin(lift_d2, axis=1)
        reach = np.sqrt(lift_d2[np.arange(len(out)), nearest])
        lift = depth[nearest] * (1.0 - smoothstep(0.004, 0.009, reach))
        _, lift_outward, _ = polar(out)
        out = out + lift_outward * (lift * (reach < 0.009))[:, None]
    return out


def teacher_crop(points: np.ndarray, skin: tuple, triangles: np.ndarray) -> np.ndarray:
    """The main shell: pinned cut edge, skull-following volume, strand ridges."""
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
    return surface_guard(ear_drape(clamped, skin, triangles), skin, target_hem)


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


def teacher_highlight(points: np.ndarray, skin: tuple, triangles: np.ndarray) -> np.ndarray:
    """The lighter strands: the same fit, held above the cut and 2 mm off the surface.

    They are separate cards lying on the shell. Cropping the shell alone would leave them
    where the helmet used to be, floating beside the head -- which is exactly what showed
    through the nape in the previous revision. Every island here is card-sized (this sheet
    has no curtain of its own), so each vertex is placed by the same rule the curtain uses,
    then carried the way the dark sheet's cards are.
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
    return surface_guard(ear_drape(clamped, skin, triangles), skin, target_hem)
