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

### Implemented in the foundation
- Godot project configuration and a launchable graybox main scene.
- Basic CharacterBody3D movement using WASD/arrow-key input.
- Fixed 2.5D camera attached to the player scene.
- GameState autoload for named runtime story flags.
- Headless scene-instantiation smoke test and GitHub Actions validation.

### Implemented in the biology-class prologue milestone
- Interaction targeting: `InteractionSensor` (on the player) and `Interactable3D`
  (on props), with a contextual prompt and a single `interact` action.
- A project-owned dialogue runtime (`DialogueScript` / `DialogueNode` /
  `DialogueChoice` / `DialogueSession`) with speaker identity, long bilingual
  text, choices, and a backlog. No addon is bundled.
- A provenance-tagged narrative ledger (`observed` / `heard` / `recollected` /
  `imagined`), surfaced in-game through the note page.
- Location transition orchestration (`PrologueDirector`) across classroom,
  corridor, and street, with per-location spawn markers.
- A subjective-imagination presentation mode that is visually distinct and
  provably unable to change world state.
- Runtime-synthesised room tone and a lesson bell (no audio assets).
- Four headless test suites, including an end-to-end playthrough test.

### Planned, but deliberately not implemented yet
- Dialogic 2 comparison spike. The custom runtime above is intentionally minimal
  and sits behind `PrologueFlow`, which is the seam a future adapter would use.
- Portraits. Speakers are identified by name, colour, and note for now.
- Journal discovery records as distinct from the close-of-scene note page.
- World-state-driven environment changes beyond the release/door state.
- Versioned save/load, slot management, and schema migration.
- Accessibility settings, localization pipeline, authored audio, input rebinding.

Do not implement every planned item in one large PR. Add each when a concrete slice requires it.

## 3. Dialogue technology decision

Run a small comparison spike before choosing:
- **Dialogic 2:** first candidate because it is Godot-native and aimed at dialogue/timeline workflows.
- **Custom dialogue layer:** only if the addon fails requirements or imposes unacceptable constraints. Keep any custom implementation small and testable.
- **Yarn Spinner Godot integration:** an alternative to investigate, not an assumed dependency.

The spike must prove long text, portraits, branching choices, conditions, persistent flags, Chinese font handling, backlog, and how dialogue reacts to world events. Record the tested plugin tag/commit, exact Godot version, license, and limitations. No plugin is bundled in this foundation.

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

### Phase 0 — Engineering foundation (current)
- Launchable Godot project.
- Agent instructions and architecture boundaries.
- CI project import and scene smoke test.
- Narrative and art direction documents.

### Phase 1 — Movement and graybox exploration
- Stabilize camera framing and movement feel.
- Add basic collision, stair traversal, door/room boundaries, and scene loading.
- Verify keyboard and controller input expectations.
- Establish one reusable environment scale and navigation conventions.

### Phase 2 — Interaction and dialogue spike
- Interactable object targeting and feedback.
- One NPC, one conversation, portrait and choice UI.
- Data-driven branches and story flags.
- Decide Dialogic/custom integration from evidence.

### Phase 3 — First vertical slice
- Residential approach → unstable stair/corridor → damp classroom.
- One NPC, three inspectable objects, one meaningful conversation, one spatial transition.
- Journal/route note only if the slice needs it.
- Save/load only after world-state ownership is stable.

### Phase 4 — Production readiness
- Versioned persistence, settings, accessibility, localization strategy.
- Content authoring validation and reusable art pipeline.
- Performance budgets and profiling.
- Steam build and platform compatibility checks.

## 6. Performance and quality gates

- Avoid expensive real-time lighting, transparent overdraw, and dense geometry without profiling.
- Prefer reusable modular environment assets; do not build a fully open world.
- Profile frame time and memory on representative hardware, not only a high-end development GPU.
- Test a clean clone/import, not only the developer's warmed editor cache.
- Keep CI focused on project import, parse errors, smoke checks, and automated logic tests. Do not add slow platform export matrices until export configuration exists.
