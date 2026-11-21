"""Meshes for the building under construction and its plot (round 9 art pass).

Everything is generated as text ArrayMeshes (site_mesh.py), so the site rebuilds
without the engine. Each function returns `site_mesh.Mesh` objects in metres; the
placement is construction_site.py's. Vertex colours are multipliers over the painted
site textures: wet sand at the toe, mud on the hoarding's foot, rust under bolts.
"""

from __future__ import annotations

import math

from site_mesh import (
    WHITE, Mesh, add, box, cross, cylinder, euler, extrude, fbm, lerp, matmul, mul, noise, norm, rand,
    ring_points, rock, rot_x, rot_y, rot_z, smoothstep, sub, tube,
)


def _shade(c, k):
    return (c[0] * k, c[1] * k, c[2] * k)


# --- sand -----------------------------------------------------------------------------

# Height over the pile's footprint, s = 0 at the centre and 1 at the foot of the slope;
# the toe runs out past 1 and dips just under the ground so no edge is left showing.
_CRATER = ((0.0, 0.80), (0.08, 0.815), (0.15, 0.905), (0.21, 0.985), (0.27, 0.975), (0.38, 0.865),
           (0.55, 0.635), (0.72, 0.405), (0.86, 0.215), (0.96, 0.105), (1.06, 0.042), (1.16, 0.012),
           (1.26, -0.025))
_DOME = ((0.0, 1.0), (0.1, 0.988), (0.2, 0.952), (0.32, 0.868), (0.55, 0.635), (0.72, 0.405),
         (0.86, 0.215), (0.96, 0.105), (1.06, 0.042), (1.16, 0.012), (1.26, -0.025))
SAND_WET = (0.62, 0.575, 0.53)
SAND_CUT = (0.76, 0.72, 0.67)


def _curve(points, s):
    s = max(points[0][0], min(points[-1][0], s))
    for i in range(len(points) - 1):
        (s0, h0), (s1, h1) = points[i], points[i + 1]
        if s <= s1:
            # Cubic Hermite with Catmull-Rom tangents.
            prev = points[max(0, i - 1)]
            nxt = points[min(len(points) - 1, i + 2)]
            m0 = (h1 - prev[1]) / (s1 - prev[0]) * (s1 - s0)
            m1 = (nxt[1] - h0) / (nxt[0] - s0) * (s1 - s0)
            t = (s - s0) / (s1 - s0)
            t2, t3 = t * t, t * t * t
            return (2 * t3 - 3 * t2 + 1) * h0 + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * h1 + (t3 - t2) * m1
    return points[-1][1]


def sand_pile(rx, rz, height, seed, *, crater=True, bite=None, rills=19, pebbles=22,
              base=(1.0, 1.0, 1.0), rings=28, segments=84):
    """A dumped heap: a rounded crest, near-straight flanks at the angle of repose,
    erosion rills, an optional excavator bite and a run-out that buries its own edge.

    Returns (sand mesh, water mesh or None, surface height function).
    `bite` = (bearing in degrees, depth 0..1): a scoop taken out of one flank.
    """
    profile = _CRATER if crater else _DOME
    s_values = [0.015 + (1.26 - 0.015) * (i / (rings - 1)) ** 0.92 for i in range(rings)]
    bite_center = None
    if bite is not None:
        bearing, depth = math.radians(bite[0]), bite[1]
        reach = 0.78
        bite_center = (math.cos(bearing) * rx * reach, height * (0.95 - 0.25 * depth),
                       math.sin(bearing) * rz * reach)
        bite_radius = 0.58 * min(rx, rz) * (0.8 + 0.4 * depth)

    def footprint(theta):
        return 1.0 + 0.085 * noise(math.cos(theta) * 1.6 + seed, math.sin(theta) * 1.6, seed) \
            + 0.04 * math.sin(3 * theta + seed * 1.7)

    def surface(theta, s):
        f = footprint(theta)
        x, z = math.cos(theta) * s * rx * f, math.sin(theta) * s * rz * f
        y = height * _curve(profile, s)
        flank = smoothstep(0.2, 0.36, s) * (1 - smoothstep(0.98, 1.2, s))
        y += height * 0.032 * flank * fbm(x * 2.3 + seed, z * 2.3, seed, 4)
        y += height * 0.010 * flank * noise(x * 9.0, z * 9.0 + seed, seed + 5)
        groove = abs(math.sin(theta * rills / 2 + 0.7 * noise(s * 3.0, theta * 2.0, seed + 9)))
        rill = math.exp(-(groove / 0.11) ** 2) * smoothstep(0.32, 0.5, s) * (1 - smoothstep(0.9, 1.05, s))
        y -= height * 0.035 * rill
        cut = 0.0
        if bite_center is not None:
            dx, dz = x - bite_center[0], z - bite_center[2]
            d2 = dx * dx + dz * dz
            if d2 < bite_radius ** 2:
                floor = bite_center[1] - math.sqrt(bite_radius ** 2 - d2)
                if y > floor:
                    cut = min(1.0, (y - floor) / 0.06)
                    y = max(floor, 0.02 * height)
        return (x, y, z), rill, cut

    rows, colors = [], []
    for s in s_values:
        row, crow = [], []
        for k in range(segments):
            theta = k * math.tau / segments
            p, rill, cut = surface(theta, s)
            wet = smoothstep(0.84, 1.14, s)
            c = lerp(WHITE, SAND_WET, wet)
            if crater and s < 0.24:
                c = lerp(c, SAND_WET, 1 - smoothstep(0.12, 0.24, s))
            c = _shade(c, 1 - 0.1 * rill)
            if cut > 0:
                c = lerp(c, SAND_CUT, cut)
            c = _shade(c, 1 + 0.045 * noise(p[0] * 4.0, p[2] * 4.0, seed + 13))
            row.append(p)
            crow.append((c[0] * base[0], c[1] * base[1], c[2] * base[2]))
        rows.append(row)
        colors.append(crow)
    sand = Mesh()
    sand.grid(rows, wrap=True, centers=[(0, -2.0 * height, 0)] * len(rows), colors=colors)
    sand.polygon(rows[0], (0, 1, 0), colors[0][0])

    # Clods and gravel caught on the run-out.
    for i in range(pebbles):
        theta = rand(i, seed) * math.tau
        s = 1.0 + 0.2 * rand(i, seed + 1)
        p, _, _ = surface(theta, s)
        r = 0.025 + 0.04 * rand(i, seed + 2)
        tone = 0.46 + 0.22 * rand(i, seed + 3)
        sand.merge(rock(r, seed + i, squash=0.55, detail=0, color=(tone, tone * 0.96, tone * 0.9)),
                   rot_y(rand(i, seed + 4) * 360), (p[0], p[1] + r * 0.2, p[2]))

    water = None
    if crater:
        level = height * 0.845
        pts = []
        for k in range(36):
            theta = k * math.tau / 36
            # The pool fills the crater up to its level; trace where the bowl meets it.
            lo, hi = 0.015, 0.21
            for _ in range(18):
                mid = (lo + hi) / 2
                if surface(theta, mid)[0][1] < level:
                    lo = mid
                else:
                    hi = mid
            f = footprint(theta)
            pts.append((math.cos(theta) * hi * rx * f, level, math.sin(theta) * hi * rz * f))
        water = Mesh().polygon(pts, (0, 1, 0))

    def height_at(x, z):
        theta = math.atan2(z / rz, x / rx)
        f = footprint(theta)
        s = math.hypot(x / (rx * f), z / (rz * f))
        return surface(theta, s)[0][1] if s < 1.26 else 0.0

    return sand, water, height_at


