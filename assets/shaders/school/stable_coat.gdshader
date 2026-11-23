shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap;

// The stable yard's animals and dressing after round 18 (docs/EXAM_DREAM_ART.md): sculpted,
// vertex-painted meshes (tools/stable_animals.py, tools/stable_props.py) lit as matter rather
// than paper. The colour is the mesh's vertex colour, which already carries the painted
// anatomy and an ambient-occlusion estimate; light is the engine's own wrapped diffuse, so
// a flank turns away from the sun in a gradient, not a cut.
//
// * `sheen` adds the soft grazing lift of a short coat or a feather (a rim, not a specular
//   highlight), strongest on the coat's lit side.
// * `fill` is a low self-light, so a form in a stall's shadow stays a shape rather than a hole.
//
// Motion is the same as `stable_paint.gdshader`, with no skeleton or script. Vertex alpha is a
// weight: 0.5 still, 0.5 -> 1 the share of the graze (or a hen's peck) about `neck_pivot`,
// 0.5 -> 0 the share of the tail swish about `tail_pivot`. Phases live in the material, never
// in instance uniforms.
uniform vec3 neck_pivot = vec3(0.0, 1.3, 0.5);
uniform float graze = 0.0;
uniform float graze_rate = 0.12;
uniform vec3 tail_pivot = vec3(0.0, 1.36, -0.93);
uniform float swish = 0.0;
uniform float swish_rate = 0.5;
uniform float phase = 0.0;
uniform float sheen : hint_range(0.0, 1.0) = 0.25;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float fill : hint_range(0.0, 1.0) = 0.08;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	float a = COLOR.a;
	float neck = clamp(a * 2.0 - 1.0, 0.0, 1.0);
	float tail = clamp(1.0 - a * 2.0, 0.0, 1.0);
	// Head down, a hold at the ground, then up again: 0..graze radians.
	float g = graze * neck * smoothstep(0.15, 0.85, 0.5 - 0.5 * cos(6.2831853 * (TIME * graze_rate + phase)));
	float c = cos(g);
	float s = sin(g);
	vec3 v = VERTEX - neck_pivot;
	vec3 n = NORMAL;
	v.yz = vec2(v.y * c - v.z * s, v.y * s + v.z * c);
	n.yz = vec2(n.y * c - n.z * s, n.y * s + n.z * c);
	v += neck_pivot;
	float w = swish * tail * sin(6.2831853 * (TIME * swish_rate + phase * 1.7));
	c = cos(w);
	s = sin(w);
	v -= tail_pivot;
	v.xz = vec2(v.x * c + v.z * s, -v.x * s + v.z * c);
	n.xz = vec2(n.x * c + n.z * s, -n.x * s + n.z * c);
	v += tail_pivot;
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	vec3 colour = to_linear(COLOR.rgb);
	ALBEDO = colour;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.2;
	RIM = sheen;
	RIM_TINT = 0.55;
	EMISSION = colour * fill;
}
