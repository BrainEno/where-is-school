# Biology classroom: an art rework experiment

- **Status:** Experiment. Development-only and never exported (every export preset excludes `scenes/dev/*`). Nothing in the game uses it, and it changes no production scene, script, shader, dialogue or setting.
- **Scene:** `scenes/dev/visual_experiments/biology_classroom/biology_classroom.tscn`. Open it in the editor and press **F6**.
- **Check:** `tests/biology_classroom_experiment_test.gd` (Godot CI, step `biology_classroom_experiment`, under Xvfb so the shaders are compiled)
- **Evidence:** `docs/screenshots/visual_experiments/biology_classroom/`, written by `tests/capture_biology_classroom.gd` through the workflow `.github/workflows/biology-classroom-capture.yml`
- **Builds on:** the visual experiments lab (PR #196, [VISUAL_EXPERIMENTS.md](VISUAL_EXPERIMENTS.md)). It reuses the lab's `observer.gd` (third-person visitor) and `collage_kit.gd` (paper and colour-field helpers), and its medium switch's technique. It changes none of the lab's files.

This is a proposal for how the biology classroom could look. It is not a fix to the production room. The owner decides whether anything from it goes further.

## 1. Concept: a room remembered, not a room lit

The production classroom is a believable room. This one is the same room as the protagonist has it: a cold, dazed boy at his desk, trying to remember who Q is. The room knows more than he does.

- **Painted, not rendered.** Every surface is a flat colour field with a hard light/shadow step (`room_tone.gdshader`) and a pen contour (`ink_hull.gdshader`, an inverted hull). There are no textures on the architecture, and the materials have no gloss. The picture is closer to a gouache illustration than to a game level.
- **The fourth wall is drawn.** The south and east walls stop at the dado (1.1 m). Above that height they are pen lines in the air: their top edges, corners, door frames, and a ghost of the back board. The follow camera can see in from the corner. The room becomes a stage set that is still a room: you walk into those walls, and the doorway is a real doorway. The lines dissolve when they come within a few metres of the lens, so they never cut across a close shot.
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
| A real high lectern where it stood, left, by the window | Stands on the platform at (−4.7, −2.55): 0.35 m from where the production room's low desk stood, beside the front window. The top is 1.3 m high (desks are 0.76 m). It has a cabinet body with one bone-white stripe toward the class. |
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
| Characters | Production protagonist, Q and N scenes, instanced read-only; the lab's visitor controller |
| Collision | Box colliders built with the geometry; the drawn walls collide to dado + 0.15 m; ramps onto the platform |

No imported textures, no new assets, and no changes to `project.godot`.

## 4. Running it

Open `biology_classroom.tscn`, press **F6**.

| Key | |
|---|---|
| WASD / arrows | walk (relative to the camera); Shift faster. Any movement key stands him up from his desk. |
| Q / E, mouse, wheel, R | turn the view, orbit, zoom, reset |
| F | free camera |
| Space / Enter | interact: talk to Q or N, look at the lectern, search the desk, sit, draw the curtain / lean out, open/close the door, stairs, the neighbouring door |
| 1–4 | jump to a beat · **0** start over · **M** paper on/off · **H** hide the HUD · **P** print a performance sample |

## 5. Evidence

The frames were rendered by the engine on GitHub's runners (llvmpipe / lavapipe software rasterisers, 1600×900, saved at 800 px wide). They come from run `43822542942` of `biology-classroom-capture.yml`, on commit `2040f4d`, and were decoded from that run's annotations without retouching. They are in `docs/screenshots/visual_experiments/biology_classroom/<renderer>/`. Each frame is set up through the scene's own public calls (see the capture script's header). Q is put in place instantly in two frames (08 and 09) only, to save the walk; in play he walks there.

