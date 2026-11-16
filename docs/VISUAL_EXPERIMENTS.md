# Visual experiments lab: postmodern collage, surreal space, medium switching

- **Status:** Experiment. Development-only and never exported. Nothing in the game uses it.
- **Scene:** `scenes/dev/visual_experiments/visual_experiments.tscn`. Open it in the editor and press F6.
- **Check:** `tests/visual_experiments_test.gd` (Godot CI, step `visual_experiments`)
- **Evidence:** `docs/screenshots/visual_experiments/`, plus the workflow `.github/workflows/visual-experiments-capture.yml`
- **Engine:** Godot 4.7.2. All numbers below come from GitHub-hosted runners (llvmpipe / lavapipe software rasterisers).

This lab asks one question: can *Where Is School* let its spaces disagree with each other?
That means paper next to plaster, a corridor that will not end, a room painted rather than lit, a
step that turns the world into a picture. Can it do that with stock Godot, on every
renderer the project might ship? It answers with a walkable scene, not with mock-ups.

The lab sits outside the game on purpose. It touches no production scene or shader,
`project.godot`, player controller, dialogue, read log or location data. Its own test
enforces this: no file under `scenes/`, `scripts/`, `data/`, `assets/` or `addons/` (outside
`scenes/dev/`) names it, and the lab names no production code. Production *assets* (two
classroom GLBs, four classroom textures, two laboratory textures, the protagonist) are
instanced read-only. The release is guarded by the existing rule: both export presets
exclude `scenes/dev/*`, and `tools/verify_build.py` fails a package that contains it.

## 1. Walking it

| Key | |
|---|---|
| WASD / arrows | walk (Shift faster); click to capture the mouse and look |
| F | fly; then Q / E down / up, N passes through walls |
| 1–8 | stations: overview, start, collage, corridor, staff room, classroom, stage, backstage |
| M | switch the medium by hand |
| P | print a performance sample (`VISUAL_LAB_PERF`) |
| H | hide the HUD (which shows renderer, draw calls, primitives, video memory) |

The observer is the lab's own `CharacterBody3D` (`observer.gd`), not the game's player.
It walks, collides and is moved by triggers like any body would be, so every effect is
tested by walking into it.

## 2. What is in it

The plan view runs from the south (the start) northward:

```
 [A collage room] -> [B corridor, 44 m, loops] -> giant door -> [C staff room] -> [D classroom | stage]
```

### A — Handmade collage (`zones/collage_room.gd`)

*Frames: `compatibility/01_collage_room.jpg`, `02_collage_detail.jpg`, `03_collage_flatness.jpg`*

- **Mixed-source surfaces.** 56 paper sheets are on one shader (`shaders/paper_cutout.gdshader`),
  which has eight procedural papers: plain, ruled, graph, halftone newsprint, kraft, a
  textured reprint, a one-point-perspective floor, and crayon hatching. Each has a torn,
  fibrous edge made by noise and `discard`. A wall is a real collision box under
  overlapping sheets, each with a slight roll.
- **Reprints of the game itself.** The classroom's own painted window, blackboard,
  timetable and clock come back as torn prints: the board at a slant, the timetable on its
  side, the clock at the size of a door.
- **Inconsistent perspective.** A floor drawn in one-point perspective lies on a floor with a
  different vanishing point. Paper desks are drawn in oblique projection and stood upright.
  From the side they vanish to a line (`03`), and each still has a collider as thin as paper.
- **2D in 3D.** Paper desks and chairs are flat `Sprite3D` cut-outs with `ALPHA_CUT_DISCARD`.
  Three magazine-cut pupils are `BILLBOARD_FIXED_Y`, so they turn to keep facing you, which
  cardboard does not do. One *real* 3D desk and chair, from the game's GLBs, stands among them.
- **Decal.** A school seal is stamped across the real desk and the floor. It is drawn on
  Forward+ and Mobile (`forward_plus/02_collage_detail.jpg`) and absent on Compatibility
  (`compatibility/02_collage_detail.jpg`), which does not implement decals.
- All textures are generated at load time by `collage_kit.gd` (6 textures, 3.7 MiB of
  RGBA8). The lab ships no image of its own.

### B — Surreal space (`zones/corridor.gd`)

*Frames: `04_corridor_long.jpg`, `05_corridor_giant_door.jpg`, `06_corridor_window.jpg`*

- **Repetition and scale that does not hold.** There are 19 doors, every one numbered "2-3".
  Each door is 85% the height of the one before it, while the corridor keeps its size, so the far
  doors come up to the knee. All slabs and all frames are two `MultiMeshInstance3D`s.
- **A door that is too large.** One doorway is taller than the wall it is cut into, and its
  header stands above the corridor. It is also the only real way out.
