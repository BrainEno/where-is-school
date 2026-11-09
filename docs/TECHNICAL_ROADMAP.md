# Technical Roadmap

## 1. Baseline decisions

| Area | Decision | Reason / boundary |
|---|---|---|
| Engine | Godot 4.7.2 Stable | Pin a known stable version. Do not follow 4.8 beta during prototype production. |
| Build | Standard, non-.NET | The project uses GDScript; no Mono/.NET runtime is needed. |
| Language | GDScript | Native editor workflow and fast iteration. |
| Renderer | Forward+ for Windows PC baseline | The project is 3D and may need custom materials, lighting, and atmospheric effects. Profile on representative lower-end hardware before content scale-up. |
| World | 3D environments + controlled 2.5D camera | Supports verticality, staircases, container geometry, and authored perspective while preserving readable navigation. |
| Target | Windows PC first | Keep engine features and file paths portable for later Linux/Steam Deck review. |
| Version control | Git + GitHub PRs | Every agent works on an isolated branch; main remains reviewable. |
| External services | None required | The game should work offline and must not depend on a paid service. |

Official engine reference: [Godot 4.7.2 stable release](https://godotengine.org/article/maintenance-release-godot-4-7-2/). Check release status before any future version upgrade.

## 2. Runtime components

### Implemented
- Godot project configuration and a launchable main scene.
- Basic CharacterBody3D movement using WASD/arrow-key input.
- Fixed 2.5D camera attached to the player scene, with occluder fading.
- GameState autoload for named runtime story flags, plus the NarrativeState
  knowledge log (ADR 0002).
- Interaction targeting, interactable contract, and location exits.
- Project-owned dialogue runtime with choices, conditions, once-only choices,
  hidden/visible dice checks, backlog, and validated JSON content.
- Inspection content with first-read effects, repeat text, and recollections.
- Subjective (imagined) presentation that cannot alter objective world state.
- Location swapping that preserves story state, plus authored beat sequencing. A swap
  is a transaction: scene, `location_id`, spawn marker and the player's placement are
  all checked before the old scene is touched, and a failure leaves the room, the
  player, Q, the story flag and the emitted signals exactly as they were
  (`docs/ARCHITECTURE.md` §5h, `tests/location_transition_test.gd`).
- Bilingual content (English and Simplified Chinese) with runtime switching that
  also works mid-line, and a parity checker that refuses a translation which
  changes the shape of a conversation.
- Data-driven dialogue throughout: every line, choice, condition, effect and check
  lives in `data/dialogue/<locale>/`, never in a gameplay script.
- Outdoor locations: the street, the residential courtyard, the alley behind the
  flats, and the open school yard (playground), with the green animal in the
  courtyard and the end of the slice at the far gap in the yard's fence.
- The hybrid inner-voice system with passive triggers and active checks, and the single
  shared dice core behind both visible and hidden checks (ADR 0003, which is a proposal
  awaiting the owner). One provisional voice ships; the plumbing is written for any
  number of them and was proven with fixture voices in `tests/multi_voice_test.gd`
  (Phase 6a).
- Native navigation in every playable location, with mouse click-to-move and
  click-to-interact sharing the existing movement and activation paths (see
  `docs/ARCHITECTURE.md` §5f).
- A reading surface built for long bilingual prose: a band in the lower left rather
  than a full-width box, a name and a quiet role above the sentence, the narrative
  source drawn as a hairline and a small tracked label, options on their own lines,
  and a layout that is measured from the content at 1280x720, 1600x900 and 1920x1080
  instead of tuned for one screen (`tests/dialogue_layout_test.gd`).
- Development-only name labels over the grey-box people, translated with the rest of
  the interface and switched off in release builds (`tests/nameplate_test.gd`).
- CI: a static syntax gate over every `.gd` file, thirty-five headless checks, a
  blocking import pass with an audit that every tracked `.import` produced its file, and
  a read-only capture job whose artifacts are the visual evidence for a pull request.
  Failures produce artifacts as well, so a red run is diagnosable.
- A reproducible Windows build: a committed `export_presets.cfg`, a release workflow that
  exports with the engine's own export templates and attaches the zip to the run (and to a
  GitHub release on a `v*` tag), and a pack verifier that reads the finished executable
  back and refuses a build that carries the repository (tests, screenshots, the 10 MB
  source font) or is missing the game (dialogue data, theme, audio). The bundled CJK font
  ships as a 325 KiB subset of the text the game can draw, rebuilt by
  `tools/subset_font.py` and verified in both CI workflows.

