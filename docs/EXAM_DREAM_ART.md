# Exam dream art (experimental layer)

> **Status:** experimental (2026-11-20; stink stable 2026-11-11, round 10). Owner art review pending.
> **Owner:** implementation PR author.
> **Source:** `tools/build_dream_annex.py`, the shader-driven `tools/dream_figures.py`, and
> `tools/exam_crowd.py` / `tools/exam_crowd_forms.py` for the 03 crowd;
> `tools/exam_hall_heads.py` sculpts the seven figures outside the exam rooms and
> shares its facial mesh forms with the mature heads in `tools/ticket_clerks.py`;
> `tools/dream_stable.py` / `tools/stable_meshes.py` build the stink stable behind 01.

This pass restyles the teaching block from a dream fragment the owner supplied: an exam
in another school, with a waiting room in that school's teachers' office. You reach the
building through a horse or chicken shed (1F), pay at a ticket counter (2F) and ride a
metro-style escalator up to an empty exam floor. The building has a single doorway at its
south-west corner, and you keep missing it. Old women dry grain and quilts in front of it.
The stable smell is everywhere.

The pass overlays the building without moving an existing wall, exit or spawn. The
counter now sits inside and to the right of the 01 glass door. The clerks and the
03 crowd use native animation on shaped, vertex-painted figures. The stink stable
uses vertex-painted meshes; the stair, chairs and other yard pieces use primitives
and shader motion. `DreamAnnex` itself still has no scripts, actors, sound or new
textures. The three clerk looks and the stench filter are staged in the corridor.

## What is where

| Place | Dream element | How it is drawn |
|---|---|---|
| 02 -> 03 west stair | Subway-scale escalator "toward an invisible direction". **The steps run down**: anyone climbing is walking up a down escalator, the "hidden slide back" of the closing feeling. | `dream_escalator.gdshader` paints a moving step belt over the existing treads. The player still walks on the teaching block's ramp collider. Steel skirts, rubber handrails, comb plates, a light-bar canopy and a metro totem reading `03 / EXAM ↑`. |
| 01, inside and to the right of the glass entrance | A ticket counter with three silent, metronomic attendants. Seen closer, they are middle-aged women in school staff uniforms. | Open petrol-blue counter with the original `EXAM FEE · TICKETS` sign. One clip drops all three stamps together onto their slips. Point at a face or jacket and click for a short front three-quarter view of that clerk. The old 02 spot is clear. |
| 03 corridor (west run and north turn) | Empty corridor; paper on every door says EXAM ROOM; inside, messy desks "finished or not yet started". | A taped paper notice on every bay door, with exam-room numbers that disagree (`07`, `07`, `13`, `00` …). Dropped papers and a tipped chair sit behind the high slit. A seating plan is painted on the corridor floor, slightly off-square. Hard vermilion, cobalt and lemon colour fields cover the walls, with a red floor rule leading to the office. |
| 03 toward the staff office | In the gaps along the glass: a brief conversation, then two candidates absorbed in exam prep. | A varsity-jacket speaker gestures palm-up; a shorter student in a pleated skirt nods back. Further along, a hooded reader traces a page with a pencil while a student in a long coat checks an admission slip. The backward footprints, turned chairs and `NOW SERVING — — —` screen stay in place. |
| 03 west wall | The troublemaker and accomplice by the damaged plaster. | `Troublemaker/Ranter` pauses between sharp forearm movements toward the dents. `Accomplice` leans in with an open hand. No dialogue or reaction to the player. |
| Staff office (`WaitingRoom`) | Chairs turning away; a small conversation and a quiet study corner. | One person offers a held snack pouch. Opposite the group, a reader and a student with a slip wait beside the south wall; the reader has a low stool. The rota, trays and key-board inspections are unchanged. |
| Behind 01, west of the glass entrance | The approach "through the horse shed"; circling the village to the inconspicuous doorway; grain and quilts that block the view; the smell. | A walkable **stable yard** opens off the forecourt's west side: an earth lane and a yard with dung and straw, low mud walls, and village houses beyond. Its centre is a two-storey **DreamHouse**. 1F is three open stalls with two grazing horses. 2F is one lit slice of window where three silhouettes stamp in step under a `TICKETS · EXAM 2F →` sign. The only door is a small dark opening at the **south-west corner**, numbered `1`, behind a line of quilts. Old women squat and rake grain mats. There are hens and a coop. Since round 10 the stalls and the heap are the **stink stable** (next section). |
| Above the DreamHouse roof | "A crowd that is never seen outside suddenly gathers, then vanishes up the escalator", heads bowed, their voices fading smoothly. | An outdoor glass escalator leaves the roof and stops in mid-air at a black void in a lit frame. Seven bowed riders loop up it (`travel`) and dither out at both ends (`fade_edge`), which is how they vanish. |

