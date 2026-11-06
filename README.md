# where-is-school

> **A school that cannot remember you. A student who cannot leave.**

where-is-school is a painterly 2.5D surreal narrative exploration game about memory, institutional repetition, and unstable school spaces.

## Project status

**Pre-production / playable graybox prologue.** A short biology-class sequence is playable from waking at a desk through the school exit. Its dialogue, primitive art, and synthesized sound are provisional. This is not the full game or production art; see the [implementation and validation note](docs/PROLOGUE_IMPLEMENTATION.md) for scope and limitations.

## Technical baseline

- **Engine:** Godot 4.7.2 Stable (standard build).
- **Language:** GDScript; no .NET/C# runtime.
- **Presentation:** 3D environments with a controlled 2.5D camera.
- **Target:** Windows PC first; keep the project portable for later Linux/Steam Deck evaluation.
- **Dependencies:** no mandatory online services, paid APIs, analytics, or proprietary runtime dependencies.

## Play the prototype

Open `project.godot` in **Godot 4.7.2 Stable, standard build**, let it import, then press F5 to run the main scene. There is no server or online dependency.

- **WASD / arrow keys:** move relative to the camera. **E:** interact with the nearest prompted object.
- **E / Enter:** advance dialogue; arrows select an answer; click an answer or press E / Enter to confirm.
- **H:** open/close conversation history. Its buttons adjust dialogue text size and instant/slow reveal. Use the mouse wheel or Page Up / Page Down to review long history.
- Search the schoolbag, explore, then press **Space** to wait for class. If asked, step away from the doorway/front desk before waiting.
- After N grants free activity, walk through the open classroom door or interact with it. In the corridor, return to class or reach the school-exit prompt. The endpoint offers return and restart.

The current session state is kept while revisiting areas, not saved to disk. Run the Linux headless checks with `GODOT=godot bash tests/run_headless.sh` after installing the pinned engine.

## Repository map

- AGENTS.md — authoritative coding-agent instructions.
- project.godot, scenes/, scripts/, data/ — Godot project, graybox runtime, and editable prototype dialogue.
- tests/ — scene smoke test and prologue integration checks.
- docs/ — concise, implementation-facing product, architecture, technical, narrative, art, prototype, and agent-evaluation references.
- docs/ASSET_PROVENANCE.md — asset rights and attribution ledger.

## Creative material

The repository is not a publication archive for the author's literary manuscripts. Do not add unpublished prose or extended manuscript-derived passages. Keep public narrative references limited to concise scene beats, implementation requirements, and dialogue explicitly approved for game use.

## Copyright and licensing

No MIT, Apache-2.0, or other open-source license is granted to the repository as a whole. Original project materials are reserved unless a specific file or component carries an explicit license or separate written permission. See [COPYRIGHT.md](COPYRIGHT.md). Third-party dependencies and assets remain under their own licenses.
