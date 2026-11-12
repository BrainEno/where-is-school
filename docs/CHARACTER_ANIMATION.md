# Character animation

The protagonist (`Protagonist_Character.glb` since PR #118), the former protagonist (now a
seated classroom student), Q and substitute teacher N use the same seven code-authored clips
(N's idle is the exception: it is built from N's own four loops, see "Substitute teacher N"
below), built in
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
the bone's rest rotation**, about the bone's *semantic* axes (below).
`CharacterAnimation.bind()` writes `rest * F * offset_rotation(key) * F⁻¹` into each
rotation track, where F is the bone's `semantic_frame()`.

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
the right arm swings only from the shoulder. Neither protagonist has posed limbs.

### Semantic frames and positional sides (PR #118)

The keys were written against the first two rigs, whose limbs' local X is (nearly) the
character's side axis. `Protagonist_Character.glb` is not like that: measured on the
imported skeleton, its upper arms are twisted −34.8° about their own length, forearms and
hands −38.9°, feet −18.8° and clavicles −68.6°. A swing about such a bone's local X goes
partly sideways and partly round the bone, which is how arms rise and hands twist. So
`bind()` composes each key in a **semantic frame**: Y along the bone (unchanged), X the
skeleton's +X made perpendicular to the bone, Z = X × Y. F is a pure twist about the bone's
length, so it never changes where a bone points at rest; it only decides which way a key
swings it. On the legs and spines of all three rigs F is within 1° of identity, so those
keys are what they always were.

The new rig also names its limbs anatomically: `UpperArm_L` is the character's own left,
at skeleton **+X**, while the clips' `.L` has always meant the −X side (the side `Thigh.L`
is on in the first two rigs). `resolve_rig()` therefore assigns each pair by rest position,
not by name: whichever of the two resolved bones is at −X is `.L`. On the new rig all seven
pairs swap (`shoulder`, `upper_arm`, `fore_arm`, `hand`, `thigh`, `shin`, `foot`) and the
bind report lists them under `mirrored`; on the other two rigs nothing swaps.

Applying the frame changes what the first two rigs' arms do, by up to 0.16 m at the hand
(the arm swing is now in the sagittal plane instead of 16–25° off it). Their legs, spine
and head are unchanged, and the runtime and model tests measure all three rigs with the
same limits.

### Substitute teacher N: a −Z model with motion of its own

`assets/models/teacher-n/teacher-n.glb` is the first character exported facing **−Z**, as
`docs/ASSET_PIPELINE.md` §1 asks; the other three face +Z. Its skeleton has Q's sixteen
joint names, but turned half way round relative to the frame the keys were written in, so
bound like the others its walk would swing the legs backwards and sitting would fold its
knees forwards. `bind(model, player, faces_negative_z = true)` measures the side axis as
skeleton −X and decides the left/right pairs by the character's own −X side. That is
exactly what binding a copy of the model turned 180° would give, without touching the asset.
N's pairs therefore all report `mirrored` — its `UpperArm.L` drives the clips' `.R`, as on a
+Z rig turned round. The +Z rigs pass nothing and bind exactly what they did before.

N's file also carries four five-second loops the owner made in Blender:
`ST_Idle_Breathing` (spine and neck, ≤1.2°), `ST_Nervous_Posture_Shift` (spine and both upper
arms, ≤3°), `ST_Slight_Hand_Movement` (right forearm and hand, ≤10°) and
`ST_Subtle_Head_Movement` (head, ≤4.5°). They share key times and touch different parts of
the body, so they are layers of one idle, not four idles. `teacher_n.tscn` lists them in
`CharacterVisualAnimation.authored_idle_layers`, and after binding,
`CharacterAnimation.adopt_authored_layers()` replaces the procedural `idle` with their
combination: on each bone, every layer's rotation away from rest is applied in turn, sampled
at 30 Hz over the 4.96 s the keys span. Bones no layer moves are held at rest, like every
bound clip, so leaving a walk puts the legs back. The state machine never knows the
difference — it still plays `char/idle`. The keys are not retargeted, scaled or smoothed;
the only reading is that they play together, which the owner can change in the wrapper.

