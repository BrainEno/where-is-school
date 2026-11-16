# Biology classroom: an art rework experiment

- **Status:** Experiment. Development-only and never exported (every export preset excludes `scenes/dev/*`). Nothing in the game uses it, and it changes no production scene, script, shader, dialogue or setting.
- **Scene:** `scenes/dev/visual_experiments/biology_classroom/biology_classroom.tscn`. Open it in the editor and press **F6**.
- **Check:** `tests/biology_classroom_experiment_test.gd` (Godot CI, step `biology_classroom_experiment`, under Xvfb so the shaders are compiled)
- **Evidence:** `docs/screenshots/visual_experiments/biology_classroom/`, written by `tests/capture_biology_classroom.gd` through the workflow `.github/workflows/biology-classroom-capture.yml`
- **Builds on:** the visual experiments lab (PR #196, [VISUAL_EXPERIMENTS.md](VISUAL_EXPERIMENTS.md)). It reuses the lab's `collage_kit.gd` (paper and colour-field helpers) and its medium switch's technique. Since round 2 it has its own camera-less visitor (`visitor.gd`) and fixed camera (`fixed_camera.gd`) instead of the lab's following `observer.gd`. It changes none of the lab's files.
- **Round 2 (owner feedback on PR #200):** see [§0](#0-round-2-what-changed) below. The atmosphere, the notebook dialogue strip, the mixed media and the curtain/paper/fall are kept as approved.

This is a proposal for how the biology classroom could look. It is not a fix to the production room. The owner decides whether anything from it goes further.

## 0. Round 2: what changed

| Owner's point | What was done |
|---|---|
| **Camera: fixed composition, no follow** | `ShotCamera` (`fixed_camera.gd`) is a root-level camera with one 60° lens. It is never parented to the character and never tracks, pans, rolls, shakes or zooms. The room is covered by a few **fixed shots chosen by zone** (`SHOTS`: classroom, east, rear, curtain, lectern, seated, corridor ×2, yard ×2). Each zone has a slightly wider *hold* area, so the shot does not flip back and forth on a boundary. The camera moves only when the zone changes, or on a story beat: sitting down or standing up, the lectern close-up, **N's entrance at the bell**, the landing after the fall, and an authored `look_from`. It glides (1.6 s, smootherstep) only between nearby, similar angles; reverse angles and changes of space are a short dip-to-dark cut. The keys are read relative to the shot on screen, and a held key keeps its direction across a cut. The fall no longer rolls the camera. The player's movement is not restricted. Every place he can stand is inside its shot's frame: the test checks a margin of ≥ 0.04 at about 250 points, and the planning sweep found a worst margin of 0.20. |
| **Closed room** | Four full-height walls and a ceiling, colliders to the ceiling. The **drawn fourth wall is gone**. The only opening to the outside is the curtained west opening (the curtain, the blank sheet, the paper medium and the fall, unchanged). The front window is a painted view, and the doors are doors. The test casts over a thousand lines of sight from three points in the room to points beyond every wall and the ceiling. None gets out, except through the curtained opening. |
| **Projector** | A ceiling projector on a plumb rod in front of the board, in line with it, tipped down at the front wall. Its beam lands on a half-lowered screen, and the picture spills onto the blackboard below (a collage of two media). The cable runs along the ceiling and down the front wall to a switch on the lectern. It is on in beats 2–3 and on standby (amber pilot light) otherwise. `set_projector(on)` and `set_projection(texture)` are hooks for later story or medium use. |
| **Concrete floor** | `concrete.gdshader`: cast concrete, not a grey texture. Aggregate in two tones, pores, cloudy mottling drifting warm and cool, grain, saw-cut joints. Faint ruled lines and a red margin are *cast into* the floor (the answer sheet again). Platform: darker, the same mix. |
| **Concrete lectern** | The same high lectern in the same place (window end, on the platform, 1.3 m, set square, register, red pencil, chalk, pointer), now board-formed concrete (formwork lines), related to the floor but not the same. |
| **Cut-paper class** | `classmates.gd` and `cut_paper.gdshader`: each pupil is one mesh of cut pieces, with no card or board behind them. Torso (some folded into a V), collar layer, head, ear, hair, arms as strips folded at the elbow. Seven papers: dyed, kraft, newsprint, graph, sugar, magazine, pencil. Torn or cut edges, thickness (6–12 mm) with the paper's pale core showing as a sliver round the cut, and the reverse dyed through (the same colour, flatter and a touch darker, so from the board no pupil is a white card). Poses: upright, turned round, asleep, ponytail, elbow, hand up, and one pupil standing at the back wall's class board pinning up a sheet. |
| Dialogue | Unchanged (the notebook strip). The HUD shows the current shot. |

## 1. Concept: a room remembered, not a room lit

The production classroom is a believable room. This one is the same room as the protagonist has it: a cold, dazed boy at his desk, trying to remember who Q is. The room knows more than he does.

- **Painted, not rendered.** Every wall is a flat colour field with a hard light/shadow step (`room_tone.gdshader`) and a pen contour (`ink_hull.gdshader`, an inverted hull, plus pen lines at the inside corners and frames). The floor, platform and lectern are cast concrete (`concrete.gdshader`), the one heavy material in a paper room. The picture is closer to a gouache illustration than to a game level.
- **A closed room** (round 2). Four walls and a ceiling; the outside is only behind the curtain. (Round 1 had a drawn fourth wall; the owner asked for the room to be closed.)
- **Absences are ink marks** (`ink_mark.gdshader`). What is missing is drawn, not modelled:
  - *B* is not in the room. Her **shadow** is: a figure nobody casts, with a set square raised, climbing the front wall beside the lectern.
  - Her **set square** lies on the lectern, taped across a crack. Its **shadow** runs the length of the floor, from the platform to the protagonist's desk.
  - The **zero** from last term is a red pencil ring.
  - The **missing textbook** is a dashed outline that fades in on his desk when he searches for it.
  - Faint **chalk ghosts** of old lessons stay on the board.
- **Three registers, driven by the story and the player:**
  - `chill`: the impression of B. Ink blue floods the colour fields, the shadow climbs, the lectern stands taller than it is, and the set square's shadow crosses the floor. A wedge cuts into the dialogue strip. It depends on the beat and on how close he stands to the lectern. It is strongest in the lesson beat, weak elsewhere, and nearly gone after the bell.
  - `dull`: the bell. Fluorescent tubes catch with a flicker and drain the colour to grey-green. N's lesson is no lesson.
  - `focus`: waking. Seated at the start, the room beyond the next desk sinks into the dark.

### The curtain: the picture becomes the blank exam paper

The production mechanism stays: draw the curtain, lean out, fall, land in the yard. What changes is what is behind it, and what that does to the picture.

Behind the curtain is not a window but a **blank white sheet**. Drawing the curtain turns the whole picture into a **pencil drawing on an answer sheet**: blue rules, a red margin and graphite hatching. The change spreads from the window as a torn edge (`blank_paper.gdshader`, a SubViewport filter like the lab's medium switch). Only red survives the change. A red pencil then draws a ring round where he stands: the zero, around him. Walk away from the window and the colour comes back. Walk back and the paper returns.

Leaning out uses the existing fall. The blank gives way, the paper lifts, and he drops into full colour in the yard one floor down. There he gets up, below the white rectangle that is now set into the face of the building. The stairs by the yard door lead back up to the corridor.

The blank paper is the strongest image in the story's opening (*last term's blank paper, the zero, B*). Here it is not an object in the room but a *medium* the room falls into. You can stand in it and walk around in it.

### The set

| Required | Done |
|---|---|
| Remove the low teacher's desk | There is none. The test fails if any node or instance looks like one. |
| A real high lectern where it stood, left, by the window | Stands on the platform at (−4.7, −2.55): 0.35 m from where the production room's low desk stood, beside the front window. The top is 1.3 m high (desks are 0.76 m). Since round 2 it is board-formed concrete, related to the floor but not the same, with a projector switch beside the register. |
| The set square and B's other things on it | Set square (taped), register and red pencil, chalk box. The pointer leans on its side. |
| Other main objects in working positions | Board on the north wall facing the class; clock, wing chart and cell chart on the north wall; curtain over the west opening; front door in the east wall at the front, opening outward; rear door shut; 4 × 3 desks with 2 m aisles and 1.1 m clear before the platform; Q's desk beside the curtain; the protagonist's desk in the second row with his bag on the hook. |

### Q

Q is an independent walker (`q_presence.gd`), not a follower:

- Every change of place is **walked** at 1.45 m/s along routes through the aisles. The test measures his largest single-frame step: there is no teleport anywhere, including to the fall's landing.
- When the protagonist goes out of the door, Q **walks to the doorway and stops on the classroom side**. He is clamped short of the wall line. When the protagonist comes back in, Q walks back.
- When the curtain opens he walks over to the window. He does not come down to the yard.
- After the bell he goes to his seat.
- `Policy { STAYS_INSIDE, INVITED, REFUSES }` is in place for invite/decline, being sent back, refusing, and chase/hide. Only `STAYS_INSIDE` is used: the story decides the rest.

### Beats (stage notes only; no lines are written)

1. **Waking.** Seated, slumped, in the dark (`focus`). Talk to Q.
2. **Biology lesson.** The impression of B. Talking to Q moves the story on.
3. **No textbook.** Search the desk and bag. The book's outline appears, and the bell follows. Or go out of the door: the corridor is open, with the stairs down to the yard and the neighbouring class's door.
4. **Bell and N.** Tubes flicker on, and the clock moves from 10:52 to 11:00. N walks in from the stair head, opens the door, and stands on the platform *beside* the lectern, not at it. Asking N about B gets a vague answer. It is free activity: stay, or go.

The dialogue strip at the bottom shows *where* lines would sit and how B presses on them. It carries bracketed stage notes (［占位］), never script.

## 2. References (open, not a spec)

- *Memory Collage Expressionism* (the owner's reference): taken as a direction (memory edits the room), not as objects to place.
- **PR #196** (the visual lab): its paper cut-outs (classmates, trees, washing), colour fields, medium switch and walk-in stage logic are absorbed here into one room.
- German Expressionist film sets (painted light and shadow, a shadow that acts without a body) and illustrated children's books with an open fourth wall. Both were used only as principles; no imagery was copied.
- School answer sheets: ruled paper, red margin, red pencil marking. These are the only "realistic" texture, and they arrive as the medium.

## 3. Method (Godot 4.7, all renderers)

| Piece | How |
|---|---|
| Colour fields | `SurfaceTool` geometry with per-vertex colour; `room_tone.gdshader` (toon step, chill/dull/focus uniforms). Generated at load. |
| Contours | `ink_hull.gdshader` as `material_overlay`: front-face-culled hull pushed out along normals |
| Marks | `ink_mark.gdshader`, unshaded alpha on quads; `amount` reveals (0 rise, 1 radial, 2 fade); textures drawn procedurally in `room_art.gd` |
| Paper medium | `paper_switch.gd`: a SubViewport at 0.6 scale shares the world, and a CanvasItem filter (`blank_paper.gdshader`) draws edges, hatching, rules and margin, keeping strong reds. The root viewport's 3D is switched off while it shows, so the frame is not drawn twice, and restored on exit. |
| Concrete | `concrete.gdshader`: world-space value noise and cells (aggregate, pores, mottling, joints, ruled lines, formwork) with the room's light step and registers |
| Classmates | `classmates.gd` paints one 256² sheet per pupil (seven paper types) and builds one mesh of cut pieces; `cut_paper.gdshader` cuts by alpha scissor and shows the reverse and the core |
| Characters | Production protagonist, Q and N scenes, instanced read-only; `visitor.gd` (a body without a camera) |
| Camera | `fixed_camera.gd` (one lens; glides or cuts when told to) and the director in `biology_classroom.gd` (`SHOTS`, zones with enter/hold areas, `frame_margin`, `_direct`, `_dip_cut`) |
| Collision | Box colliders built with the geometry, full height to the ceiling; ramps onto the platform |

No imported textures, no new assets, and no changes to `project.godot`.

## 4. Running it

Open `biology_classroom.tscn`, press **F6**.

| Key | |
|---|---|
| WASD / arrows | walk, relative to the shot on screen (a held key keeps its direction across a cut); Shift faster. Any movement key stands him up from his desk. The camera is not player-controlled. |
| Space / Enter | interact: talk to Q or N, look at the lectern, search the desk, sit, draw the curtain / lean out, open/close the door, stairs, the neighbouring door |
| 1–4 | jump to a beat · **0** start over · **M** paper on/off · **H** hide the HUD · **P** print a performance sample |

## 5. Evidence

### Round 2

The frames were rendered by the engine on GitHub's runners (llvmpipe / lavapipe software rasterisers, 1600×900, saved at 800 px wide). They come from run [`43839431982`](https://github.com/BrainEno/where-is-school/actions/runs/43839431982) of `biology-classroom-capture.yml`, on commit `677feea`, and were decoded from that run's annotations without retouching. They are in `docs/screenshots/visual_experiments/biology_classroom/<renderer>/`. Every frame is the fixed shot the room gives for where he stands, except four detail frames marked *authored*: the kind of `look_from` shot a story beat would ask for. The capture prints the camera's position and direction for each frame (`BIOLOGY_CLASSROOM_SHOT`).

| Frame (Compatibility) | Shows |
|---|---|
| [`00_overview`](screenshots/visual_experiments/biology_classroom/compatibility/00_overview.jpg) | **Whole classroom**, the classroom shot (from the rear door corner): closed walls and ceiling, the concrete floor, the projector over the front with its picture, the high lectern at the window end, the class, the curtain the only opening. |
| [`01_projector`](screenshots/visual_experiments/biology_classroom/compatibility/01_projector.jpg) | **Projector and teaching area** (authored): rod and body in front of the board, the beam, the half-lowered screen with the picture spilling onto the board, the clock, the lectern by the window. |
| [`02_floor_lectern`](screenshots/visual_experiments/biology_classroom/compatibility/02_floor_lectern.jpg) | **Floor and lectern** (authored): aggregate, pores and warm/cool drift in the floor; the board-formed concrete lectern on the platform with B's things; the projector cable on the platform. |
| [`03_classmates`](screenshots/visual_experiments/biology_classroom/compatibility/03_classmates.jpg) | **Cut-paper class close up** (authored): layered pieces, papers, edges and thickness. |
| [`15_classmates_front`](screenshots/visual_experiments/biology_classroom/compatibility/15_classmates_front.jpg) | **The class from the board** (authored), the side the lectern sees: each piece's reverse is its own paper dyed through, flatter and darker, with no white card behind anyone. |
| [`04_waking`](screenshots/visual_experiments/biology_classroom/compatibility/04_waking.jpg) | Beat 1, the seated shot. |
| [`05_lesson_b`](screenshots/visual_experiments/biology_classroom/compatibility/05_lesson_b.jpg) | Beat 2, the lectern zone's shot: the impression of B. |
| [`06_curtain_closed`](screenshots/visual_experiments/biology_classroom/compatibility/06_curtain_closed.jpg) · [`07_curtain_tearing`](screenshots/visual_experiments/biology_classroom/compatibility/07_curtain_tearing.jpg) · [`08_curtain_paper`](screenshots/visual_experiments/biology_classroom/compatibility/08_curtain_paper.jpg) · [`09_yard_landing`](screenshots/visual_experiments/biology_classroom/compatibility/09_yard_landing.jpg) | **The curtain** in the curtain zone's shot: closed (the one non-wall), tearing into the answer sheet, on paper with the red ring, then the fall and the yard's shot. |
| [`10_walk_start`](screenshots/visual_experiments/biology_classroom/compatibility/10_walk_start.jpg) → [`11_walk_moved`](screenshots/visual_experiments/biology_classroom/compatibility/11_walk_moved.jpg) | **Fixed camera at runtime:** D then W held. He walks from (−0.4, 0, 0.4) up onto the platform at (−0.5, 0.15, −2.5); the camera stays at (6.6, 2.85, 4.65) with the same direction. The frames differ only where he is. |
| [`12_walk_east`](screenshots/visual_experiments/biology_classroom/compatibility/12_walk_east.jpg) | Walking on into the east side: one cut to that zone's shot (from the window wall), then still. |
| [`13_corridor_q`](screenshots/visual_experiments/biology_classroom/compatibility/13_corridor_q.jpg) · [`14_bell_n`](screenshots/visual_experiments/biology_classroom/compatibility/14_bell_n.jpg) | The corridor's shot with Q at the doorway; beat 4 with N beside the lectern and the projector on standby. |

Forward+: `00_overview`, `02_floor_lectern`, `08_curtain_paper`. Mobile: `00_overview`, `03_classmates`, `08_curtain_paper`.

### Cost (renderer counters, same run as the round-2 frames)

| Frame | Renderer | Draw calls | Primitives | Video memory |
|---|---|---|---|---|
| overview | Compatibility / Forward+ / Mobile | 271 / 271 / 83 | 266 k | 41 / 115 / 88 MiB |
| paper | Compatibility / Forward+ / Mobile | 226 / 226 / 57 | 275 k | 45 / 131 / 94 MiB |
| classmates close up | Compatibility / Mobile | 266 / 69 | 231 k | 41 / 84 MiB |
| class from the board | Compatibility | 166 | 191 k | 41 MiB |
| east shot (busiest) | Compatibility | 418 | 422 k | 41 MiB |

Round 1's overview was 179 draw calls and 193 k primitives. The closed shell, the ceiling, the projector and its beam, and one mesh per pupil with its own material add about 90 draw calls in the Compatibility overview. Video memory is about the same (the pupils' sheets are 256² and cached). Paper mode still costs no extra draw calls, because the root viewport stops drawing 3D while it shows. Frame times on the software rasteriser (100–197 ms) are CPU-bound and only comparable within one run.

## 6. Limitations

- **Placeholder text only.** All dialogue is bracketed stage notes. The response choices are deliberately not written.
- **Q's other policies** (invited, refuses, chase/hide) are names, not behaviour.
- **N** walks a fixed route and has one stage note.
- **The neighbouring class and the textbook loan** stop at a closed door.
- **The paper medium** costs a second scene render at 0.6 scale (with the root's 3D off, the net cost is the filter). It is entered only near the open curtain.
- **Fixed shots are hand-placed.** A new piece of furniture or a new zone needs its shot checked (the test's frame-margin sweep catches a place left out of frame, not a poor composition). First person is not built; the director can take it as one more shot.
- **The projector shows one slide.** `set_projection` exists, but no story use is wired.
- **The cut-paper class is static.** The pupils do not move; from the board they show their reverse: the same paper, flatter and darker, with the back of the head instead of a face.
- **Software rasteriser timings** in the evidence are CPU-bound and only comparable within one run. Draw calls and memory carry over.
- **Generated textures** (about 12.6 MiB uncompressed) are built at load and never written to disk. They could be halved if this went further.
- **No audio.** The bell is a stage note and the tubes' flicker.
