shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Painterly character — independent evaluation, not sharing environment logic.
// Goals: silhouette, posture, clothing identity at gameplay distance; expressionist skin.
// Deliberately softer than environment: fewer, warmer bands, no harsh UV warp.

uniform vec4 skin_color : source_color = vec4(0.82, 0.66, 0.58, 1.0);
uniform vec4 cloth_color : source_color = vec4(0.42, 0.44, 0.68, 1.0);
uniform vec4 shadow_hue_color : source_color = vec4(0.58, 0.48, 0.62, 1.0); // cool violet for shadow, per portrait note
uniform float use_cloth : hint_range(0.0, 1.0) = 0.0; // 0 = skin, 1 = cloth — per material instance, not per vertex
uniform float poster_levels : hint_range(2.0, 6.0, 1.0) = 3.0; // fewer bands than environment
uniform float wrap_amount : hint_range(0.0, 0.6) = 0.35; // soft wrap for facial roundness
uniform float contour_softness : hint_range(0.0, 1.0) = 0.22;
uniform float roughness_value : hint_range(0.5, 1.0) = 0.85;

void fragment() {
	// Wrap diffuse: bias N·L so light wraps around forms (cheaper than SSS, reads as skin).
	float ndotl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndotl + wrap_amount) / (1.0 + wrap_amount), 0.0, 1.0);
	// 3-tone quantization: keep skin as mass, not steps.
	float stepped = floor(wrapped * poster_levels + 0.5) / poster_levels;

	vec3 base_color = mix(skin_color.rgb, cloth_color.rgb, use_cloth);
	// Shadow hue shift: instead of black, move hue toward cool violet in shadow.
	// This is the expressionist note from the portrait direction.
	float shadow_t = 1.0 - stepped;
	vec3 shadow_color = mix(base_color * 0.65, shadow_hue_color.rgb * 0.9, 0.45);
	vec3 lit_color = mix(shadow_color, base_color, stepped);

	// No UV warp on character — proportion/posture carry the read, not surface distortion.
	ALBEDO = lit_color;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.08;
	// Very soft contour: darken grazing angles just enough to separate limbs from torso,
	// but never a hard ink line — that belongs to the outline next_pass, if used.
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float soft_edge = pow(1.0 - ndotv, 2.5) * contour_softness * 0.18;
	ALBEDO *= 1.0 - soft_edge;

	// Subsurface-like warmth: add a faint red bias where light bleeds through thin forms (ears, etc.)
	// Approximated via N·L behind the surface, kept subtle.
	float sss = pow(clamp(dot(NORMAL, -LIGHT), 0.0, 1.0), 2.0) * 0.12 * (1.0 - use_cloth);
	ALBEDO += vec3(sss * 0.35, sss * 0.12, sss * 0.08);
}
