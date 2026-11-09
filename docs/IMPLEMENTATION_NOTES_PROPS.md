# Implementation notes — playground bench and student backpack

Companion notes for the first authored 3D props. They record where the assets came
from, how they were split into two reusable scenes, and how to change them again.
The assets themselves are owner-authored; this file is the engineering record.

## 1. What was added

| Area | Files |
|---|---|
| Runtime models | `assets/models/playground_bench/bench_playground.glb`, `assets/models/student_backpack/student_backpack.glb` |
| Scene wrappers | `scenes/environment/props/playground_bench.tscn`, `scenes/environment/props/student_backpack.tscn` |
| Preview scene | `scenes/dev/prop_asset_preview.tscn` |
| Source archive | `art/props/where_is_school_bench_bag.blend` (the Blender file the two GLBs were exported from), with `art/props/.gdignore` keeping Godot from trying to import it |
| Test | `tests/prop_asset_test.gd` (headless) |
| Ledger | `docs/ASSET_PROVENANCE.md` |

The GLBs are runtime exports. The `.blend` is the editable source and is kept in
`art/`, out of the runtime `assets/` tree, the same way character source is meant to
live apart from its exported runtime files (`docs/TECHNICAL_ROADMAP.md` §4).

## 2. Source and split

The Blender file holds one combined studio scene with two mesh objects in a
`WIS_ASSETS` collection (`PROP_Bench_Playground`, `PROP_Backpack_Student`) and a
separate `WIS_STUDIO_PREVIEW_ONLY` collection holding the preview camera, lights and
floor. Nothing was remodelled: the two GLBs are the same geometry, materials and
transforms, exported one object at a time.

Exported with Blender 5.2.3 LTS in background mode, selecting one object per run and
using the exporter's `use_selection`:

```python
import bpy

def export(name, out_path):
    bpy.ops.object.select_all(action="DESELECT")
    obj = bpy.data.objects[name]
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )

export("PROP_Bench_Playground", "bench_playground.glb")

# The backpack sat on the bench at a world offset. Clear that offset so the
# standalone asset drops at its own base; keep the authored rotation and materials.
bag = bpy.data.objects["PROP_Backpack_Student"]
bag.location = (0.0, 0.0, 0.0)
export("PROP_Backpack_Student", "student_backpack.glb")
```

The `.blend` is opened read-only and never saved back, so the source is unchanged.

**Bench origin.** The bench object already sits at the world origin with its base at
`y≈0`, so it exports as-is.

**Backpack origin.** In the combined scene the backpack sat at a world offset of
`(0.37, 0.06, 0.515)` m with an authored `-7.5°` tilt about the Blender X axis. The
translation is removed in the standalone export; the tilt is kept. The result places
the backpack at its own base, and the preview scene re-creates the original bench
composition by putting the instance back at that offset.

## 3. Asset facts

Measured from the exported GLBs (Blender mesh statistics and the Godot import pass).

| | Playground bench | Student backpack |
|---|---|---|
| Blender vertices | 4,120 | 2,650 |
| Blender faces (polygons) | 3,954 | 2,598 |
| Triangles | 7,972 | 5,172 |
| Material surfaces | 7 | 6 |
| Size (Godot X × Y × Z, metres) | 2.043 × 1.040 × 0.527 | 0.528 × 0.498 × 0.386 |
| GLB file size | 201.3 KiB (206,144 B) | 129.5 KiB (132,592 B) |

The backpack's Godot bounds are larger than its upright Blender bounds
(`0.528 × 0.329 × 0.459` m) because the AABB is measured in world axes and the model
keeps its `-7.5°` tilt.

Materials, in export order:

- Bench: `WIS_Wood_Faded_Ochre`, `WIS_Wood_Darker_Board`, `WIS_Wood_Sun_Worn`,
  `WIS_Frame_Painted_Blue_Green`, `WIS_Wood_Painted_Light_Strokes`,
  `WIS_Wood_Painted_Shadow_Strokes`, `WIS_Dark_Fixing`.
- Backpack: `WIS_Bag_Faded_Rust_Canvas`, `WIS_Bag_Shadow_Panel`,
  `WIS_Bag_Old_Ochre_Flap`, `WIS_Bag_Dark_Straps`, `WIS_Bag_Stitching`,
  `WIS_Bag_Zipper_Metal`.

No textures are embedded. The GLB carries each material's Principled base colour and
roughness; the small noise/bump nodes in the Blender materials are procedural and are
not exported to glTF. The painted-stroke look survives because it is authored as
separate flat-colour materials, not as a texture.

