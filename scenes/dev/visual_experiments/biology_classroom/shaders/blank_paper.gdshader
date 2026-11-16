// Biology classroom experiment only (scenes/dev/ is excluded from every export preset).
//
// The blank paper. When the curtain is drawn the view is no longer a room in colour but
// a pencil drawing of it on an answer sheet: the sheet's faint blue rules and red margin,
// values reduced to graphite hatching, edges drawn in, the dark void above the room shaded
// densely. Only one colour survives the change: red pencil (whatever in the frame is
// strongly red stays red, which is the ring).
//
// `reveal` spreads the paper outward from `origin` (the opening, in UV) with a ragged
// torn front, so the change is something seen arriving from the window.
//
// Developed from the visual lab's medium switch (`../../shaders/painting_filter.gdshader`):
// it reads only its own TEXTURE (a SubViewport of the same world), never the screen
// texture or the depth buffer, so it runs unchanged on Forward+, Mobile and Compatibility.
shader_type canvas_item;

uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform vec2 origin = vec2(0.2, 0.5);
uniform float screen_aspect = 1.7778;
// A uniform default must be a literal: `1.0 / 800.0` is not folded and fails to parse.
uniform vec2 texel = vec2(0.00125, 0.00222);
uniform vec4 paper_color : source_color = vec4(0.95, 0.94, 0.9, 1.0);
uniform vec4 graphite_color : source_color = vec4(0.26, 0.26, 0.3, 1.0);
uniform vec4 rule_color : source_color = vec4(0.55, 0.66, 0.84, 1.0);
uniform vec4 margin_color : source_color = vec4(0.86, 0.42, 0.4, 1.0);
uniform vec4 red_pencil : source_color = vec4(0.84, 0.14, 0.1, 1.0);
uniform float hatch_scale = 190.0;
uniform float edge_gain = 5.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// A family of parallel pencil lines at `angle`, `density` per unit, with breaks.
float hatch(vec2 p, float angle, float density, float seed) {
	vec2 dir = vec2(cos(angle), sin(angle));
	float along = dot(p, vec2(-dir.y, dir.x)) * density;
	float line = abs(fract(along) - 0.5) * 2.0;
	float broken = step(0.18, value_noise(vec2(dot(p, dir) * 3.0, floor(along) + seed)));
	return (1.0 - smoothstep(0.0, 0.42, line)) * broken;
}

void fragment() {
	vec2 aspect = vec2(screen_aspect, 1.0);
	// The hand is not a plotter: the drawing sits a hair off the photograph.
	vec2 wobble = (vec2(value_noise(UV * 9.0), value_noise(UV * 9.0 + 17.0)) - 0.5) * 0.004;
	vec2 uv = UV + wobble;
	vec3 source = texture(TEXTURE, UV).rgb;
	vec3 drawn_source = texture(TEXTURE, uv).rgb;
	float value = luma(drawn_source);
	float left = luma(texture(TEXTURE, uv - vec2(texel.x, 0.0)).rgb);
	float right = luma(texture(TEXTURE, uv + vec2(texel.x, 0.0)).rgb);
	float up = luma(texture(TEXTURE, uv - vec2(0.0, texel.y)).rgb);
	float down = luma(texture(TEXTURE, uv + vec2(0.0, texel.y)).rgb);
	float edge = clamp(length(vec2(right - left, down - up)) * edge_gain, 0.0, 1.0);
	edge *= step(0.3, value_noise(UV * 140.0));
	vec2 p = UV * aspect * (hatch_scale / 100.0);
	float darkness = 1.0 - smoothstep(0.06, 0.78, value);
	float shading = 0.0;
	shading += hatch(p, 0.79, 100.0, 1.0) * step(0.22, darkness);
	shading += hatch(p, -0.79, 100.0, 2.0) * step(0.5, darkness);
	shading += hatch(p, 0.12, 140.0, 3.0) * step(0.76, darkness);
	float graphite = clamp(shading * 0.45 + edge * 0.9, 0.0, 1.0);
	// The answer sheet: faint rules every 1/22 of the height, a red margin on the left.
	float rule = 1.0 - smoothstep(0.0, 0.0018, abs(fract(UV.y * 22.0) - 0.5) / 22.0);
	float margin = 1.0 - smoothstep(0.0, 0.0016, abs(UV.x - 0.085));
	vec3 paper = paper_color.rgb;
	paper = mix(paper, rule_color.rgb, rule * 0.35);
	paper = mix(paper, margin_color.rgb, margin * 0.5);
	paper *= 0.97 + 0.03 * value_noise(UV * vec2(300.0, 40.0));
	vec3 drawn = mix(paper, graphite_color.rgb, graphite * 0.85);
	float redness = source.r - max(source.g, source.b);
	drawn = mix(drawn, red_pencil.rgb, smoothstep(0.32, 0.5, redness));
	// The paper arrives from the opening, its front torn.
	float reach = distance(UV * aspect, origin * aspect);
	float ragged = (value_noise(UV * 26.0) - 0.5) * 0.12;
	float front = reveal * 2.4 - 0.05;
	float covered = 1.0 - smoothstep(front - 0.02, front, reach + ragged);
	float rim = covered * (1.0 - smoothstep(0.0, 0.025, front - (reach + ragged)));
	vec3 colour = mix(source, drawn, covered);
	colour = mix(colour, graphite_color.rgb, rim * step(0.001, reveal) * step(reveal, 0.999) * 0.8);
	COLOR = vec4(colour, 1.0);
}
