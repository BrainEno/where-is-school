"""Rest-space brush layout for the eight character head studies.

Points are metres in canonical X-across, Y-up, +Z-front space, not Blender's
world axes. Positive facial depth builds up a plane; negative depth cuts it.
Brushes have compact smooth falloff so the collar, iris and lip seams can be
protected. No pigment or mask is created here.
"""
from __future__ import annotations

from collections import defaultdict

import numpy as np

# Front sign, lateral eye centre, eye height, front of iris, mouth height.
LANDMARKS = {
    'lead': (1, .0305, 1.5824, .1178, 1.4966),
    'q': (1, .0333, 1.6606, .1092, 1.5738),
    'n': (-1, .0314, 1.5317, .0923, 1.4517),
    'seated': (1, .0430, 1.5816, .0995, 1.4885),
    'thin': (-1, .0267, 1.4915, .1474, 1.4184),
    'gentle': (-1, .0292, 1.5056, .1272, 1.4316),
    'court': (-1, .0310, 1.6645, .1432, 1.5881),
    'b': (-1, .0291, 1.5311, .1702, 1.4628),
}

# lobes: (X, Y relative to eye, X/Y radii, millimetres of depth), mirrored
# only where abs(X) is explicitly used. Widths intentionally differ by actor.
PLANES = {
    'lead': ((.038, -.031, .030, .028, 3.9), (.051, -.061, .029, .027, -3.2),
             (.031, .020, .040, .014, 2.2), (.004, -.053, .020, .026, -5.0),
             (.006, -.100, .029, .019, 2.8)),
    'q': ((.053, -.039, .039, .041, 4.4), (.033, -.012, .023, .016, 1.2),
          (.011, -.053, .022, .025, -3.4), (.036, -.079, .036, .028, 2.1),
          (.031, .018, .033, .019, 1.4)),
    'n': ((.049, -.031, .026, .033, 3.7), (.029, -.013, .024, .018, 1.7),
          (.009, -.047, .020, .026, -3.0), (.005, -.013, .014, .027, 2.2),
          (.012, -.104, .034, .025, 2.3)),
    'seated': ((.059, -.029, .027, .030, 3.5), (.047, -.065, .037, .031, -3.4),
               (.002, -.034, .022, .022, -6.1), (.038, .022, .034, .017, 2.2),
               (.010, -.117, .035, .022, 2.4)),
    'thin': ((.047, -.033, .029, .028, 4.0), (.045, -.058, .031, .031, -3.3),
             (.027, -.013, .031, .016, 1.9), (.022, .022, .041, .020, 2.2),
             (.009, -.093, .029, .028, 1.8)),
    'gentle': ((.048, -.029, .035, .032, 4.3), (.039, -.060, .035, .030, 2.4),
               (.029, -.014, .027, .017, 1.5), (.005, -.040, .016, .023, -1.9),
               (.012, -.092, .032, .022, 2.4)),
    'court': ((.048, -.032, .033, .026, 4.3), (.050, -.060, .035, .032, -2.1),
              (.026, .015, .031, .017, 2.3), (.006, -.034, .018, .021, -1.7),
              (.021, -.094, .035, .022, 3.1)),
    'b': ((.045, -.032, .032, .030, 3.0), (.047, -.060, .032, .027, -3.6),
          (.028, -.019, .026, .018, 2.2), (.038, .015, .030, .023, 2.0),
          (.010, -.093, .034, .025, 2.5)),
}


def ease(lo, hi, a):
    q = np.clip((a - lo) / (hi - lo), 0., 1.)
    return q*q*(3. - 2.*q)


def oval(x, y, cx, cy, rx, ry):
    return np.maximum(0., 1. - ((x-cx)/rx)**2 - ((y-cy)/ry)**2)**2


def bump(x, centre, width):
    return np.exp(-((x-centre)/width)**2)


def unit_rows(p):
    return p / np.maximum(1e-12, np.linalg.norm(p, axis=-1, keepdims=True))


