shader_type canvas_item;
// The imagined lesson's screen filter (docs/IMAGINED_LESSON.md): the classroom, repainted
// for as long as the protagonist pictures teacher B, in the manner of Munch's The Scream.
//
// It reads the finished frame (`hint_screen_texture`, which every renderer this project
// ships on provides to a canvas item) and draws it back on a full-screen rect in a canvas
// layer under the dialogue UI, so nothing here needs a depth buffer, a second viewport or a
// renderer-specific feature. The room's own geometry, lights and ink lines stay: it is the
// same place, seen through a fever.
//
// 1. A vortex sits on the imagined teacher (`vortex`, in screen UV, set every frame
//    by the scene). The picture is wound round it, hardest in a ring around her; the eye
//    itself is calm, so she stays readable.
// 2. Bands: the contours of a field that is horizontal and undulating far from her (Munch's
//    sky over the fjord) and rings round her up close. The picture is pushed back and forth
//    across the bands in a travelling wave, and smeared along them in short strokes.
// 3. Value is mapped onto a Scream palette (night blue, fjord blue, bile green, blood,
//    orange, sulphur) with the band position added in, so the colours themselves run in
//    stripes, and the original colour is kept underneath (`palette_mix` < 1) so a desk is
//    still a desk. Inside the eye she keeps most of her own colours.
// 4. Edges get a thick, wavering ink, and the corners fall into night blue.
//
// `strength` and `reach` animate it in and out: the change spreads outwards from her head as
// a ring (`reach`, in aspect-corrected screen units) and recedes the same way.

uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float reach : hint_range(0.0, 2.5) = 2.5;
uniform vec2 vortex = vec2(0.6, 0.4);
uniform float swirl : hint_range(0.0, 6.0) = 1.1;
uniform float band_count : hint_range(2.0, 30.0) = 9.0;
uniform float wave_amplitude : hint_range(0.0, 0.05) = 0.006;
uniform float smear : hint_range(0.0, 0.03) = 0.005;
uniform float palette_mix : hint_range(0.0, 1.0) = 0.62;
uniform float ink : hint_range(0.0, 1.0) = 0.7;
uniform float time_scale : hint_range(0.0, 4.0) = 1.0;

const vec3 NIGHT = vec3(0.06, 0.07, 0.18);
const vec3 FJORD = vec3(0.13, 0.28, 0.50);
const vec3 BILE = vec3(0.34, 0.45, 0.30);
const vec3 BLOOD = vec3(0.80, 0.19, 0.10);
const vec3 ORANGE = vec3(0.95, 0.52, 0.14);
const vec3 SULPHUR = vec3(0.99, 0.87, 0.44);

vec3 scream_palette(float t) {
	float x = clamp(t, 0.0, 1.0) * 5.0;
	vec3 c = mix(NIGHT, FJORD, clamp(x, 0.0, 1.0));
	c = mix(c, BILE, clamp(x - 1.0, 0.0, 1.0));
	c = mix(c, BLOOD, clamp(x - 2.0, 0.0, 1.0));
	c = mix(c, ORANGE, clamp(x - 3.0, 0.0, 1.0));
	return mix(c, SULPHUR, clamp(x - 4.0, 0.0, 1.0));
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// The band field at `uv`: horizontal undulations, wound into rings near the vortex.
float band_field(vec2 uv, vec2 aspect, float t) {
	float sky = band_count * (uv.y
		+ 0.07 * sin(uv.x * 4.2 + t * 0.35)
		+ 0.025 * sin(uv.x * 9.1 - t * 0.5 + uv.y * 3.0));
	float r = length((uv - vortex) * aspect);
	float rings = r * band_count * 1.7 - t * 0.25;
	return mix(sky, rings, 0.6 * exp(-r * 4.0));
}

vec2 rotate(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float t = TIME * time_scale;
	vec2 p = (uv - vortex) * aspect;
	float r = length(p);
	float mask = (1.0 - smoothstep(reach - 0.3, reach, r)) * strength;

	// 1. The vortex. Its eye is calm: she is wound into the room, not unrecognisable, and
	// the room is bent, not turned over.
	float eye = smoothstep(0.1, 0.5, r);
	float angle = swirl * eye * exp(-r * 2.4) * (0.85 + 0.15 * sin(t * 0.7)) * mask;
	vec2 wound = vortex + rotate(p, angle) / aspect;

	// 2. Push across the bands, smear along them.
	float field = band_field(wound, aspect, t);
	vec2 e = vec2(0.002, 0.0);
	vec2 gradient = vec2(band_field(wound + e.xy, aspect, t) - field,
		band_field(wound + e.yx, aspect, t) - field);
	vec2 across = normalize(gradient + vec2(1.0e-6));
	vec2 along = vec2(-across.y, across.x);
	vec2 warped = wound + across * wave_amplitude * mask * mix(0.4, 1.0, eye) * sin(field * PI - t * 1.2);
	warped = clamp(warped, vec2(0.001), vec2(0.999));

	vec3 painted = vec3(0.0);
	float weight = 0.0;
	for (int i = -2; i <= 2; i++) {
		float k = float(i);
		float w = 1.0 - abs(k) * 0.2;
		painted += texture(screen, clamp(warped + along * smear * mask * k, vec2(0.001), vec2(0.999))).rgb * w;
		weight += w;
	}
	painted /= weight;

	// 3. The Scream palette, banded.
	float value = luma(painted);
	float stripes = sin(field * PI) * mix(0.25, 1.0, eye);
	vec3 scream = scream_palette(value * 0.92 + 0.11 * stripes + 0.04);
	// Her own expressionist colours keep the eye; the room around her takes the palette.
	vec3 colour = mix(painted, scream, palette_mix * mask * mix(0.3, 1.0, eye));
	colour *= 1.0 + 0.1 * stripes * mask;

	// 4. Ink on the edges, night in the corners.
	vec2 px = SCREEN_PIXEL_SIZE * 1.6;
	float gx = luma(texture(screen, warped + vec2(px.x, 0.0)).rgb) - luma(texture(screen, warped - vec2(px.x, 0.0)).rgb);
	float gy = luma(texture(screen, warped + vec2(0.0, px.y)).rgb) - luma(texture(screen, warped - vec2(0.0, px.y)).rgb);
	float edge = smoothstep(0.06, 0.24, length(vec2(gx, gy)) * (0.8 + 0.4 * sin(field * 2.1 + t)));
	colour = mix(colour, NIGHT, edge * ink * mask);
	float corner = smoothstep(0.55, 1.2, length((uv - vec2(0.5)) * aspect * 1.15));
	colour = mix(colour, NIGHT, corner * 0.45 * mask);

	// The front of the change, while it spreads or recedes.
	float front = exp(-pow((r - reach) / 0.025, 2.0)) * strength * (1.0 - step(2.2, reach));
	colour = mix(colour, ORANGE, front * 0.6);

	COLOR = vec4(clamp(colour, vec3(0.0), vec3(1.0)), 1.0);
}
