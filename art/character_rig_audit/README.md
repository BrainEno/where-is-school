# Character rig records

`runtime_model_manifest.json` records the **current exported production files**, not a
Blender scene. `python3 tools/model_library.py --check` verifies paths, skin joints,
mesh/material bindings and action channels for all four runtime characters.

## Current Q

The sole production Q is `assets/models/q/new-Q.glb`, the owner's separately approved
ChatGPT-generated original. Its immutable source is
`art/character_models/q/new-Q_source.glb`, excluded from Godot import/export by `.gdignore`.
It has 60 joints including all thirty weighted finger joints, nine skinned meshes,
thirteen head morphs and six supplied actions. See `docs/Q_MODEL_MIGRATION.md` for the
independent rest/bind/hierarchy/hand audit, action migration and actual-engine evidence.

The former Q-only rig/component audits, unrigged input, rig workfile/build report and
development duplicate were retired with the old production model. The historical records
remain readable in Git at migration base `580f6f34d3ff4e56f3d00d67cf115a98e63cfdbf`;
they are **not** data about the new rig and are **not** a runtime fallback. Baseline
screenshots use a read-only archive of that base, never a second Q in the current game.

## Historical protagonist audit (unchanged)

The remaining `protagonist_rig_audit.md` / `.json` and
`components/protagonist_component_audit.md` / `.json` were produced in Blender 5.2.3 LTS.
They describe `assets/models/protagonist/protagonist.glb`, the **former** protagonist,
now the seated classroom student; not `Protagonist_Character.glb`.

| Measurement | Former protagonist |
|---|---|
| Armatures | 1 (`RIG_Protagonist_Blockout`, 16 bones) |
| Weighted vertices | 7,591 of 7,633 in the Blender scene |
| Vertices with one influence | 7,591 (rigid-part bind) |
| Meshes with an Armature modifier | 78 |
| Actions | 0 |

The component audit contains an extra untextured `Icosphere` at the origin (42 vertices,
80 triangles) which does not reach the committed export. The Blender object count is
therefore 79 / 12,468 polygons while the GLB has 78 mesh nodes / 12,388 triangles.
The manifest measures the exported file; neither an object count nor a polygon count
should be substituted for its node/triangle counts.

These structural records are not licences, authorship declarations or visual signoff.
The production protagonist, its hair, materials and existing C art are unchanged by the
Q migration; outstanding rights questions remain in `docs/ASSET_LICENSE_AUDIT.md`.
