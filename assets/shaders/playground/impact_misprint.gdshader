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
	return smoothstep(0.038, 0.21, c.r - max(c.g, c.b)) * smoothstep(0.12, 0.42, c.r);
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

	// Open the dusk shadows onto slate ink and ivory stock. Blending with the
	// original value between bands keeps thin rails and the chalk lines readable.
	float lift = sqrt(max(0.0, grey));
	float band = floor(lift * 5.0 + 0.5) * 0.2;
	float density = mix(lift, band, 0.78);
	vec3 slate = mix(vec3(0.08, 0.11, 0.17), vec3(0.42, 0.56, 0.60),
		smoothstep(0.03, 0.64, density));
	vec3 print = mix(slate, vec3(0.92, 0.88, 0.77), smoothstep(0.50, 0.94, density));
	float vermilion = max(red_ink(original) * 0.43, red_ink(red_plate));
	vec3 red = mix(vec3(0.41, 0.20, 0.23), vec3(0.90, 0.47, 0.31),
		smoothstep(0.16, 0.88, density));
	print = mix(print, red, vermilion * 0.94);
	print = mix(print, vec3(0.11, 0.15, 0.21), smoothstep(0.062, 0.28, edge) * 0.78);

	// Static angled halftone dots are larger in the midtones. No temporal noise
	// or scene judder; this is printed on a sheet, rather than projected in the yard.
	vec2 raster = fract(mat2(vec2(0.91, -0.414), vec2(0.414, 0.91)) * paper / 5.8) - 0.5;
	float radius = mix(0.36, 0.10, density);
	float dot_ink = 1.0 - smoothstep(radius - 0.065, radius + 0.065, length(raster));
	float halftone = smoothstep(0.13, 0.28, density) * (1.0 - smoothstep(0.68, 0.95, density));
	float tooth = fract(dot(floor(paper * vec2(0.74, 0.41)), vec2(0.754877, 0.56984))) - 0.5;
	print += tooth * 0.046 - dot_ink * halftone * 0.10;
	COLOR = vec4(mix(original, clamp(print, vec3(0.0), vec3(1.0)), impression), 1.0);
}