def face(role, p, mode, density=None):
    """Coherent relief field across the shell and any dependent lip/brow parts."""
    _, ex, ey, z_eye, mouth = LANDMARKS[role]
    x,y,z = p.T
    dy = y-ey
    ax = abs(x)
    front = ease(z_eye-.047, z_eye-.004, z)
    # Leave the inner and moving edge of each lid close to the original rig.
    # Treat the eyeballs separately, not with the cheekbone brush.
    rim = oval(ax,dy,ex,0.,.021,.014)
    if mode == 'eye':
        out = p.copy()
        if role in ('lead', 'q'):
            # Work the original sclera and the two moving lid islands as one
            # orbit. Flatten their depth together so the cornea stays behind
            # the lid and its supported blink path is not translated in Y.
            seat = z_eye-.0205
            out[:,2] -= .32*(z-seat) + .0012*np.tanh((ax-ex)/.014)
        else:
            inset = {'n': .0006, 'seated': 0., 'thin': .0006, 'gentle': .0008,
                     'court': .0010, 'b': .0007}[role]
            out[:,2] -= inset
        return out
    if mode == 'ear':
        out = p.copy()
        # Bring both shell and concha along; never scale an insert separately.
        shrink = .12 if role == 'seated' else .06
        out[:,0] -= np.sign(x) * shrink * np.maximum(ax-.069,0.)
        return out
    depth = sum(mm*.001*oval(ax,dy,cx,cy,rx,ry) for cx,cy,rx,ry,mm in PLANES[role])
    # Single-sided cheek/mouth adjustment, not a different neutral expression.
    asym = {'lead': -.0012, 'q': .0018, 'n': -.0012, 'seated': -.0015,
            'thin': -.0011, 'gentle': .0013, 'court': .0028, 'b': -.0010}[role]
    cheek = oval(x,dy,.037,-.034,.045,.035)
    corner = oval(ax,y,.022,mouth,.017,.015)
    shelf = oval(ax,dy,ex,-.010,.022,.014)
    lip = oval(x,y,0.,mouth-.007,.030,.010)
    out = p.copy()
    out[:,2] += front * ((depth + asym*cheek)*(1.-.82*rim) + .0018*shelf*(1.-rim) + .0010*lip)
    out[:,1] += front * np.tanh(x/.009) * asym * corner
    if role in ('lead','q'):
        # Shape the static socket rather than translating the moving lid seam.
        orbital_join = oval(ax,dy,ex+.016,-.001,.021,.022)
        tear_shelf = oval(ax,dy,ex+.004,-.013,.022,.014)
        out[:,2] += (.0046*orbital_join+.0021*tear_shelf)*ease(z_eye-.046,z_eye-.014,z)
    if role == 'thin' and density is not None:
        # Subtle bevel at the clipper transition, on the continuous scalp only.
        direction = unit_rows(p - np.array([0.,ey+.020,z_eye-.087]))
        temple = oval(ax,dy,.062,.039,.032,.046)
        relief = density * (1.-.85*density) * (1. + .24*np.cos(x*105 + z*89))
        out += direction * (relief * .0021 - density*temple*.0029)[:,None]
    if role=='n':
        # Preserve the fitted collar boundary while taking planes down to the jaw.
        out = p + (out-p)*ease(1.419,1.438,y)[:,None]
    return out


