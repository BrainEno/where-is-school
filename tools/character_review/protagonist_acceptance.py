#!/usr/bin/env python3
"""Acceptance render set A-J for the rebuilt protagonist, from the runtime game asset.

Every shot renders `assets/models/protagonist/Protagonist_Character.glb` - the model the
scene actually loads - with the review renderer (one key light, fill and ambient, no
post). Nothing is cropped to hide a defect; each frame is a fixed camera.

    A front full body      B front head        C/D +-45 degree head
    E/F profiles           G back              H game-camera distance
    I dialog close-up      J multi-light (3 keys)
plus internal review angles: K top, L bottom, M/N full-body +-45.

usage: python3 tools/character_review/protagonist_acceptance.py [outdir]
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from glbview import Glb, render, save  # noqa: E402

GLB = Path(__file__).parent.parent.parent / 'assets/models/protagonist/Protagonist_Character.glb'

HEAD = (0.0, 1.585, 0.0)
SHOTS = [
    ('A_front_full', (0, 1.05, 3.2), (0, 0.92, 0), (760, 1000), 26, None),
    ('B_front_head', (0, 1.585, 1.15), HEAD, (760, 900), 20, None),
    ('C_quarter_hisright', (2.2, 1.62, 2.2), HEAD, (760, 900), 20, None),
    ('D_quarter_hisleft', (-2.2, 1.62, 2.2), HEAD, (760, 900), 20, None),
    ('E_profile_hisright', (3.2, 1.585, 0.15), HEAD, (760, 900), 20, None),
    ('F_profile_hisleft', (-3.2, 1.585, 0.15), HEAD, (760, 900), 20, None),
    ('G_back', (0, 1.585, -3.2), HEAD, (760, 900), 20, None),
    ('H_game_distance', (0, 1.42, 2.7), (0, 1.30, 0), (900, 700), 26, None),
    ('I_dialog_closeup', (0.35, 1.585, 0.85), (0, 1.575, 0), (820, 900), 22, None),
    ('J1_light_keyleft', (1.9, 1.62, 2.4), HEAD, (760, 900), 20, (-0.75, 0.55, -0.35)),
    ('J2_light_keyright', (1.9, 1.62, 2.4), HEAD, (760, 900), 20, (0.75, 0.55, -0.35)),
    ('J3_light_keytop', (1.9, 1.62, 2.4), HEAD, (760, 900), 20, (0.0, 0.95, -0.30)),
    ('K_top', (0.4, 3.4, 0.9), (0, 1.45, 0), (760, 900), 28, None),
    ('L_bottom', (0.3, 0.25, 2.6), (0, 1.35, 0), (760, 900), 28, None),
    ('M_full_quarter', (2.4, 1.30, 2.4), (0, 0.95, 0), (760, 1000), 26, None),
    ('N_full_quarter_back', (-2.4, 1.30, -2.4), (0, 0.95, 0), (760, 1000), 26, None),
]


def main(argv):
    outdir = Path(argv[1]) if len(argv) > 1 else Path('build/head_v2/acceptance')
    outdir.mkdir(parents=True, exist_ok=True)
    glb = Glb(str(GLB))
    for name, eye, target, size, fov, key in SHOTS:
        kwargs = {} if key is None else {'key': key}
        img = render(glb, eye, target, size=size, fov=fov, **kwargs)
        path = outdir / f'{name}.png'
        save(img, str(path))
        print(path)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
