// The imagined teacher's body, bent the way a dream bends it. Shared by
// dream_figure.gdshader and dream_ink.gdshader, so a figure and its ink hull (and the shadow,
// which runs the same vertex code) always move together.
//
// Everything is measured in the model's own space: the teacher_b GLB stands on y = 0, is
// 1.64 m tall and faces -Z. `dream` is the one control the scene animates: at 0 the GLB is
// exactly its own shape, at 1 every distortion below is at full strength.
//
// In order, on each skinned vertex:
//
// - the head swells out of the collar (Munch's skull-faces, a teacher remembered as mostly
//   a face), breathing slightly;
// - everything above the waist is drawn out upwards, so she towers over a seated pupil;
// - the body twists about its own axis, more towards the crown;
// - an S-wave runs up the body and travels in time: the figure on the bridge in The Scream,
//   which is a person drawn in the same strokes as the sky behind it;
// - the crown leans towards whoever she is looking at, and sinks a little for it.
//
// Normals are left as they were. The surface is flat-painted, so a bent normal would only
// move the terminator a few degrees.

uniform float dream : hint_range(0.0, 1.0) = 1.0;
uniform float figure_height = 1.64;
uniform vec3 head_center = vec3(0.0, 1.52, -0.09);
uniform float head_radius = 0.16;
uniform float head_swell : hint_range(0.0, 1.0) = 0.42;
uniform float stretch : hint_range(0.0, 1.0) = 0.34;
uniform float twist : hint_range(-2.0, 2.0) = 0.55;
// Metres of sideways swing at the crown, and how many S-curves run up the body.
uniform float sway : hint_range(0.0, 0.5) = 0.17;
uniform float sway_waves : hint_range(0.25, 4.0) = 1.3;
uniform float sway_speed : hint_range(0.0, 4.0) = 0.9;
// Metres the crown leans forward (towards -Z, where she looks).
uniform float lean : hint_range(-0.8, 0.8) = 0.38;
// Offsets one figure's wave from another's.
uniform float phase = 0.0;

vec3 dream_shape(vec3 v, float t) {
	float w = dream;
	vec3 from_head = v - head_center;
	float head_distance = length(from_head / vec3(1.0, 1.3, 1.0)) / (head_radius * 1.9);
	float head_weight = 1.0 - smoothstep(0.35, 1.0, head_distance);
	v += from_head * head_swell * head_weight * w * (1.0 + 0.18 * sin(t * 1.7 + phase));

	float waist = figure_height * 0.45;
	v.y += max(v.y - waist, 0.0) * stretch * w;

	float h = clamp(v.y / figure_height, 0.0, 1.8);
	float angle = twist * w * h * h * (0.8 + 0.2 * sin(t * 0.6 + phase));
	float c = cos(angle);
	float s = sin(angle);
	v.xz = vec2(c * v.x - s * v.z, s * v.x + c * v.z);

	float wave = sin(h * sway_waves * TAU - t * sway_speed + phase);
	v.x += sway * w * wave * h;
	v.z += sway * 0.35 * w * cos(h * sway_waves * PI - t * sway_speed * 0.7 + phase) * h;

	v.z -= lean * w * h * h;
	v.y -= abs(lean) * w * h * h * h * 0.25;
	return v;
}
