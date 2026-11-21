#!/usr/bin/env python3
"""Shape the classroom's steel-and-plywood chair as three shared painted meshes.

Local metres: -Z faces the desk. The wrapper keeps the Seat and Back pivots and
supplies the matte material. These small ArrayMeshes bake colour and edge wear
into the geometry, without a texture import, ink pass or runtime generator.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

from fixture_geometry import Facets, circle


OUT = Path(__file__).resolve().parents[1] / "scenes/environment/props/classroom_art"
PLY = (158, 145, 126)
LAMINATE = (124, 113, 98)
EDGE = (171, 157, 137)
UNDERSIDE = (133, 121, 104)
STEEL = (67, 72, 78)
RUBBER = (45, 45, 50)
RIVET = (133, 134, 130)


class PaintedMesh(Facets):
    def __init__(self):
        super().__init__()
        self.colors = bytearray()

    def paint(self, face, pigment):
        self.tinted(face, [pigment] * len(face))

    def tinted(self, face, pigments):
        self.face(*face)
        for rgb in pigments:
            self.colors.extend((*rgb, 255))

    def resource(self):
        return f'[gd_resource type="ArrayMesh" format=3]\n\n[resource]\n_surfaces = {self.surface(bytes(self.colors))}\n'


def tone(pigment, value):
    return tuple(c + round(value) for c in pigment)


def board_grid(width, depth, radius, inset, height, bend, *, grain=False):
    """Rounded XZ outline, with a few interior breaks for the bent plywood grain."""
    w, d, r = width/2-inset, depth/2-inset, radius-inset
    edge = [d - r*k for k in (1, .32, 0)]
    rows = [-z for z in reversed(edge)] + [d*k for k in (-.46, -.19, -.065, .23, .58)] + edge
    grid = []
    for i, z in enumerate(rows):
        reach = w-r + math.sqrt(max(0.0, r*r-max(0.0, abs(z)-d+r)**2))
        gap = min(z-rows[i-1], rows[i+1]-z) if 0 < i < len(rows)-1 else 0.0
        grid.append([bend(x*reach, height, z + (.2*gap*(1-x*x)*math.sin(i*.9+x*3) if grain else 0.0))
                     for x in (-1, -.42, .20, 1)])
    return grid


def rim(grid):
    # -Z long edge, up the right edge, back along +Z, and down the left edge.
    return grid[0][:-1] + [row[-1] for row in grid[:-1]] + grid[-1][:0:-1] + [row[0] for row in grid[:0:-1]]


def cap(mesh, grid, *, face_up, wood):
    # Light, bundled streaks, not a repeating wood texture. Colours stay within
    # the chroma of the previous wood_worn material, below the indigo schoolbag.
    stain = (0, 4, 0, -3, -8, 3, 5, -5, 4, 3, 0)
    for i in range(len(grid)-1):
        for j in range(len(grid[0])-1):
            corners = [(i, j), (i, j+1), (i+1, j+1), (i+1, j)]
            if not face_up:
                corners.reverse()
            colors = [tone(wood, stain[y] + 3*math.cos(x*.82+y*.32)) for y, x in corners]
            mesh.tinted([grid[y][x] for y, x in corners], colors)


def board(width, depth, radius, profile, bend):
    """The bevel and darker exposed ply layers follow the same rim as the cap."""
    grids = [board_grid(width, depth, radius, inset, y, bend, grain=(i in (0, len(profile)-1)))
             for i, (y, inset, _) in enumerate(profile)]
    rings = list(map(rim, grids))
    mesh = PaintedMesh()
    for (a, b), (_, _, pigment) in zip(zip(rings, rings[1:]), profile[1:]):
        for i in range(len(a)):
            j = (i+1) % len(a)
            mesh.paint([a[i], a[j], b[j], b[i]], pigment)
    cap(mesh, grids[0], face_up=False, wood=UNDERSIDE)
    cap(mesh, grids[-1], face_up=True, wood=PLY)
    return mesh


def seat():
    # Seat stays 0.46×0.42 m with its bearing surface at 0.475 m above the floor.
    # A slightly dished centre doesn't move the hip height or the near hand corner.
    def bend(x, y, z):
        dish = .0025 * max(0, 1-(x/.18)**2) * max(0, 1-((z-.025)/.18)**2)
        return (x, y-dish*max(0, y/.025), z)

    return board(.46, .42, .030, [(-.025, .006, None), (-.019, 0, LAMINATE),
                                  (.011, 0, UNDERSIDE), (.025, .008, EDGE)], bend)


def back():
    # A separate curved shoulder panel; the open space below it reveals the uprights.
    # The -90° turn out of the board's XZ plane keeps its faces clockwise.
    def bend(x, y, z):
        arch = 1-(x/.226)**2
        return (x*(.97+.03*(z/.22+.5)), z+.029+.010*arch,
                .135*z-.020*(1-arch)-y)

    mesh = board(.452, .22, .037, [(-.013, .005, None), (-.008, 0, LAMINATE),
                                  (.009, 0, UNDERSIDE), (.013, .006, EDGE)], bend)
    # Four flush, dull-headed fasteners, set over the rear posts. Included in
    # Back so they follow the same picking/outline mesh, never a separate hitbox.
    for x in (-.16, .16):
        for z in (-.060, .044):
            rings = [[bend(x+u, h, z+v) for u, h, v in circle(y, r, sides=6)]
                     for y, r in ((.011, .0085), (.016, .0068))]
            skin(mesh, rings, RIVET, cap_bottom=False)
    return mesh


def skin(mesh, rings, pigment, *, cap_bottom=True, cap_top=True):
    for a, b in zip(rings, rings[1:]):
        for i in range(len(a)):
            j = (i+1) % len(a)
            glancing = 8 * math.cos(math.tau*i/len(a)-.75)
            mesh.paint([a[i], a[j], b[j], b[i]], tone(pigment, glancing))
    if cap_bottom:
        mesh.paint(list(reversed(rings[0])), tone(pigment, -4))
    if cap_top:
        mesh.paint(rings[-1], tone(pigment, 4))


def upright(mesh, sections, pigment, **caps):
    rings = [[(x+u, y, z+v) for u, _, v in circle(y, r, rz=r*.91, sides=8)] for x, y, z, r in sections]
    skin(mesh, rings, pigment, **caps)


def brace(mesh, start, end, radius):
    # All rails lie in the floor plane. Up is their first ring axis, and
    # Up × rail is the second: same handedness as the legs' XZ sections.
    dx, dz = end[0]-start[0], end[2]-start[2]
    length = math.hypot(dx, dz)
    rings = [[(x+v*dz/length, y+u, z-v*dx/length) for u, _, v in circle(0, radius, sides=6)]
             for x, y, z in (start, end)]
    skin(mesh, rings, STEEL, cap_bottom=False, cap_top=False)  # Ends are welded inside the legs.


def frame():
    mesh = PaintedMesh()
    for side in (-1, 1):
        upright(mesh, [(side*.201, .020, -.173, .012), (side*.184, .361, -.120, .014),
                       (side*.173, .431, -.101, .015)], STEEL, cap_bottom=False, cap_top=False)
        upright(mesh, [(side*.194, .020, .190, .013), (side*.183, .383, .112, .014),
                       (side*.181, .455, .142, .014), (side*.165, .606, .181, .013),
                       (side*.158, .762, .204, .012)], STEEL, cap_bottom=False)
        for x, z in ((side*.201, -.173), (side*.194, .190)):
            upright(mesh, [(x, 0, z, .016), (x, .004, z, .018), (x, .031, z, .016)], RUBBER)
        brace(mesh, (side*.19, .182, -.148), (side*.19, .182, .154), .010)
    brace(mesh, (-.19, .158, .161), (.19, .158, .161), .011)
    brace(mesh, (-.173, .418, -.101), (.173, .418, -.101), .016)
    brace(mesh, (-.182, .418, .128), (.182, .418, .128), .016)
    return mesh


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="compare the meshes without writing")
    args = parser.parse_args()
    outputs = {OUT / f"student_chair_{part}.tres": mesh.resource()
               for part, mesh in (("seat", seat()), ("back", back()), ("frame", frame()))}
    size = sum(len(text.encode("utf-8")) for text in outputs.values())
    if size > 84 * 1024:
        parser.exit(1, f"Student chair meshes exceed their 84 KiB text-source allowance ({size} B).\n")
    stale = []
    for path, text in outputs.items():
        if not args.check:
            path.write_text(text, encoding="utf-8")
        elif not path.exists() or path.read_text(encoding="utf-8") != text:
            stale.append(path.name)
    if stale:
        parser.exit(1, f"Regenerate with python3 tools/build_student_chair.py: {', '.join(stale)}\n")
    print(f"Student chair: three shared ArrayMeshes, {size} B of text, no imported textures.")


if __name__ == "__main__":
    main()
