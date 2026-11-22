shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Soft three-dimensional drifting wisps; the halo and ground stains keep their paper shader.
uniform vec3 rise = vec3(0.0);
uniform float rise_rate = 0.07;
uniform float fade_edge = 0.28;
uniform float spin = 0.0;
uniform float wobble = 0.0;
uniform float phase = 0.0;
varying float life;

void vertex() {
    float p = phase + float(INSTANCE_ID) * 0.618034;
    float t = fract(TIME * rise_rate + p);
    float a = spin * TIME + p * 6.2831853;
    VERTEX.xz = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a))) * VERTEX.xz;
    VERTEX.x += sin(TIME * 0.5 + p * 6.28) * wobble * 0.1;
    VERTEX += rise * t;
    life = smoothstep(0.0, fade_edge, t) * (1.0 - smoothstep(1.0 - fade_edge, 1.0, t));
}
void fragment() {
    float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
    ALBEDO = mix(COLOR.rgb / 2.0, COLOR.rgb, 0.5);
    ALPHA = life * 0.10 * (1.0 - rim * 0.65);
}
