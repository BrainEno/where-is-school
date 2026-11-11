# Asset Provenance Ledger

The repository now carries a small, enumerated number of externally sourced production
assets: two Poly Haven models and two owner-authored characters. Each is listed below with
its exact source and licence. Everything else was authored inside the repository from
Godot primitives, plain data files, or the project's own synthesis script, and no asset is
AI-generated. Material that was offered for import but could not be cleared, or could not
be converted on the machine doing the import, is recorded under "Not imported" instead of
being silently dropped.

| Asset/path | Type | Creator/source | Source URL | License / terms | Attribution required | Modifications | Commercial-use checked | Approved by |
|---|---|---|---|---|---|---|---|---|
| `scenes/environment/props/*.tscn`, `scenes/locations/**`, `scenes/ui/**` | Graybox 3D scenes and UI layouts | Authored for this repository from Godot primitive meshes and Controls | — | Project-owned placeholder, see COPYRIGHT.md | No | — | n/a (no third-party source) | Pending owner art review |
| `assets/materials/*.tres` | Placeholder StandardMaterial3D colours | Authored for this repository; colours follow docs/ART_BIBLE.md palette anchors | — | Project-owned placeholder | No | — | n/a | Pending owner art review |
| `assets/audio/room_tone_classroom.wav` | Ambient room tone (6 s, mono 22.05 kHz) | Synthesised by `tools/generate_placeholder_audio.py` (sine hum + white noise, in-repo algorithm) | — | Project-owned placeholder | No | — | n/a (no external samples) | Pending owner audio review |
| `assets/audio/room_tone_walkway.wav` | Ambient walkway tone (6 s) | Same script, different level/air parameters | — | Project-owned placeholder | No | — | n/a | Pending owner audio review |
| `assets/audio/bell_second.wav` | School bell one-shot (2 s) | Same script, additive sine bell with tremolo envelope | — | Project-owned placeholder | No | — | n/a | Pending owner audio review |
| `assets/audio/wake_thud.wav` | Low thud and breath for the wake beat (1.6 s) | Same script | — | Project-owned placeholder | No | — | n/a | Pending owner audio review |
| `art/fonts/NotoSansSC-Regular.ttf` (source) and `assets/fonts/NotoSansSC-Regular.ttf` (shipped subset) | Simplified-Chinese + Latin text font (variable-free static Regular). `art/` holds the untouched upstream file; the file under `assets/` is a glyph subset of it, produced by `tools/subset_font.py` | Google / Adobe, Noto Sans SC, obtained from the public google/fonts repository | https://github.com/google/fonts/tree/main/ofl/notosanssc | SIL Open Font License 1.1 (full text committed as `assets/fonts/OFL.txt`) | No (OFL allows bundling without attribution in-game; the license file ships with the font, and is copied into the release zip's `licences/`) | Modified: the shipped file is a subset, and OFL §5 permits modification. This copy declares no Reserved Font Name (the copyright line is `Google Inc.` alone), so the original name is kept, which also keeps the theme's path, the import sidecar and the licence aligned. The licence text travels with both copies. The whole family was not added, only Regular | Yes (OFL 1.1 permits commercial use and embedding) | Owner should confirm before a store build |
| `data/dialogue/<locale>/<chapter>.json` | Placeholder dialogue, in English and simplified Chinese | Written for this prototype from the approved direction; not derived from the private manuscript and not a paraphrase of it | — | Project-owned | No | Rewritten from the single-language prototype file into the chapter/locale layout | n/a | Pending owner writing review (see `data/dialogue_schema/README.md`, "Lines pending author review") |
| `data/inspections/<locale>/<chapter>.json` | Placeholder object descriptions, in English and simplified Chinese | Written for this prototype; same caveat as the dialogue files | — | Project-owned | No | Rewritten into the locale layout | n/a | Pending owner writing review |
| `data/locale/en.json`, `data/locale/zh-CN.json` | Interface strings (prompts, objective labels, badges, end card) | Written for this prototype | — | Project-owned | No | — | n/a | Pending owner writing review |
| `data/characters/*.tres` | Speaker metadata | Same as before | — | Project-owned | No | — | n/a | Pending owner writing review |
| `assets/models/sample/chair.glb` | Graybox glTF 2.0 sample: a stackable chair, 0.52 × 0.92 × 0.52 m, 72 triangles, one flat material | Generated deterministically by `tools/build_sample_models.py` (axis-aligned boxes, hand-written glTF writer, no exporter and no Blender) | — | Project-owned placeholder, see COPYRIGHT.md | No | None; the `.glb` is a build artefact of the script, and CI fails if the committed bytes drift from a fresh build | n/a (no third-party source) | Pending owner art review — expected to be replaced by an authored chair |
| `assets/models/sample/figure.glb` | Graybox glTF 2.0 sample: a person-sized figure, 0.60 × 1.72 × 0.26 m, 84 triangles, one flat material | Same script, same writer | — | Project-owned placeholder, see COPYRIGHT.md | No | None; regenerated by the same script | n/a (no third-party source) | Pending owner art review — it is not placed in any location, and no character is depicted |
| `scenes/environment/props/sample_chair.tscn`, `scenes/environment/characters/sample_figure.tscn` | Hand-authored wrapper scenes: collision, pivot, and (for the figure) an interaction anchor, around the two samples above | Authored for this repository from Godot primitive shapes | — | Project-owned placeholder | No | — | n/a | Pending owner art review |
| `assets/models/playground_bench/bench_playground.glb`, `assets/models/student_backpack/student_backpack.glb` | Authored glTF 2.0 props: a painted-wood playground bench (2.043 × 1.040 × 0.527 m, 7 material surfaces) and a canvas student backpack (0.528 × 0.498 × 0.386 m, 6 material surfaces) | Owner-authored in Blender 5.2.3 LTS and exported one object at a time with `use_selection`; the editable source is `art/props/where_is_school_bench_bag.blend`, kept out of the runtime asset tree | — | Project-owned, see COPYRIGHT.md | No | Split from one combined studio scene into two standalone exports; the backpack's bench-relative translation was cleared so it drops at its own base, its authored −7.5° tilt kept; no textures embedded | n/a (owner's own work, no third-party source) | Pending owner art review |
| `scenes/environment/props/playground_bench.tscn`, `scenes/environment/props/student_backpack.tscn`, `scenes/dev/prop_asset_preview.tscn` | Wrapper scenes: `StaticBody3D` on layer 1 with one box collider sized to the visual bounds, plus a preview scene composing both props. The bench is placed in the residential courtyard and in the schoolyard, and the bag on the schoolyard bench, from the generator's `s.props` table | Authored for this repository around the two GLBs above | — | Project-owned | No | — | n/a | Pending owner art review |
| `scenes/locations/street/**`, `scenes/locations/residential/**`, `scenes/environment/fauna/green_animal.tscn` | Graybox outdoor locations and the placeholder animal | Generated by `tools/build_outdoor_locations.py` from Godot primitives; the animal is capsules, boxes and spheres only | — | Project-owned placeholder, see COPYRIGHT.md | No | — | n/a | Pending owner art review (the animal's design is deliberately undecided) |
| `assets/models/school_desk/school_desk.glb` | glTF 2.0 runtime model: one mesh, one material, three embedded 512² PBR maps (albedo, normal, occlusion-roughness-metallic) | Ethan Place, published by Poly Haven | https://polyhaven.com/a/SchoolDesk_01 | CC0 1.0 (public domain) | No | Converted from Poly Haven's glTF download (`.gltf` + `.bin` + six 1K JPEG maps) into one `.glb` with the maps embedded; the three maps were resampled 1024 → 512 with Godot's Lanczos filter and re-encoded as JPEG at quality 0.92, so the imported scene fits the release build's per-entry budget. Geometry, UVs, materials and node transforms are untouched — 3,206 vertices / 4,162 triangles, the same geometry as the download | Yes — CC0 permits commercial use, modification and redistribution with no attribution | Pending owner art review |
| `assets/models/stationery_supplies/stationery_supplies.glb` | glTF 2.0 runtime model: nine meshes sharing one material, three embedded 512² PBR maps | Mateusz Sadek, published by Poly Haven | https://polyhaven.com/a/stationery_supplies | CC0 1.0 (public domain) | No | Same conversion and the same 1024 → 512 resample as the desk; geometry, UVs and materials untouched — 3,202 vertices / 4,412 triangles. The download is a *display line-up*: nine separate pens, pencils, an eraser and a cup, laid out around their own origin instead of standing on a floor | Yes — CC0 | Pending owner art review |
| `assets/models/protagonist/protagonist.glb` | glTF 2.0 skinned character: 78 mesh nodes, 22 materials, one 16-joint armature with rigid-part weights and no animation | Owner-authored: generated procedurally in Blender 5.2.3 LTS and exported by the owner. The generation report stays in the owner's local asset folder and is not committed | — | Project-owned, see COPYRIGHT.md | No | None to the model — the committed file is the owner's export as supplied. Measured and recorded: 1.727 m tall, 12,388 triangles, origin 1.7 cm above the sole, faces +Z | n/a (owner's own work, no third-party source) | Pending owner art review |
| `assets/models/q/q.glb` | glTF 2.0 character: 7 mesh nodes, 15 material surfaces, flat colours, no textures, no rig | Owner-supplied local file. No generation report accompanied it, so authorship is inferred from its folder, its `Q_Mat_*` material naming and the exporter version it shares with the protagonist (Khronos glTF Blender I/O v5.2.41). **The owner should confirm this before any public release** | — | Project-owned pending that confirmation, see COPYRIGHT.md | No | None — committed as supplied. Measured and recorded: 1.662 m tall, 35,432 triangles, feet on the origin, faces +Z, one authored non-uniform node scale (`Q_Collar`, 1 × 0.7 × 0.9) | Not yet established — owner to confirm authorship | Pending owner art review |
| `scenes/environment/props/school_desk.tscn`, `scenes/environment/props/stationery_supplies.tscn`, `scenes/environment/characters/protagonist.tscn`, `scenes/environment/characters/q.tscn`, `scenes/dev/imported_assets_preview.tscn` | Hand-authored wrapper scenes around the four models above (collision, origin correction, interaction anchor), plus a development preview that composes all four | Authored for this repository from Godot primitive shapes and the assets above | — | Project-owned | No | — | n/a | Pending owner art review |
| `assets/materials/classroom/textures/*.png` (+ `.import` sidecars) | Hand-painted classroom textures: the four walls, the floor, the front and back boards, the window view and its two glass panes, the banner, three small tileable surfaces (honey wood, oxblood lacquer, mustard canvas), the own-desk marks, the timetable and the clock face. 19 PNGs, 616 KiB in total, none over 111 KiB | Painted procedurally by `art/classroom/paint_classroom_textures.py` (Pillow 11.3.0 + NumPy 2.2.6). The script places every brush stroke, plane and ink line itself, from fixed seeds. It does not download, trace or sample anything, and no AI image model is involved | — | Project-owned, see COPYRIGHT.md | No | None. To regenerate, run the same script, which repaints byte-identical files | n/a (no third-party source) | Pending owner art review |
| `assets/materials/classroom/*.tres`, `scenes/environment/props/classroom_art/**`, and the classroom restyle of `blackboard.tscn`, `teacher_desk.tscn`, `set_square.tscn`, `schoolbag.tscn`, `classroom_desk.tscn` and `classroom.tscn` | The classroom's colour system: StandardMaterial3D materials (toon diffuse, an inverted-hull ink outline), the wall dressing scenes, and the overlay script that puts the room's wash and ink on the imported desk | Authored for this repository from Godot primitives. The palette and its rules are recorded in `art/classroom/README.md` | — | Project-owned | No | The imported desk and stationery models are untouched; the desk only gets a material overlay at runtime | n/a | Pending owner art review |
| `assets/models/classroom/*.glb` (11), `assets/models/corridor/*.glb` (3), `assets/models/playground/*.glb` (2), with their `.glb.import` sidecars | glTF 2.0 runtime props: 16 files, 2.4 MiB and 60,908 triangles together, flat-colour materials only (55 names, no textures, nothing to extract). Classroom: blackboard, biology chart, door assembly, ceiling fan, wall clock, window module, curtains, student desk and chair, teacher chair and lectern. Corridor: noticeboard, cleaning trolley, fire extinguisher. Playground: tyre stack, sports duffel | Supplied by the project owner in PR #85 (`local/upload-models`) as one unclassified folder, `assets/models/new models/`. No authoring notes, `.blend` source or generation report accompanied them, and they arrived in the same folder as one third-party CC0 prop (the row below). Authorship is inferred, not established: the material names are all prefixed for this project (`WIS_B02_*`, `WIS_B03_*`, `WIS_*`) rather than for a publisher or a product, the 16 are split across 55 hand-named flat-colour materials with no textures at all, and the file headers say `Khronos glTF Blender I/O v5.2.41` — the same exporter version as the owner-supplied protagonist and Q. **The owner should confirm this before any public release** | — | Project-owned pending that confirmation, see COPYRIGHT.md | No | None to the bytes: the files were sorted into `<kind>/` folders by the room each one belongs to and given the `.glb.import` sidecars the upload had none of. Measured and recorded in `docs/MODEL_LIBRARY.md`: sizes, triangle counts, bounding boxes, where each origin sits, which side each working face is on, and that none of them carries a camera, a light or a node scale | Not yet established — owner to confirm authorship | Pending owner art review |
| `dirty_football_4k.glb` (uploaded in PR #85; committed in PR #90; **removed in the issue #97 pull request**) | glTF 2.0 prop, 67.3 MiB: 35,210 vertices / 37,486 triangles, one material, three embedded 4096² maps (54.5 MiB PNG normal, 6.3 MiB PNG roughness, 5.3 MiB JPEG albedo). A 22 cm football | Poly Haven, "Dirty Football" | https://polyhaven.com/a/dirty_football | CC0 1.0 (public domain) | No | Committed once, at `art/props/dirty_football/dirty_football_4k.glb`, unmodified from the owner's export. Deleted from the tree because of its size — 5.6× the 12 MiB per-file ceiling of `tools/repo_size.py` — with the record, the measurements and the re-download route kept in `art/props/dirty_football/README.md`. The blob is still in the history; removing it there is an authorised rewrite, written up in `docs/adr/0007-large-binaries-and-repository-size.md` | Yes — CC0 permits commercial use, modification and redistribution with no attribution | Pending owner art review |

## Notes

- The audio files are regenerated deterministically by
  `python3 tools/generate_placeholder_audio.py`; the script is the provenance.
- The four interaction cue sounds are not files at all: `scripts/audio/cue_audio.gd`
  synthesises them at startup, in the same additive style, from constants in that script. The
  script is therefore the whole provenance, and there is nothing to import, license or lose.
- The one bundled third-party asset is the Noto Sans SC font above: Godot's
  built-in font has no CJK coverage, so simplified Chinese text cannot render
  without it. The license text travels with the file (`assets/fonts/OFL.txt`).
  The full font is a source file under `art/` (`.gdignore`d, never imported); the
  game loads a subset built from the project's own text by `tools/subset_font.py`,
  which is the provenance of that modification, and CI fails when the committed
  subset and the current text disagree.
- The two characters have been audited structurally, and the audits are committed:
  `art/character_rig_audit/` holds a rig and a component audit for each, with a
  `README.md` that reads them. The short version: the protagonist has a 16-bone
  rigid-part rig (7 591 of 7 633 vertices follow exactly one bone) and Q has no rig at
  all — no armature, no vertex groups, no modifiers. Neither has an Action, so no
  animation exists yet for either character. The audits were run on the owner's local
  Blender scenes rather than on the committed exports: each scene carries one leftover
  two-metre `Icosphere` with no material that the export leaves out, which is the whole
  difference between the audits' counts and the files above. Q's authorship is still
  recorded as "owner to confirm" for the same reason as before — the file arrived
  without a generation report.
- No generated imagery, marketplace packs, shader libraries, or other fonts are
  used. The outdoor blockouts are authored by an in-repo script
  (`tools/build_outdoor_locations.py`), which is the provenance.
- The two sample models are not third-party art and are not AI-generated: they are
  boxes written by `tools/build_sample_models.py`, which is their provenance. The
  import contract they prove is `docs/ASSET_PIPELINE.md`.
- Two development-only derivatives of the characters exist under
  `scenes/dev/animation_retarget_test/`: `q_rigged.glb` (the owner's Q, rigged to the
  protagonist's 16-bone hierarchy) and `protagonist_retarget_ready.glb` (the owner's
  protagonist, re-exported on a humanoid skeleton). Both are derived from owner-supplied
  files by the scripts that wrote the reports next to their `.blend` sources under
  `art/character_rigging/`, they are excluded from the export, and neither replaces the
  production models.
- `scenes/dev/animation_retarget_test/UAL1_Standard.glb` is the Universal Animation Library,
  supplied by the project owner and kept as an animation *source*: 43 clips on a 65-joint
  skeleton. It is third-party work, so its license belongs in this ledger and needs the owner
  to name it — Quaternius publishes these libraries as CC0, which is why it is usable at all,
  but that should be recorded rather than assumed. It does not ship (`scenes/dev/` is outside
  the export). `protagonist_ual.res` in the same directory is derived from it — those clips
  resampled onto the protagonist's bones by `tools/bake_animation_retarget.gd` — and also does
  not ship.
- The four clips the game's characters actually use are authored in code
  (`scripts/actors/character_animation.gd`), not taken from the library; see
  `docs/CHARACTER_ANIMATION.md`.
- Every placeholder above is expected to be replaced by owner-approved art,
  audio, and writing. Record replacement assets in this ledger as they land.
- The two Poly Haven models and the animation library above are the third-party content in
  the repository. They are
  CC0, which is why they could be committed without a purchase or an attribution
  obligation, but they are still recorded here with their source page and licence rather
  than treated as project-owned. Their licence needs no file to travel with them; if a
  future asset is *not* CC0, its licence text goes into `assets/` beside it, the way the
  Noto Sans SC OFL text does.
- The stationery is one import carrying nine separate objects. A scene that wants one
  pencil should instance the node it wants out of `stationery_supplies.tscn` rather than
  the whole line-up; the line-up is a convenient way to see the set, not a prop that sits
  on a desk as a group.
- The two characters carry no collision on purpose. They are visuals; the controller that
  drives them (the player's `CharacterBody3D`, an NPC actor) owns the capsule. See
  `docs/ASSET_PIPELINE.md` §10 for the three places these four assets deviate from the
  pipeline contract and how each is pinned by `tests/imported_assets_test.gd`.

## Not imported

| Local file | Why it is not in the repository |
|---|---|
| `dirty_football_4k.blend` (a Blender source with its 4K albedo, normal and roughness maps beside it). The owner's `.glb` export of this asset was committed in PR #90 as `art/props/dirty_football/dirty_football_4k.glb` and has since been removed for repository size (see the table above and `art/props/dirty_football/README.md`); the `.blend` below was never committed | The rights are clear — it is Poly Haven's "Dirty Football", CC0, https://polyhaven.com/a/dirty_football — but the local copy is a `.blend`, and exporting one needs a Blender binary that neither this machine nor CI has. Its maps are also 4K, including a 19.8 MB normal-map EXR, so even a successful export would need the 1K set or a resample before it could follow the desk and the stationery into `assets/`. It is left out rather than converted by a route nobody can reproduce. To bring it in: export a 512 or 1K `.glb` from Blender, or take Poly Haven's own 1K glTF download, then record it here. |

## Rules

- Record the exact asset or pack and the individual files included.
- Keep a copy/link to the license version that applied when obtained.
- Check commercial use, redistribution, modification, attribution, and AI-training restrictions where relevant.
- Marketplace purchase does not automatically permit redistribution of source files.
- An AI-generated asset is not automatically cleared for commercial use; record the tool, applicable terms, prompt/source references where appropriate, and the human editing/approval process.
- Do not commit credentials, private user data, or assets with unclear rights.
