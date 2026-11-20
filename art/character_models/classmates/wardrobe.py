"""Tailored school and court clothing, fitted to the articulated classmate rigs."""
from __future__ import annotations

import math
import numpy as np

from build_teacher_b import (bump, curve, loft, rgb, rings_faces, rounded_contour,
                             smoothstep, sphere, trigs, tube)

SIDES = (('L', 1), ('R', -1))


class FitSurface:
    """Project cut pieces, thread and lettering onto the actual curved cloth."""
    def __init__(self, points, faces, back=False):
        self.sign = -1. if back else 1.
        self.a, b, c = points[faces].transpose(1, 0, 2)
        self.u, self.v = b - self.a, c - self.a
        det = self.u[:, 0]*self.v[:, 1] - self.u[:, 1]*self.v[:, 0]
        self.inv = np.where(abs(det) < 1e-11, 0., 1. / np.where(abs(det) < 1e-11, 1., det))

    def __call__(self, xy, offset=0.):
        a, u, v = self.a, self.u, self.v
        xy = np.asarray(xy)
        out = []
        for x, y in xy:
            dx, dy = x-a[:, 0], y-a[:, 1]
            r = (dx*v[:, 1] - dy*v[:, 0])*self.inv
            s = (u[:, 0]*dy - u[:, 1]*dx)*self.inv
            hit = (self.inv != 0.) & (r >= -1e-5) & (s >= -1e-5) & (r+s < 1.00001)
            if not hit.any():
                raise ValueError(f'Clothing detail misses its fit at x={x:.5f}, height={y:.5f}')
            z = a[hit, 2] + r[hit]*u[hit, 2] + s[hit]*v[hit, 2]
            out.append((max(z*self.sign)+offset)*self.sign)
        return np.column_stack((xy, out))


