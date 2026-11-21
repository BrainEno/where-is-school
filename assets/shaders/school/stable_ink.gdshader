shader_type spatial;
render_mode unshaded, cull_front, specular_disabled, shadows_disabled;

// The drawn contour of the stink stable's horses and heap (docs/EXAM_DREAM_ART.md): the
// mesh again, pushed out along its normals and seen from behind, in one ink. Used as
// `material_overlay` beside `stable_paint.gdshader`, whose motion it repeats exactly so the
// line stays on the moving head and tail. No screen or depth read (as in #200's ink hull).
uniform vec3 neck_pivot = vec3(0.0, 1.3, 0.5);
uniform float graze = 0.0;
uniform float graze_rate = 0.12;
uniform vec3 tail_pivot = vec3(0.0, 1.36, -0.93);
uniform float swish = 0.0;
uniform float swish_rate = 0.5;
uniform float phase = 0.0;
uniform vec4 ink : source_color = vec4(0.16, 0.15, 0.2, 1.0);
uniform float width = 0.012;

void vertex() {
	float a = COLOR.a;
	float neck = clamp(a * 2.0 - 1.0, 0.0, 1.0);
	float tail = clamp(1.0 - a * 2.0, 0.0, 1.0);
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
	VERTEX = v + n * width;
}

void fragment() {
	ALBEDO = ink.rgb;
}
