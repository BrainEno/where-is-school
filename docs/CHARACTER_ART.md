# Character art: the protagonist and Q in the game

This document covers how the protagonist and Q are drawn and carried in the running game:
what was reviewed, what changed, what was deliberately left alone, and how to reproduce,
compare and check it. It follows [ART_BIBLE.md](ART_BIBLE.md) ("In-game 3D characters": silhouette,
proportion, posture, clothing identity and readability, before facial detail) and the
character facts in [NARRATIVE_BIBLE.md](NARRATIVE_BIBLE.md). Motion is covered in
[CHARACTER_ANIMATION.md](CHARACTER_ANIMATION.md) ("Each character's own way of carrying the clips").

**Status.** Everything here is a proposal. The owner has not reviewed it. The owner has
decided only the brief itself: unify the two with the classroom's hand-painted look; the
protagonist dejected, cold, tired and uneasy, between youth and adult, not a handsome lead,
not anime; Q an ordinary, talkative, overweight, over-familiar classmate, not a guide.
Substitute teacher N and the seated classroom student are out of scope and unchanged.

**Prologue art review update (2026-11).** The seated classroom student is now painted too:
`assets/characters/classroom_student/student_look.tres` (`STUDENT` in
`art/characters/build_character_looks.py`), a charcoal sibling of the protagonist's look in a
plum-grey cardigan, with the ink line on its closed outer forms only (the 78 rigid pieces
include every finger). Every shipped look (protagonist, Q, N, student) is also *room keyed*:
each part's shade and light tint is moved 30 % towards the classroom's violet shadow
(`#7E74B0`) and apricot light (`#FFE0B4`), so the figures read as lit by the same painting
as the walls. The unshipped experiments keep their tints.

**Character integration update.** The protagonist's and Q's option C palettes below are now
the *base* the shipped looks are built on, not the shipped looks themselves: the character
integration ([CHARACTER_INTEGRATION.md](CHARACTER_INTEGRATION.md)) moved the protagonist to
a charcoal treatment, Q to an oil treatment (with the shoulder-seam skin painted over), and
gave N a look of her own (chalk) on the same shader. Option C's files are kept, frozen, in
`scenes/dev/character_lab/looks/before/` for comparison. The seated classroom student is
still out of scope.

