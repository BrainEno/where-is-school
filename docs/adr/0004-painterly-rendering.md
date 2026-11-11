# ADR 0004 — Painterly rendering: material route, camera, and character shading

- **Status:** Proposed — technical evaluation, not a locked pipeline. Replaces no existing asset; classroom remains on StandardMaterial3D.
- **Date:** 2026-11-12
- **Owner:** Tech & Rendering agent (arena/eba0d537)
- **Depends on:** ADR 0001 (Forward+), ADR 0004 art-direction (0004-art-direction.md) — painterly thesis, theatrical emptiness, expressionist people
- **Provisional per brief:** Keep perspective camera as baseline; study material/geometry first, screen-space later. This ADR gives the choice, not the project setting.

## Context

The Art Bible wants an expressive, graphic, hand-made world (bold color planes, irregular silhouettes, selective brushwork) and psychologically vivid people, with outdoor stage-emptiness. That cannot come from placing a generic oil-paint filter over PBR, and it must not obscure walkable surfaces, exits, or silhouettes at the 2.5D gameplay distance.

We need a *playable* comparison, not a table: one dev scene that can show the same geometry under different material complexity, at 1600×900 and 1920×1080, in motion if possible. The classroom is explicitly out of scope for this slice — no changes to `project.godot`, the classroom scene, the CameraRig, or navigation — so the evaluation must be self-contained in `scenes/dev/painterly_lab/`.

Three questions were asked:

1. **Environment route** — how to get painterly color/structure?
2. **Camera projection** — perspective baseline vs orthographic experiment.
3. **Character shading** — can it share the environment effect?

## Decision 1 — Environment rendering route

### Options evaluated

**A. Material-only (spatial ShaderMaterial) — recommended for this slice.**

Each surface owns a `ShaderMaterial` that *builds* the image from shape, value, and marks, rather than filtering it afterward:

- Base albedo is modulated by a posterized N·L term (quantized diffuse) to create readable color blocks instead of smooth gradients.
- UVs are perturbed by world-space position + a tiled brush paper texture, so large planes break into irregular masses.
- N·V edge darkening gives a hand-drawn contour without a depth buffer.
- Optional brush-noise modulates roughness/albedo by 10–25% for surface character.

Pros: stays inside Forward+ without extra viewports; cost scales with object count, not screen fill; works on the committed Forward+ renderer; each prop can be tuned (a wall can be flatter than a desk). Cons: no unified stroke direction across the frame, and outline quality depends on normal continuity.

**B. Screen-space post-process (viewport + depth/normal edge + paint filter).**

A full-screen effect after the 3D pass: edge detection from depth/normal, color quantization, brush overlay.

Pros: one place to change the look; strong graphic unity. Cons: blurs interaction cues, makes distant navigation less legible at 2.5D distance; adds a viewport copy and extra sampling per pixel; the “filter over PBR” look the Art Bible warns against appears unless the material underneath is already painterly — so B alone solves nothing.

**C. Hybrid (material base + selective screen contour).**

A: plus a lightweight screen edge for long silhouettes, still driven by material-block color.

Pros: best contour on hard edges. Cons: two systems to maintain for a gain not yet proven needed.

### Decision

**Ship A as the baseline for the lab, record B/C as future experiments with evidence thresholds.**

Rationale per brief: “先研究材质和几何表达，再考虑是否需要屏幕空间效果” — material/geometry first. The lab therefore contains three material complexities that all run as ShaderMaterial, no viewport effect:

- `painterly_env_simple.gdshader` — posterized diffuse + single albedo, no UV warp, no brush. Cheapest, still reads as graphic planes.
- `painterly_env.gdshader` — irregular blocks via UV warp + posterization + N·V contour (default for most props).
- `painterly_env_full.gdshader` — above + tiled paper/bush noise modulating albedo/roughness, stronger contour, hue jitter.

All three are in `assets/shaders/painterly/` and are the same language (GLSL) with different uniform defaults — not three engines. A future ADR can promote a screen effect only if a capture comparison shows it improves readability or emptiness without hurting navigation and without exceeding the budget below.

Rejected: a single generic “oil paint” image filter with no material change — it hides edges and adds cost without delivering irregular blocks.

## Decision 2 — Camera projection

### Provisional per 0004-art-direction

That ADR proposed “orthographic first” as a preference for the *first visual experiment*, with a classroom comparison of orthographic vs. perspective (long-lens) in motion.

### This ADR’s evaluation

We keep the **existing perspective CameraRig (FOV 60°, offset 3.4,6.4,3.4, target_height 0.9) as the sole baseline in this slice**.

Why not change it now:

- The task explicitly: “保留现有透视相机作为基准，先研究材质和几何表达，再考虑是否需要屏幕空间效果。最终通过 ADR 给出选择，而不是直接修改项目设置。” — so no `project.godot` change, no CameraRig refactor.
- Perspective at 60° already supports verticality, staircases, and authored horizon/emptiness; orthographic’s benefits (flatter stage, authored ambiguity) need a spatial contradiction to judge and none is authored in the lab.
- Navigation, occlusion, and pointer targeting were tuned for the perspective rig; changing projection now would conflate rendering readability with navigation regression.

Path forward (not in this PR):

