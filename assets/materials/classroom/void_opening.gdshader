// The curtained window's opening: a hole through the west wall with nothing behind it.
//
// The wall itself belongs to the classroom's base geometry and is one box, so the hole
// cannot be cut into it. Instead this quad sits in the window opening, in front of the
// wall, and works out per pixel what a real hole would show from where the camera is:
// the ray from the camera through this pixel is followed into a box the size of the
// opening, and the first side it meets decides the colour. Near the mouth that is the
// broken thickness of the wall - raw section with a thin skin of plaster, and a ragged
// line where the brickwork stops. Past that line there is nothing to meet: no glass, no
// sill, no yard, no facade, so the ray ends in the void colour. The parallax is real
// (the band of broken wall widens on the far side as the camera moves), which is what
// separates it from a black texture; the depth written is the quad's own, so anyone
// standing in front of the window still covers it.
//
// Local to the classroom: nothing outside `assets/materials/classroom/` uses it.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_opaque;

// Half the opening, metres, in the quad's own x (along the wall) and y (up).
uniform vec2 half_size = vec2(0.77, 0.67);
// How deep the broken wall is before the brickwork stops.
uniform float wall_depth = 0.24;
// How far the ragged break line wanders either side of `wall_depth`.
uniform float break_jag = 0.045;
// Plaster skin at the mouth, then the wall's own section colour.
uniform vec3 plaster_colour : source_color = vec3(0.886, 0.847, 0.745);
uniform float plaster_depth = 0.03;
uniform vec3 section_colour : source_color = vec3(0.376, 0.282, 0.259);
// The absence: very dark, very slightly cold, a little lighter toward the horizon so
// the eye reads distance rather than a painted surface.
uniform vec3 void_low : source_color = vec3(0.010, 0.011, 0.014);
uniform vec3 void_high : source_color = vec3(0.034, 0.036, 0.046);

varying vec3 local_pos;
varying vec3 local_camera;

void vertex() {
	local_pos = VERTEX;
	vec3 camera_world = INV_VIEW_MATRIX[3].xyz;
	local_camera = (inverse(MODEL_MATRIX) * vec4(camera_world, 1.0)).xyz;
}

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ragged(float x) {
	float cell = floor(x);
	float f = fract(x);
	float a = hash12(vec2(cell, 3.7));
	float b = hash12(vec2(cell + 1.0, 3.7));
	return mix(a, b, f * f * (3.0 - 2.0 * f));
}

void fragment() {
	vec3 dir = normalize(local_pos - local_camera);
	// Only the room side of the quad is drawn (cull_back), so the ray always heads in
	// (dir.z < 0) and leaves the box through one of its four sides.
	float sx = abs(dir.x) < 1e-5 ? 1e-5 : dir.x;
	float sy = abs(dir.y) < 1e-5 ? 1e-5 : dir.y;
	float tx = ((dir.x >= 0.0 ? half_size.x : -half_size.x) - local_pos.x) / sx;
	float ty = ((dir.y >= 0.0 ? half_size.y : -half_size.y) - local_pos.y) / sy;
	tx = tx <= 0.0 ? 1e6 : tx;
	ty = ty <= 0.0 ? 1e6 : ty;
	float t = min(tx, ty);
	vec3 hit = local_pos + dir * t;
	float depth = -hit.z;
	// Where along the side the ray landed: drives the ragged edge and the grain.
	float along = tx < ty ? hit.y : hit.x;
	float stop = wall_depth + break_jag * (ragged(along * 11.0) * 2.0 - 1.0)
		+ 0.5 * break_jag * (ragged(along * 37.0 + 5.0) * 2.0 - 1.0);

	vec3 colour;
	if (depth < stop) {
		float skin = 1.0 - smoothstep(plaster_depth * 0.6, plaster_depth, depth);
		vec3 base = mix(section_colour, plaster_colour, skin);
		float grain = 0.86 + 0.14 * hash12(floor(vec2(along, depth) * 38.0));
		// Lit from the room: the mouth is as bright as the wall, the back of the cut is not.
		float light = mix(1.0, 0.42, clamp(depth / max(stop, 1e-3), 0.0, 1.0));
		// The sill (the bottom face, met while looking down) catches more of the room.
		if (ty < tx && dir.y < 0.0) {
			light *= 1.12;
		}
		colour = base * grain * light;
	} else {
		float horizon = smoothstep(-0.65, 0.35, dir.y);
		colour = mix(void_low, void_high, horizon);
		// A hairline of shadow right where the wall ends, so the stop reads as an edge.
		float rim = 1.0 - smoothstep(0.0, 0.035, depth - stop);
		colour = mix(colour, section_colour * 0.12, rim * 0.6);
	}
	ALBEDO = colour;
}
