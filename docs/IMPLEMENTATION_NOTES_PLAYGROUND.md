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
- the alley is deliberately one lane wide with a single bay, the yard deliberately
  open with an empty middle. Do not add content to fill the middle: it is reserved
  for people and events later.

Adding an anchor means: add the geometry and the `Interactables` entry in
`tools/build_outdoor_locations.py`, regenerate, then add the inspection (or a
conversation route and its conversation) in **both** languages.
`tests/content_integrity_test.gd` fails the build if the ids do not line up.

## 3. Adding an inner voice

1. Add the ability to `data/abilities/abilities.json` (`value`, optional `speaker`,
   `max_passive`) and its name/description to every `data/abilities/<locale>.json`.
2. Add `data/characters/voice_<id>.tres` and register it in
   `CharacterDirectory.CHARACTER_PATHS` (the list is explicit so exported builds
   include it).
3. Use it in content: a `check` block on a node, or a passive rule plus a
   conversation that opens with a hidden check.
4. Run `inner_abilities_test` — it fails if a voice exists but nothing uses it, if a
   rule points at a missing conversation, or if the text was not translated.

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
- Two of the four voices (Ledger, Onlooker) are only reachable through one anchor
  each. That is content depth, not a system limit.


## Superseded in part

The yard is still the end of the slice, but the route into it changed: the walkway's
end door now leads into the yard from the school side, and the alley route is the long
way round rather than the only one. The yard also gained tyres, an equipment
container, outdoor fitness gear and birds, and the checks were re-pointed at the one
provisional voice on the provisional 2d6 formula. See
[IMPLEMENTATION_NOTES_FREE_PERIOD.md](IMPLEMENTATION_NOTES_FREE_PERIOD.md) for the
current state; this file is kept for the regeneration steps and the earlier reasoning.
