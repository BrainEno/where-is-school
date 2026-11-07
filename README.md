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

The slice can be played with the mouse or with the keyboard. Clicking the floor walks
there; clicking a person, a prop or a door walks over and uses it on arrival, running
the same activation the E key runs. Every playable location carries its own navigation
mesh, baked when it loads.

Everything the player reads is data, and the whole game can be switched between
English and simplified Chinese while it runs — including the sentence on screen, the
log behind it and the names over the people in the room.

## Reading the game

The dialogue is a band of text at the lower left of the picture, not a window over it.
The room stays visible; the band fades into the scene instead of framing itself. Inside
it, in this order: a single hairline in the colour of the narrative source, the
speaker's name (large, tracked, tinted by the character), the role (small, quiet), the
sentence (the largest thing on screen, with a measured line width and line spacing), a
numbered list of options on their own lines under a rule, and a hint. Long prose scrolls
inside the band; the type size never shrinks to make it fit, and the layout is measured
from the real content at 1280x720, 1600x900 and 1920x1080. The four sources — seen,
heard, remembered, imagined — stay distinguishable through that hairline and a small
label, not through badges or loud colours.

In development builds each grey-box person carries their name above their head, from
the same character profile and the same locale tables as the dialogue, so it changes
with the language. The labels have no collision and never receive a click, and they are
off in a release export (override with
`ui/nameplates/show_development_nameplates`).

**Current route** (the intended way through the slice):

```
classroom (stay, or leave) → walkway → schoolyard (end card at the far gap)
                                ↓
                        street → residential courtyard → alley → schoolyard
```

The walkway is the short way in and the street is the long way round; both end in
the same yard, and the end card sits at `pg_gap_in_fence` in the yard, not at an
alley mouth.

See [docs/IMPLEMENTATION_NOTES_NAVIGATION.md](docs/IMPLEMENTATION_NOTES_NAVIGATION.md)
for the mouse-navigation round (click-to-move, automatic interaction, evidence and
limitations), [docs/IMPLEMENTATION_NOTES_FREE_PERIOD.md](docs/IMPLEMENTATION_NOTES_FREE_PERIOD.md)
for the free-period milestone's decisions, and
[docs/IMPLEMENTATION_NOTES_OPENING.md](docs/IMPLEMENTATION_NOTES_OPENING.md) for
controls, architecture, and the older known limitations.

## Technical baseline

- **Engine:** Godot 4.7.2 Stable (standard build).
- **Language:** GDScript; no .NET/C# runtime.
- **Presentation:** 3D environments with a controlled 2.5D camera.
- **Target:** Windows PC first; keep the project portable for later Linux/Steam Deck evaluation.
- **Dependencies:** no mandatory online services, paid APIs, analytics, or proprietary runtime dependencies.

## Controls

- **WASD / arrow keys** — walk (camera-relative). Holding any of them also stops an
  automatic walk in progress: the keys always win.
- **Left click on the floor** — walk there. The route follows the location's
  navigation mesh, so it goes around desks, walls and fences; a quiet ring marks the
  spot and disappears when the walk ends. Clicking a wall, a desk top or anything else
  that is not walkable is refused instead of being walked at.
- **Left click on a person or an object** — walk to a suitable spot next to it and use
  it on arrival. A click on something already within reach uses it at once. This is
  the same activation the E key performs; the object decides what it does, so a
  clicked door, exit or prop behaves exactly like a pressed one.
- **E** — use whatever is highlighted, without moving. The highlight follows the mouse
  when the cursor is over something in reach, and the player's facing otherwise; both
  always name the same object E would use. E remains the keyboard-only way to
  interact.
- **Space / Enter** — continue dialogue.
- **Left click on a dialogue option** — take that option. Options are real buttons
  drawn as text lines, so a click selects exactly one, the same option cannot be taken
  twice, and clicks on the panel never reach the world.
- **1–9** — pick a dialogue choice by number.
- **Tab** — open or close the dialogue log. Entries keep their identity and their order
  when the language changes; only their words do.
- **L** — switch between English and simplified Chinese at any time. The choice is remembered between runs.

While a conversation, a scripted beat or a location transition is running, the
character does not move and world clicks are ignored (the walk in progress is
cancelled rather than resumed afterwards).

## Navigation

Six locations are playable — the classroom, the walkway, the street, the residential
courtyard, the alley and the schoolyard — and **each one owns its own navigation mesh**.
Nothing is imported from a neighbouring room and nothing is hand-painted: every
location scene has a `NavigationRegion3D` named `Navigation` that bakes itself from
that scene's own static colliders when the location loads
(`scripts/world/location_navigation.gd`). The player walks the route the map returns
with one movement implementation, so a clicked walk accelerates, collides and turns
exactly like a walked one.

Adding navigation to a new location is therefore one node and one line:

```
[node name="Navigation" type="NavigationRegion3D" parent="."]
script = ExtResource("<id>_navigation")
```

It must be a direct child of the location root, and the walkable floor must be made of
`StaticBody3D` colliders (props that are only meshes are decoration and stay
pass-through, as before). The four generated outdoor locations get the same node from
`tools/build_outdoor_locations.py`; re-run that script rather than editing those scenes
by hand. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#5f-navigation-click-to-move-and-automatic-interaction)
for the movement and activation contracts, and
[docs/TECHNICAL_ROADMAP.md](docs/TECHNICAL_ROADMAP.md) for what is deliberately still
missing.

## Repository map

- AGENTS.md — authoritative coding-agent instructions.
- project.godot, scenes/, scripts/ — Godot project and runtime.
- data/ — dialogue, inspection text, interface strings and character presentation data (content, not code). Authors start at `data/dialogue_schema/README.md`.
- docs/screenshots/ — frames captured from a real, running window by
  `tests/capture_playthrough.gd`, plus the dialogue layout frames written by
  `tests/capture_dialogue_ui.gd` at 1280x720, 1600x900 and 1920x1080 in both languages.
- assets/ — placeholder materials and generated audio, tracked in docs/ASSET_PROVENANCE.md.
- tests/ — headless smoke, content, unit, and end-to-end flow tests run by CI.
- docs/ — concise, implementation-facing product, architecture, technical, narrative, art, prototype, and agent-evaluation references.
- docs/ASSET_PROVENANCE.md — asset rights and attribution ledger.
- tools/ — maintenance scripts (placeholder audio synthesis).

## Creative material

The repository is not a publication archive for the author's literary manuscripts. Do not add unpublished prose or extended manuscript-derived passages. Keep public narrative references limited to concise scene beats, implementation requirements, and dialogue explicitly approved for game use.

## Copyright and licensing

No MIT, Apache-2.0, or other open-source license is granted to the repository as a whole. Original project materials are reserved unless a specific file or component carries an explicit license or separate written permission. See [COPYRIGHT.md](COPYRIGHT.md). Third-party dependencies and assets remain under their own licenses.
