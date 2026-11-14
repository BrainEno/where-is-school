# Implementation notes: the laboratory (issue #163)

A standalone location scene, built to be judged on its own and then handed to the owner to
decide how a chapter uses it. It is not wired into the main line, it does not replace the
opening, and it touches no classroom file.

```
scenes/locations/laboratory/laboratory.tscn   the room (generated)
scenes/locations/laboratory/spinner.gd        the one part of it that moves
assets/materials/laboratory/*.tres            26 material presets (generated)
assets/materials/laboratory/textures/*.png    4 painted fields (generated)
assets/audio/laboratory_hum.wav               the room's bed (synthesised)
data/inspections/{en,zh-CN}/laboratory.json   9 descriptions, both languages
art/laboratory/paint_laboratory_textures.py   paints the four fields
tools/build_laboratory.py                     emits the materials and the scene
tests/laboratory_visual_slice_test.gd         what CI checks
tests/capture_laboratory.gd                   the twelve evidence frames
tests/capture_laboratory_walkthrough.gd       the recorded walkthrough
.github/workflows/laboratory-capture.yml      renders both, on both renderers
```

## The space

15.2 x 11.2 m of floor inside a 3.4 m shell, with no ceiling over the working half: the
camera looks down into the room, and a lid over the working area would hide it.

| Zone | Where | What says "someone works here" |
|---|---|---|
| Wet bench | west wall, tile splashback | two sinks, a drying rack, one flask still wet |
| Fume hood | north wall | sash at working height, three bottles, a duct that keeps going after the ceiling stops |
| Glassware cabinet | north wall | ranked flasks, stacked beakers, one empty shelf, unlocked doors |
| Analysis island | centre, with stools | two microscopes with a slide still on the stage, a centrifuge, the open log book |
| Instrument bank | east wall | four machines, four cables leaving the back of them, a controller gauge at zero |
| Mixing drum | centre, running | warm drum, turning vane, a green running light, and a screwed-down plate where a switch should be |

The five zone footprints are asserted to be separate floor rectangles
(`tests/laboratory_visual_slice_test.gd`), so "the room is divided" is a checked claim rather
than a description.

**The second room.** A partition across the north-east corner, with a 1.5 m opening in it
that the steel jambs narrow to 1.3 m of visible door. Behind it: the floor a step down, a
soffit that brings the ceiling down to 2.6 m instead of 3.4 m, one bulb on a cord, a shaft
that leaves that soffit and climbs to 5.5 m (past the top of the building), a floor hatch
where the cables end, and a
second doorway in the north wall whose corridor runs on past the building's own footprint
and stops at an unshaded black wall. Nothing in the room explains any of it, and the room
adds no text of its own.

## The cables

Every machine trails a cable. They start where a cable would start — the back of each
instrument, the hood's duct, the board's socket, the bench lamp, the balance, the drum's
motor, one drop from a ceiling fixture — reach the floor, cross it, and gather at a knot
between the island and the drum: three slack coils, a tangle, and eight cables tied into one
bundle. The bundle crawls north along the partition, goes through the narrow door, crosses
the annex floor and ends in the hatch.

- 401 segments, 28 runs, none of them above the walls.
- The five zone -> knot runs and the knot -> hatch bundle are the path a player can follow
  with their eyes at any point; there is no cable that exists only as decoration on a wall.
- **The first version of them was 12 mm thick and did not read at all.** At the follow
  camera's seven-odd metres a 12 mm cylinder is under a pixel across, and a run only shows
  the part of itself that faces the camera — its drops and its ends — so the frames showed
  a floor with a scattering of short black pegs on it instead of wire. They are 20-28 mm
  now: a cable, still, and a line you can follow from machine to knot to door.
- A leg already on the floor no longer sags. Sag is applied only while both ends of a leg
  are above 0.35 m, so what hangs from a fixture hangs and what lies down stays flat
  instead of sinking into the slab and surfacing as those same pegs.
- They are not solid. A cable is 20-28 mm; a collider would carve the navigation mesh and
  turn a thing to look at into a thing to trip on. The one run that crosses the main aisle
  is covered by a walkable steel ramp, and the ramp keeps no collider above the floor line.

## Light