### The protagonist's rig

`Protagonist_Armature/Skeleton3D`, 60 bones (the skin has 60 joints, not 61), all bound by
every one of the 9 meshes. Canonical → bone, as `bind()` resolves it:

| canonical | bone | | canonical | bone |
|---|---|---|---|---|
| hips | `Pelvis` | | thigh.L / .R | `Thigh_R` / `Thigh_L` |
| spine | `Spine` | | shin.L / .R | `Shin_R` / `Shin_L` |
| chest | `Chest` | | foot.L / .R | `Foot_R` / `Foot_L` |
| neck | `Neck` | | shoulder.L / .R | `Clavicle_R` / `Clavicle_L` |
| head | `Head` | | upper_arm.L / .R | `UpperArm_R` / `UpperArm_L` |
| | | | fore_arm.L / .R | `Forearm_R` / `Forearm_L` |
| | | | hand.L / .R | `Hand_R` / `Hand_L` |

**15 joints animate**: `Spine`, `Chest`, `Neck`, `Head`, `UpperArm_L/R`, `Forearm_L/R`,
`Hand_L` (the +X hand, keyed by `wave` only), `Thigh_L/R`, `Shin_L/R`, `Foot_L/R`.
**45 stay at rest** in every clip: `Root`, the four `IK_*` targets (nothing solves IK),
`Pelvis` (no root motion, see below), `Spine_01`, `Spine_02`, both `Clavicle_*` (resolved,
but no clip keys a shoulder), `Hand_R`, the 30 finger joints (`Index/Middle/Ring/Little/
Thumb_01–03_L/R`), both `Eye_*` and both `Toe_*`. `tests/protagonist_model_test.gd` holds
the test to exactly this list.

The GLB also embeds five clips (`Idle_Breathing` 2.5 s, `Protagonist_Idle_Breathing`
4.04 s, `Slight_Posture_Shift` 3.75 s, `Subtle_Head_Movement` 3.0 s, `Protagonist_Face_Test`
4.04 s; none loops). Every one of their tracks resolves, but they are **not played**: the
imported `AnimationPlayer` has no autoplay and the wrapper drives the model with its own
`BoundAnimationPlayer`, so the two never fight over a bone. Using them (the breathing as
the idle, the face test's 9 blend shapes for expressions) is a later decision.

Every clip keys every bone that any clip animates. Bones a clip does not author are held at
rest, so a cross-fade always has a full pose to fade to and no bone is left where the
previous clip put it.

## Runtime wiring

- `assets/models/protagonist/Protagonist_Character.glb` (the player) has the 60-bone rig
  above. `assets/models/protagonist/protagonist.glb` (the classroom student) and
  `assets/models/q/q.glb` each have a 16-bone rigid-part skeleton. Q's unrigged input is
  preserved at `art/character_rigging/q/q_unrigged_source.glb`.
- `scenes/environment/characters/classroom_student.tscn` is the former protagonist as
  scenery: `start_seated = true` opens it on `sit_idle` with no body, and its `Model` is
  lowered 0.347 m so the seated soles are on the floor.
- `assets/models/teacher-n/teacher-n.glb` (substitute teacher N) has the same 16 joint
  names, faces −Z and carries four authored loops (above).
- `scenes/environment/characters/protagonist.tscn`, `q.tscn` and `teacher_n.tscn` attach
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

N is seen in the running game by `tests/capture_playthrough.gd` (the *Playthrough capture*
workflow): `11d_n_at_the_front` head to feet after the class is dismissed, `11e_n_face` the
face at one metre, and `11f_n_walking` N mid-stride, walked two metres along the front of the
room through its own `walk_along()` and put back. `11c_n_walks_in` photographs the entry walk
along `NEntryPath` itself, but only when the capture reaches it in time: the beat usually
plays while the capture is still busy with Q, and the log then says N had already arrived. Each frame is rendered a second time with N's model hidden; the share of
N's screen box that changes is logged and has to clear a floor, so a model that imported
invisible or black fails the run. Small JPEG crops of the frames are published as the
run's *teacher N crop* annotations (base64, in numbered parts).

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
  - Shift with a movement key jogs, with the same limb checks, and stopping returns to idle;
  - the classroom Q's `walk_along()` walks, faces its path, and returns to idle;
  - the classroom N is bound facing −Z, its idle is its four loops with no track left over,
    its head and spine are measured moving over a cycle, and its `walk_along()` passes the
    full walk limb checks — measured in N's own frame, so the knee and elbow signs are the
    same test as everyone else's — before returning to idle;
  - Q following the player walks while its body moves, faces the way it walks, and idles
    when it stops;
  - the clips hold only bone-rotation tracks, the player's pivot stays at the controller's
    facing, and the model under it never moves.

- `tests/character_animation_test.gd` also binds N's GLB facing −Z and checks that
  `sit_idle` brings its knees out in front of it, and — as a control — that binding it as a
  +Z model would fold them backwards, so the flag is proven to matter.
  It also checks `adopt_authored_layers()` both ways: N's four loops replace the idle with a
  looping, rotation-only clip that applies every track; a list naming a clip N does not have,
  and Q (which carries no clips of its own), are refused with a reason and leave the
  procedural idle untouched.
- `tests/protagonist_model_test.gd` is about the model swap: the new GLB's skeleton,
  hierarchy, skinning and embedded clips; the exact bone mapping and mirrored pairs on all
  three rigs, and which of the 60 joints animate; every clip track pointing at a real bone;
  each clip's limbs measured on all three rigs (seated knees forward, walking and jogging
  feet travelling along the facing, knees never backwards, elbows never backwards, hands
  below the shoulders and on their own side, no twist about a hand's or foot's length); the
  player scene showing the new model in idle; and the classroom student seated on its chair
  with no controller, collision or interaction.

