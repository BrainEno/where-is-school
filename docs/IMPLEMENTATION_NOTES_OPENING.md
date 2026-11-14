# Implementation Notes — Biology Class Prologue

Scope: the second playable milestone. The player wakes at a desk in a biology
classroom, Q talks to them unprompted, the schoolbag is missing its textbook, the
room can be inspected, an anticipated confrontation is shown and explicitly
framed as imagination, the second bell rings without B, substitute N takes the
lesson and allows a free period, the player leaves for the walkway, walks out of
the school gate into a street, climbs the stair to a residential courtyard, and
meets the green animal standing at the edge of the planter. The build stops there
with an end-of-slice card. Every line the player reads is data, and the whole
slice can be switched between English and simplified Chinese while it runs.

All dialogue and object text in this milestone is new placeholder writing created
for the game. No manuscript prose is reproduced, paraphrased, or stored anywhere
in this repository.

## 1. Controls

| Input | Action |
|---|---|
| WASD / arrow keys | Camera-relative walking |
| E | Contextual interact (inspect, talk, door, stair, exit) |
| Space / Enter / left click inside the dialogue box | Continue dialogue; the first press completes a long line. A click outside the box does nothing while it is up |
| 1–9 | Pick a dialogue choice |
| Tab | Open/close the dialogue log |
| L | Switch between English and simplified Chinese, at any time |

The language choice is written to `user://settings.cfg` and survives a restart.

## 2. Ownership boundaries

~~~text
OpeningSequence (scripts/world/opening_sequence.gd)
  The prologue's steps: wake, Q, the bag wait, expectation, bell, substitute.
  Each step names the story flag that proves it is done, and the director runs the
  first step whose flag is not set — so starting and resuming are the same call.
  Holds a beat lock so two authored sequences cannot overlap.

LocationFlow (scripts/world/location_flow.gd)
  Everything that happens because of a place: blocked exits, the fade and the load,
  arrival bookkeeping, the first line a location says about itself, the end card,
  and the one door whose prompt depends on the story. Borrows the beat lock from
  the director rather than keeping a second copy of that state.

LocationCatalog (scripts/world/location_catalog.gd) + data/story/locations.json
  What a room declares about itself: its scene, the objective line on arrival, the
  first-time conversation and the flag that proves it played. Adding a location is a
  scene plus an entry here; no director code changes. `tests/location_catalog_test.gd`
  fails if a room on disk is undescribed, a door points at an undescribed id, or a
  key is missing from either language.

DialogueController (scripts/dialogue/dialogue_controller.gd)
  Presentation owner: loads content, drives the runtime, mirrors it into the panel,
  turns an inspection into one or two lines, applies first-read state changes, and
  rebinds the open conversation to the other language when the locale changes.

DialogueRuntime (scripts/dialogue/dialogue_runtime.gd)
  Graph walker with no UI knowledge. Emits line/choice events, writes flags and
  narrative entries through injected GameState/NarrativeState references.

