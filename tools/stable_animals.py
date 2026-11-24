"""Sculpted horses and hens for the stable yard behind 01 (docs/EXAM_DREAM_ART.md).

Round 18 (2026-11-11) replaces the cut-paper horses and the box hens. The owner found
the horses flat as paper and the hens like toy bricks, and asked for them to read as
real animals. Each body is now *sculpted* as a signed distance field: overlapping
ellipsoids and tapered limbs blended with a smooth minimum, so the shoulder runs into
the neck and the thigh into the barrel the way muscle does. A naive surface-nets pass
turns the field into one closed mesh with normals from the field's gradient. The legs,
the head and the hen's comb are separate passes at a finer grid, because they need a
smaller step than the barrel. Hair (mane, forelock, tail) is a few dozen tapered locks.

Everything stays pure Python and deterministic, like the rest of the generators: no
engine, no third-party package, and `build_teaching_block.py --check` rebuilds it.

The colour is painted per vertex from anatomy (points, socks, blaze, dapples, a hen's
hackles and wing bars) and darkened by an ambient-occlusion estimate read from the same
field. Vertex alpha keeps the motion weights of `stable_meshes.py` (0.5 still, toward 1
the graze or peck about `neck_pivot`, toward 0 the tail swish), read by
`assets/shaders/school/stable_coat.gdshader`.
"""
from __future__ import annotations

import math

from stable_meshes import STILL, PaintMesh, catmull, ellipsoid, mix, rgb, sweep
from site_mesh import fbm, noise, rand, smoothstep

FAR = 1.0

# --- signed distance primitives ---------------------------------------------------------


class Ell:
    """An ellipsoid, optionally pitched about X: its local +Z is (0, sin a, cos a)."""

    def __init__(self, c, r, pitch=0.0, k=0.06):
        self.c, self.r, self.k = c, r, k
        a = math.radians(pitch)
        self.sa, self.ca = math.sin(a), math.cos(a)
        reach = max(r) + k
        self.lo = tuple(v - reach for v in c)
        self.hi = tuple(v + reach for v in c)

    def d(self, x, y, z):
        dx, dy, dz = x - self.c[0], y - self.c[1], z - self.c[2]
        ly = dy * self.ca - dz * self.sa
        lz = dy * self.sa + dz * self.ca
        rx, ry, rz = self.r
        k0 = math.sqrt((dx / rx) ** 2 + (ly / ry) ** 2 + (lz / rz) ** 2)
        k1 = math.sqrt((dx / (rx * rx)) ** 2 + (ly / (ry * ry)) ** 2 + (lz / (rz * rz)) ** 2)
        if k1 < 1e-12:
            return -min(self.r)
        return k0 * (k0 - 1.0) / k1


class Cone:
    """A round cone: a sphere of radius ra at a swept to one of rb at b."""

    def __init__(self, a, b, ra, rb, k=0.04):
        self.a, self.b, self.ra, self.rb, self.k = a, b, ra, rb, k
        self.ba = tuple(q - p for p, q in zip(a, b))
        self.l2 = sum(v * v for v in self.ba)
        self.rr = ra - rb
        self.a2 = self.l2 - self.rr * self.rr
        self.il2 = 1.0 / self.l2
        reach = max(ra, rb) + k
        self.lo = tuple(min(p, q) - reach for p, q in zip(a, b))
        self.hi = tuple(max(p, q) + reach for p, q in zip(a, b))

    def d(self, x, y, z):
        bx, by, bz = self.ba
        px, py, pz = x - self.a[0], y - self.a[1], z - self.a[2]
        yy = px * bx + py * by + pz * bz
        zz = yy - self.l2
        qx, qy, qz = px * self.l2 - bx * yy, py * self.l2 - by * yy, pz * self.l2 - bz * yy
        x2 = qx * qx + qy * qy + qz * qz
        y2 = yy * yy * self.l2
        z2 = zz * zz * self.l2
        rr, a2, il2 = self.rr, self.a2, self.il2
        k = math.copysign(1.0, rr) * rr * rr * x2
        if math.copysign(1.0, zz) * a2 * z2 > k:
            return math.sqrt(x2 + z2) * il2 - self.rb
        if math.copysign(1.0, yy) * a2 * y2 < k:
            return math.sqrt(x2 + y2) * il2 - self.ra
        return (math.sqrt(x2 * a2 * il2) + yy * rr) * il2 - self.ra


