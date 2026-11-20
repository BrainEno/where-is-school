# Three classmates — editable and game-ready art

[中文制作与审看说明](README.zh-CN.md)

These are three original **unplaced character assets**. The labels describe the
cast, not approved character names. There is no dialogue, portrait, location,
interaction, spawn, save-state or story change in this set.

| Asset | Bind stature | Design | Signature action |
|---|---:|---|---|
| `thin_classmate` | 1.600 m | Narrow jaw and arms, forward carriage, thin wire frames, muted blue oxford with pocket pen | `mutter` — glances away and briefly draws one hand up as if complaining under his breath |
| `gentle_classmate` | 1.620 m | Softer cheeks and fuller middle, black acetate glasses, rust knit over rolled cream oxford; not a variation of Q | `listen_offer` — listens, nods once, then offers one open palm; includes a small keyed smile |
| `court_classmate` | 1.800 m | Broad shoulders, lean face, dark-rooted red crop, steel sleeper, worn red/cream **07** jersey | `check_court` — scans off-axis and relaxes his wrist and shoulder, not a fighting animation |

The jersey's little launch mark, trim and numerals are original sewn shapes. No
professional team logo, font or likeness is used. Draped garment patterns,
shared-crotch trouser topology, eyes, spectacle arms and lenses, hair, shoes and
vertex paint are authored here and held to each separate fit. These are meshes,
not image planes. The runtime files use no texture atlas or third-party clips.

## Use in Godot

- Instance `res://assets/models/classmates/<asset>.glb` directly. The model is
  floor-origin at bind, metres, Y up, forward −Z, with no root scale. The
  `.import` sidecar enables linear vertex paint using the existing B import hook;
  clear lenses stay separate from the opaque geometry. `AnimationPlayer` is
  native to each imported scene. All assets have 57 deform joints, four
  normalized influences, and `Blink_L`, `Blink_R`, `SoftSmile`, `LipRelease`.
- Play `idle` (4 s loop), `walk_in_place` (loop), or the one-shot above.
  Walking clips contain foot cycles, not actor displacement; a controller
  using the native clips should advance at 0.89 / 0.87 / 1.11 m/s respectively.
  The lip keys are expressions, not authored phonemes or recorded dialogue.
- Optional matching in-engine look: use
  `res://scenes/dev/classmates/classmates_look.tres` with the existing
  `CharacterLookApplier` beside a `Model` node. Set `blinking = false` when
  embedded clips drive the face to avoid competing writes to the same morphs.
- Open `res://scenes/dev/classmates/classmates_review.tscn` and press F6.
  `0` lineup, `1–3` select, `Q` current-Q / friend comparison, arrows orbit,
  `F` face crop, `I` idle, `W` walk, `G` signature action, `R` bind pose.
- The unplaced assets and dev stage are excluded from release exports. As part
  of later approved placement, remove the classmate exclusion, create the
  actual actor wrapper, and register the models in the runtime audit as needed.
  Do not wire story/interaction in this art review.

## Regenerate or edit

The `.blend` files were created with Blender 4.5.3 LTS. They keep separate,
selectable surfaces grouped into hair, face/hands, eyewear, tailoring and
footwear. Frame 1 is bind; labeled timeline ranges include the three synced NLA
clips and face tracks. The models can be edited directly in Blender; Python is
also the reproducible authoring source for the checked-in runtime exports.

Download the pinned [MakeHuman archive](https://codeload.github.com/makehumancommunity/makehuman/tar.gz/1f508f6083b2f823dab15de924b3bde72e08d77c)
and unpack it outside the repository or in `build/`. Only `makehuman/data/3dobjs/base.obj`,
selected entries under `targets/`, `rigs/default.mhskel` and
`rigs/default_weights.mhw` are needed. The bundle's
[licence](https://github.com/makehumancommunity/makehuman/blob/1f508f6083b2f823dab15de924b3bde72e08d77c/LICENSE.md)
places those graphical inputs under CC0 1.0 Universal. The separate MakeHuman
application code is AGPL and is neither imported nor redistributed here.
First-party art, tailoring, animation and tools are recorded in the
[asset ledger](../../../docs/ASSET_PROVENANCE.md).

From repo root with Python 3.11, NumPy 1.26.4 and Blender 4.5 LTS:

```sh
export OPENBLAS_NUM_THREADS=1
python3 art/character_models/classmates/build_classmates.py \
  --makehuman-data /path/to/unpacked/makehuman/data --split-dir build/classmates/parts
blender -b -t 2 -P art/character_models/classmates/make_blender_source.py -- \
  --parts build/classmates/parts
```

## Evidence and checks

```sh
python3 tools/model_library.py --check
python3 tests/classmates_assets_test.py
# After the project's pinned Godot is installed:
godot --headless --path . --import
godot --headless --path . --script res://tests/classmates_review_test.gd
# Optional studio turnarounds. These are renders, not Godot captures.
blender -b -t 2 -P art/character_models/classmates/make_blender_source.py -- \
  --review-dir build/classmates/studio --samples 22
python3 art/character_models/classmates/compose_review.py \
  build/classmates/studio build/classmates/delivery  # requires Pillow
```

The studio manifest hashes the exact batched runtime GLBs it imports. This
renders front, both sides, back, three-quarter, face and signature-action
views, plus a same-scale lineup. Renders are for asset review, **not** in-game
portraits. The separate `Classmates asset review` workflow cold-imports the
same commit in Godot, checks live skin and actions, then captures the painterly
look and comparison with Q using a real viewport.
