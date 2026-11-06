# Implementation Notes — Biology Class Prologue

Scope: the first playable milestone. The player wakes at a desk in a biology
classroom, Q talks to them unprompted, the schoolbag is missing its textbook, the
room can be inspected, an anticipated confrontation is shown and explicitly
framed as imagination, the second bell rings without B, substitute N takes the
lesson and allows a free period, and the player leaves for the walkway where the
build stops.

All dialogue and object text in this milestone is new placeholder writing created
for the game. No manuscript prose is reproduced, paraphrased, or stored anywhere
in this repository.

## 1. Controls

| Input | Action |
|---|---|
| WASD / arrow keys | Camera-relative walking |
| E | Contextual interact (inspect, talk, door) |
| Space / Enter / left click | Continue dialogue; the first press completes a long line |
| 1–9 | Pick a dialogue choice |
| Tab | Open/close the dialogue log |

## 2. Ownership boundaries

~~~text
OpeningSequence (scripts/world/opening_sequence.gd)
  Sequenced beats only: wake, Q, expectation, bell, substitute, exit, milestone end.
  Holds a beat lock so two authored sequences cannot overlap.

DialogueController (scripts/dialogue/dialogue_controller.gd)
  Presentation owner: loads content, drives the runtime, mirrors it into the panel,
  turns an inspection into one or two lines, and applies first-read state changes.

DialogueRuntime (scripts/dialogue/dialogue_runtime.gd)
  Graph walker with no UI knowledge. Emits line/choice events, writes flags and
  narrative entries through injected GameState/NarrativeState references.

DialoguePanel (scripts/ui/dialogue_panel.gd)
  View only: speaker, source badge, title, body, choices, typewriter, input intents.

