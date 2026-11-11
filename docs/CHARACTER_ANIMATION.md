# Character animation

The protagonist and Q use the same seven code-authored clips, built in
`scripts/actors/character_animation.gd` and resolved against each rig's own bone names at
bind time. Their production wrapper scenes bind them when instantiated; the editor preview
under `scenes/dev/` is still useful for inspecting the rigs, but it is no longer the only
place animation works.

| Clip | Length | Loops | What holds it |
|---|---|---|---|
| `idle` | 2.0 s | yes | standing still: breathing, a little sway |
| `walk` | 1.0 s | yes | the body moving between 0.08 and 4.4 m/s |
| `jog` | 0.72 s | yes | the body moving faster than 4.4 m/s — the player's sprint input |
| `sit_idle` | 2.4 s | yes | `set_seated(true)`: the protagonist at the desk during the wake beat |
| `wave` | 1.6 s | yes | a beat for an interaction, played by hand for now |
| `talk` | 1.2 s | yes | a beat for dialogue, played by hand for now |
| `get_up` | 1.5 s | **no** | a transition: `play_action("get_up")` stands the body up from `sit_idle` |

`walk` and `jog` are four keys per cycle — contact, passing, contact, passing — because two
keys made the legs scissor through a straight line and left the swing foot dragging.

## Which way a rotation turns

Each key's X angle is authored in *meaning*: swing the limb forward, close the joint, point the
toes down. `CharacterAnimation.x_signs()` measures the skeleton's rest pose at bind time to
find the sign that makes the rig's own local X axis do that, and `bind()` applies it. It has to
be derived, because on all four rigs here a **positive** X rotation swings a limb *backwards*:
the limb bones point down their own local +Y and their local X points to the character's right,
so `X × (−Y)` lands on `−forward`.

That was wrong until it was measured, and the wrongness was invisible. An earlier version of
this file assumed +X was flexion. It shipped a `walk` whose knees closed while the thighs were
swung forward — the character walked in a seated pose with its shins hanging under it — and a
`sit_idle` that folded both legs *behind* the hips, so the ankles ended up 27 cm above them. A
rotation signed the wrong way turns a bone by exactly the same number of degrees, so every
check that measured angles passed, and the picture on screen was the first thing to notice.

The frame is measured rather than assumed too: forward is `side × up`, `side` runs from the
left thigh to the right one, `up` from the hips to the head. On both production rigs that lands
on +Z — the side the protagonist's eyes and the toes of both shoes are on. A rig that faced the
other way would report the other sign instead of quietly animating backwards.

## Runtime wiring

- `assets/models/protagonist/protagonist.glb` has a 16-bone rigid-part skeleton.
- `assets/models/q/q.glb` is the rigged 16-bone Q derivative. The original unrigged input
  is preserved at `art/character_rigging/q/q_unrigged_source.glb`.
- `scenes/environment/characters/protagonist.tscn` and
  `scenes/environment/characters/q.tscn` attach
  `scripts/actors/character_visual_animation.gd` to their wrapper roots.
- The driver creates an `AnimationPlayer`, sets its root to the wrapper, then calls
  `CharacterAnimation.bind()`. Canonical bone aliases resolve the different imported names
  and the driver logs the binding report.
