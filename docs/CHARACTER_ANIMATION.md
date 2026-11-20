# Character animation

The protagonist (`Protagonist_Character.glb` since PR #118), the former protagonist (now a
seated classroom student), Q and substitute teacher N use the same semantic clip library.
Each ships its own `CharacterMotionProfile`; N's idle and Q's idle/talk still use layers
supplied by their models. Q also exposes four native rotation actions without replacing
locomotion. `scripts/actors/character_animation.gd` resolves the clips against each rig's
own bone names. Their production wrappers use one driver, `CharacterVisualAnimation`,
with the velocity their existing controllers already produce (none for the seated student).

| Clip | Base length before profile | Loops | What holds it |
|---|---|---|---|
| `idle` | 2.0 s | yes | standing still: breathing, a little sway |
| `walk` | 1.0 s | yes | the body moving: enters above 0.2 m/s, leaves below 0.08 m/s |
| `jog` | 0.72 s | yes | the body moving faster than 4.4 m/s (leaves below 4.0): the player's sprint input |
| `sit_idle` | 2.4 s | yes | `set_seated(true)`: the protagonist at B2 during the wake beat; also the student at A1 |
| `sit_talk` | 2.4 s | **no** | A1 replying in a real conversation: a look up and a small lift of one forearm, then hold; not an action lock |
| `wave` | 1.6 s | yes | a beat for an interaction, played by hand for now |
| `talk` | 1.2 s shared | yes | Q or N as the visible speaker in real dialogue, only while standing still |
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
that, and both characters idled with their arms raised (the historical frames `docs/screenshots/03j_protagonist.png`
and `03k_q_in_the_classroom.png`, from before this fix).

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
modelled pose and the bind report lists it under `posed`. The retired 16-joint Q needed
that guard; the approved 60-joint replacement does **not**. Its forearm down-cosines exceed
0.7, all semantic bones resolve, and neither arm nor hand is frozen. Neither protagonist
has posed limbs either.

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
bind report lists them under `mirrored`. New Q uses the same anatomical convention and
also swaps all seven pairs; the former protagonist keeps its original sides.

Applying the frame changes what the first two rigs' arms do, by up to 0.16 m at the hand
(the arm swing is now in the sagittal plane instead of 16–25° off it). Their legs, spine
and head are unchanged, and the runtime and model tests measure all three rigs with the
same limits.

### Substitute teacher N: a −Z model with motion of its own

`assets/models/teacher-n/teacher-n.glb` is the first character exported facing **−Z**, as
`docs/ASSET_PIPELINE.md` §1 asks; the other three face +Z. Its skeleton has the former Q's sixteen
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

### Q: approved 60-joint replacement with native hands

`assets/models/q/new-Q.glb` is the sole production Q. Its rig is measured independently,
not inferred from the shared naming with the protagonist: root `Q_Armature`, 60 skin joints,
`Root → Pelvis → Spine → Spine_01 → Spine_02 → Chest`, `Chest → Clavicle_L/R → UpperArm →
Forearm → Hand`, five three-joint fingers per hand, and `Chest → Neck → Head`. Both hands'
30 finger joints carry weights. The source, bind/rest comparison and old-Q retirement are
recorded in [Q_MODEL_MIGRATION.md](Q_MODEL_MIGRATION.md).

The wrapper keeps the shared states and the existing `BoundAnimationPlayer` contract:

| Bound state/action | Supplied layers / authoring |
|---|---|
| `idle` | `Q_Idle_Breathing` + `Q_Slight_Body_Lean`, with Q's standing calibration |
| `talk` | `Q_Casual_Hand_Gesture` + `Q_Idle_Breathing`; shoulder, elbow, wrist and all fifteen right-finger joints move |
| `walk`, `jog`, `sit_idle`, `get_up`, `wave` | Shared semantic/rest-relative clips rebound to the measured new rig; no old rig tracks reused by path |
| `head_movement`, `hand_gesture`, `body_lean`, `pose_preview` | The corresponding native `Q_Head_Movement`, `Q_Casual_Hand_Gesture`, `Q_Slight_Body_Lean`, `Q_Pose_Preview`; preview is the supplied one-key diagnostic, never used for idle or locomotion |
| `Q_Face_Test` (source player) | Supplied 13-morph facial diagnostic, retained in the imported model; explicit development preview only, not an automatic talking-mouth/lip-sync claim |