InteractionController + Interactable (scripts/interaction/*)
  Target selection and intent. Interactables declare a payload (inspection id,
  conversation route, exit) and never open UI or decide story outcomes.

LocationHost + LocationRoot (scripts/world/*)
  Location swapping, spawn markers, waypoint paths, actor and interactable lookup.

GameState (autoload)  — named gameplay flags and snapshots (existing).
NarrativeState (autoload) — what the protagonist knows, and how.
~~~

Dependency direction stays one-way: scenes compose, the director sequences, the
UI renders, and content lives in data files.

## 3. Narrative state model

Two separate stores, deliberately:

- **GameState** holds gameplay bookkeeping: `met_q`, `textbook_missing`,
  `bell_rung`, `class_dismissed`, one flag per meaningful choice, the current
  objective string, and the current location id. Flag ids live in
  `scripts/narrative/story_flags.gd`.
- **NarrativeState** holds knowledge entries. Every entry is tagged with one of
  four sources: `observed`, `reported`, `recalled`, `imagined`. Entries are
  append-only and de-duplicated by id, so re-examining a prop or replaying a
  conversation cannot duplicate or overwrite what the protagonist knows.

The UI shows the category as a badge next to the speaker (`SEEN`, `HEARD`,
`REMEMBERED`, `IMAGINED`), and the badge colour follows the art-bible palette.

## 4. Subjective imagination

The expectation beat is an ordinary conversation marked `"subjective": true` and
`"default_source": "imagined"` in `data/dialogue/opening.json`, plus a full-screen
tint and a banner that says what the player is looking at. The DialogueRuntime
enforces the boundary in code, not by convention:

- a subjective conversation may **not** set gameplay flags or the objective
  (attempts are rejected and logged);
- it may **not** record `observed` or `reported` knowledge;
- it **may** record `imagined` content, and `recalled` memory that surfaces while
  imagining (a memory that appears during a fantasy is still a memory, and is
  tagged as one).

The beat never moves actors, changes inventory, or alters the room. Afterwards
the banner changes to "THAT HAS NOT HAPPENED" before control returns.

## 5. Content format

`data/dialogue/opening.json` — conversations, validated at load
(`scripts/dialogue/dialogue_graph.gd`): unique node ids, resolvable `next` and
choice targets, no silent `next` loops, required fields per effect, and known
source identifiers. A broken file fails loudly with the file path and node id.

`data/inspections/*.json` — inspectable objects: `title`, `prompt`, observation
`text`, optional `repeat_text`, optional `recall` (a second line presented as a
memory), optional `record`, and once-only `effects` (for example, the schoolbag
sets `textbook_missing` and a new objective).

`data/characters/*.tres` — `CharacterProfile` resources: display name, short role,
accent colour. Content refers to characters by stable id only.

Dialogue is JSON rather than typed Resources for this milestone because it needs
external editing, diff review, and automated validation; the loader is a single
project-owned seam (`DialogueLibrary`) that a future Dialogic adapter could
replace without touching scene code.

## 6. Beats and triggers

1. **Wake** — black fade over 3 s, camera roll settles, the body straightens, and
   only then does control return. Objectives start as "Get your bearings".
2. **Q** — starts on its own ~0.9 s later; three choice points set distinct flags
   and produce distinct replies; the last line sets the bag objective.
3. **Schoolbag** — a real interaction; it records observed knowledge, sets
   `textbook_missing`, and shows different text on repeat visits.
4. **Inspections** — seven objects in the classroom (`blackboard`, `set_square`,
   `front_desk`, `window`, `own_desk`, `schoolbag`, `timetable`), each with its own
   text; the set square and the desk also produce tagged recollections.
5. **Expectation** — begins ~1 s after the bag is found, once. Bookkeeping flag
   `expectation_played` is written by the director, never by the subjective
   content.
6. **Bell** — rings ~6 s after the expectation, with a Q line; the door is
   readable as an exit but refuses until the class is dismissed.
7. **Substitute** — N walks an authored marker path to the front and takes the
   register; the conversation sets `class_dismissed` and a new objective.
8. **Exit** — the door becomes usable, the player enters the walkway, and the
   walkway's far end presents an explicit end-of-build card.

A reminder line from Q fires after 40 s if the bag has not been searched, and the
bell is forced after 95 s, so no player can dead-lock the slice.

## 7. Camera

The camera keeps the fixed 2.5D offset (3.4, 6.4, 3.4) with a 58° field of view.
The player body never rotates; a visual pivot turns toward travel, which keeps
camera-relative movement stable. `CameraOccluderFader` dithers any geometry in the
`camera_occluder` group that falls between the camera and the player, so a near
wall cannot hide the player when they walk up to it.

## 8. Validation

Godot 4.7.2 Stable, standard build. Commands:

~~~bash
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/smoke_test.gd
godot --headless --path . --script res://tests/narrative_state_test.gd
godot --headless --path . --script res://tests/dialogue_content_test.gd
godot --headless --path . --script res://tests/dialogue_runtime_test.gd
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
- `opening_flow_test` — boots the real main scene with beats enabled and drives
  the whole slice headlessly: wake → Q → targeting of every authored interaction →
  locked door → schoolbag → expectation (verifying no observed knowledge appears)
  → bell → substitute → class dismissed → walkway → end card.

Manual checks still required on a Windows PC with a real window: camera comfort,
collision feel in the desk aisles, prompt readability, and text pacing.

## 9. Known limitations

- Chinese dialogue is not authored yet. The default Godot font has no CJK glyphs,
  so a bundled CJK font with recorded provenance is a prerequisite for that
  localisation pass; all strings already live in data files.
- Following `docs/ARCHITECTURE.md` §5, the dialogue technology spike was not run
  and no addon is installed; this milestone uses the small project-owned layer.
- Only one save-less session exists: GameState/NarrativeState are session
  runtime state. The versioned SaveManager is still a future task, with
  `to_snapshot()`/`restore_snapshot()` kept as its data shape.
- No text-size/text-speed settings UI yet (exposed constants only).
- Chairs are non-colliding decoration so the aisles stay readable in a graybox.
- Q and N are capsule blockouts with a flat colour; no portraits or animation.
- The street route, the school gate interior, and the green-animal observation
  are **not** implemented. The walkway ends at a deliberate build card.
- `.import` files for the generated audio are intentionally not committed; the
  ambience loop is enabled at runtime instead.
- The graybox classroom is authored geometry, not final art; all materials are
  flat placeholder colours.

## 10. Next steps

1. Author approved game dialogue (and, if Chinese text is chosen, bundle a
   licensed CJK font and verify typography in-engine).
2. Add the settings pass: text size, text speed, and skip.
3. Build the gate/street transition and the animal observation as milestone 2,
   keeping the same interaction, dialogue, and narrative-state boundaries.
4. Introduce a versioned SaveManager on top of the existing snapshots.
