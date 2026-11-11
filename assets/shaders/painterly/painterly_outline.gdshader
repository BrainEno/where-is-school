shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_front, unshaded;

// Painterly outline — inverted hull technique
// Intended as next_pass on a character or hero prop ShaderMaterial.
// Keep unshaded, vertex-expanded along normal, so the line is a silhouette, not lighting.

uniform vec4 outline_color : source_color = vec4(0.10, 0.09, 0.08, 1.0);
uniform float outline_width : hint_range(0.001, 0.06, 0.001) = 0.022;
uniform float outline_feather : hint_range(0.0, 1.0) = 0.18;

void vertex() {
	// Expand along object normal in model space; scaled by outline_width.
	// Using MODEL_NORMAL ensures the line follows the authored silhouette.
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = 1.0;
	// Slight feather toward edges via N·V so the line thins on facing polygons
	// and stays solid on silhouettes — hand-made, not mechanical.
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALPHA *= 1.0 - outline_feather * ndotv * 0.35;
}
