shader_type spatial;
render_mode cull_back, specular_disabled;

// The stink stable's shaped meshes (docs/EXAM_DREAM_ART.md): horses, dung, the muck heap
// and the straw, painted in the manner of the visual experiments (#196, #200) rather than lit.
//
// * Colour is the mesh's own vertex colour, one flat field per region (sRGB bytes).
// * Light is a two-step terminator, not a gradient (`light()`), and the dark side is also
//   *painted*: a second, fixed "painted light" (`paint_light`) that ignores the lamps splits
//   every form into a lit field and a shade field, and the shade field is hatched with
//   diagonal pen lines in screen space, like a print. The two lights disagree on purpose.
// * Fresh dung can carry a hard white highlight (`gloss`), the one glossy thing allowed.
// * Everything is a little bilious: `stench` pulls the colour toward an acid yellow-green,
//   more in the shade, because the smell is the light this place is seen by.
//
// Motion without a skeleton or a script. Vertex alpha is a weight (tools/stable_meshes.py):
// 0.5 still, 0.5 -> 1 the share of the graze turn about `neck_pivot`, 0.5 -> 0 the share of
// the tail swish about `tail_pivot`. Phases live in the material, never in instance uniforms.
// `stable_ink.gdshader` repeats the same motion for the drawn contour.
uniform vec3 neck_pivot = vec3(0.0, 1.3, 0.5);
uniform float graze = 0.0;
uniform float graze_rate = 0.12;
uniform vec3 tail_pivot = vec3(0.0, 1.36, -0.93);
uniform float swish = 0.0;
uniform float swish_rate = 0.5;
uniform float phase = 0.0;
uniform vec3 paint_light = vec3(-0.55, 0.62, 0.56);
uniform vec4 shade_tint : source_color = vec4(0.56, 0.6, 0.42, 1.0);
uniform vec4 ink : source_color = vec4(0.16, 0.15, 0.2, 1.0);
uniform float hatch = 0.55;
uniform float hatch_pitch = 6.0;
uniform vec4 stench_tint : source_color = vec4(0.84, 0.9, 0.3, 1.0);
uniform float stench : hint_range(0.0, 1.0) = 0.22;
// Fresh dung is the one glossy thing in the dream (docs/EXAM_DREAM_ART.md): a hard cartoon
// highlight from the painted light, a cut-out shape rather than a specular lobe.
uniform float gloss : hint_range(0.0, 1.0) = 0.0;
uniform vec4 gloss_tint : source_color = vec4(1.0, 0.98, 0.84, 1.0);
uniform float terminator = 0.12;
uniform float softness = 0.03;
uniform float light_gain = 1.0;
uniform float emission_floor = 0.28;

varying vec3 world_normal;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	float a = COLOR.a;
	float neck = clamp(a * 2.0 - 1.0, 0.0, 1.0);
	float tail = clamp(1.0 - a * 2.0, 0.0, 1.0);
	// Head down slowly, a long hold at the grass, then up: 0..graze radians.
	float g = graze * neck * smoothstep(0.15, 0.85, 0.5 - 0.5 * cos(6.2831853 * (TIME * graze_rate + phase)));
	float c = cos(g);
	float s = sin(g);
	vec3 v = VERTEX - neck_pivot;
	vec3 n = NORMAL;
	v.yz = vec2(v.y * c - v.z * s, v.y * s + v.z * c);
	n.yz = vec2(n.y * c - n.z * s, n.y * s + n.z * c);
	v += neck_pivot;
	// The tail swishes side to side, the tip furthest.
	float w = swish * tail * sin(6.2831853 * (TIME * swish_rate + phase * 1.7));
	c = cos(w);
	s = sin(w);
	v -= tail_pivot;
	v.xz = vec2(v.x * c + v.z * s, -v.x * s + v.z * c);
	n.xz = vec2(n.x * c + n.z * s, -n.x * s + n.z * c);
	v += tail_pivot;
	VERTEX = v;
	NORMAL = n;
	world_normal = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
}

void fragment() {
	vec3 colour = to_linear(COLOR.rgb);
	float painted = smoothstep(-0.04, 0.04, dot(normalize(world_normal), normalize(paint_light)));
	vec3 shade = colour * to_linear(shade_tint.rgb);
	// Pen hatching in the painted shade: diagonal screen lines, about a pixel and a half wide.
	float line = 1.0 - smoothstep(0.18, 0.32, abs(fract((FRAGCOORD.x + FRAGCOORD.y) / hatch_pitch) - 0.5));
	shade = mix(shade, to_linear(ink.rgb), line * hatch * 0.6);
	colour = mix(shade, colour, painted);
	vec3 bile = to_linear(stench_tint.rgb);
	colour = mix(colour, colour * bile * 1.25, stench * (1.0 - painted * 0.5));
	vec3 to_light = normalize((VIEW_MATRIX * vec4(paint_light, 0.0)).xyz);
	float spot = smoothstep(0.955, 0.965, dot(normalize(NORMAL), normalize(to_light + VIEW)));
	colour = mix(colour, to_linear(gloss_tint.rgb), spot * gloss);
	ALBEDO = clamp(colour, vec3(0.0), vec3(1.0));
	EMISSION = ALBEDO * emission_floor;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float lit = smoothstep(terminator - softness, terminator + softness, dot(NORMAL, LIGHT));
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR * light_gain / PI;
}
