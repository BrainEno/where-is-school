"""Local head sculpts for the seven standing candidates on 03.

The skin is a joined skull with relief in its vertex positions, not a face decal
on a rounded box. Folded scalp edges, ears and recessed eye shapes are part of
one painted mesh under the existing Head pivot. Coordinates are in metres, +Z
forward; no new material, rig or runtime animation track is needed.
"""
from __future__ import annotations

from bisect import bisect_right
from dataclasses import dataclass
import math

from exam_crowd_forms import PigmentMesh, add, angles, cross, mix, scale, sub, tint, unit


@dataclass(frozen=True)
class HeadCut:
    jaw: float
    cheek: float
    length: float
    nose: tuple[float, float, float]  # width, bridge height, tip relief
    eyes: tuple[float, float, float]  # gap from centre, lid tilt, opening
    mouth: tuple[float, float]       # half-width and corner expression
    hair: tuple[float, float, float, float, float]  # front, temple, nape, crown, sweep
    lock: str = ""


HALL_HEADS = {
    # Round chin, oblique bangs, low side ponytail.
    "knit": HeadCut(.92, 1.02, .972, (.014, .095, .023), (.042, .003, .0065), (.021, .004),
                    (.169, .153, .091, .264, -.024), "tail"),
    # Wider square mandible and close tapered temples under a short textured top.
    "varsity": HeadCut(1.14, 1.05, 1.022, (.017, .096, .030), (.046, -.001, .005), (.030, -.002),
                       (.187, .164, .123, .252, .006), "crop"),
    # Straight bridge, long jaw, neat asymmetric side part and wire rims.
    "shirt": HeadCut(.97, .96, 1.045, (.012, .091, .036), (.043, .000, .0047), (.023, -.001),
                      (.188, .144, .101, .262, .019), "part"),
    # Fuller cheeks, short button nose, blunt bob with open air under the ends.
    "hoodie": HeadCut(.96, 1.11, .951, (.016, .101, .020), (.046, .002, .006), (.024, .001),
                       (.166, .051, .048, .257, -.016), "bob"),
    # Narrow chin and long nose; swept back above the ears into a compact knot.
    "coat": HeadCut(.90, .99, 1.055, (.013, .088, .033), (.042, .001, .0051), (.023, .002),
                     (.196, .158, .099, .259, -.010), "knot"),
    # Slightly crooked nose and mouth; high, uneven quiff, one clipped side.
    "windbreaker": HeadCut(1.07, 1.07, .996, (.018, .094, .032), (.043, -.004, .004), (.029, -.004),
                            (.188, .151, .111, .280, -.020), "quiff"),
    # Narrower temples, loose short layers gathering just at the nape.
    "workshirt": HeadCut(1.04, .95, .945, (.0125, .099, .027), (.040, -.002, .0044), (.022, .000),
                          (.177, .132, .079, .256, .021), "shag"),
}

# More slices around the nose, lids and mouth than at the back of the skull.
AZIMUTHS = tuple(math.radians(a) for a in (0, 8, 17, 28, 43, 62, 92, 134, 180,
                                         226, 268, 298, 317, 332, 343, 352))
# height, half-width, centre depth, forward depth, back depth, jaw/cheek blend
SKULL = ((-.003, .026, .010, .034, .042, 0), (.019, .047, .009, .059, .056, 0),
         (.039, .060, .008, .068, .069, .12), (.057, .070, .005, .071, .077, .32),
         (.074, .078, .004, .071, .083, .72), (.089, .083, .002, .070, .089, .92),
         (.105, .087, .000, .073, .093, 1), (.123, .087, -.001, .075, .094, 1),
         (.139, .085, -.001, .079, .094, .95), (.159, .083, -.002, .085, .092, .78),
         (.181, .081, -.004, .085, .087, .73), (.210, .073, -.007, .072, .076, .75),
         (.234, .050, -.012, .055, .056, .78), (.245, .022, -.014, .030, .033, .80))
