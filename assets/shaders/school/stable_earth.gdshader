shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;

// The stable yard's trodden earth (docs/EXAM_DREAM_ART.md). The relief is real geometry
// (tools/stable_ground.py) over the flat walking slab. Round 22: it is painted with the
// front yard's packed dirt, the same picture and the same 4 m world tile as
// stage_art/materials/yard_dirt.tres (a world-triplanar StandardMaterial; on ground that
// faces up its plan projection is exactly this one), with the same toon diffuse and no
// specular. Because the tile is laid in world space, the relief, the lane connector and
// the village ground past the wall all meet without an offset. `fill` keeps the stable's
// low self-light so the earth stays brown in the dusk shadows; `shade` darkens the
// stall floors and the village ground beyond the walls.
uniform sampler2D dirt : source_color, filter_linear_mipmap, repeat_enable;
uniform float tile_scale = 0.25;
uniform float fill : hint_range(0.0, 1.0) = 0.5;
uniform float shade : hint_range(0.0, 1.0) = 1.0;

varying vec2 ground_position;

void vertex() {
	// StandardMaterial3D's triplanar samples its up-facing plane with (z, x); so does this.
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).zx;
}

void fragment() {
	vec3 earth = texture(dirt, ground_position * tile_scale).rgb * shade;
	ALBEDO = earth;
	ROUGHNESS = 1.0;
	EMISSION = earth * fill;
}
