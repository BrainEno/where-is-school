// Visual experiments lab only (scenes/dev/ is excluded from every export preset).
//
// Expressionist colour fields: the colour lives in the mesh's vertex colours (one flat
// field per face, or a hard diagonal split inside one face), the light is a two-step
// terminator rather than a gradient, and the dark side is whatever the room's ambient
// colour is — blue in the staff room, so the shadows are blue, not grey.
//
// A custom `light()` function is supported by all three renderers; nothing here reads the
// screen or the depth buffer.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Where the lit side starts (N·L) and how hard the edge is.
uniform float terminator = 0.18;
uniform float softness = 0.025;
uniform float light_gain = 1.0;
// Brush streaks along world X/Z, so long walls read as painted in long strokes.
uniform float streak_strength = 0.08;
uniform float streak_scale = 1.4;
uniform float emission_floor = 0.0;

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
	vec2 stroke_space = vec2(world_position.x + world_position.z, world_position.y * 6.0);
	float streak = value_noise(stroke_space * streak_scale) - 0.5;
	colour *= 1.0 + streak * streak_strength * 2.0;
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
