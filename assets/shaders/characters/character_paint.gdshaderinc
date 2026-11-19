// Body of the characters' painted surface, shared by character_paint.gdshader (one-sided)
// and character_paint_two_sided.gdshader. Its notes are in character_paint.gdshader.

#include "res://assets/shaders/characters/character_shape.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.5);
// Opt in for meshes with painted-in detail (e.g. the Teacher B review asset).
// Existing flat-colour looks keep their authored palette unchanged.
uniform bool use_vertex_paint = false;
// Multiplier for the shadow side's light: the colour shadows are painted in.
uniform vec3 shade_tint : source_color = vec3(0.55, 0.55, 0.7);
// Multiplier for the lit side (a warm or cool cast on the light).
uniform vec3 light_tint : source_color = vec3(1.0);
// How much light the shadow side keeps, before the tint.
uniform float shadow_fill : hint_range(0.0, 1.0) = 0.28;
// The half-tone band's brightness between shadow (0) and light (1).
uniform float half_tone : hint_range(0.0, 1.0) = 0.62;
// Where the bands change, in N·L. Lower moves the light further round the form.
uniform float shadow_edge : hint_range(-1.0, 1.0) = -0.05;
uniform float light_edge : hint_range(-1.0, 1.0) = 0.42;
// The light band's level. A flat band at 1.0 holds every lit surface at the brightness
// Lambert gives only where the light hits square on (N·L = 1); across the band N·L
// averages about 0.75, so 1.0 burns pale skin to cream under the warm rooms' key light.
uniform float light_strength : hint_range(0.3, 1.2) = 0.76;
uniform float edge_softness : hint_range(0.001, 0.4) = 0.05;
// How far the pigment breaks the band edges, in N·L.
uniform float edge_break : hint_range(0.0, 0.6) = 0.18;

// Pigment blocks.
uniform float pigment_scale : hint_range(0.5, 40.0) = 9.0;
// Stretch of a block along each object axis (2 on Y makes vertical strokes).
uniform vec3 pigment_stretch = vec3(1.0, 2.2, 1.0);
uniform float pigment_steps : hint_range(2.0, 8.0) = 4.0;
// Value variation across the blocks (0.15 = ±15%).
uniform float pigment_value : hint_range(0.0, 0.6) = 0.14;
uniform vec3 pigment_a : source_color = vec3(0.5);
uniform vec3 pigment_b : source_color = vec3(0.5);
// How far the blocks pull the albedo towards pigment_a / pigment_b.
uniform float pigment_mix : hint_range(0.0, 1.0) = 0.3;
uniform float pigment_seed = 0.0;
// Optional glazing between the stepped pigments. Zero preserves the existing charcoal
// and oil looks; N and the seated student use it to avoid large, mask-like skin patches.
uniform float pigment_blend : hint_range(0.0, 1.0) = 0.0;

// Fine, matte surface work, in the same bind coordinates as the broad paint. This is
// deliberately opt-in: 0 = none, 1 = knitted loops, 2 = woven twill, 3 = curved hair.
// It adds no geometry, normals, specular or texture dependency to the untextured models.
uniform int detail_kind : hint_range(0, 3) = 0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.0;
uniform float detail_scale : hint_range(10.0, 400.0) = 100.0;
uniform vec3 detail_tint : source_color = vec3(0.5);
uniform vec3 detail_origin = vec3(0.0, 1.6, 0.0);

// Painted patches: an ellipsoid in rest/object space, optionally mirrored across x = 0.
uniform vec3 patch_center = vec3(0.0);
uniform vec3 patch_radius = vec3(0.0);
uniform vec3 patch_color : source_color = vec3(0.4, 0.3, 0.45);
uniform float patch_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 patch2_center = vec3(0.0);
uniform vec3 patch2_radius = vec3(0.0);
uniform vec3 patch2_color : source_color = vec3(0.6, 0.3, 0.25);
uniform float patch2_strength : hint_range(0.0, 1.0) = 0.0;
uniform bool patch_mirror_x = true;
// The x the patches mirror across: the middle of the face (Q's sits 1.2 cm off x = 0).
uniform float mirror_center_x = 0.0;
// A glaze, not a hard cosmetic disc. Off for the previously authored paint patches.
uniform float patch_feather : hint_range(0.0, 1.0) = 0.0;

