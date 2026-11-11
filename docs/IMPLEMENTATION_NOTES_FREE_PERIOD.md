# Implementation notes — free period, companion, walkway, yard route

This note covers the milestone that follows "Open yard, inner voices, and dice
checks". It records what was built, what was only proposed, how to check it, and
what a headless run cannot tell you.

## 1. What changed, and why

The previous milestone ended the slice in a school yard reached through an alley
behind the flats. That was the wrong order: the yard is the school's own yard, and
the free period happens inside the school. This milestone fixes the order and puts
the missing gameplay in the room where the free period is announced.

Four things were missing, and each one is now a system rather than a scene:

| Missing | Now |
| --- | --- |
| a free period the player could actually choose | `n_class` ends with stay / leave, both recorded, neither forced |
| Q as company rather than a one-off conversation | `CompanionController`, outside `LocationRoot`, follows / waits / resumes |
| things to do in the walkway | speaker cue, cleaning trolley, railing, plus the three existing inspections |
| a reason to walk to the yard | the walkway's end door, and the yard's content extended |

## 2. The stay-or-leave branch

`data/dialogue/{en,zh-CN}/prologue.json`, conversation `n_class`:

- `n_turn_2` sets `class_dismissed`, the new objective `objective.free_period`, and
  the reported entry `n_allows_free_period`. It no longer sets
  `objective.leave_classroom`.
- `n_choice` offers two options. **Leave is listed first** so a scripted walkthrough
  picks the intended path without knowing node ids; staying is one key away.
- `n_leave_1` sets `free_period_leaving`, `objective.leave_classroom` and records
  `n_leaving`. It does **not** move the player: the classroom door is still the way
  out, and the exit is already open because `class_dismissed` is set.
- `n_stay_1` sets `free_period_stayed`, `objective.stay_classroom` and records
  `n_stayed`. Control returns; the room stays inspectable and the door stays open, so
  a player who stays can still leave whenever they want.

Nothing in the branch is a cutscene, and no flag is written that the other branch
also writes, so the two free periods are distinguishable later.

Covered by `tests/free_period_test.gd` (state) and by
`tests/companion_route_test.gd` + `tests/opening_flow_test.gd` (the door).

## 3. Q as a companion

`scripts/world/companion_controller.gd`, instantiated in `scenes/main/main.tscn`.

The important decision is **where the node lives**. `LocationHost` frees everything
under `LocationRoot` on every transition, so anything authored inside a location —
including any Q placed there — disappears the moment the player walks through a door.
The companion therefore sits next to the player in the main scene and only *reports*
itself to the current location.

Behaviour:

- **join** happens on the first transition out of the classroom after
  `class_dismissed`, not on the dialogue choice, so staying and walking out later
  gives the same result. `join()` is idempotent and writes `q_companion`.
- **follow**: Q closes the gap above `follow_distance` (2.6 m), stops at
  `stop_distance` (1.8 m), and moves at 4.4 m/s — faster than the player's 3.6, so
  being left behind stays recoverable.
- **wait**: past `give_up_distance` (11 m) Q stops chasing instead of sliding along
  the floor, and the `q_ask_along` interaction switches on.
- **resume**: asking along plays the `q_ask_along` conversation and clears the
  waiting state; Q then walks back.
- **idle**: while standing, Q turns to the player and, every few seconds, looks off
  to one side. No pointing, no auto-conversation, no commentary on dice results.
- **never two Qs**: `_refresh_visibility()` hides the companion in any location that
  already has an authored actor with the same `npc_id`. The classroom has one, so
  walking back inside shows the authored Q and hides the companion.

Covered by `tests/companion_route_test.gd`, which counts visible actors in the
`npc_actor` group after every transition.

## 4. Walkway activities

New chapter `data/dialogue/{en,zh-CN}/corridor.json`, registered in
`DialogueLibrary.CHAPTERS`, plus interactables in `scenes/locations/corridor/corridor.tscn`:

| id | kind | notes |
| --- | --- | --- |
| `corridor_speaker` | conversation | a short original noise cue (`assets/audio/corridor_speaker.wav`, synthesised, no third-party audio) fires when the conversation starts |
| `corridor_trolley` | conversation | an ordinary obstruction; no dice |
| `corridor_wait` | conversation | lets part of the period pass; sets `corridor_waited` |
| `corridor_noticeboard`, `corridor_extinguisher`, `corridor_classroom_glass` | inspections | unchanged from the previous milestone |

Q chips in on two of them (`ct_q_q`, `cs_q_q`) through a plain `conditions.all_flags`
entry on the node, so "Q reacts only when Q is there" is content, not a special case
in code. The cue is played by `scripts/world/speaker_cue.gd` on the speaker node, and
it listens for `conversation_started` — the sound belongs to the prop, not to the
dialogue runtime.

None of these are required. The end door is open the whole time.

## 5. The route

```
classroom ──(stay | leave)──▶ walkway ──▶ schoolyard ──▶ end card at pg_gap_in_fence
                                 │
                                 └──▶ street ──▶ residential ──▶ alley ──▶ schoolyard
```

- The corridor gained `to_schoolyard` (exit to `playground.tscn#FromCorridor`) and a
  `FromSchoolyard` spawn point.
- The yard gained `FromCorridor` (-3, 0, -17.6) at the fire door, `pg_to_corridor`
  back into the walkway, and two new anchors: `pg_tyre_look` and `pg_container_look`.