### Planned, but deliberately not implemented yet
- Journal and unreliable route notebook.
- Portrait presentation for dialogue.
- Versioned save/load, slot management, and schema migration.
- Accessibility settings, audio mixing, and input rebinding.
- A code-signed, icon-carrying installer, and Linux/macOS presets. The Windows
  executable exists (Phase 5d) but is unsigned and carries the default engine icon.
- Populating the yard with people, events and further checks, now that the space
  and its interaction anchors exist.
- Navigation features that click-to-move deliberately does **not** have yet: agent
  avoidance between moving bodies, off-mesh links for stairs and ledges that are not
  ramps, and path smoothing. Each location's mesh is baked from its own colliders
  only, so nothing crosses a location boundary. These are separate from companion
  movement, which **is** implemented: Q follows the player's navigation path, keeps a
  follow distance, stops when the player stops, resumes on movement, and gives up
  beyond its leash (see `docs/ARCHITECTURE.md` §5d and `tests/companion_route_test.gd`).
  What the companion still does not do is dynamic obstacle avoidance around other
  moving bodies: it walks the map, it does not negotiate with anyone on it.

Do not implement every planned item in one large foundation PR. Add each when a
concrete slice requires it.

## 2a. Recorded documentation conflicts

Two places where this document disagreed with the code, recorded rather than
silently rewritten:

- **Dialogue technology.** This entry used to say that section 3 still described a
  spike between Dialogic, a custom layer and Yarn Spinner while the implementation had
  chosen the custom layer (ADR 0002). Section 3 now states the decision itself, so the
  divergence is gone; the entry is kept as the record of it.
- **Localisation.** This document used to list the localisation pipeline as future
  work while `Loc`, `L10n`, the bilingual content trees and the language-switch
  test were already shipping. Bilingual switching is now listed as implemented.
  What remains genuinely unbuilt is the font subsetting and the translator
  workflow, and those stay in the planned list.

## 3. Dialogue technology decision (decided, implemented)

**Decision: the project-owned dialogue layer, not an addon.** ADR 0002 records it, and
the implementation ships: `DialogueGraph`/`DialogueLibrary` parse and validate the
bilingual JSON, `DialogueRuntime` walks the graph, `DialogueController` presents it, and
`NarrativeState` keeps the knowledge log. No dialogue addon is installed, pinned or
referenced by gameplay code.

The comparison that once stood here — a bounded Dialogic 2 spike, a custom layer as the
fallback, and Yarn Spinner as an alternative — was **never run and is not planned**. It
is kept out of the plan deliberately: an unrun spike listed as future work reads like a
pending decision and invites a migration nobody approved.

The requirements the spike was meant to test are now the contract the shipped layer is
held to, and each is covered by an automated check:

| Requirement | Where it is implemented / checked |
|---|---|
| Long Chinese text and readable typography | `tests/dialogue_layout_test.gd`, `tests/i18n_test.gd` |
| Named speakers and portrait identifiers | `data/characters/`, `CharacterDirectory`, dialogue panel name row |
| Choices and conditional choices | `DialogueGraph` conditions, `tests/dialogue_runtime_test.gd` |
| Story flags and explicit state changes | `StoryFlags`, effects, `tests/narrative_state_test.gd` |
| History/backlog | `DialogueHistory`, `BacklogPanel`, `tests/language_switch_test.gd` |
| Accessibility controls | **not implemented**: listed in the planned items below; the spike requirement is unmet and is not claimed otherwise |
| Interruption by environmental events | `InnerVoiceDirector`, beat locking in `OpeningSequence` |
| Deterministic serialization of conversation state | not required yet: mid-conversation saves are not implemented (save/load is in the planned list in §2). The dice core is seeded and replayable (`tests/check_resolver_test.gd`). |

