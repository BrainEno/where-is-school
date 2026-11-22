"""Quiet, sculpted stable-yard figures, using the exam crowd's painted forms."""
from dataclasses import replace

from build_teaching_block import child_path, vec3
from dream_stable import shaped, place
from exam_crowd import ARMS, forearm, upper_sleeve, pose_loop
from exam_crowd_forms import LOOKS, head, legs, torso


def woman(b, parent, name, pos, yaw, seated=False):
    look = replace(LOOKS['cardigan' if seated else 'coat'],
                   cloth=(99, 116, 131) if seated else (112, 123, 91),
                   trim=(163, 133, 109), skin=(182, 137, 113),
                   hair=(126, 85, 75) if seated else (93, 103, 122))
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)))
    root = child_path(parent, name)
    if 'stable_people_paint' not in b.local_mats:
        b.mat('stable_people_paint', vertex_color_use_as_albedo='true', vertex_color_is_srgb='true', diffuse_mode=2)
    def piece(label, path, mesh, at=(0, 0, 0)):
        rid = shaped(b, name + label, lambda: mesh)
        place(b, label, path, at, rid, 'stable_people_paint', shadow=True)
    piece('Feet', root, legs(look, .025, seated))
    hip = .516 if seated else look.hip
    b.node('Body', root, position=vec3((0, hip, 0)), rotation_degrees=vec3((12 if seated else 8, 0, 0)))
    body = child_path(root, 'Body')
    chest = torso(look)
    arms = ARMS['Listen' if seated else 'Revise']
    for side, sign, arm in zip('LR', (-1, 1), arms):
        upper_sleeve(chest, look, (sign * look.frame * .91, .421, .009), arm.elbow)
        piece('Arm' + side, body, forearm(look, arm))
    piece('Coat', body, chest)
    piece('Head', body, head(look), (.006, .536, .017))
    pose_loop(b, root, 'Breathe', 6.0, {'Body': ((0, (12 if seated else 8, 0, 0)),
        (3, (14 if seated else 10, 0, 1)), (6, (12 if seated else 8, 0, 0)))})
    return root
