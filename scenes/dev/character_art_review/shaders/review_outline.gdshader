shader_type spatial;
// The contour for the character art review directions (issue #188). Development only.
//
// An inverted hull like the production `character_outline.gdshader` (which is not used or
// changed here), with three extra controls so one shader can draw all three directions:
//   width_variation  0 = an even line; up to 1 = a charcoal line that swells and thins
//   gap              the share of the line left out (a broken, redrawn contour)
//   boil_fps         how many times a second the line is redrawn (0 = still)
// The variation is sampled at the rest-pose position, so it stays on the body while it moves.
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

#include "res://scenes/dev/character_art_review/shaders/review_common.gdshaderinc"

uniform vec3 ink : source_color = vec3(0.169, 0.149, 0.133);
uniform float width : hint_range(0.0, 0.05) = 0.009;
uniform float reference_distance : hint_range(0.5, 20.0) = 4.0;
uniform float min_scale : hint_range(0.1, 2.0) = 0.55;
uniform float max_scale : hint_range(0.5, 4.0) = 1.7;
uniform float width_variation : hint_range(0.0, 1.0) = 0.0;
uniform float variation_scale : hint_range(1.0, 40.0) = 9.0;
uniform float gap : hint_range(0.0, 0.8) = 0.0;
uniform float boil_fps : hint_range(0.0, 24.0) = 0.0;

varying float line_noise;

void vertex() {
	vec3 rest = review_rest_position(CUSTOM0, VERTEX);
	float frame = boil_fps > 0.0 ? floor(TIME * boil_fps) : 0.0;
	float n = review_fbm2(rest * variation_scale + vec3(frame * 1.73, frame * 0.61, 0.0));
	line_noise = n;
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float distance_scale = clamp(-view_position.z / reference_distance, min_scale, max_scale);
	float swell = mix(1.0, 0.2 + 1.7 * n, width_variation);
	VERTEX += normalize(NORMAL) * width * distance_scale * swell;
}

void fragment() {
	if (line_noise < gap) {
		discard;
	}
	ALBEDO = ink;
}
