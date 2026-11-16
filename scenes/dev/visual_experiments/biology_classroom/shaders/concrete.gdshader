// Biology classroom experiment only (scenes/dev/ is excluded from every export preset).
//
// Poured concrete, made entirely in the shader from world position (no texture, so it never
// tiles): large blotches where the pour cured unevenly, drifting between a cool blue-green
// grey and a warm ochre grey; a cloudy middle scale; fine grain; exposed aggregate (small
// stones, dark and pale); air pores; saw-cut joints that do not quite run straight.
//
// Two things a school floor would not have, for the room's strangeness:
//
//   ruled_lines   the floor was poured against an answer sheet: faint ruled grooves run
//                 across it, broken where they wore away, with one red margin line
//   formwork      vertical faces carry the imprint of the boards they were cast in
//                 (the lectern): plank by plank, each a slightly different tone
//
// The light is the room's (two-step terminator, ambient-coloured shade), and the room's
// registers act on it exactly as on `room_tone.gdshader`: chill, dull, focus.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.55, 0.54, 0.52, 1.0);
uniform vec4 warm_color : source_color = vec4(0.63, 0.53, 0.43, 1.0);
uniform vec4 cool_color : source_color = vec4(0.4, 0.47, 0.49, 1.0);
uniform vec4 aggregate_dark : source_color = vec4(0.22, 0.21, 0.23, 1.0);
uniform vec4 aggregate_light : source_color = vec4(0.85, 0.82, 0.75, 1.0);
uniform vec4 margin_color : source_color = vec4(0.74, 0.3, 0.27, 1.0);
uniform float mottling = 0.6;
uniform float cloud = 0.22;
uniform float grain = 0.16;
uniform float aggregate_density = 0.3;
uniform float pores = 0.6;
uniform float joint_spacing = 2.3;
uniform float ruled_lines = 0.0;
uniform float ruled_spacing = 0.62;
uniform float margin_x = -6.2;
uniform float formwork = 0.0;
uniform float terminator = 0.12;
uniform float softness = 0.03;
uniform float light_gain = 1.0;
uniform float chill : hint_range(0.0, 1.0) = 0.0;
uniform float dull : hint_range(0.0, 1.0) = 0.0;
uniform vec3 focus_point = vec3(0.0, 0.0, 0.0);
uniform float focus_amount : hint_range(0.0, 1.0) = 0.0;
uniform float focus_radius = 3.0;

varying vec3 world_position;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.103, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
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

float fbm(vec2 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		sum += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return sum;
}

