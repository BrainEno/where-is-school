# The Biology Class (Prologue) — Implementation Notes

This milestone implements the first playable slice of the opening sequence:
wake in the classroom → Q opens the conversation → search the schoolbag →
inspect the room → the bell rings (B absent) → substitute N lets the class go →
leave through the corridor → the school gate. The street route and the green
animal are deliberately **not** in this build (milestone 2).

## Running it

The project entry scene is `scenes/main/main.tscn`, which composes
`scenes/locations/classroom/classroom.tscn`. Open the project in Godot 4.7.2
Stable (standard build) and press Play, or run:

    godot --path . --headless --editor --path . --quit   # import/parse check
    godot --path . --script res://tests/smoke_test.gd    # smoke test

Controls: WASD/arrows move · E interact · Space/Click advance text · Choices via
mouse or arrow keys + Space · Tab backlog · Esc settings (text speed, text size).

## Scene map

- `scenes/main/main.tscn` — project entry; composes the classroom only.
- `scenes/locations/classroom/classroom.tscn` — the lesson. Self-contained.
- `scenes/locations/corridor/corridor.tscn` — short exit route and the gate.
- `scenes/ui/game_ui.tscn` — HUD, dialogue panel, backlog, settings, end card.
- `scenes/actors/player/player.tscn` — CharacterBody3D + fixed 2.5D camera.
- `scenes/environment/student_desk.tscn` — reusable graybox desk prop.

## Interaction architecture

`Interactable` (Area3D, `scripts/interaction/interactable.gd`) is the contract:
prompt text, stable `interaction_id`, `enabled`, `interact_priority`. Interactables live
in the `interactables` group and only emit `interacted`; they never draw UI.

`InteractionSensor` (child of the player) picks the focused target each physics
frame: nearest enabled interactable within reach, preferring one the player is
facing, with `interact_priority` breaking ties (the loose set square wins over the
teacher's desk underneath it).

The player controller owns locomotion and forwards `E`. The HUD polls the sensor
to render the prompt (`[E] Search the schoolbag`) and hides it while busy.

Specialized interactables: `Inspectable` (plays a conversation, sets
`observed.inspect.<id>` on first look; `counts_for_progress = false` for the
schoolbag), `QTalk` (start-override branch selection), `ExitDoor` (locked by
conversation until `flow.class_dismissed`), `GateExit` (closing beat → end card).

## Dialogue architecture

Content lives in `data/dialogue/*.tres` as `DialogueConversation` resources —
never in gameplay scripts. `DialogueRunner` (RefCounted, UI-agnostic) walks the
entry graph, applies effects to `GameState`, filters condition-gated choices,
and emits `line_shown` / `choices_shown` / `conversation_finished`.
The runner is unit-tested without any UI.

`DialogueBox` (`scripts/ui/dialogue_box.gd`) renders the runner: speaker,
placeholder portrait initial, typewriter text (speed from `Settings`), choice
buttons, and a session backlog (Tab). `GameUI` (`scripts/ui/game_ui.gd`)
coordinates the HUD, prompt, settings overlay (speed/size persisted to
`user://settings.cfg`), the end card, and re-emits `conversation_finished`.

Dialogue consequence hooks used by this slice:

- **Conditional choices** — `condition_flag`/`condition_equals` on
  `DialogueChoice` (e.g. the imagination offer appears only after
  `observed.textbook_missing`).
- **Entry/choice effects** — `set_flag` on entries and choices.
- **Start override** — `QTalk` picks `ft_start_pretend` when
  `choice.pretend_remembered` is set; same conversation, different branch.
- **Chained conversations** — choosing the imagination option sets
  `flow.want_imagination`; the lesson director sees the flag when the current
  conversation ends and starts the imagination scene. Chaining, never merging.

## Narrative state namespaces

`GameState` (unchanged autoload, plus `count_flags_with_prefix`) stores string
flags. Established namespaces:

| Prefix | Meaning | Who sets it |
|---|---|---|
| `observed.*` | Facts the player directly observed in the world | Inspectables, conversation entries with `observed.` effects |
| `claim.q.*` / `claim.n.*` | Statements by Q / N — heard, not verified | Dialogue entries |
| `recollection.*` | Protagonist's uncertain recollection | Dialogue entries |
| `imagination.*` | Subjective imagination — never world state | `imagination_b` (enforced ⊆ `imagination.*`) |
| `choice.*` | Player choice traces | Choices |
| `flow.*` | Sequencing (lesson phase, dismissal, exit gate) | Director + content |

**Imagination isolation.** `imagination_b` is `presentation = "imagination"`:
tinted fullscreen wash, amber banner ("SUBJECTIVE IMAGINATION — NOT A RECORD OF
EVENTS"), low audio swell. The runner hard-blocks any flag not prefixed
`imagination.` from being applied inside an imagination conversation, and
`validate()` reports violations as content errors. It changes nothing about the
classroom: no flags outside `imagination.*`, no NPC or object positions, no
inventory, no story unlocks.

## Lesson sequencing

`LessonDirector` owns phase order only: fade-in from black → `wake_intro` →
control returns (objective: schoolbag) → `q_intro` (auto-started, no marker to
walk to) → bag discovery sets `observed.textbook_missing` → ≥ 2 other
`observed.inspect.*` flags → the bell rings (60 s fallback after the bag is
searched, so the player is never soft-locked) → `bell_gap` → N walks in →
`n_arrival` ends with `flow.class_dismissed` → the exit unlocks →
corridor → gate → end card (restart reloads the project fresh).

## Testing

Headless scripts in `tests/` (run with `godot --headless --path . --script res://tests/<name>.gd`):

- `smoke_test.gd` — main scene composes; player, camera, UI, director, ≥ 6 interactables.
- `game_state_test.gd` — flags, prefix counting, snapshot/clear.
- `settings_test.gd` — persistence round trip, invalid-value rejection.
- `dialogue_runner_test.gd` — effects, divergent choices, choice gating, start override,
  imagination isolation, finish signal, invalid-content rejection.
- `dialogue_content_test.gd` — every `.tres` in `data/dialogue/` validates; speakers known;
  required conversations present.
- `scene_composition_test.gd` — classroom, corridor and main instantiate with required nodes.

## Known limitations (this milestone)

- Street route and the green animal observation are deferred to milestone 2.
- No save/load yet (state is per-session); backlog resets when the scene changes.
- Temporary graybox primitives only; no production art, no portraits beyond placeholders.
- Sound effects are synthesized at runtime (no recorded audio assets, no assets to license).
- N's entrance uses capsule bodies and a tween, not skeletal animation.
- Settings cover text speed and size only; no other accessibility options yet.
