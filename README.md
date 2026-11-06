# where-is-school

> **A school that cannot remember you. A student who cannot leave.**

where-is-school is a painterly 2.5D surreal narrative RPG about memory, institutional roles, adulthood, shame, observation, and the impossible geography of school.

You wake at a classroom desk as a student again. A talkative classmate seems to know your past; the biology teacher everyone warns you about does not arrive. An ordinary school day becomes an attempt to leave the classroom, the school grounds, and perhaps the school itself. Beyond the gates, familiar streets and residential spaces begin to feel difficult to classify. The school has no stable address: classrooms and staircases connect to contradictory versions of the same institution, while people remember events differently.

The game is built around literary dialogue, close environmental observation, unstable recollection, and everyday objects whose significance changes with context. Its visual identity is grounded in lived-in architecture, damp concrete, faded institutional colors, damaged school objects, and a persistent orange dusk. It takes inspiration from expressive, text-rich narrative games and dreamlike stories of spatial dislocation without reproducing another work's characters, writing, art, interface, or assets.

## Project status

**Pre-production / engineering foundation.** This repository contains a launchable Godot starter project, architecture and production documents, agent instructions, and a headless CI smoke test. The full game and first playable narrative slice are not yet implemented.

## Design pillars

1. **Unstable geography:** navigation is an expressive game mechanic; familiar places subtly refuse to stay put.
2. **Literary conversations:** ordinary chatter, interior voices, observation, and contradiction are primary means of interaction.
3. **Ordinary surrealism:** strange events emerge from recognizable schools, apartment blocks, stairwells, streets, yards, and ports.
4. **Observation without certainty:** people, memories, and living things resist simple classification.
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
- docs/PRODUCT_BRIEF.md — product concept, player experience, and scope.
- docs/ARCHITECTURE.md — code boundaries, runtime ownership, and data flow.
- docs/TECHNICAL_ROADMAP.md — engine, tools, and implementation phases.
- docs/NARRATIVE_BIBLE.md — world rules, character foundations, Biology Class opening, and narrative principles.
- docs/ART_BIBLE.md and docs/CONCEPT_DIRECTION.md — text-only art direction; no generated concept images are part of the project foundation.
- docs/PROTOTYPE_BRIEF.md — bounded, testable first vertical slice.
- docs/AGENT_EVALUATION.md — fair protocol for comparing competing coding agents.
- docs/ASSET_PROVENANCE.md — asset rights and attribution ledger.
- docs/adr/ — records of important technical decisions.

## Agent workflow

Read AGENTS.md and the relevant design documents before changing code. Work on isolated branches and focused PRs. Do not have multiple agents edit the same project settings, autoload, or scene files concurrently. Every implementation claim must be backed by a command, test, or reproducible manual check.

## License and asset provenance

No project-wide source-code or content license has been selected. Do not assume that public visibility means permission to reuse or redistribute project content. Record the origin, author, license, and attribution requirements for every third-party or generated asset before shipping it.
