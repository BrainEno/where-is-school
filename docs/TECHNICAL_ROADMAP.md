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

### Implemented (up to classroom → green animal)
- Godot project configuration and a launchable main scene.
- Basic CharacterBody3D movement using WASD/arrow-key input.
- Fixed 2.5D camera attached to the player scene, with occluder fading.
- GameState autoload for named runtime story flags, plus the NarrativeState
  knowledge log (ADR 0002).
- Interaction targeting, interactable contract, and location exits.
- Project-owned dialogue runtime with choices, conditions, once-only choices,
  backlog, and validated JSON content.
- Inspection content with first-read effects, repeat text, and recollections.
- Subjective (imagined) presentation that cannot alter objective world state.
- Location swapping that preserves story state, plus authored beat sequencing.
- Headless smoke, content, unit, and end-to-end flow tests in GitHub Actions.
- **Classroom → corridor → street → residential locations** with full beat
  sequencing (wake, Q, schoolbag, inspections, expectation, bell, substitute,
  corridor/street/residential beats, green-animal encounter).
- **Data-driven bilingual content**: `data/dialogue/<locale>/prologue|street|residential.json`
  and `data/inspections/<locale>/classroom|corridor|street|residential.json`,
  with `DialogueGraph`/`DialogueLibrary` validation, `DialogueParity` cross-locale
  checks (including choice-level conditions), and runtime `L10n`/`Loc` switching.
- **Real-window playthrough capture** with `tests/capture_playthrough.gd`
  under Xvfb (`--rendering-driver opengl3`, 1600×900), 20+ frames
  committed to `docs/screenshots/` with `PLAYTHROUGH.log`.

### New in this slice — open playground + RPG core
- **Open playground location** (`scenes/locations/playground/playground.tscn`,
  `LocationRoot` + `PlaygroundDirector`): a continuous navigable area with
  three independent exploration anchors (sports shed, notice wall, old equipment)
  and free-order traversal. Transitions from `residential` via alley/estate-gate
  locations preserve `GameState`/`NarrativeState`.
- **Inner abilities (Hybrid)**: `scripts/rpg/inner_abilities.gd` + `AbilityDefinition`
  resources. Small, expandable set (e.g. `observation`, `recollection`, `intuition`,
  `composure`) with stable IDs, bilingual display, level/value, passive trigger
  rules and active-check support. Each ability has explicit narrative voice and
  may mislead.
- **Dice check engine**: `scripts/rpg/check_engine.gd` with unified formula
  `roll + ability + modifier vs difficulty`, injectable `RandomNumberGenerator`
  (seeded for tests), deterministic `CheckResult`, and anti-spam tracking
  (`attempted_checks` in `GameState`).
- **Visible (active) + hidden (passive) checks**: same core via `CheckEngine`;
  passive checks resolve silently and surface as varied inner-voice lines,
  active checks show ability, difficulty, roll and outcome in `DialoguePanel`.

### Still planned (not yet implemented)
- Dialogic comparison spike and the resulting adapter decision.
- Journal and unreliable route notebook.
- Portrait presentation for dialogue.
- Versioned save/load, slot management, and schema migration.
- Accessibility settings, audio mixing, and input rebinding (localisation pipeline
  with bundled CJK font is now **implemented**).

Do not implement every planned item in one large foundation PR. Add each when a concrete slice requires it.

## 3. Dialogue technology decision

Run a small comparison spike before choosing:
- **Dialogic 2:** first candidate because it is Godot-native and aimed at dialogue/timeline workflows.
- **Custom dialogue layer:** only if the addon fails requirements or imposes unacceptable constraints. Keep any custom implementation small and testable.
- **Yarn Spinner Godot integration:** an alternative to investigate, not an assumed dependency.

The spike must prove long text, portraits, branching choices, conditions, persistent flags, Chinese font handling, backlog, and how dialogue reacts to world events. Record the tested plugin tag/commit, exact Godot version, license, and limitations. No plugin is bundled in this foundation.

The custom layer now covers: `DialogueGraph`/`DialogueLibrary` per-chapter loading,
`InspectionLibrary`, `DialogueParity` (node+choice structure), `DialogueRuntime`
with condition-gated choices, and `DialogueController` rebind on locale change.
Content lives in `data/dialogue/<locale>/<chapter>.json`. This remains the seam
a future adapter would replace.