class Field:
    """Primitives blended by a polynomial smooth minimum; `floor` cuts everything at y."""

    def __init__(self, prims, floor=None):
        self.prims = prims
        self.floor = floor

    def __call__(self, x, y, z):
        d = FAR
        for p in self.prims:
            lo, hi = p.lo, p.hi
            if lo[0] < x < hi[0] and lo[1] < y < hi[1] and lo[2] < z < hi[2]:
                e = p.d(x, y, z)
                k = p.k
                h = k - abs(d - e)
                d = min(d, e) - (h * h * .25 / k if h > 0 else 0.0)
        if self.floor is not None:
            d = max(d, self.floor - y)
        return d

    def bounds(self, pad):
        lo = [min(p.lo[i] for p in self.prims) - pad for i in range(3)]
        hi = [max(p.hi[i] for p in self.prims) + pad for i in range(3)]
        if self.floor is not None:
            lo[1] = max(lo[1], self.floor - pad)
        return lo, hi

    def gradient(self, p, e):
        x, y, z = p
        g = (self(x + e, y, z) - self(x - e, y, z), self(x, y + e, z) - self(x, y - e, z),
             self(x, y, z + e) - self(x, y, z - e))
        n = math.sqrt(g[0] ** 2 + g[1] ** 2 + g[2] ** 2)
        return (0.0, 1.0, 0.0) if n < 1e-12 else (g[0] / n, g[1] / n, g[2] / n)

    def occlusion(self, p, n, step):
        """1 open, toward 0 in a crease: how far the field falls short of the normal probe."""
        short = 0.0
        for i, w in ((1, .5), (2, .3), (3, .2)):
            t = step * i
            short += w * max(0.0, t - self((p[0] + n[0] * t), (p[1] + n[1] * t), (p[2] + n[2] * t))) / t
        return max(0.0, 1.0 - short * 1.3)


def surface(field, step, colour, *, ao_step=None):
    """Naive surface nets over `field` at `step`; colour(point, normal, ao) -> RGBA."""
    (x0, y0, z0), (x1, y1, z1) = field.bounds(step * 1.5)
    nx, ny, nz = (int(math.ceil((b - a) / step)) + 1 for a, b in ((x0, x1), (y0, y1), (z0, z1)))
    vals = [0.0] * (nx * ny * nz)

    def at(i, j, k):
        return vals[(i * ny + j) * nz + k]

    for i in range(nx):
        x = x0 + i * step
        for j in range(ny):
            y = y0 + j * step
            base = (i * ny + j) * nz
            for k in range(nz):
                vals[base + k] = field(x, y, z0 + k * step)
    corners = [(a, b, c) for a in (0, 1) for b in (0, 1) for c in (0, 1)]
    edges = [(p, q) for p in range(8) for q in range(p + 1, 8)
             if sum(abs(u - v) for u, v in zip(corners[p], corners[q])) == 1]
    cell = {}
    mesh = PaintMesh()
    ao_step = ao_step or step * 1.6
    for i in range(nx - 1):
        for j in range(ny - 1):
            for k in range(nz - 1):
                v = [at(i + a, j + b, k + c) for a, b, c in corners]
                inside = [s < 0 for s in v]
                if all(inside) or not any(inside):
                    continue
                sx = sy = sz = 0.0
                count = 0
                for p, q in edges:
                    if inside[p] != inside[q]:
                        t = v[p] / (v[p] - v[q])
                        cp, cq = corners[p], corners[q]
                        sx += cp[0] + (cq[0] - cp[0]) * t
                        sy += cp[1] + (cq[1] - cp[1]) * t
                        sz += cp[2] + (cq[2] - cp[2]) * t
                        count += 1
                pt = (x0 + (i + sx / count) * step, y0 + (j + sy / count) * step, z0 + (k + sz / count) * step)
                n = field.gradient(pt, step * .5)
                ao = field.occlusion(pt, n, ao_step)
                cell[(i, j, k)] = mesh._vertex(pt, n, colour(pt, n, ao))
    # One quad round every grid edge the surface crosses, facing from inside to outside.
    for i in range(nx):
        for j in range(ny):
            for k in range(nz):
                f0 = at(i, j, k) < 0
                for axis in range(3):
                    di, dj, dk = ((1, 0, 0), (0, 1, 0), (0, 0, 1))[axis]
                    if i + di >= nx or j + dj >= ny or k + dk >= nz:
                        continue
                    if (at(i + di, j + dj, k + dk) < 0) == f0:
                        continue
                    if axis == 0:
                        ring = ((i, j - 1, k - 1), (i, j, k - 1), (i, j, k), (i, j - 1, k))
                    elif axis == 1:
                        ring = ((i - 1, j, k - 1), (i, j, k - 1), (i, j, k), (i - 1, j, k))
                    else:
                        ring = ((i - 1, j - 1, k), (i, j - 1, k), (i, j, k), (i - 1, j, k))
                    if any(c not in cell for c in ring):
                        continue
                    q = [cell[c] for c in ring]
                    out = [0.0, 0.0, 0.0]
                    out[axis] = 1.0 if f0 else -1.0
                    _quad(mesh, q, out)
    return mesh


