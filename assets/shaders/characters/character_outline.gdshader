shader_type spatial;
// The ink line around the protagonist and Q: an inverted hull, like the classroom's
// `assets/materials/classroom/ink_outline.tres` (same ink, #2B2622), drawn as the
// `next_pass` of the parts that carry it.
//
// The classroom's hull grows a fixed 1.6 cm. A person is seen from 1 m in a close-up and
// from 6 m in play, so this one grows with distance from the camera (`width` at
// `reference_distance`, clamped), which keeps the line about the same weight on screen:
// it never swallows the eyes in a close-up and never disappears at the far end of a room.
// The eyes, mouth, brows, buttons and teeth carry no hull at all (see the look resources).
//
// Optional (off by default): `wobble` varies the width along the form with a rest-space
// noise, so the line is cut by hand rather than ruled, and the part's `shape_*` push
// (character_shape.gdshaderinc) is applied first so the hull follows a reshaped part.
// `gap_*` is a rest-space ellipsoid, mirrored across x = `gap_mirror_x`, where the hull
// does not grow: around the eyes, the head skin's hull grows out of the sockets' inner rims
// and draws a ring round each eyeball that reads as spectacles.
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

#include "res://assets/shaders/characters/character_shape.gdshaderinc"

uniform vec3 ink : source_color = vec3(0.169, 0.149, 0.133);
// Hull growth in metres at `reference_distance` from the camera.
uniform float width : hint_range(0.0, 0.05) = 0.009;
uniform float reference_distance : hint_range(0.5, 20.0) = 4.0;
uniform float min_scale : hint_range(0.1, 2.0) = 0.55;
uniform float max_scale : hint_range(0.5, 4.0) = 1.7;
// Width variation along the form: 0 is an even line, 1 swings it from nothing to twice
// `width`.
uniform float wobble : hint_range(0.0, 1.0) = 0.0;
// Swings per metre.
uniform float wobble_scale : hint_range(1.0, 80.0) = 14.0;
uniform vec3 gap_center = vec3(0.0);
uniform vec3 gap_radius = vec3(0.0);
uniform float gap_mirror_x = 0.0;

float outline_hash(vec3 p) {
	vec3 q = fract(p * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.x + q.y) * q.z);
}

float outline_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	float x00 = mix(outline_hash(cell), outline_hash(cell + vec3(1.0, 0.0, 0.0)), t.x);
	float x10 = mix(outline_hash(cell + vec3(0.0, 1.0, 0.0)), outline_hash(cell + vec3(1.0, 1.0, 0.0)), t.x);
	float x01 = mix(outline_hash(cell + vec3(0.0, 0.0, 1.0)), outline_hash(cell + vec3(1.0, 0.0, 1.0)), t.x);
	float x11 = mix(outline_hash(cell + vec3(0.0, 1.0, 1.0)), outline_hash(cell + vec3(1.0, 1.0, 1.0)), t.x);
	return mix(mix(x00, x10, t.y), mix(x01, x11, t.y), t.z);
}

void vertex() {
	vec3 rest = CUSTOM0.w > 1.5 ? CUSTOM0.xyz : VERTEX;
	VERTEX += character_shape_push(rest, NORMAL);
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float distance_scale = clamp(-view_position.z / reference_distance, min_scale, max_scale);
	float swing = 1.0;
	if (wobble > 0.0) {
		swing = 1.0 + (outline_noise(rest * wobble_scale) - 0.5) * 2.0 * wobble;
	}
	float keep = 1.0;
	if (gap_radius.x > 0.0 && gap_radius.y > 0.0 && gap_radius.z > 0.0) {
		vec3 q = rest;
		q.x = gap_mirror_x + abs(q.x - gap_mirror_x);
		keep = smoothstep(0.7, 1.0, length((q - gap_center) / gap_radius));
	}
	VERTEX += normalize(NORMAL) * width * distance_scale * swing * keep;
}

void fragment() {
	ALBEDO = ink;
}
