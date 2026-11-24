// Offline preview rasteriser for the character head study.
// Reads the WISP2 scene written by tools/head_preview.py and writes a PPM.
//
// This is an art-review tool, not the game renderer. It reproduces the *maths* of
// assets/shaders/characters/character_paint.gdshaderinc with the parameters it reads from the
// look's own .tres (pigment blocks, the two patches, the three light bands, the local detail
// maps), so what it shows is what the game's shader is told to draw. It has no ink outline
// pass, no environment and no engine light, so it cannot stand in for an engine capture: the
// evidence it produces is labelled "offline renderer" wherever it is reported.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct { float x, y, z; } V3;
typedef struct { float r, g, b, a; } V4;
typedef struct { V3 p, n, t, b; float u, v; V4 c; } Vert;
typedef struct {
    char name[64];
    V4 color;
    unsigned nv, nt;
    Vert *v;
    unsigned *t;
    float p[56];
    unsigned flags, tw, th;
    float *alb, *nrm;
} Obj;

static V3 v3(float x, float y, float z) { V3 a = {x, y, z}; return a; }
static V3 sub(V3 a, V3 b) { return v3(a.x - b.x, a.y - b.y, a.z - b.z); }
static V3 add(V3 a, V3 b) { return v3(a.x + b.x, a.y + b.y, a.z + b.z); }
static V3 mul(V3 a, float s) { return v3(a.x * s, a.y * s, a.z * s); }
static float dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static V3 cross(V3 a, V3 b) {
    return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}
static float len(V3 a) { return sqrtf(dot(a, a)); }
static V3 norm(V3 a) { float l = len(a); return l > 1e-12f ? mul(a, 1.0f / l) : v3(0, 0, 1); }
static float clamp01(float x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }
static float mixf(float a, float b, float t) { return a + (b - a) * t; }
static float smoothstepf(float a, float b, float x) {
    float t = clamp01((x - a) / (b - a));
    return t * t * (3.0f - 2.0f * t);
}

// The shader's hash31 / value_noise, so the pigment blocks land where the game puts them.
static float fractf(float x) { return x - floorf(x); }
static float hash31(V3 p) {
    float qx = fractf(p.x * 0.1031f), qy = fractf(p.y * 0.1030f), qz = fractf(p.z * 0.0973f);
    float d = qx * (qy + 33.33f) + qy * (qz + 33.33f) + qz * (qx + 33.33f);
    float ax = fractf(qx + d), ay = fractf(qy + d), az = fractf(qz + d);
    return fractf((ax + ay) * az);
}

static float vnoise(V3 p) {
    V3 c = v3(floorf(p.x), floorf(p.y), floorf(p.z));
    V3 f = v3(p.x - c.x, p.y - c.y, p.z - c.z);
    f = v3(f.x * f.x * (3 - 2 * f.x), f.y * f.y * (3 - 2 * f.y), f.z * f.z * (3 - 2 * f.z));
    float x00 = mixf(hash31(c), hash31(add(c, v3(1, 0, 0))), f.x);
    float x10 = mixf(hash31(add(c, v3(0, 1, 0))), hash31(add(c, v3(1, 1, 0))), f.x);
    float x01 = mixf(hash31(add(c, v3(0, 0, 1))), hash31(add(c, v3(1, 0, 1))), f.x);
    float x11 = mixf(hash31(add(c, v3(0, 1, 1))), hash31(add(c, v3(1, 1, 1))), f.x);
    return mixf(mixf(x00, x10, f.y), mixf(x01, x11, f.y), f.z);
}

// slot indices into Obj.p
enum {
    P_PIGMENT_SCALE = 0, P_PIGMENT_STRETCH = 1, P_PIGMENT_STEPS = 4, P_PIGMENT_VALUE = 5,
    P_PIGMENT_MIX = 6, P_PIGMENT_SEED = 7, P_PIGMENT_BLEND = 8,
    P_SHADE_TINT = 9, P_LIGHT_TINT = 12, P_SHADOW_FILL = 15, P_HALF_TONE = 16,
    P_SHADOW_EDGE = 17, P_LIGHT_EDGE = 18, P_EDGE_SOFTNESS = 19, P_LIGHT_STRENGTH = 20,
    P_EDGE_BREAK = 21, P_ALBEDO_MIX = 22, P_NORMAL_STRENGTH = 23,
    P_PATCH_CENTER = 24, P_PATCH_RADIUS = 27, P_PATCH_STRENGTH = 30, P_PATCH_MIRROR = 31,
    P_PATCH_COLOR = 32, P_PATCH2_CENTER = 35, P_PATCH2_RADIUS = 38, P_PATCH2_STRENGTH = 41,
    P_PATCH2_COLOR = 42, P_MIRROR_CENTER_X = 45, P_PATCH_FEATHER = 46,
    P_LIGHT_IS_BANDED = 47, P_PIGMENT_A = 48, P_PIGMENT_B = 51
};

