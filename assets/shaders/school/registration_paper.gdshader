shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;

// Pigment and printed linework on room surfaces. Physics and selection stay 3D;
// this is not the experimental screen-wide SubViewport effect.
uniform vec4 stock : source_color = vec4(.86, .77, .58, 1.0);
uniform vec4 ink : source_color = vec4(.27, .23, .27, 1.0);
uniform int press = 0; // pulp, horizontal rules, cyanotype grid, graphite hatching
varying vec3 paper_position;
varying vec3 paper_normal;

float grain(vec2 p) {
	vec3 q = fract(vec3(p.xyx)*.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x+q.y)*q.z);
}

void vertex() {
	paper_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	paper_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

float rule(float n, float width) {
	float spacing = abs(fract(n + .5)-.5);
	return 1.0-smoothstep(width, width + max(.013, fwidth(n)), spacing);
}

void fragment() {
	vec3 n = abs(normalize(paper_normal));
	vec2 sheet = n.y > .63 ? paper_position.xz : vec2(n.x > n.z ? paper_position.z : paper_position.x, paper_position.y);
	float fibre = grain(floor(sheet * vec2(178.0, 290.0)));
	float pulp = grain(floor(sheet * vec2(9.4, 32.0)));
	float amount = .027 * fibre + .08 * pulp;
	if (press == 1) {
		amount += .32 * rule(sheet.y * 7.1, .034);
	} else if (press == 2) {
		amount += .50 * max(rule(sheet.x * 2.2, .016), rule(sheet.y * 2.2, .016));
		amount += .24 * max(rule(sheet.x * 11.0, .008), rule(sheet.y * 11.0, .008));
	} else if (press == 3) {
		amount += .28 * rule((sheet.x+sheet.y*.82)*14.3 + pulp*.12, .06);
		amount += .19 * rule((sheet.x-sheet.y*.93)*13.7, .045);
	}
	ALBEDO = mix(stock.rgb, ink.rgb, clamp(amount, 0.0, .90));
	ROUGHNESS = 1.0;
}
