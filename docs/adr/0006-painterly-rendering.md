# ADR 0006 — Painterly Rendering Prototype

- **Status:** Proposed — isolated prototype and measurement harness implemented; Windows visual/performance review is still required.
- **Date:** 2026-11-11
- **Depends on:** ADR 0001 (Godot 4.7.2 / Forward+), ADR 0004 (art direction, spatial logic, and camera)
- **Scope:** environment surfaces, environment contours, and a separate in-game character shading study.

> **Numbering note:** the requested rendering spike was described as ADR 0004, but this checkout already has `0004-art-direction.md` and `0005-saves.md`. This record uses the next unused identifier rather than introducing a duplicate ADR number. The existing records are left untouched.

## Context

The art direction calls for authored color masses, imperfect contours, selective brush marks, and readable 3D spaces. The current project uses Forward+ and mostly simple `StandardMaterial3D` resources. The existing protagonist and Q GLBs use multiple authored, untextured surface colors; their visual problem is not the same as the environment's.

This is a rendering study, not a production-scene conversion. `scenes/dev/painterly_lab/painterly_lab.tscn` is independent of the classroom, main `CameraRig`, location navigation, and project-wide display/render settings.

## Routes evaluated

| Route | Strengths | Risks / limits | Prototype decision |
|---|---|---|---|
| Authored textures, vertex colors, and geometry marks | Art-directed, controllable per asset; marks can follow a designed composition | Requires asset-by-asset work and UV/color authoring; not a global retrofit | Retain as the preferred path for hero assets and specific marks; use alongside shaders when authored art is available |
| World/object-space material shader | Reusable across simple and imported meshes; broad color patches stay attached to the world rather than swimming with the camera | Procedural fields can look generic if overused; per-pixel cost scales with screen coverage; world-space scale and palette need art review | Prototype broad irregular pigment fields and a restrained, broken brush mask on environment surfaces |
| Geometry contour / inverted hull | Silhouette line is stable in 3D and does not depend on the viewport resolution | Adds a material pass; line width, hard edges, and overlapping geometry can produce heavy or uneven contours | Optional second pass on selected environment props only; keep floors and character meshes out of this pass |
| Screen-space post-process | Can unify a complete image and work independently of mesh UVs | View-dependent marks, full-screen cost, possible UI/edge contamination, and reduced control over individual surfaces | Do not adopt for this prototype; reconsider only if material/geometry methods cannot unify a reviewed scene |

The shader field uses world-space value noise for uneven color masses, a second low-frequency field to break their edges, and a bounded line mask for the higher tier. It does not place a full-screen oil-paint filter over the image. The contour is an optional inverted-hull pass, not a screen-space edge detector.

## Decision 1 — Camera and projection

**Keep perspective as the rendering prototype baseline.** The lab camera uses the current main-camera FOV of 60 degrees. The decision does not change `project.godot`, `scenes/main/main.tscn`, `scripts/world/camera_rig.gd`, or the classroom camera setup.

This is a baseline for comparing material behavior, not a final projection decision. ADR 0004's later classroom comparison remains valid: judge orthographic against restrained/long-lens perspective in motion, using the same representative composition and considering occlusion, navigation, character scale, and room depth. No projection change is justified by a material-only lab.

| Projection | Expected benefit | Expected cost / open question | Status in this spike |
|---|---|---|---|
| Current perspective, FOV 60° | Preserves present project framing and depth/occlusion cues; makes this a controlled material-only comparison | Wider convergence than a long-lens composition; nearest/farthest scale changes remain visible | Baseline used by the lab; not declared the final camera |
| Restrained / long-lens perspective | Keeps depth and occlusion while reducing visible convergence and scale swing | Requires choosing new FOV, distance, offset, and framing together; would confound this material-only preview if changed here | Keep as a later camera comparison candidate |
| Orthographic | Stable apparent size and strong authored-plane composition; may support spatial dislocation | Removes perspective scale cues and changes depth readability / overlap; navigation and character staging need direct review | Keep as the alternative in the classroom comparison required by ADR 0004 |

The lab does not simulate or choose numeric settings for the latter two candidates. The current 60° lens is a baseline, not evidence that a wider perspective is artistically preferred.

## Decision 2 — Environment material study

Use three comparable environment treatments in the standalone lab:

1. **Standard:** ordinary rough `StandardMaterial3D` colors.
2. **Color fields:** the environment shader's broad, irregular world-space pigment patches and toon-like diffuse response.
3. **Fields, marks, and contour:** the same base shader with a restrained broken brush mask and optional geometry outline pass.

Every styled sample copies its source material's base color (and albedo texture if present) into a scene-local `ShaderMaterial`. This keeps the sample palette explicit and avoids changing imported sources. The shader should remain a material tool, not a substitute for authored shape design, selective geometry, textures, or scene composition.

