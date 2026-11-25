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
//
// `glyph` 1 draws the talk mark instead: the same green pen and the same rim as a speech bubble
// with three dots, for a person to talk to (`Interactable.uses_talk_cue`). The bubble is the
// same size as the ring - one pixel quad, one pen - so the two marks are one instrument.

uniform vec4 ring_color : source_color = vec4(0.55, 0.92, 0.5, 1.0);
uniform vec4 dot_color : source_color = vec4(0.86, 1.0, 0.82, 1.0);
uniform vec4 rim_color : source_color = vec4(0.02, 0.07, 0.03, 0.62);
// Diameter of the quad in pixels at a 900-pixel-high window; scaled with the window height.
uniform float pixel_size = 24.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.0;
// 0..1 breathing, written by the cue; it only widens the ring by a pixel or so.
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
// 0 = the look ring, 1 = the talk bubble.
uniform int glyph : hint_range(0, 1) = 0;

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

// Signed distance to a rounded box with the given half size, centred on the origin.
float rounded_box(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + vec2(radius);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

// The talk bubble, in a space where +y is up: a rounded body with a small tail hanging from its
// lower left. The tail is a square turned by 45 degrees, which is enough at this size.
float bubble_distance(vec2 p) {
	float body = rounded_box(p - vec2(0.0, 0.16), vec2(0.66, 0.46), 0.30);
	vec2 t = p - vec2(-0.36, -0.40);
	t = vec2(t.x - t.y, t.x + t.y) * 0.70710678;
	float tail = rounded_box(t, vec2(0.14), 0.03);
	return min(body, tail);
}

vec4 look_ring(vec2 p) {
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
	return vec4(colour, alpha);
}

vec4 talk_bubble(vec2 p) {
	// Flip to a y-up space: the quad's UV runs downwards, and the tail must hang below.
	vec2 b = vec2(p.x, -p.y);
	float d = bubble_distance(b);
	float aa = max(fwidth(d), 0.001) * 1.25;
	float widen = 0.04 * pulse;
	float outline = 1.0 - smoothstep(0.10 + widen - aa, 0.10 + widen + aa, abs(d));
	float rim = 1.0 - smoothstep(0.22 - aa, 0.22 + aa, abs(d));
	// Three dots in the body: the mark of someone about to speak.
	float dots = 0.0;
	for (int i = 0; i < 3; i++) {
		float x = -0.30 + 0.30 * float(i);
		dots = max(dots, 1.0 - smoothstep(0.10 - aa, 0.10 + aa, length(b - vec2(x, 0.16))));
	}
	vec3 colour = rim_color.rgb;
	colour = mix(colour, ring_color.rgb, outline);
	colour = mix(colour, dot_color.rgb, dots);
	float alpha = max(rim * rim_color.a, max(outline * ring_color.a, dots * dot_color.a));
	return vec4(colour, alpha);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec4 mark = glyph == 1 ? talk_bubble(p) : look_ring(p);
	ALBEDO = mark.rgb;
	ALPHA = mark.a * opacity;
}
