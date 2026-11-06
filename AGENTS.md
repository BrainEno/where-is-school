# Agent Instructions — where-is-school

You are contributing to a narrative game in pre-production. Read this file and the linked design documents before editing code or creative content.

## Product intent

where-is-school is a painterly 2.5D surreal narrative RPG. The adult protagonist wakes at a school desk as a student again, with unstable memory and no reliable explanation for their return. The opening chapter is Biology Class: a talkative classmate Q describes the absent biology teacher B, the protagonist imagines an increasingly elaborate confrontation, and an inexperienced substitute N arrives instead. The protagonist then leaves the classroom and school grounds into ordinary spaces that become difficult to classify.

The wider game explores multiple contradictory versions of the school, unstable routes through ordinary architecture, and the later-discovered elliptical building that connects school versions. The reason for the protagonist's return and the cause of spatial anomalies remain unknown.

The primary experience is exploration, environmental observation, and literary dialogue. Combat is not part of the current design. Do not add enemies, weapons, loot economies, crafting, survival meters, procedural open-world systems, or conventional horror chase loops without explicit approval.

## Source of truth

- Product and scope: docs/PRODUCT_BRIEF.md
- Runtime boundaries: docs/ARCHITECTURE.md
- Technical decisions: docs/TECHNICAL_ROADMAP.md
- Narrative rules, Biology Class source adaptation, characters, and scene sequence: docs/NARRATIVE_BIBLE.md
- Visual direction: docs/ART_BIBLE.md and docs/CONCEPT_DIRECTION.md
- First vertical-slice acceptance: docs/PROTOTYPE_BRIEF.md
- Agent comparison protocol: docs/AGENT_EVALUATION.md

If documents conflict, report the conflict instead of silently inventing a new direction. Keep this file and the design documents synchronized when an approved decision changes.

## Narrative fidelity and uncertainty

- Treat the owner's supplied "Biology Class" prose as primary source material for its events, imagery, character behavior, and narrative texture.
- Preserve the difference between what Q says, what the protagonist remembers, what the protagonist imagines, and what is actually observed.
- Do not turn the protagonist's imagined confrontation with B into an objective event.
- B is absent from the opening lesson; N substitutes for her. Do not bring B onstage early merely to deliver exposition.
- Q is an ordinary, talkative, overweight, overfamiliar classmate, not a supernatural guide, deliberate liar, or quest terminal.
- B is a woman whose authority combines a performed teacher role with ordinary pettiness and human self-interest. Do not flatten her into a monster, secret mastermind, harmless comic figure, or simple fraud.
- N is an inexperienced substitute, not automatically the truthful or morally superior counterpart to B.
- The wooden set square is a recurring material motif associated with B: borrowed from mathematics, damaged, taped, geometrically precise yet unstable in use, and capable of signifying classroom authority and physical threat.
- The green animal sequence concerns observation and uncertain classification. Do not invent a definitive species or outcome beyond the supplied source.
- A/B/C memory directions remain undecided in their specific content. D means deferring active recollection and following immediate events; it is not a permanently exclusive fourth campaign.
- Do not diagnose the protagonist or explain the school's anomalies as a confirmed psychological condition.
- Keep the elliptical building out of the opening. It is a later spatial structure connecting versions of the school, not a generic portal to unrelated locations.
- Distinguish confirmed owner decisions from provisional implementation proposals. When in doubt, mark a detail as undecided rather than filling the gap.

## Technical constraints

