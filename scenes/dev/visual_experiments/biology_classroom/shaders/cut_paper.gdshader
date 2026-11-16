// Biology classroom experiment only (scenes/dev/ is excluded from every export preset).
//
// Cut paper, pasted into the room: the classmates. Each pupil is one mesh of several
// pieces (torso, head, arms, collar, hair...) sampled from that pupil's own sheet of
// papers (`classmates.gd` paints it). The texture's alpha is the cut: outside it the
// fragment is discarded (alpha scissor, so the pieces write depth, cast clean shadows and
// sort like solids on every renderer). There is no card behind them.
//
// Vertex colour:
//   rgb  a tint for the face, or the colour of the paper's core for a thickness piece
//   a    1 = the face of a piece (texture x tint), 0 = a piece's thickness: the same cut,
//        set a few millimetres behind and filled with the core colour, so the edge of the
//        card shows when it is seen from the side
//
// The back of a piece (seen from the board) is the paper's reverse: pale, faintly the
// colour of the dye that soaked through. Light and registers are the room's
// (`room_tone.gdshader`): the two-step terminator, chill, dull, focus.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;

uniform sampler2D paper_sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 reverse_color : source_color = vec4(0.9, 0.88, 0.82, 1.0);
uniform float grain = 0.08;
uniform float flatness = 0.18;
uniform float terminator = 0.12;
uniform float softness = 0.05;
uniform float light_gain = 1.0;
uniform float chill : hint_range(0.0, 1.0) = 0.0;
uniform float dull : hint_range(0.0, 1.0) = 0.0;
uniform vec3 focus_point = vec3(0.0, 0.0, 0.0);
uniform float focus_amount : hint_range(0.0, 1.0) = 0.0;
uniform float focus_radius = 3.0;

varying vec3 world_position;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 sampled = texture(paper_sheet, UV);
	if (sampled.a < 0.5) {
		discard;
	}
	vec3 colour = mix(COLOR.rgb, sampled.rgb * COLOR.rgb, COLOR.a);
	if (!FRONT_FACING && COLOR.a > 0.5) {
		colour = mix(reverse_color.rgb, sampled.rgb, 0.18);
	}
	// The tooth of the paper, in the sheet's own pixels so it stays with the piece.
	float tooth = value_noise(UV * 900.0) - 0.5;
	colour *= 1.0 + tooth * grain;
	float grey = dot(colour, vec3(0.299, 0.587, 0.114));
	colour = mix(colour, vec3(grey) * vec3(0.95, 1.0, 0.97), dull * 0.7);
	colour = mix(colour, colour * vec3(0.74, 0.84, 1.1), chill);
	float distance_out = distance(world_position.xz, focus_point.xz);
	float outside = smoothstep(focus_radius, focus_radius + 2.6, distance_out);
	colour = mix(colour, colour * vec3(0.3, 0.32, 0.52), outside * focus_amount);
	ALBEDO = clamp(colour, vec3(0.0), vec3(1.0));
	EMISSION = ALBEDO * flatness * (1.0 - outside * focus_amount);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float n_dot_l = abs(dot(NORMAL, LIGHT));
	float lit = smoothstep(terminator - softness, terminator + softness, n_dot_l);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR * light_gain / PI;
}