`authored_clip_layers` opts in by bound name; old characters have an empty map.
`adopt_authored_layers()` composes rotations relative to each bone's actual rest pose,
not the old Q bind. `complete_pose_resets()` gives **every clip the union of animated
bone tracks**, including both hands' fingers, clavicles and pelvis. Switching from a curled
native gesture/pose into a shared walk therefore resets the extra joints instead of
leaving stale rotations behind. No `AnimationTree`, root motion or new controller is added.

`CharacterDialogueAnimation` matches the presented speaker to a **visible** `NpcActor` (including
its companion incarnation), or to an explicitly registered static visual. A1 registers
`dialogue_speaker_id = &"student"` and opts into `seated_dialogue_clip = "sit_talk"`. Q and N
still use `dialogue_clip = "talk"` when standing. Subjective lines do not animate an onstage
character. Actions retain precedence, then sitting (with or without speech), then moving,
then standing speech or idle. A different speaker, closing the panel or hiding the visual
clears speech. Consecutive lines by the same speaker do not restart the gesture. `NpcGaze` remains
a post-animation skeletal modifier on the measured Spine/Neck/Head chain (the chest follows
the spine); existing doorway-watch tests continue to cover it.

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

### Per-character motion resources

`CharacterMotionProfile` is plain data in `assets/characters/`. Writers can replace individual
semantic curves with `clip_tracks`, or keep the shared keys and layer on top. Unlisted tracks
fall back to the shared clip; empty/null profiles are the identity.

```
offset(t) = amplitude × (authored or fallback key)(t) + layer(t) + posture × posture_weight(clip, t)
```

Use the base clip's seconds in `clip_tracks`: the binder writes keys at `t × tempo`. Include
both endpoints, in increasing order, with equal first/last offsets for a loop. The binder
checks that before creating animations. The named bones must be in the shared animated set
and pass the same posed-limb guards, otherwise they appear in `profile_ignored`. A profile
can move a bone held at rest in that particular clip, but cannot add tracks for new joints.
Native Q actions still use the source bones and full-pose resets. N's native idle is not
replaced or scaled by its profile.

| Wrapper profile | Personality as seen in motion |
|---|---|
| `protagonist/protagonist_motion.tres` | Asymmetric, held-in walk; upper-arm keys ×0.85 and forearm keys ×0.82 on `walk` only. The original key times, legs and additive slump remain. Jog adds two forward pulses; idle, seated posture and staged actions are unchanged by the walk trim. |
| `q/q_motion.tres` | Looser shoulders and a delayed elbow over a quicker weight transfer, with the head counter-turning. Jog has a wider torso turn and its own elbow timing. Same resource in the classroom and on the follower. Keeps native breathing/lean, speech hand and finger motion and diagnostic actions. |
| `teacher_n/teacher_n_motion.tres` | Close, measured steps with small arm travel. At the lectern, `n_class` lines for N drive a 3 s cycle with a nod, one low hand prompt behind the lectern lip, and a pause. An actual change of speaker/close blends back to the four embedded idle layers. |
| `classroom_student/student_motion.tres` | A 7.2 s recitation loop: two small downward beats, a sleeve shift and a pause. For the reply, a delayed glance toward the aisle and one small forearm lift return to the desk. Hips, shins and boots share the same planted pose across both clips. |

All four `sit_idle` first poses agree with their `get_up` first pose. Only the protagonist
runs the B2 action/contact tracks; its seat pose, global posture data and staged actions
are unchanged. Idle and speech still play at ×1; tempo changes the bound resource duration,
not the controller speed. The production tests measure full loop closure, differences in
arm travel independent of clip length, knee/elbow directions and ground-relative seat
contacts. On the production protagonist, `character_animation_test.gd` also samples both
wrists and feet through the bound walk, with and without the two arm multipliers, to
check less wrist travel without a stride or cadence change. See
[CHARACTER_ART.md](CHARACTER_ART.md) for the visual direction.

## Runtime wiring

- `assets/models/protagonist/Protagonist_Character.glb` (the player) remains unchanged.
  `assets/models/protagonist/protagonist.glb` (the classroom student) retains its 16-bone
  rigid-part skeleton. Q alone uses the separately approved 60-joint `new-Q.glb`, built
  reproducibly from `art/character_models/q/new-Q_source.glb` by `tools/prepare_q.py`.
- `scenes/environment/characters/classroom_student.tscn` keeps a visual-only rig:
  `start_seated = true` opens on `sit_idle` with no body, and `Model` is lowered 0.347 m
  so the soles are on the floor. The separate `StudentTalk` anchor in the classroom
  reuses the existing route. Its `CameraShot` only engages after reaching the student,
  keeping the performance above the reading band; closing the reply releases the shot.
  Leave after the short reply or wait for the original exchange.
