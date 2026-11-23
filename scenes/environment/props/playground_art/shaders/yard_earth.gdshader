shader_type spatial;
render_mode diffuse_burley, specular_disabled;

// Round 20: the yard round the court is plain cast concrete, laid in 2 m slabs on the
// world grid (the court's own joints fall on the same even metres), with cloud shadows
// drifting slowly across it, after the owner's two references: a tiled plane running to
// the horizon under airbrushed shadows. Procedural and texture-free (no texture inputs, see
// tests/location_art_test.gd); the walking surface is still the yard slab below.
// Kept no brighter than the `ground` material the HUD contrast test measures.
varying vec2 ground_position;

const float SLAB = 2.0;
const vec3 PALE = vec3(0.150, 0.157, 0.176);  // linear: a cool, pale grey
const vec3 JOINT = vec3(0.024, 0.025, 0.030);
const vec2 WIND = vec2(0.30, 0.11);  // metres per second: one shadow crosses in minutes

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

float fbm(vec2 p) {
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        sum += amp * grain(p);
        p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p;
        amp *= 0.5;
    }
    return sum / 0.9375;
}

void vertex() {
    ground_position = VERTEX.xz;
}

void fragment() {
    vec2 p = ground_position;
    vec2 slab = floor(p / SLAB);
    vec2 f = p - slab * SLAB;
    float edge = min(min(f.x, SLAB - f.x), min(f.y, SLAB - f.y));
    // Each pour cured a shade apart; stains and the float's sweeps sit on top.
    float tone = hash(slab + 17.0) - 0.5;
    float stain = fbm(p * 0.38 + 3.1);
    float sweep = grain(vec2(p.x * 2.6, p.y * 0.7) + slab * 5.3);
    float grit = grain(p * 42.0);
    vec3 c = PALE * (1.0 + 0.09 * tone + 0.20 * (stain - 0.5) + 0.05 * (sweep - 0.5));
    c *= 0.93 + 0.12 * grit;
    // Exposed aggregate: pale and dark stones a few millimetres across.
    float stone = hash(floor(p * 70.0));
    c *= 1.0 + 0.16 * step(0.965, stone) - 0.28 * step(stone, 0.025);
    // Grime gathers along the sawn joints; their arrises are chipped here and there.
    c *= 1.0 - 0.14 * (1.0 - smoothstep(0.02, 0.14, edge));
    float chip = grain(p * 7.0 + 11.0);
    float joint = 1.0 - smoothstep(0.011, 0.016 + 0.035 * pow(chip, 6.0), edge);
    c = mix(c, JOINT, joint);
    // Cloud shadows, soft-edged and slow, the way they pass over a big flat yard.
    float cloud = fbm((p - WIND * TIME) * 0.042);
    float shadow = smoothstep(0.50, 0.68, cloud);
    c *= mix(1.0, 0.56, shadow);
    ALBEDO = c;
    ROUGHNESS = 1.0;
}
