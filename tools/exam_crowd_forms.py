"""Measured, vertex-painted forms for 03's anonymous exam crowd.

Metres, +Z forward. Broad joined profiles carry the silhouette; seams and print
are pigment on those profiles. Hands, footwear, hair and held paper have depth.
Only the small native ArrayMeshes ship, with no skin, texture or external model.
"""
from __future__ import annotations

from dataclasses import dataclass
import math

from dressing_geometry import face_out, rotate
from fixture_geometry import Facets, rounded_rect


INK = (63, 54, 61)
PAPER = (247, 232, 198)
RULE = (118, 140, 143)


def tint(rgb, value):
    return tuple(max(0, min(255, round(c + value))) for c in rgb)


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def scale(a, k):
    return tuple(x * k for x in a)


def unit(a):
    return scale(a, 1 / math.hypot(*a))


def cross(a, b):
    return tuple(a[(i+1) % 3]*b[(i+2) % 3] - a[(i+2) % 3]*b[(i+1) % 3] for i in range(3))


def angles(sides):
    return (math.tau * i / sides for i in range(sides))


def ring(section, sides):
    y, rx, rz, x, z = section
    return [(x + rx * math.cos(a), y, z + rz * math.sin(a)) for a in angles(sides)]


class PigmentMesh(Facets):
    def __init__(self):
        super().__init__()
        self.colors = bytearray()
        self.pigment = INK

    def face(self, *points):
        super().face(*points)
        self.colors.extend(bytes((*self.pigment, 255)) * len(points))

    def surface(self):
        return super().surface(bytes(self.colors))

    def panel(self, color, points, inside):
        self.pigment = color
        face_out(self, points, inside)

    def bands(self, rings, colors):
        """Index the round surfaces; split the vertices only across pigment seams/caps."""
        sides = len(rings[0])
        centres = [tuple(sum(axis)/sides for axis in zip(*r)) for r in rings]
        faces = []
        normals = [[(0, 0, 0) for _ in ring] for ring in rings]
        for band, (a, b) in enumerate(zip(rings, rings[1:])):
            inside = mix(centres[band], centres[band + 1], .5)
            for i in range(sides):
                j = (i + 1) % sides
                corners = ((band, i), (band, j), (band+1, j), (band+1, i))
                normal = unit(cross(sub(b[j], a[i]), sub(a[j], a[i])))
                if sum(x*y for x, y in zip(normal, sub(mix(a[i], b[j], .5), inside))) < 0:
                    corners = corners[::-1]
                    normal = scale(normal, -1)
                faces.append((colors[band], corners))
                for row, col in corners:
                    normals[row][col] = add(normals[row][col], normal)
        shared = {}
        for pigment, corners in faces:
            indices = []
            for row, col in corners:
                key = row, col, pigment
                if key not in shared:
                    shared[key] = len(self.points)
                    self.points.append(rings[row][col])
                    self.normals.append(unit(normals[row][col]))
                    shade = (-9, -3, 2, 5, -2, -5)[col*6//sides]
                    self.colors.extend((*tint(pigment, shade), 255))
                indices.append(shared[key])
            a, b, c, d = indices
            self.indices.extend((a, b, c, a, c, d))
        self.panel(tint(colors[0], -10), rings[0], centres[1])
        self.panel(colors[-1], rings[-1], centres[-2])
        return self

    def form(self, profile, pigment, sides=10):
        colors = pigment if isinstance(pigment[0], tuple) else [pigment] * (len(profile)-1)
        return self.bands([ring(section, sides) for section in profile], colors)

    def sweep(self, stations, colors, sides=8):
        """Shape a sleeve, limb or thumb along a measured 3D centreline."""
        path = [p for p, _, _ in stations]
        axis = [unit(sub(path[min(i+1, len(path)-1)], path[max(i-1, 0)])) for i in range(len(path))]
        best = min(range(3), key=lambda i: max(abs(a[i]) for a in axis))
        seed = tuple(float(i == best) for i in range(3))
        rings = []
        for (p, rx, rz), along in zip(stations, axis):
            u = unit(cross(seed, along))
            v = cross(along, u)
            rings.append([add(p, add(scale(u, rx*math.cos(a)), scale(v, rz*math.sin(a)))) for a in angles(sides)])
        return self.bands(rings, colors)

    def tile(self, color, at, size, tilt=(0, 0, 0), radius=.01):
        """A rounded, thin solid (page, pocket book, ticket or sole)."""
        w, h, d = size
        rings = [[add(at, rotate(p, tilt)) for p in rounded_rect(y, w, d, radius)] for y in (-h/2, h/2)]
        return self.bands(rings, [color])


@dataclass(frozen=True)
class Look:
    cut: str
    cloth: tuple
    trim: tuple
    legs: tuple
    skin: tuple
    hair: tuple
    style: str
    hip: float
    frame: float      # Half width across the shoulders, not a uniform model scale
    torso: float      # Hip to neck length factor
    head: float       # Face width factor (head length stays independent)
    glasses: bool = False


LOOKS = {
    "knit": Look("knit", (93, 131, 112), (219, 192, 143), (71, 79, 103), (199, 148, 118), (43, 35, 46),
                 "tail", .772, .179, .96, .90),
    "varsity": Look("varsity", (65, 86, 121), (207, 190, 161), (66, 73, 88), (192, 137, 108), (49, 36, 39),
                   "crop", .980, .221, 1.08, .96),
    "shirt": Look("shirt", (168, 104, 78), (218, 173, 123), (104, 105, 88), (225, 174, 130), (68, 49, 41),
                  "part", .875, .191, 1.00, 1.03, True),
    "hoodie": Look("hoodie", (185, 144, 89), (81, 116, 110), (82, 82, 91), (174, 118, 93), (52, 39, 45),
                   "bob", .831, .213, 1.00, 1.09),
    "coat": Look("coat", (122, 89, 112), (211, 164, 119), (72, 82, 99), (213, 161, 130), (63, 45, 43),
                 "bun", .921, .182, 1.04, .89),
    "windbreaker": Look("zip", (118, 67, 70), (188, 136, 109), (67, 77, 87), (180, 127, 102), (53, 39, 42),
                        "part", .890, .212, 1.05, 1.02),
    "workshirt": Look("shirt", (109, 130, 137), (163, 180, 177), (95, 86, 86), (213, 161, 126), (70, 50, 44),
                      "crop", .832, .188, .98, .94),
    "cardigan": Look("coat", (106, 127, 144), (198, 150, 113), (81, 83, 93), (211, 157, 116), (48, 39, 43),
                     "bob", .851, .193, .96, 1.03),
    "jersey": Look("knit", (144, 102, 93), (230, 188, 155), (93, 70, 82), (194, 143, 121), (74, 53, 45),
                   "bun", .802, .167, .97, .89, True),
    "blouson": Look("varsity", (84, 114, 117), (199, 172, 131), (87, 89, 108), (227, 182, 149), (89, 67, 56),
                    "part", .949, .209, 1.02, 1.04),
    "pullover": Look("hoodie", (135, 120, 142), (197, 180, 142), (82, 93, 116), (182, 129, 104), (51, 39, 42),
                     "tail", .841, .198, .98, .98),
    "vest": Look("zip", (143, 128, 90), (228, 200, 146), (77, 83, 76), (221, 165, 127), (65, 52, 49),
                 "bob", .889, .186, 1.00, .99, True),
}


def on_front(profile, x, y, sides):
    """The actual chord of a loft at (x,y), so small appliques follow its side planes."""
    for a, b in zip(profile, profile[1:]):
        if y <= b[0]:
            row = mix(a, b, max(0, (y-a[0])/(b[0]-a[0])))
            break
    else:
        row = profile[-1]
    front = ring(row, sides)[:sides//2+1]
    for a, b in zip(front, front[1:]):
        if x >= b[0]:
            return mix(a, b, min(1, (a[0]-x)/(a[0]-b[0])))[2]
    return front[-1][2]


def applique(mesh, profile, color, points, sides=12, relief=.004):
    mesh.panel(color, [(x, y, on_front(profile, x, y, sides) + relief) for x, y in points], (0, 0, -.4))


def badge(mesh, profile, color, x, y, radius):
    applique(mesh, profile, color, [(x+radius*math.cos(a), y+radius*math.sin(a)) for a in angles(7)])


def draped_applique(mesh, profile, color, polygon, lift=.003):
    """Fit trim to the actual triangles of the front of a 12-sided garment.

    A long straight polygon chord can go *inside* a loft's chest or waist even
    with every corner lifted. Clip convex trim to each face before lifting it.
    """
    def turn(a, b, p):
        return (b[0]-a[0])*(p[1]-a[1]) - (b[1]-a[1])*(p[0]-a[0])

    def clip(poly, a, b):
        result = []
        for p, q in zip(poly, poly[1:]+poly[:1]):
            u, v = turn(a, b, p), turn(a, b, q)
            if u <= 0.:
                result.append(p)
            if (u < 0 < v) or (v < 0 < u):
                result.append(mix(p, q, u/(u-v)))
        return result

    rings = [ring(row, 12) for row in profile]
    for lo, hi in zip(rings, rings[1:]):
        for i in range(6):
            for a, b, c in ((lo[i], lo[i+1], hi[i+1]), (lo[i], hi[i+1], hi[i])):
                clipped = clip(clip(clip(list(polygon), a, b), b, c), c, a)
                if len(clipped) < 3:
                    continue
                den = turn(a, b, c)
                def raised(p):
                    va, vb = turn(b, c, p)/den, turn(c, a, p)/den
                    return p[0], p[1], va*a[2] + vb*b[2] + (1-va-vb)*c[2] + lift
                start = clipped[0]
                for p, q in zip(clipped[1:], clipped[2:]):
                    if abs(turn(start, p, q)) > 1e-8:
                        mesh.panel(color, [raised(v) for v in (start, p, q)], (0, 0, -.4))


# Separate hem, waist, chest and shoulder ease. The narrow coat and the roomy
# varsity jacket are different patterns, not taller/shorter copies of one torso.
HALL_FIT = {
    "knit": (.95, .94, .99, .97, .95),
    "varsity": (.98, .94, 1.06, 1.06, 1.06),
    "shirt": (.96, .94, .97, .98, .91),
    "hoodie": (1.03, 1.17, 1.03, 1.04, 1.09),
    "coat": (1.00, .94, 1.00, .99, 1.01),
    "windbreaker": (1.02, 1.02, 1.02, 1.01, 1.02),
    "workshirt": (1.05, 1.10, 1.00, 1.00, .95),
}


def torso(look, *, fitted=""):
    f, cloth, trim = look.frame, look.cloth, look.trim
    cut = look.cut
    hem = {"coat": -.248, "knit": -.062, "varsity": -.118, "zip": -.086, "shirt": -.158, "hoodie": -.097}[cut]
    skirt = cut == "knit"
    # Give the hems room over the thigh lofts, including at the ends of a lean.
    width = 1.26 if cut == "coat" else 1.06
    depth = .153 if cut in ("coat", "shirt") else .133
    profile = [(hem, f*(.87 if skirt else width), depth, -.004, -.002),
               (hem+.035, f*(.96 if skirt else width-.015), depth-.004, -.005, -.002),
               (.10, f*.82, .106, -.009, .002),
               (.322, f*.99, .123, .003, .010), (.429, f, .104, .008, .003),
               (.503, f*.54, .076, .007, .006), (.531, .070, .061, .006, .007)]
    if fitted:
        hem_ease, waist, chest, shoulder, depth = HALL_FIT[fitted]
        # Slight torsion through the hem, plus the transition from a fuller chest
        # to a dropped shoulder. The arm and head sockets are not moved.
        ease = (hem_ease, hem_ease, waist, chest, shoulder, 1., 1.)
        profile = [(y, rx*e, rz*(depth if i < 5 else 1.), x+(.008 if i == 0 else 0), z)
                   for i, ((y, rx, rz, x, z), e) in enumerate(zip(profile, ease))]
    edge = tint(cloth, -21)
    body = PigmentMesh().form(profile, [edge, cloth, tint(cloth, 4), cloth, tint(cloth, 10), edge], 12)
    if fitted:
        mark = lambda color, points, lift=.005: draped_applique(body, profile, color, points, .002+lift*.3)
    else:
        mark = lambda color, points, lift=.005: applique(body, profile, color, points, relief=lift)
    body.form([(.516, .056, .051, .005, .007), (.592, .049, .044, .006, .017)], look.skin, 9)
    if fitted in ("shirt", "workshirt"):
        # A light button-up and a boxier overshirt: pointed collar versus
        # stand collar, small breast patch versus roomy flap pockets.
        for s in (-1, 1):
            collar = ((.044, .504), (.102, .446), (.071, .425), (.018, .481)) if fitted == "shirt" else (
                (.054, .507), (.088, .465), (.031, .451), (.016, .488))
            mark(tint(cloth, 18), [(s*x, y) for x, y in collar], .009)
        mark(tint(cloth, -16), ((-.006, hem+.025), (.009, hem+.025), (.016, .467), (.001, .467)))
        for y in (.090, .207, .332):
            badge(body, profile, trim, .010, y, .0058)
        for s in (-1, 1) if fitted == "workshirt" else (-1,):
            mark(tint(cloth, -10), [(s*x, y) for x, y in ((.056, .235), (.132, .241),
                                                        (.128, .324), (.064, .318))])
            if fitted == "workshirt":
                mark(tint(cloth, 16), [(s*x, y) for x, y in ((.055, .316), (.132, .319),
                                                           (.130, .332), (.062, .333))], .010)
    elif cut in ("coat", "shirt"):
        # Open V, overlapping lapels and a facing (not a second torso-shaped shell).
        mark(tint(trim, -16), ((-.072, .506), (.074, .503), (.035, .254), (-.019, .254)), .010)
        for s in (-1, 1):
            mark(tint(cloth, 22), [(s*x, y) for x, y in ((.060, .517), (.138, .469), (.088, .389), (.106, .365), (.022, .255))], .014)
        mark(edge, ((-.012, hem+.019), (.008, hem+.018), (.025, .266), (.006, .265)))
        for y in (.011, .091, .176, .244):
            badge(body, profile, trim, .020, y, .007)
        mark(edge, ((-.135, .215), (-.061, .210), (-.055, .288), (-.135, .297)))
        mark(tint(cloth, 17), ((-.137, .281), (-.053, .276), (-.057, .300), (-.136, .306)), .012)
        if cut == "coat":
            body.form([(.487, .090, .071, .006, .007), (.519, .091, .073, .007, .007),
                       (.551, .073, .066, .004, .009)], [tint(trim, -17), trim], 10)
            mark(trim, ((.022, .497), (.080, .472), (.039, .267), (-.008, .289)), .021)
            mark(tint(trim, -23), ((.031, .417), (.069, .419), (.066, .403), (.026, .402)), .024)
    if cut in ("varsity", "zip"):
        mark(tint(trim, -6), ((-.009, hem+.015), (.003, hem+.015), (.014, .503), (.002, .503)), .014)
        body.form([(.476, .083, .071, .004, .009), (.515, .079, .064, .006, .004),
                   (.550, .068, .060, .007, .005)], [edge, trim if cut == "varsity" else edge], 10)
        for s in (-1, 1):
            mark(trim, [(s*x, y) for x, y in ((.057, .044), (.122, .068), (.131, .052), (.066, .026))])
        if cut == "varsity":
            badge(body, profile, trim, -.088, .360, .036)
            applique(body, profile, cloth, [(-.103, .346), (-.072, .346), (-.075, .373), (-.100, .373)], relief=.011)
        else:
            for s in (-1, 1):
                mark(trim, [(s*x, y) for x, y in ((.024, .360), (.145, .403), (.154, .386), (.024, .338))], .012)
    if cut == "knit":
        body.form([(.504, .085, .066, .004, .008), (.526, .085, .066, .004, .008),
                   (.541, .065, .061, .004, .006)], [trim, tint(cloth, -10)])
        if fitted:
            for s in (-1, 1):
                mark(tint(cloth, -13), [(s*x, y) for x, y in ((.072, .074), (.130, .107),
                                                                           (.136, .116), (.097, .096))])
        else:
            for x in (-.128, -.082, -.035, .035, .082, .128):
                mark(tint(cloth, -13), ((x, .044), (x+.008, .049), (x+.012, .340), (x+.004, .353)))
    if cut == "hoodie":
        # The dropped hood makes the back and profile distinct; only the tips of the cords are light.
        body.form([(.338, .092, .056, -.003, -.083), (.399, .128, .083, .0, -.079),
                   (.481, .121, .072, .0, -.058), (.528, .082, .050, .0, -.024)], [edge, cloth, trim], 9 if fitted else 11)
        mark(tint(cloth, -13), ((-.100, .015), (.107, .017), (.128, .090), (.074, .135), (-.068, .137), (-.123, .094)))
        for x, end in ((-.038, .322), (.059, .283)):
            mark(PAPER, ((x, end), (x+.009, end), (x-.004, .499), (x-.011, .502)), .009)
    return body


def head(look):
    f, skin = look.head, look.skin
    profile = [(y, w*f, d, x, z) for y, w, d, x, z in (
        (.011, .043, .049, 0, .015), (.043, .060, .066, -.002, .019),
        (.082, .078, .073, -.004, .013), (.129, .089, .080, 0, .005),
        (.172, .083, .082, 0, .000), (.213, .072, .071, -.001, -.007), (.239, .032, .044, -.004, -.010),
    )]
    m = PigmentMesh().form(profile, [tint(skin, -13), skin, tint(skin, 7), skin, tint(skin, 4), skin], 12)
    front = lambda x, y, depth=0: (x, y, on_front(profile, x, y, 12) + depth)
    for s in (-1, 1):
        x = s*.087*f
        m.form([(.070, .010, .012, x, -.003), (.093, .018, .017, x*1.04, .000),
                (.132, .011, .014, x, -.003)], [tint(skin, -9), skin], 6)
        x = s*.041*f
        # Narrow lids and a pin of iris, not bulging eyeballs at gameplay distance.
        applique(m, profile, tint(skin, -42), [(x-.021, .128), (x-.008, .131), (x+.020, .126), (x+.016, .121),
                                              (x-.013, .121)], relief=.003)
        applique(m, profile, INK, [(x-.007, .129), (x+.006, .128), (x+.005, .121), (x-.006, .121)], relief=.0045)
        applique(m, profile, tint(look.hair, 18), [(x-.024, .147), (x-.008, .153), (x+.021, .149),
                                                  (x+.018, .144), (x-.015, .146)], relief=.0035)
        if look.glasses:
            rim = [(x+.033*math.cos(a), .129+.024*math.sin(a), .093) for a in angles(10)]
            for p, q in zip(rim, rim[1:]+rim[:1]):
                m.sweep([(p, .0026, .0026), (q, .0026, .0026)], [INK], 4)
            m.sweep([(rim[0 if s > 0 else 5], .0023, .0023),
                     ((x+s*.046, .137, .023), .0023, .0023)], [INK], 4)
    if look.glasses:
        m.sweep([((-.011, .135, .095), .003, .003), ((.011, .135, .095), .003, .003)], [INK], 5)
    a, b, c, d, e = front(0, .154, .002), front(-.018, .094, .003), front(.001, .106, .039), \
        front(.019, .097, .003), front(0, .087, .008)
    for tone, triangle in ((9, (a,b,c)), (1, (a,c,d)), (-14, (b,e,c)), (-19, (e,d,c))):
        m.panel(tint(skin, tone), triangle, (0, .1, -.2))
    applique(m, profile, tint(skin, -53), [(-.026, .066), (-.007, .069), (.023, .067), (.019, .063),
                                          (-.010, .063)], relief=.004)
    applique(m, profile, tint(skin, 14), [(-.016, .060), (.017, .061), (.008, .056), (-.008, .056)])
    hair(m, look)
    return m


def hair(m, look):
    rgb, style, f = look.hair, look.style, look.head
    # The hairline drops behind the ears; alternate part, bob, crop and swept-up profiles.
    edge = []
    for a in angles(12):
        side, fore = math.cos(a), math.sin(a)
        back_y = {"bob": .047, "tail": .096, "crop": .107, "part": .089, "bun": .092}[style]
        front_y = .176 + (side*.023 if style in ("part", "bob") else side*.008)
        y = front_y if fore > .47 else back_y + (front_y-back_y)*max(0, fore+.25)/.72
        rx = (.094 if style == "crop" else .100)*f
        edge.append((rx*side, y, -.010 + .101*fore))
    top = .267 if style in ("part", "tail") else .254
    m.bands([edge, ring((.207, .099*f, .096, -.005, -.007), 12),
             ring((top-.023, .079*f, .075, -.014, -.019), 12),
             ring((top, .037*f, .042, -.021 if style == "part" else -.006, -.020), 12)],
            [rgb, tint(rgb, 9), tint(rgb, 16)])
    if style == "tail":
        m.form([(-.125, .024, .024, .064, -.118), (-.054, .038, .032, .043, -.137),
                (.049, .045, .037, .019, -.134), (.131, .035, .032, .008, -.115),
                (.166, .027, .023, .01, -.094)], [rgb, tint(rgb, 12), rgb, look.trim], 8)
    if style == "bun":
        m.form([(.148, .027, .024, -.019, -.10), (.172, .056, .047, -.026, -.116),
                (.223, .048, .042, -.031, -.124), (.247, .018, .021, -.030, -.123)],
               [look.trim, tint(rgb, 13), rgb], 8)


# Ankle, knee and thigh ease, cut of the shoe. All are local to the original
# stance; moving the silhouettes must not move the actors' planted foot roots.
HALL_LEGS = {
    "knit": (.88, .90, .92, "flat"),
    "varsity": (1.06, 1.12, 1.08, "trainer"),
    "shirt": (.89, .91, .98, "loafer"),
    "hoodie": (1.05, 1.15, 1.11, "canvas"),
    "coat": (.89, .94, .97, "boot"),
    "windbreaker": (.91, 1.02, 1.00, "trainer"),
    "workshirt": (1.01, 1.06, 1.07, "loafer"),
}


def hall_shoe(mesh, look, x, z, side, style):
    # Broader at the ball than the heel, with a rounded toe and planted sole.
    # The cut determines the collar and the amount of visible outsole, not just paint.
    height, length, width, sole = {
        "flat": (.089, .111, .062, .012), "trainer": (.106, .134, .067, .023),
        "loafer": (.097, .132, .065, .018), "canvas": (.114, .120, .068, .022),
        "boot": (.138, .129, .061, .025),
    }[style]
    upper = {"flat": tint(look.legs, -28), "trainer": tint(look.cloth, -18), "loafer": (61, 53, 49),
             "canvas": (87, 78, 72), "boot": (70, 52, 52)}[style]
    sole_color = tint(look.trim, -10) if style in ("trainer", "canvas") else tint(upper, -16)
    profile = [(0, width*.94, length*.96, 0, .039), (sole, width, length, 0, .039),
               (height*.49, width*.94, length*.84, 0, .030), (height, width*.74, .056, 0, -.001)]
    at = lambda p: add((x, 0, z), rotate(p, (0, side*10, 0)))
    rings = [[at(p) for p in ring(row, 8)] for row in profile]
    mesh.bands(rings, [sole_color, upper, tint(upper, 4)])
    straps = (.72,) if style in ("flat", "loafer") else (.66, .78)
    for station in straps:
        yy = height*station
        for sign in (-1, 1):
            # Break the shallow applique at the centre ridge, following the two
            # facets instead of cutting through the toe.
            mark = [(sign*dx, yy+dy) for dx, dy in ((0, 0), (.025, .0015), (.025, .006), (0, .005))]
            mesh.panel(tint(upper, 21) if len(straps) == 1 else tint(look.trim, 13),
                       [at((dx, y, on_front(profile, dx, y, 8)+.0025)) for dx, y in mark], (x, 0, z))


def legs(look, stride, seated=False, *, fitted=""):
    m = PigmentMesh()
    h = .516 if seated else look.hip
    skirt = look.cut == "knit"
    for s in (-1, 1):
        step = stride*s
        x = s * (.126 if seated else look.frame*.65)
        knee_z = .355 if seated else step*.65+.033
        foot_z = .384 + step if seated else step
        knee_y = .454 if seated else h*.54
        cloth = tint(look.legs, -28) if skirt else look.legs
        ankle, knee = ((.041, .055) if skirt else (.058, .075))
        stations = [(.072, ankle, .055, x, foot_z), (.143, ankle+.004, .062, x, foot_z-.012),
                    (knee_y-.095, knee*.90, .071, x, knee_z-.024),
                    (knee_y, knee, .079, x-s*.014, knee_z), (h-.115, .079 if not skirt else .066, .090, x*.84, step*.4),
                    (h+.035, .062 if not skirt else .056, .070, x*.64, 0)] if not seated else [
                    (.072, ankle, .060, x, foot_z), (.180, ankle+.009, .064, x, foot_z-.015),
                    (.363, knee*.88, .074, x, knee_z), (.430, knee, .088, x, knee_z-.005),
                    (.508, knee, .071, x, knee_z-.009)]
        if fitted:
            ankle_ease, knee_ease, thigh_ease, shoe_cut = HALL_LEGS[fitted]
            ease = (ankle_ease, ankle_ease, knee_ease, knee_ease, thigh_ease, thigh_ease)
            # Pressed trousers carry a leaner shin; the wider cotton folds push
            # out at the knee. Both cuffs still meet the top of the same shoe.
            stations = [(y, rx*e, rz*e, cx+(.006*s if i == 1 else 0), cz)
                        for i, ((y, rx, rz, cx, cz), e) in enumerate(zip(stations, ease))]
        m.form(stations, [tint(cloth, -14), cloth, tint(cloth, 7), cloth] + ([] if seated else [tint(cloth, -6)]),
               8 if fitted else 9)
        if seated:
            m.sweep([((x, h-.042, knee_z), .071, .075), ((x-s*.010, h-.011, .218), .079, .083),
                     ((x-s*.02, h+.006, -.021), .105, .082)], [tint(cloth, 7), cloth], 8)
        if fitted:
            hall_shoe(m, look, x, foot_z, s, shoe_cut)
            continue
        # Angled toes, painted sole, and two off-white lace marks on the vamp.
        shoe = tint(INK, 0 if s < 0 else 6)
        rings = []
        for y, rx, rz, z in ((0, .063, .118, .046), (.022, .066, .125, .046), (.052, .061, .115, .042),
                             (.077, .052, .083, .018), (.109, .049, .064, -.002)):
            rings.append([add((x, 0, foot_z), rotate(p, (0, s*10, 0))) for p in ring((y, rx, rz, 0, z), 10)])
        m.bands(rings, [tint(shoe, -14), look.trim, shoe, tint(shoe, 11)])
        for z, y in ((.042, .111), (.077, .092)):
            m.panel(tint(look.trim, 12), [(x+dx, y, foot_z+z+dz) for dx, dz in
                    ((-.023, -.004), (.023, .007), (.022, .015), (-.026, .004))], (x, 0, foot_z))
    if skirt:
        # The deep valleys at the hem read as pleats, not a cylinder or trousers recolour.
        rings = []
        for y, width, depth, pleat in ((h-.349, .229, .159, .86), (h-.239, .213, .149, .89),
                                       (h-.071, .164, .115, .97), (h+.037, .143, .111, .99)):
            rings.append([(width*math.cos(a)*(pleat if i % 2 else 1), y,
                           depth*math.sin(a)*(pleat if i % 2 else 1)) for i, a in enumerate(angles(20))])
        m.bands(rings, [tint(look.legs, 12), look.legs, tint(look.legs, -11)])
    return m