- `assets/models/teacher-n/teacher-n.glb` (substitute teacher N) has the same 16 joint
  names, faces −Z and carries four authored loops (above). Its wrapper has a `Look` applier
  as described in [CHARACTER_INTEGRATION.md](CHARACTER_INTEGRATION.md).
- `scenes/environment/characters/{protagonist,q,teacher_n,classroom_student}.tscn` attach
  `scripts/actors/character_visual_animation.gd` to their wrapper roots. The driver builds an
  `AnimationPlayer`, binds the clips with the wrapper's `motion_profile` and logs the bind report.
- Three things can hold a clip, in this order: a **one-shot action** (nothing else takes over
  until it reports `animation_finished`), then **seated** (`sit_idle` or the opted-in
  `sit_talk`, which both outrank the body's velocity), then **locomotion**. Only an idle opted-in character can show standing
  speech. Locomotion keeps running underneath, so a character comes out of an action/seat
  into what its body and dialogue presentation are doing now.
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
  - **Stride.** Walk plays at `speed / stride_speed`, clamped to 0.7–1.9×. N uses
    `stride_speed = 1.4` rather than 1.6 m/s to fit her shorter steps; her route speed is
    unchanged. Jog uses `speed / jog_stride_speed` (5.0 m/s by default), clamped to
    0.8–1.4×. Idle, sitting and speech play at 1×.
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

The take opens asleep over the desk. `set_wake_pose(1.0)` starts the slump;
`settle_wake_seated_pose()` straightens it on the same seat while Q talks. In the
real classroom, `DeskB2/Chair/SeatMark` is the floor mark for the capsule, and the
seat mesh's top sets the visual hip height. The actor driver does not lower the
physics body. Boot contacts keep the soles level while the character breathes.

The protagonist's `classroom_rise` and `classroom_sit` are sampled on the same
clock as the chair slide, visual hip motion and two-bone contacts. The rise
loads the feet before lifting, then hands off to the already requested movement.
For a return, the room finds a capsule-clear path to the mark, faces the desk,
and draws the chair under the hips before the final settle. A fixture seated
away from that mark still uses the shared `get_up`; `set_wake_pose(0.0)` on a resume
resets directly to standing without replaying a transition.

`schoolbag_search` uses the same contacts on the feet and wrists while one hand
steadies the opening and the other lifts the flap, checks the lining and pocket,
and closes it. The room runs the beat through `StagedInteractable`; the original
`classroom_schoolbag` inspection (including its effects and record) is displayed
only after this pose is released. If the search mark is obstructed, the original
inspection stays available without a walk through scenery.

[The live-window capture](../tests/capture_classroom_motion.gd) verifies seat
contact and the two approach sides and exercises the real pointer and inspection.

## Sprinting

`PlayerController` has two speeds: `move_speed` 3.6 m/s, and `jog_speed` 5.6 m/s while the
`sprint` action (Shift) is held. Nothing tells the model which one is in use. The driver
reads the body's horizontal velocity, so acceleration through 4.4 m/s turns the walk into
the jog mid-stride. `target_speed()` is public so the difference can be asserted without a
floor to run on.

## See it

Open `scenes/dev/animation_retarget_test/animation_preview.tscn` and press **F6**.
Keys **1** idle, **2** walk, **3** jog, **4** sit_idle, **5** get_up, **6** wave, **7** talk;
Q-only: **8** head movement, **9** hand gesture, **0** body lean, **P** pose preview, **F** face test;
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

For fixed-camera phase strips and the original viewport PNGs, use the `cast-motion` job in
[Character integration capture](../.github/workflows/character-integration-capture.yml), or run:

```bash
xvfb-run -a --server-args="-screen 0 1600x900x24" godot --path . --resolution 1600x900 \
  --rendering-driver opengl3 --script res://tests/capture_character_integration.gd -- \
  --group=motion --variants=after
```

These are staged samples, not live locomotion or a geometry/paint comparison. The stride
strip samples actual bound walk poses at matching normalized phases in the real classroom;
N samples the `talk` entered on a visible `n_class` line at the lectern, and the student
samples `sit_idle` at the placed A1 desk. Each strip keeps the game camera angle, lens and
crop. The real routes and controller timing are asserted by the tests below.

- `tests/character_animation_test.gd` binds the clips to the development rigs, the
  production GLBs and the wrapper scenes. It checks that every track names a real bone, that
  each clip moves its bone and each loop closes, and that `get_up` is `LOOP_NONE`, ends on
  the rest pose and starts on the pose `sit_idle` holds. A1's non-looping answer preserves
  all six loaded leg joints and returns to the reciting state when hidden. It also checks that a wrapper switches
  idle/walk/jog by speed, holds `sit_idle` against a moving body, and hands back after the
  get-up.
- `tests/runtime_character_animation_test.gd` runs against `main.tscn`: the real player,
  the real classroom, the real companion. It measures the skeletons rather than trusting a
  state name:
  - the new game boots seated, and movement plays `classroom_rise` before walking;
    the fixture without furniture checks that `get_up` still shares its clock with the pivot;
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
  and the former protagonist (which carries no clips of its own), are refused with a reason
  and leave the procedural idle untouched. The no-clips negative control was moved from Q
  because the approved replacement now genuinely contains six actions.
- `tests/protagonist_model_test.gd` is about the model swap: the new GLB's skeleton,
  hierarchy, skinning and embedded clips; the exact bone mapping and mirrored pairs on all
  three rigs, and which of the 60 joints animate; every clip track pointing at a real bone;
  each clip's limbs measured on all three rigs (seated knees forward, walking and jogging
  feet travelling along the facing, knees never backwards, elbows never backwards, hands
  below the shoulders and on their own side, no twist about a hand's or foot's length); the
  player scene showing the new model in idle; and the classroom student seated on its chair
  without a controller or solid body. It checks the separate `StudentTalk` anchor and
  samples the full reciting loop: head travel of at least 12°, both hips and ankles
  within 2 mm of their starting contacts.
