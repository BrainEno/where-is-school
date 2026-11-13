# Asset Provenance Ledger

The repository now carries a small, enumerated number of externally sourced production
assets: two Poly Haven models, two owner-authored characters, two Noto fonts and three
dialogue portraits supplied by the owner. Each is listed below with its exact source and
licence. One further third-party asset — an animation library — is
tracked as a development-only input under `scenes/dev/` and is covered in the notes below;
it is not a production asset and cannot reach a build. Everything else was authored inside
the repository from Godot primitives, plain data files, or the project's own synthesis
script. The three dialogue portraits were described by the owner, when supplying them, as
newly generated images; the tool and its terms are not recorded yet (row below), and they
are the only assets in the repository described that way. Material that was offered for import but could not be
cleared, or could not be converted on the machine doing the import, is recorded under
"Not imported" instead of being silently dropped.

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
| `assets/models/protagonist/protagonist.glb` | glTF 2.0 skinned character: 78 mesh nodes, 22 materials, one 16-joint armature with rigid-part weights and no animation. The player character until PR #118; since then the seated classroom student (`scenes/environment/characters/classroom_student.tscn`, placed at desk A1 in `classroom.tscn`). The file is unchanged and still the only copy | Owner-authored: generated procedurally in Blender 5.2.3 LTS and exported by the owner. The generation report stays in the owner's local asset folder and is not committed | — | Project-owned, see COPYRIGHT.md | No | None to the model — the committed file is the owner's export as supplied. Measured and recorded: 1.727 m tall, 12,388 triangles, origin 1.7 cm above the sole, faces +Z | n/a (owner's own work, no third-party source) | Pending owner art review |
| `assets/models/protagonist/Protagonist_Character.glb` | glTF 2.0 skinned character, the player character since PR #118: 70 nodes, 9 skinned mesh nodes drawing 15 primitives from 12 flat-colour materials, no textures and no UVs, one 60-joint skin (`Protagonist_Armature`: root, four IK targets, pelvis, spine ×3, chest, clavicles, arms, 15 finger joints per hand, neck, head, eyes, legs, toes), 9 blend shapes on the head, five embedded animations (`Idle_Breathing`, `Protagonist_Idle_Breathing`, `Slight_Posture_Shift`, `Subtle_Head_Movement`, `Protagonist_Face_Test`) that the game does not play | Supplied by the owner (BrainEno) in PR #118 (`local/upload-new-protagonist`, commit `c7b6fa4`). The file header reads `Khronos glTF Blender I/O v5.2.41`, the same exporter as the owner's other Blender models. The owner has not yet stated in writing who made it and with what tools; until they do, the authorship is recorded as "supplied by the owner", not as confirmed | — | Project-owned, see COPYRIGHT.md (pending the owner's confirmation above) | No | Restored 12 missing glTF PBR `baseColorFactor` values using the project's muted protagonist palette; geometry, rigging, skinning, blend shapes and animations are unchanged. Added: the `.glb.import` sidecar, generated by Godot 4.7.2 in CI (it was missing from the upload). Measured and recorded: 1.767 m tall, 1.046 m wide (A-pose arms), 15,782 triangles, sole on the origin, faces +Z. Structure node by node: `art/character_rig_audit/runtime_model_manifest.json` | n/a if the owner confirms it as their own work; otherwise to be determined | Pending owner art review and authorship confirmation |
| `assets/models/q/q.glb` | glTF 2.0 skinned character: 7 mesh nodes drawing 15 primitives from 14 flat-colour materials, no textures, one 16-joint skeleton (`Q_Humanoid_Skeleton`) with weights on every primitive, no animation | Owner-authored, confirmed by the owner on 2026-11-12: made in Blender, generated by a Python script the owner directed, so the work is the owner's own. As with the protagonist, the script and the generation report stay in the owner's local asset folder and are not committed. The rig this file ships was built by `art/character_rigging/q/q_rig_build_report.json` (Blender 5.2.3 LTS) from the owner's unrigged source | — | Project-owned, see COPYRIGHT.md | No | None — the committed file is the owner's export as supplied. Measured and recorded: 1.662 m tall, 35,432 triangles, feet on the origin, faces +Z, one authored non-uniform node scale (`Q_Collar`, 1 × 0.7 × 0.9). Structure node by node: `docs/MODEL_LIBRARY.md` §5 and `art/character_rig_audit/runtime_model_manifest.json` | n/a (owner's own work, no third-party source) | Pending owner art review |
| `scenes/environment/props/school_desk.tscn`, `scenes/environment/props/stationery_supplies.tscn`, `scenes/environment/characters/protagonist.tscn`, `scenes/environment/characters/classroom_student.tscn`, `scenes/environment/characters/q.tscn`, `scenes/dev/imported_assets_preview.tscn` | Hand-authored wrapper scenes around the five models above (collision, origin correction, interaction anchor; the classroom student is a seated visual with none of them), plus a development preview that composes the desk, the stationery, the protagonist (via `protagonist.tscn`, so now `Protagonist_Character.glb`) and Q | Authored for this repository from Godot primitive shapes and the assets above | — | Project-owned | No | — | n/a | Pending owner art review |
| `assets/materials/classroom/textures/*.png` (+ `.import` sidecars) | Hand-painted classroom textures: the four walls, the floor, the front and back boards, the window view and its two glass panes, three small tileable surfaces (honey wood, oxblood lacquer, mustard canvas), the own-desk marks, the timetable and the clock face. 18 PNGs, approximately 566 KiB in total, none over 134 KiB | Painted procedurally by `art/classroom/paint_classroom_textures.py` (Pillow 11.3.0 + NumPy 2.2.6). The script places every brush stroke, plane and ink line itself, from fixed seeds. It does not download, trace or sample anything, and no AI image model is involved | — | Project-owned, see COPYRIGHT.md | No | Classroom-only palette revision: cool violet/blue shadow fields, warm ochre, layered board pigment; the red pseudo-writing banner PNG and its generator entry are removed. Regenerate with the same script; `--check` verifies byte-identical files | n/a (no third-party source) | Pending owner art review |
| `assets/materials/classroom/*.tres`, `scenes/environment/props/classroom_art/**`, and the classroom restyle of `blackboard.tscn`, `teacher_desk.tscn`, `set_square.tscn`, `schoolbag.tscn`, `classroom_desk.tscn` and `classroom.tscn` | The classroom's colour system: matte StandardMaterial3D surfaces, a restrained 6 mm prop contour, and the classroom-owned `student_wood.tres` pigment material referencing the existing environment shader read-only. `scenes/locations/classroom/classroom_presentation.gd` replaces the student desk's photographic surface after wrapper setup | Authored for this repository from Godot primitives. The palette and its rules are recorded in `art/classroom/README.md` | — | Project-owned | No | Imported models and shared desk wrappers are untouched. In this classroom only, the desk uses an opaque pigment surface instead of its source PBR material and legacy alpha overlay; source albedo, normal and ORM maps are not sampled. No downloaded or AI-generated texture is added | n/a | Pending owner art review |
| `assets/models/classroom/*.glb` (11), `assets/models/corridor/*.glb` (3), `assets/models/playground/*.glb` (2), with their `.glb.import` sidecars | glTF 2.0 runtime props: 16 files, 2.4 MiB and 60,908 triangles together, flat-colour materials only (55 names, no textures, nothing to extract). Classroom: blackboard, biology chart, door assembly, ceiling fan, wall clock, window module, curtains, student desk and chair, teacher chair and lectern. Corridor: noticeboard, cleaning trolley, fire extinguisher. Playground: tyre stack, sports duffel | Owner-authored in Blender. The owner confirmed on 2026-11-11 that they made these models themselves in Blender; the file headers agree (`Khronos glTF Blender I/O v5.2.41`), as do the project-prefixed material names (`WIS_B02_*`, `WIS_B03_*`, `WIS_*`). Supplied in PR #85 (`local/upload-models`) as one unclassified folder, `assets/models/new models/`, in the same folder as one third-party CC0 prop (the row below), which is not part of this confirmation. The `.blend` sources are not committed | — | Project-owned, see COPYRIGHT.md | No | None to the bytes: the files were sorted into `<kind>/` folders by the room each one belongs to and given the `.glb.import` sidecars the upload had none of. Measured and recorded in `docs/MODEL_LIBRARY.md`: sizes, triangle counts, bounding boxes, where each origin sits, which side each working face is on, and that none of them carries a camera, a light or a node scale | n/a (owner's own work, no third-party source) | Pending owner art review |
| `art/fonts/NotoSerifSC-Regular.otf` (source) and `assets/fonts/NotoSerifSC-Regular.otf` (shipped subset) | Simplified-Chinese + Latin serif text font (static Regular, CFF outlines), used by the dialogue panel for the sentence, the speaker name, the title and the options, and by the title screen, the pause menu and their confirmation prompts for the game's name, headings, entries and questions (`scripts/ui/menu_style.gd`); no new font file was added for the menus. `art/` holds the untouched upstream file (11,625,800 bytes, sha256 `e8f396de…c83a1cd3`); the file under `assets/` is a glyph subset of it (421 KiB), produced by `tools/subset_font.py` from the text that can reach the dialogue panel | Adobe, for Google: Noto Serif SC 2.003 (name table: "© 2017-2024 Adobe"), obtained from the public notofonts/noto-cjk repository, `Serif/SubsetOTF/SC/` at commit `9b0f1436e455d902de067a2501422e5dc71ad16b` | https://github.com/notofonts/noto-cjk/tree/main/Serif/SubsetOTF/SC | SIL Open Font License 1.1 (full text committed as `assets/fonts/NotoSerifSC-OFL.txt`, from `Serif/LICENSE` at the same commit) | No (as for Noto Sans SC; the licence ships with the font and is copied into the release zip's `licences/NotoSerifSC-OFL.txt`) | Modified: the shipped file is a subset, which OFL §5 permits. The upstream licence declares no Reserved Font Name, so the original name is kept. Only Regular was added. The variable google/fonts build (25 MB) was not used because it is over the repository's 12 MiB per-file ceiling | Yes (OFL 1.1 permits commercial use and embedding) | Owner should confirm before a store build |
| `art/portraits/protagonist.png`, `art/portraits/q.webp`, `art/portraits/n.webp` (sources) and `assets/ui/portraits/{protagonist,q,n}.webp` (+ `.import` sidecars, shipped) | 2D dialogue portraits, painted look (pastel and charcoal on cardboard/paper): the protagonist (bust, gakuran), Q (bust, pointing, white jacket) and N (standing figure, grey cardigan, light ground). Sources 1145×1374, 1254×1254 and 1280×1936 px, opaque RGB, sha256 `2b849499…5aad9c7b2b`, `993a6055…ca165d386`, `2417a5b7…5612679feae3d` (full hashes in `tools/prepare_portraits.py`). Shipped: cropped and scaled to 911×1100, 945×1100 and 726×1100 px, WebP quality 92 (409, 447 and 223 KiB), imported as lossy WebP 0.8 with mipmaps | Supplied by the owner (BrainEno) on 2026-11-12 as `protagonist.png`, `q-picture.webp` and `teacher-n.webp`, and described by the owner as newly generated portraits. **Not recorded yet:** which tool or service generated them, who prompted or edited them, and that tool's terms | — | **Unconfirmed.** Treated as project-owned only once the owner confirms that the generating tool's terms grant the project ownership or an unrestricted commercial licence for the outputs | No (pending the owner's answer above) | Cropped and downscaled by `tools/prepare_portraits.py`, which records each crop in source pixels. The protagonist loses only the ragged cardboard edge; Q loses the empty right edge (the pointing hand and the face are kept); N is cut just above the knees so that she reads at a useful size inside the panel's width cap. No retouching, no colour change, and no background removal. The sources are kept untouched under `art/portraits/` (`.gdignore`d) | **No, not yet checked**: owner to confirm the tool and its commercial-use terms before any public or store build | Owner supplied and asked for them in the dialogue box (2026-11-12); art review pending |
| `dirty_football_4k.glb` (uploaded in PR #85; committed in PR #90; **removed in the issue #97 pull request**) | glTF 2.0 prop, 67.3 MiB: 35,210 vertices / 37,486 triangles, one material, three embedded 4096² maps (54.5 MiB PNG normal, 6.3 MiB PNG roughness, 5.3 MiB JPEG albedo). A 22 cm football | Poly Haven, "Dirty Football" | https://polyhaven.com/a/dirty_football | CC0 1.0 (public domain) | No | Committed once, at `art/props/dirty_football/dirty_football_4k.glb`, unmodified from the owner's export. Deleted from the tree because of its size — 5.6× the 12 MiB per-file ceiling of `tools/repo_size.py` — with the record, the measurements and the re-download route kept in `art/props/dirty_football/README.md`. The blob is still in the history; removing it there is an authorised rewrite, written up in `docs/adr/0007-large-binaries-and-repository-size.md` | Yes — CC0 permits commercial use, modification and redistribution with no attribution | Pending owner art review |

## Notes

- The audio files are regenerated deterministically by
  `python3 tools/generate_placeholder_audio.py`; the script is the provenance.
- The four interaction cue sounds are not files at all: `scripts/audio/cue_audio.gd`
  synthesises them at startup, in the same additive style, from constants in that script. The
  script is therefore the whole provenance, and there is nothing to import, license or lose.
- The bundled third-party assets are the two Noto fonts above. Noto Sans SC is needed
  because Godot's built-in font has no CJK coverage, so simplified Chinese text cannot
  render without it. Noto Serif SC is the dialogue panel's reading face (owner's direction,
  2026-11-12), split and checked the same way by the same script; its licence is
  `assets/fonts/NotoSerifSC-OFL.txt`. The license text travels with the file (`assets/fonts/OFL.txt`).
  The full font is a source file under `art/` (`.gdignore`d, never imported); the
  game loads a subset built from the project's own text by `tools/subset_font.py`,
  which is the provenance of that modification, and CI fails when the committed
  subset and the current text disagree.
- The two characters have been audited structurally, and the audits are committed:
  `art/character_rig_audit/` holds a rig and a component audit for each, with a
  `README.md` that reads them. Read each audit for the stage it describes. The Q audit
  was run on `art/character_rigging/q/q_unrigged_source.glb`, the unrigged source, so its
  "no rig, no armature, no vertex groups" is a fact about that file and not about the
  character: the shipped `assets/models/q/q.glb` carries one 16-joint skeleton with
  weights on every primitive, the same joint names and hierarchy as the protagonist's
  (`docs/MODEL_LIBRARY.md` §5). The protagonist audit's 16-bone rigid-part rig holds for
  the shipped file (7,591 of 7,633 vertices follow exactly one bone). Neither shipped
  model contains an `Animation` — the clips the characters play are composed at run time
  by `scripts/actors/character_animation.gd`. The audits were run on the owner's local
  Blender scenes rather than on the committed exports: each scene carries one leftover
  two-metre `Icosphere` with no material that the export leaves out, which is the whole
  difference between the audits' counts and the files above. Q's authorship was settled
  by the owner on 2026-11-12 — made in Blender with a Python script the owner directed, so
  the work is the project's own (row above) — which replaces the earlier "owner to
  confirm".
- No marketplace packs or shader libraries are used, and no fonts other than the two Noto
  faces above. The only generated imagery is the three dialogue portraits (row above),
  whose tool and terms the owner has not recorded yet. The outdoor blockouts are authored by an in-repo script
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
- `scenes/dev/animation_retarget_test/UAL1_Standard.glb` is the **Universal Animation
  Library** (Standard, free edition) by **Quaternius**, downloaded by the project owner and
  kept as an animation *source*: one mesh, two materials, 43 clips on a 65-joint
  `Armature`, 7.6 MiB, no licence metadata inside the file. It is third-party work, so its
  licence is recorded here rather than assumed. Researched 2026-11-12, and the two
  documents disagree:
  - **As published for this pack**, every channel that distributes it states **CC0 1.0
    Universal**: the pack page (`quaternius.com/packs/universalanimationlibrary.html`,
    "License: CC0"), itch.io ("Asset license · Creative Commons Zero v1.0 Universal", the
    free edition), the Godot Asset Store entry for this edition ("License: CC0 1.0
    Universal") and OpenGameArt ("License(s): CC0 - 3D Art"). CC0 allows redistribution
    and modification with no attribution.
  - **Quaternius's own site-wide licence contradicts it.** The Asset License (QAL) v1.0,
    last updated 2026-08-28, grants commercial use and modification but forbids selling or
    redistributing the assets themselves, modified or not, "as a standalone asset, asset
    pack, stock file, template or similar product", free or paid. Its §7 says the version
    in effect when the assets were obtained governs and §9 says it supersedes earlier
    understandings. This checkout is shallow, so when the owner obtained the file cannot
    be established from the repository history; both documents have to be taken seriously.
  - **Decision — development-only input, never shipped.** It stays in the repository on
    the CC0 grant that the pack page shows today, and it is covered here so the two never
    drift apart. Nothing the player sees depends on it: the clips the characters play are
    authored in code (`scripts/actors/character_animation.gd`). The boundary is
    machine-checked, not just written down: both export presets exclude `scenes/dev/*`,
    `tools/verify_build.py` fails a pack that contains anything under `res://scenes/dev/`,
    and it now fails a preset that stops excluding `scenes/dev/`.
  - **If the stricter QAL reading is preferred**, the remedy is a history rewrite
    (`docs/adr/0007-*.md` is the authorisation pattern for that kind of change), because a
    plain `git rm` would leave the blob in every clone and change nothing.
  - `protagonist_ual.res` in the same directory is derived from it — those clips resampled
    onto the protagonist's bones by `tools/bake_animation_retarget.gd` — and is covered by
    the same decision: development-only, not shipped.
- The seven clips the game's characters actually use — `idle`, `walk`, `jog`, `sit_idle`,
  `get_up`, `wave` and `talk` — are authored in code
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
