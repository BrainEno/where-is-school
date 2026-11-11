# Character animation

The protagonist and Q now use the same four code-authored clips: `idle`, `walk`,
`wave`, and `talk`. Their production wrapper scenes bind the clips when instantiated;
the editor preview under `scenes/dev/` is still useful for inspecting the rigs, but it is
no longer the only place animation works.

## Runtime wiring

- `assets/models/protagonist/protagonist.glb` has a 16-bone rigid-part skeleton.
- `assets/models/q/q.glb` is now the rigged 16-bone Q derivative. The original
  unrigged input is preserved at `art/character_rigging/q/q_unrigged_source.glb`.
- `scenes/environment/characters/protagonist.tscn` and
  `scenes/environment/characters/q.tscn` attach
  `scripts/actors/character_visual_animation.gd` to their wrapper roots.
- The driver creates an `AnimationPlayer`, sets its root to the wrapper, then calls
  `CharacterAnimation.bind()`. Canonical bone aliases resolve the different imported
  names and the driver logs the binding report.
- The nearest ancestor `CharacterBody3D` supplies horizontal velocity. Above the
  movement threshold the driver plays `char/walk`; otherwise it plays `char/idle`.
  Tween-driven `NpcActor.walk_along()` calls `set_walking()` explicitly because a
  tween does not produce a physics velocity.

The clips are lightweight prototype keyframes authored in
`scripts/actors/character_animation.gd`, not clips embedded in either GLB. The same
resolver builds them for both rigs. It reports missing bones rather than silently
creating tracks that cannot resolve.

## See it

Open `scenes/dev/animation_retarget_test/animation_preview.tscn` and press **F6**.
Keys **1** idle, **2** walk, **3** wave, **4** talk, **space** pause, **R** re-bind after
re-importing a model. This preview shows the development Q rig and the retarget-ready
protagonist side by side.

## Check it

`tests/character_animation_test.gd` runs headless in CI. It checks that:

1. both rigged development models resolve the canonical bones;
2. every clip track names a bone that exists and actually moves when sampled;
3. both production GLBs have usable skeletons;
4. the real protagonist and Q wrapper scenes create their runtime players, expose all
   four clips, and switch between idle and walk.

The separate `ual_retarget` check still verifies the 42 Universal Animation Library
clips baked onto the development protagonist. That library and its baked resource remain
development-only; the game uses the four project-authored clips above.

## Remaining limitations

- The current walk cycle is a simple procedural prototype, not a polished motion-captured
  or authored animation. It should be visually reviewed in Godot and refined after the
  character proportions and art direction settle.
- The rigs use mostly rigid-part weights. Q's trouser sections have blended weights at
  joints, but the model is not a full expressive deformation rig; inspect knees, elbows,
  hands and silhouette in motion before treating the rig as final.
- There is no facial animation, lip sync, foot IK, root motion, or AnimationTree blend
  graph yet. Movement remains in-place and the existing CharacterBody3D controllers own
  translation and facing.