def shovel():
    """A round-mouth shovel: ash shaft, D-grip, socket and a dished blade."""
    steel, wood = Mesh(), Mesh()
    wood.merge(tube([(0, 0.12, 0), (0, 1.02, 0)], 0.018, 10))
    wood.merge(tube([(-0.065, 1.07, 0), (-0.06, 1.15, 0), (0.06, 1.15, 0), (0.065, 1.07, 0)], 0.011, 8))
    steel.merge(tube([(0, 1.0, 0), (0, 1.07, 0)], 0.02, 10))
    steel.merge(cylinder(0.022, 0.16, 10, top=0.019, center=(0, 0.08, 0)))
    rows = []
    for j in range(6):
        v = j / 5
        y = -0.2 * v
        half = 0.11 * math.sin(math.pi * (0.25 + 0.75 * (1 - v) ** 0.6)) if j < 5 else 0.0
        row = []
        for i in range(9):
            u = -1 + 2 * i / 8
            row.append((u * max(half, 0.004), y, 0.022 * (1 - u * u) - 0.012))
        rows.append(row)
    steel.grid(rows, outward=(0, 0, 1))
    steel.grid([[(x, y, z - 0.004) for x, y, z in row] for row in rows], outward=(0, 0, -1))
    return wood, steel


def wheelbarrow():
    """A builder's barrow: pressed tub, tube frame, a pneumatic wheel and two legs."""
    tub, frame, tyre = Mesh(), Mesh(), Mesh()
    rows = []
    for j, (y, sx, sz) in enumerate(((0.32, 0.22, 0.17), (0.40, 0.33, 0.25), (0.52, 0.42, 0.31),
                                     (0.6, 0.47, 0.34))):
        ring = []
        for i in range(28):
            a = i * math.tau / 28
            c, s = math.cos(a), math.sin(a)
            squ = (abs(c) ** 3 + abs(s) ** 3) ** (-1 / 3)
            ring.append((c * squ * sx + (0.06 if c > 0 else 0.0) * c * (y - 0.32) * 2, y, s * squ * sz))
        rows.append(ring)
    tub.grid(rows, wrap=True, centers=[(0, -1, 0)] * 4)
    tub.grid([[(x * 0.97, y + 0.006, z * 0.97) for x, y, z in r] for r in rows], wrap=True,
             centers=[(0, -1, 0)] * 4, inward=True)
    tub.polygon(rows[0], (0, -1, 0))
    tub.merge(tube(rows[-1] + [rows[-1][0]], 0.012, 6, caps=False))
    for side in (-1, 1):
        frame.merge(tube([(0.62, 0.28, side * 0.06), (0.32, 0.3, side * 0.2), (-0.35, 0.36, side * 0.24),
                          (-0.8, 0.5, side * 0.27)], 0.016, 8))
        frame.merge(tube([(-0.25, 0.33, side * 0.23), (-0.3, 0.0, side * 0.25)], 0.014, 8))
        frame.merge(tube([(-0.36, 0.0, side * 0.25), (-0.22, 0.0, side * 0.25)], 0.014, 8))
        frame.merge(tube([(0.62, 0.18, side * 0.06), (0.62, 0.3, side * 0.06)], 0.012, 6))
        tyre.merge(tube([(-0.8, 0.5, side * 0.27), (-0.95, 0.56, side * 0.28)], 0.02, 8))
    tyre.merge(tube([add((0.62, 0.18, 0), (0.17 * math.cos(a), 0.17 * math.sin(a), 0))
                     for a in (i * math.tau / 24 for i in range(24))], 0.045, 8, closed=True))
    frame.merge(cylinder(0.06, 0.09, 10, axis="z", center=(0.62, 0.18, 0)))
    return tub, frame, tyre


# --- hoarding -------------------------------------------------------------------------

PANEL_W, PANEL_H = 1.85, 2.2


def hoarding_panel(variant):
    """One trapezoidal-profile steel sheet, x across, y up, +z the outer face.

    Smooth normals soften the ribs the way real sheet reads at distance; dents, a
    slight bow and mud splashed up from the ground differ by `variant`.
    """
    pitch, depth = PANEL_W / 15, 0.032
    xs, zs = [], []
    for k in range(15):
        for f, z in ((0.0, 1), (0.3, 1), (0.5, -1), (0.8, -1)):
            xs.append(-PANEL_W / 2 + (k + f) * pitch)
            zs.append(z * depth / 2)
    xs.append(PANEL_W / 2)
    zs.append(depth / 2)
    ys = [0.02 + (PANEL_H - 0.04) * j / 13 for j in range(14)]
    dents = [(-0.5 + rand(i, variant) , 0.35 + 1.5 * rand(i, variant + 9), 0.1 + 0.18 * rand(i, variant + 3),
              -(0.012 + 0.03 * rand(i, variant + 5))) for i in range(2 + variant)]
    rows, colors = [], []
    for y in ys:
        row, crow = [], []
        for x, z in zip(xs, zs):
            dz = 0.012 * math.sin(math.pi * y / PANEL_H) * (1 if variant % 2 else -1)
            for dx_, dy_, r, d in dents:
                dist2 = (x - dx_ * PANEL_W * 0.8) ** 2 + (y - dy_) ** 2
                dz += d * math.exp(-dist2 / (r * r))
            row.append((x, y, z + dz))
            mud = 1 - smoothstep(0.0, 0.55, y + 0.12 * noise(x * 3.0, variant, variant))
            c = lerp(WHITE, (0.56, 0.5, 0.43), mud * 0.85)
            # Rust run from the top rail's bolts, fading downward.
            for bx in (-0.62, 0.0, 0.62):
                streak = math.exp(-((x - bx - 0.05 * variant) / 0.035) ** 2) * smoothstep(0.6, PANEL_H, y)
                c = lerp(c, (0.82, 0.62, 0.48), streak * 0.65)
            c = _shade(c, 0.97 + 0.06 * noise(x * 1.3 + variant * 3, y * 0.8, variant + 2))
            crow.append(c)
        rows.append(row)
        colors.append(crow)
    m = Mesh()
    m.grid(rows, outward=(0, 0, 1), colors=colors)
    return m


def hoarding_frame(runs, ground):
    """Posts, base plates, ballast blocks, rails and the inside braces of every run.

    `runs` is [(start (x, z), end (x, z), outward (x, z)), ...]. Returns meshes by
    material: (steel, concrete, fittings).
    """
    steel, concrete, fittings = Mesh(), Mesh(), Mesh()
    for start, end, outward in runs:
        span = math.dist(start, end)
        bays = max(1, round(span / PANEL_W))
        dx, dz = (end[0] - start[0]) / span, (end[1] - start[1]) / span
        yaw = math.degrees(math.atan2(-dz, dx))
        turn = rot_y(yaw)
        ox, oz = outward
        inward = (-ox, -oz)
        for i in range(bays + 1):
            t = i / bays
            px, pz = start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t
            px_post, pz_post = px + inward[0] * 0.06, pz + inward[1] * 0.06
            steel.merge(box((0.07, PANEL_H + 0.12, 0.07)), turn,
                        (px_post, ground + (PANEL_H + 0.12) / 2, pz_post))
            steel.merge(box((0.2, 0.012, 0.2)), turn, (px_post, ground + 0.006 + 0.17, pz_post))
            concrete.merge(box((0.64, 0.17, 0.26)), turn, (px_post, ground + 0.085, pz_post))
            for h in (0.12, PANEL_H - 0.14):
                fittings.merge(box((0.09, 0.07, 0.05)), turn,
                               (px + inward[0] * 0.02, ground + h, pz + inward[1] * 0.02))
            if i % 2 == 1 and i < bays:
                foot = (px_post + inward[0] * 1.15, ground + 0.06, pz_post + inward[1] * 1.15)
                steel.merge(tube([(px_post + inward[0] * 0.04, ground + 1.55, pz_post + inward[1] * 0.04),
                                  (foot[0], ground + 0.2, foot[2])], 0.022, 8))
                concrete.merge(box((0.5, 0.15, 0.3)), turn, (foot[0], ground + 0.075, foot[2]))
        # Top and mid rails on the inside face; a pale capping channel over the sheet.
        for h, size in ((PANEL_H - 0.1, 0.05), (1.05, 0.045), (0.25, 0.045)):
            a = (start[0] + inward[0] * 0.065, ground + h, start[1] + inward[1] * 0.065)
            b = (end[0] + inward[0] * 0.065, ground + h, end[1] + inward[1] * 0.065)
            mid = mul(add(a, b), 0.5)
            steel.merge(box((span, size, size * 0.8), bevel=0.004), turn, mid)
    return steel, concrete, fittings


