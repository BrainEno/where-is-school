shader_type spatial;
render_mode diffuse_toon, specular_disabled;

// Round 20: the yard round the court is plain cast concrete, laid in 2 m slabs on the
// world grid (the court's own joints fall on the same even metres), with cloud shadows
// drifting slowly across it, after the owner's two references: a tiled plane running to
// the horizon under airbrushed shadows. Procedural and texture-free (no texture inputs, see
// tests/location_art_test.gd); the walking surface is still the yard slab below.
// Kept no brighter than the `ground` material the HUD contrast test measures.
varying vec2 ground_position;
// Toon diffuse, like the court and yard materials (`diffuse_mode = 3`): under the low dusk
// sun a Lambert/Burley falloff left the slabs near-black beside the lit court. `fill` is a
// low self-light on top, so the concrete reads pale in the teaching block's shadow too.


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

// Four octaves, each turned and doubled in frequency.
float fbm(vec2 p) {
    float sum = 0.5 * grain(p);
    p = vec2(1.6 * p.x - 1.2 * p.y, 1.2 * p.x + 1.6 * p.y);
    sum += 0.25 * grain(p);
    p = vec2(1.6 * p.x - 1.2 * p.y, 1.2 * p.x + 1.6 * p.y);
    sum += 0.125 * grain(p);
    p = vec2(1.6 * p.x - 1.2 * p.y, 1.2 * p.x + 1.6 * p.y);
    sum += 0.0625 * grain(p);
    return sum / 0.9375;
}

void vertex() {
    ground_position = VERTEX.xz;
}

void fragment() {
    float SLAB = 2.0;
    vec3 PALE = vec3(0.150, 0.157, 0.176);  // linear: a cool, pale grey
    vec3 JOINT = vec3(0.024, 0.025, 0.030);
    vec2 WIND = vec2(0.30, 0.11);  // metres per second: one shadow crosses in minutes
    float fill = 0.25;
    vec2 p = ground_position;
    vec2 slab = floor(p / SLAB);
    vec2 f = p - slab * SLAB;
    float edge = min(min(f.x, SLAB - f.x), min(f.y, SLAB - f.y));
    // Each pour cured a shade apart; stains and the float's sweeps sit on top.
    float tone = hash(slab + 17.0) - 0.5;
    float stain = 0.6 * grain(p * 0.38 + 3.1) + 0.4 * grain(p * 0.9 + 7.7);
    float sweep = grain(vec2(p.x * 2.6, p.y * 0.7) + slab * 5.3);
    // Grit and the exposed aggregate. Kept to the frequencies of the old earth formula
    // (no hash of positions scaled past ~25): finer ones drew black in GL Compatibility.
    float grit = grain(p * 23.0);
    float pebble = grain(p * 11.0 + 5.0);
    vec3 c = PALE * (1.0 + 0.09 * tone + 0.20 * (stain - 0.5) + 0.05 * (sweep - 0.5));
    c *= 0.93 + 0.12 * grit;
    c *= 1.0 + 0.12 * smoothstep(0.86, 0.95, pebble) - 0.2 * (1.0 - smoothstep(0.05, 0.14, pebble));
    // Grime gathers along the sawn joints; their arrises are chipped here and there.
    c *= 1.0 - 0.14 * (1.0 - smoothstep(0.02, 0.14, edge));
    float chip = grain(p * 7.0 + 11.0);
    float width = 0.016 + 0.035 * chip * chip * chip * chip * chip * chip;
    float joint = 1.0 - smoothstep(0.011, width, edge);
    c = mix(c, JOINT, joint);
    // Cloud shadows, soft-edged and slow, the way they pass over a big flat yard.
    vec2 drift = (p - WIND * TIME) * 0.042;
    float cloud = fbm(drift);
    float shadow = smoothstep(0.50, 0.68, cloud);
    c *= mix(1.0, 0.56, shadow);
    ALBEDO = c;
    EMISSION = c * fill;
    ROUGHNESS = 1.0;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    // TEMPORARY DIAGNOSTIC (round 20): bands across the west yard, compatibility only.
    int band = int(floor((p.y + 9.0) / 1.5));
    if (band == 0) { ALBEDO = vec3(0.150, 0.157, 0.176); EMISSION = vec3(0.0); }
    if (band == 1) { ALBEDO = vec3(0.5); EMISSION = vec3(0.0); }
    if (band == 2) { ALBEDO = vec3(0.0); EMISSION = vec3(0.3); }
    if (band == 3) { ALBEDO = vec3(grit * 0.5); EMISSION = vec3(0.0); }
    if (band == 4) { ALBEDO = vec3(stain * 0.5); EMISSION = vec3(0.0); }
    if (band == 5) { ALBEDO = vec3(cloud * 0.5); EMISSION = vec3(0.0); }
    if (band == 6) { ALBEDO = vec3(tone + 0.5) * 0.5; EMISSION = vec3(0.0); }
    if (band == 7) { ALBEDO = c * 3.0; EMISSION = vec3(0.0); }
#endif
}
