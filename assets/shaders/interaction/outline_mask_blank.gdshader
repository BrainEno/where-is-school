shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, blend_mix;

// Wipes the outline mask to black after the scene has been drawn into it
// (scripts/interaction/outline_overlay.gd).
//
// The mask viewport renders the whole scene, so that the scene's depth is in its depth buffer
// when the highlighted meshes are keyed in (`outline_mask_key.gdshader`). The colours that pass
// leaves behind are noise for the mask. This full-screen quad paints over all of them - it
// does not test or write depth, so the depth buffer survives - and it sorts after every other
// transparent surface (render priority one below the key's), so nothing the scene draws in its
// transparent pass is left on top of it.
//
// Mask camera only, for the same reason as the key: the quad sits on `MASK_LAYER`, which the
// player's camera does not draw, and it collapses itself for any other camera regardless.

const uint MASK_LAYER = 524288u; // visual layer 20, OutlineOverlay.MASK_LAYER

void vertex() {
	// The quad's corners are (-1, -1)..(1, 1): straight to clip space. z = 0.5 is inside the
	// clip volume for both the OpenGL (-1..1) and the Vulkan/D3D (0..1) conventions.
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
	if ((CAMERA_VISIBLE_LAYERS & MASK_LAYER) == 0u) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 1.0;
}