def apply_yaw(turn, v):
    return tuple(turn[i][0] * v[0] + turn[i][1] * v[1] + turn[i][2] * v[2] for i in range(3))


def hoarding_cap(span):
    return box((span, 0.05, 0.1), bevel=0.01)


def hazard_board(width, height):
    """A yellow board with black chevrons, two meshes: (yellow, black)."""
    yellow = box((0.02, height, width), bevel=0.004)
    black = Mesh()
    stripes = int(width / 0.16)
    for i in range(-2, stripes + 2):
        z0 = -width / 2 + i * 0.16
        quad = [(0.0115, -height / 2 + 0.02, z0), (0.0115, -height / 2 + 0.02, z0 + 0.075),
                (0.0115, height / 2 - 0.02, z0 + 0.075 + height * 0.6),
                (0.0115, height / 2 - 0.02, z0 + height * 0.6)]
        clipped = [(x, y, max(-width / 2 + 0.02, min(width / 2 - 0.02, z))) for x, y, z in quad]
        if abs(clipped[0][2] - clipped[1][2]) < 1e-4 and abs(clipped[2][2] - clipped[3][2]) < 1e-4:
            continue
        try:
            black.polygon(clipped, (1, 0, 0))
        except ValueError:
            continue
    return yellow, black


# --- gate, chain, padlock ---------------------------------------------------------------


def gate_leaf(width, height=2.05):
    """A welded leaf in the plane x = 0, hinged at z = 0 and spanning +z.

    Returns (frame, infill): 48 mm frame and brace, 25 mm palisade bars, a kick plate.
    """
    frame, infill = Mesh(), Mesh()
    r = 0.024
    lo, hi = 0.12, 0.12 + height
    z0, z1 = 0.05, width - 0.02
    corner = 0.06
    path = []
    for (cz, cy), start in (((z1 - corner, hi - corner), 0), ((z0 + corner, hi - corner), 90),
                            ((z0 + corner, lo + corner), 180), ((z1 - corner, lo + corner), 270)):
        for k in range(4):
            a = math.radians(start + 90 * k / 3)
            path.append((0.0, cy + math.sin(a) * corner, cz + math.cos(a) * corner))
    frame.merge(tube(path, r, 10, closed=True))
    mid_y = lo + height * 0.46
    frame.merge(tube([(0, mid_y, z0), (0, mid_y, z1)], r * 0.85, 10))
    frame.merge(tube([(0, lo + 0.05, z0 + 0.05), (0, mid_y - 0.04, z1 - 0.05)], r * 0.7, 8))
    bars = max(6, int((z1 - z0) / 0.115))
    for i in range(1, bars):
        z = z0 + (z1 - z0) * i / bars
        infill.merge(tube([(0, lo + 0.02, z), (0, hi + 0.09, z)], 0.0125, 8))
        infill.merge(cylinder(0.0125, 0.05, 8, top=0.002, center=(0, hi + 0.115, z)))
    infill.merge(box((0.006, 0.3, z1 - z0 - 0.02), center=(0.012, lo + 0.17, (z0 + z1) / 2)))
    for h in (lo + 0.25, hi - 0.25):
        frame.merge(cylinder(0.034, 0.2, 12, center=(0, h, -0.02)))
        frame.merge(box((0.03, 0.05, 0.08), center=(0, h, 0.02)))
    # Drop bolt on the free stile and its keeper.
    frame.merge(tube([(0.04, lo - 0.1, z1 - 0.06), (0.04, lo + 0.45, z1 - 0.06)], 0.01, 8))
    frame.merge(tube([(0.04, lo + 0.42, z1 - 0.06), (0.1, lo + 0.42, z1 - 0.06)], 0.009, 6))
    for h in (lo + 0.05, lo + 0.35):
        frame.merge(box((0.05, 0.03, 0.04), center=(0.025, h, z1 - 0.06)))
    return frame, infill


def chain(points, link=0.034, wire=0.0058):
    """Oval links along `points`, alternating 90 degrees, as one mesh."""
    m = Mesh()
    total = sum(math.dist(a, b) for a, b in zip(points, points[1:]))
    count = max(2, int(total / (link * 0.78)))
    straight, radius = link * 0.42, link * 0.3
    oval = []
    for k in range(14):
        a = k * math.tau / 14
        c, s = math.cos(a), math.sin(a)
        oval.append((c * radius + (straight / 2 if c > 0 else -straight / 2), s * radius, 0.0))
    template = tube(oval, wire, 6, closed=True)
    for i in range(count):
        d = (i + 0.5) / count * total
        for a, b in zip(points, points[1:]):
            seg = math.dist(a, b)
            if d <= seg:
                p = lerp(a, b, d / seg)
                t = norm(sub(b, a))
                break
            d -= seg
        yaw = math.degrees(math.atan2(-t[2], t[0]))
        pitch = math.degrees(math.asin(max(-1, min(1, t[1]))))
        rot = euler((0, yaw, pitch))
        if i % 2:
            rot = matmul(rot, rot_x(90))
        m.merge(template, rot, p)
    return m


def padlock():
    """A laminated padlock seen face-on along +x: (body, shackle, keyway)."""
    body = Mesh()
    layers = 7
    for i in range(layers):
        y = -0.05 + i * (0.1 / layers)
        body.merge(box((0.036, 0.1 / layers - 0.002, 0.084), bevel=0.004), offset=(0, y + 0.05 / layers, 0))
    body.merge(box((0.03, 0.006, 0.07), bevel=0.002), offset=(0, 0.052, 0))
    shackle = tube(
        [(0, 0.05, -0.024), (0, 0.095, -0.024)]
        + [(0, 0.095 + 0.024 * math.sin(a), -0.024 * math.cos(a)) for a in
           (math.pi * k / 8 for k in range(1, 8))]
        + [(0, 0.095, 0.024), (0, 0.056, 0.024)], 0.0065, 8)
    key = box((0.004, 0.022, 0.006), center=(0.0185, -0.024, 0))
    key.merge(cylinder(0.006, 0.004, 10, axis="x", center=(0.0185, -0.012, 0)))
    return body, shackle, key


# --- the excavator ------------------------------------------------------------------------

def _grime(low=0.0, high=0.9, mud=(0.62, 0.53, 0.43)):
    def fn(p, n, c):
        k = 1 - smoothstep(low, high, p[1] + 0.12 * noise(p[0] * 2.0, p[2] * 2.0, 3))
        return lerp(c, (c[0] * mud[0], c[1] * mud[1], c[2] * mud[2]), k)
    return fn


