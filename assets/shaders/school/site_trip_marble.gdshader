shader_type spatial;
render_mode cull_back;

// The six marbles from the roof deck of the building under construction, grown to the size
// of footballs, orbiting the scaffold inside it (tools/build_site_interior.py). Motion without
// a script: every marble is the same unit sphere at the column's centre, and this shader
// spins it, carries it out to `orbit_radius` at `orbit_height` and turns it round the column,
// bobbing. The node's `custom_aabb` covers the whole orbit so it is never culled mid-flight.
// The glass is a swirl of two colours from one wheel, with a bright rim.
uniform float orbit_radius = 3.0;
uniform float orbit_height = 3.0;
uniform float orbit_rate = 0.04;
uniform float phase = 0.0;
uniform float size = 0.5;
uniform float bob = 0.25;
uniform float hue = 0.0;

varying vec3 local_normal;

vec3 palette(float t) {
	return 0.5 + 0.5 * cos(6.2831853 * (vec3(t) + vec3(0.0, 0.33, 0.67)));
}

void vertex() {
	local_normal = NORMAL;
	float spin = TIME * 0.6 + phase * 4.0;
	float cs = cos(spin);
	float ss = sin(spin);
	vec3 v = VERTEX * size;
	vec3 n = NORMAL;
	v.xy = vec2(v.x * cs - v.y * ss, v.x * ss + v.y * cs);
	n.xy = vec2(n.x * cs - n.y * ss, n.x * ss + n.y * cs);
	v += vec3(orbit_radius, orbit_height + bob * sin(TIME * 0.7 + phase * 6.2831853), 0.0);
	float turn = 6.2831853 * (TIME * orbit_rate + phase);
	float c = cos(turn);
	float s = sin(turn);
	VERTEX = vec3(v.x * c - v.z * s, v.y, v.x * s + v.z * c);
	NORMAL = vec3(n.x * c - n.z * s, n.y, n.x * s + n.z * c);
}

void fragment() {
	vec3 n = normalize(local_normal);
	float swirl = sin(atan(n.z, n.x) * 2.0 + n.y * 5.0 + sin(n.y * 3.0 + TIME * 0.4) * 2.0);
	vec3 colour = mix(palette(hue), palette(hue + 0.4), smoothstep(-0.2, 0.2, swirl));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = colour * 0.7;
	EMISSION = colour * 0.35 + vec3(rim * 0.6);
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
}
