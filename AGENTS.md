# Agent Instructions — where-is-school

You are contributing to a narrative game in pre-production. Read this file and the linked design documents before editing code or game-facing creative content.

## Product intent

where-is-school is a painterly 2.5D surreal narrative exploration RPG. The protagonist wakes in a classroom occupying the role of a student again, without a reliable explanation. The opening follows a school lesson, a brief encounter with classmates and staff, and an exit into nearby everyday spaces. The wider game explores unstable school geography and contradictory recollections.

The primary experience is exploration, environmental observation, and literary dialogue. Combat is not part of the current design. Do not add enemies, weapons, loot economies, crafting, survival meters, procedural open-world systems, or conventional horror chase loops without explicit approval.

## Source of truth

- Product and scope: docs/PRODUCT_BRIEF.md
- Runtime boundaries: docs/ARCHITECTURE.md
- Technical decisions: docs/TECHNICAL_ROADMAP.md
- Game-facing narrative constraints: docs/NARRATIVE_BIBLE.md
- Visual direction (English source of truth): docs/ART_BIBLE.md and docs/CONCEPT_DIRECTION.md
- Chinese reading copies: docs/ART_BIBLE.zh-CN.md and docs/CONCEPT_DIRECTION.zh-CN.md. Keep each English/Chinese pair synchronized; agents should use the English version as the canonical production instruction.
- First vertical-slice acceptance: docs/PROTOTYPE_BRIEF.md
- Agent comparison protocol: docs/AGENT_EVALUATION.md

If documents conflict, report the conflict instead of silently inventing a new direction.

## Creative-material confidentiality — mandatory

The author's literary manuscripts are private source material and may be intended for separate publication. Repository access is not permission to reproduce them.

- Never copy manuscript paragraphs, extended descriptions, internal monologues, unpublished endings, or distinctive literary phrasing into source files, issues, PRs, commits, screenshots, test fixtures, agent prompts, or generated documentation.
- Do not create a disguised transcript by lightly paraphrasing a manuscript paragraph-by-paragraph. Extract only the minimum game-production facts needed to build a scene.
- Public documentation may contain concise scene beats, location/prop lists, interaction requirements, character-function notes, state transitions, and short dialogue samples explicitly approved for game use.
- If an exact line from a manuscript would help, ask the owner to approve that specific line for game use. Otherwise write new implementation dialogue independently.
- Do not upload manuscripts to public repositories or send complete manuscripts to external coding agents. Give agents only the small, relevant game brief they need.
- Keep the distinction between private literary source material and approved game content explicit in every handoff.
- When uncertain whether material is too close to the manuscript, omit it and ask.

## Narrative fidelity and uncertainty

- Preserve distinctions between a character's claim, the protagonist's recollection, subjective imagination, and events observed in the playable scene.
- The opening biology teacher B is absent from the first lesson; substitute N takes the class. Do not bring B onstage early to deliver exposition.
- Q is an ordinary, talkative, overfamiliar classmate, not a supernatural guide, deliberate liar, or quest terminal. Important context can emerge incidentally from ordinary conversation.
- B is a woman associated with the teacher role and institutional authority. Her character should retain ordinary human pettiness; do not flatten her into a monster, mastermind, harmless comic figure, or simple fraud.
- N is an inexperienced substitute, not automatically the truthful or morally superior counterpart to B.
- A damaged wooden set square is a recurring prop associated with B. Its precise visual state can be defined by the scene asset brief; do not reproduce manuscript description.
- The green-animal encounter is a scene about observation and uncertain classification. Its definitive species and outcome remain undecided.
- A/B/C memory directions remain undecided in their specific content. D means deferring active recollection and following immediate events; it is not a permanently exclusive fourth campaign.
- Do not diagnose the protagonist or explain the school's anomalies as a confirmed psychological condition.
- Keep the elliptical building out of the opening. It is a later spatial structure connecting versions of the school, not a generic portal to unrelated locations.
- Distinguish confirmed owner decisions from provisional implementation proposals. Mark unresolved details as unresolved.

## Technical constraints

- Engine: Godot 4.7.2 Stable, standard build. Do not use beta/nightly APIs or silently upgrade the project version.
- Language: GDScript. Do not introduce C#, .NET, a second runtime, or a web backend without approval.
- Presentation: 3D environments with a controlled 2.5D camera.
- Use Godot scenes/resources for composition. Do not build the game as a pure-code renderer.
- Keep dialogue, character data, item descriptions, and location content out of large gameplay scripts.
- Separate world presentation, player control, interaction, dialogue, narrative state, and persistence.
- Keep autoload singletons few and cohesive.
- Evaluate third-party addons before adoption. Record exact version/tag, license, maintenance state, and reason for adoption.
- No mandatory network services, analytics, telemetry, paid APIs, or proprietary runtime dependencies.
- `addons/` holds the narrative editor (`addons/narrative_editor/`), a first-party EditorPlugin.
  It is editor-only: no autoload, no `class_name`, no preload from `scripts/`, `scenes/` or
  `tests/`, excluded from the export preset, and `tools/verify_build.py` fails if anything under
  `res://addons/` is packed. Keep it that way, keep its write surface to text fields (ids,
  branches, conditions, effects, checks and numbers are read-only by construction), and keep the
  file I/O in `core/` so it can be tested headlessly against `user://` fixtures. See
  `docs/ARCHITECTURE.md` §5i and `addons/narrative_editor/README.md`.
