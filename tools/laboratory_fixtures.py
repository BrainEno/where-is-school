"""The laboratory's wash station and glassware, fitted to the measured casework."""
from fixture_geometry import FixtureBuild, basin, vessel

# The openings are measured before the flange is fitted. The outer skirt covers the
# four saw-cut edges; the first inner vertical band is entirely inside each cutout.
WET_SPAN = (-4.2, 1.4)
WET_COUNTER_X = (-7.51, -6.59)
SINK_CENTRES = (-2.9, 1.03)
SINK_X = -7.05
CUT_WIDTH = 0.54
CUT_DEPTH = 0.66
BASIN_DROP = 0.173

GLASS_ON_WET_BENCH = (
    ("GlassFlask0", "flask", -6.84, -3.54),
    ("GlassFlask1", "small_flask", -7.13, -3.43),
    ("GlassBeaker2", "beaker", -6.71, -3.38),
    ("GlassBeaker3", "small_beaker", -7.30, -3.67),
    ("GlassFlask4", "small_flask", -6.83, 0.34),
    ("GlassCylinder5", "graduate", -7.16, -0.31),
    ("GlassBeaker6", "beaker", -6.95, -0.02),
)


# Centimetres are not fudged with an origin offset: all profiles begin at their seat.
# Upward silhouettes close the outer foot separately from the inside bottom.
def flask(h, r):
    n = r*0.39
    return ((0, r*0.87), (.009, r), (.027, r*.96), (h*.65, r*.56), (h*.76, n),
            (h-.012, n), (h-.009, n+.004), (h, n+.004), (h, n-.004),
            (h-.052, n-.004), (.029, r*.77), (.011, r*.77))


def glass_cup(h, r):
    return ((0, r*.82), (.007, r*.92), (h-.006, r), (h, r), (h, r-.0045),
            (h-.007, r-.0045), (.014, r*.80), (.010, r*.80))


def reagent(h, r):
    return ((0, r*.82), (.009, r), (h-.063, r), (h-.047, r*.90),
            (h-.028, r*.57), (h, r*.57))


