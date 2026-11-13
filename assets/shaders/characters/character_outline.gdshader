shader_type spatial;
// The ink line around the protagonist and Q: an inverted hull, like the classroom's
// `assets/materials/classroom/ink_outline.tres` (same ink, #2B2622), drawn as the
// `next_pass` of the parts that carry it.
//
// The classroom's hull grows a fixed 1.6 cm. A person is seen from 1 m in a close-up and
// from 6 m in play, so this one grows with distance from the camera (`width` at
// `reference_distance`, clamped), which keeps the line about the same weight on screen:
// it never swallows the eyes in a close-up and never disappears at the far end of a room.
// The eyes, mouth, brows, buttons and teeth carry no hull at all (see the look resources).
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec3 ink : source_color = vec3(0.169, 0.149, 0.133);
// Hull growth in metres at `reference_distance` from the camera.
uniform float width : hint_range(0.0, 0.05) = 0.009;
uniform float reference_distance : hint_range(0.5, 20.0) = 4.0;
uniform float min_scale : hint_range(0.1, 2.0) = 0.55;
uniform float max_scale : hint_range(0.5, 4.0) = 1.7;

void vertex() {
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float distance_scale = clamp(-view_position.z / reference_distance, min_scale, max_scale);
	VERTEX += normalize(NORMAL) * width * distance_scale;
}

void fragment() {
	ALBEDO = ink;
}
