// The container yard's planks (tools/build_container_yard.py): painted timber that sags
// and swings between the roofs it rests on. Vertex alpha is how much a vertex moves
// (0 at the ends, 1 mid-span); the plank lies along local +x, so the sag is local -y and
// the swing local z. The collider under it does not move.
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float sag = 0.06;
uniform float swing = 0.03;
uniform float rate = 1.0;
uniform float phase = 0.0;

void vertex() {
	float w = COLOR.a;
	float t = TIME * rate + phase;
	VERTEX.y -= w * sag * (0.6 + 0.4 * sin(t * 1.63));
	VERTEX.z += w * swing * sin(t);
}

void fragment() {
	// The vertex colour is the timber's sRGB colour; light works in linear.
	vec3 timber = mix(COLOR.rgb / 12.92, pow((COLOR.rgb + 0.055) / 1.055, vec3(2.4)), step(0.04045, COLOR.rgb));
	ALBEDO = albedo.rgb * timber;
	ROUGHNESS = 1.0;
}
