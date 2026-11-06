# where-is-school

> **A school that cannot remember you. A student who cannot leave.**

where-is-school is a painterly 2.5D surreal narrative exploration game about memory, institutional repetition, and unstable school spaces.

## Project status

**Playable prologue milestone.** The repository now contains the biology-class
opening: the protagonist wakes at a desk, is talked at by Q, finds the biology
textbook missing, inspects the room, rehearses a confrontation that does not
happen, watches a substitute teacher take the lesson, and walks out through a
corridor to the school gate. The street and green-animal sequence are the next
milestone and are not implemented.

## Technical baseline

- **Engine:** Godot 4.7.2 Stable (standard build).
- **Language:** GDScript; no .NET/C# runtime.
- **Presentation:** 3D environments with a controlled 2.5D camera.
- **Target:** Windows PC first; keep the project portable for later Linux/Steam Deck evaluation.
- **Dependencies:** no mandatory online services, paid APIs, analytics, or proprietary runtime dependencies.

## Playing it

Open the project in Godot 4.7.2 Stable and press F5, or:

~~~text
godot --path .
~~~

| Input | Action |
|---|---|
| WASD / arrows | walk |
| E or left click | inspect, talk, open, leave |
| Space / Enter | advance dialogue |
| 1–4 | choose a reply |
| Tab | backlog of the current conversation |
| N | notes: seen / heard / remembered / imagined |
| Esc | controls panel |

## Repository map

- AGENTS.md — authoritative coding-agent instructions.
- project.godot, scenes/, scripts/, data/ — Godot project and the prologue slice.
- docs/PROLOGUE_ARCHITECTURE.md — how interaction, dialogue, rehearsal, and story state are wired.
- docs/ — product, architecture, technical, narrative, art, prototype, and agent-evaluation references.
- docs/ASSET_PROVENANCE.md — asset rights and attribution ledger.
- tests/ — headless smoke test, unit tests, and integration tests.

## Testing

~~~text
godot --headless --editor --path . --quit                      # import + parse
godot --headless --path . --script res://tests/smoke_test.gd    # scene smoke
godot --headless --path . --script res://tests/test_runner.gd   # unit + integration
~~~

## Creative material

The repository is not a publication archive for the author's literary manuscripts. Do not add unpublished prose or extended manuscript-derived passages. All prologue dialogue and inspection text is new placeholder writing created for the game; it is flagged as such in the content files and can be replaced wholesale once the owner approves final lines.

## Copyright and licensing

No MIT, Apache-2.0, or other open-source license is granted to the repository as a whole. Original project materials are reserved unless a specific file or component carries an explicit license or separate written permission. See [COPYRIGHT.md](COPYRIGHT.md). Third-party dependencies and assets remain under their own licenses; the bundled Noto Sans CJK font is SIL OFL 1.1 and is recorded in `docs/ASSET_PROVENANCE.md`.
