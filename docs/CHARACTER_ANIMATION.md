# Character animation

The protagonist and Q use the same seven code-authored clips, built in
`scripts/actors/character_animation.gd` and resolved against each rig's own bone names at
bind time. Their production wrapper scenes bind them when instantiated. In the game, every
authored character goes through one state machine, `CharacterVisualAnimation`, fed by the
velocity its own controller already produces.

| Clip | Length | Loops | What holds it |
|---|---|---|---|
| `idle` | 2.0 s | yes | standing still: breathing, a little sway |
| `walk` | 1.0 s | yes | the body moving: enters above 0.2 m/s, leaves below 0.08 m/s |
| `jog` | 0.72 s | yes | the body moving faster than 4.4 m/s (leaves below 4.0): the player's sprint input |
| `sit_idle` | 2.4 s | yes | `set_seated(true)`: the protagonist at the desk during the wake beat |
| `wave` | 1.6 s | yes | a beat for an interaction, played by hand for now |
| `talk` | 1.2 s | yes | a beat for dialogue, played by hand for now |
| `get_up` | 1.5 s | **no** | a transition: `play_action("get_up")` stands the body up from `sit_idle` |

## How a clip becomes a pose

Each key in `CLIPS` is `[time, Vector3 of degrees]`, and those degrees are an **offset from
the bone's rest rotation**, about the bone's own axes. `CharacterAnimation.bind()` writes
`rest * offset_rotation(key)` into each rotation track.

That composition matters. A Godot `TYPE_ROTATION_3D` track *replaces* a bone's local
rotation; it does not add to the rest, and `Skeleton3D.get_bone_pose_rotation()` at rest
returns the rest rotation, not identity. On both rigs every limb hangs down its own −Y with
a rest rotation of roughly 170–180° from its parent. A key of "3° about X" written as an
absolute rotation therefore throws the arm straight up. The first runtime wiring did exactly
that, and both characters idled with their arms raised (`docs/screenshots/03j_protagonist.png`
and `03k_q_in_the_classroom.png` from before this fix).

The sign convention, measured from the GLB joints and checked by the runtime test, is that
**+X moves the far end of a hanging limb backward**:

| Joint | Flexion | Note |
|---|---|---|
| hip (`thigh`) | −X | the leg comes forward; sitting is `thigh −82` |
| knee (`shin`) | +X | the shin folds back; sitting is `shin +84` |
| shoulder (`upper_arm`) | −X | the arm comes forward |
| elbow (`fore_arm`) | −X | the hand comes forward |
| foot | +X points the toe | −X lifts it |
| spine, neck, head | +X leans and nods forward | rest is close to identity |
| any limb | ±Z reaches out to the side | +Z on `.L`, −Z on `.R` |

`jog`, `sit_idle` and `get_up` were first authored under an "+X is flexion everywhere"
reading, which came from the absolute-key bug. Their hip, shoulder and elbow keys were
negated when the keys became rest-relative; knees, feet, spine, neck and head were already
right.

`bind()` checks the "hanging" assumption per rig instead of trusting it
(`CharacterAnimation.posed_limbs()`). A limb whose rest direction is more than ~45° from
straight down has a different axis under the same name, so the clips hold it at its
modelled pose and the bind report lists it under `posed`. Rigged Q is modelled with its
right forearm held out in front, so on Q `fore_arm.R`, `hand.L` and `hand.R` are held, and
the right arm swings only from the shoulder. The protagonist has no posed limbs.

Every clip keys every bone that any clip animates. Bones a clip does not author are held at
rest, so a cross-fade always has a full pose to fade to and no bone is left where the
previous clip put it.

## Runtime wiring

- `assets/models/protagonist/protagonist.glb` and `assets/models/q/q.glb` each have a
  16-bone rigid-part skeleton. Q's unrigged input is preserved at
  `art/character_rigging/q/q_unrigged_source.glb`.
- `scenes/environment/characters/protagonist.tscn` and `q.tscn` attach
  `scripts/actors/character_visual_animation.gd` to their wrapper roots. The driver builds an
  `AnimationPlayer`, binds the clips and logs the bind report.
- Three things can hold a clip, in this order: a **one-shot action** (nothing else takes over
  until it reports `animation_finished`), then **seated** (`sit_idle`, which outranks the
  body's velocity), then **locomotion**. The locomotion decision keeps running underneath, so
  a character comes out of either into what its body is doing now.
- Locomotion is one rule for everyone:

  ```
  player, WASD           PlayerController._apply_movement()     → body velocity ┐
  player, click-to-move  PlayerController._path_direction()     → body velocity ┤
  Q following            CompanionController._apply_movement()  → body velocity ┼→ idle / walk / jog
  NPC on a route         NpcActor.walk_along()                  → reported velocity ┘
  ```

  - **Hysteresis.** Walk enters above 0.2 m/s and leaves below 0.08 m/s. Jog enters above
    4.4 m/s and leaves below 4.0 m/s. Q catching up runs at exactly 4.4 m/s, so without the
    gap it would flicker between walk and jog. Locomotion changes cross-fade over 0.18 s;
    actions and the seated pose cut, because `get_up` starts on exactly the pose `sit_idle`
    holds.
  - **Stride.** Walk plays at `speed / 1.6`, clamped to 0.7–1.9×; jog at `speed / 5.0`,
    clamped to 0.8–1.4×. Actions, idle and sitting play at 1×.
  - **Bodies.** `PlayerController` and `CompanionController` hand themselves to their
    model's animator with `bind_body()` in `_ready()`; a wrapper with no call falls back to
    its nearest `CharacterBody3D` ancestor. A body reads its velocity after
    `move_and_slide()`, so walking into a wall reads as standing.
  - **Tweens.** `NpcActor.walk_along()` has no physics velocity, so it reports each leg's
    real velocity, `(point − position) / duration`, with `report_velocity()`, and hands back
    with `clear_reported_velocity()`. `set_walking(bool)` is kept for older callers.
- **Facing stays with the controllers.** Every track is a bone rotation: no root motion, no
  position, no yaw. The player's facing remains `VisualPivot` (rotated by `atan2(facing)` in
  `_update_visual_facing`), and the wake beat owns `%Visual`'s tilt and sink. While Q walks
  it now turns towards its route (`NpcActor.turn_towards`, `walk_turn_speed`) instead of
  staring at the player. A leg swing seen side-on would otherwise read as stepping sideways.
  It turns back to the player when it stops, as before.

