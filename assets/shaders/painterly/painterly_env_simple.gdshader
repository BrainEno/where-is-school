shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Painterly environment — Simple variant
// Baseline graphic planes: posterized diffuse + flat albedo, no UV warp, no brush fetch.
// Cheapest painterly read: keeps cost ~0.9× StandardMaterial3D.

uniform vec4 albedo_color : source_color = vec4(0.78, 0.72, 0.62, 1.0);
uniform float poster_levels : hint_range(2.0, 12.0, 1.0) = 5.0;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.0;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.65;

void fragment() {
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// Posterize: quantize N·L into discrete bands for color blocks.
	float stepped = floor(ndotl * poster_levels + 0.5) / poster_levels;
	// Mix lit and shadow with a painterly strength.
	float lit = mix(1.0 - shadow_strength * 0.35, 1.0, stepped);
	vec3 base = albedo_color.rgb * lit;
	// Keep roughness high — painterly surfaces are not plastic.
	ALBEDO = base;
	ROUGHNESS = 0.95;
	SPECULAR = 0.02;
	// No extra contour in simple variant; edge_softness reserved for medium/full.
}
