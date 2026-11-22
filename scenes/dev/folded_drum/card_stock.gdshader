shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// A stock colour is not a photo: all grain is in the surface's own 3D coordinates.
uniform vec4 pigment : source_color = vec4(0.85, 0.79, 0.68, 1.0);
uniform int stock_kind : hint_enum("Card", "Mineral", "Painted foil") = 0;
uniform float grain_strength : hint_range(0.0, 1.5) = 1.0;
uniform float relief : hint_range(0.0, 0.04) = 0.013;
uniform vec4 dark_coat : source_color = vec4(0.105, 0.115, 0.125, 1.0);

varying vec3 stock_position;

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
		float scuff = stock_noise(p * vec3(39.0, 3.0, 36.0));
		float hammer = stock_noise(p * vec3(14.0, 21.0, 14.0));
		float tear = stock_noise(p * vec3(8.0, 6.0, 8.0));
		float exposed = smoothstep(0.45, 0.59,
			dot(radial, vec2(0.93, 0.37)) + 0.27 * (tear - 0.5) + 0.14 * (scuff - 0.5));
		float seam = smoothstep(0.994, 0.9995, dot(radial, vec2(0.91, 0.4146)));
		vec3 tin = pigment.rgb * (0.66 + 0.39 * hammer + 0.19 * scuff);
		ALBEDO = mix(dark_coat.rgb * (0.84 + 0.31 * tear), tin, exposed) * (1.0 - seam * 0.25);
		METALLIC = mix(0.32, 0.69, exposed);
		ROUGHNESS = mix(0.52, 0.32, exposed) + scuff * 0.13;
		SPECULAR = 0.62;
		NORMAL = grain_normal(NORMAL, VERTEX, relief * (0.54 * hammer + 0.27 * scuff - 0.22 * seam));
	} else {
		bool mineral = stock_kind == 1;
		vec3 mid = p * (mineral ? vec3(15.3) : vec3(18.0, 26.0, 20.0));
		vec3 fine = p * (mineral ? vec3(57.0) : vec3(36.0, 73.0, 43.0));
		float mottling = stock_noise(p * 2.6 + vec3(4.3, 0.7, 1.1));
		float pulp = (stock_noise(mid) - 0.5) * coverage(mid);
		float grain = (stock_noise(fine + vec3(5.0, 1.0, 7.0)) - 0.5) * coverage(fine);
		float pinholes = smoothstep(0.16, 0.40, abs(pulp - grain * 0.31));
		float tint = 1.0 + grain_strength * (pulp * 0.39 + grain * 0.29 - pinholes * 0.32
			+ (mottling - 0.5) * (mineral ? 0.27 : 0.14));
		ALBEDO = pigment.rgb * tint;
		NORMAL = grain_normal(NORMAL, VERTEX,
			relief * (0.67 * pulp + 0.25 * grain - 0.28 * pinholes));
		AO = 1.0 - grain_strength * pinholes * 0.20;
		ROUGHNESS = 0.94 + pinholes * 0.05;
		SPECULAR = 0.18;
	}
}
