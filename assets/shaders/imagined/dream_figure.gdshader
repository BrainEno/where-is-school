shader_type spatial;
// The imagined teacher B's surface (docs/IMAGINED_LESSON.md).
//
// The classroom paints her colleagues with character_paint.gdshader: three light bands, the
// GLB's own vertex colours, a quiet pigment. In the protagonist's head she keeps those
// colours' *places* but not their values, in the expressionist manner of the PR #196
// colour-field room and the PR #200 cut-paper figures:
//
// - every vertex colour is turned round the colour wheel (`hue_turn`) and saturated
//   (`saturation_gain`): her warm skin goes sulphur-green, the olive blouse goes teal, the
//   charcoal wool stays the darkest thing on her;
// - light is two flat steps on a fixed painted direction, not the room's lamps, so she
//   stays as loud in a dim corner as under a fitting, and the shadow step is a deep
//   ultramarine field rather than a darker copy of the colour;
// - bands like the strokes of Munch's sky run round her body in her bind-pose space and
//   drift upwards, so they stay on her while she moves;
// - a vermilion rim burns where her form turns away from the eye;
// - `echo` = 1 flattens all of it to a single ink colour with faint bands: the after-images
//   of her standing at the front of the room.
//
// Colour is worked in sRGB, the space the palette was chosen in, and decoded only at the
// end on the renderers that shade in linear (Forward+, Mobile). Unshaded: no lamp, no
// specular, nothing for a highlight to slide on.
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://assets/shaders/imagined/dream_figure.gdshaderinc"

uniform float hue_turn : hint_range(-0.5, 0.5) = 0.16;
uniform float saturation_gain : hint_range(0.5, 4.0) = 2.2;
// sRGB, not `source_color`: see above.
uniform vec3 shade_color = vec3(0.12, 0.16, 0.42);
uniform vec3 rim_color = vec3(0.93, 0.27, 0.10);
uniform vec3 stripe_color = vec3(0.98, 0.64, 0.18);
uniform float stripe_strength : hint_range(0.0, 1.0) = 0.42;
uniform float stripe_scale : hint_range(1.0, 30.0) = 7.5;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.8;
// The painted light, in view space.
uniform vec3 light_direction = vec3(-0.45, 0.6, 0.66);
uniform float echo : hint_range(0.0, 1.0) = 0.0;
uniform vec3 echo_color = vec3(0.09, 0.08, 0.16);

varying vec3 rest_position;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

vec3 to_srgb(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(vec3(1.055) * pow(c, vec3(1.0 / 2.4)) - vec3(0.055), c * 12.92,
		lessThanEqual(c, vec3(0.0031308)));
}

vec3 to_linear(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / 12.92,
		lessThanEqual(c, vec3(0.04045)));
}

void vertex() {
	// The bind-pose position, when the mesh carries one (`CharacterLookApplier`'s CUSTOM0,
	// w = 2), so the bands stay on the cloth while she moves.
	rest_position = CUSTOM0.w > 1.5 ? CUSTOM0.xyz : VERTEX;
	VERTEX = dream_shape(VERTEX, TIME);
}

void fragment() {
	vec3 hsv = rgb_to_hsv(to_srgb(COLOR.rgb));
	float turn = hue_turn * dream;
	hsv.x = fract(hsv.x + turn);
	hsv.y = clamp(hsv.y * mix(1.0, saturation_gain, dream) + 0.12 * dream, 0.0, 1.0);
	hsv.z = clamp(hsv.z * mix(1.0, 1.15, dream), 0.0, 1.0);
	vec3 base = hsv_to_rgb(hsv);

	float ndl = dot(normalize(NORMAL), normalize(light_direction));
	float lit = smoothstep(-0.12, -0.06, ndl);
	float high = smoothstep(0.52, 0.58, ndl);
	vec3 colour = mix(mix(shade_color, base * 0.55, 0.35), base, lit);
	colour = mix(colour, mix(base, vec3(1.0, 0.95, 0.8), 0.25), high * 0.6);

	float field = rest_position.y * stripe_scale
		+ 0.35 * sin(rest_position.x * 9.0 + TIME * 0.8)
		+ 0.25 * sin(rest_position.z * 11.0 - TIME * 0.6);
	float band = abs(fract(field - TIME * 0.15) - 0.5);
	float stripe = 1.0 - smoothstep(0.08, 0.14, band);
	colour = mix(colour, mix(stripe_color, shade_color, 1.0 - lit), stripe * stripe_strength * dream);

	float rim = pow(1.0 - clamp(abs(dot(normalize(NORMAL), VIEW)), 0.0, 1.0), 2.5);
	colour = mix(colour, rim_color, rim * rim_strength * dream);

	vec3 echo_paint = echo_color * (1.0 + 0.6 * stripe) + rim_color * rim * 0.25;
	colour = mix(colour, echo_paint, echo);

	ALBEDO = OUTPUT_IS_SRGB ? clamp(colour, vec3(0.0), vec3(1.0)) : to_linear(colour);
}
