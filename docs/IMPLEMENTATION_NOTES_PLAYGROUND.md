# Implementation notes — the open yard, inner voices, checks

Companion to ADR 0003. This file records the *engineering* details that do not
belong in the ADR: how the space is generated, how to change it, what is verified
and what is not.

## 1. What was added

| Area | Files |
|---|---|
| Space | `scenes/locations/alley/alley.tscn`, `scenes/locations/playground/playground.tscn` (both generated) |
| Generator | `tools/build_outdoor_locations.py` (`build_alley`, `build_playground`) |
| Content | `data/dialogue/{en,zh-CN}/{alley,playground,inner_voice}.json`, `data/inspections/{en,zh-CN}/{alley,playground}.json` |
| Abilities | `data/abilities/abilities.json`, `data/abilities/{en,zh-CN}.json`, `data/characters/voice_*.tres` |
| Code | `scripts/rpg/check_resolver.gd`, `scripts/rpg/inner_abilities.gd`, `scripts/world/inner_voice_director.gd`, `scripts/ui/check_overlay.gd` + `scenes/ui/check_overlay.tscn` |
| Wiring | `dialogue_graph.gd` (check parsing), `dialogue_runtime.gd` (resolution), `dialogue_controller.gd` (presentation), `opening_sequence.gd` (arrivals, objective), `story_flags.gd` (flag helpers) |
| Tests | `check_resolver_test`, `inner_abilities_test`, `dialogue_check_test`, `content_integrity_test`, `playground_flow_test` (all new), `opening_flow_test` (extended to the yard) |

## 2. Regenerating and editing the space

```bash
python3 tools/build_outdoor_locations.py
```

The geometry is a box table per scene. Edit the table, not the `.tscn`: the
generator rewrites `street`, `residential`, `alley` and `playground` every run, so a
hand edit to any of those four files is lost.

Conventions kept from the earlier outdoor work:

- everything is a `StaticBody3D` with a `BoxMesh`, so the graybox stays cheap;
- big masses are tagged `camera_occluder` so the 2.5D camera can fade them;
- interactables and exits live under `Interactables`, spawn points under
  `SpawnPoints` in the `spawn_point` group;
- an interactable's `support_paths` (the props it may be seen through, e.g. the pole a
  notice is mounted on) is a `support` entry in the same table, never a hand edit: the
  generator rewrites the four scenes and used to drop it;
- the alley is deliberately one lane wide with a single bay, the yard deliberately
  open with an empty middle. Do not add content to fill the middle: it is reserved
  for people and events later.

Adding an anchor means: add the geometry and the `Interactables` entry in
`tools/build_outdoor_locations.py`, regenerate, then add the inspection (or a
conversation route and its conversation) in **both** languages.
`tests/content_integrity_test.gd` fails the build if the ids do not line up.

## 3. Adding an inner voice

The order matters, because each step validates the one before it.

1. Add the ability to `data/abilities/abilities.json`: a `value`, a `speaker` id that
   no other voice and no ordinary character uses, and a `max_passive` cap. Its name
   and description go into every `data/abilities/<locale>.json`, translated (identical
   text in two languages is rejected as an unfinished translation).
2. Add the voice's presentation profile at `data/characters/<speaker>.tres`, with
   `character_id` equal to that speaker id. Nothing else has to be edited: the
   character directory resolves voices from the registry, so there is no second list
   to keep in sync. A missing or mismatched profile is a start-up error, not a silent
   fallback to another voice's name and colour.
3. Use it in content: a `check` block on a node, or a passive rule plus a
   conversation that opens with a hidden check. When two rules can answer one event,
   the one earlier in `abilities.json` speaks; that order is the priority, so moving a
   rule up the file is how you make it win.
4. Run `inner_abilities_test` — it fails if a voice exists but nothing uses it, if a
   rule points at a missing conversation, or if the text was not translated.
   `tests/multi_voice_test.gd` proves the multi-voice plumbing itself with fixtures
   that never enter `data/`.

## 4. Verified, and how

Verified by CI (run `42349573289`, Godot 4.7.2 Stable standard build, headless):

- `godot --headless --editor --path . --quit` imports cleanly.
- Static syntax gate over every `.gd` file (gdtoolkit `gdparse`).
- Fifteen headless checks, including the five new ones and the extended
  end-to-end flow.
- The capture job (`42349573295`) drove the real game through the new slice with
  simulated key presses and produced frames for the alley, the yard, the shed's
  choice list, the visible check panel and the end card.

Not verified:

- Anything requiring a human at a keyboard (camera comfort, pacing, how often the
  voices speak). See the checklist in the pull request.
- The screenshots are rendered headless under Xvfb through a simulated input path;
  they are evidence of layout and text, not of feel.