DialogueLibrary + DialogueGraph (scripts/dialogue/*)
  Per-chapter, per-locale loading and validation. A broken file fails loudly with
  the file path and node id.

DialogueParity (scripts/dialogue/dialogue_parity.gd)
  Compares the two language trees node by node and reports any dropped node,
  choice, effect or condition.

InspectionLibrary (scripts/narrative/inspection_library.gd)
  Object descriptions, their prompts, first-read and repeat text, recollections,
  recorded knowledge entries, and once-only effects.

DialoguePanel (scripts/ui/dialogue_panel.gd)
  View only: speaker, source badge, title, body, choices, typewriter, input intents.

HUD (scripts/ui/hud.gd)
  Objective line, contextual prompt, language hint. Steps its own hint aside while
  the dialogue panel is on screen, because the panel prints the same keys.

InteractionController + Interactable (scripts/interaction/*)
  Target selection and intent. Interactables declare a payload (inspection id,
  conversation route, exit) and never open UI or decide story outcomes.
  `request_activation()` is the single intent path: input, tests, and any future
  remapping all go through it, and the interactable still decides whether it can
  be used.

LocationHost + LocationRoot (scripts/world/*)
  Location swapping, spawn markers, waypoint paths, actor and interactable lookup.

L10n (static) + Loc (autoload)
  Interface strings. `Loc.locale_changed` is what lets a switch happen without a
  scene reload.

GameState (autoload)  — named gameplay flags and snapshots.
NarrativeState (autoload) — what the protagonist knows, and how.
~~~

Dependency direction stays one-way: scenes compose, the director sequences, the
UI renders, and content lives in data files.

## 3. Narrative state model

Two separate stores, deliberately:

- **GameState** holds gameplay bookkeeping: `met_q`, `textbook_missing`,
  `bell_rung`, `class_dismissed`, `left_classroom`, `left_school`,
  `street_arrived`, `residential_arrived`, `animal_seen`, one flag per meaningful
  choice, the current objective key, and the current location id. Flag ids live in
  `scripts/narrative/story_flags.gd`.
- **NarrativeState** holds knowledge entries. Every entry is tagged with one of
  four sources: `observed`, `reported`, `recalled`, `imagined`. Entries are
  append-only and de-duplicated by id, so re-examining a prop or replaying a
  conversation cannot duplicate or overwrite what the protagonist knows.

The UI shows the category as a badge next to the speaker (`SEEN`, `HEARD`,
`REMEMBERED`, `IMAGINED`), and the badge colour follows the art-bible palette.

## 4. Subjective imagination

The expectation beat is an ordinary conversation marked `"subjective": true` and
`"default_source": "imagined"` in `data/dialogue/en/prologue.json`, plus a
full-screen tint and a banner that says what the player is looking at. The
DialogueRuntime enforces the boundary in code, not by convention:

- a subjective conversation may **not** set gameplay flags or the objective
  (attempts are rejected and logged);
- it may **not** record `observed` or `reported` knowledge;
- it **may** record `imagined` content, and `recalled` memory that surfaces while
  imagining (a memory that appears during a fantasy is still a memory, and is
  tagged as one).

The beat never moves actors, changes inventory, or alters the room. Afterwards
the banner changes to "THAT HAS NOT HAPPENED" before control returns.

## 5. Content format

Text lives in three places, each in both languages (see `docs/ARCHITECTURE.md`
§5b and `data/dialogue_schema/README.md`):

- `data/dialogue/<locale>/<chapter>.json` — conversations (`prologue`, `street`,
  `residential`), validated at load (`scripts/dialogue/dialogue_graph.gd`): unique
  node ids, resolvable `next` and choice targets, no silent `next` loops, required
  fields per effect, and known source identifiers.
- `data/inspections/<locale>/<chapter>.json` — inspectable objects: `title`,
  `prompt`, observation `text`, optional `repeat_text`, optional `recall` (a
  second line presented as a memory), optional `record`, and once-only `effects`.
- `data/locale/<locale>.json` — the short strings the interface generates:
  prompts, objective labels, source badges, speaker roles, end card.

`data/characters/*.tres` — `CharacterProfile` resources: display name, short role,
accent colour. Content refers to characters by stable id only.

Dialogue is JSON rather than typed Resources because it needs external editing,
diff review, automated validation, and two language trees that can be compared
mechanically; the loader is a single project-owned seam (`DialogueLibrary`) that a
future Dialogic adapter could replace without touching scene code.

Nothing in `scripts/` holds narrative text. The only literals left in scenes
(`prompt_text`, `end_card_title`) are fallbacks used when content is missing.

Current volume per language: prologue 7 conversations / 82 nodes, street 3 / 9,
residential 4 / 17; inspections 8 (classroom), 3 (corridor), 4 (street), 4
(residential); 38 interface strings.

## 6. Beats and triggers

1. **Wake** — black fade over 3 s, camera roll settles, the body straightens, and
   only then does control return. Objectives start as "Get your bearings".
2. **Q** — starts on its own ~0.9 s later; three choice points set distinct flags
   and produce distinct replies; the last line sets the bag objective.
3. **Schoolbag** — a real interaction; it records observed knowledge, sets
   `textbook_missing`, and shows different text on repeat visits.
4. **Inspections** — eight objects in the classroom (`classroom_blackboard`,
   `classroom_set_square`, `classroom_teacher_desk`, `classroom_window`,
   `classroom_own_desk`, `classroom_schoolbag`, `classroom_timetable_sheet`,
   `classroom_door_blocked`), each with its own text; the set square and the own
   desk also produce tagged recollections, and the blocked door explains itself.
5. **Expectation** — begins ~1 s after the bag is found, once. Bookkeeping flag
   `expectation_played` is written by the director, never by the subjective
   content.
6. **Bell** — rings ~6 s after the expectation, with a Q line; the door is
   readable as an exit but refuses until the class is dismissed. Its blocked text has
   the player feel someone watching, and someone is (#174): the door names its watcher
   (`ClassroomDoor.blocked_watcher_ids = [q]` - Q, the only person in the room while the
   door refuses; N is not in yet and the seated student is scenery), and `ExitWatch`
   turns Q's head (`NpcGaze`, after the animation; the body only for what the neck cannot
   reach) towards the player in the same frame as the text, follows them while they stay
   in the doorway, and lets go when they leave, a beat starts or the door opens. From
   the doorway Q sits near the edge of the game camera's view, so while the text is up
   the view glides the smallest share towards him (from 0.1) that keeps both faces
   inside it (`CameraRig.frame_point()`), and returns when the text closes.
   `tests/doorway_watch_test.gd` covers it.
7. **Substitute** — N walks an authored marker path to the front and takes the
   register; the conversation sets `class_dismissed` and a new objective.
8. **Exit** — the door becomes usable, the player crosses the walkway, and the
   school exit drops them into the street with an arrival line.
9. **Street** — the school wall, the notice on its pole, the gutter, the shutter,
   the bins and the lamp are all inspectable or conversational; the stair at the
   north end leads up to the residential area.
10. **Residential** — an arrival line in the courtyard; the planter, the bench,
    the washing line, the stair, two identical stained wall fragments, and the
    green animal on the planter's edge.
11. **Animal** — the first conversation sets `animal_seen` and records observed
    knowledge; meeting it again uses a shorter conversation. At the alley end an
    explicit end-of-build card closes the slice.

A reminder line from Q fires after 40 s if the bag has not been searched, and the
bell is forced after 95 s, so no player can dead-lock the slice.

Both limits, and every other pause between beats, are **story time**: they go through
`OpeningSequence.wait_seconds()`, which creates its timer with `process_always = false`,
so they stop while the pause menu has the tree paused. `create_timer()` defaults to
counting through a pause, and before this was fixed a player who spent the bag step in
the menu or the settings came back to a step that had already timed out, with the
expectation beat skipped for the rest of the run. `tests/story_pause_timing_test.gd`
holds the line, including a scan that refuses a counting-through-the-pause timer
in `scripts/world/` or in a room script under `scenes/locations/`.

## 7. Camera and target selection

The camera keeps the fixed 2.5D offset (3.4, 6.4, 3.4) with a 58° field of view.
The player body never rotates; a visual pivot turns toward travel, which keeps
camera-relative movement stable. `CameraOccluderFader` dithers any geometry in the
`camera_occluder` group that falls between the camera and the player, so a near
wall cannot hide the player when they walk up to it. The outdoor blocks are in
that group.

`InteractionController` ranks candidates by
`distance + 0.9 * (1 - facing.dot(to_target))`, skipping anything further than
2.4 m, anything the interactable refuses, and anything without line of sight. The
facing vector comes from the walking actor (`PlayerController.get_facing_direction()`),
**not** from the body's global basis — the body is never rotated, so reading its
basis silently disabled the facing weight and made the controller pick whatever
was nearest, including objects behind the player.

## 8. Validation

Godot 4.7.2 Stable, standard build. Commands:

~~~bash
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/smoke_test.gd
godot --headless --path . --script res://tests/narrative_state_test.gd
godot --headless --path . --script res://tests/dialogue_content_test.gd
godot --headless --path . --script res://tests/dialogue_runtime_test.gd
godot --headless --path . --script res://tests/dialogue_validation_test.gd
godot --headless --path . --script res://tests/i18n_test.gd
godot --headless --path . --script res://tests/language_switch_test.gd
godot --headless --path . --script res://tests/opening_flow_test.gd
~~~

What each test covers:

- `smoke_test` — main scene instantiates, the classroom loads, the player, camera,
  interaction sensor/controller, UI panels, actors, spawn and waypoint markers,
  ambience and lighting exist, and both content libraries load without errors.
- `narrative_state_test` — source isolation, de-duplication, empty-input
  rejection, snapshot round-trip.
- `dialogue_content_test` — every referenced speaker has a profile, every target
  exists, the opening has at least three choices leading to distinct nodes, the
  expectation conversation is subjective, narrative entry ids are unique, and the
  inspection data is complete.
- `dialogue_runtime_test` — walks the real opening conversation, checks choice
  flags and the objective, and proves (with a generated fixture in `user://`) that
  a subjective conversation cannot set flags, change the objective, or store
  observed/reported knowledge while still allowing imagined and recalled entries;
  also covers `once` choices.
- `dialogue_validation_test` — feeds the validator a set of deliberately broken
  fixtures (missing fields, dangling `next`, unknown source, duplicate ids) and
  requires each one to be rejected with its file and node id.
- `i18n_test` — the two locale files carry the same keys, every `L10n` lookup
  resolves, and `Loc` writes and restores the language through its settings file.
- `language_switch_test` — switches language with a conversation open and checks
  that the same node is re-presented in the other language, that the prompt, the
  objective and the backlog are re-translated, and that no state is lost.
- `opening_flow_test` — boots the real main scene with beats enabled and drives
  the whole slice headlessly: wake → Q → targeting of every authored interaction →
  locked door → schoolbag → expectation (verifying no observed knowledge appears)
  → bell → substitute → class dismissed → walkway → street → stair → courtyard →
  animal (twice) → end card.

The language-agnostic half of that coverage is UID-driven by content files, so a
mistake in the Chinese tree fails the same tests as a mistake in the English one.

That run is engine-verified logic, not a look at the game. To close that gap,
`.github/workflows/playthrough-capture.yml` runs the real build in a real window
under Xvfb (`--rendering-driver opengl3`, 1600×900), drives it with simulated key
events, and uploads the resulting frames and logs as a downloadable workflow
artifact. Pull requests verify that same artifact without writing to Git. The
older snapshots already in `docs/screenshots/` remain in place and are not updated
by Actions. `tests/capture_playthrough.gd` is the driver; it waits for a line's
typewriter reveal to finish before it photographs the screen, so a frame never
shows half a sentence.

## 9. Known limitations

- **The Chinese prose is placeholder too.** It is a working translation written
  alongside the English text and has not been reviewed by the author; the table in
  `data/dialogue_schema/README.md` (\"Lines pending author review\") lists what
  needs a decision.
- The bundled `assets/fonts/NotoSansSC-Regular.ttf` is the only third-party asset
  in the repository (SIL OFL 1.1, license text shipped next to it). Font size is
  fixed; there is no typography pass for either language.
- Every environment is a graybox: flat placeholder colours, no textures, no
  animation. The green animal is three primitives and reads as "something green"
  rather than as a creature; its design is deliberately undecided.
- Outdoor lighting is only tuned to be readable: strong flat shadows and a fog
  layer stand in for real dusk lighting. The courtyard's arrival framing is
  sparse (`docs/screenshots/17_residential.png`).
- Following `docs/ARCHITECTURE.md` §5, the dialogue technology spike was not run
  and no addon is installed; this milestone uses the small project-owned layer.
- One session save exists (#60, ADR 0005): `user://save.json` holds the flags, the
  knowledge log, the dice seed and the room the player stands in. It is written at
  beat boundaries and when a location is entered, and it is resumed at boot because
  the build has no menu. A file that cannot be read is kept, copied aside and
  reported on the end card instead of being silently replaced.
- No settings UI yet: no text size, text speed, or skip control. The language
  toggle is the first setting and it is bound to a key, not to a menu.
- Chairs are non-colliding decoration so the aisles stay readable in a graybox.
  Q and N are capsule blockouts with a flat colour; no portraits or animation.
- The capture drives the slice with teleports between scenes so it fits in CI;
  nobody has played the build with a mouse and keyboard end to end yet, so camera
  comfort and walking feel are unverified.
- `.import` files for the generated audio are intentionally not committed; the
  ambience loop is enabled at runtime instead.
- The tests that build the main scene print Godot's "2 ObjectDB instances were
  leaked at exit" and "1 resource still in use at exit" warnings. They are
  cosmetic (the engine reports them while the tree is torn down), do not fail the
  run, and have not been chased down.
- The alley behind the animal, the gate out of the estate, and the courtyard the
  animal walks towards are still to be built; the slice ends at a card.

## 10. Next steps

1. Author review of both language trees, starting with the pending-review table.
2. Add the settings pass: text size, text speed, skip, and a language menu entry.
3. Add the menu that makes "continue" and "new game" a player choice instead of a
   boot rule (ADR 0005 §7 says when to revisit this).
4. Build the alley, the estate gate and the courtyard the animal walks towards,
   keeping the same interaction, dialogue and narrative-state boundaries.
5. An art pass on the outdoor blocks (materials, lighting, the animal) once the
   beats are locked.