def _quad(mesh, q, out):
    P = mesh.points
    # Split along the shorter diagonal, then wind each triangle to face `out`.
    d02 = sum((a - b) ** 2 for a, b in zip(P[q[0]], P[q[2]]))
    d13 = sum((a - b) ** 2 for a, b in zip(P[q[1]], P[q[3]]))
    tris = ((q[0], q[1], q[2]), (q[0], q[2], q[3])) if d02 <= d13 else ((q[0], q[1], q[3]), (q[1], q[2], q[3]))
    for a, b, c in tris:
        pa, pb, pc = P[a], P[b], P[c]
        u = (pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2])
        v = (pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2])
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        if n[0] * out[0] + n[1] * out[1] + n[2] * out[2] < 0:
            b, c = c, b
        mesh.indices.extend((a, b, c))


def surface_point(field, start, direction, reach):
    """Bisect from `start` (inside) along `direction` to the surface."""
    lo, hi = 0.0, reach
    for _ in range(30):
        mid = (lo + hi) / 2
        p = tuple(s + d * mid for s, d in zip(start, direction))
        if field(*p) < 0:
            lo = mid
        else:
            hi = mid
    return tuple(s + d * lo for s, d in zip(start, direction))


def lock(path, r0, r1, colour, weight, sides=5, flat=1.0):
    """One tapered lock of hair along a Catmull-Rom path; weight(point) -> motion alpha."""
    n = len(path)
    radii = [((r0 + (r1 - r0) * i / (n - 1)) * flat, r0 + (r1 - r0) * i / (n - 1)) for i in range(n)]
    m = sweep(path, radii, sides=sides, per=2)
    m.colors = [rgb(colour, weight(p)) for p in m.points]
    return m


# --- the horse ------------------------------------------------------------------------
# Frame: +Z forward, +Y up, origin on the ground between the hooves (as stable_meshes).

NECK_PIVOT = (0.0, 1.30, 0.50)
TAIL_PIVOT = (0.0, 1.36, -0.93)
HEAD_SHIFT = (0.0, 0.05, 0.07)
POLL = (0.0, 2.04, 1.03)

# Round 22: a lighter, redder bay so the horse reads in its north stall at dusk.
BAY = {"name": "bay", "coat": (160, 94, 54), "dark": (118, 66, 38), "points": (30, 24, 22),
       "hair": (26, 21, 20), "hair_hi": (58, 44, 38), "muzzle": (64, 44, 36), "hoof": (52, 46, 42),
       "white": (232, 226, 214)}
