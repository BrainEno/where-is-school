shader_type spatial;
render_mode unshaded, cull_disabled;

// A hand-cut film loop on the room's screen, not a post-process. The carrier
// glides and the ink dissolves between exposures; there is no shutter flash.
uniform float phase_offset = 0.0;
uniform float fade = 1.0;

float panel(vec2 p, vec2 centre, vec2 half_size) {
	vec2 d = abs(p - centre) - half_size;
	float edge = max(d.x, d.y);
	return 1.0 - smoothstep(-.004, .004, edge);
}

void fragment() {
	vec2 p = UV;
	float phase = TIME * .39 + phase_offset;
	float travel = .095 * sin(phase);
	vec3 base = vec3(.20, .115, .155);
	vec3 paper = vec3(.91, .73, .49);
	float exposure = panel(p, vec2(.52, .51), vec2(.385, .432));
	float fold = panel(vec2(p.x + .25 * p.y, p.y), vec2(.56, .55), vec2(.232, .284));
	vec3 stock = mix(base, paper, exposure);
	stock = mix(stock, vec3(.73, .40, .23), fold * .71);
	vec2 q = vec2(p.x + .145 * p.y - travel, p.y - .085 * p.x);
	float imprint = panel(q, vec2(.59, .55), vec2(.155, .247));
	imprint -= panel(q, vec2(.61, .58), vec2(.101, .189));
	float inset = panel(q, vec2(.64, .48), vec2(.059, .063));
	stock = mix(stock, vec3(.22, .275, .29), (imprint + inset * .55) * (.81 + .12 * cos(phase)));
	float holes = panel(vec2(p.x, fract(p.y * 7.0)), vec2(.069, .49), vec2(.018, .19));
	float fibre = sin(p.x * 329.0 + sin(p.y * 277.0)) * cos(p.y * 131.0);
	ALBEDO = mix(base, mix(stock, paper, holes * .81), fade) * (.978 + .022 * fibre);
}