class Wardrobe:
    def __init__(self, performer):
        self.s = performer
        self.d = performer.design
        self.thin, self.gentle, self.court = performer.thin, performer.gentle, performer.court
        self.hip = performer.bones['Hips'][1][1]
        self.neck = performer.bones['Neck'][1]
        self.sh = performer.bones['UpperArm_L'][1][1]
        self.hem = self.hip - (.079 if self.thin else .066 if self.gentle else .092)
        self.upper = self.neck[1] + (.018 if not self.court else .011)
        self.shade = '46464f' if self.court else self.d.shirt
        self.torso_rings = 44

    def body_weights(self, p):
        names = ['Hips', 'Spine', 'Spine_01', 'Spine_02', 'Chest']
        h = [self.s.bones[j][1][1] for j in names]
        return self.s.axial_weights(p, names, h)

    def panel(self, name, poly, surface, tone, mat, width=.003, offset=.0009, weights=None):
        # Patched pieces folded at their perimeter, not stamps projected onto
        # a flat card: each sample follows the actual cloth's curved drape.
        rim = rounded_contour(poly)
        mid = rim.mean(0)
        rings = np.linspace(.025, 1., 5)
        q = surface((mid + rings[:, None, None]*(rim-mid)).reshape(-1, 2), offset)
        q[:, 2] += surface.sign * np.repeat(width*(1.-rings)**.85, len(rim))
        f = rings_faces(len(rings), len(rim))
        n = len(q)
        q = np.vstack((q, surface([mid], offset+width)))
        f = np.vstack((f, [(n, (i+1)%len(rim), i) for i in range(len(rim))]))
        a, b, c = q[f[0]]
        if np.cross(b-a, c-a)[2] * surface.sign < 0.:
            f = f[:, ::-1]
        w = self.body_weights if weights is None else weights
        self.s.add(name, q, f, tone, mat, w(q), grain=.019)

    def stitch(self, name, xy, surface, tone, radius=.00095, offset=.00054, material='cloth_trim'):
        p, f = tube(surface(curve(xy, 8), offset), radius, 7, reference=(0, 0, 1))
        self.s.add(name, p, f, tone, material, self.body_weights(p), grain=.016)

    def top(self):
        d, s, hem, neck, sh = self.d, self.s, self.hem, self.neck, self.sh
        (hx, hz), (wx, wz), (cx, cz), (sx, sz) = d.cut
        cz0 = s.bones['Hips'][1][2] + .008
        mid = self.hip + .162
        # Collar rise and shoulder cut are separated, with actual front/back
        # thickness and a slightly asymmetric free hem.
        # The neck hole lies closer to the fore edge of the collar on all
        # three bodies, but never breaks abruptly at the back of the neck.
        cut = [(hem, -.0015, cz0, hx, hz, .93), (hem+.018, -.0015, cz0, hx+.0035, hz+.001, .92),
               (self.hip+.033, .001, cz0+.002, hx-.002, hz-.003, .93),
               (mid, .001, cz0+.012, wx, wz, .93),
               (sh-.075, -.001, neck[2]-.007, cx, cz, .89),
               (sh-.009, -.001, neck[2]-.009, sx+.009, sz, .88),
               (sh+.031, .001, neck[2]-.009, sx-.001, sz-.007, .90),
               (self.upper-.027, 0., neck[2]+.021, .072 if not self.court else .076, .058, .95),
               (self.upper, 0., neck[2]+.024, .042 if self.thin else .049 if self.gentle else .057, .051, 1.)]
        if not np.all(np.diff(np.array(cut)[:, 0]) > 0.):
            raise ValueError('Torso fit registers overlap')
        n = self.torso_rings
        p, f = loft(cut, n, 3, .012 if self.thin else .009)
        rows = p[:-2].reshape(-1, n, 3)
        a = np.linspace(0., 2.*math.pi, n, endpoint=False)
        opening = -(.023 if self.thin else .032 if self.gentle else .039)
        dip = opening*(.44+.56*np.maximum(0., np.sin(a))**2)
        rows[:, :, 1] += smoothstep(sh+.024, self.upper, rows[:, :, 1])*dip
        # Open the throat; the fold follows the actual curved edge. Keep the
        # bottom cap which is hidden beneath the overlap with the waistband.
        f = np.vstack((f[:-2*n], f[-2*n::2]))
        p = p[:-1]
        x, y, z = p.T
        # Clothes follow gravity and pinch at two specific seams instead of
        # rippling evenly like shaped plastic. Paint follows those folds.
        near_waist = bump(y, mid-.027, .088)
        fall = np.sin(30.*(x + .27*(y-mid)) + .44*np.sin(26.*y))
        ridge = .0039*fall*near_waist * smoothstep(.012, .069, abs(z-(cz0+.010)))
        p[:, 2] += ridge*np.sign(z-(cz0+.01))
        c = rgb(self.shade) + trigs(p)[:, None] * [.033, .032, .035]
        c += near_waist[:, None]*fall[:, None]*[.017, .017, .021]
        c -= smoothstep(.06, -.05, z)[:, None]*[.034, .029, .018]
        self.s.add('Pressed oxford' if not self.court else 'Dark practice undershirt', p, f, c,
                   'cotton', self.body_weights(p))
        front, rear = FitSurface(p, f), FitSurface(p, f, back=True)
        edge = p[:-1].reshape(-1, n, 3)[-1]
        # Inner facing is tucked under the neck so the view into the opening
        # shows dyed cloth, not a dark hole through to the back of the shirt.
        throat_center = np.array([0., 0., self.neck[2]+.026])
        throat = throat_center + (edge-throat_center)*[.69,1.,.53] - [0.,.0074,0.]
        facing = np.vstack((edge, throat))
        self.s.add('Neck opening inner facing', facing, rings_faces(2,n,flip=True), self.shade,
                   'cotton', self.body_weights(facing), grain=.018)
        if not self.court:
            q, ff = tube(edge, .0026, 7, closed=True, reference=(0, 1, 0))
            self.s.add('Shaped Oxford neck band', q, ff, '91a0a6' if self.thin else 'd2c5b2',
                       'cotton', self.body_weights(q))
            for side, sign in SIDES:
                t = self.upper + opening
                collar = [(sign*x, y) for x, y in [(.013,t-.003), (.036,t-.000), (.064,t-.031),
                                                    (.035,t-.060), (.019,t-.029)]]
                self.panel(f'{side} folded Oxford collar', collar, front, 'a2a9aa' if self.thin else 'dbd0be',
                           'cotton', .0048, .0014)
            self.stitch('Offset button placket', [(-.004,hem+.014), (-.005,mid), (.001,sh-.071), (.001,t-.014)],
                        front, d.seam, .00175)
            for i, y in enumerate(np.linspace(hem+.081, self.upper-.080, 7)):
                a = front([[.0045, y]], .0019)[0]
                q, ff = sphere(a, [.0033, .0033, .00198], 8, 16)
                self.s.add(f'Bone button {i+1}', q, ff, 'c2c3b7' if self.thin else 'c1b1a2',
                           'cloth_trim', self.body_weights(q), grain=.044)
        if self.thin:
            a, b = sh-.092, sh-.188
            self.panel('Mended chest pocket', [(.045,a), (.104,a-.004), (.101,b+.013), (.075,b), (.048,b+.012)],
                       front, '819297', 'cotton', .0036, .0018)
            self.stitch('Chest pocket top thread', [(.045,a-.002), (.073,a-.0035), (.103,a-.007)], front, 'a3a9a8',
                        .0011, .0032)
            q, ff = tube(front(curve([(.085,a+.027), (.086,a+.009), (.085,a-.037)], 8), .0048), .00286, 10)
            self.s.add('Ink pen in the pocket', q, ff, '435365', 'cloth_trim', self.body_weights(q))
            self.stitch('Back yoke', [(-.122,sh-.046), (-.056,sh-.060), (0.,sh-.062), (.053,sh-.059), (.122,sh-.047)],
                        rear, '71818a', .00135)
            self.stitch('Shirt central box pleat', [(-.011,sh-.064), (-.010,sh-.170), (-.014,mid+.019)], rear, '798890')
        else:
            if self.court:
                q, ff = tube(edge, .0028, 7, closed=True, reference=(0, 1, 0))
                self.s.add('Rib close to the neck', q, ff, '6b6060', 'cloth_trim', self.body_weights(q))
            self.outer_layer(p)
        self.sleeves()

    def outer_layer(self, p):
        # Trimmed circular top edge has dips at the actual front and armholes;
        # the shirt is exposed there. The vest and jersey are separate meshes.
        n = self.torso_rings
        a = np.linspace(0, 2*math.pi, n, endpoint=False)
        cos, sin = np.cos(a), np.sin(a)
        style = 'Court jersey' if self.court else 'Quiet rust knit vest'
        arm_cut = .082*bump(sin, 0., .42)
        notch = (.090 if self.court else .112)*bump(cos, 0., .43)*smoothstep(.18, .97, sin)
        rear = .016*bump(cos, 0., .49)*smoothstep(-.20, -.97, sin)
        edge = self.sh+.044 - arm_cut - notch - rear
        bottom = self.hem + (.009 if self.court else .022)
        core = p[:-1].reshape(-1, n, 3)
        rows = 21
        q = np.zeros((rows, n, 3))
        u = np.linspace(0., 1., rows)
        for i in range(n):
            x, y, z = core[:, i, :].T
            yy = bottom + u*(edge[i]-bottom)
            q[:, i] = np.column_stack((np.interp(yy, y, x)+cos[i]*.0102, yy,
                                        np.interp(yy, y, z)+sin[i]*.0123))
        # Bind tape and knit hem are their own geometry. The squared lower edge
        # also takes a very small gathering where hips carry the garment.
        fs = rings_faces(rows, n, flip=True)
        pp = q.reshape(-1, 3)
        color = rgb(self.d.shirt if self.court else '946453') + trigs(pp)[:, None]*[.034, .031, .035]
        sn = np.tile(sin, rows)
        cs = np.tile(cos, rows)
        if self.court:
            side = smoothstep(.87, .95, abs(cs))
            color += (rgb('502733') - color) * side[:, None]
        else:
            columns = np.tile(.5+.5*np.cos(a*38. + np.sin(a*4)), rows)
            color -= columns[:, None] * np.array([.045, .033, .023])
        mat = 'cotton' if self.court else 'ribbed_knit'
        self.s.add(style, pp, fs, color, mat, self.body_weights(pp))
        for label, pts, hue, thickness in [
            ('Neck and armhole binding', q[-1], self.d.seam if self.court else 'bd8c6e', .0034),
            ('Set hem and outside seam', q[0], '662c32' if self.court else '694b42', .0049),
        ]:
            xyz, faces = tube(pts, thickness, 7, closed=True, reference=(0, 1, 0))
            self.s.add(style+' / '+label, xyz, faces, hue, 'cloth_trim', self.body_weights(xyz), grain=.026)
        surf = FitSurface(pp, fs)
        if self.court:
            # Original school sports graphics: off-white taped chevrons and 07.
            self.number(surf, self.sh-.252, 1.04)
            self.number(FitSurface(pp, fs, True), self.sh-.223, 1.46)
            y = self.sh-.151
            # Trajectory and nosecone, made from three offset applique cuts.
            # The graphic is an original school team mark, not an NBA logo.
            self.panel('Ascending nosecone', [(-.028,y-.034),(-.010,y+.005),(.006,y+.013),
                       (.005,y-.004),(-.017,y-.031)], surf, 'f1dbc0', 'cloth_trim', .0007, .0015)
            self.panel('Trailing wing', [(-.006,y-.017),(.012,y-.012),(.004,y-.027),(-.014,y-.032)],
                       surf, 'ddac8c', 'cloth_trim', .0007, .0015)
            self.stitch('Launch trail', [(.011,y-.037),(.016,y-.032),(.020,y-.029)],
                        surf, 'efcfaa', .00152, .0021)
            for sign in (-1, 1):
                for i in range(2):
                    self.stitch('Court shoulder stripe', [(sign*.064,y-i*.009), (sign*.103,y+.013-i*.009),
                                                          (sign*.125,y+.011-i*.009)], surf, 'e3bea3', .0022, .0013)
            # Woven label at the lower left is deliberately unbranded.
            y = bottom+.042
            self.panel('Unbranded woven size tab', [(-.116,y),(-.077,y),(-.078,y-.023),(-.115,y-.023)],
                       surf, '462e32', 'cloth_trim', .0011, .0011)
        else:
            y = self.sh-.138
            self.stitch('Two small repair stitches on the vest', [(-.101,y),(-.093,y+.003),(-.084,y)], surf,
                        'ad7c64', .0009)

    def number(self, surf, y0, scale):
        # Cloth-applique varsity numerals. Concave figures are composed of
        # mitered strokes instead of projecting a filled polygon across holes.
        shapes = {
            'zero': [[(-.019,-.033),(-.012,-.039),(.012,-.039),(.019,-.032),(.019,.033),(.012,.039),
                      (-.012,.039),(-.019,.032),(-.019,-.033)]],
            'seven': [[(-.019,.038),(.020,.038),(-.009,-.038)]],
        }
        for name, xo in [('zero', .032*surf.sign), ('seven', -.030*surf.sign)]:
            for stroke in shapes[name]:
                for a,b in zip(stroke, stroke[1:]):
                    a, b = np.array(a), np.array(b)
                    along = b-a
                    along /= np.linalg.norm(along)
                    normal = np.array([-along[1], along[0]])*.0037
                    # Tiny shared overlap is intentional at a miter. There is
                    # no text raster or third-party font embedded in the model.
                    a = a - along*.0014
                    b = b + along*.0014
                    poly = [(xo-x*scale*surf.sign, y0+y*scale) for x,y in (a+normal,b+normal,b-normal,a-normal)]
                    self.panel(f'Court {name} applique', poly, surf, 'e3c8b1', 'cloth_trim', .0006, .0015)

    def sleeves(self):
        d, s = self.d, self.s
        for side, sign in SIDES:
            sh, el, wr = (s.bones[f'{b}_{side}'][1] for b in ('UpperArm','Forearm','Hand'))
            wx, wy, wz = wr
            ex, ey, ez = el
            sx, sy, sz = sh
            k = d.arm_fit
            rows = [(wy-.011,wx+.002*sign,wz+.005,.024*k,.031*k,.93),
                    (wy+.016,wx-.002*sign,wz+.004,.026*k,.034*k,.87),
                    (ey-.057,ex+.013*sign,ez+.002,.032*k,.034*k,.91),
                    (ey+.012,ex+.001*sign,ez+.004,.034*k,.037*k,.88),
                    (sy-.091,sx+.029*sign,sz-.006,.041*k,.046*k,.91),
                    (sy-.018,sx+.014*sign,sz-.006,.048*k,.047*k,.88),
                    (sy+.018,sx-.004*sign,sz-.006,.042*k,.043*k,.88),
                    (sy+.039,sx-.047*sign,sz-.014,.019*k,.028*k,.98)]
            # Shirt cuffs differ structurally, not by material swap. The first
            # boy's extended cuffs carry buttons; the friend's cuffs roll above
            # the elbow; the athlete's base sleeves end high on the bicep.
            rows = np.array(rows)
            min_y = wy-.011
            if self.gentle:
                min_y = ey+.035
            elif self.court:
                min_y = sy-.126
            if not self.thin:
                fit = [np.interp(min_y, rows[:,0], rows[:,i]) for i in range(6)]
                rows = np.vstack((fit, rows[rows[:,0] > min_y]))
            # Measure the actual skin at the cuff. A register from the bone
            # alone misses the inside of the bent arm on the fuller figures.
            skin = next(part.points for part in s.pieces if part.name == f'{side} articulated skin')
            for j in range(2):
                sample = skin[abs(skin[:,1] - rows[j,0]) < .012][:,[0,2]]
                if len(sample):
                    lo, hi = sample.min(0), sample.max(0)
                    center = .5*(lo+hi)
                    radius = .5*(hi-lo)+.0049
                    factor = np.max(np.linalg.norm((sample-center)/radius, axis=1))
                    blend = 1. if j==0 else .61
                    rows[j,1:3] += blend*(center-rows[j,1:3])
                    rows[j,3:5] = np.maximum(rows[j,3:5], radius*max(1.,factor)*(1. if j==0 else .97))
            p, f = loft(rows, 30, 3, .014)

            def weights(points):
                return s.arm_weights(points[:, 1], side)
            c = rgb(self.shade) + trigs(p)[:, None]*[.026,.027,.031]
            c += bump(p[:,1],ey+.014,.044)[:,None]*[.019,.015,.011]
            s.add(f'{side} set-in sleeve', p[:-2], f[:-60], c[:-2], 'cotton', weights(p[:-2]))
            _, x, z, rx, rz, power = rows[0]
            q, ff = loft([(min_y-.003,x,z,rx+.001,rz+.0016,power),
                          (min_y+.004,x,z,rx+.0035,rz+.003,power),
                          (min_y+(.021 if self.gentle else .013), x-sign*.002,z,rx+.0028,rz+.003,power)],
                         24, 2, .012)
            # This hem is a ring, not a disk that can bisect the exposed arm.
            s.add(f'{side} folded sleeve hem', q[:-2], ff[:len(ff)-48],
                  d.seam if self.thin else 'ded2bc' if self.gentle else '62606a',
                  'cloth_trim', weights(q[:-2]), grain=.030)
            if self.thin:
                q, ff = sphere([x+sign*rx*.48,min_y+.008,z+rz*.88],[.0031,.0036,.0022],8,14)
                s.add(f'{side} cuff button', q, ff, 'adb6b1', 'cloth_trim', weights(q))
        if self.court:
            wr = s.bones['Hand_R'][1]
            x,y,z = wr
            p, f = loft([(y+.012,x+.001,z,.026,.027,.91), (y+.019,x+.001,z,.028,.028,.91),
                         (y+.046,x+.004,z-.001,.030,.030,.93), (y+.052,x+.004,z-.002,.028,.029,.95)],24,2,.017)
            s.add('Plum terry wristband',p[:-2],f[:-48],'5d464f','ribbed_knit',s.arm_weights(p[:-2,1],'R'),grain=.065)

    def trousers(self):
        s, d = self.s, self.d
        # A welded bifurcation: the inseams meet at a curved crotch saddle.
        # Each outside half-circle continues into ONE waistband. No trouser
        # tubes or closed pelvis shell are left sticking through the shirt.
        n = 32
        a = np.arange(n) * (2*math.pi/n)
        cs, sn = np.cos(a), np.sin(a)
        inner = (np.arange(n) >= n//4) & (np.arange(n) <= 3*n//4)
        seat_y = self.hip-.082
        join_y = seat_y-(.081 if self.thin else .084 if self.gentle else .086)
        seat_x, seat_z = self.d.cut[0]
        seat_x -= .007
        seat_z -= .005
        z0 = s.bones['Hips'][1][2]+.008
        v, indices, weights, paint = [], [], [], []
        weld = {}
        waist_ids = [None]*n

        def leg_weights(points, side, ay, ky):
            w = s.axial_weights(points,[f'Foot_{side}',f'LowerLeg_{side}',f'Thigh_{side}','Hips'],
                                [ay-.048,ay+.061,ky+.050,seat_y+.025])
            # Blend into the pelvis across the actual welded seam, not an
            # entire horizontal ring. The outer thigh can still swing freely.
            bridge = (1. - smoothstep(.001, .047, abs(points[:,0]))) * smoothstep(join_y-.073, join_y-.019, points[:,1])
            w *= 1. - bridge[:,None]
            w[:,s.ids['Hips']] += bridge
            return w

        for side, sign in SIDES:
            hip, knee, ankle = (s.bones[f'{b}_{side}'][1] for b in ('Thigh','LowerLeg','Foot'))
            hx,hy,hz = hip
            kx,ky,kz = knee
            ax,ay,az = ankle
            fit = d.trousers_fit
            crotch = .014 if not self.court else .011
            start = join_y-.042
            # Place the upper leg along its own knee-hip axis, rather than
            # pulling every thigh in to the same x before it meets the seat.
            axis = sign*min(abs(.70*hx + .30*kx), seat_x*.61)
            knee_r = .046*fit
            thigh_r = seat_x - abs(axis) + (.006 if self.court else .004)
            thigh_z = .60*z0 + .40*hz
            data = [(ay-.025,ax,az+.008,.037*fit,.045*fit,.87),
                    (ay+.014,ax,az+.006,.040*fit,.047*fit,.87),
                    (ay+.081,ax+sign*.002,az+.002,.038*fit,.044*fit,.90),
                    (ky-.100,kx+.001*sign,kz-.013,.043*fit,.049*fit,.91),
                    (ky-.012,kx,kz-.009,knee_r,.053*fit,.90),
                    (ky+.062,.80*kx+.20*axis,.63*kz+.37*thigh_z,knee_r+.002,.059*fit,.90),
                    (start-.039,.31*kx+.69*axis,.25*kz+.75*thigh_z,.31*knee_r+.69*thigh_r,.066*fit,.89),
                    (start,axis,thigh_z,thigh_r,.073*fit,.89)]
            p, _ = loft(data,n,3,.011 if not self.court else .014)
            rings = p[:-2].reshape(-1,n,3)
            if sign < 0:
                rings = rings[:,(n//2-np.arange(n))%n,:]
            # The outer arcs match the seat above. The inner arc has one
            # shared set of vertex indices, from the zipper to the rear seam.
            top = np.column_stack((sign*seat_x*np.maximum(cs, 0.)**.91,
                                   seat_y-(seat_y-join_y)*np.maximum(-cs, 0.)**.7,
                                   z0+seat_z*np.sign(sn)*abs(sn)**.90))
            top[inner,0] = 0.
            top[:,1] -= crotch*bump(cs,-1.,.270)
            last = rings[-1]
            span = top[:,1] - last[:,1]
            prev = rings[-2]
            enter = (last-prev) * (span/(last[:,1]-prev[:,1]))[:,None]
            # Vertical tangent at the exterior, across the seam at the
            # interior. This eases the old visible bend without making a
            # round hip bulge or a sharp V in the crotch.
            medial = 1. - smoothstep(-.10, .46, cs)
            leave = np.column_stack((-sign*medial*(.019+.034*np.maximum(-cs, 0.)),
                                     span*(1.-medial), np.zeros(n)))
            rows = [*rings]
            for t in (.20,.41,.62,.82,1.):
                rows.append((2*t**3-3*t**2+1)*last + (t**3-2*t**2+t)*enter
                            + (-2*t**3+3*t**2)*top + (t**3-t**2)*leave)
            p = np.asarray(rows).reshape(-1,3)
            yy = p[:,1]
            center = np.interp(yy,[ay,ky,start],[ax,kx,axis])
            fade = 1.-smoothstep(start-.105,start-.002,yy)
            crease = bump(p[:,0],center+sign*.010,.008)*smoothstep(.021,.075,p[:,2])*fade
            knee_pleat = bump(yy,ky-.014,.041)*np.cos(100*(yy-ky)+17*p[:,0])*fade
            p[:,2] += .0028*crease + .0017*knee_pleat*np.sign(p[:,2]-kz)
            c = rgb(d.pants)+trigs(p)[:,None]*[.037,.033,.035]+crease[:,None]*[.056,.054,.051]
            c -= smoothstep(.064,-.040,p[:,2])[:,None]*[.014,.016,.009]
            w = leg_weights(p, side, ay, ky)
            ix = []
            for i, pt in enumerate(p):
                if i >= len(p)-n and inner[i%n] and i%n in weld:
                    ix.append(weld[i%n])
                    continue
                key = len(v)
                v.append(pt)
                paint.append(c[i])
                weights.append(w[i])
                ix.append(key)
                if i >= len(p)-n and inner[i%n]:
                    weld[i%n] = key
            f = rings_faces(len(rows),n,flip=sign==1)
            indices.extend(np.asarray(ix)[f])
            k = len(v)
            v.append(p[:n].mean(0)); paint.append(c[:n].mean(0)); weights.append(w[:n].mean(0))
            indices.extend((k,ix[i],ix[(i+1)%n]) if sign==1 else (k,ix[(i+1)%n],ix[i]) for i in range(n))
            for i in range(n):
                if not inner[i] or i in (n//4,3*n//4):
                    waist_ids[i if sign==1 else (n//2-i)%n] = ix[-n+i]
            # Drawn twill welts follow the OUTER knuckle of each loft. These
            # are inset enough to roll through the knee with the trouser mesh.
            q = np.asarray(rows)[:,0].copy()
            q[:,0] += sign*.00029
            q = q[q[:,1] < self.hem+.003]
            pp,ff = tube(q,.00089 if self.court else .00070,6)
            wq = leg_weights(pp, side, ay, ky)
            s.add(f'{side} sewn twill welt',pp,ff,'817883' if self.court else d.pants,'cloth_trim',wq)
        if any(i is None for i in waist_ids):
            raise ValueError('Open trouser seat')
        base = np.array([v[i] for i in waist_ids])
        rings = [*waist_ids]
        for y, scale in [(seat_y+.025,1.000),(self.hip+.018,.955),(self.hip+.073,.91)]:
            q = (base-[0.,0.,z0])*[scale,0.,scale]+[0.,y,z0]
            if self.thin:
                # Tuck the hidden back waist under the narrow oxford. It
                # previously showed at the rear when pelvis and spine pitched.
                q[:,2] += .0075*smoothstep(self.hip-.006,self.hip+.014,y)*smoothstep(0.,-.075,q[:,2]-z0)
            rings.extend(range(len(v),len(v)+n))
            v.extend(q); weights.extend(s.weights(n,'Hips')); paint.extend(rgb(d.pants)+trigs(q)[:,None]*.028)
        indices.extend(np.asarray(rings)[rings_faces(4,n,flip=True)])
        k = len(v)
        v.append(np.array(v[-n:]).mean(0)); weights.append(s.weights(1,'Hips')[0]); paint.append(rgb(d.pants))
        indices.extend((k,rings[-n+(i+1)%n],rings[-n+i]) for i in range(n))
        p, f, c, w = map(np.asarray, (v,indices,paint,weights))
        s.add('Joined pressed trousers',p,f,c,'woven_twill',w)

    def shoes(self):
        s,d = self.s,self.d
        for side, sign in SIDES:
            ax,ay,az = s.bones[f'Foot_{side}'][1]
            toe = s.bones[f'Toes_{side}'][1]
            z = az+.059
            x = ax+.002*sign
            height = .025 if self.court else .019
            width = .046 if self.court else .041 if self.gentle else .038
            length = .129 if self.court else .117 if self.gentle else .112
            def weights(p):
                q = s.weights(len(p),f'Foot_{side}')
                v = smoothstep(toe[2]-.032,toe[2]+.029,p[:,2])
                q[:,s.ids[f'Toes_{side}']] = v
                q[:,s.ids[f'Foot_{side}']] -= v
                return q
            p,f = loft([(0.,x,z,width-.003,length-.006,.75), (.0038,x,z,width+.001,length,.71),
                        (height*.68,x,z,width+.001,length+.001,.72), (height,x,z,width-.001,length-.001,.74)],32,2,.012)
            c = rgb('474249' if self.thin else '655c54' if self.gentle else 'bbab9b') + trigs(p)[:,None]*.056
            c -= bump(p[:,1],.005,.0047)[:,None]*[.059,.055,.036]
            s.add(f'{side} textured outsole',p,f,c,'shoe_sole',weights(p))
            upper = [(height-.002,x,z,width-.002,length-.002,.76),
                     (height+.012,x,z,width-.001,length-.004,.76),
                     (height+.027,x,z-.012,width-.003,length-.012,.81),
                     (height+.045,x,z-.029,width-.006,length-.038,.85),
                     (height+.063,x,z-.054,width-.009,length-.071,.92),
                     (max(ay+.026,height+.079),x,z-.063,width-.014,.037,.93)]
            p,f = loft(upper,34,3,.011)
            s.add(f'{side} stitched sneaker upper',p,f,d.shoe,'shoe_upper',weights(p),grain=.042)
            # Laces drape down the real vamp; the forward toe bumper is a
            # separate inset dark/light piece rather than a flat stripe.
            front = FitSurface(p,f)
            y0=height+.025
            for i in range(4):
                yy = y0+i*.0078
                q = front(curve([(x-.017,yy+.000), (x,yy+.0023), (x+.018,yy+.0018)],5),.0014)
                pp,ff = tube(q,.00174 if self.court else .0013,8)
                s.add(f'{side} crossing lace {i}',pp,ff,'e3d4c5' if self.court else 'b4a89d' if self.gentle else '77767a',
                      'cloth_trim',weights(pp),grain=.022)
            q = front(curve([(x-.030,height+.018),(x-.023,height+.027),(x,height+.030),
                             (x+.025,height+.026),(x+.030,height+.018)],6),.00125)
            pp,ff = tube(q,.00155,8)
            s.add(f'{side} toe cap stitch',pp,ff,'9a7771' if self.court else d.seam,'cloth_trim',weights(pp),grain=.025)

    def build(self):
        self.top()
        self.trousers()
        self.shoes()
