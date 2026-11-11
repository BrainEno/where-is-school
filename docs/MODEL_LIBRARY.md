# The model library

`docs/ASSET_PIPELINE.md` says what a model must be. This file says what is actually in
`assets/models/`: which kind every model belongs to, what each one measures, where its
origin sits, which greybox scene it is meant to replace, and what still has to happen
before a location may instance it.

The numbers are not typed by hand. They are printed by `python3 tools/model_library.py
--report`, which parses the committed `.glb` files, and `tools/model_library.py --check`
runs in CI so a new file that breaks the contract fails at the commit instead of at the
release. Anything below that the tool cannot know is marked as such.

## 1. How the tree is organised

A model lives at `assets/models/<kind>/<name>.glb`, and **the kind is the place the model
is instanced**: `classroom/`, `corridor/`, `playground/`, and the two character kinds
`protagonist/` and `q/`. That is the same unit the rest of the project is assembled in —
`scenes/locations/<location>/` — so a kind folder is exactly the set of props one location
draws from:

| Kind | Models | Instanced by |
|---|---|---|
| `classroom/` | 11 | `scenes/locations/classroom/classroom.tscn` |
| `corridor/` | 3 | `scenes/locations/corridor/corridor.tscn` |
| `playground/` | 2 | `scenes/locations/playground/playground.tscn` |
| `protagonist/`, `q/` | 1 each | the player and NPC controllers, via `scenes/environment/characters/` |
| `school_desk/`, `stationery_supplies/`, `playground_bench/`, `student_backpack/` | 1 each | the wrappers in `scenes/environment/props/` |
| `sample/` | 2 | test fixtures, built by `tools/build_sample_models.py` |

Four rules keep it that way:

- **A model has one home.** A prop that two rooms want keeps one kind folder and the other
  room instances its wrapper — a `.tscn` reference, not a second copy of the geometry.
- **The name carries the kind.** `classroom_student_desk.glb`, not `desk.glb`: a search for
  `classroom_` then finds the model, its wrapper, its test and its provenance row together.
  Names are unique across the whole library, so no name search ever returns two files.
- **One-model directories stay one-model directories.** `school_desk/`, `q/` and the three
  other single-asset folders are the shape earlier rounds used, and their wrappers, tests
  and provenance rows name those paths. A *set* added from now on is `<kind>/`.
- **Nothing here carries a sidecar-less file.** Godot writes `<name>.glb.import` beside every
  imported model and the repository commits it; `--check` fails if one is missing, or if its
  `dest_files` hash no longer matches the model's path — which is what `git mv`-ing a model
  without its `.import` produces.

## 2. The classroom, corridor and playground sets