def track_unit(side):
    """One crawler: 46 shoes round a sprocket and idler, frame, rollers and drive.

    Local frame of the machine: x forward, y up, z = side * gauge/2. Returns
    (steel, dark) meshes.
    """
    steel, dark = Mesh(), Mesh()
    zc = side * 0.92
    rear, front, cy, rad = -1.12, 1.12, 0.35, 0.35
    straight = front - rear
    perimeter = 2 * straight + math.tau * rad
    shoes = 40
    shoe = box((0.15, 0.026, 0.4))
    shoe.merge(box((0.028, 0.026, 0.4)), offset=(0.035, 0.025, 0))
    for i in range(shoes):
        d = (i + 0.3) / shoes * perimeter
        if d < straight:  # bottom run, going forward
            p, ang = (rear + d, cy - rad, zc), 180.0
        elif d < straight + math.pi * rad:
            a = (d - straight) / rad
            p = (front + rad * math.sin(a), cy - rad * math.cos(a), zc)
            ang = 180.0 + math.degrees(a)
        elif d < 2 * straight + math.pi * rad:
            p, ang = (front - (d - straight - math.pi * rad), cy + rad, zc), 0.0
        else:
            a = (d - 2 * straight - math.pi * rad) / rad
            p = (rear - rad * math.sin(a), cy + rad * math.cos(a), zc)
            ang = math.degrees(a)
        # Shoe template: outward +y. ang turns it round the z axis.
        steel.merge(shoe, rot_z(ang), p)
    # Track frame: a box girder with sloped ends between the wheels.
    outline = [(-0.95, 0.22), (0.95, 0.22), (1.06, 0.36), (0.95, 0.5), (-0.95, 0.5), (-1.06, 0.36)]
    dark.merge(extrude(outline, 0.26, center=zc))
    for i, x in enumerate((-0.66, -0.22, 0.22, 0.66)):
        dark.merge(cylinder(0.075, 0.24, 14, axis="z", center=(x, 0.1, zc), bevel=0.01))
    dark.merge(cylinder(0.055, 0.16, 12, axis="z", center=(0.0, 0.63, zc), bevel=0.008))
    # Idler: a flanged wheel; sprocket: eleven teeth and the drive motor outboard.
    dark.merge(cylinder(0.29, 0.2, 28, axis="z", center=(front, cy, zc), bevel=0.02))
    dark.merge(cylinder(0.12, 0.26, 16, axis="z", center=(front, cy, zc)))
    teeth = []
    for k in range(22):
        a = k * math.tau / 22
        r = 0.31 if k % 2 == 0 else 0.25
        teeth.append((rear + r * math.cos(a), cy + r * math.sin(a)))
    dark.merge(extrude(teeth, 0.08, center=zc))
    dark.merge(cylinder(0.2, 0.17, 20, axis="z", center=(rear, cy, zc + side * 0.17), bevel=0.02))
    for k in range(8):
        a = k * math.tau / 8
        steel.merge(cylinder(0.016, 0.02, 6, axis="z",
                             center=(rear + 0.14 * math.cos(a), cy + 0.14 * math.sin(a), zc + side * 0.26)))
    return steel, dark


