shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// A tiny bounded loop around each authored cluster. Stable rates/seeds do not
// allocate nodes or physics objects, and no screen or depth texture is read.
varying float wing;

void vertex() {
	float id = float(INSTANCE_ID);
	float t = TIME * (2.4 + mod(id, 7.0) * .22) + id * 2.39996;
	vec3 p = VERTEX;
	wing = step(.007, abs(p.x));
	p.y += abs(p.x) * wing * sin(TIME * 62.0 + id);
	float c = cos(t);
	float s = sin(t);
	p.xz = mat2(vec2(c, -s), vec2(s, c)) * p.xz;
	VERTEX = p + vec3(.19 * sin(t), .14 * sin(t * 1.71), .17 * cos(t * 1.13));
}

void fragment() {
	ALBEDO = mix(vec3(.033, .028, .018), vec3(.235, .212, .157), wing * .64);
}
