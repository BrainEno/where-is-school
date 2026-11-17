shader_type spatial;
// character_paint.gdshader drawn from both sides, for a part whose GLB material is
// double-sided *and* whose triangles face inward. N's eyeballs (`ST_Eye_L`, `ST_Eye_R` in
// teacher-n.glb) are such a part: every sclera, iris and pupil triangle is wound, and its
// normal points, into the eyeball. Under the one-sided shader their front halves were
// culled and what showed through was the inside of the back wall: blank, ringed eyes.
// With culling off, Godot flips NORMAL on back faces, so the half facing the camera is lit
// as if it faced outward. Everything else is character_paint.gdshader.
render_mode specular_disabled, cull_disabled, depth_draw_opaque;

#include "res://assets/shaders/characters/character_paint.gdshaderinc"