def excavator_meshes():
    """A 6-tonne excavator, boom over the hoarding into the south heap.

    Returns {material: Mesh} in the machine's frame (x forward, y up).
    """
    yellow, steel, dark, chrome, glass, rubber, lamp = (Mesh() for _ in range(7))

    for side in (-1, 1):
        s, d = track_unit(side)
        steel.merge(s)
        dark.merge(d)
    dark.merge(box((1.5, 0.34, 1.3), bevel=0.05, center=(0, 0.52, 0)))
    dark.merge(cylinder(0.68, 0.14, 40, center=(-0.08, 0.76, 0), bevel=0.015))
    for k in range(24):
        a = k * math.tau / 24
        chrome.merge(cylinder(0.018, 0.02, 6, center=(-0.08 + 0.6 * math.cos(a), 0.84, 0.6 * math.sin(a))))

    # Dozer blade on the front of the undercarriage: a curved mouldboard and its arms.
    blade_rows = []
    for j in range(9):
        t = j / 8
        a = math.radians(-60 + 120 * t)
        blade_rows.append([(1.55 + 0.25 * (1 - math.cos(a)) * 0.6, 0.06 + 0.36 * t, z)
                           for z in (-1.05, -0.35, 0.35, 1.05)])
    blade_rows_t = [list(col) for col in zip(*blade_rows)]
    yellow.grid(blade_rows_t, outward=(1, 0, 0))
    yellow.grid([[(x - 0.02, y, z) for x, y, z in row] for row in blade_rows_t], outward=(-1, 0, 0))
    yellow.merge(box((0.05, 0.38, 0.03), center=(1.6, 0.25, -1.05)))
    yellow.merge(box((0.05, 0.38, 0.03), center=(1.6, 0.25, 1.05)))
    steel.merge(box((0.05, 0.04, 2.12), bevel=0.006, center=(1.53, 0.05, 0)))
    for z in (-0.45, 0.45):
        yellow.merge(tube([(1.5, 0.3, z), (0.72, 0.5, z)], (0.07, 0.05), 6,
                          section=[(1, 1), (-1, 1), (-1, -1), (1, -1)]))
    chrome.merge(tube([(1.42, 0.42, 0), (0.95, 0.62, 0)], 0.028, 10))
    dark.merge(tube([(0.95, 0.62, 0), (0.62, 0.72, 0)], 0.05, 10))

    # Upper structure: deck, curved counterweight, engine hood, tank box.
    pivot_x = -0.08
    deck = [(pivot_x + 1.12 * math.cos(math.radians(a)), 1.12 * math.sin(math.radians(a)))
            for a in range(100, 261, 10)]
    deck += [(1.05, -1.02), (1.15, -0.85), (1.15, 0.85), (1.05, 1.02)]
    yellow.merge(extrude([(x, z) for x, z in deck], 0.12, axis="y", center=0.91))
    profile = [(0.74, 0.97), (1.14, 0.97), (1.19, 1.04), (1.19, 1.44), (1.14, 1.56), (1.02, 1.62), (0.74, 1.62)]
    cw_rows = []
    angles = [math.radians(98 + (262 - 98) * i / 30) for i in range(31)]
    for a in angles:
        cw_rows.append([(pivot_x + r * math.cos(a), y, r * math.sin(a)) for r, y in profile])
    centers = [(pivot_x + 0.96 * math.cos(a), 1.3, 0.96 * math.sin(a)) for a in angles]
    cw = Mesh()
    cw.grid(cw_rows, wrap=True, centers=centers)
    cw.polygon(cw_rows[0], (math.sin(angles[0]), 0, -math.cos(angles[0])))
    cw.polygon(cw_rows[-1], (-math.sin(angles[-1]), 0, math.cos(angles[-1])))
    yellow.merge(cw)
    # Engine hood: rounded top lofted across the machine's right rear.
    hood_rows = []
    for x in (-0.82, -0.8, 0.15, 0.17):
        inset = 0.02 if abs(x) in (0.82, 0.17) else 0.0
        sec = []
        for k in range(12):
            a = math.pi * k / 11
            sec.append((x, 1.0 + (0.62 - inset) * (0.75 + 0.25 * math.sin(a)) if 0 < k < 11 else 0.98,
                        -1.0 + inset + (0.92 - 2 * inset) * (1 - math.cos(a)) / 2))
        hood_rows.append(sec)
    hood = Mesh().grid(hood_rows, centers=[(x, 1.2, -0.55) for x in (-0.82, -0.8, 0.15, 0.17)])
    hood.polygon(hood_rows[0], (-1, 0, 0))
    hood.polygon(hood_rows[-1], (1, 0, 0))
    yellow.merge(hood)
    for k in range(7):
        dark.merge(box((0.5, 0.018, 0.01), center=(-0.32, 1.18 + k * 0.045, -1.004)))
    dark.merge(box((0.56, 0.36, 0.006), center=(-0.32, 1.31, -0.998)))
    yellow.merge(box((0.68, 0.5, 0.42), bevel=0.04, center=(0.62, 1.22, -0.78)))
    dark.merge(box((0.26, 0.05, 0.12), bevel=0.01, center=(0.62, 1.49, -0.78)))
    steel.merge(tube([(-0.38, 1.6, -0.7), (-0.38, 2.12, -0.7), (-0.42, 2.18, -0.7)], 0.045, 10))
    steel.merge(cylinder(0.05, 0.02, 10, center=(-0.44, 2.19, -0.7)))
    for z in (-0.2, -0.95):
        steel.merge(tube([(-0.7, 1.62, z), (-0.68, 1.82, z), (0.05, 1.82, z), (0.07, 1.62, z)], 0.014, 6))

    # The cab: pillars, roof, glazing, door, step, mirror, lamps and a beacon.
    cx0, cx1, cz0, cz1, cy0, cy1 = -0.38, 0.78, 0.04, 1.0, 0.97, 2.56
    for x, z in ((cx0, cz0), (cx0, cz1), (cx1, cz0), (cx1, cz1)):
        lean = -0.06 if x == cx1 else 0.0
        yellow.merge(tube([(x, cy0, z), (x + lean, cy1 - 0.06, z)], (0.035, 0.035), 4,
                          section=[(1, 1), (-1, 1), (-1, -1), (1, -1)]))
    yellow.merge(box((cx1 - cx0 + 0.16, 0.1, cz1 - cz0 + 0.12), bevel=0.03,
                     center=((cx0 + cx1) / 2 - 0.02, cy1, (cz0 + cz1) / 2)))
    yellow.merge(box((cx1 - cx0, 0.26, 0.04), bevel=0.01, center=((cx0 + cx1) / 2, cy0 + 0.13, cz1)))
    yellow.merge(box((0.04, 0.26, cz1 - cz0), bevel=0.01, center=(cx0, cy0 + 0.13, (cz0 + cz1) / 2)))
    glass.merge(box((cx1 - cx0 - 0.07, cy1 - cy0 - 0.44, 0.012), center=((cx0 + cx1) / 2, cy0 + 0.82, cz1 - 0.004)))
    glass.merge(box((0.012, cy1 - cy0 - 0.2, cz1 - cz0 - 0.07), center=(cx1 - 0.03, cy0 + 0.7, (cz0 + cz1) / 2)))
    glass.merge(box((0.012, cy1 - cy0 - 0.62, cz1 - cz0 - 0.07), center=(cx0 + 0.004, cy0 + 0.92, (cz0 + cz1) / 2)))
    glass.merge(box((cx1 - cx0 - 0.07, cy1 - cy0 - 0.44, 0.012), center=((cx0 + cx1) / 2, cy0 + 0.82, cz0 + 0.004)))
    yellow.merge(box((0.03, cy1 - cy0 - 0.4, 0.02), center=(0.24, cy0 + 0.8, cz1 + 0.006)))
    chrome.merge(box((0.12, 0.022, 0.024), bevel=0.004, center=(0.12, cy0 + 0.72, cz1 + 0.03)))
    dark.merge(box((0.012, 0.6, 0.01), center=(cx1 - 0.015, cy0 + 0.75, 0.62), ))
    steel.merge(box((0.44, 0.03, 0.22), bevel=0.006, center=(0.25, 0.86, cz1 + 0.1)))
    steel.merge(tube([(cx0 - 0.03, 1.2, cz1 + 0.04), (cx0 - 0.03, 2.25, cz1 + 0.04)], 0.014, 6))
    steel.merge(tube([(cx1 - 0.04, 2.3, cz1 + 0.02), (cx1 + 0.12, 2.4, cz1 + 0.16)], 0.01, 6))
    dark.merge(box((0.02, 0.16, 0.11), bevel=0.01, center=(cx1 + 0.13, 2.4, cz1 + 0.17)))
    for z in (0.18, 0.86):
        dark.merge(box((0.09, 0.08, 0.12), bevel=0.01, center=(cx1 + 0.04, cy1 + 0.02, z)))
        lamp.merge(box((0.006, 0.055, 0.09), center=(cx1 + 0.087, cy1 + 0.02, z)))
    lamp.merge(cylinder(0.05, 0.09, 12, center=(cx0 + 0.18, cy1 + 0.1, 0.8)))
    dark.merge(cylinder(0.055, 0.02, 12, center=(cx0 + 0.18, cy1 + 0.06, 0.8)))
    rubber.merge(box((0.42, 0.5, 0.42), bevel=0.06, center=(0.15, 1.28, 0.52)))

    # Boom: a banana box section from the swing post, over the hoarding.
    zb = -0.25
    foot, knee, tip = (0.95, 1.18, zb), (2.55, 3.5, zb), (3.95, 3.3, zb)
    spine = []
    for i in range(23):
        t = i / 22
        a = lerp(foot, knee, t)
        b = lerp(knee, tip, t)
        p = lerp(a, b, t)
        spine.append(p)
    heights = [0.2 + 0.07 * math.sin(math.pi * min(1, i / 15)) - 0.05 * max(0, i - 15) / 7 for i in range(23)]
    section = [(1, 0.72), (0.78, 1), (-0.78, 1), (-1, 0.72), (-1, -0.72), (-0.78, -1), (0.78, -1), (1, -0.72)]
    yellow.merge(tube(spine, [(0.16, h) for h in heights], 8, section=section))
    yellow.merge(box((0.5, 0.5, 0.42), bevel=0.05, center=(1.0, 1.1, zb)))
    for p, r in ((foot, 0.13), (tip, 0.12)):
        dark.merge(cylinder(r, 0.38, 18, axis="z", center=p, bevel=0.012))
        chrome.merge(cylinder(r * 0.45, 0.44, 12, axis="z", center=p))
    # Stick (dipper) and the bucket linkage.
    stick_dir = norm((0.34, -0.94, 0))
    stick_top = add(tip, mul(stick_dir, -0.42))
    pin = add(tip, mul(stick_dir, 1.98))
    stick_path = [lerp(stick_top, pin, i / 8) for i in range(9)]
    yellow.merge(tube(stick_path, [(0.12, 0.16 - 0.05 * i / 8) for i in range(9)], 8, section=section))
    dark.merge(cylinder(0.08, 0.3, 14, axis="z", center=pin, bevel=0.01))

    def ram(a, b, barrel=0.075, rod=0.038, split=0.58):
        mid = lerp(a, b, split)
        dark.merge(tube([a, mid], barrel, 12))
        chrome.merge(tube([lerp(a, b, split - 0.02), b], rod, 10))
        dark.merge(cylinder(barrel * 1.12, 0.06, 12, center=lerp(a, b, split - 0.01), axis="y"))
        for p in (a, b):
            dark.merge(cylinder(0.055, 0.15, 12, axis="z", center=p))

    ram((1.25, 1.0, zb), (2.18, 2.95, zb))
    ram(add(lerp(foot, knee, 0.78), (0.0, 0.3, 0)), add(stick_top, (0.0, 0.07, 0)), barrel=0.068, rod=0.034)
    link_top = add(pin, (0.23, 0.48, 0))
    ram(add(stick_top, (0.18, -0.05, 0)), link_top, barrel=0.06, rod=0.03, split=0.62)
    for z in (-0.09, 0.09):
        dark.merge(tube([link_top, add(pin, (0.2, 0.05, z))], (0.03, 0.012), 4,
                        section=[(1, 1), (-1, 1), (-1, -1), (1, -1)]))
        dark.merge(tube([link_top, add(pin, (0.02, 0.22, z))], (0.025, 0.012), 4,
                        section=[(1, 1), (-1, 1), (-1, -1), (1, -1)]))
    # Hoses ride the boom's back in two pairs.
    for dz in (-0.05, 0.05):
        hose = [add(add(p, mul(norm(cross((0, 0, 1), norm(sub(spine[min(i + 1, 22)], spine[max(i - 1, 0)])))),
                                    heights[i] + 0.04)), (0, 0, dz)) for i, p in enumerate(spine) if i % 2 == 0]
        hose = [(1.05, 1.42, zb + dz)] + hose[1:] + [add(stick_top, (0.1, 0.1, dz))]
        rubber.merge(tube(hose, 0.019, 6))

    # Bucket: curved back, side plates, lip and five teeth, with a load of sand.
    bucket, teeth, load = Mesh(), Mesh(), Mesh()
    outer = [(0.08, 0.06), (-0.12, 0.0), (-0.26, -0.16), (-0.3, -0.36), (-0.24, -0.55), (-0.08, -0.66),
             (0.14, -0.68), (0.36, -0.6)]
    w = 0.33
    rows = [[(x, y, z) for x, y in outer] for z in (-w, w)]
    bucket.grid(rows, centers=[(0.08, -0.3, -w), (0.08, -0.3, w)])
    inner = [(x + 0.02 * (1 if x < 0.1 else -0.3), y + 0.02, 0) for x, y in outer]
    bucket.grid([[(x, y, z) for x, y, _ in inner] for z in (-w + 0.012, w - 0.012)],
                centers=[(0.08, -0.3, -w), (0.08, -0.3, w)], inward=True)
    for z, sign in ((-w, -1), (w, 1)):
        plate = [(x, y, z) for x, y in outer] + [(0.36, -0.42, z), (0.1, 0.12, z)]
        bucket.polygon(plate, (0, 0, sign))
    bucket.merge(box((0.12, 0.03, 2 * w + 0.04), bevel=0.006, center=(0.38, -0.6, 0)), rot_z(-22))
    for i in range(5):
        z = -w + 0.06 + i * (2 * w - 0.12) / 4
        tooth = Mesh()
        tooth.grid([[(0.0, -0.02, z - 0.03), (0.0, 0.02, z - 0.03), (0.0, 0.02, z + 0.03), (0.0, -0.02, z + 0.03)],
                    [(0.14, -0.006, z - 0.012), (0.14, 0.006, z - 0.012), (0.14, 0.006, z + 0.012),
                     (0.14, -0.006, z + 0.012)]], wrap=True, centers=[(0, 0, z), (0.14, 0, z)], flat=True)
        teeth.merge(tooth, rot_z(-30), (0.43, -0.63, 0))
    for z in (-0.09, 0.09):
        bucket.merge(box((0.16, 0.12, 0.03), bevel=0.008, center=(0.04, 0.06, z)))
    load_rows = []
    for j in range(7):
        t = j / 6
        ring = []
        for k in range(16):
            a = k * math.tau / 16
            rr = 0.27 * math.sin(math.pi * 0.5 * (1 - t)) + 0.005
            ring.append((-0.04 + rr * math.cos(a) * 0.95, -0.36 + 0.24 * math.sin(math.pi * 0.5 * t)
                         + 0.02 * noise(a * 2, t * 3, 4), rr * math.sin(a) * 1.15))
        load_rows.append(ring)
    load.grid(load_rows, wrap=True, centers=[(-0.04, -0.6, 0)] * 7)

    bucket_rot = rot_z(-38)
    place = add(pin, (0.0, 0.0, 0.0))
    steel.merge(bucket, bucket_rot, place)
    chrome.merge(teeth, bucket_rot, place)

    yellow.recolor(_grime(0.6, 1.4, (0.7, 0.62, 0.52)))
    return {
        "site_yellow": yellow, "site_steel": steel, "metal_ink": dark, "exit_steel": chrome,
        "site_glass": glass, "tyre": rubber, "lane_light": lamp,
    }, (load, bucket_rot, place)


