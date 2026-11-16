// The classroom's poured concrete (floor and platform), migrated from the approved
// biology-classroom experiment. The body lives in `concrete.gdshaderinc`, shared with the
// experiment; see there for what it draws and what its uniforms do.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

#include "res://assets/materials/classroom/shaders/concrete.gdshaderinc"