- `tests/capture_classroom_motion.gd` drives mouse and touch through the real world input,
  including a walk to A1 from outside reach. It captures the seated reply and return to
  reciting, with checks for short and longer branches, speech cues and return of control.
- `tests/n_presence_test.gd` watches the actual entry play N's walk, then follows speakers
  in `n_class` and checks that N stops gesturing on other lines and when the panel closes;
  it samples projected wrists/hand tips against the lip at the actual stand. The
  existing lectern, re-entry and save checks still apply.

- `tests/q_model_prepare_test.py` proves approved-source hash, reproducibility, all mesh,
  weight, bind and morph data, all non-rest action channels, five weighted fingers per
  hand, and retirement of every obsolete Q-only model.
- `tests/q_model_test.gd` checks the actual imported Q wrapper/skin/materials/native clips,
  full cross-state reset tracks, moving finger/head/forearm joints, and the real `q_wake`
  presentation through `main.tscn`, including talk → walk → talk → idle.
- `tests/capture_q_migration.gd` and `q-model-capture.yml` capture actual before/after
  `main.tscn` views at the fixed task base and current head, using one camera script,
  plus a real route walk sequence. See [Q_MODEL_MIGRATION.md](Q_MODEL_MIGRATION.md).

The Universal Animation Library (UAL), its baked library and the dedicated bake/preview
have been retired from the current tree (#64). Neither the game nor the first-party preview
above used them. `tests/animation_retarget_test.gd` now checks the generic retarget algorithm
with two synthetic rigs and original test clips: semantic mapping, target track paths, actual
movement and preservation of rotation changes relative to each rest pose. The separate
production animation tests above still run. See the [asset audit](ASSET_LICENSE_AUDIT.md)
for the licence history and the distinction between removal and clearance.

## Remaining limitations

- The shared locomotion loops are procedural, with no foot planting: at the playback
  ceilings the feet still slide. The classroom contacts apply only to its staged beats.
- **The shared seated clip does not lower the body.** At the desk the real chair owns the
  marker and the protagonist owns visual height; the other seated student, which never
  stands, gets its height from its wrapper (`Model` at y = −0.347).
- The new protagonist's fingers, eyes, toes, clavicles and two of its four spine bones never
  move, and its five embedded clips and 9 blend shapes are unused (see above).
- N walks with the procedural walk (its file has none) and its idle is the owner's; the two
  were not made for each other, so the change between them is a 0.18 s cross-fade and nothing
  more. N's facial blend shapes are not shipped. The A1 reply is posture and gesture,
  not lip sync or voice acting.
- Q's source gestures and the shared walk were not authored as one motion set; transitions
  use the existing 0.18 s fade plus complete reset tracks, not foot planting or corrective
  deformation. Wave is available as an explicit action/preview, not a new story beat.
- No geometry, weights or large-shape sculpt was changed on Q. Head/neck, shoulder, palm,
  thumb and finger shape quality still need owner review of the real motion frames; a
  structural/import pass is not visual acceptance.
- No facial animation, lip sync, foot IK, root motion or AnimationTree; cross-fades are the
  `AnimationPlayer`'s own.
