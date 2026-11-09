# Implementation notes — imported production models (round two)

Companion notes for the four models that landed after the two placeholder samples and the
bench/backpack pair. They record where each asset came from, what it measures, how to use
it, and the parts that are still open. The contract is `docs/ASSET_PIPELINE.md`; the
provenance ledger is `docs/ASSET_PROVENANCE.md`. This file is the engineering record.

**Status: a reusable library, not a scene change.** Nothing in this round is placed in a
playable location. No existing graybox was replaced, no layout moved, no NPC, interaction
or story hook was touched. These assets are here so the next scene round can choose where
they go.

## 1. What was added

| Kind | Runtime model | Wrapper scene | Place in a scene? |
|---|---|---|---|
| Furniture | `assets/models/school_desk/school_desk.glb` | `scenes/environment/props/school_desk.tscn` | yes, anywhere a desk is wanted |
| Desk dressing | `assets/models/stationery_supplies/stationery_supplies.glb` | `scenes/environment/props/stationery_supplies.tscn` | on top of a desk or shelf |
| Character | `assets/models/protagonist/protagonist.glb` | `scenes/environment/characters/protagonist.tscn` | as the player's visual, or an NPC |
| Character | `assets/models/q/q.glb` | `scenes/environment/characters/q.tscn` | as Q's visual |

Plus `scenes/dev/imported_assets_preview.tscn`, which composes all four under a camera and
a light so they can be looked at without building a location. It is development-only and
is excluded from the export (`docs/ASSET_PIPELINE.md` §9.4).

## 2. Sources and modifications

| Asset | Source | Licence | What was done to it |
|---|---|---|---|
| School desk | Poly Haven, "School Desk 01", by Ethan Place — https://polyhaven.com/a/SchoolDesk_01 | CC0 1.0 | Repackaged the glTF download (`.gltf` + `.bin` + six 1K JPEG maps) into one `.glb` with the maps embedded, and resampled the three maps 1024 → 512. Geometry, UVs, materials and transforms untouched. |
| Stationery supplies | Poly Haven, "Stationery Supplies", by Mateusz Sadek — https://polyhaven.com/a/stationery_supplies | CC0 1.0 | Same repackaging and same resample. No geometry or material change. |
| Protagonist | Owner-authored, generated procedurally in Blender 5.2.3 LTS; the owner's generation report stays in the local asset folder | Project-owned | None — committed as supplied. |
| Q | Owner-supplied local file with no accompanying report | Project-owned pending confirmation | None — committed as supplied. |

No Blender was available on the machine that did this import, so the two Poly Haven
sources were converted by repacking their glTF rather than re-exporting from Blender, and
the one `.blend`-only asset (a dirty football) could not be converted at all — it is
recorded under "Not imported" in the ledger.

## 3. Asset facts

Measured in Godot 4.7.2 after import, not read off a file listing.

| | School desk | Stationery | Protagonist | Q |
|---|---|---|---|---|
| Size X × Y × Z (m) | 0.712 × 0.883 × 0.546 | 0.302 × 0.164 × 0.084 | 0.556 × 1.727 × 0.337 | 0.726 × 1.662 × 0.607 |
| Triangles | 4,162 | 4,412 | 12,388 | 35,432 |
| Mesh nodes | 1 | 9 | 78 | 7 |
| Material surfaces | 1 | 9 (one shared material) | 78 (22 materials) | 15 |
| Textures | 3 × 512² embedded | 3 × 512² embedded | none (flat colours) | none (flat colours) |
| Rig | — | — | 16 joints, rigid-part weights, **no animation** | — |
| GLB file | 254 KiB | 326 KiB | 514 KiB | 648 KiB |
| Origin | on the floor, centred on X | wrapper re-origins it to its base | 1.7 cm above the sole | on the feet |
| Facing | +Z | +Z | **+Z** | **+Z** |

## 4. How to use each one

- **School desk** — instance `scenes/environment/props/school_desk.tscn`. Its root is a
  `StaticBody3D` on physics layer 1 with one box collider covering the whole desk, so it
  collides, carves the navigation mesh, and blocks the interaction line-of-sight probe.
  Place it where it does not cut walkable space in two (the agent radius is 0.4 m), and
  put any look-anchor off its own collision. It is 0.88 m tall, the height a school desk
  is, so a 1.2 m NPC anchor and a 1.8 m player both read correctly against it.
- **Stationery supplies** — instance `scenes/environment/props/stationery_supplies.tscn`
  and drop it on the desk top at y ≈ 0.86. It carries **no collision on purpose**; the
  desk already collides. It is a *display line-up* of nine separate objects, so a scene
  that wants a single pencil should instance the individual node it wants out of the
  wrapper rather than the whole set.
- **Protagonist / Q** — instance the wrapper and parent it under whatever drives the
  character: the player's `VisualPivot`, or an `NpcActor`. The wrapper is a `Node3D` with
  the model and an `InteractionAnchor` at 1.2 m, and **no collision** — the driving
  controller's `CharacterBody3D` owns the capsule. Both characters face **+Z**, so a
  placement that wants them facing −Z yaws the instance 180°; there is no baked
  correction to fight. The protagonist is a rigid-weighted rig with no animation, so it
  reads as a static pose until one exists.
- **Preview** — open `scenes/dev/imported_assets_preview.tscn` and run it to see all four
  composed at their real relative scale.

## 5. Verified

Godot 4.7.2 Stable (standard build), Windows, NVIDIA RTX 5080:

- `godot --headless --path . --import` imports all four models and both new wrappers with
  no parse or resource errors.
- `godot --headless --path . --script res://tests/imported_assets_test.gd` passes: each
  model loads and instantiates, its measured bounding box matches the size above, its
  origin is where the table says, the scaled nodes are exactly the recorded set, the
  characters still face +Z, each wrapper instances its model, the prop wrapper collides to
  the size of the model, and the character and decoration wrappers carry no collision.
- `godot --headless --path . --script res://tests/model_import_test.gd` and
  `tests/prop_asset_test.gd` still pass — the new assets did not disturb the samples or
  the bench/backpack.
- The four models and the preview scene were rendered and looked at: nothing is inverted,
  floating or sunk, the scale against the sample chair and the 1.8 m player is right, and
  no surface rendered black, white or transparent.

## 6. Open, and what the next round still owns

- **Nothing here is in a location yet.** Replacing `classroom_desk.tscn`,
  `teacher_desk.tscn` or the `NpcActor` capsule with these assets is a scene decision with
  placement, navigation and line-of-sight consequences, and was deliberately not taken
  here.
- **The characters' +Z facing** is the one place these assets break the pipeline contract.
  Either the owner re-exports them facing −Z, or "authored characters are yawed at
  placement" becomes the written rule. Until then, yaw 180° where it matters.
- **Q's authorship is unconfirmed.** It is committed as the owner's own work on the
  strength of its folder and tooling, and the ledger says so. Confirm before any public
  release, or remove the file.
- **The dirty football could not be imported** — no Blender on the machine, and 4K maps.
  See the ledger's "Not imported" section for the two ways in.
- **No animation, no LOD, no lightmap UVs** on any of these; the protagonist's rig is not a
  deformation rig.