# --- the building ----------------------------------------------------------------------------


def tower_shell(radius_at, deck, joints, segments=96):
    """The cast ellipsoid: closed skin, shallow cold joints, pour-to-pour tone,
    rain streaks from the deck and splashback at the foot."""
    rings = {round(i * 0.3, 3): 0.0 for i in range(1, math.floor(deck / 0.3) + 1)}
    for y in joints:
        for p in list(rings):
            if abs(p - y) < 0.16:
                del rings[p]
        for offset, inset in ((-0.10, 0.016), (-0.036, 0.012), (-0.012, -0.05),
                              (0.037, -0.05), (0.075, 0.0), (0.14, 0.0)):
            rings[round(y + offset, 3)] = inset
    rings.update({-0.018: -0.05, 0.05: 0.0, deck - 0.09: 0.0, deck: -0.01})
    levels = sorted(rings.items())
    rows, colors, centers = [], [], []
    for y, inset in levels:
        rx, rz = radius_at(y)
        row, crow = [], []
        lift = sum(1 for j in joints if y > j)
        for k in range(segments):
            th = k * math.tau / segments
            bulge = 0.006 * math.sin(math.pi * ((y % 2.5) / 2.5)) + 0.004 * noise(th * 6, y * 2, 4)
            r_x, r_z = rx + inset + bulge, rz + inset + bulge
            row.append((r_x * math.cos(th), y, r_z * math.sin(th)))
            c = _shade(WHITE, (0.97, 1.03, 0.99, 1.01)[lift % 4])
            streak = max(0.0, noise(th * 9.0, 0.5, 21)) ** 2 * smoothstep(deck - 6, deck - 0.3, y)
            c = _shade(c, 1 - 0.22 * streak)
            splash = 1 - smoothstep(0.0, 0.9, y + 0.2 * noise(th * 5, 1, 2))
            c = lerp(c, (0.68, 0.6, 0.52), splash * 0.7)
            if inset < -0.02:
                c = _shade(c, 0.8)
            crow.append(c)
        rows.append(row)
        colors.append(crow)
        centers.append((0, y, 0))
    m = Mesh()
    m.grid(rows, wrap=True, centers=centers, colors=colors)
    m.polygon(rows[0], (0, -1, 0), colors[0][0])
    m.polygon(rows[-1], (0, 1, 0), (0.9, 0.88, 0.84))
    return m


def tie_holes(radius_at, deck, joints, skip):
    """Formwork tie holes: dark plugs on a grid between the cold joints."""
    m = Mesh()
    lifts = [0.0, *joints, deck]
    for a, b in zip(lifts, lifts[1:]):
        for row in (0.3, 0.7):
            y = a + (b - a) * row
            if y > deck - 0.4:
                continue
            rx, rz = radius_at(y)
            count = int(math.tau * (rx + rz) / 2 / 0.62)
            for k in range(count):
                th = (k + 0.5 * (row > 0.5)) * math.tau / count
                if skip(th, y):
                    continue
                p = (rx * math.cos(th), y, rz * math.sin(th))
                n = norm((math.cos(th) / rx, 0, math.sin(th) / rz))
                ring = []
                t1 = norm(cross(n, (0, 1, 0)))
                t2 = (0, 1, 0)
                for q in range(6):
                    ang = q * math.tau / 6
                    ring.append(add(add(p, mul(n, 0.004)), add(mul(t1, 0.022 * math.cos(ang)), mul(t2, 0.022 * math.sin(ang)))))
                m.polygon(ring, n)
    return m


