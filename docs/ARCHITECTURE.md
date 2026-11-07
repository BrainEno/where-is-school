# Runtime Architecture

This document defines boundaries, not an excuse to build every planned subsystem immediately. Implement a subsystem when a playable requirement needs it; keep its ownership clear as it grows.

## 1. Top-level structure

~~~text
project.godot
scenes/
  main/                 # project entry scene and high-level composition
  actors/player/        # player scene and reusable actor scenes
  locations/            # authored location scenes, not procedural world data
  environment/           # reusable architecture and prop scenes
  ui/                   # menus, HUD, dialogue, journal
  cutscenes/             # authored in-engine sequences
scripts/
  autoload/              # very few application-wide state services
  actors/                # movement and actor behavior
  interaction/           # interaction contracts and targeting
  dialogue/              # dialogue runtime and adapters
  rpg/                   # inner voices and the one dice core
  world/                 # world state and spatial rule behavior
  save/                  # serialization and migration
  ui/                    # UI-specific presentation logic
data/
  dialogue/              # narrative content, not hard-coded in gameplay scripts
  inspections/           # object descriptions, per language
  abilities/             # inner-voice values, passive rules, and their text
  characters/
  items/
  locations/
assets/
  characters/
  environment/
  materials/
  audio/
  fonts/
addons/                   # pinned third-party plugins only
tests/
docs/
~~~

Directories are created when a real asset or implementation lands; do not add large collections of empty placeholders.

## 2. Dependency direction

Keep dependencies moving from presentation toward application/domain logic:

- **Scenes** compose nodes and resources. A scene should not own the entire narrative or save implementation.
- **Actor scripts** own local movement, animation requests, and actor state.
- **Interaction** identifies a target and requests an action; it should not decide how dialogue UI is drawn.
- **Dialogue runtime** advances a content graph and emits presentation events. It should not directly manipulate arbitrary level nodes.
- **UI** renders state and sends player intent. It should not become the authoritative story-state store.
- **World state** owns named story/world flags and offers small APIs.
- **Save system (future)** serializes explicit data snapshots. It must not serialize arbitrary live Nodes or scene-tree references.

Use signals at clear boundaries. Do not create a global event bus by default; first consider a direct reference, a signal on the owning node, or a narrowly scoped controller.

## 3. Autoload policy

The project contains two autoloads.

- **GameState** — runtime story flags and snapshot/restore of those flags. It is
  not a dumping ground for quests, dialogue UI, scene transitions, audio,
  inventory, settings, or save-file I/O.
- **NarrativeState** — append-only narrative knowledge entries, each tagged
  observed / reported / recalled / imagined, de-duplicated by id, with
  snapshot/restore. It exists because knowledge categories are used by dialogue,
  inspection, and presentation independently of gameplay flags; see
  `docs/adr/0002-dialogue-and-narrative-state.md`.

Add another autoload only when:
1. multiple independent scenes genuinely need the same service;
2. ownership and lifecycle cannot be expressed cleanly by a scene-level node;
3. the API is small and documented;
4. tests can validate it independently.

A future save manager should call explicit serializers and use a versioned save schema. It should not be merged into GameState.

## 4. Scene ownership

- The main scene composes the active location and persistent application-level nodes.
- Location scenes own their local geometry, navigation affordances, lighting, and location-specific interactive props.
- Reusable architecture/prop scenes belong under scenes/environment/.
- The player scene owns its controller and local camera rig. A later camera system may extract the rig if multiple actor modes require it.
- UI scenes should be replaceable without rewriting narrative data.

Avoid hard-coded NodePaths that reach across unrelated scene ownership. Prefer exported Node references, signals, groups used for a documented purpose, or explicit service APIs.

## 5. Narrative data contract

Dialogue content must be separate from gameplay scripts. The current milestone
implements a project-owned layer (see ADR 0002) that satisfies the requirements
below.

> **Recorded conflict.** Earlier revisions of this section described the Dialogic 2
> integration spike as an open decision and asked for it to be run before choosing.
> The implementation went ahead with the in-project layer, and ADR 0002 records that
> choice. The spike has not been run and is no longer planned; ADR 0002 stands. The
> paragraph below is kept as the checklist that decision had to satisfy.

Before adopting a dialogue addon or format, validate that it supports:
- long Chinese text and readable typography;
- named speakers and portrait identifiers;
- choices and conditional choices;
- story flags and explicit state changes;
- history/backlog and accessibility controls;
- interruption by environmental events;
- deterministic serialization of the current conversation state, if mid-conversation saves are required.

First run a bounded Dialogic 2 integration spike. Keep addon-specific calls behind a small project-owned adapter so content and gameplay code are not permanently coupled to one plugin. Do not install or pin the addon until its current Godot compatibility, license, and maintenance status are reviewed.

