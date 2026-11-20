shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Stationary stains in metres, not a camera filter. A shared variation of the
// same pigments on grout, glaze and plaster keeps the fittings in the room.
uniform vec4 base_ink : source_color = vec4(.55, .56, .44, 1.0);
uniform vec4 damp_ink : source_color = vec4(.19, .21, .15, 1.0);
uniform vec4 rust_ink : source_color = vec4(.32, .21, .13, 1.0);
uniform int field = 0; // floor, wall, glaze, pooled water
uniform float phase = 0.0;
varying vec3 position_m;
varying vec3 normal_m;

float grain(vec2 point) {
	vec3 q = fract(vec3(point.xyx) * .1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float fibre(vec2 point) {
	vec2 cell = floor(point);
	vec2 f = fract(point);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(grain(cell), grain(cell + vec2(1, 0)), f.x),
		mix(grain(cell + vec2(0, 1)), grain(cell + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	position_m = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_m = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec2 p = position_m.xz;
	if (field == 1 || (field == 2 && abs(normal_m.y) < .62)) {
		p = vec2(abs(normal_m.x) > abs(normal_m.z) ? position_m.z : position_m.x, position_m.y);
	}
	vec2 q = p + vec2(phase * 1.3, phase * .8);
	float cloud = .66 * fibre(q * 1.9) + .24 * fibre(q * 7.6) + .10 * fibre(q * 28.0);
	float seep = 0.0;
	if (field == 1) {
		float stripes = fibre(q * vec2(19.0, 1.25));
		seep = smoothstep(.53, .85, stripes) * smoothstep(.33, .94, fibre(q * vec2(4.5, 1.9)));
		cloud += .18 * (1.0 - smoothstep(.0, .8, position_m.y));
	}
	float patch = smoothstep(.35, .69, cloud + .28 * seep);
	float edge = smoothstep(.12, .92, cloud);
	vec3 colour = mix(base_ink.rgb, damp_ink.rgb, patch * (field == 2 ? .72 : .93));
	colour = mix(colour, rust_ink.rgb, .46 * seep + .21 * smoothstep(.61, .77, edge));
	colour *= .93 + .13 * fibre(q * 46.0);
	if (field == 3) {
		colour = mix(damp_ink.rgb, base_ink.rgb, .23 + .30 * edge);
		colour += vec3(.09, .095, .062) * smoothstep(.56, .71, fibre(q * vec2(3.0, 27.0)));
	}
	ALBEDO = colour;
	ROUGHNESS = field == 3 ? .27 : (field == 2 ? .58 : .94);
}