## 4. Content and asset pipeline

- Use Blender to create blockouts and reusable 3D props.
- Use Krita or Blender texture painting for authored material work.
- Keep source assets (for example, .blend, layered art files, and source audio) separate from optimized runtime exports where useful.
- Name assets by stable function, not temporary narrative meaning (for example, classroom_desk_a rather than desk_from_chapter_2).
- Keep dialogue and character/item metadata in data/resources, not in one giant GDScript.
- Track source, license, attribution, and modifications in docs/ASSET_PROVENANCE.md.
- Use generated imagery only as disposable ideation unless redistribution and commercial-use rights are clear and the final asset has been intentionally authored/approved.

Do not add Git LFS until large binary assets actually justify it. Decide file-size thresholds and storage cost before enabling it.

## 5. Development phases

### Phase 0 — Engineering foundation ✓
- Launchable Godot project. ✓
- Agent instructions and architecture boundaries. ✓
- CI project import and scene smoke test. ✓
- Narrative and art direction documents. ✓

### Phase 1 — Movement and graybox exploration ✓
- Stabilize camera framing and movement feel. ✓
- Add basic collision, stair traversal, door/room boundaries, and scene loading. ✓
- Verify keyboard and controller input expectations. ✓
- Establish one reusable environment scale and navigation conventions. ✓

### Phase 2 — Interaction and dialogue spike ✓
- Interactable object targeting and feedback. ✓
- One NPC, one conversation, portrait and choice UI. ✓
- Data-driven branches and story flags. ✓
- Decide Dialogic/custom integration from evidence (custom layer accepted, ADR 0002). ✓

### Phase 3 — First vertical slice (classroom → green animal) ✓ DELIVERED
- Classroom prologue — wake, Q, schoolbag, seven inspectables, the expectation
  beat, the substitute, and the walkway exit. ✓
- Gate/street/residential route and green-animal observation, keeping the same
  interaction, dialogue, and narrative-state boundaries. ✓
- Bilingual switching, data-driven dialogue/inspections, playground capture. ✓
- Save/load only after world-state ownership is stable (deferred).

### Phase 3b — Open playground slice (current)
- **Route continuation**: residential courtyard → alley → estate gate → courtyard
  before playground → **open playground** (open, freely explorable, 3 anchors).
- Preserve `LocationHost`/`LocationRoot`/`GameState`/`NarrativeState`/
  `InteractionController`/`DialogueController` contracts; state survives transitions.
- Old end-card moved to playground exit; residential alley is no longer a hard stop.
- **RPG core (Hybrid + Both)**:
  - Inner abilities with passive (auto-trigger) + active (player-chosen) modes.
  - Dice with visible (player sees roll/requirement) + hidden (background) modes
    sharing one `CheckEngine` and injectable RNG.
  - Success and failure both yield narrative; no hard locks.
- **Engineering fixes**: capture CI fail-fast with artifacts; `DialogueParity`
  now checks choice-level `requires`/`all_flags`/`not_flags`.
- ADR-0003 records hybrid/both rationale, check formula, RNG testing, and
  `DialogueRuntime` integration.

### Phase 4 — Production readiness (future)
- Versioned persistence, settings, accessibility, localization strategy
  (CJK font and locale switching already delivered; save/load still pending).
- Content authoring validation and reusable art pipeline.
- Performance budgets and profiling.
- Steam build and platform compatibility checks.

## 6. Performance and quality gates

- Avoid expensive real-time lighting, transparent overdraw, and dense geometry without profiling.
- Prefer reusable modular environment assets; do not build a fully open world.
  The playground is open but bounded and density-focused, not an open world.
- Profile frame time and memory on representative hardware, not only a high-end development GPU.
- Test a clean clone/import, not only the developer's warmed editor cache.
- Keep CI focused on project import, parse errors, smoke checks, and automated logic tests. Do not add slow platform export matrices until export configuration exists.
- Playground must stay readable at 60 fps on the Windows baseline; its three
  anchors are distinct without inflating the navmesh.
