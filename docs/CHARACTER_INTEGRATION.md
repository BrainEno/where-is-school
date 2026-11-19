# Character integration: the protagonist, Q and N in the prologue's scene language

Chinese copy: [CHARACTER_INTEGRATION.zh-CN.md](CHARACTER_INTEGRATION.zh-CN.md). This English
file is canonical.

**What this is.** PR #203 moved the classroom to the biology-classroom experiment's look:
a two-step terminator with ambient-coloured shade, cool walls, deep-blue curtains, a warm
low sun and a single ink. The three people in it were not moved with it. This document
records:
- the audit of the three characters against that room;
- the experiments, with at least two substantially different schemes each for Q and N, and
  one for the protagonist;
- what was integrated, and how it was verified in the running game.

It extends [CHARACTER_ART.md](CHARACTER_ART.md), whose option C palettes are now the *base*
the shipped looks are built on. It does not replace it.

**Status.** Proposal, not owner-approved. Nothing here changes a character's model, rig,
animation, story role, dialogue or portrait. The owner decisions still open are listed at
the end.

Model identity: 平台未显示，无法核实.

## 1. Baseline audit (main `a3b274b`)

### 1.1 How each character is built and drawn

| | Protagonist | Q | N |
|---|---|---|---|
| Model | `assets/models/protagonist/Protagonist_Character.glb`, 1.767 m, about 6.6 heads | `assets/models/q/new-Q.glb`, 1.784 m, about 6.7 heads, broad and moderately stocky | `assets/models/teacher-n/teacher-n.glb`, 1.654 m, about 6.7 heads, small narrow head |
| Rig | 60 joints, 9 head morphs | 60 joints, 13 head morphs | 16 joints (old Q joint names), no morphs |
| Meshes and materials | 9 meshes, 15 surfaces, 12 flat materials | 9 meshes, 16 surfaces, 12 flat materials | 18 meshes, 28 surfaces, 17 flat materials (`M_ST_*`), roughness 0.15–0.9 |
| Textures and UVs | none | none | none |
| Animation | UAL retarget plus own profile `protagonist_motion.tres` | own six actions plus `q_motion.tres` | its own four loops (`authored_idle_layers`), no profile |
| How it is drawn in game | `CharacterLookApplier` with option C: `character_paint.gdshader` plus ink hull | the same, option C | **raw GLB PBR materials**: no applier, no paint shader, no ink |
| Portrait | separate 2D artwork (`id-*`), not a render | the same | the same |

### 1.2 What the room asks for

The classroom lights everything through one model, `concrete.gdshaderinc`:
- a hard two-step terminator (0.12 ± 0.03);
- shade in the room's own ambient colour (0.44, 0.38, 0.52);
- broken blue-green and ochre mottling;
- no specular highlights;
- one ink, `#292433`.

The sun is warm, low and from the west. Shadows on the floor are violet. The backdrops
behind a standing character are the dark green-black board, the deep-blue curtain and the
lavender walls.

### 1.3 Three problems per character (classified)

Measured on `before` frames from `tests/capture_character_integration.gd`.