HEIGHTS = tuple(p[0] for p in SKULL)
# Keep the hidden upper skull more economical than the visible face.
SKIN_ROWS = tuple(y for y in HEIGHTS if y != .234)


def spot(x, y, cx, cy, rx, ry):
    return math.exp(-((x-cx)/rx)**2 - ((y-cy)/ry)**2)


def smooth(mesh, points, triangles, pigment):
    """Share actual sculpt vertices, including their normals and painted shade."""
    normals = [(0., 0., 0.)] * len(points)
    for a, b, c in triangles:
        normal = cross(sub(points[c], points[a]), sub(points[b], points[a]))
        if math.hypot(*normal) < 1e-10:
            raise ValueError(f"Degenerate sculpt triangle at {points[a], points[b], points[c]}")
        for i in (a, b, c):
            normals[i] = add(normals[i], normal)
    first = len(mesh.points)
    mesh.points.extend(points)
    mesh.normals.extend(unit(n) for n in normals)
    mesh.indices.extend(first + i for face in triangles for i in face)
    for color in pigment:
        mesh.colors.extend((*color, 255))


def loft_indices(rows, cols):
    for row in range(rows-1):
        for i in range(cols):
            a = row*cols+i
            b = row*cols + (i+1) % cols
            yield a, b+cols, b
            yield a, a+cols, b+cols


def loft(mesh, rings, colors, *, bottom=True, crown=None):
    cols = len(rings[0])
    points = [p for ring in rings for p in ring]
    triangles = list(loft_indices(len(rings), cols))
    for cap in ([0, -1] if bottom else [-1]):
        ring = rings[cap]
        # Keep the packed cap centroid identical across Python's float sum changes.
        centre = crown if cap and crown is not None else tuple(math.fsum(axis)/cols for axis in zip(*ring))
        start = len(points)-cols if cap else 0
        pole = len(points)
        points.append(centre)
        colors.append(colors[start])
        for i in range(cols):
            a, b = start+i, start+(i+1) % cols
            triangles.append((pole, b, a) if cap else (pole, a, b))
    smooth(mesh, points, triangles, colors)


