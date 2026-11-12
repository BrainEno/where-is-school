shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

// The highlighted meshes' own pixels in the outline mask (scripts/interaction/outline_overlay.gd).
//
// `OutlineOverlay` hangs this on each highlighted mesh as (the end of) its `material_overlay`
// chain. An overlay is drawn after the scene's opaque geometry, with the depth test on, over
// the same surface: so it lands exactly on the parts of the mesh that are in front of
// everything else, and on nothing that a wall or a desk hides. That is the whole of the
// occlusion: the depth buffer the mask viewport has just filled, used the way every overlay
// uses it. No depth texture is read, so nothing here depends on a renderer feature.
//
// It writes white. `outline_mask_blank.gdshader` has already painted the mask black, one
// priority step earlier, so the mask's red channel is "visible part of the highlighted object".
//
// It draws only for the mask camera. The mask camera sees `MASK_LAYER`; the overlay strips
// that layer from the player's camera, so in the frame the player sees this pass is moved off
// screen in the vertex stage and costs one vertex pass per highlighted surface, no pixels.

const uint MASK_LAYER = 524288u; // visual layer 20, OutlineOverlay.MASK_LAYER

// A small pull towards the camera, so the overlay is never behind the surface it covers: the
// overlay's vertex code is not the mesh material's, and two programs need not round the same
// position to the same depth. Moving along the view ray keeps every pixel where it was.
// Fixed part in metres, plus a part proportional to distance (depth precision falls off
// with distance). At the 3-12 m the camera works at this is 5-14 mm: well under any real gap
// between an object and the thing in front of it.
uniform float pull_m = 0.002;
uniform float pull_per_m = 0.001;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float distance_m = length(view.xyz);
	if (distance_m > 0.0001) {
		view.xyz -= view.xyz / distance_m * (pull_m + pull_per_m * distance_m);
	}
	POSITION = PROJECTION_MATRIX * view;
	if ((CAMERA_VISIBLE_LAYERS & MASK_LAYER) == 0u) {
		// Not the mask camera: outside the clip volume, so the primitive is dropped.
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	ALBEDO = vec3(1.0);
	ALPHA = 1.0;
}