def deck_edge(radius_at, deck):
    """Timber formwork band with studs, edge-protection posts and rails round the deck."""
    timber, steel, toe = Mesh(), Mesh(), Mesh()
    rx, rz = radius_at(deck)
    band = []
    for y in (deck - 0.32, deck + 0.18):
        band.append(ring_points(0, y, 0, rx + 0.04, rz + 0.04, 96))
    timber.grid(band, wrap=True, centers=[(0, deck - 0.32, 0), (0, deck + 0.18, 0)])
    inner = [ring_points(0, y, 0, rx - 0.04, rz - 0.04, 96) for y in (deck + 0.18, deck - 0.1)]
    timber.grid(inner, wrap=True, centers=[(0, deck + 0.18, 0), (0, deck - 0.1, 0)], inward=True)
    timber.grid([band[1], inner[0]], wrap=True, outward=(0, 1, 0))
    studs = 52
    for k in range(studs):
        th = k * math.tau / studs
        p = ((rx + 0.075) * math.cos(th), deck - 0.07, (rz + 0.075) * math.sin(th))
        timber.merge(box((0.05, 0.5, 0.075)), rot_y(-math.degrees(th)), p)
    posts = 26
    for k in range(posts):
        th = (k + 0.5) * math.tau / posts
        base = ((rx - 0.12) * math.cos(th), deck + 0.18, (rz - 0.12) * math.sin(th))
        steel.merge(tube([base, add(base, (0, 1.05, 0))], 0.022, 8))
    for h, r in ((0.55, 0.018), (1.05, 0.022)):
        path = ring_points(0, deck + 0.18 + h, 0, rx - 0.12, rz - 0.12, 72)
        steel.merge(tube(path, r, 8, closed=True))
    toe_rows = [ring_points(0, deck + 0.18 + y, 0, rx - 0.15, rz - 0.15, 72) for y in (0.0, 0.15)]
    toe.grid(toe_rows, wrap=True, centers=[(0, deck + 0.18, 0), (0, deck + 0.33, 0)])
    toe.grid([[(x * 0.995, y, z * 0.995) for x, y, z in r] for r in toe_rows], wrap=True,
             centers=[(0, deck + 0.18, 0), (0, deck + 0.33, 0)], inward=True)
    return timber, steel, toe


def starter_bars(radius_at, deck, count=40):
    """Vertical starter bars with bent tops, set back from the formwork."""
    m = Mesh()
    rx, rz = radius_at(deck)
    for k in range(count):
        th = (k + 0.35) * math.tau / count
        for j, setback in enumerate((0.28 + 0.14 * (k % 2),)):
            h = 0.7 + 0.25 * rand(k * 2 + j, 3)
            base = ((rx - setback) * math.cos(th), deck + 0.15, (rz - setback) * math.sin(th))
            inward = norm((-math.cos(th), 0, -math.sin(th)))
            top = add(base, (0, h, 0))
            hook = add(top, mul(inward, 0.12 + 0.05 * rand(k, 8)))
            m.merge(tube([base, top, add(top, mul(inward, 0.03)), hook], 0.011, 5))
    return m


def entrance(width=1.7, height=2.45, depth=1.75):
    """The temporary entrance porch on the shell's east side, its door facing +x.

    Local: the porch's front face is at x = 0, its back reaches into the shell (-x).
    Returns {material: Mesh} and the door hinge/latch extents.
    """
    ply, frame, door, glass, steel, lamp, sign, dark = (Mesh() for _ in range(8))
    hw = width / 2
    # Side walls and roof: plywood over studs; the back is buried in the concrete.
    for z in (-hw, hw):
        ply.merge(box((depth, height, 0.03), center=(-depth / 2, height / 2, z)))
        for x in (-depth + 0.2, -depth / 2, -0.04):
            frame.merge(box((0.06, height, 0.06), bevel=0.006, center=(x, height / 2, z - math.copysign(0.03, z))))
    ply.merge(box((depth + 0.12, 0.04, width + 0.14), center=(-depth / 2 + 0.06, height + 0.03, 0)), rot_z(-3))
    frame.merge(box((0.08, 0.12, width + 0.16), bevel=0.01, center=(0.02, height - 0.02, 0)))
    # Front: a steel frame round a single door with a wired-glass vision panel.
    door_w, door_h = 0.96, 2.08
    for z in (-door_w / 2 - 0.04, door_w / 2 + 0.04):
        frame.merge(box((0.1, door_h + 0.08, 0.07), bevel=0.008, center=(0.0, (door_h + 0.08) / 2, z)))
    frame.merge(box((0.1, 0.08, door_w + 0.16), bevel=0.008, center=(0.0, door_h + 0.04, 0)))
    for z in (-hw + (hw - door_w / 2 - 0.08) / 2, hw - (hw - door_w / 2 - 0.08) / 2):
        ply.merge(box((0.03, height - 0.05, hw - door_w / 2 - 0.08), center=(-0.01, (height - 0.05) / 2, z)))
    ply.merge(box((0.03, height - door_h - 0.08, door_w + 0.1), center=(-0.01, (height + door_h + 0.08) / 2, 0)))
    door.merge(box((0.05, door_h - 0.02, door_w - 0.02), bevel=0.006, center=(-0.03, door_h / 2, 0)))
    for y in (0.4, 1.2):
        door.merge(box((0.008, 0.012, door_w - 0.16), center=(0.0, y, 0)))
    glass.merge(box((0.01, 0.42, 0.22), center=(0.0, 1.5, 0.18)))
    steel.merge(box((0.012, 0.46, 0.26), center=(-0.004, 1.5, 0.18)))
    steel.merge(tube([(0.0, 1.0, -0.36), (0.07, 1.0, -0.36), (0.07, 1.0, 0.0), (0.0, 1.0, 0.0)], 0.012, 8))
    steel.merge(box((0.03, 0.18, 0.05), bevel=0.005, center=(0.0, 1.05, -0.4)))
    dark.merge(box((0.012, 0.03, 0.012), center=(0.007, 0.95, -0.4)))
    for y in (0.3, door_h - 0.3):
        steel.merge(cylinder(0.016, 0.12, 8, center=(-0.01, y, door_w / 2 - 0.02)))
    # A bulkhead lamp over the door and a blank site board beside it.
    dark.merge(box((0.08, 0.14, 0.22), bevel=0.02, center=(0.05, door_h + 0.22, 0)))
    lamp.merge(box((0.01, 0.09, 0.16), center=(0.092, door_h + 0.22, 0)))
    sign.merge(box((0.015, 0.55, 0.42), bevel=0.004, center=(0.02, 1.45, -hw + 0.32)))
    yellow, black = hazard_board(0.42, 0.1)
    return {
        "site_ply": ply, "site_steel": frame, "hoard_fold": door, "site_glass": glass,
        "exit_steel": steel, "lane_light": lamp, "pale": sign, "metal_ink": dark,
    }, (yellow, black)


def drain_pipe(radius_at, angle, heights, stand_off=0.2):
    pipe, clamp = Mesh(), Mesh()
    pts = []
    for y in [heights[0] + (heights[-1] - heights[0]) * i / 40 for i in range(41)]:
        rx, rz = radius_at(y)
        pts.append(((rx + stand_off) * math.cos(angle), y, (rz + stand_off) * math.sin(angle)))
    pipe.merge(tube(pts, 0.055, 10))
    for y in heights[1:-1]:
        rx, rz = radius_at(y)
        a = ((rx + stand_off) * math.cos(angle), y, (rz + stand_off) * math.sin(angle))
        b = ((rx - 0.05) * math.cos(angle), y, (rz - 0.05) * math.sin(angle))
        clamp.merge(tube([b, a], 0.02, 6))
        clamp.merge(cylinder(0.07, 0.07, 10, center=a))
    rx, rz = radius_at(heights[0])
    foot = ((rx + stand_off) * math.cos(angle), heights[0], (rz + stand_off) * math.sin(angle))
    pipe.merge(tube([foot, add(foot, (0.18 * math.cos(angle), -0.16, 0.18 * math.sin(angle)))], 0.055, 10))
    return pipe, clamp