- **An inexplicable connection.** Walk into the far door and an `Area3D` moves you 40 m
  back, facing the same way. The corridor seems to go on for ever. The test walks it and
  the walkthrough records it (`loops 1`).
- **A window onto somewhere else.** A window in the corridor wall looks *down into the
  collage room*. It is a live `SubViewport` that shares the world and is printed on the
  same paper shader. It renders only while you are in the corridor.
- A staircase that climbs to the top of the wall and stops there.

### C — Expressionist environment (`zones/expression_room.gd`)

*Frames: `07_expression_room.jpg`, `08_expression_shadow.jpg`*

- **Large unnatural colour fields.** The floor is viridian with a diagonal ochre field. The
  walls are Prussian blue, cadmium and madder. Every field is a vertex colour on a procedural
  `SurfaceTool` mesh, with no texture at all. `shaders/colour_field.gdshader` replaces the
  lighting with a two-step terminator, so light falls in hard shapes rather than gradients.
- **A room that leans.** The north and south walls lean inward as they rise. The way in
  narrows from 2 m to 1.2 m.
- **Chiaroscuro.** The only light is one shadowed `SpotLight3D` through a barred slot high
  in the east wall. The ambient is deep blue, so the shadows are blue. The ceiling is a single
  downward quad: it is culled from above (the overview still sees in) but casts shadow from
  both sides.
- **Psychological composition.** A long table has twelve chairs on one side, one on the
  other, and the light on the one.
- **Painted lies.** On the floor, the single chair's shadow is painted toward the light. On
  the wall, a barred parallelogram of painted sunlight falls from a window that does not exist.

### D — Medium switch, the core experiment (`zones/threshold.gd`, `medium_switch.gd`)

*Frames: `09_threshold_3d.jpg` → `10_threshold_painted.jpg`, `11_classroom_picture.jpg`,
`12_backstage.jpg`; walkthrough stills*

A plain classroom, made of the game's own desks and chairs on plaster and concrete, opens
on a stage of theatre flats. The flats paint a corridor on plywood, and each wing
paints its own vanishing point. The protagonist stands on the stage with a paper chair.

**Crossing the threshold changes the medium of everything you see.** When the observer's
body enters the stage's `Area3D`:

1. The root viewport stops drawing 3D (`Viewport.disable_3d = true`).
2. A `SubViewport` at half resolution, sharing the same `World3D`, renders the scene from a
   camera that copies the observer's camera every frame.
3. A `TextureRect` on a `CanvasLayer` shows that texture through
   `shaders/painting_filter.gdshader`, a `canvas_item` shader. The shader smears along a
   noise stroke field, lifts saturation, posterises, inks Sobel edges and lays the painting
   crookedly on a paper mount.
4. The painting *tears in* from the left over 0.7 s, so the change is seen happening.

It is still a world. The flats keep their colliders, and the test sweeps the observer's
capsule at the back flat while painted and it stops. Walk round behind the flats and you
leave the trigger: the tear runs backwards and you see plywood, braces and stage weights in 3D
(`12_backstage.jpg`). In the classroom, a framed picture on the wall is a *live* view of
the stage (`11`), so the 2D picture of the 3D room is in the 3D room. Freeing the lab while
painted restores root 3D (`_exit_tree`); the test checks this too.

The switch needs no screen-reading shader and no depth texture, and it changes no project
setting. It is the same code on all three renderers (§4).

## 3. Godot 4.7 techniques, as used here

| Technique | Where | Note |
|---|---|---|
| `Sprite3D` + `ALPHA_CUT_DISCARD`, `BILLBOARD_FIXED_Y` | collage cut-outs, pupils, stage chair | cheapest 2D-in-3D; alpha-cut keeps depth sorting correct |
| Spatial shader with `discard` | torn paper edges | edge shape is per-pixel, the quad stays four vertices |
| `SubViewport` + `ViewportTexture` on a material | corridor window, classroom picture | renders the shared world again: the most expensive item in the lab (§5) |
| `Viewport.disable_3d` + `SubViewport` + `canvas_item` shader | medium switch | portable "post-process" that reads only its own texture |
| `CanvasLayer` over a 3D scene | painting mount, HUD | 2D keeps drawing when root 3D is off |
| Vertex colours + custom `light()` | staff room colour fields | one mesh per wall, no textures; custom `light()` works on all renderers |
| `SurfaceTool` procedural meshes, `create_trimesh_shape()` | leaning walls, passage, stage boards | collision from the same triangles as the visual |
| `MultiMeshInstance3D` | 19 doors, beams | repetition at constant draw cost on Forward+/Mobile |
| `Decal` | school seal | Forward+ / Mobile only |
| Painted backdrop on a flat with real collision | stage flats | `shaders/painted_backdrop.gdshader`, unshaded, procedural corridor |
| `Area3D` triggers moving a body | corridor loop, threshold | `body_entered` → teleport / switch |
| Per-room `Environment` swap | `visual_experiments.gd` | each zone gets its own background, ambient, fog and sun energy |
| `Image` generated at load | all paper, figures, seal | no image assets; cost reported by `Kit.generated_bytes()` |

