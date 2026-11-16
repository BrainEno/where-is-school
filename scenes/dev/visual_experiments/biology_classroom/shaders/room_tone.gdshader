// Biology classroom experiment only (scenes/dev/ is excluded from every export preset).
//
// The room's one surface. Colour lives in the mesh's vertex colours (flat fields: the
// dado, the plaster, the lacquer of the lectern), the light is a two-step terminator, and
// the dark side is the room's ambient colour, so shade is violet-blue rather than grey.
// Developed from the staff room of the visual lab (`../shaders/colour_field.gdshader`),
// with three controls the classroom's registers drive:
//
//   chill         the impression of B: the warm fields cool toward ink blue
//   dull          the fluorescent hour: colour drains toward an institutional grey-green
//   focus_*       memory narrowing: everything farther than `focus_radius` from
//                 `focus_point` sinks into the ambient, so one desk is left in the light
//
// Nothing here reads the screen or the depth buffer; a custom `light()` runs on Forward+,
// Mobile and Compatibility alike.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float terminator = 0.12;
uniform float softness = 0.03;
uniform float light_gain = 1.0;
uniform float streak_strength = 0.05;
uniform float streak_scale = 1.6;
uniform float emission_floor = 0.0;
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
	vec3 colour = COLOR.rgb * base_color.rgb;
	// Long horizontal brush streaks: walls read as painted in broad strokes, not printed.
	vec2 stroke_space = vec2(world_position.x + world_position.z, world_position.y * 7.0);
	float streak = value_noise(stroke_space * streak_scale) - 0.5;
	colour *= 1.0 + streak * streak_strength * 2.0;
	float grey = dot(colour, vec3(0.299, 0.587, 0.114));
	colour = mix(colour, vec3(grey) * vec3(0.95, 1.0, 0.97), dull * 0.7);
	colour = mix(colour, colour * vec3(0.74, 0.84, 1.1), chill);
	float distance_out = distance(world_position.xz, focus_point.xz);
	float outside = smoothstep(focus_radius, focus_radius + 2.6, distance_out);
	colour = mix(colour, colour * vec3(0.3, 0.32, 0.52), outside * focus_amount);
	ALBEDO = colour;
	EMISSION = colour * emission_floor;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	float lit = smoothstep(terminator - softness, terminator + softness, n_dot_l);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR * light_gain / PI;
}
