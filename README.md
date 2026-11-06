# where-is-school

> **A school that cannot remember you. A student who cannot leave.**

where-is-school is a painterly 2.5D surreal narrative exploration game about memory, institutional repetition, and unstable school spaces.

## Project status

**Pre-production — first playable milestone implemented.** The repository now
contains the Biology Class prologue: an adult wakes at a classroom desk, is talked
at by a classmate, finds their biology textbook missing, inspects the room,
rehearses a confrontation with an absent teacher, and is then released by a
substitute teacher into a corridor, onto the street, and out past a school gate.

Everything is graybox: primitives, flat materials, no textures, no portraits, no
authored audio. The game runs in Simplified Chinese by default and switches to
English with `L`. The rest of the game is not implemented.

See [`docs/PROLOGUE_ARCHITECTURE.md`](docs/PROLOGUE_ARCHITECTURE.md) for the
ownership boundaries between interaction, dialogue, presentation, and narrative
state, plus the validation record and known limitations.

## Start the project

1. Install the **standard (non-.NET) Godot 4.7.2 Stable** editor.
2. Clone this repository.
3. Import/open the repository root containing `project.godot`.
4. Run the project (F5). It starts in the classroom, seated at the desk.

| Action | Key |
|---|---|
| Move | `W` `A` `S` `D` or arrow keys (camera-relative) |
| Interact / advance dialogue | `E`, `Space`, or left click |
| Choose a reply | `1`–`4`, or click the choice |
| Dialogue history | `Tab` |
| Notes (provenance ledger) | `N` |
| Switch 简体中文 / English | `L`, or the button in the top-right |

The first minute is deliberately hands-off: the protagonist has just woken up, so
input is locked for a moment, and the classmate in the next seat starts talking on
his own before any prompt appears.

### Headless validation

~~~sh
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/smoke_test.gd
godot --headless --path . --script res://tests/content_privacy_test.gd
godot --headless --path . --script res://tests/narrative_state_test.gd
godot --headless --path . --script res://tests/prologue_flow_test.gd
godot --headless --path . --script res://tests/reachability_test.gd
godot --headless --path . --script res://tests/language_switch_test.gd
~~~

`smoke_test` checks scene composition and required props; `content_privacy_test`
checks that content stays bilingual, provenance-tagged, and free of manuscript
markers; `narrative_state_test` covers provenance and dialogue logic;
`prologue_flow_test` plays the whole slice headlessly; `reachability_test` proves
every required prop can be reached and targeted; `language_switch_test` proves the
UI shows one language at a time and that English never leaks Chinese. None of these substitutes for
playtesting camera comfort and pacing on a real GPU.

## Technical baseline

- **Engine:** Godot 4.7.2 Stable (standard build).
- **Language:** GDScript; no .NET/C# runtime.
- **Presentation:** 3D environments with a controlled 2.5D camera.
- **Target:** Windows PC first; keep the project portable for later Linux/Steam Deck evaluation.
- **Dependencies:** no mandatory online services, paid APIs, analytics, or proprietary runtime dependencies.

## Repository map

- AGENTS.md — authoritative coding-agent instructions.
- project.godot, scenes/, scripts/ — Godot project and starter runtime.
- docs/ — concise, implementation-facing product, architecture, technical, narrative, art, prototype, and agent-evaluation references.
- docs/ASSET_PROVENANCE.md — asset rights and attribution ledger.
- docs/PROLOGUE_ARCHITECTURE.md — how the implemented prologue is built, what it
  deliberately does not do, and the exact validation record.
- data/dialogue/ — all conversation and inspection text, separate from code.

## Creative material

The repository is not a publication archive for the author's literary manuscripts. Do not add unpublished prose or extended manuscript-derived passages. Keep public narrative references limited to concise scene beats, implementation requirements, and dialogue explicitly approved for game use.

## Copyright and licensing

No MIT, Apache-2.0, or other open-source license is granted to the repository as a whole. Original project materials are reserved unless a specific file or component carries an explicit license or separate written permission. See [COPYRIGHT.md](COPYRIGHT.md). Third-party dependencies and assets remain under their own licenses.