Accessors for tests and debugging: `get_character_animator()` on `PlayerController`,
`NpcActor` and `CompanionController`. On the animator: `get_locomotion_state()`,
`get_current_clip()`, `get_planar_speed()`, `get_bind_report()`, `get_animation_player()`,
`get_skeleton()`, `is_seated()`, `is_playing_action()` and the `locomotion_changed` signal.

## The wake beat: sitting, then getting up

The take opens asleep over a desk, so the prologue's slump is not only the pivot tilt: while
black is still coming up the model holds `sit_idle`, and the settle that straightens the
pivot is also `get_up`. `PlayerController.set_wake_pose()` above `SEATED_WAKE_POSE` (0.5)
seats the model, and coming back to 0 plays the transition, so the two halves of "waking up"
happen together. A resume from a save calls `set_wake_pose(0.0)` from an already-upright
state, which is why no get-up plays there.

## Sprinting

`PlayerController` has two speeds: `move_speed` 3.6 m/s, and `jog_speed` 5.6 m/s while the
`sprint` action (Shift) is held. Nothing tells the model which one is in use. The driver
reads the body's horizontal velocity, so acceleration through 4.4 m/s turns the walk into
the jog mid-stride. `target_speed()` is public so the difference can be asserted without a
floor to run on.

## See it

Open `scenes/dev/animation_retarget_test/animation_preview.tscn` and press **F6**.
Keys **1** idle, **2** walk, **3** jog, **4** sit_idle, **5** get_up, **6** wave, **7** talk,
**space** pause, **R** re-bind after re-importing a model. Press **4** before **5** to see
the movement the two halves make. In the game, walk around the classroom with WASD or a
click, then leave the classroom during the free period with Q along.

## Check it

- `tests/character_animation_test.gd` binds the clips to the development rigs, the
  production GLBs and the wrapper scenes. It checks that every track names a real bone, that
  each clip moves its bone and closes its loop, and that `get_up` is `LOOP_NONE`, ends on the
  rest pose and starts on the pose `sit_idle` holds. It also checks that a wrapper switches
  idle/walk/jog by speed, holds `sit_idle` against a moving body, and hands back after the
  get-up.
- `tests/runtime_character_animation_test.gd` runs against `main.tscn`: the real player,
  the real classroom, the real companion. It measures the skeletons rather than trusting a
  state name:
  - the new game boots seated (the hip folded), and `set_wake_pose(0.0)` plays `get_up` once
    and stands the protagonist in idle;
  - idle limbs are within 20° of rest, hands are below the shoulders (against each rig's own
    modelled arm), and feet are below the hips;
  - holding a movement key plays walk. The thigh swings, the foot travels forward and back
    along the facing (not sideways), knees fold only backwards and elbows only forwards (the
    sign convention above), and no hand rises to the shoulder. Releasing the key returns to
    idle with the legs back under the body;
  - a click on the floor through `PointerNavigator` walks and stops the same way;
  - the classroom Q's `walk_along()` walks, faces its path, and returns to idle;
  - Q following the player walks while its body moves, faces the way it walks, and idles
    when it stops;
  - the clips hold only bone-rotation tracks, the player's pivot stays at the controller's
    facing, and the model under it never moves.

The separate `ual_retarget` check still verifies the 42 Universal Animation Library clips
baked onto the development protagonist. That library and its baked resource remain
development-only; the game uses the seven project-authored clips above.

## Remaining limitations

- The clips are procedural prototypes, not captured or hand-animated motion, and there is
  no foot planting: at the playback ceilings the feet still slide. They need an eye in the
  editor and a pass once proportions settle.
- **The seated pose folds the legs; it does not lower the body.** No clip translates the
  hips, because clip-driven translation is root motion and the controllers are the only thing
  that moves a body. What lowers the protagonist at the desk is the pivot's 6 cm sink, so
  `sit_idle` on its own sits in the air at standing height. A real seated animation needs an
  authored hip offset (and a decision about who owns it) or a seat marker.
- Q's right forearm is held at its modelled pose in every clip, so `wave` on Q raises the
  upper arm with a rigid forearm. `wave` and `talk` are not triggered by anything in the game.
- The rigs use mostly rigid-part weights. Q's trousers blend at the joints, but neither model
  is a full deformation rig; knees, elbows and hands crease in motion.
- No facial animation, lip sync, foot IK, root motion or AnimationTree; cross-fades are the
  `AnimationPlayer`'s own.
