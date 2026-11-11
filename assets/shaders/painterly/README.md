# Painterly shaders — lab prototypes

These are **lab prototypes**, not the shipping asset pipeline. They live only in `assets/shaders/painterly/` and are instanced only in `scenes/dev/painterly_lab/`. The classroom and every playable location remain on `StandardMaterial3D`; nothing here changes `project.godot`, the CameraRig, or navigation.

## Files

- `painterly_env_simple.gdshader` — simple: posterized N·L + flat albedo. Cheapest, ~0.9× StandardMaterial. Use for distant or quiet planes.
- `painterly_env.gdshader` — medium (default): adds world-position UV warp for irregular blocks + N·V hand-drawn contour. Cost ~1.15× simple. Default for most props.
- `painterly_env_full.gdshader` — full: medium + tiled `brush_paper` texture for surface grain + hue jitter + stronger contour. +1 texture fetch. Hero props only, ~1.35× simple.
- `painterly_character.gdshader` — independent evaluation. 3-tone wrap diffuse, shadow hue shift to cool violet (portrait note), subtle SSS warmth. No UV warp — character read is posture/silhouette, not surface distortion.
- `painterly_outline.gdshader` — inverted-hull outline, intended as `next_pass` on a ShaderMaterial. Keep unshaded, vertex-expanded along normal. Width 0.018–0.025 for characters, 0.0–0.015 for environment if ever used.

## Uniforms to tune per instance

Environment (all three share naming where applicable):

- `albedo_color` — the plane’s local palette. Build palettes per location, not one global filter.
- `poster_levels` (3–6) — fewer = bolder graphic blocks. Simple/medium default 5–6, full 6.
- `irregularity` (0–1) — amount of world-position UV warp. 0 = clean plane, 0.35 default medium.
- `contour_color` / `contour_strength` / `contour_sharpness` — hand-drawn edge. Strength 0.35–0.48, sharpness 3.0.
- `brush_paper` (full only) — 128×128 tiled paper noise, repeat. Keep strength 0.25–0.30; above 0.4 the grain competes with the plane.

Character:

- `skin_color` / `cloth_color` / `shadow_hue_color` — skin warm, shadow cool (e.g., 0.58,0.48,0.62). Do not copy environment shadow logic.
- `use_cloth` (0/1) — per material instance: 0 for skin, 1 for cloth. Characters need at least two materials.
- `poster_levels` 3.0 — must stay softer than environment.
- `wrap_amount` 0.35 — roundness without PBR.

Outline:

- `outline_color` ~ 0.10,0.09,0.08 — near-black, not pure black.
- `outline_width` 0.022 default for character proxy; tune per character silhouette.

## Lab controls

Open `scenes/dev/painterly_lab/painterly_lab.tscn` directly (not via Main).

- 1 / 2 / 3 — highlight simple / medium / full prop (visual only; does not change project setting).
- O — toggle outline on the character proxy’s `next_pass` (outline shader on/off).
- C — toggle between perspective baseline (FOV 60) and an orthographic preview (size 12.5) on the *lab’s own* Camera3D. This does not touch `project.godot` or the Main CameraRig; it is a local comparison aid.
- Window menu: resize to 1600×900, then 1920×1080; compare ink, edge, and readability at the same camera pose.

## Performance notes

No viewport copy, no screen-space pass in this slice. Cost is per-object ShaderMaterial:

- simple: baseline (1 ALU quantize)
- medium: + UV warp (2 ALU) + N·V edge (2 ALU) — no extra texture
- full: + brush texture (1 fetch) + hue jitter

The test `tests/painterly_rendering_test.gd` asserts the lab stays at 7 ShaderMaterials and that a hypothetical location of 40 props (all medium) stays inside the Forward+ budget for the target PC. Full variant is capped to hero props.

## What not to do

- Do not assign environment shaders to characters, or character shader to walls — they were evaluated separately for a reason.
- Do not add a global screen filter to get painterliness — the spec forbids generic filters; build from shape/color/value first.
- Do not copy these uniforms into classroom materials — the classroom is out of scope for this task by instruction.
