shader_type spatial;
render_mode cull_front, unshaded, depth_draw_never;

uniform vec4 ink_color : source_color = vec4(0.11, 0.12, 0.11, 1.0);
uniform float line_width : hint_range(0.0, 0.08, 0.001) = 0.018;
uniform float edge_wobble : hint_range(0.0, 0.8, 0.01) = 0.28;

void vertex() {
	// Inverted-hull contour: the two low-amplitude waves keep the silhouette from
	// reading as a perfectly uniform vector stroke without adding screen-space work.
	float broad_wobble = sin(dot(VERTEX, vec3(3.1, 5.7, 7.9)));
	float fine_wobble = sin(dot(VERTEX, vec3(11.2, 7.1, 2.8)) + 0.71);
	float unevenness = broad_wobble * 0.65 + fine_wobble * 0.35;

	// MODEL_NORMAL_MATRIX is the inverse-transpose needed for a correct world normal
	// under rotation and non-uniform scale. Convert a constant world-space normal offset
	// back to model space; expanding along NORMAL directly is wrong for non-uniform scale.
	mat3 model_normal_matrix = MODEL_NORMAL_MATRIX;
	vec3 world_normal = model_normal_matrix * NORMAL;
	float world_normal_length = length(world_normal);
	if (world_normal_length > 0.0001) {
		world_normal /= world_normal_length;
		vec3 local_offset = transpose(model_normal_matrix) * world_normal;
		VERTEX += local_offset * line_width * (1.0 + unevenness * edge_wobble);
	}
}

void fragment() {
	ALBEDO = ink_color.rgb;
}
