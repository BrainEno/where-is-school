shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

// The stable yard's trodden earth (round 19, docs/EXAM_DREAM_ART.md). The relief is real
// geometry (tools/stable_ground.py) over the flat walking slab; this paints it as the same
// soil as the original playground shader at base d4f06f76: its mineral mottle and grit
// are kept here because the playground shader is being changed to concrete independently.
// `fill` retains the stable's existing low self-light under the dusk sky. The connector
// offsets its local plane coordinates to the same yard-local space as the relief mesh.
uniform float fill : hint_range(0.0, 1.0) = 0.5;
uniform vec2 ground_offset = vec2(0.0);

varying vec2 ground_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float grain(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), u.x), u.y);
}

void vertex() {
	ground_position = VERTEX.xz + ground_offset;
}

void fragment() {
	float mottle = grain(ground_position * 0.55);
	float grit = grain(ground_position * 28.0);
	vec3 earth = mix(vec3(0.27, 0.19, 0.13), vec3(0.50, 0.39, 0.28), mottle);
	earth *= 0.88 + 0.24 * grit;
	ALBEDO = earth;
	ROUGHNESS = 1.0;
	EMISSION = earth * fill;
}
