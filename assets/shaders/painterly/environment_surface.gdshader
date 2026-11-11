shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_back;

// Shared by environment meshes only. The scene-local base_color is copied from each
// source StandardMaterial3D so one ShaderMaterial can preserve authored color blocks.
uniform vec4 base_color : source_color = vec4(0.52, 0.45, 0.35, 1.0);
uniform vec3 base_uv_scale = vec3(1.0);
uniform vec3 base_uv_offset = vec3(0.0);
uniform vec4 shadow_pigment : source_color = vec4(0.25, 0.29, 0.25, 1.0);
uniform vec4 highlight_pigment : source_color = vec4(0.78, 0.61, 0.39, 1.0);
uniform vec4 brush_pigment : source_color = vec4(0.37, 0.24, 0.21, 1.0);
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_base_texture = false;
uniform int style_level : hint_range(1, 2) = 1;
uniform float patch_scale : hint_range(0.08, 6.0, 0.01) = 0.72;
uniform float patch_strength : hint_range(0.0, 1.0, 0.01) = 0.24;
uniform float brush_scale : hint_range(0.2, 12.0, 0.1) = 2.4;
uniform float brush_strength : hint_range(0.0, 1.0, 0.01) = 0.12;

varying vec3 world_position;
varying vec3 world_normal;

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
	vec4 world_vertex = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_position = world_vertex.xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec4 pigment = base_color;
	if (use_base_texture) {
		vec2 base_uv = UV * base_uv_scale.xy + base_uv_offset.xy;
		pigment *= texture(base_texture, base_uv);
	}

	vec3 color_mass = pigment.rgb;
	if (style_level >= 1) {
		float broad_field = value_noise(world_position * patch_scale);
		float edge_field = value_noise(world_position * patch_scale * 0.37 + vec3(17.3, 4.1, 9.7));
		float uneven_field = broad_field + (edge_field - 0.5) * 0.18;
		float patch = smoothstep(0.43, 0.58, uneven_field);
		vec3 patch_color = mix(shadow_pigment.rgb, highlight_pigment.rgb, patch);
		color_mass = mix(color_mass, patch_color, patch_strength);
	}

	if (style_level >= 2 && brush_strength > 0.0) {
		vec3 normal_weight = abs(normalize(world_normal));
		vec2 brush_position = world_position.xz;
		if (normal_weight.x > normal_weight.y && normal_weight.x > normal_weight.z) {
			brush_position = world_position.zy;
		} else if (normal_weight.z > normal_weight.y) {
			brush_position = world_position.xy;
		}

		float row = floor(brush_position.y * brush_scale);
		float stroke_jitter = value_noise(vec3(brush_position.x * brush_scale * 0.38, row * 0.31, 2.7));
		float stroke_phase = fract(brush_position.y * brush_scale + stroke_jitter * 0.16);
		float stroke_edge = min(stroke_phase, 1.0 - stroke_phase);
		float stroke = 1.0 - smoothstep(0.035, 0.095, stroke_edge);
		float broken_ink = smoothstep(0.28, 0.66, value_noise(world_position * brush_scale * 0.43 + vec3(3.0, 11.0, 5.0)));
		float brush_mask = stroke * broken_ink;
		color_mass = mix(color_mass, brush_pigment.rgb, brush_mask * brush_strength);
	}

	ALBEDO = color_mass;
	ROUGHNESS = 0.96;
}
