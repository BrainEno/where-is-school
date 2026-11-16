// Visual experiments lab only (scenes/dev/ is excluded from every export preset).
//
// The medium switch. Past the threshold the 3D camera no longer draws to the screen; it
// draws into a half-resolution SubViewport, and this CanvasItem shader turns that texture
// into a painting on a sheet of paper: smeared along a stroke field, banded into a few
// values, inked at the edges, laid slightly crooked on a paper mount. `reveal` tears the
// painting in from the left, so the change of medium is something seen happening.
//
// It reads only its own TEXTURE (the SubViewport) — no screen texture, no depth — so the
// same code runs on Forward+, Mobile and Compatibility.
shader_type canvas_item;

uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float posterize_levels = 6.0;
uniform float stroke_length = 0.006;
uniform float ink_strength = 0.85;
uniform float mount_tilt = 0.018;
uniform float mount_scale = 1.07;
uniform vec4 paper_color : source_color = vec4(0.9, 0.86, 0.76, 1.0);
uniform vec4 ink_color : source_color = vec4(0.12, 0.1, 0.12, 1.0);
uniform vec2 texel = vec2(1.0 / 800.0, 1.0 / 450.0);
uniform float screen_aspect = 1.7778;

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

float luminance(vec3 colour) {
	return dot(colour, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 centred = UV - 0.5;
	centred.x *= screen_aspect;
	float c = cos(mount_tilt);
	float s = sin(mount_tilt);
	vec2 rotated = vec2(c * centred.x - s * centred.y, s * centred.x + c * centred.y);
	rotated.x /= screen_aspect;
	vec2 picture_uv = rotated * mount_scale + 0.5;
	vec3 colour;
	bool inside = picture_uv.x > 0.0 && picture_uv.x < 1.0 && picture_uv.y > 0.0 && picture_uv.y < 1.0;
	if (inside) {
		// Stroke direction from a slow noise field: short, mostly diagonal dabs.
		float angle = value_noise(picture_uv * vec2(6.0 * screen_aspect, 6.0)) * 3.1416 + 0.6;
		vec2 direction = vec2(cos(angle), sin(angle)) * stroke_length;
		vec3 sum = vec3(0.0);
		for (int i = -3; i <= 3; i++) {
			sum += texture(TEXTURE, picture_uv + direction * float(i)).rgb;
		}
		colour = sum / 7.0;
		// Lift the saturation a little before banding, so the bands are colours, not greys.
		float grey = luminance(colour);
		colour = clamp(mix(vec3(grey), colour, 1.35), 0.0, 1.0);
		colour = floor(colour * posterize_levels + 0.5) / posterize_levels;
		// Ink where the value changes sharply (a four-tap Sobel on luminance).
		float l = luminance(texture(TEXTURE, picture_uv - vec2(texel.x, 0.0)).rgb);
		float r = luminance(texture(TEXTURE, picture_uv + vec2(texel.x, 0.0)).rgb);
		float t = luminance(texture(TEXTURE, picture_uv - vec2(0.0, texel.y)).rgb);
		float b = luminance(texture(TEXTURE, picture_uv + vec2(0.0, texel.y)).rgb);
		float edge = smoothstep(0.08, 0.22, length(vec2(r - l, b - t)));
		colour = mix(colour, ink_color.rgb, edge * ink_strength);
		// Canvas tooth.
		float tooth = value_noise(picture_uv * vec2(420.0 * screen_aspect, 420.0)) - 0.5;
		colour *= 1.0 + tooth * 0.1;
	} else {
		// The mount: paper, with a soft shadow just outside the picture.
		vec2 outside = max(-picture_uv, picture_uv - 1.0);
		float distance_out = length(max(outside, 0.0));
		float shadow = 1.0 - smoothstep(0.0, 0.025, distance_out);
		float fibres = value_noise(UV * vec2(300.0, 60.0)) * 0.08;
		colour = paper_color.rgb * (0.94 + fibres) * (1.0 - shadow * 0.35);
	}
	// The tear that brings the painting in: a ragged vertical edge sweeping left to right.
	float ragged = (value_noise(vec2(UV.y * 18.0, 3.0)) - 0.5) * 0.08
		+ (value_noise(vec2(UV.y * 90.0, 7.0)) - 0.5) * 0.02;
	float front = reveal * 1.2 - 0.1;
	float shown = step(UV.x + ragged, front);
	vec3 raw = texture(TEXTURE, UV).rgb;
	float fibre_band = shown * (1.0 - step(UV.x + ragged, front - 0.012));
	colour = mix(raw, colour, shown);
	colour = mix(colour, vec3(0.97, 0.96, 0.92), fibre_band);
	COLOR = vec4(colour, 1.0);
}
