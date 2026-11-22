shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec4 pigment : source_color = vec4(0.94, 0.90, 0.79, 1.0);

varying vec3 card_position;

float fleck(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float paper_noise(vec3 point) {
	vec3 cell = floor(point);
	vec3 f = smoothstep(vec3(0.0), vec3(1.0), fract(point));
	vec2 a = mix(vec2(fleck(cell), fleck(cell + vec3(0, 0, 1))),
		vec2(fleck(cell + vec3(1, 0, 0)), fleck(cell + vec3(1, 0, 1))), f.x);
	vec2 b = mix(vec2(fleck(cell + vec3(0, 1, 0)), fleck(cell + vec3(0, 1, 1))),
		vec2(fleck(cell + vec3(1, 1, 0)), fleck(cell + vec3(1, 1, 1))), f.x);
	return mix(mix(a.x, b.x, f.y), mix(a.y, b.y, f.y), f.z);
}

void vertex() {
	card_position = VERTEX;
}

void fragment() {
	float pulp = paper_noise(card_position * vec3(24.0, 10.0, 24.0));
	float wash = paper_noise(card_position * 1.6 + vec3(4.3, 0.7, 1.1));
	ALBEDO = pigment.rgb * (0.92 + 0.11 * pulp + 0.045 * wash);
	ROUGHNESS = 1.0;
}
