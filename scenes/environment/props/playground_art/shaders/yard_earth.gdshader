shader_type spatial;
render_mode diffuse_burley, specular_disabled;

// Original procedural mineral pigment; physical walking remains on the yard slab.
varying vec2 ground_position;
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float grain(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), u.x), u.y);
}
void vertex() {
    ground_position = VERTEX.xz;
}
void fragment() {
    float mottle = grain(ground_position * 0.55);
    float grit = grain(ground_position * 28.0);
    vec3 earth = mix(vec3(0.27, 0.19, 0.13), vec3(0.50, 0.39, 0.28), mottle);
    ALBEDO = earth * (0.88 + 0.24 * grit);
    ROUGHNESS = 1.0;
}
