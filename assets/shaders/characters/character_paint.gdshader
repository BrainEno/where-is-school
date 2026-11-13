shader_type spatial;
// The protagonist's and Q's painted surface (option C in docs/CHARACTER_ART.md).
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
// - no specular, no reflections, no rim: nothing for a highlight to slide on.
//
// The ink line is a separate pass, character_outline.gdshader, on the parts that need it.
render_mode specular_disabled, cull_back, depth_draw_opaque;

uniform vec3 albedo : source_color = vec3(0.5);
// Multiplier for the shadow side's light: the colour shadows are painted in.
uniform vec3 shade_tint : source_color = vec3(0.55, 0.55, 0.7);
// Multiplier for the lit side (a warm or cool cast on the light).
uniform vec3 light_tint : source_color = vec3(1.0);
// How much light the shadow side keeps, before the tint.
uniform float shadow_fill : hint_range(0.0, 1.0) = 0.28;
// The half-tone band's brightness between shadow (0) and light (1).
uniform float half_tone : hint_range(0.0, 1.0) = 0.62;
// Where the bands change, in N·L. Lower moves the light further round the form.
uniform float shadow_edge : hint_range(-1.0, 1.0) = -0.05;
uniform float light_edge : hint_range(-1.0, 1.0) = 0.42;
// The light band's level. A flat band at 1.0 holds every lit surface at the brightness
// Lambert gives only where the light hits square on (N·L = 1); across the band N·L
// averages about 0.75, so 1.0 burns pale skin to cream under the warm rooms' key light.
uniform float light_strength : hint_range(0.3, 1.2) = 0.76;
uniform float edge_softness : hint_range(0.001, 0.4) = 0.05;
// How far the pigment breaks the band edges, in N·L.
uniform float edge_break : hint_range(0.0, 0.6) = 0.18;

// Pigment blocks.
uniform float pigment_scale : hint_range(0.5, 40.0) = 9.0;
// Stretch of a block along each object axis (2 on Y makes vertical strokes).
uniform vec3 pigment_stretch = vec3(1.0, 2.2, 1.0);
uniform float pigment_steps : hint_range(2.0, 8.0) = 4.0;
// Value variation across the blocks (0.15 = ±15%).
uniform float pigment_value : hint_range(0.0, 0.6) = 0.14;
uniform vec3 pigment_a : source_color = vec3(0.5);
uniform vec3 pigment_b : source_color = vec3(0.5);
// How far the blocks pull the albedo towards pigment_a / pigment_b.
uniform float pigment_mix : hint_range(0.0, 1.0) = 0.3;
uniform float pigment_seed = 0.0;

// Painted patches: an ellipsoid in rest/object space, optionally mirrored across x = 0.
uniform vec3 patch_center = vec3(0.0);
uniform vec3 patch_radius = vec3(0.0);
uniform vec3 patch_color : source_color = vec3(0.4, 0.3, 0.45);
uniform float patch_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 patch2_center = vec3(0.0);
uniform vec3 patch2_radius = vec3(0.0);
uniform vec3 patch2_color : source_color = vec3(0.6, 0.3, 0.25);
uniform float patch2_strength : hint_range(0.0, 1.0) = 0.0;
uniform bool patch_mirror_x = true;
// The x the patches mirror across: the middle of the face (Q's sits 1.2 cm off x = 0).
uniform float mirror_center_x = 0.0;

varying vec3 paint_position;

float hash31(vec3 p) {
	vec3 q = fract(p * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.x + q.y) * q.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	float x00 = mix(hash31(cell), hash31(cell + vec3(1.0, 0.0, 0.0)), t.x);
	float x10 = mix(hash31(cell + vec3(0.0, 1.0, 0.0)), hash31(cell + vec3(1.0, 1.0, 0.0)), t.x);
	float x01 = mix(hash31(cell + vec3(0.0, 0.0, 1.0)), hash31(cell + vec3(1.0, 0.0, 1.0)), t.x);
	float x11 = mix(hash31(cell + vec3(0.0, 1.0, 1.0)), hash31(cell + vec3(1.0, 1.0, 1.0)), t.x);
	return mix(mix(x00, x10, t.y), mix(x01, x11, t.y), t.z);
}

// 0..1, two octaves, stretched.
float pigment_field(vec3 p) {
	vec3 q = p * pigment_scale / max(pigment_stretch, vec3(0.05)) + vec3(pigment_seed);
	return value_noise(q) * 0.68 + value_noise(q * 2.37 + vec3(11.7, 3.1, 7.9)) * 0.32;
}

float patch_mask(vec3 p, vec3 center, vec3 radius, float noise) {
	if (radius.x <= 0.0 || radius.y <= 0.0 || radius.z <= 0.0) {
		return 0.0;
	}
	vec3 q = p;
	if (patch_mirror_x) {
		q.x = mirror_center_x + abs(q.x - mirror_center_x);
	}
	float d = length((q - center) / radius);
	// A hard-ish, uneven edge: a patch of paint, not an airbrushed blush.
	return 1.0 - smoothstep(0.72, 0.9, d + (noise - 0.5) * 0.45);
}

void vertex() {
	paint_position = CUSTOM0.w > 1.5 ? CUSTOM0.xyz : VERTEX;
}

void fragment() {
	float n = pigment_field(paint_position);
	float steps = max(pigment_steps, 2.0);
	float block = floor(n * steps) / (steps - 1.0);
	block = clamp(block, 0.0, 1.0);
	vec3 drift = mix(pigment_a, pigment_b, block);
	vec3 colour = mix(albedo, drift, pigment_mix);
	colour *= 1.0 + (block - 0.5) * 2.0 * pigment_value;
	colour = mix(colour, patch_color, patch_mask(paint_position, patch_center, patch_radius, n) * patch_strength);
	colour = mix(colour, patch2_color, patch_mask(paint_position, patch2_center, patch2_radius, n) * patch2_strength);
	ALBEDO = clamp(colour, vec3(0.0), vec3(1.0));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	// Recomputed here rather than passed from fragment(): vertex-to-light varyings work on
	// every renderer this project is captured with (Forward+ and Compatibility).
	float n = pigment_field(paint_position);
	float ndl = dot(NORMAL, LIGHT) + (n - 0.5) * edge_break;
	float half_band = smoothstep(shadow_edge - edge_softness, shadow_edge + edge_softness, ndl);
	float light_band = smoothstep(light_edge - edge_softness, light_edge + edge_softness, ndl);
	float lit = mix(0.0, half_tone, half_band);
	lit = mix(lit, 1.0, light_band) * light_strength;
	vec3 tint = mix(shade_tint * shadow_fill, light_tint, lit);
	DIFFUSE_LIGHT += tint * ATTENUATION * LIGHT_COLOR / PI;
}
