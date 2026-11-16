// The local paper anomaly at the classroom's back window: the approved biology-classroom
// experiment's blank paper (scenes/dev/.../blank_paper.gdshader), brought into the game as
// a *place* instead of a filter on the whole picture.
//
// In the experiment, drawing the curtain turned the entire frame into a pencil drawing on
// an answer sheet. In the game only the ground round the opening turns: the floor, the
// wall either side of the cut, the curtain, the desks nearest it. The rest of the room
// keeps its own materials, so the drawing reads as something wrong *here*.
//
// How it stays put (why it cannot spread, and why it has no seam):
//
// * It is a `material_overlay` that `PaperZone` (scripts/environment/paper_zone.gd) lays
//   only on the meshes that reach into the zone. Nothing else in the room draws it.
// * Its mask is a distance in the world, not on the screen: the horizontal distance of the
//   fragment from `zone_centre` against `zone_radius`, with the experiment's ragged torn
//   front (`value_noise`) and a graphite rim. Every mesh computes the same function of the
//   same world position, so where two meshes meet the paper edge meets itself exactly, and
//   the edge is fixed to the floor and the wall whatever the camera does.
// * The pencil itself - the answer sheet's ruled lines, the red margin, the three hatching
//   families of `paper_marks.gdshaderinc` - is laid out in world metres on the plane each
//   face lies in (the concrete's projection), so it does not slide when the camera moves.
//   Hatching finer than a pixel fades out instead of shimmering.
// * It reads no screen texture, no depth texture and no SCREEN_UV, so it is the same on
//   Forward+, Mobile and Compatibility.
//
// The shading is the experiment's: a surface's value (its own tone, `base_value`, set per
// mesh by PaperZone, times the room's sun through a two-step terminator and its shadow)
// decides how many hatching families cover it. The sun is read in `light()`; the room's
// ambient light is disabled, so the paper is not tinted violet like the room around it.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled, ambient_light_disabled;

#include "res://assets/materials/classroom/shaders/paper_marks.gdshaderinc"

uniform vec3 zone_centre = vec3(0.0, 0.0, 0.0);
uniform float zone_radius = 2.6;
// 0 = nothing drawn yet, 1 = the zone's full extent: the front spreads out from the centre.
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float feather = 0.32;
uniform float ragged = 0.55;
uniform float rim_strength = 0.75;
// The mesh's own tone, 0..1 (PaperZone sets it from the mesh's material).
uniform float base_value : hint_range(0.0, 1.0) = 0.6;
uniform float terminator = 0.12;
uniform float softness = 0.03;
uniform vec4 paper_color : source_color = vec4(0.95, 0.94, 0.9, 1.0);
uniform vec4 graphite_color : source_color = vec4(0.26, 0.26, 0.3, 1.0);
uniform vec4 rule_color : source_color = vec4(0.55, 0.66, 0.84, 1.0);
uniform vec4 margin_color : source_color = vec4(0.86, 0.42, 0.4, 1.0);
// Metres between the answer sheet's ruled lines, and where its red margin runs (world x on
// the floor and the wall faces that look along x).
uniform float rule_spacing = 0.31;
uniform float margin_x = -6.2;
// The blank sheet in the opening itself: paper and its rules, opaque, with no zone, no
// hatching and no light on it ("nothing that can be lit").
uniform bool blank_sheet = false;
// Pencil lines per metre (the experiment's 100 lines per screen unit at its hatch scale).
uniform float hatch_density = 34.0;

varying vec3 world_position;
varying vec3 world_normal;
// 1 where the pencil lines are wider than a pixel, 0 where they would alias. From the
// camera distance in vertex() because light() has no derivatives.
varying float hatch_fade;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// A pixel of a 900-line frame at a 60-degree lens is about 0.0013 rad.
	float footprint = distance(world_position, INV_VIEW_MATRIX[3].xyz) * 0.0013;
	hatch_fade = 1.0 - smoothstep(0.6 / hatch_density, 1.4 / hatch_density, footprint);
}