# Detail cuts are laid out on the first pass, in metres (dimensions) and mm
# (relief). Each performer gets a different brow, aperture, bridge and lip:
# Q's lifted corners, N's narrow bridge, the student's small flat eyelids,
# the thin student's deep-set eyes, the friend's softer mouth, the court
# student's one-sided brow and B's hooded eyes and thin, longer mouth.
# eye: (lower shelf, upper crease, narrowing fraction, outer-corner weight)
# brow: (height above iris, left/right bias, arch lift, ridge)
# nose: (tip below eye, bridge relief, tip relief, wing width change)
# lip: (centre shift from LANDMARKS, front of lips, half-width, upper/lower relief, corner lift)
DETAILS = {
    'q': ((2.1, 2.6, .15, .45), (.026, -.002, 2.8, 1.6),
          (.0525, 1.9, -2.5, -.9), (.001, .113, .026, 2.0, 2.4, 1.0)),
    'n': ((2.2, 2.8, .18, -.25), (.025, -.001, 2.7, 2.1),
          (.045, 2.2, -2.0, -.9), (-.001, .089, .024, 2.0, 1.8, -.5)),
    'seated': ((1.4, 2.7, 0., -.65), (.018, -.001, 2.5, 1.7),
               (.034, .9, -2.7, -.9), (0., .108, .025, 1.7, 2.3, -.4)),
    'thin': ((2.5, 3.2, 0., -.55), (.017, .002, 2.6, 2.0),
             (.042, 1.6, -2.2, -1.3), (.001, .159, .022, 1.6, 1.9, -.9)),
    'gentle': ((2.4, 1.8, 0., .65), (.019, .0015, 2.6, 1.3),
               (.036, 1.1, -1.8, 1.0), (.002, .138, .026, 2.1, 2.6, 1.0)),
    'court': ((2.1, 2.8, 0., .75), (.018, .004, 3.1, 2.1),
              (.044, 1.9, -1.5, -.9), (.002, .158, .024, 2.2, 2.2, 1.3)),
    'b': ((2.2, 3.1, 0., -.75), (.023, .0015, -2.4, 2.0),
          (.041, 2.0, -3.1, -.8), (-.016, .176, .028, 2.0, 1.7, -.7)),
}


def facial_details(role, p, kind):
    """Small shared cuts across the face, lip and brow surfaces, not new paint."""
    _, ex, ey, ze, mouth = LANDMARKS[role]
    eye, brow, nose, lip = DETAILS[role]
    x, y, z = p.T
    ax, side = abs(x), np.sign(x)
    out = p.copy()

    # The orbit is a very shallow fold, not a translated eyeball. Q and N can
    # take a small taper across the complete aperture (sclera, iris and lids).
    # The student keeps the exact cut-surface eye patches, and donor eyelids
    # keep their blink seam; their relief is sculpted just outside the rim.
    shelf, crease, aperture, tilt = eye
    eye_y = ey - .00125 * side if role == 'n' else ey
    dy = y - eye_y
    orbital_front = ease(ze - .032, ze - .008, z)
    fit = oval(ax, dy, ex, 0., .024, .020) * orbital_front
    out[:, 1] -= dy * aperture * fit
    out[:, 1] += .001 * tilt * (ax - ex) / .024 * fit * (aperture > 0.)
    if aperture:
        floor = ze - .024
        out[:, 2] -= .14*np.maximum(0., z-floor)*fit
    if kind == 'eye':
        return out
    rim = 1. - oval(ax, dy, ex, 0., .022, .013)
    lower_shelf = oval(ax, dy, ex + .004, -.015, .030, .014)
    upper_fold = oval(ax, dy, ex - .001, .013, .028, .012)
    outer = oval(ax, dy, ex + .017, -.001, .013, .014)
    depth = orbital_front * rim * (shelf*lower_shelf - crease*upper_fold + tilt*outer)

    # Broaden the ridge under the brow but taper its tail. The offset is the
    # same field on skin and brow islands, including N's two-sided strokes.
    rise, bias, lift, ridge = brow
    u = np.clip((ax - ex) / .032, -1., 1.)
    brow_axis = ey + rise + bias*side - .004*u*u
    arch = oval(ax, y - brow_axis, ex, 0., .031, .012)
    brow_front = ease(ze - .035, ze - .006, z)
    depth += ridge*arch*brow_front
    out[:, 1] += .001*lift*(.54 - .72*u)*arch*brow_front

    # A straightening stroke on the bridge fades into two alae. Do not shift
    # the separately painted nostrils away from that same underlying relief.
    tip_drop, bridge, tip, wing = nose
    tip_y = ey - tip_drop
    nose_front = ease(ze - .004, ze + .011, z)
    bridge_plane = oval(x, y, 0., ey - .016, .014, .030)
    tip_plane = oval(x, y, 0., tip_y, .018, .014)
    alae = oval(ax, y, .013, tip_y - .006, .011, .011)
    depth += nose_front*(bridge*bridge_plane + tip*tip_plane + .83*alae)
    out[:, 0] += .001*side*wing*nose_front*alae

    # A slight Cupid's bow and a wider lower plane, with a groove above and
    # soft corners rather than moving the lip seam as a separate ribbon.
    shift, z_lip, width, upper, lower, corner = lip
    lip_y = mouth + shift
    lip_front = ease(z_lip - .024, z_lip - .006, z)
    seam = lip_y + .003*np.minimum(1., (x/width)**2)
    lip_top = oval(ax, y - seam, .006, .0055, .020, .009)
    lip_bottom = oval(x, y - seam, 0., -.005, width, .010)
    philtrum = oval(x, y, 0., lip_y + .014, .006, .009)
    mouth_corner = oval(ax, y - seam, width - .004, 0., .014, .011)
    if role in ('thin','gentle','court'):
        # The donor's SoftSmile folds into the old mouth corners. Keep that
        # hinge instead of pulling it out with the central lip planes.
        lip_front *= 1. - ease(.008, .015, ax)
    depth += lip_front*(upper*lip_top + lower*lip_bottom - .95*philtrum - .74*mouth_corner)
    out[:, 1] += .001*corner*mouth_corner*lip_front*(.64 + .36*side)
    out[:, 2] += .001*depth
    return out


