shader_type spatial;
render_mode cull_back;

// Inside the building under construction (scenes/locations/site_interior/, written by
// tools/build_site_interior.py): raw concrete, timber and steel with the colour running up it.
//
// * The base colour is the mesh's own vertex colour (sRGB bytes): concrete, ply, steel, brass.
// * Over it, hard-edged stripes of colour flow upward. A stripe's phase is the world height,
//   bent by the bearing round `band_centre` (the column of light) so the stripes swirl round
//   the room instead of lying flat; every stripe has its own hue, and the whole wheel turns.
// * `dots` lights the tie holes of a cast wall: a grid of small round eyes, in the colour
//   opposite the stripe they sit in.
// * `pulse` makes the vertex colour itself glow and fade (the key); `glow` is how much of the
//   stripe colour is emitted rather than lit, so the room keeps its colour in the dark.
// * `sway` bends geometry by its vertex alpha (0 at the root, 1 at the tip): the starter bars
//   wave like weed in a current. Walls keep their alpha at 1 and leave `sway` at 0.
uniform float band_mix : hint_range(0.0, 1.0) = 0.5;
uniform float band_pitch = 0.9;
uniform float band_speed = 0.12;
uniform float band_twist = 1.2;
uniform vec3 band_centre = vec3(0.0);
uniform float palette_shift = 0.0;
uniform float dots : hint_range(0.0, 1.0) = 0.0;
uniform float glow = 0.25;
uniform float pulse = 0.0;
uniform float pulse_rate = 2.4;
uniform float sway = 0.0;
uniform float sway_rate = 0.7;
uniform float roughness_value = 0.85;

varying vec3 world_pos;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 palette(float t) {
	return 0.5 + 0.5 * cos(6.2831853 * (vec3(t) + vec3(0.0, 0.33, 0.67)));
}

void vertex() {
	if (sway > 0.0) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float k = COLOR.a * COLOR.a;
		VERTEX.x += sin(TIME * sway_rate + w.x * 0.9 + w.z * 0.4) * sway * k;
		VERTEX.z += cos(TIME * sway_rate * 0.8 + w.z * 0.7 - w.x * 0.3) * sway * k;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = to_linear(COLOR.rgb);
	vec3 rel = world_pos - band_centre;
	float bearing = atan(rel.z, rel.x);
	float reach = length(rel.xz);
	float f = world_pos.y / band_pitch + band_twist * sin(bearing * 3.0 + TIME * 0.2) + reach * 0.22
		- TIME * band_speed;
	float cell = fract(f);
	float width = fwidth(f) * 1.5 + 0.001;
	float stripe = smoothstep(0.5 - width, 0.5 + width, cell) * (1.0 - smoothstep(1.0 - width, 1.0, cell));
	vec3 ink = palette(floor(f) * 0.17 + palette_shift + TIME * 0.02);
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 paint = ink * mix(0.55, 1.15, clamp(lum * 2.0, 0.0, 1.0));
	float amount = band_mix * stripe;
	vec3 colour = mix(base, paint, amount);
	vec3 emit = paint * glow * amount;

	if (dots > 0.0) {
		// 56 holes round the room: a whole number, so the grid closes where the bearing wraps.
		vec2 grid = vec2(bearing * 56.0 / 6.2831853, world_pos.y / 0.62);
		vec2 hole = fract(grid) - 0.5;
		float eye = (1.0 - smoothstep(0.07, 0.1, length(hole))) * dots * step(0.3, world_pos.y);
		vec3 eye_colour = palette(floor(f) * 0.17 + palette_shift + 0.5 + TIME * 0.05);
		colour = mix(colour, eye_colour, eye);
		emit += eye_colour * eye * 0.9;
	}

	float beat = 0.5 + 0.5 * sin(TIME * pulse_rate);
	emit += base * pulse * (0.35 + 0.65 * beat);
	ALBEDO = colour;
	EMISSION = emit;
	ROUGHNESS = roughness_value;
}
