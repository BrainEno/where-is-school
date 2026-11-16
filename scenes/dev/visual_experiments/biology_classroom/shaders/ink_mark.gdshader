// Biology classroom experiment only (scenes/dev/ is excluded from every export preset).
//
// A mark painted onto the room rather than built in it: the shadow on the front wall that
// no one casts, the set square's long shadow on the floor, the red pencil ring, the chalk
// ghosts on the board, the outline of a book that is not there. Unshaded on purpose: a
// painted shadow does not answer the real light.
//
// `amount` brings the mark in, three ways (`mode`):
//   0  grows up from the bottom edge, with a ragged front (a shadow rising up a wall)
//   1  is drawn round the centre, like a pencil going round (the ring)
//   2  simply fades
// Alpha-blended, depth-tested, never writing depth; same code on all three renderers.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D mark : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 tint : source_color = vec4(0.17, 0.12, 0.26, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform int mode = 0;
uniform float seed = 0.0;

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

void fragment() {
	vec4 sampled = texture(mark, UV);
	float shown = 1.0;
	float alpha = sampled.a * tint.a * opacity;
	if (mode == 0) {
		float height = 1.0 - UV.y;
		float ragged = (value_noise(vec2(UV.x * 16.0 + seed, 3.0)) - 0.5) * 0.1;
		shown = step(height + ragged, amount * 1.12 - 0.04);
	} else if (mode == 1) {
		vec2 centred = UV - 0.5;
		float turn = atan(centred.y, centred.x) / 6.28318 + 0.5;
		shown = step(turn, amount);
	} else {
		alpha *= amount;
	}
	ALBEDO = tint.rgb * sampled.rgb;
	ALPHA = alpha * shown;
}