GREY = {"name": "grey", "coat": (172, 170, 165), "dark": (120, 118, 116), "points": (88, 84, 84),
        "hair": (210, 206, 198), "hair_hi": (150, 146, 142), "muzzle": (74, 70, 72), "hoof": (70, 66, 64),
        "white": (228, 226, 220)}
EYE = (18, 13, 12)
NOSTRIL = (30, 22, 20)


def _neck_weight(p):
    ax, ay, az = NECK_PIVOT
    bx, by, bz = POLL
    vx, vy, vz = bx - ax, by - ay, bz - az
    t = ((p[0] - ax) * vx + (p[1] - ay) * vy + (p[2] - az) * vz) / (vx * vx + vy * vy + vz * vz)
    return smoothstep(0.05, 0.95, t) * smoothstep(0.40, 0.56, p[2])


def _tail_weight(p):
    drop = max(0.0, min(1.0, (TAIL_PIVOT[1] - p[1] + .04) / 0.8))
    return STILL - 0.5 * smoothstep(0.0, 1.0, drop)


def _horse_body():
    prims = [
        Ell((0, 1.19, -.12), (.25, .315, .60), k=.1),
        Ell((0, 1.18, .34), (.225, .33, .32), k=.12),
        Ell((0, 1.05, .55), (.15, .2, .16), k=.1),
        Ell((0, 1.23, -.64), (.245, .31, .34), k=.12),
        Ell((0, 1.38, -.66), (.18, .14, .32), k=.1),
        Ell((0, 1.16, -.86), (.2, .24, .15), k=.1),
        Ell((0, 1.40, -.14), (.17, .12, .52), k=.14),
        Ell((0, 1.47, .30), (.105, .12, .22), pitch=20, k=.1),
        Ell((0, .99, -.15), (.21, .14, .42), k=.15),
    ]
    for s in (-1, 1):
        prims += [
            Ell((s * .13, 1.20, .40), (.09, .26, .16), pitch=-62, k=.08),
            Cone((s * .145, 1.02, .45), (s * .15, .57, .505), .095, .062, k=.07),
            Ell((s * .14, 1.06, -.68), (.11, .28, .22), pitch=-80, k=.08),
            Cone((s * .15, .95, -.66), (s * .15, .58, -.775), .11, .062, k=.07),
        ]
    # The neck: deep and narrow, a chain of ellipsoids along its own line, and the crest.
    neck = ((0, 1.31, .50), (0, 1.54, .67), (0, 1.76, .85), (0, 1.92, .97))
    sizes = ((.15, .29), (.125, .235), (.105, .19), (.092, .155))
    for (c, (w, h)), nxt in zip(zip(neck, sizes), neck[1:] + ((0, 2.02, 1.06),)):
        a = math.degrees(math.atan2(nxt[1] - c[1], nxt[2] - c[2]))
        prims.append(Ell(c, (w, h, .17), pitch=a, k=.1))
    prims.append(Ell((0, 1.73, .69), (.075, .08, .32), pitch=52, k=.08))
    return Field(prims)


def _horse_head():
    a = -40
    prims = [
        Ell((0, 1.83, .88), (.09, .15, .17), pitch=55, k=.08),  # the top of the neck
        Ell((0, 1.95, 1.01), (.092, .10, .12), pitch=a, k=.06),
        Ell((0, 1.855, 1.035), (.088, .13, .12), pitch=a, k=.06),
        Ell((0, 1.77, 1.21), (.074, .088, .23), pitch=a, k=.07),
        Ell((0, 1.69, 1.31), (.07, .085, .12), pitch=a, k=.06),
        Ell((0, 1.63, 1.39), (.07, .082, .085), pitch=a, k=.06),
        Ell((0, 1.575, 1.36), (.048, .038, .06), pitch=a, k=.03),
    ]
    for s in (-1, 1):
        prims += [
            Ell((s * .045, 1.865, 1.045), (.05, .088, .08), pitch=a, k=.04),
            Ell((s * .038, 1.63, 1.44), (.03, .034, .034), k=.02),
            Ell((s * .072, 1.935, 1.085), (.028, .028, .04), pitch=a, k=.03),
            Cone((s * .05, 2.02, .965), (s * .082, 2.19, .945), .032, .006, k=.03),
        ]
    return Field([_shifted(p) for p in prims])