- Performance on the target Windows hardware. The yard adds ~90 boxes and no new
  materials; that should be negligible, but it has not been measured on real
  hardware.

## 5. Known rough edges

- The yard's lighting is the same dusk rig as the rest of the outdoors; the far
  half of the court is a slightly darker wash plane rather than a second light
  setup. It reads correctly in the frames but it is a trick.
- `CheckOverlay` is positioned at the top centre and does not move out of the way of
  the dialogue panel on very short windows. Untested below 720p.
- The bag on the bench and the metal tag under the shed are geometry with text, not
  items: nothing can be picked up, and nothing should be until an inventory exists.
- `PingPongBall` and `PaleUnderHedge` are separate boxes with no collision. They are
  scenery for the `pg_ball` conversation.
- Two of the inner voices that this note was written against (Ledger, Onlooker) are
  gone: the milestone now ships one provisional voice, so those two anchors are plain
  inspections.
- The alley mouth is a 3.4 m-high arch in the north block and has no light of its own, so
  it is darker than the courtyard. It is readable in the greybox, but it has not been lit
  as a place yet.
- The courtyard's stair sits inside `BlockWest` (x -15.3..-11.9 against a block face at
  x = -11), so it, its `res_stair` interactable and the unused `FromStair` spawn marker
  are buried in solid geometry. It is a coordinate error from before this round and it is
  not fixed here; the slice never routes a player through it.
  each. That is content depth, not a system limit.


## 6. The alley mouth (issue #33)

The courtyard's way out to the lane behind the flats was painted, not built. `AlleyGround`
and `PathNorth` were mesh-only boxes — no `StaticBody3D`, so no collider and no geometry
for the navigation bake — and they also sat about three metres east of the courtyard side
of the route. The result: the exit `res_alley_end` led into a strip the player could not
stand on, and coming back out of the lane dropped the player (`FromAlley`) onto the same
dead strip, 4.75 m from the nearest navigation polygon.

Fixed in the geometry table, not in the runtime:

| Was | Is |
|---|---|
| `BlockNorth`, one solid 34 m wall across the north side | split into `BlockNorthWest` (x -17..2.8) and `BlockNorthEast` (x 9.2..17), both 17 m tall; `AlleyLintel` fills y 3.4..17 over the first 2 m of the gap, so the courtyard sees a 6.4 m wide, 3.4 m high arch in one facade rather than two separate buildings |
| `AlleyGround`, a 0.04 m mesh-only slab at y 0.02, x 3.2..8.8 | a 0.1 m `StaticBody3D` at x 2.8..9.2, z -36..-22, whose **top face is exactly y = 0** and whose south edge butts the courtyard's north edge at z = -22 |
| `PathNorth`, a second mesh-only strip inside the old wall | removed: the lane's own floor is the path now |
| the lane's retaining walls, z -32..-24 | lengthened to z -36..-22 so they reach the courtyard edge, and `AlleyBackWall` closes the far end: walls that stopped short left a 0.4 m slot with no floor under it, which a player walking the edge could fall into |

The gap in the block matches the lane exactly: 6.4 m between the two masses, 5.6 m between
the retaining walls, and no step at any of the joins. The navigation bake runs straight
through it — agent radius 0.4 m still leaves ~4.8 m of walkable width in the narrowest
part. `FromAlley` stands at y = 0 on a floor whose top face is y = 0, and the route from
the courtyard spawn to `res_alley_end` is about 43 m long. The lane is closed on all four
sides now, so there is no edge to walk off.

Evidence in the test suite, both ends:

- `tests/location_transition_test.gd` walks the pair as routes
  (`_check_the_flats_and_the_lane_connect`) and prints the length, and its allowlist for
  off-mesh arrivals (`KNOWN_OFF_MESH`) is gone: every arrival is held to 3.0 m again.
- `tests/navigation_test.gd` now asks for a walkable route from the spawn to *every*
  exit of every location instead of to one of them, so the courtyard's alley exit is
  held to being reachable, not merely present.

What this does not claim: nobody has walked the mouth with a human at the keyboard, the
arch has no light of its own, and the courtyard's stair is still where it always was —
inside `BlockWest`, with its `StairLook` interactable and the unused `FromStair` marker
buried in the same block (the stair needs its own issue; nothing in the slice routes
through it).

## Superseded in part

The yard is still the end of the slice, but the route into it changed: the walkway's
end door now leads into the yard from the school side, and the alley route is the long
way round rather than the only one. The yard also gained tyres, an equipment
container, outdoor fitness gear and birds, and the checks were re-pointed at the one
provisional voice on the provisional 2d6 formula. See
[IMPLEMENTATION_NOTES_FREE_PERIOD.md](IMPLEMENTATION_NOTES_FREE_PERIOD.md) for the
current state; this file is kept for the regeneration steps and the earlier reasoning.