def lead_spikes(p, triangles):
    """Loosen the archived spike silhouette on the original indexed hair."""
    out = p.copy()
    centre = np.array([0., 1.627, .029])
    crown = p[:, 1].max()
    cap, *locks = components(p, triangles)
    x, y, z = p[cap].T
    fringe = ease(.098, .124, z) * ease(1.656, 1.624, y)
    out[cap, 1] += fringe*(.0056*np.sin(127*x+.37) + .0028*np.cos(223*x))
    for ids in locks:
        v = p[ids]
        mid = v.mean(axis=0)
        centred = v - mid
        _, _, axes = np.linalg.svd(centred, full_matrices=False)
        axis = axes[0]
        radial = mid - centre
        if axis @ radial < 0.:
            axis = -axis
        length = centred @ axis
        span = np.ptp(length)
        if span < .020:
            continue
        t = (length - length.min()) / span
        root = ease(.19, .94, t) * (1. - ease(crown - .013, crown, v[:, 1]))
        # Sweep some tufts off-axis; the nearly horizontal long needles near
        # the ears come back a little. The irregular, tall crown still reads
        # very differently from the combed shell, even at gameplay distance.
        noise = np.sin(radial @ [217., 143., 79.])
        horizontal = 1. - abs(axis[1])
        contraction = .095 * horizontal * ease(.044, .082, span)
        sweep = unit_rows(np.array([[radial[2], .27*abs(radial[0]), -radial[0]]]))[0]
        fringe_drop = .010*ease(.093, .128, mid[2])*ease(1.708, 1.667, mid[1])
        bend = (.0036 + .0056*noise) * sweep + [0., .0037*horizontal*noise - fringe_drop, 0.]
        out[ids] += root[:, None] * (bend - contraction*span*axis)
        x, y, z = v.T
        # Rake locks which cross the pinna back behind it, retaining their
        # insertions and most of the side silhouette, not trimming them off.
        crosses_ear = (abs(x) > .062) & (abs(x) < .098) & (y > 1.537) & (y < 1.600) \
            & (z > -.012) & (z < .035)
        if crosses_ear.any():
            out[ids, 2] -= .037*ease(.049, .077, abs(x))
    return out


def components(p, triangles):
    """Join vertex splits by position for brush grouping, never merge their indices."""
    _, ids = np.unique(np.round(p,6),axis=0,return_inverse=True)
    roots = list(range(max(ids)+1))

    def root(i):
        while roots[i] != i:
            roots[i] = roots[roots[i]]
            i = roots[i]
        return i

    for a,b,c in ids[triangles]:
        ra = root(a)
        roots[root(b)] = roots[root(c)] = ra
    groups = defaultdict(list)
    for i, ident in enumerate(ids):
        groups[root(ident)].append(i)
    return [np.asarray(g) for g in sorted(groups.values(), key=lambda g:(-len(g),g[0]))]