def _shifted(p):
    dx, dy, dz = HEAD_SHIFT
    if isinstance(p, Ell):
        q = Ell((p.c[0] + dx, p.c[1] + dy, p.c[2] + dz), p.r, k=p.k)
        q.sa, q.ca = p.sa, p.ca
        return q
    return Cone((p.a[0] + dx, p.a[1] + dy, p.a[2] + dz), (p.b[0] + dx, p.b[1] + dy, p.b[2] + dz), p.ra, p.rb, k=p.k)


def _sh(p):
    return (p[0] + HEAD_SHIFT[0], p[1] + HEAD_SHIFT[1], p[2] + HEAD_SHIFT[2])


def _horse_leg(s, fore):
    x = s * .15
    if fore:
        top, joint, z = (x, .70, .512), (x, .55, .528), (.535, .545, .55, .585, .60)
        prims = [Cone(top, joint, .06, .055, k=.04), Ell(joint, (.054, .066, .06), k=.03),
                 Cone((x, .50, .505), (x, .21, .52), .028, .028, k=.02)]
    else:
        top, joint, z = (x, .73, -.745), (x, .56, -.77), (-.765, -.735, -.735, -.70, -.685)
        prims = [Cone(top, joint, .066, .055, k=.04), Ell(joint, (.05, .07, .075), k=.03),
                 Ell((x, .60, -.835), (.034, .04, .04), k=.03),
                 Cone((x, .50, -.80), (x, .21, -.765), .028, .028, k=.02)]
    prims += [
        Cone((x, .53, z[0]), (x, .20, z[1]), .045, .04, k=.03),
        Ell((x, .17, z[2]), (.048, .05, .055), k=.03),
        Cone((x, .16, z[2] + .005), (x, .07, z[3]), .038, .042, k=.02),
        Cone((x, .075, z[3]), (x, .012, z[4]), .048, .062, k=.015),
    ]
    return Field(prims, floor=0.0)


def _horse_colour(look, region, side=0, fore=True):
    coat, dark, points = look["coat"], look["dark"], look["points"]
    grey = look["name"] == "grey"
    seed = 3 if grey else 1

    def paint(p, n, ao):
        x, y, z = p
        c = coat
        # A soft countershade: the belly and the inside of the legs a little darker.
        c = mix(c, dark, smoothstep(1.0, .78, y) * .55 * (1 - abs(n[0]) * .5))
        c = mix(c, dark, max(0.0, -n[1]) * .25)
        if grey:
            # Dapples: pale rounds with darker rims over the barrel and quarters.
            cell = noise(x * 13 + 5.1, z * 13 + y * 9, 11) + .4 * noise(x * 29, y * 27 + z * 23, 12)
            ring = smoothstep(.18, .32, cell) - smoothstep(.32, .5, cell)
            body = smoothstep(.8, 1.1, y) * smoothstep(1.2, .6, z)
            c = mix(c, (214, 212, 206), smoothstep(.3, .55, cell) * body * .8)
            c = mix(c, dark, ring * body * .35)
            # Greys darken toward the head, the knees and the hocks.
            c = mix(c, look["points"], smoothstep(1.27, 1.57, z) * .6)
        else:
            c = mix(c, dark, smoothstep(.1, .5, fbm(x * 4 + seed, z * 4 + y * 3, seed, 3)) * .25)
        if region == "head":
            c = mix(c, look["muzzle"], smoothstep(1.37, 1.49, z))
            if not grey and abs(x) < .022 + .03 * smoothstep(1.37, 1.07, z) and 1.07 < z < 1.43 and n[1] > -.2:
                c = look["white"]  # a stripe down the face
            if p[1] > 2.09:
                c = mix(c, points, .85)  # dark ear rims
        if region == "leg":
            k = smoothstep(.62 if fore else .64, .46, y)
            c = mix(c, points, k * (1.0 if not grey else .7))
            if not grey and not fore and side > 0 and y < .22:
                c = look["white"]  # one white sock, hind right
            if y < .085:
                c = look["hoof"]
        if region == "body":
            k = smoothstep(.62, .46, y)
            c = mix(c, points, k)
        c = tuple(v * (.5 + .5 * ao) for v in c)
        w = STILL
        if region == "head":
            w = 1.0 if p[2] > 1.02 or p[1] > 2.03 else STILL + .5 * _neck_weight(p)
        elif region == "body":
            w = STILL + .5 * _neck_weight(p)
        return rgb(c, w)
    return paint