static float pigment_field(V3 p, const float *q) {
    V3 stretch = v3(q[P_PIGMENT_STRETCH], q[P_PIGMENT_STRETCH + 1], q[P_PIGMENT_STRETCH + 2]);
    stretch.x = fmaxf(stretch.x, 0.05f);
    stretch.y = fmaxf(stretch.y, 0.05f);
    stretch.z = fmaxf(stretch.z, 0.05f);
    V3 s = v3(p.x / stretch.x, p.y / stretch.y, p.z / stretch.z);
    V3 a = add(mul(s, q[P_PIGMENT_SCALE]), v3(q[P_PIGMENT_SEED], q[P_PIGMENT_SEED], q[P_PIGMENT_SEED]));
    V3 b = add(mul(a, 2.37f), v3(11.7f, 3.1f, 7.9f));
    return vnoise(a) * 0.68f + vnoise(b) * 0.32f;
}

static float patch_mask(V3 p, const float *q, int which) {
    int c = which ? P_PATCH2_CENTER : P_PATCH_CENTER;
    int r = which ? P_PATCH2_RADIUS : P_PATCH_RADIUS;
    float strength = q[which ? P_PATCH2_STRENGTH : P_PATCH_STRENGTH];
    if (q[r] <= 0.0f || q[r + 1] <= 0.0f || q[r + 2] <= 0.0f || strength <= 0.0f) return 0.0f;
    V3 s = p;
    if (q[P_PATCH_MIRROR] > 0.5f) s.x = q[P_MIRROR_CENTER_X] + fabsf(s.x - q[P_MIRROR_CENTER_X]);
    float feather = q[P_PATCH_FEATHER];
    V3 d = v3((s.x - q[c]) / q[r], (s.y - q[c + 1]) / q[r + 1], (s.z - q[c + 2]) / q[r + 2]);
    float dist = len(d);
    float noise = pigment_field(p, q);
    return 1.0f - smoothstepf(mixf(0.72f, 0.22f, feather), 0.9f,
        dist + (noise - 0.5f) * mixf(0.45f, 0.12f, feather));
}