If an addon is ever reconsidered, it starts as a new ADR with the spike results attached
— not as a silent change to this section.

## 4. Content and asset pipeline

- Use Blender to create blockouts and reusable 3D props.
- Imported models follow `docs/ASSET_PIPELINE.md`: glTF 2.0 binary, one unit = one metre,
  +Y up and -Z forward, origin on the floor, no node scale, one named material per mesh.
  Two project-owned placeholder samples (`assets/models/sample/chair.glb` and
  `figure.glb`) are written by `tools/build_sample_models.py` and measured by
  `tests/model_import_test.gd`; CI also rebuilds them and fails if the committed bytes
  differ from a fresh build.
- Collision, the interaction anchor and navigation belong to a hand-authored wrapper
  scene under `scenes/environment/`, never to the model and never to a generated
  location: `tools/build_outdoor_locations.py` only decides where a wrapper stands, so
  regenerating any of the four outdoor scenes keeps the hook-up and cannot overwrite it.
- Use Krita or Blender texture painting for authored material work.
- Keep source assets (for example, .blend, layered art files, and source audio) separate from optimized runtime exports where useful.
- Name assets by stable function, not temporary narrative meaning (for example, classroom_desk_a rather than desk_from_chapter_2).
- Keep dialogue and character/item metadata in data/resources, not in one giant GDScript.
- Track source, license, attribution, and modifications in docs/ASSET_PROVENANCE.md.
- Use generated imagery only as disposable ideation unless redistribution and commercial-use rights are clear and the final asset has been intentionally authored/approved.

Do not add Git LFS until large binary assets actually justify it. Decide file-size thresholds and storage cost before enabling it.

## 5. Development phases

Phases 0-5d are delivered, each in its own round. Phase 6 and Phase 7 are intent, not
a promise, and neither is scheduled by this document. The "delivered in this round" label
on a phase records the round that shipped it; it is not a claim about the current
branch.

### Phase 0 — Engineering foundation (delivered)
- Launchable Godot project, agent instructions, architecture boundaries.
- CI project import, a static syntax gate, and scene smoke coverage.
- Narrative and art direction documents.

### Phase 1 — Movement and graybox exploration (delivered)
- Camera framing, movement feel, collision, stair traversal, scene loading.
- One reusable environment scale; interiors and exteriors share it.

### Phase 2 — Interaction and dialogue (delivered)
- Interactable targeting, one NPC and one conversation, choices, story flags.
- The dialogue layer was built in-project rather than adopted (ADR 0002).

### Phase 3 — First vertical slice (delivered)
- Classroom prologue: wake, Q, schoolbag, seven inspectables, the expectation
  beat, the substitute, the walkway exit.
- The gate and the street, the residential courtyard, and the green-animal
  observation, on the same interaction/dialogue/narrative-state boundaries.
- Bilingual content and switching.

### Phase 4 — Open yard, inner voices, dice (delivered in this round)
- The alley behind the flats and the estate gate, leading to an open school yard
  that is walked freely rather than in a corridor.
- The hybrid inner-voice system: passive rules that fire on events with strict
  frequency control, and active checks the player chooses in a conversation.
- One dice core serving visible checks (numbers shown) and hidden checks (only
  the reaction shown), with an injectable, seedable RNG and recorded outcomes so
  an attempt cannot be farmed.
- The end of the slice moved to the far gap in the yard's fence.
- Evidence: `docs/screenshots` from the capture workflow, plus the headless test
  suite. Windows hands-on checks are listed in the pull request and are not yet
  performed.

### Phase 5 — Free period, companion, and the yard behind the school (delivered in this round)
- N's announcement ends with a real choice: stay at the desk, or leave. Both are
  recorded, neither forces a transition, and the classroom stays playable if the
  player stays.
- Q becomes a companion who survives location swaps, follows at a natural distance,
  waits instead of teleporting when left behind, and can be asked along through one
  ordinary interaction.
- The walkway gains optional activities (a wall speaker with its own noise cue, a
  cleaning trolley, the railing) and the end door that opens onto the yard.
