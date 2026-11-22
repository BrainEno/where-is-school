# Teacher B — isolated character review

[简体中文](README.zh-CN.md)

This is the editable model and review stage for B. The existing fantasy uses the
runtime GLB; the review is not her real entrance or a release approval. The
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
- Open [`teacher_b_review.tscn`](../../../scenes/dev/teacher_b/teacher_b_review.tscn)
  in Godot and press **F6**. B starts in her own idle. Click the bottom buttons
  or press **7** (Idle), **8** (Short walk), **9** (Explain). **Space** pauses or
  resumes; **R** starts the selected clip again. Press **6**, then **7–9**, to
  see a clip at gameplay distance.
- **1–6** select still views of the body, face, back, elbow/hand, stride and the
  game camera. **Left/Right** turn the figure. **Tab** switches between B and the
  current `Protagonist_Character` wrapper in views 1, 2 and 6; **M** compares B's
  matte painted finish to the GLB originals. The comparison uses the same mark,
  light and camera scale; the face view is only re-centered vertically.
- `assets/models/teacher_b/teacher_b.glb` is the meter-scale **+Y / −Z** export.
  Crown at **1.640 m**, soles at **0**, origin on the centered ankle line. It
  carries one 57-joint armature, normalized four-influence weights, inverse binds,
  vertex paint, and two authored blink targets. There are 49,466 triangles across
  13 skinned surfaces and 12 materials. The two transparent lenses are batched
  separately from the frames. No camera, light, texture, collider or action is
  stored in the GLB. Face shapes and the jaw are not a dialogue performance rig.
  The Godot import sidecar enables linear glTF vertex colors on the original
  materials; the review finish keeps those colors when it replaces materials.

The review itself changes no production room, `BPresence`, dialogue, `q_wake` or
`b_on_stage` behavior. It stages the actual classroom's backdrop and lights with
its actor, navigation and interaction branches removed. The source and review
directories stay outside release packs under the existing export rules.

**Shipped in the imagined lesson.** The GLB, its import sidecar, the look and the
motion library now live in `assets/models/teacher_b/` and ship: the classroom's
imagined lesson (`expected_b`, [IMAGINED_LESSON.md](../../../docs/IMAGINED_LESSON.md))
draws her three times with its own dream shaders instead of `teacher_b_look.tres`.
That is a placement as a fantasy, not her entrance as an actor (`BPresence.present()`
is unchanged) and not a visual or rights approval of the model.
The triangle count is descriptive, not a finish criterion: review the head,
clothing joins, gesture and readability against the **current** protagonist, not
the retired `protagonist.glb` now used by the seated student.

## Local face and hair polish

The [head study](../sculpt/README.md) tightens B's silver sweep and low chignon,
lowers the brows against the frames, and softens the cheek hollows without
removing her age lines. The split Blender source and production GLB use the same
baked strokes. The glasses, blink deltas, rig, clothes and motions are unchanged,
as are story cues and the existing imagined staging.

## Earlier silver-hair refinement

The side part and low chignon stay. Fitted, tapered locks break up the crown;
subdivided ridges and an asymmetric tuck carry the flow into the nape. The
room-keyed comb shader works in rest coordinates and keeps the existing silver
vertex pigment. The runtime mesh changes only for the hair; the old crown
height, exact bind transforms, face, clothes and walk calibration are preserved.

## B-only motion

[`teacher_b_motion.tres`](../../../assets/models/teacher_b/teacher_b_motion.tres)
is a Godot `AnimationLibrary`, not a retarget of the lead's walk. The dev
`AnimationPlayer` resolves the imported Skeleton3D and points native tracks
straight to its joints. No script drives this library in the story. The GLB
still carries no clips. The bind matrices, Blender pose checkpoints and baked Godot library
are unchanged.

| Clip | Performance | Playback |
|---|---|---|
| `idle` | Uneven standing weight, small breath and glance | 3.8 s loop |
| `walk` | Measured arm swing and four short steps, both shoes settle | 2.9 s, 0.90 m travel along −Z, one shot |
| `explain` | Left elbow and wrist lift, independent knuckles and two small beats, then hands down | 3.2 s, one shot |

The walk is an authored **start, walk, stop** for review, not an in-place
locomotion cycle and not coupled to pathfinding. Root travel and rotations are
baked at 30 Hz before key reduction; planted ankles are solved against the
measured leg lengths and sole mesh offline. Every clip writes the same track
set so switching actions does not retain displaced roots or curled fingers.
The source is [`build_teacher_b_motion.py`](build_teacher_b_motion.py). With
NumPy 2.2.6, run `python3 art/character_models/teacher_b/build_teacher_b_motion.py`
to rebuild or add `--check` to verify the committed library. No donor download
or Blender install is required for motion-only changes.

## Source and rights

The geometry recipe is first-party. The face and hand topology, morph offsets,
joint placement and seed skin masks use only the **CC0 1.0 data** of MakeHuman
v1.3.0, fixed at [`1f508f6083b2f823dab15de924b3bde72e08d77c`](https://github.com/makehumancommunity/makehuman/tree/1f508f6083b2f823dab15de924b3bde72e08d77c).
See the [pinned license split](https://github.com/makehumancommunity/makehuman/blob/1f508f6083b2f823dab15de924b3bde72e08d77c/LICENSE.md).
Inputs are `makehuman/data/3dobjs/base.obj` (only the `body` shell), relevant
`targets/` deltas (see the recipe), `rigs/default.mhskel` and
`rigs/default_weights.mhw`. No MakeHuman executable code, UI, ready-made dressed
character, hair/clothing, skin texture, eyes or animation is redistributed.
Glasses, hair, garment surfaces, their skinning and paint, the review poses
and all three development clips were made here. Donor CC0 does **not** establish the rights to the owner's
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

The Blender driver uses the `bpy` and `mathutils` APIs of the Blender 4.5 host,
not the project's Python tooling venv.

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
software OpenGL. The `Teacher B asset review` artifact has the original frames,
still comparisons, `teacher-b-motion.webp` and logs. The test samples actual
skinned sole vertices between animation keys in the staged walk; that check
is not validation of navigation, slopes, locomotion blending, or a story
entrance. Visual acceptance and runtime blink/lip sync are separate.