- Engine: Godot 4.7.2 Stable, standard build. Do not use beta/nightly APIs or silently upgrade the project version.
- Language: GDScript. Do not introduce C#, .NET, a second runtime, or a web backend without approval.
- Presentation: 3D environments with a controlled 2.5D camera. The first slice should use one consistent camera model; do not add camera-mode switching before it is required by a validated design.
- Use Godot scenes/resources for composition. Do not build the game as a pure-code renderer.
- Keep dialogue, character data, item descriptions, and location content out of large gameplay scripts.
- Separate world presentation, player control, interaction, dialogue, narrative state, and persistence.
- Keep autoload singletons few and cohesive. Do not turn every manager into a global singleton.
- Evaluate third-party addons before adoption. Record the exact version/tag, license, maintenance state, and reason for adoption.
- No mandatory network services, analytics, telemetry, paid APIs, or proprietary runtime dependencies.
- Windows PC is the first target. Keep input, paths, and content portable for later Linux/Steam Deck evaluation.

## Art and asset constraints

- Visual target: restrained painterly realism, damp concrete, faded institutional colors, lived-in objects, and subtle spatial impossibilities.
- The world should feel ordinary before it feels surreal.
- Do not imitate the distinctive art, UI, character designs, dialogue, or assets of any existing game. References describe broad qualities only.
- Do not add generated or downloaded assets without recording provenance and commercial-use rights in docs/ASSET_PROVENANCE.md.
- Temporary graybox assets are encouraged and must be treated as placeholders.
- Do not block a playable prototype on a large collection of final portraits, textures, or animations.

## Code quality

- Prefer small, cohesive scripts and scenes with explicit responsibilities.
- Use typed GDScript for public methods, exported properties, and non-trivial state.
- Give nodes, signals, resources, input actions, and story flags stable descriptive names.
- Avoid magic strings repeated across scripts; centralize identifiers when appropriate.
- Handle missing or invalid narrative data with actionable errors instead of silent fallbacks.
- Do not swallow errors, create fake success paths, or use placeholder tests that always pass.
- Do not add dependencies for trivial functionality.
- Do not reformat or rewrite unrelated files.
- Never commit editor caches, local machine settings, exports, credentials, or personal absolute paths.
- Preserve .uid files generated by Godot when they are part of the project.

## Testing and evidence

For every code task:
1. State the exact Godot version used.
2. Run the project in headless/editor mode where applicable and report the command.
3. Run relevant automated checks; if none exist, explain what was manually verified.
4. Check the debugger/output for parse errors, missing resources, and runtime errors.
5. Include a concise manual test checklist for movement, interaction, dialogue, scene transitions, and save/load when relevant.
6. Distinguish verified behavior from assumptions and untested behavior.

Never claim a test passed unless it was actually run. Never delete or skip a failing test merely to obtain a green result.

## Git and collaboration

- Work on a dedicated feature branch. Do not push directly to main.
- Keep pull requests focused: one PR should represent one coherent implementation task.
- Before editing, inspect the branch, working tree, project structure, and relevant existing code.
- Do not overwrite another agent's work. Avoid concurrent edits to shared scenes, project settings, autoloads, and central architecture files.
- Do not force-push, rewrite history, merge your own PR, or change repository protections.
- Do not add unrelated features or expand scope without asking.
- PR descriptions must include purpose, implementation summary, files changed, exact validation commands/results, known limitations, and screenshots/video for visual changes.
- If blocked, report the blocker and the smallest decision needed; do not fabricate missing infrastructure.

## Prototype priorities

Implement in this order:
1. Launchable Godot project, input, player movement, and camera.
2. One compact classroom environment with collision and readable navigation.
3. Interactable objects and one NPC.
4. Dialogue presentation with name, portrait, body, choices, and story flags.
5. One transition from the classroom toward the school grounds or another authored space.
6. Basic save/load and usability settings after the core loop is stable.

Do not build all chapters, a quest database, complex skill trees, voice acting, cinematic facial animation, or final production art during the first prototype.

## Definition of done

A task is done only when:
- Its acceptance criteria are met.
- The project still opens and the changed path works in the target engine.
- Relevant checks have been run and honestly reported.
- No known regression is concealed.
- Documentation and asset provenance are updated where necessary.
- The PR is reviewable and limited to the agreed scope.
