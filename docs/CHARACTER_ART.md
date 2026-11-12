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
(#2B2622). The classroom's hull grows a fixed 1.6 cm; a person is seen from under a metre in a
close-up and from six metres in play, so this hull grows with view distance (`width` 9 mm at
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
| Skin | #C8B9A0, pale and sallow (pigments #B3B39A / #D5BDA4), shadow #9AA6C6 | #CE9A70, ruddy, shadow olive #B5B88E |
| Face patches | under-eyes #6F5F7A (bruised), cheek hollows #98997F | cheeks #C9634C (flushed) |
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
  sigh in the chest and a head that drops and recovers. The walk keeps its stride but the arms
  barely swing (×0.45), the talk gestures are half size, and he gets up more slowly (2.0 s).
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