## 4. Godot import

Both GLBs import with Godot's default glTF settings (`importer="scene"`, no root
script, materials embedded). Each becomes its own `PackedScene`; there is no shared
or duplicated import.

The `.import` sidecars are tracked, as they are for every other asset in the
repository (see the inventory at the end of `.gitignore`). They carry the per-asset
import options and the asset's `uid://`, and a clone that regenerates them silently
gets whatever the defaults are on that machine.

Two consequences follow, and both are checked in CI:

- **The import pass must be blocking.** `godot --headless --editor --path . --quit`
  returns after one frame, while the first filesystem scan is still running on its
  worker thread. Without a sidecar an unimported asset is still loadable — its own
  loader reads the source file — but *with* a sidecar the engine resolves the path
  through `.godot/imported/...` and never falls back, so an empty import cache turns
  every binary asset into "non-existent". CI therefore runs
  `godot --headless --path . --import`, which waits for the queue to drain.
- **Every tracked sidecar must have its imported file.** The `import audit` step in
  `godot-ci.yml` reads the `res://.godot/imported/...` paths out of each `.import` and
  fails when one is missing, so a silent import gap cannot reach a test as a
  confusing "the model is 0 m wide" failure.

The Blender source at `art/props/where_is_school_bench_bag.blend` is inside the
project folder, and Godot's `.blend` importer needs a Blender executable that neither
this machine-independent build nor CI has. `art/props/.gdignore` keeps the editor out
of that folder: the `.blend` stays in the repository as the source of record, and no
attempt is made to import it. (Its `.import` sidecar was removed for the same reason —
it named an imported scene nothing can produce.)

Do not hand-edit `.godot/imported/`. Change the `.blend`, re-export the GLB, and let
Godot re-import.

## 5. Using the props

Both props are ordinary `Node3D` scenes with a single `Model` child holding the
imported mesh. They are independent and carry no script.

- **In the editor:** drag `scenes/environment/props/playground_bench.tscn` or
  `student_backpack.tscn` into a location scene. Position and rotate the instance
  like any node; nothing else is required.
- **The bench** drops with its feet on `y = 0`.
- **The backpack** drops at its own base, upright relative to its authored tilt. Tune
  the instance's rotation if you want it standing perfectly flat.
- **Preview:** open `scenes/dev/prop_asset_preview.tscn` and run it to see the two
  props composed the way the Blender source shows them, with a simple environment,
  key light and camera.

## 6. Editing and re-importing

1. Open `art/props/where_is_school_bench_bag.blend`.
2. Edit `PROP_Bench_Playground` or `PROP_Backpack_Student`. Keep the collection names
   so the export selection stays unambiguous.
3. Re-export the object you changed with the snippet in §2 (or File ▸ Export ▸ glTF,
   selecting only that object, "Y Up" on, materials exported). Replace the matching
   GLB under `assets/models/…`.
4. In Godot, the `.glb` re-imports automatically. If the bounds change, update the
   expected sizes in `tests/prop_asset_test.gd`.

## 7. Verified

Verified with Godot 4.7.2 Stable (standard build), Windows, NVIDIA RTX 5080,
OpenGL 3.3 compatibility renderer:

- `godot --headless --editor --path . --quit` imports the new assets and scenes
  without parse or resource errors.
- `godot --headless --path . --script res://tests/prop_asset_test.gd` passes: each
  prop loads and instantiates on its own, keeps one mesh with the expected surface
  count, matches its expected metre size, and the backpack rests on the bench seat in
  the preview scene.
- `godot --headless --path . --script res://tests/smoke_test.gd` still passes.
- The preview scene was rendered from three angles (three-quarter, front, side) and
  compared against the four Blender preview images; the composition, scale and
  materials match.

## 8. Known limitations

- The backpack keeps the `-7.5°` tilt it was authored with; on a flat surface its
  lowest point sits about 14 mm below its origin. The preview scene reproduces this
  exactly. Bake the rotation into the mesh if a perfectly flat-base asset is wanted.
- Only one bench and one backpack exist. They are the first authored props, not a
  set; more props can follow the same wrapper convention.
- The bench has no collision body. Add a `StaticBody3D` at the scene that places it
  if the player must not walk through it.
- Windows hands-on play checks were performed here; the CI job for the new test is
  added to the workflow but has not yet run on GitHub.
