// Shared by the character art review shaders (issue #188, development only).
// The same value noise and rest-pose coordinates as the production
// `assets/shaders/characters/character_paint.gdshader`, re-declared here so the experiments
// never include, edit or depend on a production shader file.

float review_hash31(vec3 p) {
	vec3 q = fract(p * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.x + q.y) * q.z);
}

float review_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	float x00 = mix(review_hash31(cell), review_hash31(cell + vec3(1.0, 0.0, 0.0)), t.x);
	float x10 = mix(review_hash31(cell + vec3(0.0, 1.0, 0.0)), review_hash31(cell + vec3(1.0, 1.0, 0.0)), t.x);
	float x01 = mix(review_hash31(cell + vec3(0.0, 0.0, 1.0)), review_hash31(cell + vec3(1.0, 0.0, 1.0)), t.x);
	float x11 = mix(review_hash31(cell + vec3(0.0, 1.0, 1.0)), review_hash31(cell + vec3(1.0, 1.0, 1.0)), t.x);
	return mix(mix(x00, x10, t.y), mix(x01, x11, t.y), t.z);
}

float review_fbm2(vec3 p) {
	return review_noise(p) * 0.66 + review_noise(p * 2.31 + vec3(7.1, 3.3, 11.9)) * 0.34;
}

// The vertex's bind-pose position when `CharacterLookApplier` has rebuilt the mesh with
// one (CUSTOM0.w == 2), otherwise the object-space position (the protagonist's head).
vec3 review_rest_position(vec4 custom0, vec3 vertex) {
	return custom0.w > 1.5 ? custom0.xyz : vertex;
}

// An ellipsoid patch with a broken edge, mirrored across x = mirror_x when asked.
float review_patch(vec3 p, vec3 center, vec3 radius, float noise, bool mirror, float mirror_x) {
	if (radius.x <= 0.0 || radius.y <= 0.0 || radius.z <= 0.0) {
		return 0.0;
	}
	vec3 q = p;
	if (mirror) {
		q.x = mirror_x + abs(q.x - mirror_x);
	}
	float d = length((q - center) / radius);
	return 1.0 - smoothstep(0.7, 0.92, d + (noise - 0.5) * 0.5);
}