- Three things can hold a clip, in this order: a **one-shot action** (nothing else takes
  over until it reports `animation_finished`), then **seated** (`sit_idle`, which outranks
  the body's velocity), then **locomotion** read from the nearest ancestor
  `CharacterBody3D` — `idle`, `walk`, or `jog` above `jog_speed_threshold`. Tween-driven
  `NpcActor.walk_along()` calls `set_walking()` explicitly because a tween produces no
  physics velocity.
- The driver never writes position: every track is a bone rotation. `CharacterBody3D` owns
  translation, `PlayerController`'s `VisualPivot` owns the wake tilt and sink, and this node
  owns the skeleton. There is therefore no root motion in the game's characters.

## The wake beat: sitting, then getting up

The take opens asleep over a desk, so the prologue's slump is not only the pivot tilt: while
black is still coming up the model holds `sit_idle`, and the settle that straightens the
pivot is also `get_up`. `PlayerController.set_wake_pose()` above `SEATED_WAKE_POSE` (0.5)
seats the model, and coming back to 0 plays the transition, so the two halves of "waking up"
happen together instead of the model standing in the seated pose while the pivot straightens.
A resume from a save calls `set_wake_pose(0.0)` from an already-upright state, which is why
no get-up plays there.

The two clips are halves of one movement, so `tests/character_animation_test.gd` checks that
their first poses agree to within 0.5° per bone; if they drift, the body jumps on the frame
nobody is looking at.

## Sprinting

`PlayerController` has two speeds — `move_speed` 3.6 m/s and `jog_speed` 5.6 m/s while the
`sprint` action (Shift) is held — and nothing tells the model which one is in use: the
driver reads the body's horizontal velocity, so acceleration through 4.4 m/s turns the walk
into the jog mid-stride. `target_speed()` is public so the difference can be asserted without
a floor to run on.

## See it

Open `scenes/dev/animation_retarget_test/animation_preview.tscn` and press **F6**.
Keys **1** idle, **2** walk, **3** jog, **4** sit_idle, **5** get_up, **6** wave, **7** talk,
**space** pause, **R** re-bind after re-importing a model. This preview shows the development
Q rig and the retarget-ready protagonist side by side, and it plays a transition once — press
**4** before **5** to see the movement the two halves make.

## Check it

`tests/character_animation_test.gd` runs headless in CI. It checks that:

1. both rigged development models resolve the canonical bones;
2. every clip track names a bone that exists and actually moves when sampled;
3. both production GLBs have usable skeletons;
4. the real protagonist and Q wrapper scenes create their runtime players, expose all seven
   clips, switch between idle, walk and jog by speed, hold the seated clip against a moving
   body, and hand back to locomotion when the one-shot get-up finishes;
5. `get_up` is built with `LOOP_NONE`, ends on the rest pose, and starts from the pose
   `sit_idle` holds;
6. the pose each clip actually produces, measured in metres in the rig's own frame: no ankle
   above a hip, no knee bending backwards, a step whose knees close only while that thigh is
   *not* forward, feet that leave the ground, ankles that come apart with the arms
   counterbalancing, and a seated clip whose knees are in front of the hips with the shins
   hanging under them.

The separate `ual_retarget` check still verifies the 42 Universal Animation Library clips
baked onto the development protagonist. That library and its baked resource remain
development-only; the game uses the seven project-authored clips above.

## Remaining limitations

- The clips are a simple procedural prototype, not polished motion-captured or authored
  animation. They should be visually reviewed in Godot and refined after the character
  proportions and art direction settle.
- **The seated pose folds the legs; it does not lower the body.** There is no hip
  translation in any clip, because clip-driven translation is root motion and the project
  keeps the controllers as the only thing that moves a body. What lowers the protagonist at
  the desk is the pivot's existing 6 cm sink, so `sit_idle` on its own is a figure sitting
  in the air at standing height. A real seated animation needs either an authored hip
  offset (and a decision about who owns it) or a seat marker the body is placed at.
- The rigs use mostly rigid-part weights. Q's trouser sections have blended weights at
  joints, but the model is not a full expressive deformation rig; inspect knees, elbows,
  hands and silhouette in motion before treating the rig as final.
- The step clips are rotation-only, so a swinging foot rises a few centimetres instead of
  staying planted (`walk` lifts it 8 cm, `jog` 22 cm): keeping the sole on the floor wants a
  hips height track or foot IK, and both need a decision about who owns translation.
- There is no facial animation, lip sync, foot IK, root motion, or AnimationTree blend
  graph yet. Since these are bone-rotation clips cut against each other, a walk-to-jog
  change is a hard cut rather than a blend; the speed thresholds hide it, an `AnimationTree`
  would remove it.
- `wave` and `talk` exist and play, but nothing in the game triggers them yet: dialogue is
  text with no talk animation driven by it, and no interaction waves.