// Stroke marks (all off while `mark_strength` is 0).
uniform float mark_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 mark_color : source_color = vec3(0.85, 0.8, 0.7);
// Strokes per metre, counted across them.
uniform float mark_scale : hint_range(5.0, 400.0) = 90.0;
// The direction the strokes are counted across, in rest space: the strokes themselves run
// at right angles to it. (1, 0.3, 0) gives near-vertical strokes leaning a little.
uniform vec3 mark_across = vec3(1.0, 0.3, 0.0);
// A stroke's thickness as a share of the spacing.
uniform float mark_width : hint_range(0.02, 0.95) = 0.3;
// How long a stroke runs before it breaks, in spacings.
uniform float mark_length : hint_range(1.0, 60.0) = 6.0;
// How much of the part carries strokes everywhere, and how much more towards the
// silhouette (1 - |N·V|, raised to `mark_contour_power`).
uniform float mark_coverage : hint_range(0.0, 1.0) = 0.0;
uniform float mark_contour : hint_range(0.0, 1.0) = 0.0;
uniform float mark_contour_power : hint_range(0.5, 8.0) = 2.0;
// How far a stroke wanders off its straight line, in spacings.
uniform float mark_jitter : hint_range(0.0, 1.5) = 0.5;

varying vec3 paint_position;

float hash31(vec3 p) {
	vec3 q = fract(p * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.x + q.y) * q.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	float x00 = mix(hash31(cell), hash31(cell + vec3(1.0, 0.0, 0.0)), t.x);
	float x10 = mix(hash31(cell + vec3(0.0, 1.0, 0.0)), hash31(cell + vec3(1.0, 1.0, 0.0)), t.x);
	float x01 = mix(hash31(cell + vec3(0.0, 0.0, 1.0)), hash31(cell + vec3(1.0, 0.0, 1.0)), t.x);
	float x11 = mix(hash31(cell + vec3(0.0, 1.0, 1.0)), hash31(cell + vec3(1.0, 1.0, 1.0)), t.x);
	return mix(mix(x00, x10, t.y), mix(x01, x11, t.y), t.z);
}

// 0..1, two octaves, stretched.
float pigment_field(vec3 p) {
	vec3 q = p * pigment_scale / max(pigment_stretch, vec3(0.05)) + vec3(pigment_seed);
	return value_noise(q) * 0.68 + value_noise(q * 2.37 + vec3(11.7, 3.1, 7.9)) * 0.32;
}

float patch_mask(vec3 p, vec3 center, vec3 radius, float noise) {
	if (radius.x <= 0.0 || radius.y <= 0.0 || radius.z <= 0.0) {
		return 0.0;
	}
	vec3 q = p;
	if (patch_mirror_x) {
		q.x = mirror_center_x + abs(q.x - mirror_center_x);
	}
	float d = length((q - center) / radius);
	// Keep the original broken edge at zero; feathering softens both its inner edge and
	// noise, so the new small facial glazes do not turn into rings or bruises.
	return 1.0 - smoothstep(mix(0.72, 0.22, patch_feather), 0.9,
		d + (noise - 0.5) * mix(0.45, 0.12, patch_feather));
}

// A zero-mean thread. Fade to the underlying paint, not a screen-door/checker pattern,
// before a cycle becomes sub-pixel. Derivatives are only used in fragment(), never light().
float resolved_thread(float cycles) {
	float visible = 1.0 - smoothstep(0.32, 0.9, fwidth(cycles));
	return sin(cycles * 6.28318530718) * visible;
}

float cloth_threads(vec2 uv) {
	vec2 q = uv * detail_scale;
	if (detail_kind == 1) {
		// V-shaped interlocking loops, rather than straight pinstripes on a cardigan.
		float course = q.y * 0.72;
		float loop = q.x + abs(fract(course) - 0.5) * 0.85;
		return resolved_thread(loop) * 0.72 + resolved_thread(course) * 0.28;
	}
	// Restrained warp, weft and diagonal twill for the shirt and trousers.
	return resolved_thread(q.x) * 0.4 + resolved_thread(q.y) * 0.25
		+ resolved_thread(q.x * 0.5 + q.y * 0.5) * 0.35;
}

