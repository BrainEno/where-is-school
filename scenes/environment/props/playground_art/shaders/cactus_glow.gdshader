shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap;

// The saguaro and the skipping girl in the cactus plot (round 20, source/cactus_plot.py).
// The yard is kept in its blue dusk; these two are lit as if it were still broad day, so
// they are the brightest things in the frame (the owner's brief: Magritte's Empire of
// Light). The colour is the mesh's sRGB vertex colour, which carries the painted detail
// and an ambient-occlusion estimate. On top of the engine's own light, a key light of the
// material's own, from the upper left of the yard's camera (the south-west), is added as
// emission: a lit side, a turned-away side that still holds its colour, and a soft rim.
uniform float glow : hint_range(0.0, 3.0) = 0.9;
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
uniform float sheen : hint_range(0.0, 1.0) = 0.3;
uniform vec3 key_direction = vec3(-0.55, 0.62, 0.56);

varying vec3 world_normal;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 colour = to_linear(COLOR.rgb);
	vec3 n = normalize(world_normal);
	float key = dot(n, normalize(key_direction));
	float day = 0.32 + 0.68 * smoothstep(-0.35, 0.85, key);
	ALBEDO = colour;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.25;
	RIM = sheen;
	RIM_TINT = 0.6;
	EMISSION = colour * glow * day;
}
