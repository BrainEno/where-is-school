# Biology Class Prologue — Implementation Notes

Scope note: this document describes the first playable milestone (Beats A–G) and
the second milestone (the residential street and the green-animal observation).
It is implementation-facing. It contains no source-manuscript material.

## 1. Ownership

| Concern | Owner | Notes |
|---|---|---|
| Story flags | `GameState` autoload (unchanged) | Flags are declared once in `scripts/narrative/prologue_flags.gd`. |
| Flag identifiers | `PrologueFlags` | Static constants; treated as save-data contracts. |
| Narrative record | `NarrativeLedger` (plain `RefCounted`) | Append-only, provenance-tagged. No scene access, so it is unit-testable. |
| Provenance kinds | `NarrativeProvenance` | `observed` / `heard` / `recollected` / `imagined`. |
| Conversation data | `data/dialogue/*.gd` | Authored dialogue graphs. No gameplay code. |
| Conversation runtime | `DialogueSession` | Traverses a graph, keeps the backlog. Emits no UI. |
| Beat orchestration | `PrologueFlow` | The only node that turns dialogue state into flags, records, and room changes. |
| Location loading | `PrologueDirector` | Which room is live, and where the player spawns. |
| Geometry / props | `scenes/locations/*` | Each location owns its own interactables and spawn markers. |
| Player movement + camera | `PlayerController` | Keeps the 2.5D rig local to the player scene. |
| Targeting | `InteractionSensor` + `Interactable3D` | The sensor reports what is in reach; the interactable reports its own id. |
| Presentation | `DialoguePanel`, `PrologueHud`, `NoteBook` | Render only. Never read or write story state. |
| Ambience | `RoomTone` | Synthesised at runtime; no audio assets are shipped yet. |

Dependency direction is one-way: presentation → flow → data/narrative. Data files
never import scene code, and no UI node writes a flag.

## 2. Interaction contract

`Interactable3D` (Area3D) exposes `interact_id`, `kind`, and prompt text. It emits
`interacted(self)` and knows nothing else. `InteractionSensor` lives under the
player, finds the nearest enabled interactable inside a sphere, and republishes it
via `focus_changed`. `PrologueFlow` receives that signal and dispatches:

- `INSPECT` → builds an inspection `DialogueScript` from `ClassroomInspections`
- `TALK` → builds the speaker's conversation
- `DOOR` → checks whether the room has been released, then loads the corridor
- `THRESHOLD` → loads the adjacent location (or starts the street beat)
- `SIT` → short refusal line; the chair is a memory, not a seat

Because every interactable registers in the `interactable` group, the smoke test
can assert that a required prop (for example the schoolbag) still exists after a
scene edit.

## 3. Dialogue contract

`DialogueScript` → `DialogueNode` → `DialogueLine` / `DialogueChoice`. All three
are plain `RefCounted` objects, so a whole conversation can be built and validated
in a headless test with no scene tree.

- Each line declares a speaker id and a **provenance kind**.
- Each choice declares its own flags, ledger records, and optional protagonist
  aside. Choices that must not converge point at different nodes, and a test
  asserts that the opening conversation does not collapse to one target.
- `DialogueScript.validate()` reports dangling continuations, unknown speakers,
  missing text in either language, duplicate ids, and invalid provenance. Content
  that fails validation is never played: `PrologueFlow` logs every problem and
  refuses to open the panel.
- `DialogueSession` keeps a backlog of every line already read, which the panel
  renders on the history key.

Choices do not apply themselves. `PrologueFlow` applies flags and records first,
then follows the continuation, which is why the flag order in a test is
deterministic.

## 4. Narrative-state boundaries

The ledger is the mechanism that keeps four different things apart:

| Kind | Example from this slice | Written as |
|---|---|---|
| `observed` | The schoolbag contains no biology textbook. | fact |
| `heard` | Q says the last exam paper was sent back for recalculation. | claim |
| `recollected` | "I might remember the crooked desk he described." | uncertain memory |
| `imagined` | The confrontation with B that the protagonist rehearses. | never happened |

Rules enforced in code:

