// Visual experiments lab only (scenes/dev/ is excluded from every export preset).
//
// A theatre flat painted with a corridor in one-point perspective: floor tiles, a dado
// line, doors down both walls and a pale far end. Everything is computed from UV, so the
// "corridor" is exactly as deep as the plywood it is painted on — the point of the stage.
// Unshaded on purpose: a painted light does not move when the real light does. The real
// spotlight still lands on it, because the flat's shadow and the actors' shadows are cast
// by geometry, not by this material.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec2 vanishing_point = vec2(0.5, 0.46);
// Half size of the far end, in UV.
uniform vec2 far_half = vec2(0.07, 0.11);
uniform vec4 wall_color : source_color = vec4(0.42, 0.55, 0.47, 1.0);
uniform vec4 upper_wall_color : source_color = vec4(0.83, 0.79, 0.66, 1.0);
uniform vec4 floor_color_a : source_color = vec4(0.71, 0.55, 0.3, 1.0);
uniform vec4 floor_color_b : source_color = vec4(0.44, 0.36, 0.25, 1.0);
uniform vec4 ceiling_color : source_color = vec4(0.18, 0.17, 0.2, 1.0);
uniform vec4 door_color : source_color = vec4(0.28, 0.2, 0.17, 1.0);
uniform vec4 far_color : source_color = vec4(0.98, 0.9, 0.66, 1.0);
uniform vec4 ink_color : source_color = vec4(0.1, 0.09, 0.1, 1.0);
uniform float aspect = 2.0;
uniform float brush_wobble = 0.012;
uniform float seed = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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

void fragment() {
	// A hand does not paint a ruler line: wobble the coordinates before classifying them.
	vec2 wobble = vec2(
		value_noise(UV * vec2(9.0, 23.0) + seed),
		value_noise(UV * vec2(23.0, 9.0) + seed + 4.1)
	) - 0.5;
	vec2 uv = UV + wobble * brush_wobble;
	vec2 offset = uv - vanishing_point;
	vec2 near_half = vec2(max(vanishing_point.x, 1.0 - vanishing_point.x), max(vanishing_point.y, 1.0 - vanishing_point.y));
	float sx = abs(offset.x) / near_half.x;
	float sy = abs(offset.y) / near_half.y;
	float s = max(sx, sy);
	float far_ratio = max(far_half.x / near_half.x, far_half.y / near_half.y);
	vec3 colour;
	float edge_ink = 0.0;
	if (s < far_ratio) {
		colour = far_color.rgb;
		// A doorframe at the far end, painted in two strokes.
		float frame_edge = abs(s - far_ratio * 0.92);
		edge_ink = 1.0 - smoothstep(0.0, 0.004, frame_edge);
	} else {
		// Distance down the corridor: 1 at the flat's edge, growing toward the far end.
		float depth = 1.0 / s;
		edge_ink = 1.0 - smoothstep(0.0, 0.006, abs(sx - sy));
		if (sy > sx) {
			float across = offset.x / abs(offset.y) * near_half.y / near_half.x;
			if (offset.y > 0.0) {
				float checker = mod(floor(depth * 3.0) + floor(across * 2.5 + 10.0), 2.0);
				colour = mix(floor_color_a.rgb, floor_color_b.rgb, checker);
			} else {
				colour = ceiling_color.rgb;
				float lamp = 1.0 - smoothstep(0.0, 0.08, abs(fract(depth * 0.7) - 0.5) * 2.0 - 0.0);
				colour = mix(colour, far_color.rgb, lamp * step(abs(across), 0.25) * 0.8);
			}
		} else {
			// Height on the wall: -1 at the floor line, +1 at the ceiling line.
			float height = -offset.y / abs(offset.x) * near_half.x / near_half.y;
			colour = height < -0.2 ? wall_color.rgb : upper_wall_color.rgb;
			edge_ink = max(edge_ink, 1.0 - smoothstep(0.0, 0.02 * s, abs(height + 0.2) * s));
			float door_phase = fract(depth * 1.1 + (offset.x > 0.0 ? 0.5 : 0.0));
			if (door_phase < 0.34 && height < 0.45) {
				colour = door_color.rgb;
				float panel = step(0.05, door_phase) * step(door_phase, 0.29) * step(height, 0.38);
				colour = mix(colour, colour * 1.25, panel * 0.6);
			}
		}
	}
	float stroke = value_noise(vec2(uv.x * 40.0 * aspect, uv.y * 7.0) + seed) - 0.5;
	colour *= 1.0 + stroke * 0.12;
	colour = mix(colour, ink_color.rgb, clamp(edge_ink, 0.0, 1.0) * 0.85);
	// The canvas shows at the very edge, where the painter stopped.
	float border = min(min(UV.x, 1.0 - UV.x) * aspect, min(UV.y, 1.0 - UV.y));
	colour = mix(vec3(0.86, 0.82, 0.72), colour, smoothstep(0.004, 0.02, border + wobble.x * 0.01));
	ALBEDO = colour;
}
