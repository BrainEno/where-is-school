# Character animation

The protagonist and Q use the same four code-authored clips: `idle`, `walk`, `wave` and
`talk`. In the game, idle and walk are wired: every authored character stands or walks
through the same state machine, fed by the velocity its own controller already produces.
`wave` and `talk` are built and bound but nothing in the game plays them yet.

## How a clip becomes a pose

The clips live in `CLIPS` in `scripts/actors/character_animation.gd`. Each key is
`[time, Vector3 of degrees]`, and those degrees are an **offset from the bone's rest
rotation**, about the bone's own axes. `CharacterAnimation.bind()` writes
`rest * offset_rotation(key)` into each rotation track.

That composition matters. A Godot `TYPE_ROTATION_3D` track *replaces* a bone's local
rotation; it does not add to the rest. On both rigs every limb hangs down its own −Y with a
rest rotation of roughly 170–180° from its parent, so a key of "3° about X" written as an
absolute rotation throws the arm straight up. The first runtime wiring did exactly that,
and both characters idled with their arms raised (see `03j_protagonist.png` and
`03k_q_in_the_classroom.png` from before this fix).

Conventions every key follows, measured from the GLB joints:

| Axis | Meaning on a hanging limb |
|---|---|
| +X | swings the far end **backward** (a knee bends with +X, an elbow with −X) |
| ±Z | reaches out to the side |
| Spine, neck and head | rest is close to identity, so the angles read as written |

`bind()` checks the "hanging" assumption per rig instead of trusting it
(`CharacterAnimation.posed_limbs()`). A limb whose rest direction is more than ~45° from
straight down has a different axis under the same name, so the clips hold it at its
modelled pose and the bind report lists it under `posed`. Rigged Q is modelled with its
right forearm held out in front, so on Q `fore_arm.R`, `hand.L` and `hand.R` are held. The
right arm then swings only from the shoulder. The protagonist has no posed limbs.

Every clip keys every bone that any clip animates. Bones a clip does not author are held at
rest, so the idle↔walk cross-fade always has a full pose to fade to and no bone is left
where the previous clip put it.

## Runtime wiring

- `scenes/environment/characters/protagonist.tscn` and `q.tscn` attach
  `scripts/actors/character_visual_animation.gd` (`CharacterVisualAnimation`) to their
  wrapper roots. It builds an `AnimationPlayer`, binds the clips, and runs the one
  locomotion rule:

  ```
  player, WASD           PlayerController._apply_movement()     → body velocity ┐
  player, click-to-move  PlayerController._path_direction()     → body velocity ┤
  Q following            CompanionController._apply_movement()  → body velocity ┼→ idle / walk
  NPC on a route         NpcActor.walk_along()                  → reported velocity ┘
  ```

- **Hysteresis.** A standing character starts walking above `walk_enter_speed` (0.2 m/s)
  and a walking one stops below `walk_exit_speed` (0.08 m/s), so the last centimetres of a
  deceleration do not flicker between clips. Clips cross-fade over `blend_time` (0.18 s).
- **Stride.** While walking, the clip plays at `speed / stride_speed` (1.6 m/s), clamped to
  0.7–1.9×. The player at 3.6 m/s and Q catching up at 4.4 m/s both hit the 1.9× ceiling.
  Their feet still slide somewhat; see the limitations below.
- **Bodies.** `PlayerController` and `CompanionController` hand themselves to their
  model's animator with `bind_body()` in `_ready()`. A wrapper with no call falls back to
  its nearest `CharacterBody3D` ancestor. A body reads its velocity after
  `move_and_slide()`, so walking into a wall reads as standing.
- **Tweens.** `NpcActor.walk_along()` has no physics velocity, so it reports each leg's real
  velocity, `(point − position) / duration`, with `report_velocity()`. It hands control
  back with `clear_reported_velocity()` at the end. `set_walking(bool)` is kept for older
  callers.
- **Facing stays with the controllers.** The clips contain bone-rotation tracks and nothing
  else: no root motion, no position, no yaw. The player's facing remains `VisualPivot`
  (rotated by `atan2(facing)` in `_update_visual_facing`), and the wake beat still owns
  `%Visual`'s tilt. While Q walks, it now turns towards its route
  (`NpcActor.turn_towards`, `walk_turn_speed`) instead of staring at the player. A leg
  swing seen side-on otherwise looks like stepping sideways. Q turns back to the player
  when it stops, as before.

Accessors used by the tests and handy when debugging: `get_character_animator()` on
`PlayerController`, `NpcActor` and `CompanionController`. On the animator itself:
`get_locomotion_state()`, `get_planar_speed()`, `get_bind_report()`,
`get_animation_player()`, `get_skeleton()` and the `locomotion_changed` signal.

## See it

Open `scenes/dev/animation_retarget_test/animation_preview.tscn` and press **F6**.
Keys **1** idle, **2** walk, **3** wave, **4** talk, **space** pause, **R** re-bind after
re-importing a model. In the game, walk around the classroom with WASD or a click, then
leave the classroom during the free period with Q along.

## Check it

- `tests/character_animation_test.gd` binds the clip table to the development rigs, the
  production GLBs and the wrapper scenes. It checks that every track names a real bone,
  that each clip moves the bone it is about and closes its loop, and that a wrapper
  switches between idle and walk.
- `tests/runtime_character_animation_test.gd` runs against `main.tscn`: the real player,
  the real classroom, the real companion. It measures the skeletons rather than trusting a
  state name:
  - idle limbs are within 20° of rest, hands are below the shoulders (against each rig's
    own modelled arm), and feet are below the hips;
  - holding a movement key plays walk. The thigh swings, the foot travels forward and back
    along the facing (not sideways), knees fold only backwards and elbows only forwards
    (this checks the +X sign convention above), no hand rises to the shoulder, and releasing
    the key returns to idle with the legs back under the body;
  - a click on the floor through `PointerNavigator` walks and stops the same way;
  - the classroom Q's `walk_along()` walks, faces its path, and returns to idle;
  - Q following the player walks while its body moves, faces the way it walks, and idles
    when it stops;
  - the clips hold only bone-rotation tracks, the player's pivot stays at the controller's
    facing, and the model under it never moves.

## Remaining limitations

- The walk is a four-phase procedural cycle, not authored or captured motion, and there is
  no foot planting. At the 1.9× playback ceiling the feet still slide relative to the
  floor. It needs an eye in the editor and a pass once proportions settle.
- Q's right forearm is held at its modelled pose in every clip (see above), so `wave` on Q
  raises the upper arm with a rigid forearm. Wave and talk are not wired into the game yet.
- The rigs use mostly rigid-part weights. Q's trousers blend at the joints, but neither
  model is a full deformation rig, so knees, elbows and hands crease in motion.
- No facial animation, lip sync, foot IK, root motion or AnimationTree.