The separate `ual_retarget` check still verifies the 42 Universal Animation Library clips
baked onto the development protagonist (the library ships 43; `A_TPose` is a rest pose and
is skipped). That library and its baked resource remain development-only; the game uses the
seven project-authored clips above. Its licence is recorded in
`docs/ASSET_PROVENANCE.md` — CC0 1.0 on every channel that distributes the pack — together
with the note there about Quaternius's site-wide licence and the decision to keep it out of
every build.

## Remaining limitations

- The clips are procedural prototypes, not captured or hand-animated motion, and there is
  no foot planting: at the playback ceilings the feet still slide. They need an eye in the
  editor and a pass once proportions settle.
- **The seated pose folds the legs; it does not lower the body.** No clip translates the
  hips, because clip-driven translation is root motion and the controllers are the only thing
  that moves a body. What lowers the protagonist at the desk is the pivot's 6 cm sink, so
  `sit_idle` on its own sits in the air at standing height. A real seated animation needs an
  authored hip offset (and a decision about who owns it) or a seat marker. The classroom
  student, which never stands, gets its height from its wrapper instead (`Model` at
  y = −0.347).
- The new protagonist's fingers, eyes, toes, clavicles and two of its four spine bones never
  move, and its five embedded clips and 9 blend shapes are unused (see above).
- N walks with the procedural walk (its file has none) and its idle is the owner's; the two
  were not made for each other, so the change between them is a 0.18 s cross-fade and nothing
  more. N's facial blend shapes are not shipped, and `talk` on N is as untriggered as on Q.
- Q's right forearm is held at its modelled pose in every clip, so `wave` on Q raises the
  upper arm with a rigid forearm. `wave` and `talk` are not triggered by anything in the game.
- The rigs use mostly rigid-part weights. Q's trousers blend at the joints, but neither model
  is a full deformation rig; knees, elbows and hands crease in motion.
- No facial animation, lip sync, foot IK, root motion or AnimationTree; cross-fades are the
  `AnimationPlayer`'s own.
