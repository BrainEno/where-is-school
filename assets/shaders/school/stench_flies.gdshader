shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Flies over the stink stable (docs/EXAM_DREAM_ART.md). Two uses, one shader:
//
// * a MultiMesh swarm (`swarm` > 0): each instance loops a lissajous knot of its own about
//   its authored place, and turns as it goes, so a cloud of them never settles;
// * the giant fly (`orbit_radius` > 0): one dog-sized fly circling the muck heap, facing
//   the way it flies, bobbing - the same insect pasted in at the wrong scale.
//
// Vertex alpha below 0.1 marks a wing (tools/stable_meshes.py); wings flap about the
// body's long axis and are drawn as dithered film. The body is two painted tones from a
// fixed painted light, like the rest of the stable. No screen or depth texture is read.
uniform float swarm = 0.0;
uniform float swarm_rate = 2.6;
uniform float orbit_radius = 0.0;
uniform float orbit_rate = 0.05;
uniform float bob = 0.0;
uniform float flap = 0.5;
uniform float flap_rate = 60.0;
uniform float phase = 0.0;
uniform vec3 paint_light = vec3(-0.55, 0.62, 0.56);

varying float wing;
varying vec3 world_normal;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 turn_y(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

void vertex() {
	float id = float(INSTANCE_ID);
	vec3 p = VERTEX;
	vec3 n = NORMAL;
	wing = 1.0 - step(0.1, COLOR.a);
	p.y += abs(p.x) * wing * flap * sin(TIME * flap_rate + id * 1.7 + phase * 6.28);
	if (orbit_radius > 0.0) {
		float a = 6.2831853 * (TIME * orbit_rate + phase);
		float heading = a + 1.5707963;
		p = turn_y(p, heading);
		n = turn_y(n, heading);
		p += vec3(orbit_radius * sin(a), bob * sin(a * 3.0), orbit_radius * cos(a));
	}
	if (swarm > 0.0) {
		float t = TIME * (swarm_rate + mod(id, 7.0) * 0.23) + id * 2.39996 + phase * 6.28;
		p = turn_y(p, t * 1.3);
		n = turn_y(n, t * 1.3);
		p += swarm * vec3(sin(t) + 0.4 * sin(t * 2.7), 0.7 * sin(t * 1.71), cos(t * 1.13) + 0.3 * cos(t * 3.1));
	}
	VERTEX = p;
	world_normal = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
}

void fragment() {
	vec3 colour = to_linear(COLOR.rgb);
	float lit = smoothstep(-0.05, 0.05, dot(world_normal, normalize(paint_light)));
	colour *= mix(0.55, 1.0, lit);
	if (wing > 0.5) {
		float h = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
		if (h > 0.62) {
			discard;
		}
	}
	ALBEDO = colour;
}