// The plane a face lies in, in metres (the concrete's projection).
vec2 face_plane(vec3 position, vec3 normal) {
	vec3 n = abs(normal);
	if (n.y > 0.6) {
		return position.xz;
	}
	return n.x > n.z ? position.zy : position.xy;
}

// How much of this fragment is paper (0..1), and the graphite rim along the torn front.
vec2 zone_mask(vec3 position) {
	float reach = length(position.xz - zone_centre.xz);
	float tear = (value_noise(position.xz * 2.1 + vec2(position.y * 0.7, 3.0)) - 0.5) * ragged;
	float front = zone_radius * reveal;
	float covered = 1.0 - smoothstep(front - feather, front, reach + tear);
	float rim = (1.0 - smoothstep(0.0, 0.05, abs(front - feather * 0.55 - (reach + tear))));
	return vec2(covered * step(0.001, reveal), rim * step(0.001, reveal));
}

// The pencil's shading for a value (the experiment's mapping and thresholds).
float graphite_for(vec2 p, float value, float fade) {
	float darkness = 1.0 - smoothstep(0.06, 0.78, value);
	float shading = 0.0;
	shading += hatch(p, 0.79, hatch_density, 1.0) * step(0.22, darkness);
	shading += hatch(p, -0.79, hatch_density, 2.0) * step(0.5, darkness);
	shading += hatch(p, 0.12, hatch_density * 1.4, 3.0) * step(0.76, darkness);
	// Lines finer than the pixel turn into an even grey of the same weight.
	return mix(darkness * 0.42, shading * 0.45, fade);
}

void fragment() {
	vec2 mask = blank_sheet ? vec2(1.0, 0.0) : zone_mask(world_position);
	if (mask.x < 0.002 && mask.y < 0.002) {
		discard;
	}
	vec2 p = face_plane(world_position, world_normal);
	float footprint = max(length(fwidth(p)), 0.0001);
	// The answer sheet: faint blue rules across the plane, the red margin at `margin_x`.
	float row = abs(fract(p.y / rule_spacing) - 0.5) * rule_spacing;
	float rule = 1.0 - smoothstep(0.5 * rule_spacing - 0.004 - footprint, 0.5 * rule_spacing, row);
	float margin = 1.0 - smoothstep(0.008, 0.008 + footprint * 2.0, abs(world_position.x - margin_x));
	vec3 paper = paper_color.rgb;
	paper = mix(paper, rule_color.rgb, rule * 0.35);
	paper = mix(paper, margin_color.rgb, margin * 0.5 * step(0.6, abs(world_normal.y) + abs(world_normal.z)));
	paper *= 0.97 + 0.03 * value_noise(p * vec2(60.0, 8.0));
	ALBEDO = paper;
	ALPHA = clamp(max(mask.x, mask.y * rim_strength), 0.0, 1.0);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL && blank_sheet) {
		DIFFUSE_LIGHT += vec3(1.0);
	} else if (LIGHT_IS_DIRECTIONAL) {
		vec3 position = world_position;
		vec2 p = face_plane(position, world_normal);
		float lit = smoothstep(terminator - softness, terminator + softness, dot(NORMAL, LIGHT));
		lit *= ATTENUATION;
		// The value the experiment's filter would have read off the frame: the surface's own
		// tone, a quarter of it in shade.
		float value = base_value * (0.25 + 0.75 * lit);
		float graphite = clamp(graphite_for(p, value, hatch_fade), 0.0, 1.0);
		vec2 mask = zone_mask(position);
		graphite = max(graphite, mask.y * rim_strength * (1.0 - mask.x * 0.6));
		vec3 ink = graphite_color.rgb / max(paper_color.rgb, vec3(0.01));
		// Final colour = ALBEDO (the paper) x this: paper where the pencil did not go,
		// graphite where it did.
		DIFFUSE_LIGHT += mix(vec3(1.0), ink, graphite * 0.85);
	}
}
