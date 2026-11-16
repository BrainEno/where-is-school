shader_type spatial;
// Direction 1 of the character art review (issue #188): "stage light". Development only.
//
// Each character carries its own key light, authored in *view space* the way a painter or a
// lighting designer composes it, instead of taking all of its modelling from the room:
//   - the protagonist is lit from high above (a top light): brow and eye sockets fall into
//     shadow, the head is the brightest thing and the legs sink into a pool of shadow;
//   - Q is lit from low in front (a footlight): the belly and the underside of the face are
//     lit, which reads as too close, slightly uncanny.
// The light falls in two hard values with a narrow saturated band at the terminator (an
// expressionist "core" colour), and the shadow is an absolute painted colour, not a darker
// albedo. `stage_share` of the result is the character's own light (EMISSION); the rest is
// lit by the room's lights in two soft bands, so the character still belongs to the place.
render_mode specular_disabled, cull_back, depth_draw_opaque;

#include "res://scenes/dev/character_art_review/shaders/review_common.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.5);
uniform vec3 shadow_color : source_color = vec3(0.12, 0.13, 0.24);
// How much of the part's own colour survives in the shadow.
uniform float shadow_local : hint_range(0.0, 1.0) = 0.3;
uniform vec3 key_color : source_color = vec3(1.0);
uniform vec3 edge_color : source_color = vec3(0.6, 0.25, 0.3);
uniform float edge_width : hint_range(0.0, 0.5) = 0.1;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.75;
// Towards the light, in view space (+Y screen up, +Z towards the viewer).
uniform vec3 key_direction = vec3(0.2, 1.0, 0.35);
uniform float threshold : hint_range(-1.0, 1.0) = 0.15;
uniform float break_amount : hint_range(0.0, 0.8) = 0.25;
uniform float break_scale : hint_range(1.0, 40.0) = 11.0;
// A pool of light by rest height (metres): full above pool_high, pool_floor below pool_low.
uniform float pool_low = 0.3;
uniform float pool_high = 1.45;
uniform float pool_floor : hint_range(0.0, 1.0) = 0.35;
uniform bool pool_invert = false;
uniform float stage_share : hint_range(0.0, 1.0) = 0.7;
uniform float stage_energy : hint_range(0.0, 3.0) = 1.0;
uniform float room_light_strength : hint_range(0.0, 2.0) = 0.8;

uniform vec3 patch_center = vec3(0.0);
uniform vec3 patch_radius = vec3(0.0);
uniform vec3 patch_color : source_color = vec3(0.4, 0.3, 0.45);
uniform float patch_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 patch2_center = vec3(0.0);
uniform vec3 patch2_radius = vec3(0.0);
uniform vec3 patch2_color : source_color = vec3(0.6, 0.3, 0.25);
uniform float patch2_strength : hint_range(0.0, 1.0) = 0.0;
uniform bool patch_mirror_x = true;
uniform float mirror_center_x = 0.0;

varying vec3 rest_pos;

void vertex() {
	rest_pos = review_rest_position(CUSTOM0, VERTEX);
}

void fragment() {
	float n = review_fbm2(rest_pos * break_scale);
	vec3 base = albedo;
	base = mix(base, patch_color, review_patch(rest_pos, patch_center, patch_radius, n, patch_mirror_x, mirror_center_x) * patch_strength);
	base = mix(base, patch2_color, review_patch(rest_pos, patch2_center, patch2_radius, n, patch_mirror_x, mirror_center_x) * patch2_strength);

	float ndl = dot(normalize(NORMAL), normalize(key_direction)) + (n - 0.5) * break_amount;
	float aa = max(fwidth(ndl), 0.002);
	float lit = smoothstep(threshold - aa, threshold + aa, ndl);
	float edge = lit * (1.0 - smoothstep(threshold + edge_width - aa, threshold + edge_width + aa, ndl));

	float pool = smoothstep(pool_low, pool_high, rest_pos.y);
	if (pool_invert) {
		pool = 1.0 - smoothstep(pool_low, pool_high, rest_pos.y) * 0.6;
	}
	pool = mix(pool_floor, 1.0, pool);

	vec3 shade = mix(shadow_color, shadow_color * base * 2.2, shadow_local);
	vec3 lit_colour = mix(base * key_color, edge_color, edge * edge_strength);
	vec3 stage = mix(shade, mix(shade, lit_colour, pool), lit);

	EMISSION = stage * stage_share * stage_energy;
	ALBEDO = base * (1.0 - stage_share);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(-0.02, 0.08, ndl);
	DIFFUSE_LIGHT += mix(0.22, 1.0, band) * room_light_strength * ATTENUATION * LIGHT_COLOR / PI;
}