def hairline(role, a):
    """Cut the hem as a continuous curve: crown over temple, then around the ear."""
    a = np.arctan2(np.sin(a),np.cos(a))
    c = np.cos(a)
    forehead, nape = ease(.17,.95,c), ease(.01,-.93,c)
    if role=='lead':
        breaks = .072*np.sin(6*a+.4) + .024*np.cos(11*a-.2)
        return 1.49 - .31*forehead + .68*nape + forehead*(.19*np.sin(a+.29)+breaks)
    breaks = .039*np.sin(5*a+.71) + .020*np.sin(9*a-.4)
    sideburn = .10*bump(abs(a),.98,.13)
    return 1.45 - .245*forehead + .77*nape + sideburn + forehead*(.093*np.sin(2*a-.3)+breaks)


def shell_relief(role, rest, a, t):
    """Large swept planes first, small grooves following them, never free spikes."""
    x,y,z = np.moveaxis(rest,-1,0)
    _,_,eye,ze,_ = LANDMARKS[role]
    faceward = ease(ze-.106,ze+.011,z)
    skirt = 1.-ease(.91,1.,t)
    crown = ease(eye+.019,eye+.104,y)
    surround = ease(.04,.27,t)

    def stroke(start, turn, width, begin, end, gain):
        trace = start + turn*(t-.36) + .19*turn*np.sin(3.1*t)
        delta = np.arctan2(np.sin(a-trace),np.cos(a-trace))
        envelope = ease(begin,begin+.15,t)*ease(end,end-.20,t)
        return gain*bump(delta,0.,width)*envelope

    if role=='lead':
        flow = x + .40*(z-.064) - .34*(y-1.671)
        broad = .63*np.cos(94*flow+.5) + .25*np.cos(161*flow-.34)
        seam = bump(flow,-.033,.008)*faceward
        high = .52*bump(flow,.004,.024) + .31*bump(flow,.047,.026)
        top = .024*crown*(.69+.39*faceward+.56*high)
        # Distinct long forms ride across the broad sweep. Their ends merge
        # back into the outer shell; asymmetry is concentrated around the crest.
        locks = sum(stroke(*guide) for guide in (
            (-1.04,.72,.24,.07,.90,.0117),(-.50,.97,.21,.06,.92,.0161),
            (.04,1.18,.19,.04,.96,.0199),(.62,.94,.20,.10,.89,.0160),
            (1.23,.58,.22,.16,.86,.0104),(2.44,.45,.26,.13,.75,.0087)))
        bend = crown*skirt*(.0051*broad - .0037*seam) + locks
        back = .0024*np.cos(7*a+4.9*t+.6)*surround*(1.-faceward)
        depth = .0023 + skirt*(.0059 + top + bend + back)
        drift = .0195*crown*skirt
    else:
        flow = x - .52*(z-.049) - .18*(y-1.738)
        rake = .55*np.cos(113*flow+.4)+.28*np.cos(164*flow-.7)+.15*np.cos(229*flow+1.3)
        shell_seam = .0021*bump(flow,.035,.010)*faceward*crown
        wave = (.0027*rake - shell_seam)*(.43+.57*faceward)*ease(.14,.46,t)
        long_lobe = .0083*bump(flow,-.008,.046)*faceward*ease(.47,.75,t)
        comb = sum(stroke(*guide) for guide in (
            (-1.52,-.40,.22,.22,.93,.0040),(-.98,-.65,.22,.14,.99,.0045),
            (-.40,-.71,.17,.12,.98,.0038),(.11,-.60,.18,.11,.93,.0049),
            (.63,-.62,.19,.12,.97,.0042),(1.09,-.45,.20,.15,.94,.0036),
            (1.68,-.56,.23,.15,.89,.0032),(2.65,-.70,.26,.11,.89,.0031)))
        depth = .0021 + skirt*(.0034 + .0026*crown + wave + long_lobe + comb)
        drift = -.0060*crown*skirt + .0020*np.sin(a+.7)*faceward*surround*skirt
    return depth, drift