## Decision 3 — Character shading is separate

Do **not** apply the environment shader or environment contour pass to characters by default. The lab compares the imported protagonist's existing surface palette against a separate per-surface character shader. That shader preserves each source material color, uses a smoother Burley light response rather than the environment's toon response, and only adds a very small pigment variation; it does not add environmental color patches, brush lines, or the outline pass.

This is an evaluation candidate, not a decision to recolor production characters. Silhouette, clothing identity, face readability, and the authored color blocks take priority at gameplay distance. Dialogue portraits remain independent 2D art.

## Measurement method

The lab contains one 144-instance `MultiMesh` batch so all material tiers use the same repeated geometry and instance count. In the preview, press **B** to show the batch, **1 / 2 / 3** to select Standard / Color fields / Full, and **Enter** to run a one-second warm-up plus a three-second sample for each tier. The output lines are prefixed `PAINTERLY_BENCHMARK` and include frame-derived average FPS, average frame time, CPU-side `TIME_PROCESS`, draw calls, and primitives.

The timed runner temporarily disables VSync so the measured frame rate is not capped by the display, then restores the window's previous VSync mode. The logged frame time is still end-to-end and can be affected by GPU, CPU, driver, power plan, window composition, and background applications. `TIME_PROCESS` is CPU-side engine time, not GPU time. Use the same Windows machine, driver, power mode, and focused window for both resolutions; run the sequence at **1600×900** and **1920×1080**. Each result records the window size and that VSync was disabled during sampling. Record device/driver and the output below before treating a tier as production-ready. If GPU time is needed, pair this readout with an external GPU profiler rather than infer GPU cost from CPU time.

### Results

No results are recorded yet. This checkout has no Godot executable or Windows graphics session, so shader compilation, visual acceptance, and GPU-backed measurements could not be performed in this environment. Do not interpret this blank table as a pass.

| Resolution | Tier | Average FPS | Average frame ms | Average process ms | Average draw calls | Device / notes |
|---|---|---:|---:|---:|---:|---|
| 1600×900 | Standard | Not measured | Not measured | Not measured | Not measured | Windows run pending |
| 1600×900 | Color fields | Not measured | Not measured | Not measured | Not measured | Windows run pending |
| 1600×900 | Marks + contour | Not measured | Not measured | Not measured | Not measured | Windows run pending |
| 1920×1080 | Standard | Not measured | Not measured | Not measured | Not measured | Windows run pending |
| 1920×1080 | Color fields | Not measured | Not measured | Not measured | Not measured | Windows run pending |
| 1920×1080 | Marks + contour | Not measured | Not measured | Not measured | Not measured | Windows run pending |

### Required manual Windows review

1. Open the project in the pinned Godot 4.7.2 Stable standard editor, open `scenes/dev/painterly_lab/painterly_lab.tscn`, and run the current scene (F6). Allow shader compilation to finish before judging the image.
2. Set the game window to exactly **1600×900** (verify the size in the HUD), inspect the three environment lanes side by side, and compare the two protagonist treatments. Check patch scale, contour thickness, stroke restraint, color identity, and silhouette readability.
3. Press **B**, then **Enter**. Keep the window focused and copy the three `PAINTERLY_BENCHMARK` result lines, which include the measured window width and height.
4. Set the window to exactly **1920×1080** and repeat without changing display scaling, driver, or power mode. The timed benchmark disables and restores VSync on its own. If the monitor can only show 1920×1080 in fullscreen, use **F11** in the lab; its HUD and benchmark log should report the actual window size.
5. Append the six measured rows plus GPU/driver and a short visual verdict to this ADR. If the Windows build reports shader errors or the style obscures shape/readability, do not accept the current preset values.

## Consequences

- The environment prototype is reusable and independent of the classroom, but its palette and strengths still need review against representative project art.
- Characters have a separate material path; the environment outline and broad texture must not be assumed to work on faces, hair, or clothing.
- The low/mid/high comparison keeps geometry count constant for profiling. The side-by-side preview is for visual judgement; the timed benchmark isolates one tier at a time.
- There is no screen-space effect, global material override, camera refactor, renderer change, or project-setting change in this decision.
- This record remains **Proposed** until the lab is opened on Windows at both target resolutions and the measured output / visual review is appended.

## Revisit when

- The Windows 1600×900 and 1920×1080 comparison has been captured and reviewed.
- The classroom vertical slice can compare the existing perspective baseline with orthographic in motion.
- Representative environment assets show that the procedural marks are either too generic or insufficiently controllable.
- A measured performance issue justifies changing the number of noise evaluations, outline usage, renderer, or camera strategy.
