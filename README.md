# where-is-school

> A surreal school exploration game about unstable memory and impossible geography.

where-is-school is a painterly 2.5D narrative exploration RPG. The protagonist wakes in a classroom as a student again, with no reliable explanation for how they got there. A routine lesson becomes a route through the school and into surrounding spaces, where familiar places and remembered events do not always agree.

The game focuses on environmental observation, literary dialogue, ordinary objects, and spaces that gradually become difficult to navigate or classify. Its world is grounded in recognizable school and residential architecture, with subtle spatial impossibilities.

## Project status

**Pre-production / engineering foundation.** This repository contains a launchable Godot starter project, technical documentation, agent instructions, and a headless CI smoke test. The first playable narrative slice is in development.

## Design pillars

1. **Unstable geography:** familiar routes and spaces can connect in unexpected ways.
2. **Literary conversations:** ordinary speech, silence, and differing accounts shape the player's understanding.
3. **Ordinary surrealism:** anomalies emerge from recognizable places and objects.
4. **Observation without certainty:** seeing and naming something does not guarantee understanding.
5. **Player clarity:** controls, immediate objectives, and interaction feedback remain legible.

## Technical baseline

- **Engine:** Godot 4.7.2 Stable (standard build).
- **Language:** GDScript; no .NET/C# runtime.
- **Presentation:** 3D environments with a controlled 2.5D camera.
- **Target:** Windows PC first; keep the project portable for later Linux/Steam Deck evaluation.
- **Narrative:** data-driven dialogue and story state. Evaluate Dialogic 2 in a bounded technical spike before adopting an addon or building a custom runtime.
- **Dependencies:** no mandatory online services, paid APIs, analytics, or proprietary runtime dependencies.

## Start the project

1. Install the **standard (non-.NET) Godot 4.7.2 Stable** editor.
2. Clone this repository.
3. Import/open the repository root containing project.godot.
4. Run the main scene with F6/F5 or the editor's Run Project command.
5. Use **WASD** to move in the graybox test space.

Headless validation commands:

~~~sh
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/smoke_test.gd
~~~

The second command checks that the main scene can be instantiated and contains the expected starter nodes. It is a smoke test, not a substitute for interactive playtesting.

## Repository map

- AGENTS.md — authoritative coding-agent instructions.
- AGENT.md — compatibility pointer for tools that look for the singular filename.
- project.godot, scenes/, scripts/ — the actual Godot project and starter runtime.
- docs/PRODUCT_BRIEF.md — product concept and scope.
- docs/ARCHITECTURE.md — code boundaries, runtime ownership, and data flow.
- docs/TECHNICAL_ROADMAP.md — engine, tools, and implementation phases.
- docs/NARRATIVE_BIBLE.md — game-facing scene, character, and world constraints.
- docs/ART_BIBLE.md and docs/CONCEPT_DIRECTION.md — text-only art direction.
- docs/PROTOTYPE_BRIEF.md — bounded, testable first vertical slice.
- docs/AGENT_EVALUATION.md — fair protocol for comparing coding agents.
- docs/ASSET_PROVENANCE.md — asset rights and attribution ledger.

## Agent workflow

Read AGENTS.md and the relevant design documents before changing code. Work on isolated branches and focused PRs. Do not have multiple agents edit the same project settings, autoload, or scene files concurrently. Every implementation claim must be backed by a command, test, or reproducible manual check.

## Creative material and confidentiality

The repository contains game-production notes, not the author's unpublished literary manuscripts. Do not add private drafts, complete prose passages, extended literary descriptions, unused manuscript fragments, or unpublished story endings. Keep only concise game-facing scene requirements, interaction notes, and dialogue samples specifically approved for implementation. Do not infer permission to reproduce manuscript text from access to a game brief.

## License and asset provenance

No project-wide source-code or content license has been selected. Do not assume that public visibility means permission to reuse or redistribute project content. Record the origin, author, license, and attribution requirements for every third-party or generated asset before shipping it.
