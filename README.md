# where-is-school

> **A school that cannot remember you. A student who cannot leave.**

where-is-school is a painterly 2.5D surreal narrative exploration game about memory, institutional repetition, and unstable school spaces.

## Project status

**Third milestone: the free period, and the yard behind it.** The player wakes in
the biology classroom, talks to Q, searches the schoolbag, lives through an
expectation that is explicitly not a real event, and sits through the substitute's
lesson. When the substitute announces a free period the player is not pushed out of
the room: staying at the desk and leaving are both real, both recorded, and neither
one is a cutscene. Leaving brings Q along as a companion who walks, waits, and can
be asked along again; the walkway offers a few things to do that are not homework;
and the end door of the walkway opens onto the open schoolyard, which is walked in
any direction, has its own optional checks, and ends at the gap in the far fence.
The street, the residential courtyard and the green animal from the previous
milestone are unchanged and still reachable.

Everything the player reads is data, and the whole game can be switched between
English and simplified Chinese while it runs.

**Current route** (the intended way through the slice):

```
classroom (stay, or leave) → walkway → schoolyard (end card at the far gap)
                                ↓
                        street → residential courtyard → alley → schoolyard
```

The walkway is the short way in and the street is the long way round; both end in
the same yard, and the end card sits at `pg_gap_in_fence` in the yard, not at an
alley mouth.

See [docs/IMPLEMENTATION_NOTES_FREE_PERIOD.md](docs/IMPLEMENTATION_NOTES_FREE_PERIOD.md)
for this milestone's decisions, and
[docs/IMPLEMENTATION_NOTES_OPENING.md](docs/IMPLEMENTATION_NOTES_OPENING.md) for
controls, architecture, and the older known limitations.

## Technical baseline

- **Engine:** Godot 4.7.2 Stable (standard build).
- **Language:** GDScript; no .NET/C# runtime.
- **Presentation:** 3D environments with a controlled 2.5D camera.
- **Target:** Windows PC first; keep the project portable for later Linux/Steam Deck evaluation.
- **Dependencies:** no mandatory online services, paid APIs, analytics, or proprietary runtime dependencies.

## Controls

- **WASD / arrow keys** — walk (camera-relative).
- **E** — interact with the highlighted object or person. The highlight follows the
  mouse when the cursor is over something in reach, and the player's facing
  otherwise; both always name the same object E would use.
- **Space / Enter / left click** — continue dialogue, or answer with the numbered choice.
- **1–9** — pick a dialogue choice.
- **Tab** — open or close the dialogue log.
- **L** — switch between English and simplified Chinese at any time. The choice is remembered between runs.

## Repository map

- AGENTS.md — authoritative coding-agent instructions.
- project.godot, scenes/, scripts/ — Godot project and runtime.
- data/ — dialogue, inspection text, interface strings and character presentation data (content, not code). Authors start at `data/dialogue_schema/README.md`.
- docs/screenshots/ — frames captured from a real, running window by `tests/capture_playthrough.gd`.
- assets/ — placeholder materials and generated audio, tracked in docs/ASSET_PROVENANCE.md.
- tests/ — headless smoke, content, unit, and end-to-end flow tests run by CI.
- docs/ — concise, implementation-facing product, architecture, technical, narrative, art, prototype, and agent-evaluation references.
- docs/ASSET_PROVENANCE.md — asset rights and attribution ledger.
- tools/ — maintenance scripts (placeholder audio synthesis).

## Creative material

The repository is not a publication archive for the author's literary manuscripts. Do not add unpublished prose or extended manuscript-derived passages. Keep public narrative references limited to concise scene beats, implementation requirements, and dialogue explicitly approved for game use.

## Copyright and licensing

No MIT, Apache-2.0, or other open-source license is granted to the repository as a whole. Original project materials are reserved unless a specific file or component carries an explicit license or separate written permission. See [COPYRIGHT.md](COPYRIGHT.md). Third-party dependencies and assets remain under their own licenses.
