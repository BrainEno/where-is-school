shader_type canvas_item;
// Dialogue portrait edges (scripts/ui/dialogue_panel.gd).
//
// The portraits are painted rectangles with their own grounds, not cut-out figures. Drawn
// as they are, a portrait reads as a card pinned to the screen. This dissolves the two
// edges that face the picture - the top and the side towards the text - into the scene,
// and leaves the edge on the screen border and the bottom edge hard, so the portrait looks
// like it stands in the frame rather than floats over it. No colour is changed and no
// border or glow is drawn; only alpha falls off.

// Width of each fade as a fraction of the drawn portrait; 0 leaves that edge hard.
uniform float fade_left : hint_range(0.0, 0.5) = 0.0;
uniform float fade_right : hint_range(0.0, 0.5) = 0.0;
uniform float fade_top : hint_range(0.0, 0.5) = 0.1;

void fragment() {
	float alpha = 1.0;
	if (fade_left > 0.0) {
		alpha *= smoothstep(0.0, fade_left, UV.x);
	}
	if (fade_right > 0.0) {
		alpha *= smoothstep(0.0, fade_right, 1.0 - UV.x);
	}
	if (fade_top > 0.0) {
		alpha *= smoothstep(0.0, fade_top, UV.y);
	}
	COLOR.a *= alpha;
}