def horse(look):
    """(trunk, limbs): a sculpted body and head, then finer legs with the mane and tail.

    Two meshes of about 5.8k and 6.2k vertices, each under the release's per-file warning
    line; both take the same material, so the head and tail move as one animal.
    """
    m = PaintMesh()
    body = _horse_body()
    m.add(surface(body, .04, _horse_colour(look, "body")))
    head = _horse_head()
    m.add(surface(head, .026, _horse_colour(look, "head")))
    limbs = PaintMesh()
    for s in (-1, 1):
        for fore in (True, False):
            limbs.add(surface(_horse_leg(s, fore), .022, _horse_colour(look, "leg", s, fore)))
    # Eyes and nostrils sit in the head's own surface.
    for s in (-1, 1):
        eye = surface_point(head, _sh((s * .02, 1.905, 1.095)), (s, .05, .25), .2)
        m.add(ellipsoid((eye[0] - s * .006, eye[1], eye[2]), (.014, .019, .025), 6, 10), rgb(EYE, 1.0))
        nose = surface_point(head, _sh((s * .03, 1.625, 1.38)), (s * .35, 0, 1), .2)
        m.add(ellipsoid((nose[0], nose[1], nose[2] - .004), (.011, .017, .012), 5, 8), rgb(NOSTRIL, 1.0))
    _mane(limbs, look, body, head)
    _tail(limbs, look)
    return m, limbs


def _mane(m, look, body, head):
    hair, hi = look["hair"], look["hair_hi"]
    crest = catmull([(0, 1.56, .40), (0, 1.71, .56), (0, 1.86, .74), (0, 2.0, .92), (0, 2.08, 1.01)], 6)
    for i, c in enumerate(crest):
        # Root just under the crest's surface, then fall to the off side under gravity.
        root = surface_point(body if c[2] < .86 else head, (0, c[1] - .12, c[2]), (0, 1, 0), .3)
        root = (0.0, root[1] - .012, root[2])
        length = .15 + .1 * rand(i, 41) + .05 * math.sin(i * 1.7)
        lean = .55 + .35 * rand(i, 42)
        drop = (.02 + length * lean * .45, -length * .35, -.01)
        mid = (root[0] + drop[0], root[1] + drop[1], root[2] - .015)
        tip = (root[0] + .03 + length * lean * .32, root[1] - length, root[2] - .03 - .02 * rand(i, 43))
        col = mix(hair, hi, rand(i, 44) * .6)
        m.add(lock([root, mid, tip], .02, .004, col, lambda p: STILL + .5 * _neck_weight(p), flat=.55))
        if i % 2 == 0:
            # A thinner lock on the near side keeps the crest from looking combed flat.
            tip2 = (-.04 - length * .2, root[1] - length * .55, root[2] - .02)
            m.add(lock([root, (-.03, root[1] - .03, root[2] - .01), tip2], .014, .003, mix(col, hi, .2),
                       lambda p: STILL + .5 * _neck_weight(p), flat=.55))
    # The forelock between the ears.
    for i, dx in enumerate((-.03, -.012, .008, .026)):
        root = _sh((dx, 2.035, .975))
        tip = _sh((dx * 1.3, 1.90 - .02 * (i % 2), 1.07))
        m.add(lock([root, _sh((dx, 2.0, 1.02)), tip], .012, .003, mix(hair, hi, .25 * (i % 2)), lambda p: 1.0))