Eight lights, no global illumination and no glow: five tube fixtures at 2.86 m (two of them
cast shadows, the rest do not, so the frame keeps a direction without ten shadow maps), the
annex bulb, the bench lamp and one weak light in the far corridor. The environment fills at
0.45 with a *neutral-warm* ambient — the first pass filled at 0.62 with a blue-grey one, and
the plaster, the resin bench top and the tile all came out as one pale blue field with no
shadow left in it. The coldness belongs to the tubes; the room it lights is grey and beige.

## Navigation and collision

- The room owns a `NavigationRegion3D` with `scripts/world/location_navigation.gd`, which
  bakes from the location's own colliders at load time, as every location does.
- **The two doorways are 1.5 m wide and 2.45 m tall on purpose.** The bake erodes the
  walkable surface by `agent_radius` (0.5 m) on each side and quantises height in 0.25 m
  cells, so a 0.95 m door — the first version of this room — is baked shut, and the annex
  and the far corridor become unreachable while still looking open. The steel jambs carry
  no collider, so the door still *reads* narrower than the opening the bake sees.
- Nothing collides that cannot be seen: every `StaticBody3D` in the scene is a box whose
  size is its own box mesh's size (checked), and decoration and cables carry no collision
  at all.
- The far corridor ends in a box with the black material on it, not in an invisible wall:
  what stops the player is the surface they can see.

## Interaction

Nine anchors, all through the existing `Interactable` contract (`interact_id`,
`inspection_id`, `prompt_key` from `data/inspections/`, outline paths into the scene's own
meshes, no ground ring):

`laboratory_wet_bench`, `laboratory_fume_hood`, `laboratory_glass_cabinet`,
`laboratory_log_book`, `laboratory_microscope`, `laboratory_mixer`,
`laboratory_instruments`, `laboratory_cable_knot`, `laboratory_annex_door`.

All nine exist in English and Simplified Chinese. The texts describe what is in the scene —
the open tap, the labels turned to the wall, the slide still on the stage, the plate screwed
over the switch — and none of them names a character, gives a reason, or draws a conclusion.

## Deliberate omissions

- **No entry in `data/story/locations.json`.** The catalogue says what a room *declares*
  (objective line, arrival conversation, start flag); the laboratory declares nothing, and a
  room that declares nothing still loads (`LocationCatalog` is explicit about it). How and
  when a chapter enters this room is the owner's decision, and registering it now would
  claim a place in the current slice that this change is not allowed to take.
- **No exit.** The entrance door on the south wall is a door, not a `LocationExit`. The
  scene has nothing to lead back to, and adding an exit would wire it into the main line.
- **No dialogue and no story flags.** Reading an object records nothing and sets nothing.
- **No music.** `assets/audio/laboratory_hum.wav` is a 6 s looped bed: 54/55 Hz beating
  against each other with two partials above and a filtered noise floor.

## Tests

| What | Where | Why it is there |
|---|---|---|
| The room, its zones, walls, solids, cables, annex geometry, material ownership, textures, texts, the spinner, navigation, the game camera, and that the scene stays unregistered | `tests/laboratory_visual_slice_test.gd` | `godot-ci.yml`, `run_check laboratory_visual_slice` |
| Inspection ids resolve in both languages | `tests/content_integrity_test.gd` (`LOCATIONS` now includes `laboratory`) | the same test that checks every other scene's anchors |
| The scene and the materials match their generator | `tools/build_laboratory.py --check`, `art/laboratory/paint_laboratory_textures.py --check` | `godot-ci.yml`, next to the model and music reproducibility checks |
| Frames and the recording | `tests/capture_laboratory.gd`, `tests/capture_laboratory_walkthrough.gd` | `.github/workflows/laboratory-capture.yml` |

Run one check by hand:

```bash
godot --headless --path . --script res://tests/laboratory_visual_slice_test.gd
```

## Not done, and known limits

- The room is not wired into a chapter, has no arrival conversation and no objective line.
- `tests/location_art_test.gd` does not list it yet: that test's per-location table records
  a runtime collider count and an exit map for scenes it was written for, and adding a
  seventh entry there belongs with the change that decides where the room sits in the story.
- The far corridor is 2.8 m of walkable floor that ends in black. It is a deliberate dead
  end, not an unfinished area, and the acceptance frames show it as one.
- The FollowCamera's occluder fade covers the walls (`camera_occluder` group). Nothing in
  the annex is a lid: the low ceiling is a perimeter soffit at 2.6 m, with the middle open,
  because the camera looks down into the room from above and a full ceiling would hide the
  player from it — no other interior in the project has one either. The soffits, the shaft
  and the far corridor walls are props outside the group.