vec3 surface_detail(vec3 p, vec3 colour) {
	float thread = 0.0;
	if (detail_kind == 3) {
		vec3 local = p - detail_origin;
		float angle = atan(local.x, local.z + 0.00001);
		// Integer turns meet at the back of the head; the strands curve around the bob
		// instead of painting the same parallel hatch over its front and sides.
		float turns = max(floor(detail_scale * 0.1 + 0.5), 1.0);
		float flow = angle * turns / 6.28318530718
			+ sin(local.y * 21.0 + angle * 2.0) * 0.12;
		thread = resolved_thread(flow) * 0.75 + resolved_thread(flow * 3.0) * 0.25;
	} else {
		// Rest-space derivatives recover the unposed surface orientation. A posed/view
		// normal would rotate the projection when an arm moves, making the cloth swim.
		vec3 n = normalize(cross(dFdx(p), dFdy(p)) + vec3(0.0000000001));
		vec3 weight = pow(abs(n), vec3(4.0));
		weight /= max(weight.x + weight.y + weight.z, 0.0001);
		thread = cloth_threads(p.zy) * weight.x + cloth_threads(p.xz) * weight.y
			+ cloth_threads(p.xy) * weight.z;
	}
	// Diffuse-only highlights: no shiny skin, metal yarn or moving hair highlight.
	colour *= 1.0 + thread * detail_strength * 0.25;
	return mix(colour, detail_tint, max(thread, 0.0) * detail_strength * 0.55);
}

// 0..1: how much stroke covers this fragment (already faded with distance to the
// stroke's average coverage, see the header).
float mark_mask(vec3 p, float facing) {
	vec3 across = normalize(mark_across);
	float wander = (value_noise(p * mark_scale * 0.11 + vec3(5.3, 1.7, 9.1)) - 0.5) * 2.0 * mark_jitter;
	float s = dot(p, across) * mark_scale + wander;
	float lane = floor(s);
	float half_width = mark_width * 0.5;
	float line = 1.0 - smoothstep(half_width - 0.07, half_width + 0.07, abs(fract(s) - 0.5));
	float local = clamp(mark_coverage + mark_contour * pow(1.0 - facing, mark_contour_power), 0.0, 1.0);
	float segment = value_noise(p * (mark_scale / mark_length) + vec3(lane * 7.13, lane * 3.71, lane * 1.37));
	float present = smoothstep(1.0 - local - 0.06, 1.0 - local + 0.06, segment);
	// Strokes thinner than about a pixel become their average tone.
	float pixel = fwidth(s);
	float resolved = 1.0 - smoothstep(0.3, 0.75, pixel);
	return mix(local * mark_width, line * present, resolved);
}

void vertex() {
	paint_position = CUSTOM0.w > 1.5 ? CUSTOM0.xyz : VERTEX;
	VERTEX += character_shape_push(paint_position, NORMAL);
}

void fragment() {
	float n = pigment_field(paint_position);
	float steps = max(pigment_steps, 2.0);
	float block = floor(n * steps) / (steps - 1.0);
	block = clamp(block, 0.0, 1.0);
	block = mix(block, smoothstep(0.18, 0.82, n), pigment_blend);
	vec3 drift = mix(pigment_a, pigment_b, block);
	vec3 colour = mix(albedo, drift, pigment_mix);
	colour *= 1.0 + (block - 0.5) * 2.0 * pigment_value;
	colour = mix(colour, patch_color, patch_mask(paint_position, patch_center, patch_radius, n) * patch_strength);
	colour = mix(colour, patch2_color, patch_mask(paint_position, patch2_center, patch2_radius, n) * patch2_strength);
	if (mark_strength > 0.0) {
		colour = mix(colour, mark_color, mark_mask(paint_position, abs(dot(NORMAL, VIEW))) * mark_strength);
	}
	if (detail_strength > 0.0 && detail_kind != 0) {
		colour = surface_detail(paint_position, colour);
	}
	if (use_vertex_paint) {
		colour *= COLOR.rgb;
	}
	ALBEDO = clamp(colour, vec3(0.0), vec3(1.0));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	// Recomputed here rather than passed from fragment(): vertex-to-light varyings work on
	// every renderer this project is captured with (Forward+ and Compatibility).
	float n = pigment_field(paint_position);
	float ndl = dot(NORMAL, LIGHT) + (n - 0.5) * edge_break;
	float half_band = smoothstep(shadow_edge - edge_softness, shadow_edge + edge_softness, ndl);
	float light_band = smoothstep(light_edge - edge_softness, light_edge + edge_softness, ndl);
	float lit = mix(0.0, half_tone, half_band);
	lit = mix(lit, 1.0, light_band) * light_strength;
	vec3 tint = mix(shade_tint * shadow_fill, light_tint, lit);
	DIFFUSE_LIGHT += tint * ATTENUATION * LIGHT_COLOR / PI;
}
