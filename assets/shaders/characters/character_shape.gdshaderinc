// Look-level silhouette shaping, shared by character_paint.gdshader and
// character_outline.gdshader so a part and its ink hull always move together (and its
// shadow, which is drawn with the same vertex code).
//
// Up to two soft ellipsoids in the model's *rest* space (the bind-pose position the
// `CharacterLookApplier` copies into CUSTOM0, w = 2; the skinned position when a mesh has
// none). A vertex inside one is pushed along its own skinned normal by `shape_offset`
// metres at the centre, fading to nothing at the ellipsoid's surface: negative takes a form
// in (a cardigan's flared hem), positive lets it out (the crown of a bob). Because the
// region is chosen in rest space and the push follows the posed normal, the change stays on
// the same cloth while the limbs move, and a model at rest is the GLB's own shape outside
// the ellipsoids. Nothing in the GLB changes; the default (no radius) is the GLB exactly.
//
// Kept to centimetres on purpose: it is a correction of silhouette and proportion, not a
// remodel, and garments layered over each other only stay closed for small offsets.

uniform vec3 shape_center = vec3(0.0);
uniform vec3 shape_radius = vec3(0.0);
uniform float shape_offset : hint_range(-0.05, 0.05) = 0.0;
uniform vec3 shape2_center = vec3(0.0);
uniform vec3 shape2_radius = vec3(0.0);
uniform float shape2_offset : hint_range(-0.05, 0.05) = 0.0;

float character_shape_weight(vec3 rest, vec3 center, vec3 radius) {
	if (radius.x <= 0.0 || radius.y <= 0.0 || radius.z <= 0.0) {
		return 0.0;
	}
	float d = length((rest - center) / radius);
	return 1.0 - smoothstep(0.3, 1.0, d);
}

// The push for one vertex, in the same space as `normal`.
vec3 character_shape_push(vec3 rest, vec3 normal) {
	float amount = shape_offset * character_shape_weight(rest, shape_center, shape_radius)
			+ shape2_offset * character_shape_weight(rest, shape2_center, shape2_radius);
	return normalize(normal) * amount;
}
