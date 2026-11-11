shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_back;

// Character model colors are authored per surface in the GLB. This material preserves
// those colors, adds only restrained pigment wobble, and intentionally has no outline pass.
uniform vec4 base_color : source_color = vec4(0.55, 0.46, 0.39, 1.0);
uniform vec3 base_uv_scale = vec3(1.0);
uniform vec3 base_uv_offset = vec3(0.0);
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_base_texture = false;
uniform float pigment_wobble : hint_range(0.0, 0.12, 0.001) = 0.018;
uniform float pigment_scale : hint_range(0.1, 8.0, 0.1) = 1.4;

varying vec3 world_position;

float hash33(vec3 p) {
	vec3 q = fract(p * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.x + q.y) * q.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 blend = fract(p);
	blend = blend * blend * (3.0 - 2.0 * blend);

	float x00 = mix(hash33(cell + vec3(0.0, 0.0, 0.0)), hash33(cell + vec3(1.0, 0.0, 0.0)), blend.x);
	float x10 = mix(hash33(cell + vec3(0.0, 1.0, 0.0)), hash33(cell + vec3(1.0, 1.0, 0.0)), blend.x);
	float x01 = mix(hash33(cell + vec3(0.0, 0.0, 1.0)), hash33(cell + vec3(1.0, 0.0, 1.0)), blend.x);
	float x11 = mix(hash33(cell + vec3(0.0, 1.0, 1.0)), hash33(cell + vec3(1.0, 1.0, 1.0)), blend.x);
	return mix(mix(x00, x10, blend.y), mix(x01, x11, blend.y), blend.z);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 pigment = base_color;
	if (use_base_texture) {
		vec2 base_uv = UV * base_uv_scale.xy + base_uv_offset.xy;
		pigment *= texture(base_texture, base_uv);
	}
	float variation = (value_noise(world_position * pigment_scale) - 0.5) * 2.0;
	ALBEDO = pigment.rgb * (1.0 + variation * pigment_wobble);
	ROUGHNESS = 0.96;
}
