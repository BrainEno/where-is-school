shader_type canvas_item;
render_mode unshaded, blend_disabled;

// The trip inside the building under construction (scenes/locations/site_interior/), as a
// screen filter. `SiteTrip` (site_trip.gd) sets `trip`: a floor everywhere in the room, more
// the closer the protagonist stands to the column of light. Hidden at 0.
//
// It reads the finished frame (`hint_screen_texture`) and draws it back on a full-screen rect
// in a canvas layer under the outline and the UI, like the stable's stench and the concussion
// paste-up, so it needs no depth buffer, no extra viewport and no renderer feature.
//
// 1. The frame breathes: a slow lens swell and ripples running out from the middle.
// 2. Rainbow split: red, green and blue are read a little apart along the radius.
// 3. Kaleidoscope: at the margins a six-fold mirrored, turning copy of the picture folds in.
// 4. Colour drifts round the wheel, more toward the edges.
// 5. Contour lines of brightness, drawn in rainbow ink, as if the light had tide marks.
// 6. Saturation is pushed, and the corners fall into a violet dark that breathes.
//
// The middle of the frame is protected, so the protagonist, the path and the outline cue
// stay legible at full strength.
uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform float trip : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

const vec3 VIOLET = vec3(0.12, 0.02, 0.18);

vec3 palette(float t) {
	return 0.5 + 0.5 * cos(6.2831853 * (vec3(t) + vec3(0.0, 0.33, 0.67)));
}

vec3 hue_rotate(vec3 c, float angle) {
	vec3 k = vec3(0.57735);
	float ca = cos(angle);
	return c * ca + cross(k, c) * sin(angle) + k * dot(k, c) * (1.0 - ca);
}

void fragment() {
	float s = clamp(trip, 0.0, 1.0);
	float t = TIME;
	vec2 uv = SCREEN_UV;
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 to_uv = vec2(1.0 / aspect.x, 1.0);
	vec2 c = (uv - 0.5) * aspect;
	float r = length(c);
	vec2 dir = c / max(r, 0.0001);
	float edge = smoothstep(0.12, 0.62, r);
	float breath = sin(t * 0.7 + seed);

	vec2 warp = dir * (0.018 * breath * r * r + 0.006 * sin(r * 18.0 - t * 2.0)) * s * edge;
	vec2 split = dir * 0.006 * s * (0.4 + edge);
	vec2 at = uv + warp * to_uv;
	vec3 col = vec3(
		texture(screen, at + split * to_uv).r,
		texture(screen, at).g,
		texture(screen, at - split * to_uv).b
	);

	float seg = 6.2831853 / 6.0;
	float folded = abs(mod(atan(c.y, c.x) + t * 0.05, seg) - seg * 0.5);
	vec2 kp = vec2(cos(folded), sin(folded)) * r * 0.9;
	vec3 kal = texture(screen, clamp(kp * to_uv + 0.5, vec2(0.0), vec2(1.0))).rgb;
	col = mix(col, hue_rotate(kal, 2.1), smoothstep(0.42, 0.75, r) * 0.55 * s);

	col = mix(col, hue_rotate(col, t * 0.35 + r * 3.0), s * (0.25 + 0.5 * edge));

	float l = dot(col, vec3(0.299, 0.587, 0.114));
	float band = abs(fract(l * 7.0 - t * 0.15) - 0.5);
	float line = 1.0 - smoothstep(0.02, 0.06, band);
	col = mix(col, palette(l * 2.0 + t * 0.1), line * 0.35 * s * edge);

	col = mix(vec3(l), col, 1.0 + 0.45 * s);
	float dark = smoothstep(0.45 - 0.08 * breath * s, 1.0, r * 1.15);
	col = mix(col, VIOLET, dark * 0.7 * s);
	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