def build(top, hood_deck, shelf_tops):
    mats = {name: f"res://assets/materials/laboratory/{name}.tres" for name in (
        "glassware", "metal_frame", "metal_pale", "metal_dark", "ceramic_white", "paper_pale", "accent_oxide",
        "sink_edge", "bottle_umber", "bottle_smoke", "cap_olive", "drain_ink",
    )}
    b = FixtureBuild("Fittings", materials=mats)
    wash = "WashStation"
    b.node(wash, ".")
    for i, z in enumerate(SINK_CENTRES):
        p = f"{wash}/Sink{i}"
        b.node(f"Sink{i}", wash, position=f"Vector3({SINK_X}, {top}, {z})")
        b.detail("Bowl", p, (0, 0, 0), basin(0.598, 0.734, BASIN_DROP, 0.102), "sink_edge", shadow=True)
        b.drain("Strainer", p, (0, -BASIN_DROP-0.006, 0), 0.037,
                "metal_frame" if i == 0 else "metal_pale", "drain_ink")
        b.tap("Tap", p, (-0.374, 0, 0), "metal_pale", "metal_dark", rise=0.375, reach=0.38)
        # An inset kick panel and recessed pull below each bowl, not a blank worktop block.
        b.box("AccessPanel", p, (0.408, -0.36, 0), (0.031, 0.56, 0.695), "accent_oxide")
        b.box("PanelGrip", p, (0.433, -0.149, 0), (0.025, 0.032, 0.182), "metal_dark")
        for j, dz in enumerate((-0.29, 0.29)):
            b.round(f"Screw{j}", p, (0.428, -0.552, dz), 0.014, 0.008, "metal_pale", rot=(0, 0, 90))
    # Draining board: broad ridges with narrow channels, a dish on the dry side.
    for i in range(5):
        b.box(f"DrainingRib{i}", wash, (-7.24+i*.096, top+0.007, -2.19),
              (0.014, 0.014, 0.49), "metal_pale")
    b.box("SoapDish", wash, (-7.32, top+0.013, -1.86), (0.155, 0.026, 0.105), "ceramic_white")
    b.box("Soap", wash, (-7.32, top+0.045, -1.86), (0.113, 0.039, 0.067), "accent_oxide", rot=(0, 10, 0))

    glass = "Glassware"
    b.node(glass, ".")
    profiles = {"flask": flask(.194, .074), "small_flask": flask(.144, .054),
                "beaker": glass_cup(.126, .053), "small_beaker": glass_cup(.090, .043),
                "graduate": glass_cup(.254, .026), "tube": glass_cup(.149, .014)}
    meshes = {kind: vessel(profile, 12) for kind, profile in profiles.items()}
    for name, kind, x, z in GLASS_ON_WET_BENCH:
        b.detail(name, glass, (x, top, z), meshes[kind], "glassware", shadow=True)
    # Graduations are selectively drawn on the visible near wall of the tall cylinder.
    _, _, gx, gz = GLASS_ON_WET_BENCH[5]
    for i in range(5):
        b.box(f"Graduation{i}", glass, (gx+0.0254, top+0.050+0.031*i, gz),
              (0.004, 0.005, 0.023 if i%2 == 0 else 0.012), "bottle_smoke")

    rack = "DryingRack"
    b.node(rack, ".")
    x, z = -7.075, -1.20
    b.box("Tray", rack, (x, top+0.014, z), (0.54, 0.028, 0.89), "metal_pale")
    for i, dx in enumerate((-0.264, 0.264)):
        b.box(f"Rail{i}", rack, (x+dx, top+0.043, z), (0.018, 0.032, 0.89), "metal_frame")
    for i, dz in enumerate((-0.265, 0, 0.265)):
        for j, dx in enumerate((-0.133, 0.133)):
            b.round(f"Peg{i}_{j}", rack, (x+dx, top+0.076, z+dz), .009, .096, "metal_frame", sides=8)
    # The mouth carries weight on the tray; the short peg locates it from inside.
    for i, (dx, dz, kind) in enumerate(((-.133, -.265, "flask"), (.133, 0, "small_flask"),
                                         (-.133, .265, "small_flask"))):
        b.detail(f"Flask{i}", rack, (x+dx, top+.028+max(y for y, _ in profiles[kind]), z+dz), meshes[kind],
                 "glassware", rot=(180, 0, 0), shadow=True)

    for level, y in enumerate(shelf_tops):
        if level == 1:  # Leave a readable horizontal band of empty shelf between the two ranks.
            continue
        for i, (x, kind) in enumerate(zip((-2.43, -2.17, -1.91, -1.64, -1.38, -1.13),
                                          ("small_beaker", "beaker", "flask", "graduate", "flask", "small_flask"))):
            if level == 2 and i in (0, 3):
                continue
            b.detail(f"CabinetGlass{level}_{i}", glass, (x, y, -5.34), meshes[kind], "glassware", shadow=True)

    def bottle(name, x, y, z, h, r, mat, label_side):
        b.detail(name, glass, (x, y, z), vessel(reagent(h, r), 12), mat, shadow=True)
        b.round(name+"Cap", glass, (x, y+h+.017, z), r*.64, .034, "cap_olive", sides=12)
        b.round(name+"CapRing", glass, (x, y+h+.007, z), r*.67, .012, "metal_pale", sides=12)
        b.box(name+"Label", glass, (x, y+h*.31, z+label_side*(r*.96)),
              (r*.96, h*.24, .008), "paper_pale")

    for i, (x, z, h, r, mat) in enumerate(((-5.22, -5.19, .216, .064, "bottle_umber"),
            (-4.91, -5.31, .173, .059, "bottle_smoke"), (-4.05, -5.24, .266, .070, "bottle_umber"))):
        bottle(f"HoodBottle{i}", x, hood_deck, z, h, r, mat, -1)
    for i, (x, z, h, r, mat) in enumerate(((-3.055, -2.52, .217, .055, "bottle_smoke"),
            (-2.95, -2.72, .267, .062, "bottle_umber"))):
        bottle(f"IslandBottle{i}", x, top, z, h, r, mat, 1)

    tubes = "TubeRack"
    b.node(tubes, ".")
    b.box("Base", tubes, (-1.91, top+0.012, -2.61), (0.26, 0.024, 0.105), "metal_frame")
    for i in range(5):
        b.detail(f"Tube{i}", tubes, (-2.014+i*.052, top+0.024, -2.61), meshes["tube"], "glassware")
    for i, z in enumerate((-2.664, -2.555)):
        b.box(f"TopRail{i}", tubes, (-1.91, top+0.096, z), (0.26, 0.015, 0.020), "metal_pale")
    for i, x in enumerate((-2.034, -1.786)):
        b.box(f"RackEnd{i}", tubes, (x, top+0.055, -2.61), (0.016, 0.097, 0.126), "metal_pale")
    return b.emit()
