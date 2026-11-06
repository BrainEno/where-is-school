# where-is-school

> **A school that cannot remember you. A student who cannot leave.**

where-is-school is a painterly 2.5D surreal narrative exploration game about memory, institutional repetition, and unstable school spaces.

## Project status

**First playable milestone: the biology-class prologue.** The project launches into the opening classroom, where the player can wake up, talk to Q, search the schoolbag, inspect the room, experience an expectation that is explicitly not a real event, sit through the substitute's lesson, and leave for the walkway. The street route and the green-animal observation are the next milestone and are not implemented.

See [docs/IMPLEMENTATION_NOTES_OPENING.md](docs/IMPLEMENTATION_NOTES_OPENING.md) for controls, architecture, and known limitations.

## Technical baseline

- **Engine:** Godot 4.7.2 Stable (standard build).
- **Language:** GDScript; no .NET/C# runtime.
- **Presentation:** 3D environments with a controlled 2.5D camera.
- **Target:** Windows PC first; keep the project portable for later Linux/Steam Deck evaluation.
- **Dependencies:** no mandatory online services, paid APIs, analytics, or proprietary runtime dependencies.

## Controls

- **WASD / arrow keys** — walk (camera-relative).
- **E** — interact with the highlighted object or person.
- **Space / Enter / left click** — continue dialogue, or answer with the numbered choice.
- **1–9** — pick a dialogue choice.
- **Tab** — open or close the dialogue log.

## Repository map

- AGENTS.md — authoritative coding-agent instructions.
- project.godot, scenes/, scripts/ — Godot project and runtime.
- data/ — dialogue, inspection text, and character presentation data (content, not code).
- assets/ — placeholder materials and generated audio, tracked in docs/ASSET_PROVENANCE.md.
- tests/ — headless smoke, content, unit, and end-to-end flow tests run by CI.
- docs/ — concise, implementation-facing product, architecture, technical, narrative, art, prototype, and agent-evaluation references.
- docs/ASSET_PROVENANCE.md — asset rights and attribution ledger.
- tools/ — maintenance scripts (placeholder audio synthesis).

## Creative material

The repository is not a publication archive for the author's literary manuscripts. Do not add unpublished prose or extended manuscript-derived passages. Keep public narrative references limited to concise scene beats, implementation requirements, and dialogue explicitly approved for game use.

## Copyright and licensing

No MIT, Apache-2.0, or other open-source license is granted to the repository as a whole. Original project materials are reserved unless a specific file or component carries an explicit license or separate written permission. See [COPYRIGHT.md](COPYRIGHT.md). Third-party dependencies and assets remain under their own licenses.
