shader_type spatial;
// The characters' painted surface: option C in docs/CHARACTER_ART.md, and the protagonist's
// charcoal, Q's oil and N's chalk looks of docs/CHARACTER_INTEGRATION.md.
//
// The classroom around them is toon-lit, specular-free and painted in broad strokes with an
// ink line. A character in the GLBs' own materials is a smooth Burley/PBR gradient with a
// specular sheen, which is what made both of them read as plastic in front of it. This
// shader paints a part (skin, hair, jacket, trousers, ...) the way the room is painted:
//
// - light falls in three bands (shadow, half-tone, light) instead of a gradient, and the
//   band edges are broken by the pigment so they read as brushed rather than ruled;
// - the shadow side is not a darker albedo but a painted colour (`shade_tint`, a multiplier:
//   cool violet-green on the protagonist's skin, olive on Q's), with a little of the light
//   left in it (`shadow_fill`) so it never goes dead black under a single lamp;
// - the pigment is a posterised, slightly stretched value noise: rough colour blocks that
//   drift between two authored colours, not a texture (neither GLB has UVs). It is sampled
//   at the vertex's *rest* position when the mesh carries one in CUSTOM0 (with w = 2, see
//   `CharacterLookApplier`), so the blocks stay on the cloth while the limbs move instead
//   of swimming through it; meshes without it (the protagonist's head, which only nods a
//   few degrees) fall back to the object-space position;
// - up to two painted patches per part, mirrored across the face: the protagonist's
//   bruised under-eyes and Q's flushed cheeks;
// - no specular, no reflections, no rim: nothing for a highlight to slide on;
// - optional stroke marks (`mark_*`, off at the default `mark_strength` 0): short, broken,
//   hand-placed-looking strokes in one colour, laid on in rest space so they stay on the
//   cloth. They can cover a part evenly (`mark_coverage`, a dry-brush or chalk tooth) or
//   gather where the form turns away from the eye (`mark_contour`, the carved line along a
//   woodcut's edge), and fade to their average tone once a stroke is smaller than a pixel,
//   so they never shimmer at gameplay distance;
// - optional silhouette shaping (`shape_*`, character_shape.gdshaderinc), shared with the
//   ink hull.
//
// The ink line is a separate pass, character_outline.gdshader, on the parts that need it.
render_mode specular_disabled, cull_back, depth_draw_opaque;

#include "res://assets/shaders/characters/character_paint.gdshaderinc"
