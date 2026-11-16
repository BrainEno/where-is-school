shader_type spatial;
// Direction 3 of the character art review (issue #188): "expressionist colour planes".
// Development only.
//
// The figure is built from a few large planes of *different hues*, the way an expressionist
// head is (Jawlensky, Kirchner's woodcuts), rather than one colour getting lighter and darker:
//   - every fragment is assigned to one of five planes by its skinned model-space normal
//     (left-front "key", right-front "side", top, underside, back), with the boundary broken
//     by rest-pose noise so the planes have cut, angular edges rather than smooth ones;
//   - each plane has its own authored colour, fixed to the body (the protagonist's right
//     cheek is always the green one), so colour describes the person, not the lamp;
//   - plane boundaries are cut in with a thin gouge line (`gouge_*`), faded out at gameplay
//     distance so the small figure does not turn into a net of lines;
//   - the room's lights still decide value, in two bands, with the shadow side shifted
//     towards `shade_tint` (a hue, not only darker).
render_mode specular_disabled, cull_back, depth_draw_opaque;

#include "res://scenes/dev/character_art_review/shaders/review_common.gdshaderinc"

uniform vec3 plane_key : source_color = vec3(0.8, 0.7, 0.5);
uniform vec3 plane_side : source_color = vec3(0.5, 0.6, 0.55);
uniform vec3 plane_top : source_color = vec3(0.85, 0.8, 0.6);
uniform vec3 plane_under : source_color = vec3(0.5, 0.3, 0.35);
uniform vec3 plane_back : source_color = vec3(0.3, 0.32, 0.45);
// Model space: +X is the character's left, +Z forward.
uniform vec3 key_dir = vec3(0.62, 0.35, 0.7);
uniform vec3 side_dir = vec3(-0.75, 0.05, 0.66);
uniform float top_bias : hint_range(0.0, 1.0) = 0.15;
uniform float jitter : hint_range(0.0, 1.0) = 0.38;
uniform float jitter_scale : hint_range(1.0, 40.0) = 8.0;
uniform vec3 shade_tint : source_color = vec3(0.45, 0.48, 0.7);
uniform float shadow_fill : hint_range(0.0, 1.0) = 0.42;
uniform float light_strength : hint_range(0.3, 1.5) = 0.85;
uniform vec3 gouge_ink : source_color = vec3(0.1, 0.08, 0.1);
uniform float gouge_strength : hint_range(0.0, 1.0) = 0.8;
uniform float gouge_near = 2.5;
uniform float gouge_far = 5.5;

uniform vec3 patch_center = vec3(0.0);
uniform vec3 patch_radius = vec3(0.0);
uniform vec3 patch_color : source_color = vec3(0.8, 0.25, 0.2);
uniform float patch_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 patch2_center = vec3(0.0);
uniform vec3 patch2_radius = vec3(0.0);
uniform vec3 patch2_color : source_color = vec3(0.8, 0.25, 0.2);
uniform float patch2_strength : hint_range(0.0, 1.0) = 0.0;
uniform bool patch_mirror_x = true;
uniform float mirror_center_x = 0.0;

varying vec3 rest_pos;
varying vec3 model_normal;
varying float view_depth;

void vertex() {
	rest_pos = review_rest_position(CUSTOM0, VERTEX);
	model_normal = NORMAL;
	view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec3 q = rest_pos * jitter_scale;
	vec3 wobble = vec3(review_noise(q), review_noise(q + vec3(5.2, 1.3, 8.7)), review_noise(q + vec3(2.9, 7.7, 3.1))) - 0.5;
	vec3 nrm = normalize(normalize(model_normal) + wobble * jitter * 2.0);
	float d_key = dot(nrm, normalize(key_dir));
	float d_side = dot(nrm, normalize(side_dir));
	float d_top = nrm.y + top_bias;
	float d_under = -nrm.y - 0.1;
	float d_back = -nrm.z - 0.05;
	float best = d_key;
	float id = 0.0;
	vec3 colour = plane_key;
	if (d_side > best) { best = d_side; id = 1.0; colour = plane_side; }
	if (d_top > best) { best = d_top; id = 2.0; colour = plane_top; }
	if (d_under > best) { best = d_under; id = 3.0; colour = plane_under; }
	if (d_back > best) { best = d_back; id = 4.0; colour = plane_back; }

	float n = review_fbm2(rest_pos * 10.0);
	colour = mix(colour, patch_color, review_patch(rest_pos, patch_center, patch_radius, n, patch_mirror_x, mirror_center_x) * patch_strength);
	colour = mix(colour, patch2_color, review_patch(rest_pos, patch2_center, patch2_radius, n, patch_mirror_x, mirror_center_x) * patch2_strength);

	float edge = step(0.01, fwidth(id));
	float near_fade = 1.0 - smoothstep(gouge_near, gouge_far, view_depth);
	colour = mix(colour, gouge_ink, edge * gouge_strength * near_fade);

	ALBEDO = clamp(colour, vec3(0.0), vec3(1.0));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(0.02, 0.1, ndl);
	vec3 tint = mix(shade_tint * shadow_fill, vec3(light_strength), band);
	DIFFUSE_LIGHT += tint * ATTENUATION * LIGHT_COLOR / PI;
}