class Skull:
    def __init__(self, look, cut):
        self.look, self.cut = look, cut
        self.rings = [[self.point(y, a) for a in AZIMUTHS] for y in SKIN_ROWS]
        # Cache the actual front triangles, not a different ellipsoid behind the eyes.
        self.front = [[] for _ in range(len(self.rings)-1)]
        cols = len(AZIMUTHS)
        points = [p for row in self.rings for p in row]
        for face in loft_indices(len(self.rings), cols):
            if any(math.cos(AZIMUTHS[i % cols]) > .11 for i in face):
                self.front[min(face)//cols].append(tuple(points[i] for i in face))

    def point(self, y, a):
        row = min(len(SKULL)-2, max(0, bisect_right(HEIGHTS, y)-1))
        lo, hi = SKULL[row:row+2]
        _, width, depth, front, back, cheek = mix(lo, hi, min(1, max(0, (y-lo[0])/(hi[0]-lo[0]))))
        cut = self.cut
        side, fore = math.sin(a), math.cos(a)
        x = width * side * self.look.head * (cut.jaw + (cut.cheek-cut.jaw)*cheek)
        z = depth + (front * fore**.82 if fore >= 0 else back * fore)
        if fore > 0:
            xx = x / self.look.head
            nx = .0035 if cut.lock == "quiff" else -.0012
            nw, ny, tip = cut.nose
            eye = cut.eyes[0]
            # Jaw pad, cheek plane, ocular hollows, brow ridge, a continuous nasal bridge
            # into the alae, philtrum and lips. The relief fades at the edge of the skull.
            z += min(1., fore*2.4) * (
                .010*spot(xx, y, .0, .032, .039, .012)
                + .009*spot(abs(xx), y, .056, .111, .023, .025)
                - .010*spot(abs(xx), y, eye, .134, .021, .013)
                + .008*spot(abs(xx), y, eye*.92, .153, .026, .011)
                + .014*spot(xx, y, nx*.4, ny+.035, nw*.81, .033)
                + tip*spot(xx, y, nx, ny, nw*.86, .012)
                + .011*spot(abs(xx-nx), y, nw*.76, ny-.008, nw*.60, .010)
                + .009*spot(xx, y, .001, .060, cut.mouth[0], .012)
                - .0035*spot(xx, y, .001, .073, .006, .008)
                - .003*spot(xx, y, .003, .045, .026, .006)
            )
        return x, y, z

    def surface(self, x, y, lift=0.):
        band = min(len(self.front)-1, max(0, bisect_right(SKIN_ROWS, y)-1))
        for (ax, ay, az), (bx, by, bz), (cx, cy, cz) in self.front[band]:
            den = (by-cy)*(ax-cx) + (cx-bx)*(ay-cy)
            if abs(den) < 1e-10:
                continue
            a = ((by-cy)*(x-cx)+(cx-bx)*(y-cy))/den
            b = ((cy-ay)*(x-cx)+(ax-cx)*(y-cy))/den
            c = 1-a-b
            if min(a, b, c) >= -1e-6:
                return x, y, a*az + b*bz + c*cz + lift
        raise ValueError(f"Facial feature outside the sculpt: {x:.4f}, {y:.4f}")

    def paint(self, p):
        x, y, z = p
        front = min(1., max(0., z/.073))
        x = abs(x)/self.look.head
        warm = spot(x, y, .050, .106, .030, .025) * front
        light = (.6 * math.sin((y-.084)*11) + .4*math.cos(x*22)) * 9
        shade = -12*spot(x, y, .025, .015, .057, .033) - 8*spot(x, y, .047, .134, .031, .013)*front
        r, g, b = tint(self.look.skin, light+shade)
        return (min(255, round(r+warm*8)), max(0, round(g-warm*2)), max(0, round(b-warm*3)))


def relief(mesh, skull, outline, centre, color, rise=.001, lift=.0008):
    """Small conformal, domed relief bounded by a clockwise loop in screen space."""
    p = [skull.surface(*centre, lift+rise)] + [skull.surface(x, y, lift) for x, y in outline]
    mesh_color = [color] + [tint(color, -5)]*len(outline)
    smooth(mesh, p, [(0, i+1, (i+1) % len(outline)+1) for i in range(len(outline))], mesh_color)


def almond(mesh, skull, x, y, width, upper, lower, tilt, color, *, lift=.001, rise=.0015):
    # Always wind clockwise for Godot. Separate curves let a raised lid shade a
    # pitched-down eye without painting a horizontal slit across the brow ridge.
    us = (-.60, 0., .60)
    arc = lambda u, h: (x+width*u, y+tilt*u+h*(1-u*u))
    outline = [arc(-1, 0), *(arc(u, upper) for u in us), arc(1, 0), *(arc(u, -lower) for u in reversed(us))]
    relief(mesh, skull, outline, (x, y), color, rise, lift)


def eyes(mesh, skull):
    look, cut = skull.look, skull.cut
    gap, tilt, opening = cut.eyes
    for s in (-1, 1):
        x = s*gap*look.head
        y = .132 + (.0017*s if cut.lock in ("quiff", "part") else .0006*s)
        w = (.018 if cut.lock in ("shag", "knot") else .020)*look.head
        almond(mesh, skull, x, y, w+.002, opening+.0030, .0040, s*tilt, tint(look.skin, -42), rise=.002)
        almond(mesh, skull, x, y-.001, w, opening, .0027, s*tilt, tint(look.skin, 34), lift=.0034)
        ix, iy = x+.0025*s, y+.0005
        iris = [(ix+.0054*math.cos(-a), iy+.0036*math.sin(-a)) for a in angles(7)]
        relief(mesh, skull, iris, (ix, iy), (56, 40, 37), .0012, .0053)
        yy = .153 + (.002*s if cut.lock == "quiff" else 0.)
        almond(mesh, skull, x-.001*s, yy, w+.004, .0041, .0011, s*(tilt+.001), tint(look.hair, 18), rise=.0018)
    if look.glasses:
        glasses(mesh, skull)


def glasses(mesh, skull):
    # One continuous bevel per wire oval rather than a dozen capped segments.
    rim = (75, 60, 52)
    for s in (-1, 1):
        x = s * skull.cut.eyes[0]*skull.look.head
        ring = [(x + .027*math.cos(a), .132+.018*math.sin(a), .097-.006*s*math.cos(a)) for a in angles(8)]
        # Tiny closed torus along each oval, winding is repaired against its tube axis.
        for i, p in enumerate(ring):
            q = ring[(i+1) % len(ring)]
            v = unit((p[0]-x, (p[1]-.132)*1.5, 0.))
            w = unit((q[0]-x, (q[1]-.132)*1.5, 0.))
            for j in range(3):
                a, b = math.tau*j/3, math.tau*(j+1)/3
                at = lambda c, r, a: add(c, add(scale(r, .0022*math.cos(a)), (0., 0., .0022*math.sin(a))))
                mesh.panel(rim, [at(p, v, a), at(q, w, a), at(q, w, b), at(p, v, b)], mix(p, q, .5))
        outer = ring[0 if s > 0 else len(ring)//2]
        mesh.sweep([(outer, .0019, .0022), ((s*.093*skull.look.head, .135, -.011), .0019, .0020)], [rim], 4)
    mesh.sweep([((-.018, .139, .100), .0019, .0019), ((0, .147, .105), .0021, .0021),
                ((.018, .139, .100), .0019, .0019)], [rim, rim], 4)


def lips_and_nostrils(mesh, skull):
    look, cut = skull.look, skull.cut
    w, corner = cut.mouth
    w *= look.head
    y = .061 if cut.lock != "knit" else .058
    # Lip volume stays restrained: a shaded crease above the softer lower lip.
    almond(mesh, skull, .0013, y, w, .0042, .0046, corner*.35, tint(look.skin, -17), rise=.0017)
    almond(mesh, skull, .0013, y+.0009, w*.97, .00115, .00145, corner*.38, tint(look.skin, -50),
           lift=.0034, rise=.0009)
    nw, ny, _ = cut.nose
    nx = .0035 if cut.lock == "quiff" else -.0012
    for s in (-1, 1):
        x = nx + s*nw*.70
        almond(mesh, skull, x, ny-.010, .0048, .0018, .0017, s*.0016, tint(look.skin, -39), rise=.0007)


def ears(mesh, look, cut):
    for s in (-1, 1):
        x = s*.083*look.head*cut.cheek
        # The helix tapers into a lobe, with a shaded inner strip facing forwards.
        mesh.form([(.075, .009, .011, x, -.012), (.089, .016, .018, x*1.02, -.010),
                   (.119, .017, .019, x*1.035, -.011), (.134, .009, .014, x*1.012, -.019)],
                  [tint(look.skin, -10), look.skin, tint(look.skin, 6)], 6)
        mesh.panel(tint(look.skin, -26), [(x+s*.010, .092, .005), (x+s*.017, .105, .005),
                                        (x+s*.014, .122, .003), (x+s*.008, .114, .008)], (x, .105, -.01))


def scalp(mesh, skull):
    cut, look = skull.cut, skull.look
    front_y, side_y, back_y, crown, sweep = cut.hair
    rings, pigments = [], []
    cuff = []
    for t in (0., .36, .71, .91):
        ring = []
        for a in angles(16):
            side, fore = math.sin(a), math.cos(a)
            slope = max(0., min(1., (fore+.6)/.86))
            fringe = max(0., min(1., (fore-.28)/.58))
            y_edge = back_y+(side_y-back_y)*slope+(front_y-side_y+sweep*side)*fringe
            y_edge += (.005 if cut.lock in ("quiff", "shag") else .0028)*math.sin(a*5+.7)
            if cut.lock == "quiff":
                y_edge += .017*max(0., side)*(1-fringe)
            # Raise the middle rows over the forehead and keep the back round.
            y = y_edge+(crown-y_edge)*t**.85
            flow = a + t*(.68 if sweep < 0 else -.62)
            comb = math.cos(flow*(7 if cut.lock in ("crop", "shag") else 5))
            bulge = (.006 + .004*comb) * math.sin(math.pi*(.12+t*.85))
            if cut.lock == "quiff":
                lift = max(0., fore)**2 * math.sin(t*math.pi)
                bulge += .031*lift
                y += .008*lift
            if cut.lock == "shag":
                bulge += .0045*comb*math.sin(t*math.pi)
            if cut.lock == "crop":
                bulge *= .46
            if t == 0.:
                x, yy, z = skull.point(y_edge-.003, a)
                cuff.append((x*.955, yy, (z+.014)*.950-.014))
            x, _, z = skull.point(min(.245, y), a)
            if y > .220:
                # Dome the hair outward of the engraved skull until the crown
                # apex. A tiny, mean-height cap used to expose the top of bobs.
                d = (y-.220)/(crown-.220)
                arc = math.sqrt(max(0., 1-d*d))
                x = math.copysign(max(abs(x), .075*look.head*abs(side)*arc), side)
                z = -.014 + math.copysign(max(abs(z+.014), .083*abs(fore)*arc), fore)
            if cut.lock == "bob" and not fringe:
                x = math.copysign(max(abs(x), .087*look.head*abs(side)*(1-t*.60)), side)
                z -= .016*(1-t)*max(0., -fore)
            off = (.005 if cut.lock == "crop" else .012) + bulge
            ring.append((x + side*off + sweep*t*.40, y, z + fore*off - .003*t))
            pigment = tint(look.hair, -8+19*t+comb*10 + max(0., side)*5)
            if cut.lock == "crop" and t == 0.:
                pigment = tint(mix(pigment, look.skin, .20), 0)
            pigments.append(pigment)
        rings.append(ring)
    # The hidden cuff overlaps the skin, so no lit strips float beside the temples.
    loft(mesh, [cuff, *rings], [tint(look.hair, -14)]*len(cuff)+pigments, bottom=False,
         crown=(sweep*.43, crown, -.007 if cut.lock == "quiff" else -.020))
    if cut.lock == "tail":
        mesh.sweep([((.028,.152,-.099), .025,.022), ((.040,.098,-.124), .032,.027),
                    ((.061,.017,-.143), .024,.020), ((.081,-.062,-.133), .010,.009),
                    ((.076,-.084,-.133), .004,.004)],
                   [tint(look.hair, -6), look.hair, tint(look.hair, 10), tint(look.hair, 5)], 7)
        mesh.form([(.111, .028, .024, .034, -.117), (.124, .029, .023, .031, -.111)], look.trim, 7)
    if cut.lock == "knot":
        mesh.form([(.116, .022, .022, -.028, -.101), (.137, .041, .037, -.031, -.123),
                   (.173, .039, .033, -.041, -.129), (.198, .020, .018, -.043, -.108)],
                  [tint(look.hair, -13), tint(look.hair, 8), look.hair], 8)


def sculpt_head(look, cut):
    skull = Skull(look, cut)
    mesh = PigmentMesh()
    loft(mesh, skull.rings, [skull.paint(p) for ring in skull.rings for p in ring])
    ears(mesh, look, cut)
    eyes(mesh, skull)
    lips_and_nostrils(mesh, skull)
    scalp(mesh, skull)
    mesh.points = [(x, y*cut.length, z) for x, y, z in mesh.points]
    mesh.normals = [unit((x, y/cut.length, z)) for x, y, z in mesh.normals]
    return mesh
