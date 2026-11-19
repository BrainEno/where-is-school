# Teacher B — isolated character review

[简体中文](README.zh-CN.md)

This is a **review asset**, not a character placement or a release approval. The
owner's reference is visual direction only; it is not included, sampled into a
texture, or re-created as a dialogue portrait. The stand collar, thin silhouette,
swept grey hair, low roll, angular eyes and tortoiseshell spectacles are the
model's interpretation of the reference. The straight trousers and flat shoes
extend beyond the reference and are provisional.

## Inspect or edit

- Open [`teacher_b.blend`](teacher_b.blend) in Blender 4.5 LTS. The metric source
  has individually editable parts in collections (skin, hair, glasses, tailoring,
  trousers and shoes). Turn overlays back on and enter Pose Mode to pose the
  selected armature. The timeline marks **1** (bind), **24** (elbow and fingers)
  and **48** (stride). These are static deformation checkpoints, not performance
  clips. Lens, rims, temples, hinges, hair and earrings are distinct geometry.
- In Godot, open `scenes/dev/teacher_b/teacher_b_review.tscn` and run the current
  scene (F6). **1–6** choose full, face, back, elbow/hand, stride and the game
  camera. **Left/Right** turn the figure. **Tab** switches between B and the
  current `Protagonist_Character` wrapper in shots 1, 2 and 6; **M** compares B's
  matte painted finish to the original GLB. Same mark, room lighting and camera
  scale; the close-up is only re-centered vertically to account for height.
- `scenes/dev/teacher_b/teacher_b.glb` is the meter-scale **+Y / −Z** export.
  Crown at **1.640 m**, soles at **0**, origin on the centered ankle line. It
  carries one 57-joint armature, normalized four-influence weights, inverse binds,
  vertex paint, and two authored blink targets. There are 49,686 triangles across
  13 skinned surfaces and 12 materials. The two transparent lenses are batched
  separately from the frames. No camera, light, texture, collider or action is
  stored in the GLB. Face shapes and the jaw are not a dialogue performance rig.

No production room, `BPresence`, dialogue, impression, `q_wake` or `b_on_stage`
behavior changes. The review stages the actual classroom's backdrop and lights
with its actor, navigation and interaction branches removed. The source and
review directories stay outside release packs under the existing export rules.
The triangle count is descriptive, not a finish criterion: review the head,
clothing joins, gesture and readability against the **current** protagonist, not
the retired `protagonist.glb` now used by the seated student.

## Source and rights

The geometry recipe is first-party. The face and hand topology, morph offsets,
joint placement and seed skin masks use only the **CC0 1.0 data** of MakeHuman
v1.3.0, fixed at [`1f508f6083b2f823dab15de924b3bde72e08d77c`](https://github.com/makehumancommunity/makehuman/tree/1f508f6083b2f823dab15de924b3bde72e08d77c).
See the [pinned license split](https://github.com/makehumancommunity/makehuman/blob/1f508f6083b2f823dab15de924b3bde72e08d77c/LICENSE.md).
Inputs are `makehuman/data/3dobjs/base.obj` (only the `body` shell), relevant
`targets/` deltas (see the recipe), `rigs/default.mhskel` and
`rigs/default_weights.mhw`. No MakeHuman executable code, UI, ready-made dressed
character, hair/clothing, skin texture, eyes or animation is redistributed.
Glasses, hair, garment surfaces, their skinning and paint, and the review poses
were made here. Donor CC0 does **not** establish the rights to the owner's
reference or its public reuse. The attachment and the donor archive stay out of
Git; release use still needs owner approval.

## Rebuild / verify

Extract the [pinned data archive](https://codeload.github.com/makehumancommunity/makehuman/tar.gz/1f508f6083b2f823dab15de924b3bde72e08d77c)
outside the repository. Set `DONOR` to its `makehuman/data` directory and `PARTS`
to a temporary `.glb` path. Run from the repository root with Python 3.11 and
NumPy 1.26.4:

```sh
SRC=art/character_models/teacher_b
OPENBLAS_NUM_THREADS=1 python3 "$SRC/build_teacher_b.py" --makehuman-data "$DONOR"
OPENBLAS_NUM_THREADS=1 python3 "$SRC/build_teacher_b.py" --makehuman-data "$DONOR" --split-parts --output "$PARTS"
blender --background --python-exit-code 1 --python "$SRC/make_blender_source.py" -- --parts "$PARTS"
```

The Python recipe authors the batched review GLB; the `.blend` is the editable
companion to that export. If making direct Blender edits, start at frame 1, omit
the review action on export and recheck the scale, materials, bind poses and
sampled poses before replacing the review GLB. Render from the same split source
with `--render-dir builds/teacher-b-review/studio`; `compose_review.py
--studio-only` arranges those images (Pillow 11.3.0).

```sh
godot --headless --path . --import
godot --headless --path . --script res://tests/teacher_b_review_test.gd
godot --headless --path . --script res://tests/b_reveal_timing_test.gd
godot --path . --resolution 1120x720 --rendering-method gl_compatibility \
  --script res://tests/teacher_b_review_test.gd -- --capture
```

The last command needs a window. CI uses the project-pinned standard Godot and
software OpenGL and preserves the original frames and logs in the
`Teacher B asset review` artifact. Captures are an isolated comparison, not an
endorsement of a final look, navigation, foot sliding or an in-story entrance.