# --- the plot ---------------------------------------------------------------------------------


def plot_ground(x_range, z_range, top, ruts, sand_spots, keep_flat):
    """The site's earth as a height field: track ruts with cleat marks, a few puddles,
    sand trodden round the heaps, and a skirt down the three outer edges."""
    (x0, x1), (z0, z1) = x_range, z_range
    step = 0.3
    nx, nz = int(round((x1 - x0) / step)) + 1, int(round((z1 - z0) / step)) + 1
    rows, colors = [], []
    puddles = []
    for j in range(nz):
        z = z0 + (z1 - z0) * j / (nz - 1)
        row, crow = [], []
        for i in range(nx):
            x = x0 + (x1 - x0) * i / (nx - 1)
            flat = keep_flat(x, z)
            y = top + 0.012 * fbm(x * 0.6, z * 0.6, 17, 3) - 0.006
            c = _shade(WHITE, 0.95 + 0.07 * fbm(x * 0.9 + 3, z * 0.9, 19, 3))
            for path, gauge in ruts:
                d, along = _distance_along(path, (x, z))
                for side in (-1, 1):
                    off = abs(d - side * gauge / 2)
                    if off < 0.32:
                        groove = math.exp(-(off / 0.17) ** 4)
                        cleat = 0.5 + 0.5 * math.cos(along / 0.15 * math.tau)
                        y -= groove * (0.035 + 0.01 * cleat)
                        y += 0.02 * math.exp(-((off - 0.27) / 0.05) ** 2)
                        c = lerp(c, (0.7, 0.62, 0.56), groove * 0.8)
            for sx, sz, sr in sand_spots:
                k = 1 - smoothstep(sr * 0.8, sr * 1.5, math.hypot(x - sx, z - sz))
                c = lerp(c, (1.08, 1.02, 0.9), k * 0.55)
            y = top + (y - top) * (1 - flat)
            row.append((x, y, z))
            crow.append(c)
        rows.append(row)
        colors.append(crow)
    m = Mesh()
    m.grid(rows, outward=(0, 1, 0), colors=colors)
    # Skirt on the west, north and south edges (the east edge meets the yard).
    for edge in (rows[0], rows[-1], [r[0] for r in rows]):
        lower = [(x, top - 0.5, z) for x, _, z in edge]
        mid = ((edge[0][0] + edge[-1][0]) / 2, top, (edge[0][2] + edge[-1][2]) / 2)
        inside = ((x0 + x1) / 2, top, (z0 + z1) / 2)
        m.grid([edge, lower], outward=norm(sub(mid, inside)), colors=[[(0.7, 0.62, 0.55)] * len(edge)] * 2)
    return m, puddles


def _distance_along(path, p):
    best, along, total = 1e9, 0.0, 0.0
    signed = 0.0
    for a, b in zip(path, path[1:]):
        ab = (b[0] - a[0], b[1] - a[1])
        seg = math.hypot(*ab)
        t = max(0.0, min(1.0, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / (seg * seg)))
        q = (a[0] + ab[0] * t, a[1] + ab[1] * t)
        d = math.dist(p, q)
        if d < best:
            best = d
            along = total + seg * t
            side = ab[0] * (p[1] - a[1]) - ab[1] * (p[0] - a[0])
            signed = d if side >= 0 else -d
        total += seg
    return signed, along


def puddle(center, rx, rz, seed, level):
    pts = []
    for k in range(20):
        a = k * math.tau / 20
        f = 1 + 0.25 * noise(math.cos(a) * 1.5 + seed, math.sin(a) * 1.5, seed)
        pts.append((center[0] + rx * f * math.cos(a), level, center[1] + rz * f * math.sin(a)))
    return Mesh().polygon(pts, (0, 1, 0))


def rebar_bundle(length=3.2, bars=14, seed=2):
    """Bars strapped on two timber bearers."""
    steel, timber = Mesh(), Mesh()
    for b in (-length * 0.3, length * 0.3):
        timber.merge(box((0.09, 0.08, 0.7), bevel=0.008, center=(b, 0.04, 0)))
    for i in range(bars):
        row, col = divmod(i, 5)
        z = -0.13 + col * 0.065 + (0.03 if row % 2 else 0)
        y = 0.1 + row * 0.055
        sag = 0.012 * rand(i, seed)
        steel.merge(tube([(-length / 2, y, z), (0, y - sag, z + 0.01 * rand(i, seed + 1)), (length / 2, y, z)],
                         0.013, 6))
    for b in (-length * 0.3, length * 0.3):
        steel.merge(tube([(b, 0.07, -0.2), (b, 0.3, -0.18), (b, 0.3, 0.18), (b, 0.07, 0.2)], 0.008, 5))
    return steel, timber


def block_pallet(seed=5):
    """A pallet of hollow concrete blocks, a few taken from the top course."""
    timber, blocks = Mesh(), Mesh()
    for z in (-0.45, 0.0, 0.45):
        timber.merge(box((1.2, 0.1, 0.1), bevel=0.006, center=(0, 0.05, z)))
    for x in range(7):
        timber.merge(box((0.12, 0.022, 1.0), center=(-0.55 + x * 0.183, 0.111, 0)))
    for layer in range(4):
        for i in range(3):
            for j in range(5):
                if layer == 3 and (i * 5 + j) % 4 == int(rand(j, seed) * 3):
                    continue
                c = 0.9 + 0.12 * rand(layer * 31 + i * 7 + j, seed)
                blocks.merge(box((0.39, 0.19, 0.19), color=(c, c, c)),
                             offset=(-0.4 + i * 0.4, 0.22 + 0.095 + layer * 0.195, -0.4 + j * 0.2))
    return timber, blocks


def floodlight(pole_h=4.3):
    pole, head, lens = Mesh(), Mesh(), Mesh()
    pole.merge(cylinder(0.055, pole_h, 12, top=0.045, center=(0, pole_h / 2, 0)))
    pole.merge(box((0.3, 0.1, 0.3), bevel=0.01, center=(0, 0.05, 0)))
    pole.merge(tube([(0, pole_h - 0.2, 0), (0.25, pole_h + 0.02, 0)], 0.03, 8))
    head.merge(box((0.12, 0.3, 0.42), bevel=0.025), rot_z(-28), (0.3, pole_h + 0.02, 0))
    for k in range(6):
        head.merge(box((0.03, 0.26, 0.012), center=(0.24, pole_h + 0.04, -0.15 + k * 0.06)), rot_z(0))
    lens.merge(box((0.012, 0.24, 0.34)), rot_z(-28), (0.358, pole_h - 0.01, 0))
    return pole, head, lens


def marble(radius=0.07, seed=0):
    rows = []
    for j in range(9):
        lat = -math.pi / 2 + math.pi * (j + 0.5) / 9
        rows.append(ring_points(0, radius * math.sin(lat), 0, radius * math.cos(lat), radius * math.cos(lat), 14))
    m = Mesh().grid(rows, wrap=True, centers=[(0, 0, 0)] * 9)
    m.polygon(rows[0], (0, -1, 0))
    m.polygon(rows[-1], (0, 1, 0))
    return m


__all__ = [name for name in dir() if not name.startswith("_")] + ["euler", "rot_x", "rot_y", "rot_z"]