def _tail(m, look):
    hair, hi = look["hair"], look["hair_hi"]
    dock = [(0, 1.38, -.93), (0, 1.32, -1.0), (0, 1.22, -1.05), (0, 1.10, -1.07)]
    d = sweep(dock, (.05, .046, .04, .03), sides=12, per=3)
    d.colors = [rgb(hair, _tail_weight(p)) for p in d.points]
    m.add(d)
    for i in range(24):
        t = rand(i, 51)
        a = rand(i, 52) * math.tau
        start = catmull(dock, 4)[int(t * 12)]
        sx, sz = math.cos(a) * .03, math.sin(a) * .02
        root = (start[0] + sx, start[1], start[2] + sz - .01)
        length = .55 + .25 * rand(i, 53) - .25 * t
        spread = .05 + .06 * rand(i, 54)
        path = [root]
        for k in range(1, 5):
            f = k / 4
            path.append((root[0] + math.cos(a) * spread * f + .015 * math.sin(f * 5 + i),
                         root[1] - length * f,
                         root[2] - .06 * math.sin(f * 2.2) - spread * .4 * f))
        col = mix(hair, hi, rand(i, 55) * .5)
        m.add(lock(path, .016, .003, col, _tail_weight, flat=.7))


# --- the hen --------------------------------------------------------------------------
# Frame: +Z forward, +Y up, origin on the ground between the feet; about 0.42 m to the comb.

HEN_PIVOT = (0.0, 0.29, 0.07)
HEN_HEAD = (0.0, 0.435, 0.13)
WHITE_HEN = {"name": "white", "body": (238, 234, 222), "shade": (196, 192, 184), "hackle": (244, 240, 228),
             "tail": (226, 224, 216), "bar": (206, 204, 196), "leg": (222, 182, 82)}
BROWN_HEN = {"name": "brown", "body": (150, 82, 40), "shade": (108, 56, 30), "hackle": (196, 128, 58),
             "tail": (48, 34, 28), "bar": (88, 52, 32), "leg": (214, 170, 78)}
COMB = (188, 38, 40)
BEAK = (220, 176, 96)


def _peck_weight(p):
    ax, ay, az = HEN_PIVOT
    bx, by, bz = HEN_HEAD
    vx, vy, vz = bx - ax, by - ay, bz - az
    t = ((p[0] - ax) * vx + (p[1] - ay) * vy + (p[2] - az) * vz) / (vx * vx + vy * vy + vz * vz)
    return STILL + .5 * smoothstep(.0, .75, t) * smoothstep(.02, .07, p[2])


def _hen_body():
    prims = [
        Ell((0, .24, -.01), (.088, .085, .135), pitch=-14, k=.05),
        Ell((0, .235, .07), (.075, .082, .075), k=.05),
        Ell((0, .295, -.085), (.065, .05, .085), pitch=-28, k=.05),
        
        Ell((0, .205, -.11), (.065, .06, .065), k=.05),
        Ell((0, .362, .10), (.034, .034, .08), pitch=66, k=.04),
        Ell((0, .31, .075), (.05, .055, .05), k=.04),
        Ell((0, .435, .127), (.028, .03, .038), k=.025),
    ]
    for s in (-1, 1):
        prims += [
            
            Ell((s * .076, .25, -.035), (.02, .058, .112), pitch=-12, k=.02),
            Ell((s * .036, .178, .005), (.03, .04, .04), k=.03),
        ]
    for i, (dx, pitch, length_) in enumerate(((-.028, 106, .05), (-.014, 116, .058), (0, 122, .062),
                                             (.014, 116, .058), (.028, 106, .05))):
        prims.append(Ell((dx, .325, -.15), (.011, .026, length_), pitch=pitch, k=.012))
    return Field(prims)


HEN_UP, HEN_FWD = .025, .007