- The yard is now reached through the walkway as well as through the alley, and gains
  tyres, an equipment container, outdoor fitness gear and birds on the fence.
- Pointer targeting with an explicit priority rule against facing, and a hover cue
  that always names the object E would use.
- One provisional voice on a provisional 2d6 formula.
- Evidence: the capture workflow now walks the corridor-to-yard transition on foot
  and moves a real cursor for the hover shot. Windows hands-on checks are listed in
  the pull request and are not yet performed.

### Phase 5b — Mouse navigation and automatic interaction (delivered in this round)
- Every playable location — classroom, walkway, street, residential courtyard, alley,
  schoolyard — owns a `NavigationRegion3D` that bakes its mesh from its own static
  colliders on load. The four generated outdoor scenes get the node from
  `tools/build_outdoor_locations.py`.
- `PlayerController` gained one path-following branch that shares acceleration,
  gravity, `move_and_slide()` and facing with manual movement. A walk can be cancelled
  by any movement key, by a control lock, by a second destination, or by a location
  change; a walk that cannot progress ends through a stall watchdog.
- `PointerNavigator` maps one left click to either a walk, an approach-and-activate, or
  a refusal. Automatic activation goes through
  `InteractionController.request_activation()`, the same call E makes, and happens at
  most once.
- A left click on a dialogue option selects exactly one option and never reaches the
  world; the options keep their hover styling, their digits, and their text across a
  language switch.
- The reading band is a click surface: a left click inside the dialogue box continues
  the line (finishing it first if it is still typing), and while the box is up a click
  outside it is swallowed — neither an advance nor a walk.
- The street's way back into the school is now `prompt.back_to_classroom`
  ("Return to classroom" / "回到教室"), and the story's dismissal rewrite only touches
  the classroom door.
