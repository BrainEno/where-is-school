// Biology classroom experiment only (scenes/dev/ is excluded from every export preset).
//
// A drawn contour for the furniture: the mesh again, pushed out along its normals and seen
// from behind (front faces culled), in one warm-violet ink. Used as `material_overlay`, so
// it costs one extra draw per mesh and needs no screen or depth read. On flat-shaded boxes
// the pushed faces part at the corners, which leaves the small gaps a pen leaves.
shader_type spatial;
render_mode unshaded, cull_front, specular_disabled, shadows_disabled;

uniform vec4 ink : source_color = vec4(0.18, 0.16, 0.2, 1.0);
uniform float width = 0.012;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = ink.rgb;
}
