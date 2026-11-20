shader_type spatial;
render_mode diffuse_toon, specular_disabled;

// A painted escalator belt over the walkable stair. Local -Z is uphill. The steps
// always run downhill, toward +Z: whoever climbs is walking up a down escalator.
uniform vec4 plate : source_color = vec4(.70, .71, .72, 1.0);
uniform vec4 groove : source_color = vec4(.33, .34, .37, 1.0);
uniform vec4 riser : source_color = vec4(.13, .13, .16, 1.0);
uniform vec4 edge : source_color = vec4(.93, .78, .22, 1.0);
uniform float step_length = .38;
uniform float speed = .45;
uniform float width = 3.2;
varying vec3 belt_pos;

void vertex() {
	belt_pos = VERTEX;
}

void fragment() {
	float s = fract((belt_pos.z - TIME * speed) / step_length);
	vec3 c = mix(plate.rgb, groove.rgb, step(.55, fract(belt_pos.x * 16.0)) * .55);
	c = mix(c, edge.rgb, step(.84, s) * step(s, .9));
	c = mix(c, riser.rgb, step(.9, s));
	c = mix(c, edge.rgb, step(width * .5 - .085, abs(belt_pos.x)));
	ALBEDO = c;
	ROUGHNESS = .75;
}