1. `NarrativeLedger.has_observed()` is true only for entries whose kind is
   `OBSERVED`. Hearsay, memory, and imagination are excluded by construction.
2. The imagined sequence has its own presentation mode. While it plays, the panel
   dims and cools, a caption states that this did not happen, and the flow records
   `imagined_confrontation` as `IMAGINED`. The integration test asserts that the
   player's position, the current location, and Q's conversational state are
   unchanged across the sequence.
3. Ledger entries are append-only by id. Re-inspecting an object rewrites nothing,
   so revisiting a prop cannot manufacture a second, contradictory "fact".
4. B never appears, is never voiced, and no flag encodes her behaviour or
   motives. The set square is described only as a worn object that a teacher
   left out; Q's account of her is heard, not confirmed.

## 5. Beat sequence and where it lives

| Beat | Trigger | Code |
|---|---|---|
| A. Wake | `PrologueDirector.start_prologue()` | `wake_duration` input lock, then `AWAKENED` + `CONTROL_RETURNED` |
| B. Q talks | timer after control returns | `PrologueQConversation`, started without an interaction |
| C. Schoolbag | `bag` interactable | `ClassroomInspections._bag()`, sets `TEXTBOOK_MISSING` |
| D. Inspect | `set_square`, `teacher_desk`, `timetable`, `window`, `chair` | one `DialogueScript` per object |
| E. Anticipation | `desk_think` pseudo-interactable, enabled after Q's conversation | `PrologueAnticipation` |
| F. Substitution | end of the anticipation beat | bell → absence → `NActor` enters → `PrologueNConversation` |
| G. Leave | `classroom_door`, only after the release | corridor → stairwell threshold → street |
| Street | `street_gate` | `StreetObservations` (green animal, unresolved) |

`desk_think` is deliberately not another object. It is the empty space at the
front of the room, which is what the protagonist is actually looking at. It is
disabled until Q has stopped talking, so Beat E cannot pre-empt Beat B.

## 6. Camera framing contract

The prologue uses one fixed 2.5D angle for the whole slice: yaw 40°, pitch 44°,
distance 8.4 m, from above and outside the room. That imposes three rules on the
classroom blockout, and they are documented at the top of the scene's authoring
source:

1. The camera looks toward the (-x, -z) corner, so everything the player must read
   is on the far walls: blackboard on the far-left wall, window on the far-right
   wall, teacher's desk at the front.
2. The doorway to the corridor is in the *east* wall (facing the camera) rather
   than the near wall, so the exit is never hidden behind the camera's own
   viewing direction.
3. There is no ceiling and the near wall is a 1.1 m parapet. A ceiling would
   occlude the entire floor from this angle, and a full-height near wall would
   hide the player whenever they walked to the back of the room.

The corridor repeats the pattern: it runs west→east, the classroom door is at the
near end, and the stairwell threshold is at the far end, so the route is legible
from the camera's fixed angle.

## 7. Layout reference

`docs/images/classroom_blockout_plan.png` is a top-down plan of the classroom
generated from the authored scene geometry (mesh transforms and interactable
positions read out of `classroom.tscn`), with the fixed camera angle drawn on it.
It is a reference figure, not concept art: it documents where the door, the
teacher's desk, the students and every interactable actually are, and it is how
the framing rules in section 6 were checked.