def other_hair(role,p,label,component):
    x,y,z = p.T
    _,_,ey,ze,_ = LANDMARKS[role]
    q = p.copy()
    radial = unit_rows(p - np.array([0.,ey+.020,ze-.092]))
    fore = ease(ze-.041,ze+.008,z)
    if role == 'n':
        # Pull ear-front shards back into the outline of the tucked bob. The
        # falloff fades above the ear and keeps the outer cheek hair-free.
        lobe = ease(.039,.062,abs(x)) * ease(1.541,1.494,y) * ease(-.057,.002,z)
        # Trade part of the old upward lift for an inward/backward stroke
        # rather than inflating the hem past the outer cheek.
        q[:,2] -= .0075*lobe
        q[:,0] -= np.sign(x)*(.0118*lobe+.0056*oval(abs(x),y,.056,1.459,.022,.019)*ease(-.008,.027,z))
        q[:,1] -= .0100*lobe
        scalp = ease(1.552,1.614,y)*ease(1.632,1.623,y)
        sweep = x-.32*(z-.028)
        ridge = .58*np.cos(78*sweep-.75)+.23*np.cos(141*sweep+1.1)
        part = bump(sweep,-.032,.0105)*scalp
        q += radial*(scalp*(.0027*ridge+.0016) - .0041*part)[:,None]
        # Shorten the visible surface strips embedded in the nape; no lighter
        # panel should extend below the cohesive hem of the main shell.
        if component > 0 or label == 'M_ST_HairLight':
            q[:,1] += .0042*ease(1.531,1.453,y)
            q -= (.0042 if label == 'M_ST_HairLight' else .0034)*radial
    elif role == 'seated':
        side = ease(.030,.083,abs(x))
        back = ease(ze-.086,ze-.176,z)
        flow = x + .31*(z-.034) - .21*(y-1.678)
        crests = (.65*np.cos(83*flow+.3)+.24*np.cos(164*flow-.9))
        crest_mask = ease(1.577,1.684,y)*(1.-ease(1.726,1.744,y))
        ridge = (.0047*crests + .0020)*crest_mask
        part = .0041*bump(flow,-.029,.013)*crest_mask*ease(-.052,.068,z)
        q += radial*(ridge - part + .0017*back*(1.-.50*side))[:,None]
        q[:,1] += .0061*fore*bump(y,1.638,.031)*np.tanh(x/.037)
        if label == 'Hair_Back':
            q -= radial*(.0014+.0038*ease(1.579,1.664,y))[:,None]
        elif label.startswith('Hair_Fringe'):
            # The five overlapping locks keep a shared curve and long visible tips.
            q[:,0] += .0023*bump(y,1.666,.044)
    elif role == 'gentle':
        flow = x+.41*(z-.072)-.31*(y-ey-.059)
        sweep = oval(x,y,-.020,ey+.082,.081,.062)*ease(ze-.087,ze+.007,z)
        part = bump(flow,.025,.009)*ease(ey+.039,ey+.083,y)*ease(ze-.105,ze-.013,z)
        arc = .50*np.cos(89*flow+1.05)+.32*np.cos(152*flow-.25)
        q += radial*(.0058*sweep+.0025*sweep*arc-.0044*part)[:,None]
        q[:,0] -= .0044 * sweep
    elif role == 'court':
        axis = x + .19*(z-.108) + .13*(y-ey-.085)
        crest = bump(axis,-.015,.048)*ease(ey+.040,ey+.104,y)
        drift = .64*np.cos(79*axis-29*z)+.30*np.cos(147*axis+36*z+.45)
        q[:,0] -= .0047*crest
        q[:,1] += crest*(.0047*drift+.0020)
        q += radial*(crest*(.0031*drift+.0037))[:,None]
    elif role == 'b':
        flow = x + .45*(z-.103) + .36*(y-ey-.048)
        ridge = .60*np.cos(79*flow-.8) + .21*np.cos(160*flow+.64)
        bun = ease(.067,.027,z) * ease(ey+.013,ey-.034,y)
        # Higher counter-sweep on the temple; quieter curved relief at the knot.
        sweep = oval(x,y,.018,ey+.075,.078,.057)*ease(ze-.089,ze+.001,z)
        part = bump(flow,-.039,.012)*sweep
        q += radial*(sweep*(.0041+.0028*ridge)-.0039*part)[:,None]
        q[:,1] += bun*.0038*(.80+.20*np.cos(59*x + 21*z))
        q[:,2] += bun*.0047
        q[:,0] -= bun*.0035
    return q