- Windows PC is the first target. Keep input, paths, and content portable for later Linux/Steam Deck evaluation.

## Art and asset constraints

- Visual target: expressionist people and independent expressionist dialogue portraits; graphic, hand-made environments; and absurd theatrical negative space, especially outdoors. See docs/ART_BIBLE.md and docs/CONCEPT_DIRECTION.md for the full direction.
- Outdoor spaces may feel like spare stage sets: broad areas of sky and ground, an exposed horizon, isolated objects, simplified distant structures, and a deliberate atmosphere of waiting or disorientation. Do not fill empty space merely to make a scene look complete.
- Environment art may use bold color planes, hand-drawn outlines, rough brush marks, selective graffiti-like gestures, and simplified geometry. Graphic treatment must not obscure walkable space or important interactables.
- In-game 3D characters prioritize silhouette, proportion, posture, clothing identity, and gameplay-distance readability. Dialogue portraits are separate 2D artworks, not renders or screenshots of the 3D models.
- Dialogue UI follows an integrated composition: portrait, text, speaker identity, and choices belong to one visual arrangement. Long Chinese text must remain comfortable to read.
- The currently implemented dialogue surface is a text-led lower-left reading band; treat it as the implementation baseline and evolve it toward the integrated portrait composition when approved portrait art exists. Preserve its tested readability and interaction behavior.
- Do not treat dampness, dirt, rust, or heavy weathering as mandatory atmosphere. Surface treatment is selected according to each scene's composition and narrative purpose.
- Keep the English art documents canonical for agent execution and update their matching .zh-CN.md reading copies whenever they change.
- Do not add generated or downloaded assets without recording provenance and commercial-use rights in docs/ASSET_PROVENANCE.md.
- Temporary graybox assets are encouraged and must be treated as placeholders.

## Code quality

- Prefer small, cohesive scripts and scenes with explicit responsibilities.
- Use typed GDScript for public methods, exported properties, and non-trivial state.
- Give nodes, signals, resources, input actions, and story flags stable descriptive names.
- Handle missing or invalid narrative data with actionable errors.
- Do not swallow errors, create fake success paths, or use placeholder tests that always pass.
- Do not add dependencies for trivial functionality.
- Do not reformat or rewrite unrelated files.
- Never commit editor caches, local machine settings, exports, credentials, or personal absolute paths.

## Testing and evidence

For every code task:
1. State the exact Godot version used.
2. Run the project in headless/editor mode where applicable and report the command.
3. Run relevant automated checks; if none exist, explain what was manually verified.
4. Check output for parse errors, missing resources, and runtime errors.
5. Include a concise manual test checklist for relevant gameplay paths.
6. Distinguish verified behavior from assumptions and untested behavior.

Never claim a test passed unless it was actually run.

The narrative editor's data layer is tested headlessly (`tests/narrative_editor_test.gd`,
`tests/ability_validation_test.gd`) against a `user://` copy of the shipped content. The
dock itself needs a window: its frames come from `tests/capture_editor_dock.gd` under Xvfb,
and anything the plugin adds to the editor shell needs a manual checklist in the pull
request. Do not add a test that saves into `res://data/`.

## Git and collaboration

- Work on a dedicated feature branch. Do not push directly to main.
- Keep pull requests focused.
- Before editing, inspect branch, working tree, project structure, and relevant code.
- Do not overwrite another agent's work.
- Do not force-push, rewrite history, merge your own PR, or change repository protections.
- PR descriptions must include purpose, implementation summary, files changed, exact validation commands/results, and known limitations.
- If blocked, report the blocker and the smallest decision needed.

## Prototype priorities

1. Launchable Godot project, input, player movement, and camera.
2. One compact classroom with collision and readable navigation.
3. Interactable objects and one NPC.
4. Dialogue presentation with name, portrait, body, choices, and story flags.
5. One transition from the classroom toward school grounds or another authored space.
6. Basic save/load and usability settings after the core loop is stable.

Do not build all chapters, complex skill trees, voice acting, cinematic facial animation, or final production art during the first prototype.

## Definition of done

A task is done only when acceptance criteria are met, the changed path works in the target engine, relevant checks are honestly reported, no known regression is concealed, and the PR contains only approved game-production material.