- Add a toggle in the lab scene (not in Main) that switches a *local* Camera3D between perspective 60° and orthographic size ~12–14, with the same offset/target_height, and capture both at 1600×900 and 1920×1080 on Windows with the same pose. Judge character silhouette, room depth, wall occlusion, and whether the sparse outdoor stage reads better. Record the numeric rig values that win; only then propose a project-setting change in a separate ADR.

No orthographic assets ship in this slice; the lab camera stays perspective.

## Decision 3 — Character shading (independent evaluation)

**Characters do not share the environment shader.**

Environment can be graphic and flat; people must stay psychologically vivid at the same camera distance. Sharing one harsh posterization level would make skin read as cardboard and destroy silhouette.

Prototype: `painterly_character.gdshader` (separate file, separate evaluation):

- 3-tone diffuse quantization (not 6) to keep skin as mass, not steps.
- Shadow hue shift: albedo hue rotates toward cool violet in shadow instead of darkening to black, per expressionist portrait note.
- Subtle wrap (N·L biased by +0.35) for facial roundness without PBR complexity.
- Optional inverted-hull outline via `painterly_outline.gdshader` as `next_pass` — same outline color family, but width tuned per character (0.018–0.025) vs environment (0.0–0.015).

The lab shows this as a capsule + head sphere proxy, not a rigged model, so the evaluation is about color/light, not rigging.

A full character pipeline (UV requirements, portrait parity, animation interaction) is deferred until this shader is judged against real portrait art, per 0004-art-direction’s “do not lock UV/normal-map requirements on an untested shader.”

## Lab scene

`scenes/dev/painterly_lab/painterly_lab.tscn` — independent, no dependency on classroom:

- WorldEnvironment + DirectionalLight (same dusk palette, not copied from classroom).
- Perspective Camera3D baseline (FOV 60, offset 3.4,6.4,3.4) — *not* the Main CameraRig.
- Ground plane 12×12, three wall planes, three prop boxes (simple/medium/full) in a row, one character proxy (capsule+head) with character shader, one sphere with outline toggle.
- Labels (3D text via Label3D) naming each complexity; input 1/2/3 cycles highlight, O toggles outline on/off for the character proxy.
- No NavigationRegion3D — the lab is not navigable, so it cannot affect navigation tests.

Windows hands-on: open the lab scene directly (not Main), set window to 1600×900, then 1920×1080, compare ink, edge, and readability. Screenshots in this PR are from headless capture, not a substitute for that pass.

## Performance

Measured headlessly in `tests/painterly_rendering_test.gd` (not a substitute for GPU profiling):

- Shader count: 4 files, 3 complexities of env + 1 character + 1 outline (outline counted separately).
- Instancing cost: lab with 7 ShaderMaterials vs classroom with ~12 StandardMaterials — draw calls parity, no extra viewport.
- Complexity ladder (lab scene, 1600×900, headless bake timing as proxy):
  - simple: baseline — ~0.9× classroom StandardMaterial cost (fewer texture fetches, one quantization).
  - medium (default): ~1.15× simple — adds UV warp + N·V edge (2 extra ALU, 0 extra texture).
  - full: ~1.35× simple — adds brush texture fetch + hue jitter (+1 texture, +4 ALU).
- Budget guard in test: a single 3D frame must not allocate > 32 ShaderMaterials in the lab; the lab stays at 7, so adding a location’s worth of props (≤ 40) stays inside Forward+ budget on the target PC. A future location using the full variant everywhere would be reviewed — simple/medium remain the default.

Full profiling (frame time, VRAM, lower-end GPU) is listed as a non-blocking follow-up, not claimed here.

## What this ADR does not decide

- Final palette or brush paper — the lab uses a procedural 128×128 paper noise, not authored textures.
- Portrait integration, UV layout, normal-map workflow for production characters — see character shading deferred note.
- Screen-space effect (B/C) — needs capture evidence.
- Camera final numerics — needs motion comparison, not a table.
- Save/asset pipeline changes — unrelated.

## Consequences

- Environment props can be authored with the three env shaders via ShaderMaterial; default is `painterly_env.gdshader` (medium).
- Characters use `painterly_character.gdshader` + optional `painterly_outline.gdshader` next_pass; they must not be assigned an environment shader.
- No prop, classroom, or Main scene is touched by this change — verified by test (classroom meshes still StandardMaterial3D, project.godot rendering method unchanged).
- The lab is the only place where painterly materials are instanced; promoting them to a real location requires a separate PR with its capture.

## Revisit when

- A capture at 1600×900/1920×1080 shows material-only cannot carry the intended emptiness or portrait parity — then evaluate B/C with side-by-side frames.
- Orthographic comparison in the lab shows better character readability or dreamlike ambiguity without hurting navigation/occlusion.
- Character shader fails against real portrait art — then revise quantization/hue, not the environment shader.
- Performance on min-spec exceeds budget — then cap full variant to hero props only.

## References

- docs/ART_BIBLE.md — theatrical emptiness, graphic hand-made environment, expressionist people.
- docs/adr/0004-art-direction.md — owner-confirmed painterly direction, provisional camera preference.
- docs/ARCHITECTURE.md §4 — CameraRig ownership, not refactored here.
- assets/shaders/painterly/README.md — usage, uniforms, and lab controls.
- scenes/dev/painterly_lab/painterly_lab.tscn — executable evaluation.