- The alley route is untouched, so the previous milestone's walk still works and
  still ends in the same yard. Both ways in exist on purpose; the walkway is the
  short one.

Yard additions (all in `tools/build_outdoor_locations.py`, regenerate after editing):

- **tyres** stacked against the shed, plus one loose;
- an **equipment container** on two concrete pads, bar across the door, no padlock;
- **outdoor fitness gear** along the west wall (two bars, a sit-up bench);
- **birds**: three silhouettes on the fence and one wire, static and unlit.

Equivalents kept rather than replaced: the **equipment shed** from the earlier
milestone is still the "container" the checks are about, and the new container is an
addition, not a substitute. The painted court, the two hoops, the bench, the climbing
frame, the notice board, the tap, the school back wall and the far fence gap are
unchanged.

## 6. Pointer targeting and the hover cue

`scripts/interaction/interaction_controller.gd` now has two ways to choose a target,
with one explicit rule:

1. the **pointer** wins when the cursor is over an interactable that is in reach and
   not behind a wall;
2. otherwise **facing** decides, exactly as before.

A new pointer pick must hold for `mouse_hold_frames` (default 1) before it replaces a
different target. That is the whole anti-flicker mechanism: it is invisible to
someone deliberately pointing, and it swallows the jitter at a prop's edge. When the
pointer leaves everything, facing takes over on the next frame with no delay.

`Interactable.set_highlighted()` builds a small unshaded torus ring in code — no art
asset, no per-prop scene edit. `InteractionController` drives it from `_set_current`,
so the cue and `request_activation()` cannot disagree: there is exactly one place
that decides the current target and exactly one place that lights it.

Covered by `tests/interaction_hover_test.gd`, which projects interactables through
the real camera and asserts priority, the hold, the single highlight, and that
activating the current target reports the same id the cue showed.

Headless runs have no cursor, so the pointer path is dormant there and tests pin a
position with `set_mouse_override()`. The capture run uses `Input.warp_mouse` and the
real path.

## 7. One voice, provisional 2d6

- `data/abilities/abilities.json`: one ability, `orientation`, value 3, speaker
  `voice_orientation`, three passive rules.
- The four previous voices, their character profiles, and their dialogue are gone.
  The remaining voice's profile is `data/characters/voice_orientation.tres`; it is
  found from the `speaker` id the registry declares rather than from a hard-coded
  list (see `docs/ARCHITECTURE.md` §5c).
- `CheckResolver` is now `2d6 + value + modifier >= difficulty`, with `dice` (the two
  faces), `die` (their sum), `dice_count` and `die_faces` in the result.
- Difficulties in shipped content: 7, 8, 9. With value 3 that is roughly
  "usually / two in three / worth trying".
- ADR 0003 was rewritten as a **proposal**: the owner-confirmed constraints and the
  engineering proposals are listed separately, and the numbers are marked
  provisional in a table.

## 8. How to check it

Local, static (no engine needed):

```
gdparse $(git ls-files '*.gd') tests/*.gd
python3 tools/build_outdoor_locations.py   # then confirm only the playground changed
```

Engine, on CI only:

```
tests/free_period_test.gd            stay / leave state
tests/subjective_isolation_test.gd   'once' and 'check' refused, twice
tests/companion_route_test.gd        classroom → walkway → yard with Q
tests/interaction_hover_test.gd      pointer, facing, cue, E
tests/opening_flow_test.gd           the whole prologue, unchanged expectations
tests/playground_flow_test.gd        the alley route still ends in the same yard
```

Capture: `.github/workflows/playthrough-capture.yml` now shoots `13a_q_following`,
`13b_hover_trolley`, `13c_trolley_line`, `13d_corridor_speaker`,
`13e_yard_door_prompt`, `13f_schoolyard_from_corridor` and
`13g_back_in_the_walkway`, between the walkway and the street. The corridor-to-yard
transition is made by holding the forward key at the door, and the hover shot moves
the real cursor with `Input.warp_mouse`.

## 9. What is *not* verified

- **No one has played this on Windows.** Every screenshot in `docs/screenshots` was
  produced by a scripted run against a real window in CI, which is not the same as a
  human playing it: it does not judge whether Q's following distance *feels* right,
  whether the pointer rule is comfortable, or whether the cue ring reads against the
  dusk light.
- Following, waiting and resuming are asserted numerically, not visually.
- The noise cue is judged by an assertion that it played, not by an ear.
- The yard's new props are greybox boxes; they are placed to be found, not to look
  finished.

## 10. Known rough edges

- The one voice has three passive rules and six check applications. That is enough to
  test the system and not enough to show range; more content waits on an owner
  decision about voices.
- `n_class` can be replayed by a test, which re-writes the free-period flags. Nothing
  in the game replays it, but the flags are written by dialogue rather than by a
  one-shot guard.
- The companion's "ask along" prompt appears only when Q has been left more than 11 m
  behind. A player who never wanders far will never see it.
- ~~The hover cue ring is drawn at `hover_cue_height` above the interaction point, so on
  a wall-mounted prop it floats rather than hugging the object.~~ Resolved in the outline
  round: there is no ring any more; the object's own meshes are outlined, and the pointer
  finds the object where they are drawn (`docs/ARCHITECTURE.md` 5f).
