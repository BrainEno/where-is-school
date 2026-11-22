shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// A smell drawn as a rising, bending ribbon: thin dithered bands, no texture,
// no alpha sorting. The quad's base stays put; the top wanders.
uniform vec4 tint : source_color = vec4(.66, .62, .28, 1.0);
uniform float rate = .35;
uniform float phase = 0.0;

void vertex() {
	float lift = 1.0 - UV.y;
	VERTEX.x += sin(VERTEX.y * 3.1 + TIME * 1.3 + phase * 6.28) * .16 * lift;
	VERTEX.z += cos(VERTEX.y * 2.3 + TIME * .9 + phase * 4.1) * .09 * lift;
}

void fragment() {
	float lift = 1.0 - UV.y;
	float band = fract(UV.y * 5.0 + TIME * rate + phase);
	float core = 1.0 - abs(UV.x - .5) * 2.0;
	float density = smoothstep(.15, .5, band) * (1.0 - smoothstep(.55, .9, band)) * core * (1.0 - lift * .8);
	float h = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	if (h > density * .18) {
		discard;
	}
	ALBEDO = tint.rgb;
}
