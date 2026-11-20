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
is instanced**: `classroom/`, `corridor/`, `playground/`, and the three character kinds
`protagonist/`, `q/` and `teacher-n/`. That is the same unit the rest of the project is assembled in —
`scenes/locations/<location>/` — so a kind folder is exactly the set of props one location
draws from:

| Kind | Models | Instanced by |
|---|---|---|
| `classroom/` | 11 | `scenes/locations/classroom/classroom.tscn` |
| `corridor/` | 3 | `scenes/locations/corridor/corridor.tscn` |
| `playground/` | 2 | `scenes/locations/playground/playground.tscn` |
| `protagonist/` | 2 | `Protagonist_Character.glb`, the player (`player.tscn`, via `scenes/environment/characters/protagonist.tscn`); `protagonist.glb`, the former protagonist, seated in the classroom (`classroom_student.tscn`) |
| `q/` | 1 | the NPC and companion controllers, via `scenes/environment/characters/q.tscn` |
| `teacher-n/` | 1 | the classroom's `Actors/N`, via `scenes/environment/characters/teacher_n.tscn`; built from the owner's export by `tools/prepare_teacher_n.py` |
| `classmates/` | 3 | Unplaced, inspected with `scenes/dev/classmates/classmates_review.tscn`; excluded from release exports |
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
| `classroom_door_assembly` | **placed twice, in the east wall** (issue #159): `props/classroom_art/classroom_door.tscn` (`ClassroomDoorDressing`, the model in classroom materials, wear marks hidden, a plaster backing behind it, no collision) → `classroom.tscn` `WallEast/FrontDoor` (grey leaf, the `classroom_door` exit) and `WallEast/RearDoor` (white leaf, the door that never opens) |
| `classroom_window_module` | the `window_view_front`/`window_view_back` materials painted onto the classroom wall |
| `classroom_window_curtains` | nothing since issue #159 — the back window's floor-to-ceiling blackout curtain is built procedurally by `WindowCurtain` (`props/classroom_art/window_curtain.tscn`), because this window-sized model cannot be stretched to 3.3 × 3.14 m without distorting its folds |
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
| The two runtime characters still have the node tree, meshes, materials, skin joints and embedded animations `art/character_rig_audit/runtime_model_manifest.json` records | same | same |
| The tables in this file | `tools/model_library.py --report` | re-run it; the numbers are printed from the files, and this file is a copy of its output |

`tests/model_library_test.py` tests the checker itself against files it writes — a scaled
node, a matrix node, a camera, a light, a size one byte over each limit, an oversized
embedded texture (in a `bufferView` and in a data URI), a missing sidecar, a sidecar left
behind by a move, and a duplicate name — so a checker that quietly stops checking fails CI
instead of passing it.

## 5. The runtime character manifest

The four rigged models the game instantiates at run time —
`assets/models/protagonist/Protagonist_Character.glb` (the player since PR #118),
`assets/models/protagonist/protagonist.glb` (the former protagonist, now the seated
classroom student), `assets/models/q/new-Q.glb` and `assets/models/teacher-n/teacher-n.glb`
(substitute teacher N) — are also checked against a written-down structure,
`art/character_rig_audit/runtime_model_manifest.json`. `tools/model_library.py --check`
reads it on every run and fails when a registered model does not match it; the other 22
models in the library keep the checks in §4 and are not registered.

The rest of this library is judged by rules (no scale, no camera, inside the budget). A rig
cannot be: a character whose hand bone was renamed, whose mesh was split, whose joint list
was reordered or whose node was added still parses, still fits, still has no light — and
binds to a skeleton nobody declared. The manifest is what makes that a red check instead of
a bug found while playing.

### 5.1 What the runtime files actually contain

Measured from the committed `.glb` files, not from the Blender sources and not from
`art/character_rig_audit/*_rig_audit.json`:

| | `Protagonist_Character.glb` | `protagonist.glb` | `new-Q.glb` | `teacher-n.glb` |
|---|---|---|---|---|
| nodes | 70 | 82 | 70 | 35 |
| scene root → armature | `Protagonist_Armature` (the root) | `CHR_Protagonist_Root` → `RIG_Protagonist_Blockout` | `Q_Armature` (the root) | `CHR_Substitute_Teacher_Root` → its armature |
| skin joints (bones) | 60 | 16 | 60 | 16 |
| mesh nodes, all bound to skin 0 | 9 | 64 | 9 | 18 |
| meshes / primitives | 9 / 15 | 64 / 64 | 9 / 16 | 18 / 28 |
| materials | 12 | 22 | 12 | 17 |
| embedded animations | 5 (721 channels; not played by the game) | 0 | 6 (70 channels; native idle/talk and named actions) | 4 (8 channels; played together as N's idle) |
| triangles | 15,782 | 46,384 | 17,918 | 56,950 |
| file | 852.3 KiB | 1083.8 KiB | 980.7 KiB | 1314.7 KiB |

The former protagonist and N retain the 16-joint naming convention. Q no longer
shares that hierarchy: its approved replacement has `Root → Pelvis → Spine → Spine_01
→ Spine_02 → Chest`, clavicles, toes and thirty independently weighted finger bones.
The semantic resolver checks rest-position sides rather than assuming identical rigs.

The former protagonist alone has no embedded animation. Q carries six supplied actions;
its native breathing/lean and hand gesture are used by the production idle/talk, four
named rotation previews remain available, and the facial diagnostic remains in the source
player. N's four loops remain its idle, unchanged. The manifest locks each action's name,
channel count and target paths; adding/removing a channel is a reviewed structural change.
Q, N and the seated student are reproducibly prepared from immutable `.gdignore`d sources
under `art/character_models/`; their respective preparation tools have `--check` modes.
Geometry revision 2 (`prepare_teacher_n.py`, `prepare_classroom_student.py`, shared
`character_geometry.py`) refines N/student silhouettes, eyes and garment seams and uses
fewer triangles than the first refinement without changing the registered structure.
`tests/character_geometry_test.py` verifies connected closed five-digit hands, normal/skin
validity, exact source/output, joint/rest/inverse-bind preservation, and N's live actions.
The N wrist and student elbow weights are authored, not represented as original weights.
Structural checks and smaller files do not establish visual quality; source rights and engine/owner
acceptance remain in [ASSET_PROVENANCE.md](ASSET_PROVENANCE.md) and
[CHARACTER_INTEGRATION.md](CHARACTER_INTEGRATION.md) §§9–10.

The manifest verifies that every primitive remains skinned, not that skin deformation is
artistically accepted. For Q, `tests/q_model_prepare_test.py` additionally compares all
mesh/normal/weight/index/morph accessors and inverse binds against the approved source;
engine motion and owner visual checks are separate evidence levels.

### 5.2 What it locks, and what it deliberately does not

Locked, because each is a structural promise the runtime depends on:

- the node tree, by **path** — `CHR_Protagonist_Root/RIG_Protagonist_Blockout/Neck`. Paths,
  not names: both rigs contain two nodes called `Neck`, one a bone and one a mesh node.
  A new node, a lost node, a rename or a re-parent changes a path and fails;
- each node's `mesh` and `skin` binding;
- each mesh's primitive count, and each primitive's material and whether it carries bone
  weights;
- the material names;
- each skin's joint list **in order** — `JOINTS_0` stores indices into that list, so
  reordering it rebinds every vertex to a different bone;
- the embedded animations: names, channel counts and what each channel targets.

Not locked, on purpose: node transforms, triangle and vertex counts, UVs, texture details,
import metadata, file size. Those move with every legitimate art pass, and a manifest that
failed on them would be a file lock nobody could work behind. The size budget in §4 still
applies to these files, and node scale is still forbidden by pipeline §1.

### 5.3 Where the runtime files differ from the older records

Three stages of the same characters exist in this repository and they do not agree, which is
why the manifest was built from the `.glb` files rather than from the audits:

- **`protagonist_rig_audit.json`** describes a Blender import of the *same path*: 1 armature,
  16 bones, **79 mesh objects**, 12,468 polygons, 0 actions. The original runtime export had
  **78 mesh nodes**, 12,388 triangles (one Blender object did not reach the export; polygons
  are not triangles). That exact export is now `student_source.glb`. Geometry revision 1
  replaces fourteen obsolete hand/face components with integrated surfaces, so the current
  runtime manifest correctly records **64 meshes**. The second pass has 46,384 triangles.
  The old rig audit is historical source evidence, not the current geometry contract.
- **Former Q records** described an unrigged input and a separate 16-joint derivative,
  not today's approved replacement. Those Q-only sources, workfiles, audit reports and
  development duplicate have been removed with the retired production model. They can be
  read at task base `580f6f34d3ff4e56f3d00d67cf115a98e63cfdbf` for historical comparison;
  they are not a runtime fallback. See [Q_MODEL_MIGRATION.md](Q_MODEL_MIGRATION.md).

### 5.4 Changing a character on purpose

The manifest is not a lock; it is a reviewed snapshot. To make a structural change:

```sh
# ... change the model, re-export it, then:
python3 tools/model_library.py --update-manifest   # accepts the new structure, prints each
                                                   # difference it accepted, keeps the entry's
                                                   # human-written `wrapper` and `note`
git diff art/character_rig_audit/runtime_model_manifest.json
```

The diff is the review: it shows, node by node, what the character gained or lost. A change
that was not meant to be structural shows up there before it reaches a release, which is the
whole point of writing the structure down. If the manifest itself is malformed, the update
refuses to run and leaves the file alone (§5.5) — a broken manifest is fixed by hand, never
by overwriting it with whatever a run happened to generate.

`--update-manifest` only rewrites entries that exist. Adding a *new* runtime character is
two reviewed edits: add its path to `REQUIRED_RUNTIME_MODELS` in `tools/model_library.py`,
and add its entry, whose structural fields are exactly what `describe_model()` reads from
the committed `.glb` (with a human-written `wrapper` and `note`). That is how
`Protagonist_Character.glb` was registered in PR #118 and `teacher-n.glb` after it; the
`--check` that follows compares the file against that entry like any other, and
`--update-manifest` run straight after reports no difference.

### 5.5 What the manifest itself has to be

A snapshot check is only as strong as the document it reads, so the manifest is validated as
a document before any `.glb` is opened (`validate_manifest` in `tools/model_library.py`,
called by both `--check` and `--update-manifest`):

- **Every runtime character, once each, and nothing else.** The manifest registers
  `assets/models/protagonist/protagonist.glb`, `assets/models/q/new-Q.glb`,
  `assets/models/protagonist/Protagonist_Character.glb` and
  `assets/models/teacher-n/teacher-n.glb`. A missing entry, a duplicated
  entry, an entry for any other model and an empty `models` are all failures. "At least one
  model" was the old rule and it was not enough: deleting Q's entry used to leave a file that
  was valid, plausible and had quietly stopped checking Q.
- **Every structural field, with the right shape.** `counts`, `scene_roots`, `nodes`,
  `meshes`, `materials`, `skins` and `animations` must all be present and of the right type,
  and every element inside them is checked too — a node without a `path`, a primitive whose
  `skinned` is not a boolean, a `joints` list that is a string, a counter that is not a whole
  number. A field that is missing or `null` is a *problem*, never a section the comparison
  skips.
- **The counters must agree with the lists they count** — `counts.nodes` against `len(nodes)`
  and so on. A truncated entry with a stale counter would otherwise report one difference
  when what happened is that the entry lost data.
- **Names are identity, so names must be unique.** `compare_model` pairs resources by name
  (and nodes by path); two meshes called `Q_Hair_mesh.001` would fold into one entry and make
  one of them invisible. Duplicates are therefore refused on *both* sides — in the manifest
  and in the `.glb` — and the structure is not compared while a name is ambiguous. The same
  rule covers skins and embedded animations. Node *paths* are unique by construction (`Neck`
  legitimately appears twice in each rig, so the second occurrence is recorded as `…/Neck#2`).

Every one of those is reported as a `MODEL_LIBRARY_PROBLEM` line naming the manifest, the
entry (and its model path) and the field, and `--check` exits non-zero. Nothing in this path
raises: a malformed manifest is a diagnosis, not a traceback.

`--update-manifest` runs the same validation **before** it reads a single model, and refuses
a malformed manifest instead of "repairing" it: the file is left byte-for-byte as it was, the
run exits non-zero, and the reason is printed. When the manifest is well-formed it also
validates the text it is about to write, and the write itself is atomic (a temporary file
replaced into place), so an interrupted or buggy update cannot leave a half-written manifest
behind.

`tests/model_library_test.py` tests the checker against a synthetic rig it writes itself —
an added node, a removed node, a re-parented node, a split primitive, a reassigned material,
a primitive that lost its weights, a reordered joint list, a lost joint, a lost skin, an
animation that appeared, a lost animation, a changed channel target — and against a manifest
it writes itself: a missing character, a duplicated one, a stray third entry, an empty
`models`, each structural field removed or set to the wrong type, a malformed element inside
each list, duplicate mesh/skin/animation names on both sides, a resource replaced by a copy
of another, and an update run against a malformed file that must leave it untouched. 140
checks, so the snapshot cannot rot into a check that always passes.

## 6. Unplaced classmates

### `classmates/` — 3 models, 4352 KiB

| model | KiB | tris | materials | textures | W × H × D (m) | min y (m) | max y (m) |
|---|---|---|---|---|---|---|---|
| `court_classmate` | 1483.5 | 47658 | 11 | — | 0.69 × 1.8 × 0.32 | +0.000 | +1.800 |
| `gentle_classmate` | 1513.9 | 48842 | 12 | — | 0.61 × 1.62 × 0.3 | +0.000 | +1.620 |
| `thin_classmate` | 1354.7 | 42960 | 11 | — | 0.57 × 1.6 × 0.27 | +0.000 | +1.600 |

These are separately sculpted, skinned assets with three native clips apiece.
The heights are bind-pose geometry bounds, from the actual soles to the top of
the hair. See the [classmates source and usage](../art/character_models/classmates/README.md).
The runtime manifest remains unchanged: no location instantiates these models.
The three files exceed the advisory line but meet the per-model hard limit.

The revised off-stage B review model is 1509.2 KiB, 49,466 triangles, 13
surfaces / 12 materials and 1.640 m tall. It has the same bind transform and
no embedded actions; the separate B-only review animation library is unchanged.
