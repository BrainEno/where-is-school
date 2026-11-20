shader_type spatial;
render_mode diffuse_toon, specular_disabled;

// Dream dressing that moves whole assemblies without scripts, physics or extra
// nodes. Parts of one assembly share `phase` and stay unrotated in its frame, so a
// uniform offset or a turn about a shared pivot keeps the boxes together. A loop
// dithers in and out at both ends; no alpha sorting against the cutaway's glass.
uniform vec4 albedo : source_color = vec4(.6, .6, .6, 1.0);
uniform vec3 travel = vec3(0.0);
uniform float travel_rate = 0.0;
uniform float fade_edge = 0.0;
uniform vec3 sway = vec3(0.0);
uniform float sway_rate = 0.0;
uniform float mechanical = 0.0;
uniform float turn = 0.0;
uniform float turn_rate = 0.0;
instance uniform float phase = 0.0;
// Pivot of the turn relative to this mesh's own origin, in the shared frame.
instance uniform vec3 pivot = vec3(0.0);
varying float fade;

void vertex() {
	// MultiMesh instances take their own place in the loop.
	float p = phase + float(INSTANCE_ID) * .618034;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float a = turn * sin(6.2831853 * (TIME * turn_rate + p));
	float c = cos(a);
	float s = sin(a);
	mat2 r = mat2(vec2(c, -s), vec2(s, c));
	v.xz = r * (v.xz - pivot.xz) + pivot.xz;
	n.xz = r * n.xz;
	float w = sin(6.2831853 * (TIME * sway_rate + p));
	// A stamp holds at both ends and snaps between them: a hand, not a breath.
	w = mix(w, smoothstep(-.18, .18, w) * 2.0 - 1.0, mechanical);
	v += sway * w;
	float t = fract(TIME * travel_rate + p);
	v += travel * t;
	fade = 0.0;
	if (fade_edge > 0.0) {
		fade = 1.0 - min(smoothstep(0.0, fade_edge, t), 1.0 - smoothstep(1.0 - fade_edge, 1.0, t));
	}
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	float h = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	if (h < fade) {
		discard;
	}
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
}
