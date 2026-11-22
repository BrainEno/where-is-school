shader_type canvas_item;
render_mode unshaded, blend_disabled;

// The smell of the stable behind 01, made visible (docs/EXAM_DREAM_ART.md): a yellow-green
// screen filter that thickens as the protagonist walks toward the stalls and the muck heap,
// as if he were being knocked out by it. `StenchHaze` (scenes/locations/corridor/stench_haze.gd)
// sets `stench` from his distance; at 0 the layer is hidden and costs nothing.
//
// It reads the finished frame (`hint_screen_texture`, which Forward+, Mobile and
// Compatibility all give a canvas item) and draws it back on a full-screen rect in a canvas
// layer under the outline and the UI - the same arrangement as the concussion paste-up and the
// imagined lesson - so it needs no depth buffer, no extra viewport and no renderer feature.
//
// 1. The air wobbles in slow rising waves, hardest at the edges of the frame.
// 2. Seeing double: a ghost of the frame drifts on a slow circle, and every few seconds a
//    swoon pushes it further out and brings it back.
// 3. The colour is printed as a two-plate riso in olive ink, bile, acid green and mustard,
//    over a general yellow-green cast: the filter is the smell's colour.
// 4. Stink contours: the iso-lines of a field drifting upward, drawn in acid green, with
//    halftone dots in the margins - the comic-book way of drawing a smell, pasted over the world.
// 5. The corners fall into olive dark that breathes in and out.
//
// The middle of the frame is protected, so the protagonist, the path and the outline cue
// stay legible at full strength.
uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform float stench : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

const vec3 OLIVE_INK = vec3(0.12, 0.14, 0.06);
const vec3 BILE = vec3(0.46, 0.56, 0.14);
const vec3 ACID = vec3(0.78, 0.88, 0.24);
const vec3 MUSTARD = vec3(0.98, 0.85, 0.38);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

void fragment() {
	float s = clamp(stench, 0.0, 1.0) * 0.18;
	float t = TIME;
	vec2 uv = SCREEN_UV;
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 c = (uv - 0.5) * aspect;
	float edge = smoothstep(0.1, 0.6, length(c));
	float reach = mix(0.3, 1.0, edge);
	float swoon = pow(0.5 + 0.5 * sin(t * 0.83 + seed), 6.0);

	vec2 wave = vec2(sin(uv.y * 11.0 - t * 1.1 + sin(uv.x * 5.0 + t * 0.4) * 1.6), cos(uv.x * 8.0 + t * 0.8));
	uv += wave * 0.0055 * s * reach * (1.0 + swoon);
	vec2 drift = vec2(cos(t * 0.41), sin(t * 0.33)) * 0.011 * s * reach * (1.0 + 1.8 * swoon);
	vec3 base = texture(screen, uv).rgb;
	vec3 ghost = texture(screen, uv + drift).rgb;
	vec3 col = mix(base, ghost, (0.32 + 0.18 * swoon) * s);

	float l = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 plate = mix(OLIVE_INK, BILE, smoothstep(0.13, 0.17, l));
	plate = mix(plate, ACID, smoothstep(0.33, 0.37, l));
	plate = mix(plate, MUSTARD, smoothstep(0.6, 0.64, l));
	vec3 cast = col * vec3(0.94, 1.0, 0.52) + vec3(0.035, 0.045, 0.0);
	col = mix(col, cast, s);
	col = mix(col, plate * (0.62 + 0.55 * l), s * (0.26 + 0.34 * edge));

	vec2 field = c * 3.2 + vec2(seed, -t * 0.16);
	float f = value_noise(field) + 0.5 * value_noise(c * 7.0 + vec2(-t * 0.1, seed + 3.0));
	float band = abs(fract(f * 4.5 - t * 0.04) - 0.5);
	float contour = 1.0 - smoothstep(0.018, 0.045, band);
	col = mix(col, ACID * 1.06, contour * s * 0.5 * edge);

	vec2 grid = mat2(vec2(0.966, -0.259), vec2(0.259, 0.966)) * FRAGCOORD.xy / 7.0;
	float radius = 0.36 * edge * edge * s;
	float dot_ink = 1.0 - smoothstep(radius - 0.08, radius + 0.08, length(fract(grid) - 0.5));
	col = mix(col, MUSTARD * 0.82, dot_ink * 0.3 * step(0.01, radius));

	float breath = 0.5 + 0.5 * sin(t * 0.9);
	float dark = smoothstep(0.42 - 0.1 * breath * s, 0.95, length(c) * 1.12);
	col = mix(col, OLIVE_INK, dark * s * 0.72);
	COLOR = vec4(col, 1.0);
}