// Nearest feature point of a jittered grid: x = distance, y = that cell's random id.
vec2 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 point = hash22(i + offset);
			float d = length(offset + point - f);
			if (d < best) {
				best = d;
				id = hash12(i + offset + vec2(3.7, 1.3));
			}
		}
	}
	return vec2(best, id);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	bool horizontal = n.y > 0.6;
	// The plane this face lies in, in metres.
	vec2 p = horizontal ? world_position.xz : (n.x > n.z ? world_position.zy : world_position.xy);
	// How many metres one pixel covers: detail finer than that fades instead of shimmering.
	float footprint = max(length(fwidth(p)), 0.0001);

	vec3 colour = base_color.rgb;
	float blotch = fbm(p * 0.33 + vec2(4.1, 2.7));
	float drift = fbm(p * 1.4 + vec2(11.3, 7.7));
	colour = mix(colour, warm_color.rgb, smoothstep(0.42, 0.72, blotch) * mottling);
	colour = mix(colour, cool_color.rgb, smoothstep(0.48, 0.78, drift) * mottling * 0.85);
	colour *= 1.0 - cloud * 0.5 + cloud * fbm(p * 4.2 + vec2(1.9, 5.3));

	// Burnished patches: where the float went over twice, the surface is smoother and
	// paler and the grain sinks.
	float burnish = smoothstep(0.6, 0.78, fbm(p * 0.8 + vec2(23.0, 4.0)));
	colour = mix(colour, colour * 1.08 + vec3(0.02), burnish * 0.5);

	float fine_fade = 1.0 - smoothstep(0.003, 0.016, footprint);
	float mid_fade = 1.0 - smoothstep(0.01, 0.05, footprint);
	float fine = value_noise(p * 160.0) - 0.5;
	float mid = value_noise(p * 38.0 + vec2(2.0, 8.0)) - 0.5;
	colour *= 1.0 + (fine * fine_fade + mid * 0.6 * mid_fade) * grain * (1.0 - burnish * 0.6);

	// Exposed aggregate.
	vec2 stone = cells(p * 26.0);
	float has_stone = step(1.0 - aggregate_density, stone.y);
	float stone_edge = 1.0 - smoothstep(0.16, 0.26, stone.x);
	vec3 stone_colour = mix(aggregate_dark.rgb, aggregate_light.rgb, fract(stone.y * 7.31));
	colour = mix(colour, stone_colour, has_stone * stone_edge * mid_fade * 0.75);

	// Air pores: small dark pits, rarer and larger on the vertical faces.
	vec2 pore = cells(p * (horizontal ? 11.0 : 7.0) + vec2(5.0, 1.0));
	float pit = step(0.86, pore.y) * (1.0 - smoothstep(0.05, 0.09, pore.x));
	colour *= 1.0 - pit * pores * 0.55 * mid_fade;

	if (horizontal && joint_spacing > 0.0) {
		// Saw-cut joints, each line wandering a little and chipped along its edges.
		vec2 q = p / joint_spacing;
		q += 0.05 * vec2(value_noise(p.yx * 0.7), value_noise(p * 0.7 + vec2(3.0))) - 0.025;
		vec2 to_line = abs(fract(q) - 0.5) * joint_spacing;
		float line_distance = 0.5 * joint_spacing - max(to_line.x, to_line.y);
		float chipped = 0.006 + 0.006 * value_noise(p * 9.0);
		float joint = 1.0 - smoothstep(chipped, chipped + 0.004 + footprint, line_distance);
		colour *= 1.0 - joint * 0.42;
	}

	if (horizontal && ruled_lines > 0.0) {
		// The answer sheet the floor was poured against: grooves across the room, worn
		// away in places, and the margin line in faded red.
		float row = abs(fract(p.y / ruled_spacing) - 0.5) * ruled_spacing;
		float groove = smoothstep(0.5 * ruled_spacing - 0.006 - footprint, 0.5 * ruled_spacing, row);
		float worn = smoothstep(0.35, 0.6, value_noise(vec2(p.x * 0.9, floor(p.y / ruled_spacing) * 3.1)));
		colour *= 1.0 - groove * worn * ruled_lines * 0.22;
		float margin = 1.0 - smoothstep(0.012, 0.012 + footprint * 2.0, abs(p.x - margin_x));
		float margin_worn = smoothstep(0.25, 0.55, value_noise(vec2(p.y * 1.3, 4.0)));
		colour = mix(colour, colour * margin_color.rgb * 1.5, margin * margin_worn * ruled_lines * 0.6);
	}

	if (!horizontal && formwork > 0.0) {
		// Board-formed: planks 0.15 m high, each poured against a different board.
		float plank = floor(world_position.y / 0.15);
		colour *= 1.0 + (hash12(vec2(plank, 2.0)) - 0.5) * 0.12 * formwork;
		float seam = abs(fract(world_position.y / 0.15) - 0.5) * 0.15;
		colour *= 1.0 - smoothstep(0.072 - footprint, 0.075, seam) * 0.3 * formwork;
		float along = n.x > n.z ? world_position.z : world_position.x;
		float wood = value_noise(vec2(along * 2.0 + plank * 13.0, world_position.y * 46.0)) - 0.5;
		colour *= 1.0 + wood * 0.1 * formwork * mid_fade;
	}

	colour *= COLOR.rgb;
	float grey = dot(colour, vec3(0.299, 0.587, 0.114));
	colour = mix(colour, vec3(grey) * vec3(0.95, 1.0, 0.97), dull * 0.7);
	colour = mix(colour, colour * vec3(0.74, 0.84, 1.1), chill);
	float distance_out = distance(world_position.xz, focus_point.xz);
	float outside = smoothstep(focus_radius, focus_radius + 2.6, distance_out);
	colour = mix(colour, colour * vec3(0.3, 0.32, 0.52), outside * focus_amount);
	ALBEDO = clamp(colour, vec3(0.0), vec3(1.0));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	float lit = smoothstep(terminator - softness, terminator + softness, n_dot_l);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR * light_gain / PI;
}
