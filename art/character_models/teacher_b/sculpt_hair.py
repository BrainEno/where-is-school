"""Fitted, closed hair shells. The sculpt and its paint follow the same comb guides."""
from __future__ import annotations

import numpy as np


# Independent of tessellation: the scalp phase is also used for the painted
# ridges and the Godot strand shading. Angles here are in sculpt space (+Z front).
def direction(azimuth, polar):
    azimuth, polar = np.broadcast_arrays(azimuth, polar)
    return np.stack((np.sin(polar)*np.cos(azimuth), np.cos(polar),
                     np.sin(polar)*np.sin(azimuth)), axis=-1)


def ease(a, b, x):
    t = np.clip((x-a)/(b-a), 0., 1.)
    return t*t*(3.-2.*t)


def cap_samples(sculpt, center, hairline, rings, sides):
    """Sample just inside each end of the scalp and keep the hairline fitted."""
    a = np.linspace(0., 2.*np.pi, sides, endpoint=False)[None, :]
    reach = np.linspace(1., .012, rings)[:, None]
    polar = hairline(a)*reach
    rays = direction(a, polar)
    radius = sculpt.scalp_rays(center, rays.reshape(-1, 3)).reshape(polar.shape)
    return a, reach, polar, rays, radius


def comb_field(rays, lanes, sweep, tilt, rake):
    """Offset the comb origin so locks flow across the head, not down from its centre."""
    x, y, z = np.moveaxis(rays, -1, 0)
    xp = x*np.cos(tilt) + y*np.sin(tilt)
    yp = y*np.cos(tilt) - x*np.sin(tilt)
    zp = z*np.cos(rake) - yp*np.sin(rake)
    yp = yp*np.cos(rake) + z*np.sin(rake)
    a, polar = np.arctan2(zp, xp), np.arctan2(np.hypot(xp, zp), yp)
    phase = lanes*(a - sweep*np.sin(.88*polar) - .077*np.sin(2.*a-1.6*polar)*np.sin(polar))
    phase += .61*np.sin(6.*a + 2.*polar)*ease(.22,.7,polar)
    group = .58 + .42*np.cos(4.*a + .43*np.sin(a) - 1.8*polar)**2
    falloff = ease(.07, .29, polar)
    blade = (.5+.5*np.cos(phase))**2.8 * falloff
    split = (.5+.5*np.cos(2.*phase + .57*np.sin(3.*a - .82*polar) + .40))**3.5 * falloff
    return group*blade, split, np.cos(phase + .65)*falloff


def shell_grid(center, fitted, depth, crown=None):
    _, _, _, rays, radius = fitted
    xyz = center + rays*(radius+depth)[..., None]
    if crown is not None:
        # B's existing skeleton and authored Godot clips must not be re-scaled
        # due to a new sculpted lock being a fraction taller than the old cap.
        y = xyz[..., 1]
        high = y.max()
        y += (crown-high) * ease(high-.053, high, y)
    return xyz


def sample_grid(grid, a, s):
    """Wrapped bilinear sampler for a fitted cap or its bound paint."""
    rows, sides = grid.shape[:2]
    u = (a % (2.*np.pi)) * sides/(2.*np.pi)
    v = np.clip((1.-s)/(.988), 0., 1.) * (rows-1)
    i, j = np.floor(u).astype(int), np.floor(v).astype(int)
    t, h = (u-i)[...,None], (v-j)[...,None]
    x0, x1, y1 = i%sides, (i+1)%sides, np.minimum(j+1, rows-1)
    return (grid[j,x0]*(1.-t) + grid[j,x1]*t)*(1.-h) + (grid[y1,x0]*(1.-t) + grid[y1,x1]*t)*h


def fitted_ribbon(center, cap, paint, hairline, trace, width, rise, accent):
    """A flat tapered lock following the sculpt, with all edges buried in the cap."""
    a, s = trace.T
    path = sample_grid(cap, a, s)
    rays = path-center
    rays /= np.linalg.norm(rays, axis=1, keepdims=True)
    across = np.cross(rays, np.gradient(path, axis=0))
    across /= np.maximum(np.linalg.norm(across, axis=1, keepdims=True), 1.e-8)
    width_fade = np.sin(np.linspace(.12,np.pi-.07,len(path)))**.57
    u = np.linspace(-1.,1.,5)[None,:]
    guess = path[:,None,:] + across[:,None,:]*(u*width*width_fade[:,None])[...,None]
    xx, yy, zz = np.moveaxis(guess-center, -1, 0)
    azimuth = np.arctan2(zz,xx)
    reach = np.arctan2(np.hypot(xx,zz), yy)/hairline(azimuth)
    position = sample_grid(cap, azimuth, reach)
    bound = sample_grid(paint, azimuth, reach)
    section = np.maximum(0., 1.-u*u)**1.22
    section *= 1. - .24*np.exp(-((u-.46)/.19)**2)
    ridge_fade = width_fade[:,None]**1.9
    # The end pairs are beneath the scalp even on the foreheadward taper.
    ridge_fade[[0,-1]] = 0.
    lift = rise*section*ridge_fade - .00063
    relief = direction(azimuth, np.arctan2(np.hypot(xx,zz),yy))
    position += relief*lift[...,None]
    shade = (section*.56 + .44*np.exp(-((u+.42)/.32)**2))*ridge_fade
    return position, bound + shade[...,None]*np.array(accent)
