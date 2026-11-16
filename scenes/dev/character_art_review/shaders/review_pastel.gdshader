shader_type spatial;
// Direction 2 of the character art review (issue #188): "charcoal and oil pastel".
// Development only.
//
// The form is carried by drawn marks, not by smooth shading:
//   - value comes from charcoal hatching laid in *screen space*, anchored to the character
//     (so it reads as marks drawn over the figure, not a texture printed on the cloth), its
//     spacing in pixels clamped so it never dissolves into grey at the gameplay distance;
//   - the darkest parts get a second, crossing layer;
//   - the marks "boil": their offset jumps a few times a second like redrawn animation
//     frames (`boil_fps`, 0 holds them still);
//   - the lit colour is a waxy pastel with the under-colour showing through its grain;
//   - painted accents (`patch*`) put raw colour where Schiele would: nose, ears, knuckles,
//     the bruise under the protagonist's eyes, Q's flush.
// The hatching is placed by the character's own key (`key_direction`, view space), so it
// survives any room; the room's lights then modulate the whole gently in two soft bands.
render_mode specular_disabled, cull_back, depth_draw_opaque;

#include "res://scenes/dev/character_art_review/shaders/review_common.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.7, 0.65, 0.55);
uniform vec3 pastel_b : source_color = vec3(0.8, 0.6, 0.45);
uniform float grain_scale : hint_range(5.0, 120.0) = 42.0;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.35;
uniform vec3 shade_tint : source_color = vec3(0.55, 0.62, 0.7);
uniform vec3 charcoal : source_color = vec3(0.12, 0.11, 0.12);
uniform vec3 key_direction = vec3(-0.35, 0.8, 0.5);
// Key shade (0 dark .. 1 lit) below which the first layer starts, and the crossing layer.
uniform float hatch_start : hint_range(0.0, 1.0) = 0.55;
uniform float cross_start : hint_range(0.0, 1.0) = 0.28;
uniform float hatch_angle = 1.05;
uniform float cross_angle = -0.45;
// Line spacing in pixels at `reference_distance`, clamped.
uniform float spacing_px : hint_range(2.0, 20.0) = 7.0;
uniform float reference_distance = 2.0;
uniform float min_spacing_px : hint_range(1.0, 10.0) = 3.2;
uniform float max_spacing_px : hint_range(2.0, 30.0) = 11.0;
uniform float hatch_strength : hint_range(0.0, 1.0) = 0.85;
uniform float wobble : hint_range(0.0, 2.0) = 0.6;
uniform float boil_fps : hint_range(0.0, 24.0) = 6.0;
uniform float room_fill : hint_range(0.0, 1.0) = 0.55;
uniform float room_light_strength : hint_range(0.0, 2.0) = 0.85;
uniform float paper_glow : hint_range(0.0, 1.0) = 0.12;

uniform vec3 patch_center = vec3(0.0);
uniform vec3 patch_radius = vec3(0.0);
uniform vec3 patch_color : source_color = vec3(0.7, 0.3, 0.25);
uniform float patch_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 patch2_center = vec3(0.0);
uniform vec3 patch2_radius = vec3(0.0);
uniform vec3 patch2_color : source_color = vec3(0.7, 0.3, 0.25);
uniform float patch2_strength : hint_range(0.0, 1.0) = 0.0;
uniform bool patch_mirror_x = true;
uniform float mirror_center_x = 0.0;

varying vec3 rest_pos;
varying vec2 screen_offset;
varying float origin_depth;

void vertex() {
	rest_pos = review_rest_position(CUSTOM0, VERTEX);
	vec4 clip_vertex = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec4 clip_origin = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 1.0));
	// Pixels from the character's own anchor (a point 1 m up its origin).
	screen_offset = (clip_vertex.xy / clip_vertex.w - clip_origin.xy / clip_origin.w) * 0.5 * VIEWPORT_SIZE;
	origin_depth = clip_origin.w;
}

float hatch_layer(vec2 px, float angle, float spacing, float darkness, float jitter, float shift) {
	vec2 dir = vec2(cos(angle), sin(angle));
	float s = dot(px, dir) / spacing + jitter + shift;
	float duty = clamp(darkness, 0.0, 1.0) * 0.55;
	float d = abs(fract(s) - 0.5) * 2.0;
	float aa = max(fwidth(s) * 2.0, 0.02);
	return (1.0 - smoothstep(duty - aa, duty + aa, d)) * step(0.02, duty);
}

void fragment() {
	float n = review_fbm2(rest_pos * 9.0);
	float step_time = boil_fps > 0.0 ? floor(TIME * boil_fps) : 0.0;
	float shift = review_hash31(vec3(step_time, 3.7, 1.3)) * 7.0;
	float angle_jitter = (review_hash31(vec3(step_time, 9.1, 4.2)) - 0.5) * 0.12;

	// The pastel: waxy colour broken by the grain of the paper.
	float grain = review_noise(rest_pos * grain_scale);
	vec3 colour = mix(albedo, pastel_b, step(1.0 - grain_amount, grain));
	colour = mix(colour, patch_color, review_patch(rest_pos, patch_center, patch_radius, n, patch_mirror_x, mirror_center_x) * patch_strength);
	colour = mix(colour, patch2_color, review_patch(rest_pos, patch2_center, patch2_radius, n, patch_mirror_x, mirror_center_x) * patch2_strength);

	float key = dot(normalize(NORMAL), normalize(key_direction)) * 0.5 + 0.5;
	key += (n - 0.5) * 0.18;
	colour = mix(colour * shade_tint, colour, smoothstep(hatch_start - 0.2, hatch_start + 0.05, key));

	float spacing = clamp(spacing_px * reference_distance / max(origin_depth, 0.1), min_spacing_px, max_spacing_px);
	float jitter = (review_noise(rest_pos * 14.0) - 0.5) * wobble;
	float first = hatch_layer(screen_offset, hatch_angle + angle_jitter, spacing, (hatch_start - key) / max(hatch_start, 0.01) * 1.4, jitter, shift);
	float second = hatch_layer(screen_offset, cross_angle - angle_jitter, spacing * 1.1, (cross_start - key) / max(cross_start, 0.01) * 1.6, jitter * 0.7, shift * 1.3);
	float marks = max(first * step(key, hatch_start), second * step(key, cross_start));
	colour = mix(colour, charcoal, marks * hatch_strength);

	ALBEDO = clamp(colour, vec3(0.0), vec3(1.0));
	EMISSION = colour * paper_glow * (1.0 - marks);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(-0.15, 0.25, ndl);
	DIFFUSE_LIGHT += mix(room_fill, 1.0, band) * room_light_strength * ATTENUATION * LIGHT_COLOR / PI;
}