At the time of this milestone the sandbox used to validate the project had no GPU
and no display server (only Godot's dummy renderer), so a real in-engine
screenshot could not be captured. The plan above plus the automated flow and
reachability tests are the substitute; an in-engine capture is listed as
follow-up work in the PR.

## 8. Language

The game ships in **Simplified Chinese** and **English**, and shows exactly one
of them at a time. There is no stacked bilingual view and no mixed page: a line,
a choice, an aside, a notebook group heading, and the interaction prompt each
render in one language only.

- `scripts/ui/language.gd` (`class_name Language`) owns the selection and every
  string the UI generates itself (button captions, hints, group headings). It is
  **all-static and not an autoload**, because `--script` test runs do not
  instantiate autoloads and an autoload would make the UI scripts uncompilable in
  the suites.
- `Language.pick(zh, en)` is the only place a pair becomes one string. Content
  never concatenates the two languages.
- The switch is the `L` key or the button in the top-right corner, and it works at
  any time, including mid-line and with the notebook open.
- Switching re-renders what is on screen (`apply_language()` on the panel, the
  notebook and the HUD, plus `PrologueFlow.refresh_language()` for the prompt and
  ledger count). It does **not** restart the typewriter reveal, because the player
  has already read that line.
- Language is a presentation preference, deliberately **not** in `GameState`.
  Story-state tests must not depend on which language the UI happens to be in, and
  switching language must never look like narrative state changing.

Authoring rules, enforced by `tests/language_switch_test.gd`:

1. Chinese text is **Simplified**. The five content files are scanned for
   traditional-only glyphs (`著牠裡麼`) and fail CI if one survives.
2. Every line, choice, aside and ledger record has both fields, the Chinese one
   actually contains Chinese, and the English one contains **no** CJK at all.
3. Chinese vocabulary is mainland-neutral. Local/Taiwanese items were replaced
   during this milestone (`机车`→`电动车`, `骑楼`→`楼下`, `公车`→`公交车`,
   `立可白`→`涂改液`, `便当盒`→`饭盒`, `班代`→`课代表`), and the narrator uses `它`,
   not `牠`.

### The protagonist's voice

The narration is the protagonist thinking, so it is written the way that character
actually speaks: short sentences, sentence fragments, hesitations, self-correction
mid-thought, and no closing summary that explains the moment to the player.

- No aphorisms. Earlier drafts ended lines on a polished observation ("This is
  harder to deal with than a lie."). Those were rewritten as the thought that had
  not finished: "他是真的不高兴了。不是装的。这个比被他说谎难办。"
- Repetition and restatement are allowed on purpose ("我不太想开口。不太想。").
- Uncertainty is shown, not named: "最后一学期。这四个字我念了一遍。是我知道的，还是他说的。"
- Words are chosen from ordinary speech rather than literary register: `趴下去`
  → `趴下去` (kept, it is neutral), `有够` → `真能`, `喔/啦/嘛` removed from the
  protagonist's and other characters' lines.

This is a voice rule, not a dialect rule: the point is the halting quality, the
half-sentences and the self-correction, not a regional accent.

## 9. Testing

| Test | What it proves |
|---|---|
| `tests/smoke_test.gd` | The main scene instantiates; the classroom contains every required interactable; all three location scenes load and have spawn markers; all authored dialogue validates. |
| `tests/narrative_state_test.gd` | Provenance boundaries, ledger append-only behaviour, snapshot round-trip, dialogue traversal, and that the opening choices branch to distinct nodes. |
| `tests/prologue_flow_test.gd` | Plays the whole slice through the same entry points as player input and asserts each beat's flags and records, including that the imagined sequence changes no world state. |
| `tests/content_privacy_test.gd` | No manuscript markers, external references, or unmarked quoted material in content; every line and choice is bilingual and carries provenance. |
| `tests/reachability_test.gd` | Every required interactable has a free standing position within interact range, and the real `InteractionSensor` focuses it from there. Uses the physics server, not a hard-coded coordinate list. |
| `tests/language_switch_test.gd` | On the real UI: the body, choices, aside, backlog, notebook and prompt each render exactly one language; switching mid-line swaps them without restarting the reveal or losing the choices; English mode contains no CJK anywhere. Also builds every authored conversation and asserts each pair is complete, and scans content for traditional-only glyphs. |

Run them headlessly:

~~~sh
godot --headless --path . --script res://tests/smoke_test.gd
godot --headless --path . --script res://tests/content_privacy_test.gd
godot --headless --path . --script res://tests/narrative_state_test.gd
godot --headless --path . --script res://tests/prologue_flow_test.gd
godot --headless --path . --script res://tests/reachability_test.gd
godot --headless --path . --script res://tests/language_switch_test.gd
~~~

Autoloads are not created under `--script`, which is why story-state access goes
through `StoryFlags` (resolves `/root/GameState` at call time) instead of naming
the singleton. This keeps the same ownership model and lets the tests run.

## 10. Known limitations

- No save/load yet. The ledger has `to_array()` / `restore_from_array()` and
  `GameState` has snapshot APIs, but nothing writes a file.
- No authored audio. `RoomTone` synthesises a low hum and a bell so the room is
  not silent; replacing it with real assets is a drop-in node swap. Consequence:
  a headless exit prints `1 ObjectDB instance was leaked` naming an
  `AudioStreamGeneratorPlayback`. That is the engine-side generator buffer being
  released after the SceneTree is gone, not a leaked node or a script error; it is
  reported here rather than hidden.
- Graybox art only: primitives and flat materials. No textures, no portraiture.
  The dialogue panel identifies speakers by name, colour, and note instead.
- NPC bodies are static primitives with a small idle sway; there is no walking
  animation. N slides in along a short authored path.
- The street beat ends at the gate observation. The route past the bus stop, and
  the animal's species or fate, are deliberately unresolved and unimplemented.
- The five inner voices from the narrative bible are not implemented in this
  slice. Interior lines exist, but they are the protagonist's own notes rather
  than the voice system.
- Text size and text speed are exposed as exported properties on `DialoguePanel`
  (`text_reveal_chars_per_second`) but there is no settings menu yet.

## 11. Validation record

Engine used for the validation below: **Godot v4.7.2.stable**, standard (non-.NET)
build, `4.7.2.stable.custom_build` as reported by `--version`. The sandbox that
produced this milestone could not download the official editor binary (GitHub's
release CDN is blocked there), so the engine was **compiled from the pinned
`4.7.2-stable` source tag** with the default `linuxbsd` editor target:

~~~sh
curl -L -o godot-src.tar.gz https://codeload.github.com/godotengine/godot/tar.gz/refs/tags/4.7.2-stable
tar xzf godot-src.tar.gz && cd godot-4.7.2-stable
scons -j2 platform=linuxbsd target=editor production=no use_sowrap=yes \
      x11=no wayland=no alsa=no pulseaudio=no dbus=no udev=no speechd=no fontconfig=no
~~~

X11/Wayland/audio/fontconfig were disabled only because the sandbox has no
display server and no system font packages. None of those affect project
behaviour, except that the validation build cannot render frames (see the
limitation below).

Commands and results, run from the repository root:

~~~sh
# Import / parse check (no output on success)
godot --headless --editor --path . --quit

# Test suites
godot --headless --path . --script res://tests/smoke_test.gd
#   Smoke test passed: prologue composition, locations, props, and dialogue content instantiated.
godot --headless --path . --script res://tests/content_privacy_test.gd
#   content_privacy_test passed: no manuscript markers, external references, or unmarked quotes in content.
godot --headless --path . --script res://tests/narrative_state_test.gd
#   narrative_state_test passed (423 checks).
godot --headless --path . --script res://tests/prologue_flow_test.gd
#   prologue_flow_test passed (166 checks).
godot --headless --path . --script res://tests/reachability_test.gd
#   reachability_test passed (33 checks): every required interactable has a standing spot within reach.

# Boot the game headlessly for 600 frames
godot --headless --path . --quit-after 600
#   no script errors, no missing resources
~~~

A clean checkout (no `.godot/` cache) needs the import step to run **twice** the
first time: the first pass generates the font import data concurrently with
loading the project theme, so the theme reports that the font is missing. The
second pass is silent. This is an engine import-ordering behaviour, not a broken
resource, and CI runs the import step twice for that reason. It was verified by
copying the tree without `.godot/` and repeating both steps.

The same branch also passes GitHub Actions on the official Godot 4.7.2 install
(`chickensoft-games/setup-godot@v2.4.3`), including the import step, all five
suites, and the headless boot. That covers the case where the local engine came
from source rather than from a release binary.

Not verified in this environment: actual on-screen rendering, camera comfort,
animation feel, and audio output, because the sandbox has no GPU or audio device.
Those are the first things to check on a Windows desktop.