- The courtyard's way out to the lane behind the flats became a real passage: the north
  block is split into two masses with a lintel over the gap, and the lane's asphalt is a
  collider whose top face is flush with the courtyard, so the pair walks in both
  directions and bakes into the mesh. The lane used to be mesh-only boxes with nothing to
  stand on and no polygon to route over (issue #33).
- Evidence: `tests/navigation_test.gd`, `tests/automatic_interaction_test.gd`,
  `tests/dialogue_pointer_test.gd`, `tests/street_prompt_test.gd`, and capture frames
  taken with real pointer events. Windows hands-on checks are listed in the pull
  request and are not yet performed.

### Phase 5c — The authored props in the world (delivered in this round)
- The two owner-authored Blender props stopped being preview-only. The residential
  courtyard's three grey boxes by the planter became `playground_bench.tscn`, and the
  schoolyard's grey-box seat and the box that stood for a bag became the bench and the
  backpack. Both seat planes are the same 0.51 m the boxes had, so nothing that leaned on
  the old seat moved.
- Placements are rows in `tools/build_outdoor_locations.py`'s `s.props` table, so a
  regeneration cannot drop them; the wrappers, their collision and their anchors stay
  hand-authored outside `scenes/locations/` (§4, issue #21).
- The courtyard's `BenchLook` anchor moved from the middle of the seat to just off its
  front edge. A 1.04 m body owns its whole footprint, and the visibility probe treats a
  prop as a wall, so an anchor inside it is invisible from everywhere: the object hides
  its own hotspot. Declaring the prop in `support_paths` is the alternative, and is not
  needed here.
- Evidence: `tests/prop_placement_test.gd` (instance is the wrapper, declared transform,
  grey boxes gone from scene and table, the bag rests on the seat, anchors clear of their
  own collision with walkable ground in reach, both sites still route spawn to far exit),
  on top of the existing `tests/prop_asset_test.gd`, `tests/model_import_test.gd` and
  `tests/interaction_visibility_sweep_test.gd`. Windows hands-on checks are listed in the
  pull request and are not yet performed.

### Phase 5d — The build (delivered in this round)
- The slice became something that can be handed over: `export_presets.cfg` is committed
  (it used to be gitignored, which is why no build had ever been produced), and
  `.github/workflows/release.yml` exports a single embedded-pack Windows executable on
  pull requests, on demand and on a `v*` tag, then verifies and packages it.
- The build is verified by reading it back, not by trusting the preset:
  `tools/verify_build.py` parses the pack out of the executable and fails when the game is
  missing from it or the repository is in it. That is the check that caught the two things
  "export all resources" would have shipped by default — 9.4 MB of committed screenshots
  and the 10 MB source font.
- The font is split: the untouched Noto Sans SC lives in `art/fonts/` (`.gdignore`d) and the
  game loads a 325 KiB subset that `tools/subset_font.py` rebuilds from the project's own
  text. Both CI workflows run `--check`, so text needing a character the subset lacks fails
  with the characters named instead of shipping tofu boxes.
- `packaging/HOW-TO-RUN.txt` travels in the zip (controls, the SmartScreen warning, the
  known cosmetic gaps), the font licence travels beside the executable in `licences/`, and
  `docs/PLAYTEST_CHECKLIST.md` is the ordered hands-on pass the build exists for.
- Evidence: the release workflow's export, verify and package steps, plus the annotations
  they publish (executable size, pack contents, zip size).
  `docs/IMPLEMENTATION_NOTES_BUILD.md` records the decisions and the limits — no icon, no
  signature, Windows only, no save/load or settings screen.

### Phase 6a — Multi-voice foundation (delivered in this round)
- The inner-voice plumbing now holds any number of voices instead of one, and the
  number is data rather than code. Every voice keeps its own `ability_id`, its own
  `speaker_id`, its own value and its own passive cap; a speaker id resolves to exactly
  one voice and to exactly one profile at `data/characters/<speaker_id>.tres`, which the
  character directory loads from the registry instead of from a hard-coded list.
- The registry rejects what would otherwise fail silently: two voices claiming one
  speaker, a non-numeric or out-of-range value, a negative passive cap, a missing
  translation, a translation copied from English, and text for a voice that does not
  exist. A missing, foreign or colliding character profile is a start-up error, never a
  fallback to someone else's name and colour.
- Active checks were already per-ability and stay that way, one record per check node;
  passive lines now choose their voice at fire time, in `abilities.json` order, so two
  voices matching one event are deterministic instead of racing, and an event is no
  longer lost when the rule queued first could not speak.
- Proven by `tests/multi_voice_test.gd`, which loads two fictional voices from a
  `user://` fixture through the real loaders. No second voice, name, value or line was
  added to `data/` — the cast is the owner's decision, and this round deliberately
  writes none of it.
- Still open, and deliberately not decided here: how many voices there will be, their
  names, personalities, values, trigger rules, typography, and the prose of the three
  hidden checks that ship today. The shipped `orientation` description still says "one
  voice", which becomes the owner's copy edit at that point.

### Phase 6 — Filling the yard (planned, not started)
- People and events in the yard, using the anchors that exist now: the court, the
  shed, the container, the bench, the climbing frame, the notice board.
- The owner has decided (2026-11) that the one provisional voice is to be **extended into
  several voices** rather than kept as it is. The technical foundation for that is done
  (Phase 6a); the cast itself is a content-and-rules round of its own — who the voices
  are, new trigger rules, a way to tell them apart in the typography, and a rewrite of
  the three hidden checks that ship now — and it is not started.
- Retuning the dice against real playtest data.
- A journal/notebook for what the protagonist knows, once there is enough of it
  to be worth reading.

### Phase 7 — Production readiness (planned, not started)
- Versioned persistence, settings, accessibility.
- Store-grade packaging: an icon, code signing, an installer, and the Linux/macOS presets
  the release workflow does not build.
- Content authoring validation and reusable art pipeline.
- Performance budgets and profiling.
- Steam build and platform compatibility checks.

## 6. Performance and quality gates

- Avoid expensive real-time lighting, transparent overdraw, and dense geometry without profiling.
- Prefer reusable modular environment assets; do not build a fully open world.
- Profile frame time and memory on representative hardware, not only a high-end development GPU.
- Test a clean clone/import, not only the developer's warmed editor cache.
- Keep CI focused on project import, parse errors, smoke checks, and automated logic tests. Do not add slow platform export matrices until export configuration exists.
