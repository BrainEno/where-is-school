shader_type canvas_item;
render_mode unshaded, blend_disabled;
// The dazed look after a hurt landing (`ConcussionView`, docs/CONCUSSION_VIEW.md): the world
// seen as a postmodern paste-up - a photomontage of itself rather than a blur or a spin.
//
// It reads the finished frame (`hint_screen_texture`, which Forward+, Mobile and
// Compatibility all give a canvas item) and draws it back on a full-screen rect in a canvas
// layer under the outline and the UI, so it needs no depth buffer, no extra viewport and no
// renderer-specific feature.
//
// Nothing in it moves. There is no TIME: no wobble, no pulse, no drift, no temporal noise,
// because the brief is "an art style, not nausea". The only change is `daze`, which the
// script lowers over ten minutes of play, far too slowly to be seen as motion, and `seed`,
// which is changed only behind the black of a room change, so each room is a new paste-up.
//
// 1. Cuts. Four straight, slightly torn cuts slice the frame into sheets. Each sheet is the
//    same picture pasted a few pixels off its neighbours and printed in its own manner:
//    as it is, as a pink/teal duotone, as halftone newsprint on cream, or as a two-plate
//    riso print. The cuts get a paper edge and a drop shadow on one side.
// 2. A pasted quotation. Near one side a tilted, white-bordered cut-out holds an enlarged
//    copy of the middle of the frame - the protagonist quoting himself - in newsprint.
// 3. Memphis marks in the margins: a squiggle, a dot field, a ring. Flat, pastel, static.
// 4. The middle of the frame is protected: every treatment is weaker there, so the player,
//    the path and the outline cue stay legible.
//
// As `daze` falls the pieces leave in order - the quotation, then the marks, then the
// printing manners - and the last thing to go is a faint misregistration of the sheets.

uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
// 1 at the landing, 0 when the protagonist sees normally again.
uniform float daze : hint_range(0.0, 1.0) = 0.0;
// Which paste-up: set per room, behind black.
uniform float seed = 0.0;

const vec3 PAPER = vec3(0.95, 0.93, 0.86);
const vec3 TEAL = vec3(0.09, 0.41, 0.45);
const vec3 PINK = vec3(0.97, 0.60, 0.65);
const vec3 RISO_BLUE = vec3(0.16, 0.22, 0.56);
const vec3 RISO_YELLOW = vec3(0.98, 0.84, 0.27);
const vec3 INK = vec3(0.10, 0.11, 0.15);