| Character | Problem | Class |
|---|---|---|
| Protagonist | Jacket, trousers and hair are all near-black (#22–#3B). From the gameplay camera above he is the darkest object on a sunlit floor and reads as a cast shadow, not a person | material (value design) |
| Protagonist | His ink line is the same value as his clothes, so on the dark side his contour disappears into the floor's violet shadows (mean luminance 0.090 in shade) | render (separation) |
| Protagonist | The spiky hair, his most recognisable shape, has no internal value, so from above it is a blot | material |
| Q | The broad face has small features. The eyes and the heavy lids, which are his expression, vanish at distance | material (face value) |
| Q | The body skin pokes through the hoodie at the shoulder seams: pale spikes at both shoulder tips in every frame (`Q_MODEL_MIGRATION.md` §8) | model defect, source approved so not reshaped |
| Q | The hoodie's moss green and the bright tan rib sit between the curtain's blue and the board's green, so the costume competes with the room instead of belonging to it | material (colour relation) |
| N | Drawn with none of the room's pipeline: PBR gradient, specular, no terminator, no ink. She looks plastic and lit by a different sun | render (pipeline) |
| N | Pale, low-contrast costume: blouse, cardigan and trousers all within a narrow light grey band (mean luminance 0.298 against the others' 0.18–0.19). She is the brightest thing on the stage and has no value structure, so she reads as a low-detail placeholder | material |
| N | Pear-shaped silhouette: narrow shoulders (±0.22 m) over a cardigan that flares to 0.136 m deep at the hem, light trousers that widen it further, a helmet-like striped bob, and a mask-like face | model (silhouette) plus material |

The pale-yellow rim around Q in the old `q_close` frame is **not** his ink. It is the
interaction highlight, `WorldCue.OUTLINE_COLOR`, drawn because the player was within talk
range. The new capture switches interaction off except for its click on Q.

**Real cause, in one line:** the room is defined by a *light model and a value plan*, and
the characters were not on that plan. N was off the light model entirely; the protagonist
and Q were on it but with the wrong values. Neither more polygons, nor textures (there are
no UVs), nor post-processing addresses that.

### 1.4 Duplicate, old and unused assets

| Asset | Status |
|---|---|
| `assets/models/protagonist/protagonist.glb` | the former protagonist; **still used** by `classroom_student.tscn` (the seated student), so it is not unused |
| `assets/models/sample/figure.glb` | used by `sample_figure.tscn` and the model library tests |
| `art/character_models/{q,teacher-n}/*_source.glb` | pinned sources (`.gdignore`d); required by `prepare_q.py` and `prepare_teacher_n.py` |
| `assets/shaders/painterly/character_pigment.gdshader` | option B, rejected, but still a reachable treatment (`PIGMENT`) that `imported_assets_test.gd` checks |

No character asset is confirmed unused, so **nothing was deleted**.

## 2. Experiments

Every experiment is a `CharacterLook` built by `art/characters/build_character_looks.py`
from `art/characters/look_experiments.py`. They use the same paint and ink shaders, and the
experiments added three opt-in features to those shaders, all off by default:
- **Stroke marks** (`mark_*`, `character_paint.gdshader`): short, broken strokes laid on in
  rest space. They can cover a part evenly (dry brush or chalk tooth) or gather where the
  form turns away from the eye (the carved edge of a woodcut). Below pixel size they fade
  to their average tone, so they do not shimmer at gameplay distance.
- **Silhouette shaping** (`shape_*`, `character_shape.gdshaderinc`, shared by paint and
  hull): up to two rest-space ellipsoids push a form in or out along its posed normal by a
  few centimetres. The GLB is untouched, and the mesh AABB and skinning are unchanged.
- **Hull wobble** (`wobble`, `character_outline.gdshader`): a hand-cut line width.
- **Two-sided paint** (`two_sided`, `character_paint_two_sided.gdshader`): the same paint
  drawn with culling off, for a part whose triangles face inward (see N below).

The option C looks that shipped before (`assets/characters/{protagonist,q}/*_look.tres` on
main) are produced byte for byte by the same builder until a look sets a new parameter.
Frozen copies are in `scenes/dev/character_lab/looks/before/`.

| Character | Scheme | Idea | Result in game | Decision |
|---|---|---|---|---|
| Protagonist | **charcoal** | Gakuran lifted from near-black to a slate that takes the sun, warm light on shoulders and back; pale "erased" strokes along every turning edge; strand marks in the hair | Shoulders and back read from the gameplay camera, and his contour separates from violet shade (0.090 → 0.110 in shade). v1's hair marks cluttered the face; v2 halves them, and v3 darkens them, because at this scale they averaged into a grey veil along the spikes | **integrated** |
| Q | **oil** | Large stretched colour blocks; olive half-tones that carry the broad face's planes; an upper-lid hollow for his heavy lids; impasto fold strokes; hoodie moved towards ochre-olive, rib dulled | The face keeps its expression at distance and the hoodie sits with the floor and the board rather than against them. v1's eye patch smudged the bridge of the nose; v2 keeps it 1.4 cm off the centre | **integrated** |
| Q | **etched print** (`q_paper`) | Two hard bands, almost no colour drift, long diagonal hatching in a darker tone, flat black hair with pale strands | The hoodie reads as knit, but on skin the hatching read as scars and drew contour rings on the neck (v1). Without it (v2) the face goes flat and poster-like, a different medium from the room's paint | experiment only |
| N | **chalk** | Pastel on grey paper: softer terminator, lilac shade from the room's ambient, pale chalk strokes over a lifted sage cardigan, dark slim trousers, the portrait's pale face and dark bob, cardigan hem taken in by 8 mm | A person in the room's light. Value is now in the family (0.241 against 0.186 and 0.189), the pear shape is gone, and she is youthful and soft, not authoritative. v1 and v2 showed blank, ringed eyes, like spectacles. The cause is the model, not the look: teacher-n.glb's eyeballs face inward, so the one-sided paint culled iris and pupil and showed the inside of the back wall. Their three parts are now painted two-sided | **integrated** |
| N | **woodcut** (`n_woodcut`) | White-line woodcut: hard bands, deep violet shade, pale gouges along the edges of a near-black slate cardigan, a hand-cut wobbling contour, hem taken in by 12 mm, crown of the bob let out by 1 cm | Striking, but she becomes as dark and heavy as the protagonist (0.158 in sun), merges with the board, and reads severe and authoritative. That contradicts the bible: an inexperienced substitute, not superior. Its wide, wobbling hull also draws a thin spectacle-like line in the eye-socket and nose-bridge creases (the inverted hull's known crease artifact), left unfixed because the scheme is not shipped | experiment only |

The two schemes for Q, and the two for N, differ in medium (paint against print, chalk
against cut block), in value plan and in line, not just in strength.

## 3. What was integrated

| Character | Look (`assets/characters/…`) | In one sentence |
|---|---|---|
| Protagonist | `protagonist/protagonist_look.tres`, "charcoal (integrated)" | Still the black-gakuraned, grey-skinned, spiky-haired boy, now drawn in charcoal on the room's paper: a slate that catches the sun, erased light along his edges, hair read by its strands |
| Q | `q/q_look.tres`, "oil (integrated)" | Still the ordinary, broad, over-familiar classmate in a green hoodie, now in thick oil with the room's olive and ochre, his heavy lids legible, the shoulder-seam skin painted over |
| N | `teacher_n/teacher_n_look.tres`, "chalk (integrated)", plus a `Look` node in `teacher_n.tscn` | Still the young substitute with a dark bob in a sage cardigan, now drawn in the room's light and line, soft pastel, slim and uncertain rather than pale and pear-shaped |

**Heterogeneous but one world.** The three looks share the room's light model, its shade
colour family, its single ink and its paper, but use three media: charcoal, oil and chalk.
Each also has its own value key: dark (protagonist), mid and warm (Q), light and cool (N).

**Unchanged:**
- every GLB, rig, skin and animation clip;
- the motion profiles, and N's authored idle layers;
- dialogue and portraits;
- interaction anchors and collision;
- N's hidden-until-entry placement, `NEntryPath`, `NPresence` and story flags;
- Q's camera shot `q_talk` and its focus logic;
- the player controller and camera rig.

## 4. In-game verification

All frames come from `tests/capture_character_integration.gd`, run by the
`Character integration capture` workflow. It boots `main.tscn`, enters the real classroom
and photographs the real wrappers (the player's protagonist and the room's `Actors/Q` and
`Actors/N`) under the room's own sun and environment. Columns differ only in the look the
applier carries. Blender or offline renders are not used anywhere as evidence.

Committed sheets:
- `docs/screenshots/character_integration/final/` (before / second scheme / after);
- `docs/screenshots/character_integration/round1/` (before / v1 experiments).

| Required comparison | Sheet(s) |
|---|---|
| Protagonist in the classroom | `final/protagonist_gameplay__before_after.jpg`, `final/protagonist_body_sun__before_after.jpg`, `final/protagonist_body_shade__before_after.jpg` |
| Q close-up and dialogue | `final/q_face__before_q_paper_after.jpg`, `final/q_face_three_quarter__before_q_paper_after.jpg`, `final/dialogue_dialogue_q__before_after.jpg` |
| N close-up and in scene | `final/n_face__before_n_woodcut_after.jpg`, `final/n_lectern__before_n_woodcut_after.jpg`, `final/dialogue_dialogue_n__before_after.jpg` |
| All three under the same light | `final/lineup_lineup_sun__before_after.jpg`, `final/lineup_lineup_shade__before_after.jpg`, `final/lineup_lineup_game__before_after.jpg` |
| Motion | `final/q_talk__before_after.jpg`, `final/q_walk__before_after.jpg` |

The dialogue frames come from the game's own click path and camera (`q_talk` focus) and
from `play_conversation(&"n_class")`. They show the 2D portraits, unchanged. The before
and after columns are taken in one session, so they can stop on different lines of the
same conversation.

Mean luminance of each character's drawn pixels, from the `ARTNOTE` lines of capture run
43918819332 (the committed `final/` sheets):

| Frame | Protagonist before → after | Q before → after | N before → after |
|---|---|---|---|
| Lineup, sun | 0.177 → 0.186 | 0.193 → 0.189 | 0.298 → 0.241 |
| Lineup, shade | 0.135 → 0.151 | 0.147 → 0.144 | 0.239 → 0.175 |
| Solo, shade | 0.090 → 0.110 | — | 0.223 → 0.174 (woodcut 0.108) |

## 5. Tests and checks

- `tests/imported_assets_test.gd` holds N to the same look contract as the other two:
  - every one of her 28 surfaces is painted, and some but not all carry ink;
  - ORIGINAL and PIGMENT are reachable and reversible;
  - the rebuilt meshes differ only in `CUSTOM0`, with the same AABB and bone count.

  Exactly six of her surfaces (sclera, iris and pupil, both eyes) use the two-sided shader;
  the other characters use none. Her wrapper must carry **no** motion profile (`"motion": ""`), because she plays her own
  loops.
- `build_character_looks.py --check` (Godot CI) now also covers N's look and the two kept
  experiments.
- No test was skipped, weakened or removed.

## 6. Inventory of changed and added files

| File | What |
|---|---|
| `assets/shaders/characters/character_paint.gdshaderinc` (+ `.uid`) | the paint body: opt-in stroke marks and shaping (defaults reproduce the old output) |
| `assets/shaders/characters/character_paint.gdshader` | one-sided entry shader (`cull_back`), the notes |
| `assets/shaders/characters/character_paint_two_sided.gdshader` (+ `.uid`) | two-sided entry shader, for N's inward-facing eyeballs |
| `assets/shaders/characters/character_outline.gdshader` | opt-in shaping, wobble |
| `assets/shaders/characters/character_shape.gdshaderinc` (+ `.uid`) | shared silhouette shaping |
| `art/characters/build_character_looks.py` | per-part hulls, `two_sided` parts, N target, experiments |
| `art/characters/look_experiments.py` | all scheme palettes and the shipped selection |
| `assets/characters/protagonist/protagonist_look.tres` | regenerated: charcoal |
| `assets/characters/q/q_look.tres` | regenerated: oil, shoulder fix |
| `assets/characters/teacher_n/teacher_n_look.tres` | new: chalk |
| `scenes/environment/characters/teacher_n.tscn` | `Look` applier node |
| `scenes/dev/character_lab/looks/{q_paper,n_woodcut}.tres`, `before/*.tres` | experiments and frozen option C (export-excluded) |
| `scripts/actors/character_look_applier.gd` | doc comment only |
| `tests/imported_assets_test.gd` | N in `CHARACTER_LOOKS`, "no motion profile" rule |
| `tests/capture_character_integration.gd` (+ `.uid`), `.github/workflows/character-integration-capture.yml` | in-game capture |
| `docs/CHARACTER_INTEGRATION{,.zh-CN}.md`, `docs/CHARACTER_ART.md`, `docs/screenshots/MANIFEST.json`, `docs/screenshots/character_integration/` | documentation and evidence |

No model, texture or animation file changed; there are no textures. All looks are
hand-authored parameters, not generated assets, so `ASSET_PROVENANCE.md` needs no new row.

## 7. Unresolved, and decisions for the owner

1. **Q's shoulder seam** is painted over, not fixed. The skin still pokes through the
   hoodie by a few millimetres; it is now the hoodie's colour and carries no ink. A real
   fix is a local garment patch on the approved source, which needs your authorisation
   (`Q_MODEL_MIGRATION.md` §8).
2. **How far to lift the protagonist.** The charcoal look keeps the gakuran dark on
   purpose: it is his identity. Lifting it further would read better from above, but would
   move him away from the portrait.
3. **N's cardigan hue.** Kept in her sage family. The woodcut scheme suggests a darker,
   stronger costume. It was rejected for this task because it makes her authoritative; it
   is your call if her role is meant to harden later.
4. **N's model** has inward-facing eyeballs, worked around in the look; turning them in the
   source is a one-line fix for her next model revision. It still has its 16-joint rig, no face morphs (no blink, no expression) and
   a helmet-like bob mesh. Its stripes are now hidden by one hair tone. A remodel, if
   wanted, is a separate task.
5. **Hands.** Q's mitten-like hands and N's simplified hands are unchanged.
6. The seated classroom student was out of scope in that integration. The later requested
   surface refinement below includes it; its model and seated placement remain unchanged.

## 8. N and the seated student's surface refinement (2026-11-18)

**Scope/status.** Implemented material proposal against base `42b25b29adc53bfb36d2c6f5be7fcf4ee948b6b6`,
not owner visual approval. This is not the retired issue #188 overlay experiment. The two
production looks already use the painted pipeline. Their roughness is visual coarseness,
not a request for lower PBR roughness or glossy skin: coarse pigment/contour, generic hair
hatching and little separation between fabric types. N has no UVs; the student's main
clothing surfaces also have none. Upscaling a bitmap cannot add detail to them.

### Implementation and boundaries

- The existing `character_paint.gdshaderinc` gains opt-in `pigment_blend` (continuous glaze
  between pigment steps), `patch_feather`, and `detail_kind/strength/scale/tint/origin`.
  Kind 1 is fine V-shaped knit, 2 is woven twill, 3 is curved angular hair flow. Detail
  changes diffuse colour only: roughness stays 1, metallic/specular stay 0, with no extra
  normal, texture sample, geometry, pass or material slot.
- Clothing uses triplanar projections of the existing rest coordinates. Projection weights
  come from rest-position derivatives, not a posed/view normal; moving a shoulder must not
  rotate the weave on the garment. Thread contrast fades with `fwidth` before it becomes
  sub-pixel. This is an anti-aliasing measure, not a measured FPS improvement.
- `refined_teacher()` keeps N's sage cardigan, cream blouse and dark trousers: quieter
  broad chalk, finer knit/twill, curved brown hair strands, lower-contrast facial pigment
  and feathered glazes. `refined_student()` retains plum/cream/navy, quiets the harsh
  light/shadow skin inserts and under-eyes, and assigns knit/twill/hair by material role.
  Their outline is 5.5 mm with less wobble; fingers, facial inserts and small garment
  pieces still have no individual hull.
- Defaults are off. Only those two shipped looks opt in, before `room_keyed()`; protagonist,
  Q and the retained woodcut/paper experiments are not restyled. Regenerate with
  `python3 art/characters/build_character_looks.py`; `--check` detects drift. Do not edit
  the generated `.tres` files by hand.
- No GLB, normal, skin weight, skeleton, animation, blend shape, wrapper transform,
  collision, interaction, dialogue or portrait changes. N's six inward-facing eye surfaces
  still use the existing two-sided shader; this does not repair the source model or add
  facial expressions. The student's modelled angular features remain model geometry.

**Surface provenance.** The updated existing `.tres` resources are deterministic output
of the in-repo Python palette table; the shader is first-party code authored with Arena
coding assistance. No downloaded/traced/image-generated artwork or new runtime asset is
added. The model rights remain exactly those in `ASSET_PROVENANCE.md`; these parameter
changes do not establish rights in any other model or portrait. That shared ledger is
left untouched to avoid overlap with the concurrent environment-art PR #245.

### Reproducible comparison and regression coverage

`capture_character_integration.gd` now includes the real `Actors/SeatedStudent` without
standing it up: face/front-three-quarter, cloth, its own desk/chair, and gameplay-distance
frames. N gains a cloth close-up. `baseline` is explicitly different from the historical
`before`: it loads **n.tres and student.tres from this change's base** using
`--baseline-dir`; omitting the directory or a resource fails rather than substituting an
older/raw look. `--freeze-pose` fixes the bound idle/sit pose and blink for material A/Bs.
Do not use it to claim motion validation.

```sh
baseline="$(mktemp -d)"
base=42b25b29adc53bfb36d2c6f5be7fcf4ee948b6b6
git show "$base:assets/characters/teacher_n/teacher_n_look.tres" > "$baseline/n.tres"
git show "$base:assets/characters/classroom_student/student_look.tres" > "$baseline/student.tres"
for group in n student; do
  xvfb-run -a --server-args="-screen 0 1600x900x24" \
    godot --path . --resolution 1600x900 --rendering-driver opengl3 \
    --script res://tests/capture_character_integration.gd -- \
    --group="$group" --variants=baseline,after --baseline-dir="$baseline" --freeze-pose
done
```

The capture workflow's `refinement-n` and `refinement-student` jobs extract these looks
from the **actual PR base SHA**, record that SHA, and publish two-column sheets (left base,
right current) plus full-size artifacts. On manual dispatch, the baseline is the dispatched
revision itself; it is not evidence of a historical improvement. All columns share scene,
light, camera and pose; the base uses the current shader with its new options disabled.

`tests/imported_assets_test.gd` additionally pins the fine-detail material roles and
restrained strengths, keeps it off skin/eyes and all protagonist/Q parts, and checks their
glaze options remain off. Its existing geometry/rest-coordinate, reversible-treatment,
seated-wrapper and six two-sided-eye contracts remain in force. Exact run results and
remaining environment warnings belong in the PR, not an assumed visual pass here.

**Owner checklist:** compare face and hair in sun/shade; inspect both fabric close-ups;
check N at the lectern and the student in the actual chair; move/zoom the gameplay camera
for shimmer and silhouette readability; run the normal (unfrozen) idle, walk and sit paths
for swimming detail. Forward+ on the target GPU and Windows performance still need target
hardware verification; software/OpenGL captures are not that verification.
