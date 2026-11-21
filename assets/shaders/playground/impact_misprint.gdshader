// A two-plate print of the live yard, not a replacement sky or a camera effect.
// After #196's change of medium and #200's selective red. Only world pixels
// have been drawn at this layer; the notebook, prompts and object outline follow it.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D world_print : hint_screen_texture, repeat_disable, filter_linear;
uniform float impression : hint_range(0.0, 1.0) = 0.0;

float value(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float red_ink(vec3 c) {
	return smoothstep(0.035, 0.28, c.r - max(c.g, c.b)) * smoothstep(0.17, 0.48, c.r);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel = SCREEN_PIXEL_SIZE;
	vec2 paper = (uv / pixel) * (900.0 * pixel.y);
	vec3 original = texture(world_print, uv).rgb;
	float grey = value(original);

	// Two passes of the same plate almost line up. A single angled fold changes
	// their registration by a few pixels. The contours and the camera stay put.
	float fold = smoothstep(0.34, 0.355, uv.x + 0.39 * uv.y);
	vec2 drift = vec2(3.0 + 2.0 * fold, -1.5) * pixel * impression;
	vec3 red_plate = texture(world_print, uv + drift).rgb;
	float edge = max(abs(grey - value(texture(world_print, uv - vec2(1.7, 0.0) * pixel).rgb)),
		abs(grey - value(texture(world_print, uv - vec2(0.0, 1.7) * pixel).rgb)));

	// Off-white stock, slate midtone, blue-black pressure marks. Blend rather
	// than clip the bands so feet, rails and chalk routes still read.
	float band = floor(grey * 6.0 + 0.5) / 6.0;
	float density = mix(grey, band, 0.69);
	vec3 dry_blue = mix(vec3(0.12, 0.16, 0.23), vec3(0.49, 0.61, 0.65),
		smoothstep(0.04, 0.58, density));
	vec3 print = mix(dry_blue, vec3(0.93, 0.88, 0.76), smoothstep(0.51, 0.99, density));
	float vermilion = max(red_ink(original) * 0.56, red_ink(red_plate));
	vec3 red = mix(vec3(0.43, 0.16, 0.18), vec3(0.93, 0.53, 0.35), density);
	print = mix(print, red, vermilion * 0.91);
	print = mix(print, vec3(0.12, 0.15, 0.21), smoothstep(0.063, 0.29, edge) * 0.79);

	// A still, fine paper tooth and sparse slant of dry ink in the darker values.
	// Screen-height units keep those marks small on wide or resized windows.
	float tooth = fract(dot(floor(paper * vec2(0.74, 0.41)), vec2(0.754877, 0.56984))) - 0.5;
	float stroke = 1.0 - smoothstep(0.08, 0.24, abs(fract(dot(paper, vec2(0.18, -0.12))) - 0.5));
	print += tooth * 0.048 - stroke * (1.0 - smoothstep(0.15, 0.51, grey)) * 0.035;
	COLOR = vec4(mix(original, clamp(print, vec3(0.0), vec3(1.0)), impression), 1.0);
}