The lab has no dependency of any kind: no addon, no GDExtension, no third-party asset.

## 4. Renderer behaviour (observed, not assumed)

The capture workflow ran the same scene with only command-line overrides:
`--rendering-driver opengl3` (Compatibility), `--rendering-driver vulkan` (Forward+) and
`--rendering-method mobile --rendering-driver vulkan` (Mobile).

| Experiment | Compatibility | Forward+ | Mobile |
|---|---|---|---|
| Paper shader, torn edges, posterise | ✅ | ✅ | ✅ |
| Sprite3D cut-outs / Y-billboards | ✅ | ✅ | ✅ |
| Vertex-colour fields, custom `light()` | ✅ | ✅ | ✅ |
| SubViewport windows (corridor, picture) | ✅ | ✅ | ✅ |
| Medium switch (`disable_3d` + SubViewport + canvas shader) | ✅ | ✅ | ✅ (same image, minor banding differences) |
| Decal seal | ❌ not drawn (engine limitation) | ✅ | ✅ |
| Staff-room ceiling blocking the sun | ⚠️ sun light reaches the floor in places | ✅ | ✅ |
| Depth fog in the corridor | enabled; not probed separately | same | same |

The decal gap is documented engine behaviour. The ceiling difference was seen in the
first capture run ([43799522663](https://github.com/BrainEno/where-is-school/actions/runs/43799522663)),
where the slot light was misplaced and the sun was the only light: on Forward+ and Mobile
the staff room was dark, on Compatibility the ochre field was sunlit. It shows how Compatibility
handles a double-sided shadow caster with a directional light. In the staff room it makes the
room brighter than intended. A production version would use a closed box for the ceiling
or turn the sun off in that room. Nothing in the lab needs SDFGI, volumetric fog, screen
textures or depth textures, all of which are Forward+-only or behave differently per renderer.

## 5. Performance and resource cost

Measured by `sample_performance()` (the renderer's own monitors, averaged over 20 frames)
at 1600×900 on CI. The renderers are **software** (llvmpipe / lavapipe), so frame times are
CPU time and only comparable within one run. Draw calls, primitives and memory are the
renderer's own counts and do carry over to real hardware.
Source: run [43800746336](https://github.com/BrainEno/where-is-school/actions/runs/43800746336),
commit `3b2a5f9`.

**Per view (draw calls / primitives):**

| View | Compatibility | Forward+ | Mobile |
|---|---|---|---|
| Overview (everything) | 1216 / 87k | 641 / 87k | 501 / 87k |
| Collage detail | 393 / 20k | 381 / 20k | 193 / 20k |
| Collage room (doorway) | 1494 / 103k | — | — |
| Corridor long | 1365 / 75k | — | — |
| Staff room | 1055 / 92k | 412 / 92k | 356 / 92k |
| Classroom → stage (3D) | 480 / 132k | — | — |
| Stage, painted | 163 / 63k | 131 / 63k | 53 / 63k |

**A/B probes:** each one switches a single experiment off and on in the same view.

| Probe | Compatibility | Forward+ | Mobile |
|---|---|---|---|
| Corridor window SubViewport, live vs frozen | +699 draws, +30 ms (788 vs 89) | +522 draws, +25 ms | +521 draws, +151 ms |
| 56 paper sheets, shown vs hidden | +56 draws, +112 tris, ~0 ms | +56 draws, +7 ms | +56 draws, +5 ms |
| Decal, shown vs hidden | no change (not drawn) | 0 draws, +4 ms | 0 draws, +3 ms |
| Medium switch, painted vs 3D | +1 draw, −4 ms | +1 draw, −11 ms | +1 draw, −21 ms |

**Memory:** video memory is 36.9 MiB on Compatibility, 147.6 MiB on Forward+ and
120.3 MiB on Mobile (the difference is renderer baseline buffers). Painted mode adds
2.7 MiB on Compatibility and 23 MiB on Forward+ (the half-size SubViewport's targets).
Generated textures: 3.7 MiB. The lab adds about 0.15 MiB of
source to the repository and the evidence frames about 0.6 MiB.

**What this says:**

- **Paper is nearly free.** Each sheet costs one draw call and two triangles; the torn edge
  is in the fragment shader. A room papered with 56 sheets costs less than one shadowed light.
- **The medium switch is cheaper than 3D.** At half resolution the painted view shades a
  quarter of the pixels, and the filter's 12 texture taps cost less than that saving. On every
  renderer, painted mode was faster than the same view in 3D.
- **SubViewport windows are the expensive item.** Each one renders the shared world again
  from another camera, including shadow passes. On Compatibility that is ~9× the draw calls
  of the same view with the window frozen. The lab renders them only while you are in the room
  that has them. Production would need the same rule, or `UPDATE_ONCE` snapshots.
- **Compatibility draws more.** It renders each shadowed light in its own pass, so
  Compatibility issues up to 2.6× the draw calls of Forward+ for the same view. The lab's worst
  view (1494) is within reach of a desktop GPU but not of the game's 1–2 lights per room.
  Production rooms would keep one shadowed light.

## 6. Three ideas that could become real scenes

1. **"The Thirteenth Chair" (staff-room interview).** A conversation scene in the staff room's
   language: colour fields, one shadowed slot light, twelve chairs and one, a painted shadow
   that points the wrong way. It is a *location*, not an effect. It is cheap on every renderer
   (one light, vertex colours), it fits the game's existing dialogue staging, and the painted
   shadow is a clue the player can notice and the ReadLog can record.
2. **"Room 2-3" (the corridor that will not end).** The looping corridor as a navigation
   puzzle. The doors shrink, the numbers repeat, and the giant door is the only exit.
   It is found by noticing what is too large, not by walking further. MultiMesh doors, a
   trigger loop and one fog setting. The window onto another room would be an `UPDATE_ONCE`
   snapshot refreshed on entry, not a live view.
3. **"Through the Picture" (the threshold).** The classroom picture shows the stage. Step through
   the door and the world becomes a painting you can still walk in, with the protagonist
   inside it. Walk behind the flats and it is plywood again. This is the medium switch as a
   narrative device: a memory, a dream, a story told about the school. It costs less than the
   3D view, and it uses only portable features.

## 7. Verdict: what suits *Where Is School*

**Suits it, and could be adopted with production care:**

- **The medium switch (D).** It is the strongest idea here, and it is portable, cheap and
  reversible. Its literary register suits the game: the world becomes *told* rather than
  *seen*. It is not a jump-scare. It needs an authored trigger, a reason in the story and a
  way back.
- **Expressionist colour fields and one hard light (C).** This is psychological unease without
  horror props. It fits the art bible's restraint if it is used for one or two rooms, not as a
  house style.
- **Torn-paper reprints of the game's own textures (A, in small doses).** A timetable on its
  side, a clock too large. These are quiet wrongnesses inside an otherwise normal classroom.

**Interesting, but not for this game (or not as built here):**

- **The full paper room (A as a whole).** As a set piece it is striking, but an entire room
  of oblique-projection paper desks reads as a different game. Flat cut-outs vanish from the
  side, and a point-and-click camera would show that constantly.
- **Y-billboard cut-out people.** They turn to face the camera, which is uncanny for a few
  seconds and then reads as a technical shortcut. The game's characters are 3D, and mixing
  them in would undercut the protagonist.
- **Live SubViewport windows everywhere.** They are the most expensive item measured, about
  9× the draw calls on Compatibility. Keep them to one authored moment, or use snapshots.
- **Decals as a storytelling tool.** They are missing on Compatibility, so anything the story
  depends on cannot be a decal if Compatibility is a target.
- **The endless corridor as ambient décor.** It works only as a puzzle with an exit. As
  scenery, it is a cliché of the genre.

## 8. Reproducing the evidence

```
# the check (Godot CI runs exactly this)
xvfb-run -a godot --resolution 1280x720 --rendering-driver opengl3 --path . \
  --script res://tests/visual_experiments_test.gd

# frames + counters (Compatibility; use --rendering-driver vulkan for Forward+,
# add --rendering-method mobile for Mobile)
xvfb-run -a godot --path . --resolution 1600x900 --rendering-driver opengl3 \
  --script res://tests/capture_visual_experiments.gd -- label=compatibility probes=1

# the walkthrough film
xvfb-run -a godot --path . --resolution 960x540 --rendering-driver opengl3 \
  --write-movie build/visual_walk/frame.png --fixed-fps 24 \
  --script res://tests/capture_visual_experiments_walkthrough.gd
```

The committed frames are 640 px JPEGs decoded from the capture run's annotations (run
43800746336, commit `3b2a5f9`). The 60-second walkthrough film (1436 frames at 24 fps, one
corridor loop, two medium switches) is 14.7 MB. That is over the repository's per-file
budget (ADR 0007), so it lives only as the run's artifact `visual-experiments-walkthrough-1`.
Four stills from it are in `walkthrough/`.