**V2 head update (issue #383).** The "no UVs, no GLB is modified" rule of §2 applied to the
look round and is now deliberately superseded for the protagonist's head only: the head has
its own V2 build (`tools/head_v2.py`) with a local UV atlas, a tangent basis, 1024² albedo
and normal maps, and a denser hair cage that keeps the approved hairstyle. The approved V1
model is kept byte for byte as `art/character_models/sculpt/lead_v1_head.glb` (its SHA-256
is pinned in the builder, and `check` refuses to build from anything else). Body, wardrobe,
skeleton, weights, animations, materials, node names and every other mesh are unchanged.
Section 9 records the contract.

## Q replacement note

The Q-specific measurements and review statements in sections 1–2 below are **historical**:
they describe the retired 16-joint model, not today's separately approved replacement.
`assets/models/q/new-Q.glb` is now the sole production Q: 1.78449 m rest height, 9 skinned
meshes / 16 surfaces / 12 materials, 60 joints, thirty weighted finger joints and thirteen
head morphs. Its source is an original ChatGPT-generated Q explicitly approved by the owner
for this project. This approval does not constitute visual signoff on the migration.

The shipped C shader, protagonist model/hair/look and all unrelated art remain unchanged.
Only Q's material-name map, face-patch coordinates, blink names and posture calibration
are adapted: hoodie/hood/rib, body skin, sclera and inner mouth use their actual new names;
the patch follows the raised face, both hands omit the large hull that would merge fingers,
and the head's shared skin/hair surfaces are outlined selectively. Breathing/lean and
hand/finger gestures now use Q's own supplied motion rather than a held old forearm.
The complete structural comparison, reproducible source preparation, actual-engine evidence
and remaining visual review are in [Q_MODEL_MIGRATION.md](Q_MODEL_MIGRATION.md).
Do not restart the rejected Character Art Review experiments to evaluate this migration.

## 1. What was wrong

The protagonist and Q are lit with their GLB materials as imported: Godot's PBR path, with a
smooth Burley falloff, a specular lobe, and one flat colour per part. The classroom around
them is the opposite: toon diffuse, no specular, painted textures and an ink outline
(`assets/materials/classroom/*.tres`). Against that room the two read as plastic figurines:

- the faces are one smooth gradient with a highlight on the nose and cheeks;
- the clothes are one value per part, so the jacket, trousers and shoes merge under the
  room's low, warm light, and the silhouette depends on the background behind it;
- nothing in the line or colour belongs to the painted room, so the people look pasted in;
- both characters breathe, walk and talk to one shared rhythm (`CharacterAnimation.CLIPS`),
  and the protagonist stands as straight as Q does.

## 2. Model review

Both GLBs were read structurally and rendered from several angles before anything changed
(rest pose and bound clips, off-line, as reference only; not acceptance evidence).

| | Protagonist (`Protagonist_Character.glb`) | Q (`q.glb`) |
|---|---|---|
| Height | 1.767 m | 1.647 m |
| Head | 0.27 m chin to crown (about 6.6 heads tall), a narrow face 0.17 m wide, large eyes | 0.26 m (about 6.4 heads), a broad round face 0.24 m wide, full cheeks, small features |
| Body | narrow shoulders, thin limbs, a flat torso (0.24 m deep), A-pose arms about 35° out | round belly reaching 0.32 m in front of the spine, short limbs, right forearm modelled forward |
| Silhouette | tall and thin, with spiky hair as the top note | wide and soft, bowl hair, the belly the widest point in profile |
| Clothing | grey-green jacket (portrait: black gakuran), shirt, trousers, shoes | green sweater (portrait: off-white jacket), navy trousers, brown shoes with pale soles |
| Data | 9 meshes, 15 surfaces, 12 materials, 60 joints, no UVs, 9 blend shapes on the head | 7 meshes, 15 surfaces, 14 materials, 16 joints, no UVs, no blend shapes |

**Findings.**

- **Proportions and silhouettes already separate the two.** Tall and thin against short and
  round reads at gameplay distance, and it matches the narrative bible. Nothing in the
  geometry argues against either character's identity.
- **The protagonist's problem is posture and finish, not shape.** He stands upright with his
  arms out and his head level, which reads as neutral and confident. Every quality the brief
  asks for (tired, slightly hunched, held in) is a posture and an expression, and both are
  available without touching the mesh: the clip system poses the spine, neck, head and arms,
  and the head already carries `BrowCompress`, `LipTension`, `Frown` and the two blink shapes.
- **Q's problem is finish, and a body that moves like the protagonist's.** His silhouette is
  right; a looser, heavier rhythm leaning back on the heels is the missing part.
- **Hands, feet and faces** are simplified, as the art bible allows at a 2.5D camera. No hand
  or foot reads wrong in the clips; the protagonist's fingers are rigged but not animated.
- **No UVs.** Neither model has texture coordinates, so a painted texture would need new UVs
  for every part. That is a re-export, which would break the pinned sizes, the rig audits and
  the skinning contract. It is not needed: a position-based procedural paint gives the
  colour blocks the room has, and rest-pose coordinates keep them on the cloth (§4).

**Decision (proposal): no Blender source and no GLB is modified in this round.** No bone is
renamed, no vertex moves, no UV is added and no part is retopologised. Every change is in a
character-specific resource next to the model. A later round can still change the meshes;
if it does, keep the current export as the source of record and document the export here
and in `docs/ASSET_PROVENANCE.md`.

## 3. Three treatments, compared in the game

The comparison was made in the running game: the real classroom, corridor and street, with
their own lights, environment and tonemapping, through the game's own camera and from close
up. Section 7 says where the frames are. A model-preview window is not acceptance evidence.
The three treatments are switchable at run time on one node (`CharacterLookApplier`), so the
same frame can be taken three times.

| | A — original | B — pigment | C — painted (shipped) |
|---|---|---|---|
| What | the GLB materials as imported | `assets/shaders/painterly/character_pigment.gdshader`, one instance per GLB material carrying its base colour | `assets/shaders/characters/character_paint.gdshader` with an authored palette per part, plus `character_outline.gdshader` |
| Light | PBR, smooth falloff, specular | Lambert with a soft wobble | three bands (shadow, half-tone, light) with brushed edges, a painted shadow colour per part, no specular |
| Colour | one value per part | one value per part with slight mottling | two pigments per part in posterised blocks, plus painted patches (under-eyes, cheeks) |
| Line | none | none | ink hull on the outer forms, scaled with distance |
| Against the classroom | plastic; parts merge in low light | less glossy but still smooth and flat; parts still merge | in the room's own language: bands, blocks, ink |
| Identity | recognisable | recognisable | recognisable: same shapes, same colour families |

**B was evaluated and not applied.** It removes the specular sheen, but it keeps each part a
single value: the jacket and trousers still merge, there is no line to hold the silhouette
against the dark board, and the mottling is too fine to read at gameplay distance. It also
has no notion of a shadow colour, which is where most of the room's character lives.
`character_pigment.gdshader` and its `.tres` stay as they are, used by the painterly lab and
its test only.

**C is shipped** because it is the only one that matches the classroom on all three counts
(band lighting, rough colour blocks, ink) while keeping each character's identity: the same
colour families as the models and portraits, no part recoloured into another identity.

## 4. Option C in detail

### 4.1 The painted surface (`character_paint.gdshader`)

- **Three light bands.** `light()` turns N·L into shadow / half-tone / light with soft edges
  (`shadow_edge`, `light_edge`, `edge_softness`). The pigment noise shifts N·L by up to
  `edge_break` before the bands are cut, so a band edge wanders like a brush edge instead of
  following the mesh's facets.
- **The light band is held below full.** The full-light band is `light_strength` (0.76 by
  default, 0.70 on the protagonist's skin and 0.72 on Q's), not 1.0. Lambert reaches 1.0 only
  where the light hits square on; across the band N·L averages about 0.75. The first capture
  used a flat 1.0, and the warm key light of the classroom burned the protagonist's pale
  face to cream, so the eyes and the bruise under them stopped reading. The protagonist's
  skin also moves its `light_edge` to 0.55, so most of his face sits in the half-tone. That
  half-tone is darker on him (0.5 against 0.62), and his skin's pigment blocks are coarser
  (scale 15, value 0.14), so the cheekbone, nose and brow ridge keep their planes. With the
  defaults, the second capture showed one flat pale value from brow to chin.
- **A painted shadow colour.** The shadow side keeps `shadow_fill` of the light, tinted by
  `shade_tint`: cool violet-grey on the protagonist, olive on Q. It never goes dead black
  under one lamp, and it gives each character a colour of his own in shadow.
- **Pigment blocks.** A posterised, two-octave value noise (`pigment_steps` levels) pulls
  the base colour towards `pigment_a` or `pigment_b` and varies its value by
  `pigment_value`. Blocks are slightly stretched (`pigment_stretch`) so they read as strokes.
- **Rest-pose coordinates.** The noise is sampled at the vertex's bind-pose position, which
  `CharacterLookApplier` copies into `CUSTOM0` once per mesh (marked with w = 2). A skinned
  vertex's own position moves with its bone, and blocks placed by it would slide through a
  swinging trouser leg. The rebuilt mesh carries the GLB's own vertices, indices, normals,
  bones and weights unchanged and in order; only `CUSTOM0` is added
  (`tests/imported_assets_test.gd` compares them array by array). Meshes with blend shapes
  (the protagonist's head) keep their mesh and fall back to the object-space position, so
  the blocks on his face shift by a few millimetres when the head nods.
- **Painted patches.** Two ellipsoids per part, mirrored across the face, with an uneven
  edge: the protagonist's bruised under-eyes and hollow cheeks, Q's flushed cheeks.
- **No specular, no rim, no reflections** (`specular_disabled`, `SPECULAR = 0`,
  `ROUGHNESS = 1`): nothing for a highlight to slide on.

### 4.2 The ink line (`character_outline.gdshader`)

An inverted hull drawn as the `next_pass` of the outer parts, in the classroom's ink
(#292433, the biology-classroom experiment's pen since the prologue art migration). The classroom's hull grows a fixed 1.6 cm; a person is seen from under a metre in a
close-up and from six metres in play, so this hull grows with view distance (`width` 10 mm at
4 m, clamped ×0.55–×1.7). It stays thin enough not to swallow the eyes in a close-up and thick
enough to hold the silhouette against the board. Eyes, mouth, brows, buttons, collar, shirt
and soles carry no hull. Being a material pass, it adds no node, mesh or surface: the wrapper's
counts and bounds are unchanged.

### 4.3 Palettes

The protagonist is cool and held in; Q is warm and open. They separate in hue (cool slate and
grey-green against moss and terracotta), in value structure (dark jacket on a pale face against
a mid-green sweater on a ruddy face) and in shadow colour.

| Part | Protagonist | Q |
|---|---|---|
| Skin | #B4A58C (body #A99A83), pale and sallow (pigments #98A088 / #C2A68E), shadow #9AA6C6 | #CE9A70, ruddy, shadow olive #B5B88E |
| Face patches | under-eyes #665570 (bruised), cheek hollows #98997F | cheeks #C9634C (flushed) |
| Hair | #221E21, near-black | #18151B, near-black |
| Top | slate jacket #37414A (towards the portrait's gakuran, kept apart from the dark board by the ink and the lighter shadow fill) | moss sweater #516F4C (the model's own green, not the portrait's jacket: the model is the identity in play) |
| Trousers | warm charcoal #3B3836, so jacket and legs separate | navy #313D52 |
| Shoes | dark, outlined | brown, pale soles (no line on the sole) |

The full table, with every pigment, shadow tint and patch, is
`art/characters/build_character_looks.py`, which writes
`assets/characters/protagonist/protagonist_look.tres` and `assets/characters/q/q_look.tres`.
Edit the script, not the `.tres` files, and run it (stdlib Python, no dependencies):

```bash
python3 art/characters/build_character_looks.py          # rewrite both looks
python3 art/characters/build_character_looks.py --check  # fail if they are out of date
```

### 4.4 The protagonist's face

The head's own blend shapes give him a resting expression: `BrowCompress` 0.45 (a knitted,
worried brow), `LipTension` 0.35, `Frown` 0.15, and lids a little lowered and uneven
(`Blink_L` 0.10, `Blink_R` 0.15): tired, uneasy, not sad-cartoon. He blinks every 1.8–4.2 s,
from a seed derived from the look's label, so two captures of the same scene blink alike.
His eyes stay the brightest, highest-contrast point of the face, framed by the bruised
patch, which is what makes them the first thing read. Q's face is left as modelled: his smile
is his identity.

## 5. Posture and rhythm

Each wrapper carries a `CharacterMotionProfile`
(`assets/characters/{protagonist/protagonist_motion.tres, q/q_motion.tres}`), handed to
`CharacterAnimation.bind()`. It changes the keys the shared clips are written with: tempo,
amplitude, a standing posture and small layers. It does not change the clips, their names,
their bones or the state machine. The details and the numbers are in
[CHARACTER_ANIMATION.md](CHARACTER_ANIMATION.md); in short:

- **Protagonist:** spine, chest and neck pitched forward (4° / 5° / 6°), head lowered, arms
  drawn in 14° towards the body and the elbows a little bent. The idle is twice as slow, with a
  sigh in the chest and a head that drops and recovers. The walk keeps its stride and uses
  restrained arm tracks (see the current [motion profile](CHARACTER_ANIMATION.md#per-character-motion-resources));
  the talk gestures are half size, and he gets up more slowly (2.0 s).
- **Q:** leaning back (spine −4.5°), head cocked, a wider stance, the free arm out from the
  belly. A quicker idle with a sway, a walk with the spine and arms swinging more, a talk
  that is half as big again and faster.

## 6. Where it lives

| Path | What |
|---|---|
| `assets/shaders/characters/character_paint.gdshader` | the painted surface (§4.1) |
| `assets/shaders/characters/character_outline.gdshader` | the ink hull (§4.2) |
| `assets/characters/protagonist/protagonist_look.tres`, `assets/characters/q/q_look.tres` | `CharacterLook`: one painted `ShaderMaterial` per GLB material (or `mesh/material`), the resting expression and the blink. Generated (§4.3) |
| `assets/characters/protagonist/protagonist_motion.tres`, `assets/characters/q/q_motion.tres` | `CharacterMotionProfile` (§5) |
| `scripts/actors/character_look.gd` | the `CharacterLook` resource |
| `scripts/actors/character_look_applier.gd` | `CharacterLookApplier`: applies a look to the model next to it, switches treatments, rebuilds meshes with rest coordinates, drives the blink |
| `scripts/actors/character_motion_profile.gd` | the `CharacterMotionProfile` resource |
| `scenes/environment/characters/protagonist.tscn`, `q.tscn` | the wrappers: `motion_profile` on the root, a `Look` node beside `Model` |
| `art/characters/build_character_looks.py` | the palette table and the generator of both looks |
| `tools/head_v2.py`, `tools/head_v2_textures.py` | the V2 head builder and its map generator (§9) |
| `assets/characters/protagonist/textures/head_albedo.png`, `head_normal.png` | the head's local 1024² maps (§9.2) |
| `scripts/actors/character_detail_maps.gd` | the detail-map draw the paint shader includes when a look names maps (§9.2) |
| `tools/head_preview.py`, `tools/head_preview.c` | the offline renderer that reproduces the evidence frames (§9.3) |
| `tests/capture_character_art.gd`, `.github/workflows/character-art-capture.yml` | the in-game capture (§7) |

The model directories still hold only the `.glb` and its `.import` (tested). Nothing in the
classroom or any other location scene, nor in the display system, was changed: the wrappers
are the only scenes touched, so every place that instances them gets the new look.

## 7. Checking it

**Headless, in `godot-ci.yml`:**

- `tests/imported_assets_test.gd`: both wrappers carry their profile and a `Look`; every one
  of the 15 surfaces is painted with `character_paint.gdshader` (none kept in its GLB
  material); some, not all, carry the ink; ORIGINAL and PIGMENT are reachable and reversible;
  the rebuilt meshes keep the GLB's vertices, indices, bones and weights and add rest
  coordinates; the skeleton's bone count is unchanged; the protagonist has a resting expression.
- `tests/protagonist_model_test.gd`: the painted player's meshes are still skinned to the
  60-bone skeleton and the head keeps its nine blend shapes.
- `tests/character_animation_test.gd`: the profiles add no track and move no track to another
  bone, every clip is `CLIPS` length × tempo, `get_up` still starts on the `sit_idle` pose,
  the posture is in the standing pose, and the two characters' idle, walk and talk differ in
  length.
- `tests/runtime_character_animation_test.gd`: in the running game, both characters are bound
  with their profile, drawn PAINTED with nothing kept, and do not share one tempo; all the
  existing idle, walk, hand-height, leg and get-up limits hold with the profiles applied.

**Offline, beside the engine:**

- `python3 tools/head_v2.py check`: rebuilds the head from the pinned V1 source, requires the
  installed GLB to be that build byte for byte, and asserts the §9.3 contract (atlas, seam,
  lids, aperture, hair locks, budget);
- `python3 tests/model_library_test.py`: every model still parses, fits its budget, carries
  no camera or light, and the runtime characters still match their manifest.

**In the game, `Character art capture` workflow** (`tests/capture_character_art.gd`, Xvfb,
OpenGL, 1600×900), one job per group:

| Group | Frames |
|---|---|
| `bodies` | head to feet, A / B / C, each character alone in the west aisle against the board |
| `faces` | face close-ups A / B / C, and the game's own camera with A and with C |
| `clips` | idle, walk, jog, sit_idle, get_up, wave, talk, painted, one still each |
| `posture` | idle and walk without and with the profile, side on; silhouettes front, ¾, side, back |
| `light` | the painted pair in the classroom (front and back of the room), the corridor and the street, from the game camera and close |

Each job publishes its contact sheets as notices (base64 JPEG in 4000-character parts) and
uploads the full-size frames and the log as an artifact. The job fails when a character does
not draw, did not bind, or kept a GLB material under the painted look. Nameplates (a
development aid) are hidden for the frames.

## 8. Limits and open points

- The pigment on the protagonist's face is sampled in object space (his head mesh has blend
  shapes, which the rest-coordinate rebuild does not carry), so it shifts slightly when the
  head nods. Carrying the blend shapes over is possible, but it was left out until it can be
  checked in an engine.
- The shader recomputes the noise in `light()` for each light. That costs a little more than
  the GLB material, on two characters only; the classroom has two lights plus the sun.
- The portraits differ from the models in clothing (the protagonist's black gakuran, Q's
  off-white jacket). The palettes move towards the portraits only where the model's identity
  allows (a darker slate jacket); they do not recolour Q's sweater into a jacket. Whether the
  models should follow the portraits is an owner decision.
- Options B and C can be compared at any time in a running scene:
  `$Look.apply_treatment(CharacterLookApplier.Treatment.PIGMENT)`.

## 9. The V2 head (issue #383)

### 9.1 What the build is

A deterministic rebuild of the protagonist's head and hair, run only from the pinned V1
source (`art/character_models/sculpt/lead_v1_head.glb`, SHA-256
`2b24d063bee3044dac8b9eb11945ead8cf001b6decd045c48e1e0b2ee7c40e6e`; `check` refuses any
other file):

```bash
python3 tools/head_v2.py build     # V1 -> build/head_v2/Protagonist_Character.glb
python3 tools/head_v2.py install   # copy that build over the runtime GLB
python3 tools/head_v2.py check     # rebuild, require the installed GLB to be this build's
                                   # output byte for byte, assert the contract in §9.3
```

- **The skin** is subdivided once (four triangles per original), sculpted in rest space —
  eye sockets, lids that wrap the eyeball, nose wings and underside, lips and their
  surroundings, cheekbones, a widened jaw, a brought-forward chin, brow ridge, neck — then
  given one continuous face-focused UV atlas (the back seam is split in the mesh), a tangent
  basis, and its nine sparse morph targets resampled through the subdivision map (deltas
  under a fifth of a micron are zeroed so the sparse targets stay honest).
- **The hair keeps the owner's hairstyle**: the same 96 locks, roots, tips and silhouette —
  the bounding box is identical to V1's. Each lock's five rings are subdivided in place:
  the midpoint of every ring edge is inserted (5 → 10 columns, 45 → 90 triangles per lock;
  2 799 → 5 199 vertices and 4 880 → 9 200 triangles overall, smaller than the strand-split
  draft it replaces), thinned to 0.82 of its radius about the strand's own axis, and the
  strand takes one gentle outward bend of at most `min(2 mm, 3 % of length) · sin(πt)` with
  `t` the ring centre's axial parameter. The root ring and the tip take no bend, the scalp
  cap is untouched, and the mesh stays manifold with no degenerate triangle.
- **The eyes** are levelled (V1's right eye sat 2.5 mm high), their flat iris and pupil
  discs domed, the iris given a limbal ring through vertex colour; the eyebrows are re-hung
  on the brow ridge as tapered tubes; the ears get a bowl, helix, concha and lobe; the
  mouth's interior follows the lips. The rebuilt face parts re-express the head's nine
  morph targets against their new rest pose; the eye mesh itself carries none, as in V1.
- **Body, wardrobe, skeleton, weights, animations, materials, node names and every other
  mesh** are copied byte-for-byte from the runtime GLB.

### 9.2 Maps and their wiring

The head's fine relief and local colour live in 1024² maps, not in more triangles:
`assets/characters/protagonist/textures/head_albedo.png` (lips, the bruised under-eye
patch, stubble) and `head_normal.png` (creases and skin grain), generated by
`tools/head_v2_textures.py`. `CharacterLook.detail_maps` names them,
`CharacterLookApplier` binds them, and `scripts/actors/character_detail_maps.gd` is the
draw the paint shader includes when a look names maps. The channel is **opt-in**: the
protagonist's look enables it, every other character's look does not, and none of those
models has UVs, so the old path is untouched. The A/B is one flag:

```bash
python3 tools/head_preview.py assets/models/protagonist/Protagonist_Character.glb \
    --look assets/characters/protagonist/protagonist_look.tres --out build/head_v2/look
python3 tools/head_preview.py assets/models/protagonist/Protagonist_Character.glb \
    --look assets/characters/protagonist/protagonist_look.tres --no-detail-maps \
    --out build/head_v2/look_nodetail
```

### 9.3 The contract `check` asserts

| | |
|---|---|
| V1 source | SHA-256 pinned; any other file refuses to build |
| Head | 11 332 vertices, 22 064 triangles, 9 morph targets, atlas inside [0, 1], no triangle spanning the back seam (max U span 0.49999), 4 lid shells, aperture 13.4 mm |
| Hair | 5 199 vertices, 9 200 triangles, 96 locks + the cap, bounding box identical to V1 |
| Eyes | 0 morph targets on the eye mesh |
| Budget | installed GLB 1 199 412 B, under the 1 536 KiB model budget |

Evidence frames are reproducible with `tools/head_preview.py` (clay = no `--look`, wired =
the shipped look, `--views front,quarter,side,close`, `--no-detail-maps` for the A/B).
At this head the offline check, the offline renders and the Python tests
(`verify_build_test`, `model_library_test`, `character_geometry_capture_test`,
`agent_docs_test`) were run locally; the engine tests in §7 run in CI; the owner's grey-model
and textured acceptance is recorded on issue #383.

### 9.4 Limits

- The face pigment of §4.1 still samples object space for the head (the rest-coordinate
  rebuild does not carry blend shapes), so those blocks shift a few millimetres when the
  head nods; the new maps are UV-space and do not shift.
- The hair's bend and taper are rest-pose geometry, not simulation.
- `tools/head_v2.py extract` re-creates the V1 source from the pre-V2 runtime only; the
  committed V1 file, not an extract, is what `build` reads.

## 10. The V3 hair (issue #386)

### 10.1 What the build is

The same deterministic pipeline (`tools/head_v2.py`), still built only from the pinned V1
source and still byte-compared by `check` — with one more pass over the hair between the
V2 ring refinement and the write. The issue asks for the work in a fixed order, and the
pass runs in that order:

1. **Whorl and hairline.** The scalp cap's interior takes a spiral relief around the
   crown plus concentric arcs running from the whorl towards the nape (`whorl_cap`, at
   most 1.3 mm along each vertex's own outward direction, faded to nothing within 18 mm
   of the cap's edge). The cap's boundary is the owner's hairline and is pinned vertex
   for vertex — the cut never moves.
2. **The silhouette is clamped.** The V2 hair envelope (the model's measured bounding
   box) is pinned as constants; every V3 displacement is clamped inside it, and `check`
   asserts the built hair's bounding box back against the pins. The approved outer
   silhouette — the tips, the model height, the width the tests measure — cannot drift.
3. **The fall, root first.** Each lock's root ring dives 8 mm back along its own axis,
   under a skull clamp: a polar radius field of the *sculpted* skin (4° × 4 mm bins,
   dilated one bin) pushes every displaced vertex at least 1.2 mm off the head, so the
   burial enters the mass without ever piercing the skin. The root ring widens
   1.28–1.56× in its own plane (ring 1 follows at 45 %) until neighbouring roots touch —
   the triangular gaps between fringe locks close from underneath, not by pushing tips
   about. Each shaft then bows 5–11 mm under gravity — yawed per lock, zero at root and
   tip — with a gentle S wobble, so the upward locks lean and the side locks drop as one
   hair. Locks wider than 22 mm (the plate bunches) take one inward crease down rings
   2–3, splitting the plate into strands.
4. **The strand rhythm.** The V2 profile measured (1.0, 1.14, 1.04, 0.88, 0.55) — a
   mid-shaft bulge that is why every lock read as a cone with a pinched tip. V3 remaps
   the rings onto a clean fall (1.0, 0.94, 0.82, 0.66, 0.55), and each lock takes its own
   width (0.86–1.12×, hashed — no randomness, every build identical), a ±16 % wide-thin
   modulation along the shaft, and a cross-section twist of at most 0.15 rad. No two
   neighbouring locks share a width-phase-bend combination, which is what breaks the
   clone-array read.

No transparency, no groom, no new geometry: vertex and triangle counts and the topology
are V2's (5 199 vertices, 9 200 triangles, 96 locks + the cap), the skin weights are
untouched, and the cap edge and every tip stay where V2 put them.

### 10.2 The hair's maps

The hair mesh now carries a UV atlas (`hair_uv`): the cap maps azimuth and height into a
3 × 3 block, and each of the 96 locks owns one cell of the remaining grid — U runs around
the ring, V runs root to tip, no island wraps, and no vertex is duplicated, so the mesh
keeps its exact V2 vertex count and topology. The look draws two new maps into that
atlas through the same `detail_maps` channel as the head's (§9.2):

- `hair_normal.png` (1024²): two flickered strand grooves per lock cell — dark lines,
  broken by noise so they read as separate hairs rather than extruded stripes — the same
  whorl field the mesh relief uses, sampled at texel resolution, and a strand grain.
- `hair_albedo.png` (512²): two lighter strand glazes offset beside the grooves (colour
  beside relief, never on top of it), darker roots, and a cool tone noise, drawn as a
  multiplier over the look's hair colour at `albedo_mix` 0.75.

The maps ride the same UV gate as the head's: the applier binds them only to surfaces
that really carry UVs, and the eyebrows — which share the hair material on the head mesh
without UVs — keep drawing exactly as before. `detail_maps_enabled` is the A/B for both
the head's and the hair's maps, and the preview takes `--no-detail-maps` for the
comparison:

```bash
python3 tools/head_preview.py assets/models/protagonist/Protagonist_Character.glb \
    --look assets/characters/protagonist/protagonist_look.tres --out build/head_v2/look
python3 tools/head_preview.py assets/models/protagonist/Protagonist_Character.glb \
    --look assets/characters/protagonist/protagonist_look.tres --no-detail-maps \
    --out build/head_v2/look_nodetail
```

### 10.3 What `check` adds

| | |
|---|---|
| Hair UV | the hair primitive carries `TEXCOORD_0` |
| Envelope | the built hair's bounding box matches the pinned V2 envelope within 0.1 mm |
| Counts | 5 199 vertices, 9 200 triangles, 96 locks + the cap — unchanged from V2 |
| Budget | installed GLB 1 199 412 B, under the 1 536 KiB model budget |

### 10.4 Limits

- The whorl, the bow and the twist are rest-pose geometry, as in §9.4 — not simulation.
- The strand grooves are painted in each lock's own atlas cell, so they follow the lock
  it belongs to; the hair carries no morph targets, so nothing shifts them.
- The envelope clamp is absolute: V3 re-shapes the volume between root and tip, never the
  silhouette's extremes.
