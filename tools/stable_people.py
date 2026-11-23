"""The two women at work in the stable yard (round 19), as dream-annex nodes.

The sculpts and the poses are `stable_workers.py`; this module places them. Each figure is
`Feet`, `Body` (a pivot at the hip) with `Coat`, `Head`, `ArmL` and `ArmR`, and a `Motion`
AnimationPlayer whose single looping clip turns only those visual pivots and the tool she
holds. No script, actor or collider; the yard's walking surface is untouched.
"""
from build_teaching_block import child_path, vec3
from dream_stable import coat, place, shaped
import stable_workers as sw


def motion_loop(b, parent, action, duration, tracks):
    """A native looping clip over {(path, property): [(time, value)]}, linear between keys."""
    props = {"length": duration, "loop_mode": 1}
    for i, ((path, prop), keys) in enumerate(tracks.items()):
        slot = f"tracks/{i}/"
        props[slot + "type"] = '"value"'
        props[slot + "path"] = f'NodePath("{path}:{prop}")'
        props[slot + "interp"] = 2
        props[slot + "loop_wrap"] = "true"
        times = ", ".join(f"{time:.4g}" for time, _ in keys)
        transitions = ", ".join("1" for _ in keys)
        values = ", ".join(vec3(tuple(round(v, 4) for v in value)) for _, value in keys)
        props[slot + "keys"] = (f'{{"times": PackedFloat32Array({times}), "transitions": '
                                f'PackedFloat32Array({transitions}), "update": 0, "values": [{values}]}}')
    animation = b.mesh("Animation", **props)
    library = b.mesh("AnimationLibrary", _data=f'{{&"{action}": SubResource("{animation}")}}')
    b.node("Motion", parent, "AnimationPlayer", autoplay=f'"{action}"', libraries=f'{{&"": SubResource("{library}")}}')


def _figure(b, parent, name, kind, pos, yaw):
    parts, shoulders = sw.worker(kind)
    seated = kind == "sifter"
    hip = sw.HIP_SIT if seated else sw.HIP_STAND
    lean = sw.SIT_LEAN if seated else sw.RAKE_LEAN
    b.node(name, parent, position=vec3(pos), rotation_degrees=vec3((0, yaw, 0)))
    root = child_path(parent, name)
    cloth = coat(b, sheen=.12, roughness=.95, fill=.34)
    skin_and_cloth = cloth

    def piece(label, path, at=(0, 0, 0), rot=None):
        rid = shaped(b, name + label, lambda: parts[label])
        return place(b, label, path, at, rid, skin_and_cloth, rot=rot, shadow=True)
    piece("Feet", root)
    b.node("Body", root, position=vec3((0, hip, 0)), rotation_degrees=vec3((lean, 0, 0)))
    body = child_path(root, "Body")
    piece("Coat", body)
    piece("Head", body, sw.NECK)
    for side in "LR":
        piece("Arm" + side, body, shoulders[side], rot=(0, 0, 0))
    return root, body


def raker(b, parent, name, pos, yaw):
    """She draws a grain rake through the grain, bending into each stroke."""
    root, _ = _figure(b, parent, name, "raker", pos, yaw)
    _, _, reach, rest = sw.raker_pose()
    rid = shaped(b, "GrainRake", lambda: sw.rake(reach, rest))
    place(b, "Rake", root, sw.RAKE_GRIP, rid, coat(b, sheen=.08, fill=.3), rot=(rest, 0, 0), shadow=True,
          aabb=(-.4, -1.2, -.8, .8, 1.6, 2.4))
    keys = sw.rake_keys()
    motion_loop(b, root, "Rake", sw.RAKE_PERIOD, {
        ("Body", "rotation_degrees"): [(t, (lean, 0, 0)) for t, lean, _, _, _, _ in keys],
        ("Body", "position"): [(t, (0, sw.HIP_STAND, shift)) for t, _, _, shift, _, _ in keys],
        ("Body/ArmL", "rotation_degrees"): [(t, (w, 0, 0)) for t, _, w, _, _, _ in keys],
        ("Body/ArmR", "rotation_degrees"): [(t, (w, 0, 0)) for t, _, w, _, _, _ in keys],
        ("Rake", "position"): [(t, grip) for t, _, _, _, grip, _ in keys],
        ("Rake", "rotation_degrees"): [(t, (pitch, 0, 0)) for t, _, _, _, _, pitch in keys],
    })
    return root


def sifter(b, parent, name, pos, yaw):
    """She sits on a low stool and shakes a bamboo sieve of grain over her knees."""
    root, body = _figure(b, parent, name, "sifter", pos, yaw)
    dressing = coat(b, sheen=.08, fill=.3)
    place(b, "Stool", root, (0, 0, -.02), shaped(b, "LowStool", sw.stool), dressing, shadow=True)
    at = sw.body_local(sw.SIEVE_AT, (0, sw.HIP_SIT, 0), sw.SIT_LEAN)
    place(b, "Sieve", body, at, shaped(b, "BambooSieve", sw.sieve), dressing, rot=(-sw.SIT_LEAN, 0, 0), shadow=True,
          aabb=(-.4, -.2, -.4, .8, .4, .8))
    place(b, "Basket", root, (.52, 0, .3), shaped(b, "GrainBasket", sw.basket), dressing, rot=(0, 20, 0), shadow=True)
    place(b, "Sack", root, (-.5, 0, .02), shaped(b, "GrainSack", sw.sack), dressing, rot=(0, -30, 0), shadow=True)
    keys = sw.sift_keys()
    motion_loop(b, root, "Sift", sw.SIFT_PERIOD, {
        ("Body/ArmL", "rotation_degrees"): [(t, (0, a, 0)) for t, a, _ in keys],
        ("Body/ArmR", "rotation_degrees"): [(t, (0, a, 0)) for t, a, _ in keys],
        ("Body/Sieve", "position"): [(t, tuple(p + o for p, o in zip(at, off))) for t, _, off in keys],
    })
    return root
