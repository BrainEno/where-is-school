# where-is-school

> **A school that cannot remember you. A student who cannot leave.**

where-is-school is a painterly 2.5D surreal narrative RPG about memory, institutional repetition, adulthood, shame, and the impossible geography of school.

You play an adult who has somehow been sent back to school. The school has no stable address: classrooms migrate, staircases lead to contradictory places, and the exit may be several countries—or one wrong turn—away. You explore unstable everyday spaces, inspect objects, meet people who may or may not remember you, and navigate long, literary conversations alongside competing voices inside your own head.

The project takes inspiration from expressive, text-rich narrative RPGs and dreamlike stories of spatial dislocation. It does not reproduce another game's characters, interface, writing, art, or assets. Its visual identity is grounded in ordinary lived-in architecture, damp concrete, faded institutional colors, and a persistent orange dusk.

## Project status

**Pre-production / engineering foundation.** This repository contains a launchable Godot starter project, architecture and production documents, agent instructions, and a headless CI smoke test. The full game and vertical slice are not yet implemented.

## Design pillars

1. **Unstable geography:** navigation is an expressive game mechanic; familiar places subtly refuse to stay put.
2. **Literary conversations:** dialogue, interior voices, observation, and contradiction are the primary means of interaction.
3. **Ordinary surrealism:** strange events emerge from recognizable schools, apartment blocks, stairwells, parking lots, and ports.
4. **A coherent authored art direction:** painterly surfaces and expressive portraits, not a random collage of generated assets.
5. **Player clarity inside an unclear world:** objectives, controls, saves, and interaction feedback remain understandable even when the fiction is not.

## Technical baseline

- **Engine:** Godot 4.7.2 Stable (standard build).
- **Language:** GDScript; no .NET/C# runtime.
- **Presentation:** 3D environments with a controlled 2.5D camera; hand-authored/painterly materials; illustrated 2D dialogue portraits.
- **Target:** Windows PC first; keep the project portable for later Linux/Steam Deck evaluation.
- **Narrative:** data-driven dialogue and story state. Evaluate Dialogic 2 in a bounded technical spike before adopting an addon or building a custom runtime.
- **Dependencies:** no mandatory online services, paid APIs, analytics, or proprietary runtime dependencies.

## Start the project

1. Install the **standard (non-.NET) Godot 4.7.2 Stable** editor.
2. Clone this repository.
3. Import/open the repository root containing project.godot.
4. Run the main scene with F6/F5 or the editor's Run Project command.
5. Use **WASD** or the arrow keys to move in the graybox test space.

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
- docs/PRODUCT_BRIEF.md — product concept, player experience, and scope.
- docs/ARCHITECTURE.md — code boundaries, runtime ownership, and data flow.
- docs/TECHNICAL_ROADMAP.md — engine, tools, and implementation phases.
- docs/NARRATIVE_BIBLE.md — world rules, themes, scene sequence, and opening.
- docs/ART_BIBLE.md and docs/CONCEPT_DIRECTION.md — text-only art direction; no generated concept images are part of the project foundation.
- docs/PROTOTYPE_BRIEF.md — bounded, testable first vertical slice.
- docs/AGENT_EVALUATION.md — fair protocol for comparing competing coding agents.
- docs/ASSET_PROVENANCE.md — asset rights and attribution ledger.
- docs/adr/ — records of important technical decisions.

## Agent workflow

Read AGENTS.md and the relevant design documents before changing code. Work on isolated branches and focused PRs. Do not have multiple agents edit the same project settings, autoload, or scene files concurrently. Every implementation claim must be backed by a command, test, or reproducible manual check.

## License and asset provenance

No project-wide source-code or content license has been selected. Do not assume that public visibility means permission to reuse or redistribute project content. Record the origin, author, license, and attribution requirements for every third-party or generated asset before shipping it.
