shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Smell cut out of coloured paper (docs/EXAM_DREAM_ART.md): cartoon stink clouds that rise
// off the dung and stall and dither away, and the knocked-out spiral and stars that turn
// over a head. The colour is the mesh's vertex colour (paper face, cream core, ink backing,
// tools/stable_meshes.py); the light is the paper's own, so it reads as pasted onto the
// scene rather than lit by it - the collage manner of #196 and #200.
//
// MultiMesh instances take their own place in the loop (`INSTANCE_ID`); phases are material
// values, never instance uniforms. No screen or depth texture is read.
uniform vec3 rise = vec3(0.0);
uniform float rise_rate = 0.0;
uniform float fade_edge = 0.0;
uniform float spin = 0.0;
uniform float wobble = 0.0;
uniform float wobble_rate = 0.3;
uniform float phase = 0.0;
uniform float tooth = 0.07;

varying float fade;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	float p = phase + float(INSTANCE_ID) * 0.618034;
	vec3 v = VERTEX;
	float a = spin * TIME + p * 6.2831853;
	float c = cos(a);
	float s = sin(a);
	v.xz = vec2(v.x * c + v.z * s, -v.x * s + v.z * c);
	// A slow rock about the paper's own X, as if it were floating on the air it stinks of.
	float r = wobble * sin(6.2831853 * (TIME * wobble_rate + p));
	c = cos(r);
	s = sin(r);
	v.yz = vec2(v.y * c - v.z * s, v.y * s + v.z * c);
	float t = fract(TIME * rise_rate + p);
	v += rise * t;
	fade = 0.0;
	if (fade_edge > 0.0) {
		fade = 1.0 - min(smoothstep(0.0, fade_edge, t), 1.0 - smoothstep(1.0 - fade_edge, 1.0, t));
	}
	VERTEX = v;
}

void fragment() {
	if (hash(floor(FRAGCOORD.xy)) < fade) {
		discard;
	}
	vec3 colour = to_linear(COLOR.rgb);
	colour *= 1.0 + (hash(floor(FRAGCOORD.xy * 0.5)) - 0.5) * tooth;
	ALBEDO = colour;
}
