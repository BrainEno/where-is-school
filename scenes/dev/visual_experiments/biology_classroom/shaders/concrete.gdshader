// Biology classroom experiment only (scenes/dev/ is excluded from every export preset).
//
// Poured concrete. Promoted to the game's classroom when the experiment was migrated: the
// body now lives in one place, `res://assets/materials/classroom/shaders/concrete.gdshaderinc`,
// and this file and the game's `concrete.gdshader` are both only this header and the include.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

#include "res://assets/materials/classroom/shaders/concrete.gdshaderinc"
