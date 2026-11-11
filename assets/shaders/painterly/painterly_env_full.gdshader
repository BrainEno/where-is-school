shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Painterly environment — Full variant
// Irregular blocks + posterization + N·V contour + brush paper texture + hue jitter.
// Hero props only; most of a location stays on simple/medium.

uniform vec4 albedo_color : source_color = vec4(0.72, 0.68, 0.58, 1.0);
uniform sampler2D brush_paper : hint_default_white, repeat_enable;
uniform float irregularity : hint_range(0.0, 1.0) = 0.45;
uniform float poster_levels : hint_range(2.0, 12.0, 1.0) = 6.0;
uniform vec4 contour_color : source_color = vec4(0.12, 0.11, 0.10, 1.0);
uniform float contour_strength : hint_range(0.0, 1.0) = 0.48;
uniform float contour_sharpness : hint_range(0.5, 8.0) = 3.0;
uniform float brush_strength : hint_range(0.0, 1.0) = 0.28;
uniform float hue_jitter : hint_range(0.0, 0.15) = 0.04;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.60;

// Simple hue rotation helper (RGB -> approximate hue shift via mix).
vec3 hue_shift(vec3 color, float amount) {
	// Warm-cool jitter without full HSV conversion: lerp toward complement.
	vec3 complement = vec3(1.0) - color;
	return mix(color, complement, amount * 0.12);
}

varying vec2 warped_uv;
varying vec3 world_pos_interp;

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos_interp = wpos;
	float jx = sin(wpos.x * 1.7 + wpos.z * 0.9) * 0.5 + cos(wpos.z * 2.1) * 0.5;
	float jy = sin(wpos.z * 1.4 + wpos.y * 1.1) * 0.5 + cos(wpos.x * 1.3) * 0.5;
	warped_uv = UV + vec2(jx, jy) * irregularity * 0.08;
}

void fragment() {
	vec2 uv = warped_uv;
	// Posterized lighting for color blocks.
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float stepped = floor(ndotl * poster_levels + 0.5) / poster_levels;
	float lit = mix(1.0 - shadow_strength * 0.45, 1.0, stepped);

	// Brush paper: tiled, subtle, never dominant. Paper adds surface character.
	// Use world XZ for large planes so the grain doesn't stretch with UV seams.
	vec2 paper_uv = world_pos_interp.xz * 0.18 + uv * 0.35;
	vec3 paper = texture(brush_paper, paper_uv).rgb;
	float paper_lum = dot(paper, vec3(0.299, 0.587, 0.114));
	// Center at 0, scale by brush_strength so paper is dial-able.
	float paper_mod = (paper_lum - 0.5) * brush_strength;

	vec3 base = albedo_color.rgb * lit;
	base = hue_shift(base, hue_jitter * sin(world_pos_interp.x * 0.7) * cos(world_pos_interp.z * 0.8));
	base += vec3(paper_mod * 0.18);

	// Hand-drawn contour via N·V, slightly stronger than medium for hero props.
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = pow(1.0 - ndotv, contour_sharpness);
	base = mix(base, base * contour_color.rgb * 1.45, edge * contour_strength * 0.72);

	// Limited brushwork: break up specular highlight into granular flecks.
	// No extra highlight — just modulate roughness via paper.
	ALBEDO = clamp(base, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(0.88 + paper_mod * 0.35, 0.75, 1.0);
	SPECULAR = 0.02;
}
