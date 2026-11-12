shader_type canvas_item;
render_mode unshaded;

// The outline drawn around the object the player can use (scripts/interaction/outline_overlay.gd).
//
// `mask` is a viewport rendered from the player's camera. Its red channel is 1 where a
// highlighted mesh is the nearest thing to the camera and 0 everywhere else - including where
// the mesh is behind a wall or a desk (see outline_mask_key.gdshader). It is therefore the
// *visible* part of the object's silhouette in screen space: the outline traces the object as
// the player sees it - any mesh, any shape, no per-prop authoring - stops where something
// covers it, and is absent when the object is hidden. Its width is in pixels, not in metres,
// so a key on a desk and a doorway across the yard get the same pen.
//
// Three layers, drawn in this order:
//   fill - a faint wash over the object itself, so it lifts a little off the room;
//   rim  - a thin dark line just outside the outline, so it separates from a pale wall;
//   line - the outline proper: warm, thin, crisp, and breathing slowly.

uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec4 line_color : source_color = vec4(1.0, 0.87, 0.62, 1.0);
uniform vec4 rim_color : source_color = vec4(0.1, 0.075, 0.06, 0.55);
uniform float line_px = 2.0;
uniform float rim_px = 1.5;
uniform float fill_alpha = 0.07;
uniform float opacity = 0.0;
// How much of the line's alpha the slow breath takes away at its lowest point.
uniform float breath_depth = 0.18;
uniform float breath_hz = 0.6;

const int TAPS = 16;

// The highest mask coverage on a circle of `radius` pixels around `uv`: 1 when any part of
// the object is that close, which is what "inside the pen" means for an outline.
float reach(vec2 uv, float radius, vec2 texel) {
	float best = 0.0;
	for (int i = 0; i < TAPS; i++) {
		float angle = TAU * (float(i) + 0.5) / float(TAPS);
		best = max(best, texture(mask, uv + vec2(cos(angle), sin(angle)) * radius * texel).r);
	}
	return best;
}

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(mask, 0));
	float inside = texture(mask, UV).r;
	float near = max(reach(UV, line_px * 0.5, texel), reach(UV, line_px, texel));
	float far = max(near, reach(UV, line_px + rim_px, texel));
	float line = clamp(near - inside, 0.0, 1.0);
	float rim = clamp(far - near, 0.0, 1.0) * rim_color.a;
	float breath = 1.0 - breath_depth * (0.5 + 0.5 * sin(TIME * TAU * breath_hz));

	// Premultiplied "over" compositing, back to front: fill, rim, line.
	vec3 colour = line_color.rgb * inside * fill_alpha;
	float alpha = inside * fill_alpha;
	colour = rim_color.rgb * rim + colour * (1.0 - rim);
	alpha = rim + alpha * (1.0 - rim);
	float line_alpha = line * line_color.a * breath;
	colour = line_color.rgb * line_alpha + colour * (1.0 - line_alpha);
	alpha = line_alpha + alpha * (1.0 - line_alpha);

	alpha *= opacity;
	COLOR = vec4(alpha > 0.0001 ? colour * opacity / alpha : vec3(0.0), alpha);
}
