shader_type spatial;
render_mode cull_back;

// The floor of the building under construction (tools/build_site_interior.py), and the void
// under it: a slowly turning op-art spiral, black and a rainbow ink, printed over the wet
// slab (its vertex colour). Logarithmic arms crossed with rings that run outward, so the
// pattern seems to pour toward the column of light at `centre` while it stays where it is.
// `contrast` is how much of the print covers the slab, fading out toward `fade_radius`;
// `glow` emits the print, so the void far below (`Vortex`, glow above 1) lights itself.
uniform vec3 centre = vec3(0.0);
uniform float arms = 10.0;
uniform float twist = 6.0;
uniform float spin = 0.05;
uniform float contrast : hint_range(0.0, 1.0) = 0.6;
uniform float glow = 0.15;
uniform float fade_radius = 7.0;
uniform float wet : hint_range(0.0, 1.0) = 0.45;

varying vec3 world_pos;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 palette(float t) {
	return 0.5 + 0.5 * cos(6.2831853 * (vec3(t) + vec3(0.0, 0.33, 0.67)));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = to_linear(COLOR.rgb);
	vec2 p = world_pos.xz - centre.xz;
	float r = max(length(p), 0.05);
	float a = atan(p.y, p.x);
	float arm = sin(a * arms + log(r) * twist - TIME * spin * 6.2831853);
	float ring = sin(r * 3.2 - TIME * 0.6);
	float field = arm * ring;
	float width = fwidth(field) + 0.02;
	float print = smoothstep(-width, width, field);
	float fade = 1.0 - smoothstep(fade_radius * 0.55, fade_radius, r);
	vec3 ink = vec3(0.02, 0.015, 0.04);
	vec3 hue = palette(r * 0.08 - TIME * 0.03 + 0.15 * sin(a * 2.0));
	vec3 paint = mix(ink, hue, print);
	ALBEDO = mix(base, paint, contrast * fade);
	ROUGHNESS = mix(0.9, 0.3, wet * (1.0 - print * 0.5));
	EMISSION = paint * glow * fade;
}
