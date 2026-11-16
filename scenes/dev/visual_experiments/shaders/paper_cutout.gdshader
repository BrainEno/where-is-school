// Visual experiments lab only (scenes/dev/ is excluded from every export preset).
//
// One sheet of paper pasted into 3D space: a procedural or sampled surface, a torn
// silhouette and the white fibre band a real tear leaves. The tear is a `discard`, not
// alpha blending, so the sheet sorts like an opaque surface, writes depth, casts a clean
// shadow and behaves the same on Forward+, Mobile and Compatibility.
//
// Patterns (uniform `pattern`):
//   0 plain colour       1 ruled notebook      2 graph paper        3 newsprint halftone
//   4 kraft fibre        5 sampled texture     6 perspective grid   7 crayon hatching
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert, specular_disabled;

uniform int pattern = 0;
uniform vec4 paper_color : source_color = vec4(0.93, 0.9, 0.82, 1.0);
uniform vec4 ink_color : source_color = vec4(0.24, 0.33, 0.58, 1.0);
uniform sampler2D source_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform vec2 texture_scale = vec2(1.0, 1.0);
uniform vec2 texture_offset = vec2(0.0, 0.0);
// Sheet size in metres: keeps rulings, fibres and tears the same physical size on every
// sheet, whatever its aspect.
uniform vec2 sheet_size = vec2(1.0, 1.0);
uniform float pattern_density = 1.0;
uniform float seed = 0.0;
// How far the torn edge eats into the sheet, in metres, and the width of the white
// fibre band just inside it. 0 keeps a straight guillotine edge.
uniform float tear_depth = 0.05;
uniform float fibre_width = 0.012;
uniform vec4 fibre_color : source_color = vec4(0.97, 0.96, 0.92, 1.0);
// Fraction of the colour returned as emission: paper that half ignores the scene light
// reads as pasted on, not built.
uniform float flatness = 0.35;
// Perspective grid: where the drawn lines converge, in UV. Deliberately not where the
// real room's lines converge.
uniform vec2 vanishing_point = vec2(0.5, -0.35);
// 0 keeps the sampled colour; 3..8 bands it like a cheap print or a poster.
uniform float posterize_levels = 0.0;
uniform float grain = 0.06;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		total += amplitude * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return total;
}

float line_mask(float coordinate, float spacing, float width) {
	float distance_to_line = abs(fract(coordinate / spacing + 0.5) - 0.5) * spacing;
	return 1.0 - smoothstep(width * 0.5, width, distance_to_line);
}

vec3 surface_colour(vec2 uv, vec2 metres) {
	vec3 paper = paper_color.rgb;
	vec3 ink = ink_color.rgb;
	float density = max(pattern_density, 0.05);
	if (pattern == 1) {
		// Ruled notebook: blue rules every 8 mm-ish (scaled up for distance), one red margin.
		float rules = line_mask(metres.y, 0.09 / density, 0.006);
		float margin = line_mask(metres.x - 0.16, 1000.0, 0.007);
		vec3 colour = mix(paper, ink, rules * 0.75);
		return mix(colour, vec3(0.72, 0.36, 0.34), margin * 0.8);
	} else if (pattern == 2) {
		float minor = max(line_mask(metres.x, 0.05 / density, 0.003), line_mask(metres.y, 0.05 / density, 0.003));
		float major = max(line_mask(metres.x, 0.25 / density, 0.006), line_mask(metres.y, 0.25 / density, 0.006));
		return mix(paper, ink, max(minor * 0.35, major * 0.7));
	} else if (pattern == 3) {
		// Newsprint halftone: dot size follows a soft blotch, as if a photograph had been
		// reprinted until only the dots remained.
		float cell = 0.035 / density;
		vec2 rotated = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * metres;
		vec2 local = fract(rotated / cell) - 0.5;
		float tone = fbm(metres * 1.3 + seed);
		float radius = mix(0.08, 0.52, smoothstep(0.25, 0.75, tone));
		float dot_mask = 1.0 - smoothstep(radius - 0.06, radius, length(local));
		return mix(paper, ink, dot_mask * 0.9);
	} else if (pattern == 4) {
		float fibres = value_noise(vec2(metres.x * 6.0, metres.y * 90.0) + seed) * 0.6;
		fibres += fbm(metres * 9.0 + seed) * 0.4;
		return paper * (0.86 + fibres * 0.22);
	} else if (pattern == 5) {
		vec3 sampled = texture(source_texture, uv * texture_scale + texture_offset).rgb;
		if (posterize_levels >= 2.0) {
			sampled = floor(sampled * posterize_levels + 0.5) / posterize_levels;
		}
		return sampled * paper_color.rgb;
	} else if (pattern == 6) {
		// A floor drawn in one-point perspective on a sheet that lies flat on a real floor.
		vec2 from_vp = uv - vanishing_point;
		float angle = atan(from_vp.x, max(from_vp.y, 0.001));
		float rays = line_mask(angle, 0.12 / density, 0.008);
		float depth = 1.0 / max(from_vp.y, 0.02);
		float rows = line_mask(depth, 0.9 / density, 0.05 * depth * from_vp.y);
		return mix(paper, ink, max(rays, rows) * 0.8);
	} else if (pattern == 7) {
		float wobble = (value_noise(metres * 3.0 + seed) - 0.5) * 0.04;
		float hatch = line_mask(metres.x + metres.y + wobble, 0.045 / density, 0.012);
		float cross_hatch = line_mask(metres.x - metres.y - wobble, 0.06 / density, 0.009);
		float pressure = smoothstep(0.3, 0.8, fbm(metres * 0.9 + seed * 3.0));
		return mix(paper, ink, max(hatch, cross_hatch * pressure) * 0.85);
	}
	return paper;
}

void fragment() {
	vec2 metres = UV * sheet_size;
	vec2 edge = min(UV, vec2(1.0) - UV) * sheet_size;
	float edge_distance = min(edge.x, edge.y);
	float tear_noise = fbm(metres * 7.0 + vec2(seed * 13.7, seed * 5.3));
	float tear_line = tear_depth * (0.25 + 0.75 * tear_noise);
	if (tear_depth > 0.0 && edge_distance < tear_line) {
		discard;
	}
	vec3 colour = surface_colour(UV, metres);
	if (tear_depth > 0.0 && edge_distance < tear_line + fibre_width) {
		colour = mix(colour, fibre_color.rgb, 0.85);
	}
	float tooth = value_noise(metres * 140.0 + seed) - 0.5;
	colour *= 1.0 + tooth * grain;
	ALBEDO = colour;
	EMISSION = colour * flatness;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
