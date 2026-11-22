// The port's sea (tools/build_port.py): the water as the sky laid flat, at the edge of
// the world (docs/MAP_PLAN.md). Nothing lights it. Every pixel is the evening sky it
// would mirror: blue-violet overhead, the pale orange low toward the sun, clouds drifting
// across a deck overhead, and a slow, broad swell that makes the whole reflection tremble.
// Only the normal moves; the plane stays flat. No vertex colours, no textures: the colours
// are uniforms, so `source_color` already hands them over in linear.
shader_type spatial;
render_mode unshaded;

uniform vec4 zenith : source_color = vec4(0.34, 0.38, 0.55, 1.0);
uniform vec4 horizon : source_color = vec4(0.7, 0.6, 0.66, 1.0);
uniform vec4 glow : source_color = vec4(0.98, 0.7, 0.46, 1.0);
uniform vec4 cloud : source_color = vec4(0.86, 0.76, 0.78, 1.0);
uniform vec4 deep : source_color = vec4(0.12, 0.14, 0.22, 1.0);
uniform vec2 sun_dir = vec2(-0.7, -0.7);
uniform float swell = 0.18;
uniform float cloud_height = 40.0;
uniform float cloud_scale = 0.02;
uniform float drift = 0.6;

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	// The swell: two long travelling waves and a short chop.
	vec2 slope = vec2(0.8, 0.6) * cos(dot(p, vec2(0.8, 0.6)) * 0.23 - t * 0.55) * 0.6;
	slope += vec2(-0.35, 0.94) * cos(dot(p, vec2(-0.35, 0.94)) * 0.41 - t * 0.8) * 0.35;
	slope += (vec2(fbm(p * 0.6 + t * 0.12), fbm(p * 0.6 - t * 0.1 + 31.0)) - 0.5) * 0.9;
	vec3 n = normalize(vec3(-slope.x * swell, 1.0, -slope.y * swell));
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 r = reflect(normalize(world_pos - eye), n);
	float up = clamp(r.y, 0.0, 1.0);
	vec3 sky = mix(horizon.rgb, zenith.rgb, smoothstep(0.02, 0.75, up));
	vec2 sun = normalize(sun_dir);
	float toward_sun = max(dot(normalize(r.xz + vec2(0.0001)), sun), 0.0);
	sky = mix(sky, glow.rgb, pow(toward_sun, 3.0) * (1.0 - smoothstep(0.0, 0.6, up)) * 0.8);
	// Clouds where the mirrored ray meets a deck `cloud_height` overhead: the sky laid flat.
	vec2 cp = p + r.xz / max(r.y, 0.12) * cloud_height;
	float c = smoothstep(0.48, 0.72, fbm(cp * cloud_scale + vec2(t * drift * cloud_scale, 0.0)));
	sky = mix(sky, mix(cloud.rgb, glow.rgb, toward_sun * 0.35), c * 0.7);
	// Faces of the swell turned from the sun go a little toward the deep water's colour.
	ALBEDO = mix(deep.rgb, sky, 0.86 + 0.14 * clamp(dot(slope, sun), -1.0, 1.0));
}
