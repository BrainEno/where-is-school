shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The column of light the scaffold stands in, inside the building under construction
// (tools/build_site_interior.py): an open cylinder drawn additively from both sides, bands
// of colour rising up it, brightest along its silhouette (where a real shaft of light would
// be thickest to the eye), faded in at the floor and out toward `height`.
uniform float strength = 0.55;
uniform float rise = 0.25;
uniform float height = 14.0;

varying vec3 local_pos;

vec3 palette(float t) {
	return 0.5 + 0.5 * cos(6.2831853 * (vec3(t) + vec3(0.0, 0.33, 0.67)));
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float y = local_pos.y;
	float a = atan(local_pos.z, local_pos.x);
	float bands = 0.5 + 0.5 * sin(y * 2.2 - TIME * rise * 6.2831853 + sin(a * 3.0 + TIME * 0.3) * 0.8);
	vec3 colour = palette(y * 0.05 - TIME * 0.04);
	float facing = abs(dot(NORMAL, VIEW));
	float fade = smoothstep(0.0, 0.6, y) * (1.0 - smoothstep(height * 0.55, height, y));
	ALBEDO = colour * (0.35 + 0.65 * bands) * strength * fade * (0.3 + 0.7 * (1.0 - facing));
}
