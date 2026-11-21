shader_type spatial;
// The imagined teacher's ink line: an inverted hull like character_outline.gdshader, but
// bent by the same dream_shape() as her body and drawn thick and uneven, the way a woodcut
// line swells and starves. `dream` = 0 gives the GLB's own hull at `width`.
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

#include "res://assets/shaders/imagined/dream_figure.gdshaderinc"

uniform vec3 ink = vec3(0.07, 0.05, 0.12);
uniform float width : hint_range(0.0, 0.06) = 0.008;
// How much thicker the line may swell in the dream, as a multiple of `width`.
uniform float swell : hint_range(0.0, 4.0) = 1.8;
uniform float swell_scale : hint_range(1.0, 60.0) = 9.0;

vec3 to_linear(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / 12.92,
		lessThanEqual(c, vec3(0.04045)));
}

void vertex() {
	vec3 rest = VERTEX;
	VERTEX = dream_shape(VERTEX, TIME);
	float n = sin(rest.y * swell_scale + TIME * 1.3 + phase) * sin(rest.x * swell_scale * 1.7 - TIME * 0.7);
	float grow = width * (1.0 + dream * swell * (0.5 + 0.5 * n));
	VERTEX += normalize(NORMAL) * grow;
}

void fragment() {
	ALBEDO = OUTPUT_IS_SRGB ? ink : to_linear(ink);
}