static void tex_sample(const float *tex, unsigned tw, unsigned th, float u, float v, float *out) {
    if (tex == 0 || tw == 0 || th == 0) { out[0] = out[1] = out[2] = 1.0f; return; }
    // Clamp to the edge: the atlas is not tiled, and the seam must not bleed the far side.
    float x = clamp01(u) * (float)tw - 0.5f;
    float y = clamp01(v) * (float)th - 0.5f;
    int x0 = (int)floorf(x), y0 = (int)floorf(y);
    float fx = x - x0, fy = y - y0;
    int xa = x0 < 0 ? 0 : (x0 >= (int)tw ? (int)tw - 1 : x0);
    int xb = x0 + 1 < 0 ? 0 : (x0 + 1 >= (int)tw ? (int)tw - 1 : x0 + 1);
    int ya = y0 < 0 ? 0 : (y0 >= (int)th ? (int)th - 1 : y0);
    int yb = y0 + 1 < 0 ? 0 : (y0 + 1 >= (int)th ? (int)th - 1 : y0 + 1);
    for (int k = 0; k < 3; k++) {
        float top = mixf(tex[(ya * (int)tw + xa) * 3 + k], tex[(ya * (int)tw + xb) * 3 + k], fx);
        float bot = mixf(tex[(yb * (int)tw + xa) * 3 + k], tex[(yb * (int)tw + xb) * 3 + k], fx);
        out[k] = mixf(top, bot, fy);
    }
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s scene.wisp2 out.ppm\n", argv[0]); return 2; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("scene"); return 1; }
    char magic[6] = {0};
    fread(magic, 1, 5, f);
    if (strcmp(magic, "WISP2")) { fprintf(stderr, "bad magic %s\n", magic); return 1; }
    unsigned version = 0, no = 0;
    fread(&version, 4, 1, f);
    fread(&no, 4, 1, f);
    if (version != 2) { fprintf(stderr, "unsupported scene version %u\n", version); return 1; }
    Obj *objs = calloc(no, sizeof(Obj));
    for (unsigned o = 0; o < no; o++) {
        Obj *ob = &objs[o];
        if (fread(ob->name, 1, 64, f) != 64) return 1;
        fread(&ob->color, sizeof(V4), 1, f);
        fread(&ob->nv, 4, 1, f);
        fread(&ob->nt, 4, 1, f);
        if (ob->nv == 0 || ob->nv > 8000000u || ob->nt == 0 || ob->nt > 16000000u) {
            fprintf(stderr, "object %u ('%s') has %u vertices and %u triangles\n",
                o, ob->name, ob->nv, ob->nt);
            return 1;
        }
        ob->v = calloc(ob->nv, sizeof(Vert));
        ob->t = calloc((size_t)ob->nt * 3, 4);
        fread(ob->v, sizeof(Vert), ob->nv, f);
        fread(ob->t, 4, (size_t)ob->nt * 3, f);
        fread(ob->p, 4, 56, f);
        fread(&ob->flags, 4, 1, f);
        fread(&ob->tw, 4, 1, f);
        fread(&ob->th, 4, 1, f);
        if (ob->flags & 1) {
            ob->alb = malloc(sizeof(float) * (size_t)ob->tw * ob->th * 3);
            fread(ob->alb, 4, (size_t)ob->tw * ob->th * 3, f);
        }
        if (ob->flags & 2) {
            ob->nrm = malloc(sizeof(float) * (size_t)ob->tw * ob->th * 3);
            fread(ob->nrm, 4, (size_t)ob->tw * ob->th * 3, f);
        }
    }
    unsigned W, H;
    fread(&W, 4, 1, f);
    fread(&H, 4, 1, f);
    float cam[3], tgt[3], up[3];
    fread(cam, 4, 3, f);
    fread(tgt, 4, 3, f);
    fread(up, 4, 3, f);
    float fov;
    fread(&fov, 4, 1, f);
    float ldir[3], lcol[3], amb[3];
    fread(ldir, 4, 3, f);
    fread(lcol, 4, 3, f);
    fread(amb, 4, 3, f);
    fclose(f);

    V3 cp = v3(cam[0], cam[1], cam[2]), ct = v3(tgt[0], tgt[1], tgt[2]);
    V3 fz = norm(sub(ct, cp));
    V3 rx = norm(cross(fz, v3(up[0], up[1], up[2])));
    V3 ry = cross(rx, fz);
    float aspect = (float)W / (float)H;
    float th = tanf(fov * 0.5f * (float)M_PI / 180.f);
    V3 L = norm(v3(ldir[0], ldir[1], ldir[2]));

    float *zbuf = malloc(sizeof(float) * (size_t)W * H);
    unsigned char *img = malloc((size_t)W * H * 3);
    for (unsigned i = 0; i < W * H; i++) {
        zbuf[i] = 1e30f;
        img[i * 3] = 24; img[i * 3 + 1] = 23; img[i * 3 + 2] = 28;
    }

    for (unsigned o = 0; o < no; o++) {
        Obj *ob = &objs[o];
        float *sx = malloc(sizeof(float) * ob->nv), *sy = malloc(sizeof(float) * ob->nv);
        float *sz = malloc(sizeof(float) * ob->nv), *invw = malloc(sizeof(float) * ob->nv);
        V3 *vn = malloc(sizeof(V3) * ob->nv), *vt = malloc(sizeof(V3) * ob->nv);
        V3 *vb = malloc(sizeof(V3) * ob->nv);
        for (unsigned i = 0; i < ob->nv; i++) {
            V3 d = sub(ob->v[i].p, cp);
            float z = dot(d, fz);
            float x = dot(d, rx), y = dot(d, ry);
            if (z < 0.02f) { invw[i] = 0; continue; }
            float iw = 1.0f / z;
            invw[i] = iw;
            sx[i] = (x * iw / (th * aspect) * 0.5f + 0.5f) * W;
            sy[i] = (0.5f - y * iw / th * 0.5f) * H;
            sz[i] = z;
            vn[i] = norm(ob->v[i].n);
            vt[i] = norm(ob->v[i].t);
            vb[i] = norm(ob->v[i].b);
        }
        for (unsigned t = 0; t < ob->nt; t++) {
            unsigned a = ob->t[t * 3], b = ob->t[t * 3 + 1], c = ob->t[t * 3 + 2];
            if (invw[a] == 0 || invw[b] == 0 || invw[c] == 0) continue;
            float minx = fminf(sx[a], fminf(sx[b], sx[c])), maxx = fmaxf(sx[a], fmaxf(sx[b], sx[c]));
            float miny = fminf(sy[a], fminf(sy[b], sy[c])), maxy = fmaxf(sy[a], fmaxf(sy[b], sy[c]));
            int x0 = (int)fmaxf(0, floorf(minx)), x1 = (int)fminf(W - 1, ceilf(maxx));
            int y0 = (int)fmaxf(0, floorf(miny)), y1 = (int)fminf(H - 1, ceilf(maxy));
            for (int py = y0; py <= y1; py++) for (int px = x0; px <= x1; px++) {
                float fx = px + 0.5f, fy = py + 0.5f;
                float d = (sy[b] - sy[c]) * (sx[a] - sx[c]) + (sx[c] - sx[b]) * (sy[a] - sy[c]);
                if (fabsf(d) < 1e-9f) continue;
                float wa = ((sy[b] - sy[c]) * (fx - sx[c]) + (sx[c] - sx[b]) * (fy - sy[c])) / d;
                float wb = ((sy[c] - sy[a]) * (fx - sx[c]) + (sx[a] - sx[c]) * (fy - sy[c])) / d;
                float wc = 1 - wa - wb;
                if (wa < 0 || wb < 0 || wc < 0) continue;
                float iw = wa * invw[a] + wb * invw[b] + wc * invw[c];
                float z = 1.0f / iw;
                unsigned idx = (unsigned)py * W + px;
                if (z >= zbuf[idx]) continue;
                zbuf[idx] = z;
                V3 n = norm(v3(wa * vn[a].x + wb * vn[b].x + wc * vn[c].x,
                               wa * vn[a].y + wb * vn[b].y + wc * vn[c].y,
                               wa * vn[a].z + wb * vn[b].z + wc * vn[c].z));
                V3 p = v3(wa * ob->v[a].p.x + wb * ob->v[b].p.x + wc * ob->v[c].p.x,
                          wa * ob->v[a].p.y + wb * ob->v[b].p.y + wc * ob->v[c].p.y,
                          wa * ob->v[a].p.z + wb * ob->v[b].p.z + wc * ob->v[c].p.z);
                float u = wa * ob->v[a].u + wb * ob->v[b].u + wc * ob->v[c].u;
                float v = wa * ob->v[a].v + wb * ob->v[b].v + wc * ob->v[c].v;
                V3 V = norm(sub(cp, p));

                // ---- fragment(): the same steps, in the same order ----
                float noise = pigment_field(p, ob->p);
                float steps = fmaxf(ob->p[P_PIGMENT_STEPS], 2.0f);
                float block = clamp01(floorf(noise * steps) / (steps - 1.0f));
                block = mixf(block, smoothstepf(0.18f, 0.82f, noise), ob->p[P_PIGMENT_BLEND]);
                float mixamt = ob->p[P_PIGMENT_MIX];
                V3 alb = v3(ob->color.r, ob->color.g, ob->color.b);
                alb.x *= wa * ob->v[a].c.r + wb * ob->v[b].c.r + wc * ob->v[c].c.r;
                alb.y *= wa * ob->v[a].c.g + wb * ob->v[b].c.g + wc * ob->v[c].c.g;
                alb.z *= wa * ob->v[a].c.b + wb * ob->v[b].c.b + wc * ob->v[c].c.b;
                V3 drift = v3(mixf(ob->p[P_PIGMENT_A], ob->p[P_PIGMENT_B], block),
                              mixf(ob->p[P_PIGMENT_A + 1], ob->p[P_PIGMENT_B + 1], block),
                              mixf(ob->p[P_PIGMENT_A + 2], ob->p[P_PIGMENT_B + 2], block));
                V3 colour = v3(mixf(alb.x, drift.x, mixamt), mixf(alb.y, drift.y, mixamt),
                               mixf(alb.z, drift.z, mixamt));
                colour = mul(colour, 1.0f + (block - 0.5f) * 2.0f * ob->p[P_PIGMENT_VALUE]);
                float m1 = patch_mask(p, ob->p, 0) * ob->p[P_PATCH_STRENGTH];
                colour = v3(mixf(colour.x, ob->p[P_PATCH_COLOR], m1),
                            mixf(colour.y, ob->p[P_PATCH_COLOR + 1], m1),
                            mixf(colour.z, ob->p[P_PATCH_COLOR + 2], m1));
                float m2 = patch_mask(p, ob->p, 1) * ob->p[P_PATCH2_STRENGTH];
                colour = v3(mixf(colour.x, ob->p[P_PATCH2_COLOR], m2),
                            mixf(colour.y, ob->p[P_PATCH2_COLOR + 1], m2),
                            mixf(colour.z, ob->p[P_PATCH2_COLOR + 2], m2));
                if (ob->flags & 1) {
                    float tex[3];
                    tex_sample(ob->alb, ob->tw, ob->th, u, v, tex);
                    float k = ob->p[P_ALBEDO_MIX];
                    colour = v3(colour.x * mixf(1.0f, tex[0], k),
                                colour.y * mixf(1.0f, tex[1], k),
                                colour.z * mixf(1.0f, tex[2], k));
                }
                if (ob->flags & 2) {
                    float tex[3];
                    tex_sample(ob->nrm, ob->tw, ob->th, u, v, tex);
                    V3 tn = v3(tex[0] * 2 - 1, tex[1] * 2 - 1, tex[2] * 2 - 1);
                    V3 T = norm(v3(wa * vt[a].x + wb * vt[b].x + wc * vt[c].x,
                                   wa * vt[a].y + wb * vt[b].y + wc * vt[c].y,
                                   wa * vt[a].z + wb * vt[b].z + wc * vt[c].z));
                    V3 B = norm(v3(wa * vb[a].x + wb * vb[b].x + wc * vb[c].x,
                                   wa * vb[a].y + wb * vb[b].y + wc * vb[c].y,
                                   wa * vb[a].z + wb * vb[b].z + wc * vb[c].z));
                    V3 mapped = norm(add(add(mul(T, tn.x), mul(B, tn.y)), mul(n, tn.z)));
                    float depth = ob->p[P_NORMAL_STRENGTH];
                    n = norm(add(mul(n, 1.0f - depth), mul(mapped, depth)));
                }
                // ---- light(): three bands ----
                float ndl = dot(n, L) + (noise - 0.5f) * ob->p[P_EDGE_BREAK];
                float es = ob->p[P_EDGE_SOFTNESS];
                float half_band = smoothstepf(ob->p[P_SHADOW_EDGE] - es, ob->p[P_SHADOW_EDGE] + es, ndl);
                float light_band = smoothstepf(ob->p[P_LIGHT_EDGE] - es, ob->p[P_LIGHT_EDGE] + es, ndl);
                float lit = mixf(0.0f, ob->p[P_HALF_TONE], half_band);
                lit = mixf(lit, 1.0f, light_band) * ob->p[P_LIGHT_STRENGTH];
                if (ob->p[P_LIGHT_IS_BANDED] < 0.5f) {
                    lit = clamp01(0.30f + 0.70f * clamp01((dot(n, L) + 0.35f) / 1.35f));
                }
                V3 shade = v3(mixf(ob->p[P_SHADE_TINT] * ob->p[P_SHADOW_FILL], ob->p[P_LIGHT_TINT], lit),
                              mixf(ob->p[P_SHADE_TINT + 1] * ob->p[P_SHADOW_FILL], ob->p[P_LIGHT_TINT + 1], lit),
                              mixf(ob->p[P_SHADE_TINT + 2] * ob->p[P_SHADOW_FILL], ob->p[P_LIGHT_TINT + 2], lit));
                // A neutral key light stands in for the room's DirectionalLight3D: the bands
                // and the tints are the look's, the level is not.
                float key = 1.35f;
                V3 lit3 = v3(colour.x * shade.x * key, colour.y * shade.y * key, colour.z * shade.z * key);
                unsigned char R = (unsigned char)(clamp01(powf(lit3.x, 1.0f / 2.2f)) * 255);
                unsigned char G = (unsigned char)(clamp01(powf(lit3.y, 1.0f / 2.2f)) * 255);
                unsigned char B = (unsigned char)(clamp01(powf(lit3.z, 1.0f / 2.2f)) * 255);
                img[idx * 3] = R; img[idx * 3 + 1] = G; img[idx * 3 + 2] = B;
            }
        }
        free(sx); free(sy); free(sz); free(invw); free(vn); free(vt); free(vb);
    }
    FILE *out = fopen(argv[2], "wb");
    fprintf(out, "P6\n%u %u\n255\n", W, H);
    fwrite(img, 1, (size_t)W * H * 3, out);
    fclose(out);
    return 0;
}
