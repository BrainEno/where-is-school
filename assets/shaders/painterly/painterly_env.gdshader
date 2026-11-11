shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Painterly environment — Medium variant (default)
// Irregular color blocks via UV warp + posterized bands + hand-drawn contour (N·V).
// Default for most props: readable planes without extra texture fetch.

uniform vec4 albedo_color : source_color = vec4(0.74, 0.70, 0.60, 1.0);
uniform float irregularity : hint_range(0.0, 1.0) = 0.35;
uniform float poster_levels : hint_range(2.0, 12.0, 1.0) = 6.0;
uniform vec4 contour_color : source_color = vec4(0.13, 0.12, 0.11, 1.0);
uniform float contour_strength : hint_range(0.0, 1.0) = 0.38;
uniform float contour_sharpness : hint_range(0.5, 8.0) = 3.2;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.55;

varying vec2 warped_uv;

void vertex() {
	// Irregularity as world-position driven UV jitter — no extra texture fetch.
	// This breaks up large planes into hand-made masses, not a repeating pattern.
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float jx = sin(wpos.x * 1.7 + wpos.z * 0.9) * 0.5 + cos(wpos.z * 2.1) * 0.5;
	float jy = sin(wpos.z * 1.4 + wpos.y * 1.1) * 0.5 + cos(wpos.x * 1.3) * 0.5;
	warped_uv = UV + vec2(jx, jy) * irregularity * 0.06;
}

void fragment() {
	vec2 uv = warped_uv;
	// Posterize the diffuse term for bold color planes.
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float stepped = floor(ndotl * poster_levels + 0.5) / poster_levels;
	float lit = mix(1.0 - shadow_strength * 0.4, 1.0, stepped);
	vec3 base = albedo_color.rgb * lit;

	// Hand-drawn contour via view-normal edge: softens toward grazing angles.
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = pow(1.0 - ndotv, contour_sharpness);
	// Only darken, never lighten — contour is ink, not highlight.
	base = mix(base, base * contour_color.rgb * 1.4, edge * contour_strength * 0.65);

	ALBEDO = base;
	ROUGHNESS = 0.92;
	SPECULAR = 0.03;

	// Subtle UV-driven value jitter to break perfect flatness without a texture fetch.
	// Amount tied to irregularity so simple->medium is a smooth ladder.
	float jitter = sin(uv.x * 18.0) * sin(uv.y * 18.0) * 0.015 * irregularity;
	ALBEDO += vec3(jitter);
}