float hash(float n) {
	return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

float soft_noise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Angled halftone: 1 where the dot is inked. `cells` is the dot pitch in screen pixels.
float halftone(vec2 pixel_pos, float value, float cells) {
	vec2 grid = mat2(vec2(0.966, -0.259), vec2(0.259, 0.966)) * pixel_pos / cells;
	float radius = mix(0.52, 0.06, value);
	return 1.0 - smoothstep(radius - 0.08, radius + 0.08, length(fract(grid) - 0.5));
}

vec3 print_manner(float manner, vec3 c, vec3 plate, vec2 pixel_pos) {
	float v = luma(c);
	if (manner < 1.0) {
		return c;
	}
	if (manner < 2.0) {
		return mix(TEAL, PINK, smoothstep(0.08, 0.82, v));
	}
	if (manner < 3.0) {
		float ink = halftone(pixel_pos, smoothstep(0.05, 0.95, v), 4.6);
		return mix(PAPER, INK, ink * 0.88);
	}
	// Two plates that do not quite line up: blue carries the shadows, yellow the light,
	// and the yellow plate is read from the misregistered sample.
	vec3 riso = mix(PAPER, RISO_BLUE, 1.0 - smoothstep(0.10, 0.70, v));
	return mix(riso, RISO_YELLOW, smoothstep(0.55, 0.95, luma(plate)) * 0.75);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	vec2 q = vec2(uv.x * aspect, uv.y);
	vec2 pixel_pos = uv / px;
	vec3 original = texture(screen, uv).rgb;
	float d = clamp(daze, 0.0, 1.0);

	// How strong things may be here: weaker in the middle of the frame.
	float centre = length((uv - 0.5) * vec2(aspect, 1.0));
	float margin = smoothstep(0.10, 0.46, centre);
	float strength = d * mix(0.38, 1.0, margin);

	// --- 1. Cuts: which sheet this pixel is on, and how near a cut it is.
	float sheet = 0.0;
	float edge_px = 10000.0;
	float shadow_side = 0.0;
	for (int k = 0; k < 4; k++) {
		float fk = float(k);
		vec2 anchor = vec2((0.15 + 0.7 * hash(fk * 3.17 + 1.0)) * aspect, 0.15 + 0.7 * hash(fk * 5.31 + 2.0));
		float angle = hash(fk * 7.13 + 3.0) * 3.14159;
		vec2 normal = vec2(cos(angle), sin(angle));
		vec2 along_dir = vec2(-normal.y, normal.x);
		float along = dot(q - anchor, along_dir);
		// A torn edge: a few pixels of irregularity along the cut, fixed in place.
		float tear = (soft_noise(along * 90.0 + fk * 11.0) - 0.5) * 0.0045;
		float side = dot(q - anchor, normal) + tear;
		sheet += step(0.0, side) * exp2(fk);
		float dist = abs(side) / px.y;
		edge_px = min(edge_px, dist);
		// The shadow falls on the negative side of each cut, a few pixels wide.
		shadow_side = max(shadow_side, (1.0 - smoothstep(2.0, 7.0, dist)) * step(side, 0.0));
	}

	// Each sheet is pasted slightly off, and printed in its own manner.
	vec2 jitter = vec2(hash(sheet * 3.1 + 7.0), hash(sheet * 4.7 + 9.0)) - 0.5;
	// The middle keeps almost all of its register, so the protagonist is never split.
	vec2 offset = jitter * 2.0 * 12.0 * px * d * mix(0.08, 1.0, margin);
	float manner = floor(hash(sheet * 7.7 + 13.0) * 4.0);
	vec3 pasted = texture(screen, uv + offset).rgb;
	vec3 plate = texture(screen, uv + offset + vec2(3.0, -2.0) * px * strength).rgb;
	vec3 printed = print_manner(manner, pasted, plate, pixel_pos);
	float manner_weight = smoothstep(0.12, 0.55, d) * mix(0.30, 0.86, margin);
	vec3 collage = mix(pasted, printed, manner_weight);

	// Paper edges and drop shadows along the cuts.
	// Cut edges fade out in the middle of the frame: no white line across the protagonist.
	float clear_middle = smoothstep(0.07, 0.24, centre);
	float edge = (1.0 - smoothstep(1.2, 2.6, edge_px)) * smoothstep(0.05, 0.30, d) * clear_middle;
	collage = mix(collage, collage * 0.72, shadow_side * smoothstep(0.08, 0.35, d) * 0.8 * clear_middle);
	collage = mix(collage, PAPER, edge * 0.92);

	// --- 2. The pasted quotation: an enlarged copy of the middle, tilted, white-bordered.
	float quote_in = smoothstep(0.32, 0.55, d);
	if (quote_in > 0.0) {
		float left = step(0.5, hash(21.0));
		vec2 c = vec2(mix(0.80, 0.20, left) * aspect, 0.30 + 0.38 * hash(23.0));
		float tilt = (hash(25.0) - 0.5) * 0.22;
		mat2 rot = mat2(vec2(cos(tilt), sin(tilt)), vec2(-sin(tilt), cos(tilt)));
		vec2 half_size = vec2(0.15, 0.11);
		vec2 local_pos = rot * (q - c);
		vec2 shadow_pos = rot * (q - c - vec2(0.008, 0.010));
		float border = 0.010;
		float in_shadow = step(abs(shadow_pos.x), half_size.x + border) * step(abs(shadow_pos.y), half_size.y + border);
		float in_frame = step(abs(local_pos.x), half_size.x + border) * step(abs(local_pos.y), half_size.y + border);
		float in_picture = step(abs(local_pos.x), half_size.x) * step(abs(local_pos.y), half_size.y);
		collage = mix(collage, collage * 0.6, in_shadow * (1.0 - in_frame) * quote_in);
		collage = mix(collage, PAPER, in_frame * quote_in);
		vec2 source = vec2(0.5) + vec2(local_pos.x / aspect, local_pos.y) * 0.62;
		vec3 quoted = texture(screen, source).rgb;
		float quoted_ink = halftone(pixel_pos, smoothstep(0.05, 0.95, luma(quoted)), 3.6);
		vec3 quote = mix(PAPER, INK, quoted_ink * 0.9);
		quote = mix(quote, PINK * 0.95, 0.18);
		collage = mix(collage, quote, in_picture * quote_in);
	}

	// --- 3. Memphis marks in the margins.
	float marks_in = smoothstep(0.18, 0.42, d) * smoothstep(0.30, 0.55, centre);
	if (marks_in > 0.0) {
		// A squiggle along the top or the bottom.
		float top = step(0.5, hash(31.0));
		float y_line = mix(0.92, 0.08, top) + 0.018 * sin(uv.x * aspect * 46.0 + seed);
		float squiggle = 1.0 - smoothstep(0.0025, 0.0045, abs(uv.y - y_line));
		collage = mix(collage, PINK, squiggle * marks_in * 0.9);
		// A dot field in one corner.
		vec2 corner = vec2(step(0.5, hash(33.0)), step(0.5, hash(35.0)));
		vec2 to_corner = abs(uv - corner);
		float field = step(to_corner.x, 0.20) * step(to_corner.y, 0.24);
		float dots = 1.0 - smoothstep(0.17, 0.23, length(fract(q * 30.0) - 0.5));
		collage = mix(collage, RISO_YELLOW, field * dots * marks_in * 0.85);
		// A ring in the opposite corner.
		vec2 ring_c = vec2((1.0 - corner.x) * 0.84 + 0.08, (1.0 - corner.y) * 0.80 + 0.10);
		float ring_r = length((uv - ring_c) * vec2(aspect, 1.0));
		float ring = 1.0 - smoothstep(0.004, 0.007, abs(ring_r - 0.065));
		collage = mix(collage, TEAL, ring * marks_in * 0.9);
	}

	// Paper tooth: static grain, strongest where the treatment is.
	float tooth = fract(dot(floor(pixel_pos * vec2(0.73, 0.41)), vec2(0.754877, 0.56984))) - 0.5;
	collage += tooth * 0.035 * strength;

	COLOR = vec4(mix(original, clamp(collage, vec3(0.0), vec3(1.0)), smoothstep(0.0, 0.04, d)), 1.0);
}
