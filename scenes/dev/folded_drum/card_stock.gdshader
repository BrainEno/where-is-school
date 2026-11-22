shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// A stock colour is not a photo: all grain is in the surface's own 3D coordinates.
uniform vec4 pigment : source_color = vec4(0.85, 0.79, 0.68, 1.0);
uniform int stock_kind : hint_enum("Card", "Mineral", "Painted foil") = 0;
uniform float grain_strength : hint_range(0.0, 1.5) = 1.0;
uniform float relief : hint_range(0.0, 0.04) = 0.013;
uniform float exposed_bias : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dark_coat : source_color = vec4(0.105, 0.115, 0.125, 1.0);

varying vec3 stock_position;

// Turn the grain off the model axes, so a folded face never samples a row of the lattice.
const mat3 GRAIN_AXES = mat3(vec3(0.80, 0.60, 0.0), vec3(-0.48, 0.64, 0.60), vec3(0.36, -0.48, 0.80));

float fleck(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float stock_noise(vec3 point) {
	vec3 cell = floor(point);
	vec3 f = smoothstep(vec3(0.0), vec3(1.0), fract(point));
	vec2 a = mix(vec2(fleck(cell), fleck(cell + vec3(0, 0, 1))),
		vec2(fleck(cell + vec3(1, 0, 0)), fleck(cell + vec3(1, 0, 1))), f.x);
	vec2 b = mix(vec2(fleck(cell + vec3(0, 1, 0)), fleck(cell + vec3(0, 1, 1))),
		vec2(fleck(cell + vec3(1, 1, 0)), fleck(cell + vec3(1, 1, 1))), f.x);
	return mix(mix(a.x, b.x, f.y), mix(a.y, b.y, f.y), f.z);
}

// Tiny hollows at jittered lattice corners. The radius plus the maximum jitter
// is less than one cell, so only the eight corners around the sample can contribute.
float stock_pores(vec3 point) {
	vec3 cell = floor(point);
	vec3 f = fract(point);
	float pore = 0.0;
	for (int i = 0; i < 8; i++) {
		vec3 corner = vec3(float(i & 1), float((i >> 1) & 1), float(i >> 2));
		vec3 seed = (cell + corner) * 0.87;
		vec3 jitter = vec3(fleck(seed), fleck(seed + 29.7), fleck(seed + 53.8));
		vec3 to_pore = f - corner - (jitter - 0.5) * 0.69;
		float radius = mix(0.18, 0.43, jitter.y * jitter.y);
		float bowl = 1.0 - smoothstep(0.0, radius * radius, dot(to_pore, to_pore));
		pore = max(pore, bowl * mix(0.43, 1.0, jitter.x));
	}
	return pore;
}

// Fade the finest grain once a pixel covers more than a fibre width.
float coverage(vec3 p) {
	vec3 pixel = fwidth(p);
	return 1.0 - smoothstep(0.72, 1.85, max(pixel.x, max(pixel.y, pixel.z)));
}

// Surface-gradient bump from the view-space position, independent of UV seams/tangents.
vec3 grain_normal(vec3 n, vec3 position, float height) {
	vec3 dx = dFdx(position);
	vec3 dy = dFdy(position);
	vec3 u = cross(dy, n);
	vec3 v = cross(n, dx);
	float det = dot(dx, u);
	vec3 gradient = sign(det) * (dFdx(height) * u + dFdy(height) * v);
	return normalize(max(abs(det), 0.0000001) * n - gradient);
}

void vertex() {
	stock_position = VERTEX;
}

void fragment() {
	vec3 p = stock_position;
	if (stock_kind == 2) {
		// Rolled, blackened foil: noisy paint breaks, axial scuffs and a shallow crimp,
		// contrasted with exposed tin. The shine itself comes from the scene lights/sky.
		vec2 radial = normalize(p.xz + vec2(0.0001));
		vec3 scratches = p * vec3(46.0, 3.2, 41.0);
		float scuff = (stock_noise(scratches) - 0.5) * coverage(scratches);
		float hammer = stock_noise(GRAIN_AXES * (p * vec3(14.5, 11.0, 14.5)));
		float wrinkle = 1.0 - abs(2.0 * stock_noise(GRAIN_AXES * p * 8.3) - 1.0);
		float tear = stock_noise(p * vec3(5.9, 4.7, 5.9));
		float exposed = smoothstep(0.39, 0.62, dot(radial, vec2(0.93, 0.37))
			+ 0.57 * (tear - 0.5) + 0.17 * scuff + exposed_bias);
		float seam = smoothstep(0.994, 0.9995, dot(radial, vec2(0.91, 0.4146))) * (1.0 - exposed_bias);
		vec3 tin = pigment.rgb * (0.76 + 0.53 * hammer + 0.20 * scuff);
		ALBEDO = mix(dark_coat.rgb * (0.79 + 0.44 * tear), tin, exposed) * (1.0 - seam * 0.23);
		METALLIC = mix(0.32, 0.72, exposed);
		ROUGHNESS = mix(0.56, 0.28, exposed) + 0.15 * hammer + 0.085 * scuff;
		SPECULAR = 0.61;
		NORMAL = grain_normal(NORMAL, VERTEX,
			relief * (0.57 * hammer + 0.38 * wrinkle + 0.25 * scuff - 0.22 * seam));
	} else {
		bool mineral = stock_kind == 1;
		vec3 q = GRAIN_AXES * p;
		vec3 mid = q * (mineral ? vec3(18.5) : vec3(17.0, 27.0, 22.0));
		vec3 fine = GRAIN_AXES * mid * vec3(3.07, 1.85, 2.51);
		vec3 pits = q * (mineral ? vec3(24.0, 23.0, 26.0) : vec3(30.0, 46.0, 38.0));
		float cloud = stock_noise(q * 2.8 + vec3(4.3, 0.7, 1.1)) - 0.5;
		float pulp = (stock_noise(mid) - 0.5) * coverage(mid);
		float grit = (stock_noise(fine + vec3(5.0, 1.0, 7.0)) - 0.5) * coverage(fine);
		float pinholes = stock_pores(pits + 11.4) * coverage(pits);
		float tint = 1.0 + grain_strength * (pulp * 0.23 + grit * 0.44
			- pinholes * (mineral ? 0.37 : 0.27) + cloud * (mineral ? 0.23 : 0.16));
		ALBEDO = pigment.rgb * tint;
		NORMAL = grain_normal(NORMAL, VERTEX,
			relief * (0.56 * pulp + 0.29 * grit - 0.29 * pinholes));
		AO = 1.0 - grain_strength * pinholes * 0.12;
		ROUGHNESS = 0.92 + pinholes * 0.07;
		SPECULAR = 0.18;
	}
}