The metro pictogram at the lane's mouth (a horse and an arrow) is the one modern sign in
the village.

## The stink stable (round 10, 2026-11-11)

The owner asked for the stable left of the 01 entrance to be refined and pushed toward the
absurd and psychedelic, *as if the smell of the dung knocked you out*, in the postmodern
manner of the visual experiments (#196's colour fields and paper cut-outs, #200's ink hulls
and cut paper). Everything below is generated by `tools/dream_stable.py` from the meshes in
`tools/stable_meshes.py`, and each mesh is its own text ArrayMesh in
`scenes/locations/corridor/stable_meshes/` (the annex scene is too close to the 1 MiB
scene budget to embed them).

| Piece | What it is | How it is drawn |
|---|---|---|
| `DreamHouse/BayHorse`, `GreyHorse` | Two horses with their heads over the half doors. The bay grazes slowly; the grey one is dazed, its head bobbing, a spiral and stars turning over it (`DazeHalo`). | Lofted barrel, neck and head, muscled legs, hooves, ears, eyes and nostrils, a cut-paper mane and tail. `stable_paint.gdshader`: flat colour fields, a two-step terminator, a second fixed *painted light* that splits each form into a lit and a hatched shade field, and a bilious yellow-green cast. `stable_ink.gdshader` as `material_overlay` draws the contour (#200's ink hull). |
| `DreamHouse/HorseShadow` | The empty middle stall has a horse's ink shadow painted on its back wall - a horse that is not there - with acid-green and mustard stains. | Cut-out slab in ink; `stench_paper.gdshader` stains. |
| `DreamHouse/StallBedding`, `StableYard/Straw0`-`3` | Bedding in the stalls and loose straw over the yard and lane, some of it trodden into muck. | One mesh of creased straw ribbons per area. |
| `StableYard/Dung*`, `Heap/Muck` | Droppings of heaped balls with undigested straw, and a lumpy muck heap bristling with straw, a pitchfork stuck in it and a sickly green lamp over it (`HeapGlow`). | `stable_paint` with **`gloss`**: a hard cream cartoon highlight (see the exception below). The heap has an ink contour. |
| `StableYard/Flies0`-`5`, `GiantFly` | Swarms over the heap, the stall fronts and the droppings (220 flies), and one fly the size of a dog circling the heap. | `stench_flies.gdshader`: each instance loops its own knot (`INSTANCE_ID`); wings (vertex alpha below 0.1) flap and are drawn as dithered film. The giant fly orbits facing its way. |
| `StableYard/Stink0`-`4`, `Stain0`-`6`, `Smell0`-`11` | Cartoon stink clouds cut out of acid, mustard and bile paper, rising off the heap, the stalls and the droppings, stalling and dithering away; painted puddles of smell on the ground; the old smell ribbons, thicker and greener. | `stench_paper.gdshader` (unshaded paper with its own tooth) and `dream_odor.gdshader`. |
| `StableYard/DazeHaloOldWoman` | The old woman on her stool has been knocked out by it too. | The same spiral and stars. |
| `StenchHaze` (in `corridor.tscn`) | **The smell made visible.** As the protagonist walks toward the stalls the screen turns yellow-green: the air wobbles, the frame doubles and swoons, colours print as an olive/bile/acid/mustard riso, stink contours and halftone dots crowd the margins and the corners fall into a breathing olive dark. Walking away clears it. | `stench_haze.gdshader` on a full-screen sheet in a `world_filter` CanvasLayer at layer -3 (under the concussion paste-up, the outline and the UI). `stench_haze.gd` eases `stench` from the protagonist's distance to the stall fronts and the heap: full within 2.4 m, nothing past 9.5 m or on another floor. Hidden at 0. |

**Motion in vertex alpha.** The shaped meshes carry RGBA8 vertex colour: RGB is the painted
field, alpha a motion weight. 0.5 is still; 0.5 -> 1 is the share of the graze turn about the
neck pivot; 0.5 -> 0 the share of the tail swish; below 0.1 a fly's wing. Rates, amplitudes
and phases are material values, so a whole animal moves without a skeleton, a script or an
instance uniform, and its ink contour moves with it.

## Style rules of this layer

- **Modern against municipal.** The exam floor uses hard colour fields, steel and rubber,
  and black-and-white wayfinding. It reads as a metro station or a test centre and
  contrasts with the indigo-and-lavender 03 ledger underneath. The yard uses earth, lime,
  timber and saturated quilt prints. The dressing stays matte: toon diffuse for the
  boxes and wrapped diffuse on 03's rounded people, with no specular.
  **The one exception is fresh dung**, which carries a hard cartoon highlight
  (`stable_paint` `gloss`): a cut-out cream shape from the painted light, not a specular
  lobe, so the droppings read wet from across the yard. Nothing else in the dream shines.
- **Repetition is the absurdity.** The three clerks share one exact stamp clock; they do
  not turn, speak or interrupt it when approached. Half the door numbers say `07`. The
  footprints reverse. The escalator runs down under people walking up.
- **03 moves at a different rhythm.** Twelve candidates vary in shoe-to-head height,
  shoulder width, dress, hairline and stance. Rounded, tapered profiles and cloth/skin
  pigment planes hold up at walking distance. Collars, cuffs, pleats, glasses and laced
  shoes are secondary to the silhouettes. Each moving form uses one opaque painted
  surface, with indexed vertices on curved forms to keep the scene size down.
  `AnimationPlayer` drives torso, head and forearm poses, with anchored shoes
  and a prop attached to the same joint as its gripping hand; no runtime code or dialogue.
- **Motion without behaviour, elsewhere.** A vertex offset or a turn about a shared pivot
  in `dream_motion.gdshader` moves unrotated box assemblies as one piece. The builder
  stores phases and pivots in material variants, not per-instance uniforms, so a corridor
  reload won't exhaust Compatibility's shared slots. Fades are dithered, not alpha.
- **No resolution.** No new text, dialogue, flag or exit. The doorway and the sky
  escalator lead nowhere.

## Build and check

- `python3 tools/build_teaching_block.py` writes `scenes/locations/corridor/dream_annex.tscn`
  with the teaching block. `--check` detects stale output. `corridor.tscn` instances
  it as `DreamAnnex` beside `TeachingBlock` (not under `StageArt`, whose stage-material
  rule this layer's ShaderMaterials would break). The forecourt's west guard rail is gone,
  so the lane joins the apron.
- `python3 tools/build_school_rooms.py` adds `WaitingRoom` to the staff office through
  `build_dream_annex.waiting_room()`.
- `godot --headless --path . --script res://tests/dream_annex_test.gd` checks:
  - every piece has a material and a shader;
  - nothing under the annex carries a script or is an actor, interactable or sound;
  - the yard, the strip by the corner doorway and the lane bake into the corridor's
    navigation and can be reached from the glass entrance;
  - the stair under the escalator still climbs 02 -> 03 directly, and the 01 gallery stays
    walkable;
  - no annex collider crowds a spawn marker; the counter stays to the right of the clear doorway;
  - the 01 clerks bend only their stamp arms, with planted feet and two simultaneous paper contacts;
  - the exam-floor and office vignettes add no collider;
  - the crowd keeps its varied heights, native posed joints, planted shoes and held props;
  - `StenchHaze` is a world filter under the outline, hidden with nobody near, full at the
    muck heap, strong in the yard, and nothing at the glass entrance, the 01 gallery or on 02;
    a stand-in protagonist at the heap brings it up.

  `corridor_art_test.gd`, `location_art_test.gd` and `school_rooms_test.gd` keep their
  contracts unchanged.
- The `Location art capture` workflow's `dream_annex (after)` job runs
  `tests/capture_locations.gd -- dream-annex`. It keeps three gameplay stances (the one by
  the muck heap shows the stench filter) and eight overviews (two of the stink stable),
  adding six timed review frames: the conversation, booklet and pencil
  at two points of the revision loop, plaster pair, waiting-room conversation, and
  seated reader. A separate ticket visit job renders one entrance frame and three face
  shots from actual clicks. For a manual 03 pass, climb the west stair from 02, turn along
  03 past the glass and watch each group for a full loop (about eight seconds). Continue to the
  staff office and check that the study stool stays out of the entrance and inspection routes.

## Looking at the ticket clerks on 01

Walk through the 01 glass door and turn right along the inside face. The counter sits
outside the clear span of the opening, with the through lane to the stair on its front
side. A click on a clerk uses the normal pointer approach; it does not pull the camera
while hovering or while the player is still walking up. There are three separate look
targets. Each uses the original camera with a head-relative insert and eases back after
roughly three seconds. No dialogue, interaction with a fee, objective, record or save is
started. The lower lids, cheek shapes, warmer skin tones, greying hair and matching
pressed collars are in the mesh, not an overlay on the shot. The silhouettes in the
stable-yard house remain the old set dressing.

`godot --headless --path . --script res://tests/ticket_counter_test.gd` walks from the
real spawn through the threshold, sends mouse events at all three faces, checks that
the same camera frames their eyes and hair, then checks the facing interaction and walks
on after controls return. Append `-- --mobile-preview` to exercise the touch path instead.
With a window, `-- capture=<dir>` saves the approach and three clicked close-ups.
The booth sits slightly inside the wall line. The clerk heads clear the lintel in the
follow camera on turning right, while the east end leaves the original gallery lane
open to the blue stair. To review the full-size frames without the artifact
store, dispatch `location-art-capture.yml` with `relay_ticket_evidence=true`, then
`python3 tools/dialogue_evidence_relay.py fetch --run <id> --out build/ticket-frames`.
The relay checks the commit and each JPEG's hash; the images stay out of Git.

## The seven 03 corridor sculpts

This is the model-only pass on `ExamFloor/{Clique0,Clique1,Troublemaker}`. Shoulder,
waist, trouser and shoe profiles are cut separately, and the eyes, continuous nasal
bridge, mouth and jaw have depth in the mesh. Trim follows the cloth triangles so the
plackets and pockets do not slice through the surface. Hand tips are shaped on the
open gestures; the original grips and their paper, booklet and pencil stay attached.

| Figure | Standout model details | Rest height to crown |
|---|---|---:|
| `Clique0/Person0` | Swept ponytail, round chin, knit top, pleated skirt, low flats | 1.53 m |
| `Clique0/Person1` | Tapered crop, squared jaw, broad varsity jacket and trainers | 1.84 m |
| `Clique0/Person2` | Neat part, narrow bridge and wire glasses, short-sleeved button-up and loafers | 1.68 m |
| `Clique1/Person0` | Cheek-length bob, full cheeks, dropped-hood sweatshirt, loose trousers | 1.61 m |
| `Clique1/Person1` | Low knot, narrow chin, long layered coat, boots | 1.76 m |
| `Troublemaker/Ranter` | Lifted asymmetric quiff, crooked nasal profile, striped windbreaker | 1.75 m |
| `Troublemaker/Accomplice` | Short layered cut, straight brow, roomier cuffed work shirt | 1.59 m |

Rebuild with `python3 tools/build_teaching_block.py`, then run it with `--check`.
That 03 pass added no character and did not change a pose key, pivot, spawn, prop or
dialogue. This 01 clerk round does not change the 03 or waiting-room meshes. Each
candidate still fits the 2,100-triangle limit (including props) and uses the same
five to seven painted meshes. In `dream_annex_test.gd` the width and depth of each
head, measured relative to its height, also distinguish the seven silhouettes.

## Known limits

- The escalator belt paints over the treads. Its steps do not carry the player.
- The stench filter is art only: no flag, save or gameplay effect. The horses' heads and the
  flies move in the vertex shader, so their meshes carry a `custom_aabb` wide enough for it.
- Shader motion is per mesh, so a turned chair keeps its pivot only because its parts are
  unrotated boxes. Do not add rotated parts to a shader-driven assembly.
- The 03 and stable-yard crowds are noninteractive. The three 01 looks are camera staging,
  not conversations or a transaction. The fixed overview capture views are review frames;
  the separate ticket click captures use the gameplay camera.