Seventeen `.glb` files arrived in PR #85 as an unclassified folder, `assets/models/new
models/` (a path with a space in it, no `.import` sidecars, nothing referencing them). They
were the owner's classroom furniture, corridor fixtures and playground props in one bag.
This round sorted them by the room they belong to, gave each one a sidecar, and recorded
what they measure. Nothing was re-exported: the files are byte-for-byte what was uploaded.

The split is by place, not by material or function — a `furniture/`+`fixtures/`+`outdoor/`
taxonomy would have been just as easy to draw and would have told the next person nothing,
because no scene in this project ever needs "all the wood" or "all the metal". It needs
"the things in this room".

### 2.1 `classroom/` — 11 models, 2175 KiB

| model | KiB | tris | materials | textures | W × H × D (m) | min y (m) | max y (m) |
|---|---|---|---|---|---|---|---|
| `classroom_biology_chart` | 279.3 | 6464 | 8 | — | 0.91 × 1.18 × 0.11 | -0.590 | +0.590 |
| `classroom_blackboard` | 129.0 | 2448 | 9 | — | 5 × 1.59 × 0.27 | +0.845 | +2.437 |
| `classroom_ceiling_fan` | 144.7 | 3496 | 3 | — | 1.28 × 0.46 × 1.28 | -0.462 | +0.000 |
| `classroom_door_assembly` | 147.1 | 3064 | 9 | — | 1.21 × 2.21 × 0.2 | +0.000 | +2.208 |
| `classroom_student_chair` | 133.5 | 2916 | 5 | — | 0.44 × 0.81 × 0.43 | +0.040 | +0.855 |
| `classroom_student_desk` | 157.9 | 3380 | 8 | — | 1.26 × 0.8 × 0.6 | +0.000 | +0.804 |
| `classroom_teacher_chair` | 135.6 | 2916 | 4 | — | 0.49 × 0.95 × 0.51 | +0.034 | +0.982 |
| `classroom_teacher_lectern` | 187.2 | 4112 | 10 | — | 1.9 × 0.99 × 0.85 | +0.035 | +1.021 |
| `classroom_wall_clock` | 205.9 | 4916 | 7 | — | 0.47 × 0.47 × 0.14 | -0.235 | +0.235 |
| `classroom_window_curtains` | 482.6 | 16016 | 7 | — | 1.96 × 1.48 × 0.18 | -1.422 | +0.055 |
| `classroom_window_module` | 172.4 | 3704 | 7 | — | 1.78 × 1.42 × 0.24 | -0.742 | +0.680 |

### 2.2 `corridor/` — 3 models, 156 KiB

| model | KiB | tris | materials | textures | W × H × D (m) | min y (m) | max y (m) |
|---|---|---|---|---|---|---|---|
| `corridor_cleaning_trolley` | 80.3 | 1992 | 10 | — | 0.95 × 1.43 × 0.7 | +0.020 | +1.452 |
| `corridor_fire_extinguisher` | 31.0 | 420 | 6 | — | 0.42 × 0.81 × 0.28 | +0.050 | +0.858 |
| `corridor_noticeboard` | 45.0 | 684 | 7 | — | 1.78 × 1.18 × 0.19 | +0.862 | +2.038 |

### 2.3 `playground/` — 2 models, 159 KiB

| model | KiB | tris | materials | textures | W × H × D (m) | min y (m) | max y (m) |
|---|---|---|---|---|---|---|---|
| `playground_sports_duffel` | 22.3 | 364 | 5 | — | 1 × 0.69 × 0.45 | +0.008 | +0.697 |
| `playground_tyre_stack` | 136.4 | 4016 | 2 | — | 1.84 × 0.77 × 1.06 | +0.030 | +0.799 |

The 16 models are 2.4 MiB and 60,908 triangles together — 15 % of the 16 MiB release
budget (§9 of the pipeline document) if a scene ever placed all of them at once. One file,
`classroom_window_curtains` at 482.6 KiB, is over the model category's 384 KiB warning
line, and that is the only note `--check` prints about this set.

### 2.4 Reading the table

`W × H × D` is the world-space bounding box after every node transform — a model's own
numbers, not a guess from its accessors. `min y` and `max y` are that box measured from the
model's origin, which is the number a wrapper is built from:

- **A floor prop should have `min y` at 0.** Where it does not, the difference is how far it
  floats, and the wrapper's `Model` child takes `position.y = -min.y` — the same correction
  `stationery_supplies.tscn` already carries for its own 7.4 cm (pipeline §10.2). In this
  set: student desk and door exactly 0; the student chair 4.0 cm, the teacher chair 3.4 cm,
  the lectern 3.5 cm, the trolley 2.0 cm, the extinguisher 5.0 cm, the duffel 0.8 cm, the
  tyre stack 3.0 cm. Those eight are the whole of the "origin is not quite the floor"
  story — the same few-centimetre deviation the playground bench (−0.7 cm) and the
  protagonist (−1.7 cm) have carried since they were imported.
- **A ceiling fixture hangs from its origin.** The fan reaches from `max y` = 0.000 down to
  −0.462: drop its origin on the ceiling plane and it hangs 46 cm below it, blades included.
- **A wall fixture is one of two things, and the set is not consistent about which.** The
  blackboard (`min y` +0.845) and the noticeboard (+0.862) put their origin at the floor
  under the board, so they are placed by standing them on the floor at the wall. The
  biology chart (−0.590 / +0.590) and the wall clock (−0.235 / +0.235) put their origin at
  their own centre, so they are placed by putting the origin at the height you want the
  middle of the board. Curtains hang from `max y` = +0.055: the origin is 5.5 cm below the
  top of the rail, with 1.42 m of fabric below it.
- **A window sits around the opening.** The window module reaches 0.680 m above its origin
  and 0.742 m below it, which is where the sill goes.

### 2.5 Facing: two conventions in one set

The pipeline asks for −Z forward. A static prop does not walk, but it does have a working
face — the side the chalk is on, the side the handle is on, the side a notice is pinned to.
Where the front-detail nodes sit, measured along Z against the middle of each bounding box:

| Model | Front-detail node | Offset from the box centre |
|---|---|---|
| `classroom_blackboard` | `Blackboard_chalk_0…2`, `Blackboard_eraser_felt` | −0.105 m |
| `classroom_biology_chart` | `Chart_paper` (the backing board is at +0.022) | −0.011 m |
| `classroom_wall_clock` | `Clock_dial`, `Clock_hour_hand` | −0.035 m |
| `classroom_door_assembly` | `Door_handle_lever` | −0.057 m |
| `corridor_noticeboard` | `Notice_ink_mark_0…7` | **+0.068 m** |
| `classroom_window_module` | `Window_handle` | **+0.102 m** |
| `corridor_fire_extinguisher` | `Gauge_face`, `Safety_label` | **+0.092 m** |

The classroom's blackboard, chart, clock and door were authored facing −Z, as §1 asks; the
corridor noticeboard, the window handle and the extinguisher's gauge face the other way.
Both conventions are in the set, so **a wrapper must check the item it wraps** rather than
assume, and the round that writes the wrappers should pin each one with a test the way
`tests/imported_placement_test.gd` pins the characters and the bench. The corridor round
decided the three corridor items: the notices, the gauge and the trolley's front panel all
face the walkway, and `tests/corridor_props_test.gd` finds those nodes in the placed models
and fails if any of them ends up facing the wall or the parapet
([IMPLEMENTATION_NOTES_CORRIDOR_PROPS.md](IMPLEMENTATION_NOTES_CORRIDOR_PROPS.md)).

### 2.6 Materials: 55 names in three batches

The three sets carry no textures at all — every surface is a flat `StandardMaterial3D`
colour, which is why sixteen models fit in 2.4 MiB. The names record how the set was
authored, in three passes:

| Prefix | Names | Batch |
|---|---|---|
| `WIS_B02_*` | 16 | 5 models: the blackboard, student chair, student desk, lectern, window module |
| `WIS_B03_*` | 23 | 6 models: the biology chart, wall clock, door, ceiling fan, curtains, teacher chair |
| `WIS_*` | 16 | 5 models: everything in `corridor/` and `playground/` |

Twenty-six of the 55 names are shared by more than one model (`WIS_B02_wood_mid` and
`WIS_B02_metal_dark` appear in five each), so one `.tres` per name can dress a whole set — but the same colour exists under
different names in different batches (`WIS_B02_wood_mid`, `WIS_B03_wood_mid`, `WIS_wood`),
and none of the 55 names point at the painterly classroom materials in
`assets/materials/classroom/` (`wood_honey`, `board_slate`, `metal_ink`, …). Re-dressing
these models into the room's palette is a round of its own; the names above are the list
that round has to cover.

### 2.7 What is not there yet

Apart from the three corridor models (placed, see the last rows), these are model files.
They have no wrapper, no collision shape and no placement, so **nothing instantiates them
yet** — `scenes/locations/*` still builds those rooms out of greybox boxes. The replacement each one is meant to make, taking the existing greybox
wrappers as the target:

| Model | Today's stand-in |
|---|---|
| `classroom_blackboard` | `scenes/environment/props/blackboard.tscn` (dressed by `classroom_art/back_board.tscn`), instanced in `classroom.tscn`. (`corridor.tscn` used to declare it as an external resource that no node used; the corridor round removed that line.) |
| `classroom_student_desk`, `classroom_student_chair` | `scenes/environment/props/classroom_desk.tscn`, which is a desk with a chair modelled onto it |
| `classroom_teacher_chair` | the chair half of `scenes/environment/props/teacher_desk.tscn` |
| `classroom_teacher_lectern` | the desk half of `teacher_desk.tscn` (closest existing piece; a lectern is not a desk, so this is a design choice, not a swap) |
| `classroom_biology_chart` | nothing — the front wall is a painted plane (`classroom_art/front_wall_dressing.tscn`) |
| `classroom_door_assembly` | nothing — `classroom.tscn` has a `door`/`door_try`/`door_blocked` trigger and no door geometry |
| `classroom_window_module`, `classroom_window_curtains` | the `window_view_front`/`window_view_back` materials painted onto the classroom wall |
| `classroom_ceiling_fan`, `classroom_wall_clock` | nothing |
| `corridor_noticeboard` | **placed**: `props/corridor_noticeboard.tscn` → `corridor.tscn` `CorridorNoticeboard`, replacing the `NoticeboardFrame`/`NoticeboardCork`/`NoticePaperA`/`NoticePaperB` boxes |
| `corridor_cleaning_trolley`, `corridor_fire_extinguisher` | **placed**: `props/corridor_cleaning_trolley.tscn` → `CorridorTrolley` (replacing `TrolleyBody`/`TrolleyLid`/`TrolleyBucket`) and `props/corridor_fire_extinguisher.tscn` → `CorridorExtinguisher` (replacing `Extinguisher`/`ExtinguisherBracket`); numbers in [IMPLEMENTATION_NOTES_CORRIDOR_PROPS.md](IMPLEMENTATION_NOTES_CORRIDOR_PROPS.md) |
| `playground_tyre_stack`, `playground_sports_duffel` | nothing (`playground.tscn` already uses the imported bench and backpack) |

So the next round for any of these is the same three steps as pipeline §4: a hand-authored
wrapper under `scenes/environment/props/` (a `StaticBody3D` on layer 1, one box collider
sized to the box above, the model as the `Model` child at `position.y = -min.y`), a
placement in the location's table, and — if the prop is meant to be reachable — an entry in
the location's interaction data. The box sizes above are what the collider is sized from,
which is why they are recorded to the centimetre.

## 3. The football: a source file that is not in the repository

PR #85 also carried `dirty_football_4k.glb` — Poly Haven's CC0 "Dirty Football", the one
third-party file in the upload (`docs/ASSET_PROVENANCE.md` has the row, and records that the
same asset had been left out of the repository while only its `.blend` existed). It never
belonged in `assets/models/`: 67.3 MiB in one file — 35,210 vertices and **three 4096²
maps** (a 54.5 MiB PNG normal map, a 6.3 MiB PNG roughness map, a 5.3 MiB JPEG albedo) —
against a model budget of 1.5 MiB and a whole-release budget of 16 MiB. While it sat there,
`Export, verify, package` failed with *"151.9 MiB is not a plausible size for this build"*.

It sat under `art/` for one pull request and is now **removed from the tree entirely** (issue
#97): at 5.6× the repository's per-file ceiling it was the reason `tools/repo_size.py
--check` exists. `art/props/dirty_football/README.md` keeps the record — provenance, the
measurements above, where a copy can be downloaded, and what an export that could ship would
need. The blob is still in the history until someone rewrites it; that is a decision for the
owner, written up in `docs/adr/0007-large-binaries-and-repository-size.md`.

## 4. How these numbers stay true

| What | Where | Enforced by |
|---|---|---|
| Every model parses as glTF 2.0 binary | `tools/model_library.py --check` | CI: `Check the model library against the pipeline contract` |
| No node scale, no node matrix, no camera, no light | same | same |
| File size inside the model budget of pipeline §9.1 | same (the budget is imported from `tools/verify_build.py`, not copied) | same |
| Embedded images under 512 KiB (warn) / 2 MiB (fail) | same | same |
| A `.import` sidecar that matches the model's path | same | same |
| Model names unique across the library | same | same |
| The tables in this file | `tools/model_library.py --report` | re-run it; the numbers are printed from the files, and this file is a copy of its output |

`tests/model_library_test.py` tests the checker itself against files it writes — a scaled
node, a matrix node, a camera, a light, a size one byte over each limit, an oversized
embedded texture (in a `bufferView` and in a data URI), a missing sidecar, a sidecar left
behind by a move, and a duplicate name — so a checker that quietly stops checking fails CI
instead of passing it.
