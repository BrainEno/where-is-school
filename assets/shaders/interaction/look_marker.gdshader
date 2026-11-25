shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled, blend_mix;

// The small green ring on a thing to look at or a person to talk to
// (scripts/interaction/hover_cue.gd; docs/ARCHITECTURE.md, "Marker or outline"). Disco Elysium
// marks these with a dot on the object rather than an outline around it; the outline is kept
// for doors, gates and stairs.
//
// The quad is a billboard of constant *pixel* size: a ring on a pencil case on the desk next to
// you and on a window across the hall are the same pen. It is drawn without a depth test because
// it sits at the middle of the object it marks - inside it, for anything solid - and is only
// shown while the object is the target, which already requires the object to be visible.
//
// Three layers, inside out: a pale dot, the green ring, a thin dark rim so it reads on the pale
// classroom walls as well as on the dusk-blue brick outside.

uniform vec4 ring_color : source_color = vec4(0.55, 0.92, 0.5, 1.0);
uniform vec4 dot_color : source_color = vec4(0.86, 1.0, 0.82, 1.0);
uniform vec4 rim_color : source_color = vec4(0.02, 0.07, 0.03, 0.62);
// Diameter of the quad in pixels at a 900-pixel-high window; scaled with the window height.
uniform float pixel_size = 24.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.0;
// 0..1 breathing, written by the cue; it only widens the ring by a pixel or so.
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	vec4 centre = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float units_per_pixel;
	if (PROJECTION_MATRIX[3][3] > 0.5) {
		// Orthographic: the scale does not depend on depth.
		units_per_pixel = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	} else {
		units_per_pixel = 2.0 * max(-centre.z, 0.05) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	}
	float size = pixel_size * (VIEWPORT_SIZE.y / 900.0) * units_per_pixel;
	POSITION = PROJECTION_MATRIX * (centre + vec4(VERTEX.xy * size, 0.0, 0.0));
}

float band(float r, float inner, float outer, float aa) {
	return smoothstep(inner - aa, inner, r) * (1.0 - smoothstep(outer, outer + aa, r));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = max(fwidth(r), 0.001) * 1.25;
	float widen = 0.05 * pulse;
	float ring = band(r, 0.56 - widen, 0.80, aa);
	float rim = band(r, 0.44 - widen, 0.96, aa);
	float core = 1.0 - smoothstep(0.17, 0.17 + aa, r);
	vec3 colour = rim_color.rgb;
	colour = mix(colour, ring_color.rgb, ring);
	colour = mix(colour, dot_color.rgb, core);
	float alpha = max(rim * rim_color.a, max(ring * ring_color.a, core * dot_color.a));
	ALBEDO = colour;
	ALPHA = alpha * opacity;
}