## 5b. Where text lives (implemented contract)

Every line the game says is data, in two languages, loaded by chapter:

- `data/dialogue/<locale>/<chapter>.json` — conversations (ids, speakers, text,
  `next`, choices, effects, conditions, narrative source);
- `data/inspections/<locale>/<chapter>.json` — object descriptions, their prompt,
  the first-read and repeat text, the optional recollection, the knowledge entry
  they record and the effects they apply once;
- `data/locale/<locale>.json` — the short strings the interface generates
  (prompts, objective labels, source badges, end card).

`DialogueGraph`/`DialogueLibrary` parse and validate the dialogue,
`InspectionLibrary` the descriptions, and `L10n` (static) plus `Loc` (autoload,
persisted in `user://settings.cfg`) the interface strings. Both language trees must
have identical structure; `DialogueParity` compares them node by node and reports
any dropped node, choice or effect. Authors edit JSON, not GDScript; the schema and
the editing rules are in `data/dialogue_schema/README.md`.

Nothing in `scripts/` may hold narrative text. The only literals left in scenes
(`prompt_text`, `end_card_title`) are fallbacks used when content is missing, and
the dialogue controller prefers the localized key or the inspection's own prompt.

The display language can change at any time: `Loc.locale_changed` makes the
dialogue controller rebind the open conversation to the same node id in the other
language, re-resolve the prompt, redraw the backlog and re-translate the objective.
No scene reload, no lost state.

## 5c. Inner voices and checks (implemented contract)

The ability system is deliberately small and lives in three places, each with one
job:

- `scripts/rpg/check_resolver.gd` — the only code that throws a die. Pure maths
  (`d10 + value + modifier >= difficulty`), an injected session seed, and a result
  dictionary. It knows nothing about content, UI or flags.
- `scripts/rpg/inner_abilities.gd` — reads `data/abilities/abilities.json`
  (values, speakers, passive rules) and `data/abilities/<locale>.json` (names and
  descriptions), validates them strictly, and reports every problem with a file
  path.
- `scripts/world/inner_voice_director.gd` — decides *when* a passive voice may
  speak: event triggers, `once` per rule, a per-voice session cap, no two
  unprompted lines in a row, and silence while an authored beat, a conversation or
  the end card owns the frame.

A check itself is dialogue data, not a script: a node carries a `check` block with
an ability id, a difficulty, `kind` (`visible`/`hidden`) and two branch targets.
`DialogueGraph` validates the block, `DialogueRuntime` resolves it when the node is
entered, emits `check_resolved`, records the result under
`check:<conversation>:<node>` and continues to the branch. `DialogueController`
shows visible results in `CheckOverlay` and shows nothing for hidden ones.

Invariants that later work must keep:

1. exactly one dice implementation; both modes call it;
2. the RNG is injectable and seedable, so tests never depend on luck;
3. a resolved check is recorded and replayed, so re-entering cannot reroll it;
4. a failed check may never be the only route past a required beat;
5. no gameplay script may contain a roll, a difficulty, or an ability name.

ADR 0003 records the reasoning, the formula, the frequency policy and the open
design questions.

## 6. Persistent identifiers and data

- Use stable IDs for dialogue nodes, characters, items, locations, and story flags.
- Treat IDs as save-data contracts; rename them only with an explicit migration plan.
- Do not use display names as identifiers.
- Validate external content at load time and report the file path and invalid field.
- Keep presentation text out of movement and world simulation scripts.
- Prefer typed Godot Resources for structured authoring; use JSON only where it materially improves localization, external editing, or automated validation. (Dialogue and inspection text use JSON for exactly that reason; see section 5b.)

## 7. Save/load design (future requirement)

When implemented, saves should contain a schema version and explicit snapshots for:
- current location and safe spawn identifier;
- story/world flags;
- journal discoveries;
- player progression and inventory, if later approved;
- relevant dialogue state only if the design requires mid-dialogue continuation.

Use user:// paths. Write to a temporary file, validate the result, then replace the prior save. Implement migrations before changing a released schema. Never save absolute machine paths or arbitrary Node references.

## 8. Testing boundaries

- Unit tests: pure state transformations, dialogue condition evaluation, content validation, save serialization/migration, dice maths and seeds.
- Negative fixtures: a validator that has never rejected anything proves nothing, so the content and check tests feed it deliberately broken input and assert the rejection.
- Scene smoke tests: required nodes/resources instantiate and scenes load.
- Integration tests: movement/interaction/dialogue/scene-state transitions.
- Manual tests: navigation readability, pacing, camera comfort, typography, controller feel, and spatial surprises.

A successful headless import is not proof that the game is playable. PRs must say which level of validation they actually performed.