| Frame (Compatibility) | Shows |
|---|---|
| [`00_overview`](screenshots/visual_experiments/biology_classroom/compatibility/00_overview.jpg) | **Whole space.** The open corner: drawn south/east walls, platform and tall lectern at the window end, curtain, corridor (right), and the yard one floor down (left). |
| [`01_waking`](screenshots/visual_experiments/biology_classroom/compatibility/01_waking.jpg) | Beat 1: seated, slumped, with Q across the aisle. |
| [`02_lectern_set`](screenshots/visual_experiments/biology_classroom/compatibility/02_lectern_set.jpg) | **The high lectern and the set:** on the platform by the front window, with set square, register, pencil, chalk box and pointer; board, chart and clock behind. |
| [`03_lesson_b`](screenshots/visual_experiments/biology_classroom/compatibility/03_lesson_b.jpg) | Beat 2 near the lectern: ink-blue chill, B's uncast shadow on the wall, the grown lectern, the set square's shadow, and the wedge in the dialogue strip. |
| [`04_curtain_closed`](screenshots/visual_experiments/biology_classroom/compatibility/04_curtain_closed.jpg) | **Curtain, before:** the pleats over the west opening, with Q's desk beside it. |
| [`05_curtain_tearing`](screenshots/visual_experiments/biology_classroom/compatibility/05_curtain_tearing.jpg) | **Curtain, during:** the blank sheet is revealed and the picture tears into a pencil drawing from the window outward. |
| [`06_curtain_paper`](screenshots/visual_experiments/biology_classroom/compatibility/06_curtain_paper.jpg) | **Curtain, after:** the answer-sheet medium. Rules, margin and graphite; only red survives, as the ring around him. |
| [`07_yard_landing`](screenshots/visual_experiments/biology_classroom/compatibility/07_yard_landing.jpg) | After leaning out: back in colour in the yard, below the white opening. |
| [`08_corridor_q`](screenshots/visual_experiments/biology_classroom/compatibility/08_corridor_q.jpg) | Through the front door into the corridor. Q stays at the doorway, inside. |
| [`09_bell_n`](screenshots/visual_experiments/biology_classroom/compatibility/09_bell_n.jpg) | Beat 4: tubes on, colour drained, N beside the lectern, Q in his seat. |

Forward+ and Mobile: `00_overview`, `03_lesson_b` and `06_curtain_paper` in `forward_plus/` and `mobile/`. They match Compatibility; the paper filter and the marks behave the same on all three renderers.

### Cost (renderer counters, same run)

| Frame | Renderer | Draw calls | Primitives | Video memory |
|---|---|---|---|---|
| overview | Compatibility / Forward+ / Mobile | 179 / 179 / 92 | 193 k | 41 / 112 / 84 MiB |
| lesson, B at full | Compatibility / Forward+ / Mobile | 142 / 142 / 40 | 122 k | 41 / 118 / 91 MiB |
| paper | Compatibility / Forward+ / Mobile | 150 / 148 / 40 | 217–224 k | 45 / 131 / 94 MiB |
| yard (busiest) | Compatibility | 238 | 281 k | 45 MiB |

Paper mode adds about 4 MiB (the 0.6-scale SubViewport) and costs no extra draw calls, because the root viewport stops drawing 3D while the paper shows. Frame times on the software rasteriser were 74–157 ms. That is CPU-bound and only comparable within one run.

## 6. Limitations

- **Placeholder text only.** All dialogue is bracketed stage notes. The response choices are deliberately not written.
- **Q's other policies** (invited, refuses, chase/hide) are names, not behaviour.
- **N** walks a fixed route and has one stage note.
- **The neighbouring class and the textbook loan** stop at a closed door.
- **The paper medium** costs a second scene render at 0.6 scale (with the root's 3D off, the net cost is the filter). It is entered only near the open curtain.
- **The drawn walls** depend on the camera staying in the open corner. The free camera can look through them from anywhere, by design.
- **Compatibility renderer:** the sun leaks through where a ceiling would be (there is none, on purpose).
- **Software rasteriser timings** in the evidence are CPU-bound and only comparable within one run. Draw calls and memory carry over.
- **Generated textures** (about 12.6 MiB uncompressed) are built at load and never written to disk. They could be halved if this went further.
- **No audio.** The bell is a stage note and the tubes' flicker.
