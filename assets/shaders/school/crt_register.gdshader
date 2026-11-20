shader_type spatial;
render_mode unshaded, cull_disabled;

// Original monochrome test pattern, not an OS image or a flashing effect.
uniform vec4 phosphor : source_color = vec4(.48, .82, .66, 1.0);
uniform vec4 phosphor_dark : source_color = vec4(.045, .092, .09, 1.0);
uniform float channel = 0.0;

float line(float x, float width) {
	return 1.0 - smoothstep(width, width + fwidth(x), abs(x));
}

void fragment() {
	vec2 centre = UV - vec2(.5);
	vec2 p = .5 + centre * (1.0 + dot(centre, centre) * .17);
	float scan = .91 + .09 * cos(p.y * 275.0);
	float grid = .2 * max(line(fract(p.x * 10.0 + .5)-.5, .025), line(fract(p.y * 8.0 + .5)-.5, .022));
	float row = fract(p.y * 11.0 + channel * .08);
	float trace = step(.19, p.x) * step(p.x, .73 + .1 * cos(floor(p.y*11.0 + channel)*2.7))
		* (smoothstep(.17, .22, row) - smoothstep(.25, .31, row));
	float cross = max(line(p.x - .38 - channel*.027, .007) * step(.15, p.y) * step(p.y, .9),
		line(p.y - .61, .007) * step(.14, p.x) * step(p.x, .89));
	float edge = smoothstep(.0, .13, min(1.0-max(abs(centre.x), abs(centre.y))*2.0, 1.0));
	ALBEDO = mix(phosphor_dark.rgb, phosphor.rgb, clamp((grid + trace * .48 + cross*.66)*scan*edge, 0.0, 1.0));
}
