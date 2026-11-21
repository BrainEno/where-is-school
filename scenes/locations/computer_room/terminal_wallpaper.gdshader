shader_type canvas_item;
render_mode unshaded;
// Original school-screen graphic: reset rows, a dusk palette and a vanishing grid.
void fragment() {
	vec2 uv = UV;
	vec3 ink = mix(vec3(.105, .069, .229), vec3(.38, .203, .42), smoothstep(.0, .72, uv.y));
	vec2 disk_uv = (uv - vec2(.743, .449)) * vec2(1.3333, 1.0);
	float disk = 1.0 - smoothstep(.206, .209, length(disk_uv));
	float slices = step(.22 + .5 * smoothstep(.44, .64, uv.y), fract(uv.y * 48.0));
	vec3 apricot = mix(vec3(.984, .717, .555), vec3(.86, .319, .537), smoothstep(.27, .66, uv.y));
	ink = mix(ink, apricot, disk * mix(1.0, slices, smoothstep(.36, .65, uv.y)));
	if (uv.y > .675) {
		float depth = uv.y - .65;
		float across = abs(fract((uv.x - .743) * 10.0 / (1.0 + depth * 8.0) + .5) - .5);
		float rows = abs(fract(5.0 * log(depth * 6.0 + 1.0) + .5) - .5);
		float rule = max(1.0 - smoothstep(.012, .027, across), 1.0 - smoothstep(.018, .05, rows));
		ink = mix(vec3(.092, .07, .202), vec3(.68, .361, .63), rule * min(1.0, depth * 4.5));
	}
	float scan = mix(.93, 1.0, step(.27, fract(uv.y * 240.0)));
	float corners = 1.0 - .22 * pow(length((uv - .5) * 1.13), 1.7);
	COLOR = vec4(ink * scan * corners, 1.0);
}
