// The pencil of the blank paper: noise and the broken hatching lines, shared by the
// biology-classroom experiment's full-screen paper (blank_paper.gdshader, scenes/dev/) and
// the game's local paper anomaly at the classroom's back window (paper_zone.gdshader).
// Functions only - no uniforms, no entry points - so it can be included by a canvas_item
// shader and by a spatial one alike.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

// A family of parallel pencil lines at `angle`, `density` per unit, with breaks.
float hatch(vec2 p, float angle, float density, float seed) {
	vec2 dir = vec2(cos(angle), sin(angle));
	float along = dot(p, vec2(-dir.y, dir.x)) * density;
	float line = abs(fract(along) - 0.5) * 2.0;
	float broken = step(0.18, value_noise(vec2(dot(p, dir) * 3.0, floor(along) + seed)));
	return (1.0 - smoothstep(0.0, 0.42, line)) * broken;
}