def _hen_comb():
    u, f = HEN_UP, HEN_FWD
    prims = [Ell((0, .436 + u, .118 + f), (.006, .012, .034), k=.006)]
    for i, (z, h) in enumerate(((.09, .012), (.104, .02), (.118, .024), (.132, .02), (.145, .013))):
        prims.append(Cone((0, .436 + u, z + f), (0, .444 + u + h, z + f - .004), .008, .0035, k=.006))
    for s in (-1, 1):
        prims.append(Ell((s * .008, .382 + u, .148 + f), (.007, .014, .009), k=.006))  # wattles
        prims.append(Ell((s * .027, .405 + u, .098 + f), (.004, .008, .007), k=.004))  # ear lobes
    return Field(prims)


def _hen_colour(look):
    white = look["name"] == "white"

    def paint(p, n, ao):
        x, y, z = p
        c = look["body"]
        # Feathers: a soft scale pattern laid back along the body.
        scale = .5 + .5 * math.sin((z * 120 + noise(x * 40, y * 40, 5) * 2.2)) * math.sin(y * 110 + x * 60)
        c = mix(c, look["shade"], scale * .18)
        if y > .3 and z > .02:
            c = mix(c, look["hackle"], smoothstep(.3, .36, y))  # neck hackles
            if not white:
                streak = smoothstep(.4, .9, noise(x * 90, y * 30 + z * 60, 7))
                c = mix(c, look["shade"], streak * .5)
        if abs(x) > .07 and -.12 < z < .06 and .18 < y < .3:
            # The wing: a darker bar across the coverts, primaries at the back edge.
            c = mix(c, look["bar"], smoothstep(.22, .24, y) - smoothstep(.25, .27, y))
            c = mix(c, look["bar"], smoothstep(-.06, -.1, z) * .7)
        if z < -.12 and y > .3:
            c = mix(c, look["tail"], .85 if not white else .4)  # tail feathers
        c = mix(c, look["shade"], max(0.0, -n[1]) * .35)
        c = tuple(v * (.55 + .45 * ao) for v in c)
        return rgb(c, _peck_weight(p))
    return paint


def hen(look):
    """About 4k vertices: a sculpted body, comb and wattles, beak, eyes, scaly legs."""
    m = PaintMesh()
    body = _hen_body()
    m.add(surface(body, .012, _hen_colour(look), ao_step=.014))
    m.add(surface(_hen_comb(), .004, lambda p, n, ao: rgb(tuple(v * (.6 + .4 * ao) for v in COMB), 1.0)))
    u, f = HEN_UP, HEN_FWD
    beak = sweep([(0, .412 + u, .142 + f), (0, .407 + u, .162 + f), (0, .397 + u, .178 + f)], ((.011, .008), (.007, .006), (.0015, .0015)),
                 sides=8, per=2)
    beak.colors = [rgb(BEAK, 1.0) for _ in beak.points]
    m.add(beak)
    for s in (-1, 1):
        eye = surface_point(body, (0, .418 + u, .128 + f), (s, 0, .2), .08)
        m.add(ellipsoid((eye[0] - s * .002, eye[1], eye[2]), (.006, .007, .007), 5, 8), rgb((176, 96, 30), 1.0))
        m.add(ellipsoid((eye[0] + s * .0015, eye[1], eye[2] + .001), (.0035, .004, .004), 4, 6),
              rgb((14, 10, 8), 1.0))
        # Shank, then three toes forward and one back, scaled and a touch paler underneath.
        hip, ankle = (s * .042, .125, .0), (s * .044, .026, .018)
        legs = PaintMesh()
        legs.add(sweep([hip, (s * .043, .075, .012), ankle], (.009, .007, .0065), sides=8, per=2))
        for yaw, length_ in ((-28, .05), (0, .058), (28, .05), (180, .026)):
            a = math.radians(yaw + s * 6)
            tip = (ankle[0] + math.sin(a) * length_, .004, ankle[2] + math.cos(a) * length_)
            mid = (ankle[0] + math.sin(a) * length_ * .5, .01, ankle[2] + math.cos(a) * length_ * .5)
            legs.add(sweep([ankle, mid, tip], (.0065, .005, .0025), sides=6, per=2))
        legs.colors = [rgb(mix(look["leg"], (150, 120, 70), smoothstep(.06, .0, p[1]) * .3)) for p in legs.points]
        m.add(legs)
    return m
