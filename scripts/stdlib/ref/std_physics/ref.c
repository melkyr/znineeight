/*
 * ref.c — C89 reference for std_physics (Position-Based Dynamics, PBD).
 *
 * Independent C89 implementation of the same Verlet + iterative
 * distance-constraint projection as sf/src/std_physics.zig. All persistent
 * particle state is f32; the distance length is computed in f64 by libm
 * `sqrt` and stored back as f32. The constraint shuffle uses the same
 * xoshiro256** seeding and rejection-sampling `xoshiroBounded` as std_rand.
 *
 * Crosscheck protocol (scenarios read until EOF):
 *   <seed decimal>
 *   <gravity_x> <gravity_y> <gravity_z>     (8-hex f32 bit patterns)
 *   <damping>                               (8-hex f32 bit pattern)
 *   <iterations decimal>
 *   <steps decimal>
 *   <dt>                                    (8-hex f32 bit pattern)
 *   <particle_count> <constraint_count>
 *   <x> <y> <z> <inv_mass>                  (particle_count lines)
 *   <a> <b> <stiffness>                     (constraint_count lines)
 * After `steps` pbdStep calls prints one line per particle:
 *   <x> <y> <z>                             (8-hex f32 bit patterns)
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>

typedef unsigned long long u64;
typedef unsigned int u32;

typedef struct {
    u64 s[4];
} Xoshiro256;

typedef struct {
    float pos[3];
    float prev[3];
    float inv_mass;
} Particle;

typedef struct {
    u32 a;
    u32 b;
    float rest;
    float stiffness;
} DistanceConstraint;

typedef struct {
    Particle *particles;
    DistanceConstraint *constraints;
    u32 *order;
    u32 particle_cap;
    u32 constraint_cap;
    u32 particle_count;
    u32 constraint_count;
    float gravity[3];
    float damping;
    unsigned char iterations;
    Xoshiro256 rng;
} PbdWorld;

typedef union {
    float f;
    u32 u;
} F32Bits;

static u32 f32_bits(float v)
{
    F32Bits x;
    x.f = v;
    return x.u;
}

static float bits_f32(u32 b)
{
    F32Bits x;
    x.u = b;
    return x.f;
}

static u64 rotl64(u64 x, unsigned n)
{
    n &= 63u;
    if (n == 0u) return x;
    return (x << n) | (x >> (64u - n));
}

static Xoshiro256 xoshiro_init(u64 seed)
{
    Xoshiro256 r;
    u64 x = seed;
    int i;
    for (i = 0; i < 4; i++) {
        u64 z;
        x += 0x9E3779B97F4A7C15ULL;
        z = x;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        r.s[i] = z ^ (z >> 31);
    }
    return r;
}

static u64 xoshiro_next(Xoshiro256 *r)
{
    u64 result = rotl64(r->s[1] * 5ULL, 7) * 9ULL;
    u64 t = r->s[1] << 17;
    r->s[2] ^= r->s[0];
    r->s[3] ^= r->s[1];
    r->s[1] ^= r->s[2];
    r->s[0] ^= r->s[3];
    r->s[2] ^= t;
    r->s[3] = rotl64(r->s[3], 45u);
    return result;
}

static u64 xoshiro_bounded(Xoshiro256 *r, u64 bound)
{
    u64 threshold = ((~bound) + 1ULL) % bound;
    for (;;) {
        u64 v = xoshiro_next(r);
        if (v >= threshold) return v % bound;
    }
}

static int pbd_init(PbdWorld *w, u32 np, u32 nc, u64 seed)
{
    u32 i;
    w->particle_cap = np;
    w->constraint_cap = nc;
    w->particle_count = 0;
    w->constraint_count = 0;
    w->particles = (Particle *)calloc((size_t)(np > 0 ? np : 1), sizeof(Particle));
    w->constraints = (DistanceConstraint *)calloc((size_t)(nc > 0 ? nc : 1), sizeof(DistanceConstraint));
    w->order = (u32 *)calloc((size_t)(nc > 0 ? nc : 1), sizeof(u32));
    if (w->particles == NULL || w->constraints == NULL || w->order == NULL) return 0;
    w->gravity[0] = 0.0f;
    w->gravity[1] = 0.0f;
    w->gravity[2] = 0.0f;
    w->damping = 0.0f;
    w->iterations = 4;
    w->rng = xoshiro_init(seed);
    for (i = 0; i < np; i++) {
        w->particles[i].pos[0] = 0.0f;
        w->particles[i].pos[1] = 0.0f;
        w->particles[i].pos[2] = 0.0f;
        w->particles[i].prev[0] = 0.0f;
        w->particles[i].prev[1] = 0.0f;
        w->particles[i].prev[2] = 0.0f;
        w->particles[i].inv_mass = 0.0f;
    }
    return 1;
}

static void pbd_free(PbdWorld *w)
{
    free(w->particles);
    free(w->constraints);
    free(w->order);
}

static u32 pbd_add_particle(PbdWorld *w, float x, float y, float z, float inv_mass)
{
    u32 idx = w->particle_count;
    Particle *p;
    if (idx >= w->particle_cap) return idx;
    p = &w->particles[idx];
    p->pos[0] = x;
    p->pos[1] = y;
    p->pos[2] = z;
    p->prev[0] = x;
    p->prev[1] = y;
    p->prev[2] = z;
    p->inv_mass = inv_mass;
    w->particle_count = idx + 1;
    return idx;
}

static float pbd_len(float dx, float dy, float dz)
{
    float sx = (float)(dx * dx);
    float sy = (float)(dy * dy);
    float sz = (float)(dz * dz);
    float sxy = (float)(sx + sy);
    float sum = (float)(sxy + sz);
    return (float)sqrt((double)sum);
}

static u32 pbd_add_distance(PbdWorld *w, u32 a, u32 b, float stiffness)
{
    u32 idx = w->constraint_count;
    DistanceConstraint *c;
    float dx, dy, dz, rest;
    if (idx >= w->constraint_cap) return idx;
    if (a == b) return idx;
    if (a >= w->particle_count || b >= w->particle_count) return idx;
    dx = w->particles[b].pos[0] - w->particles[a].pos[0];
    dy = w->particles[b].pos[1] - w->particles[a].pos[1];
    dz = w->particles[b].pos[2] - w->particles[a].pos[2];
    rest = pbd_len(dx, dy, dz);
    c = &w->constraints[idx];
    c->a = a;
    c->b = b;
    c->rest = rest;
    c->stiffness = stiffness;
    w->constraint_count = idx + 1;
    return idx;
}

static void pbd_step(PbdWorld *w, float dt)
{
    float zero = 0.0f;
    float one = 1.0f;
    float dt2;
    float keep;
    u32 i, j, k, cidx;
    unsigned char it;

    if (w->particle_count == 0) return;

    dt2 = dt * dt;
    keep = one - w->damping;
    for (i = 0; i < w->particle_count; i++) {
        Particle *p = &w->particles[i];
        float ox, oy, oz, vx, vy, vz, nx, ny, nz;
        if (p->inv_mass == zero) continue;
        ox = p->pos[0];
        oy = p->pos[1];
        oz = p->pos[2];
        vx = (float)(ox - p->prev[0]) * keep;
        vy = (float)(oy - p->prev[1]) * keep;
        vz = (float)(oz - p->prev[2]) * keep;
        nx = (float)(ox + vx) + (float)(w->gravity[0] * dt2);
        ny = (float)(oy + vy) + (float)(w->gravity[1] * dt2);
        nz = (float)(oz + vz) + (float)(w->gravity[2] * dt2);
        p->prev[0] = ox;
        p->prev[1] = oy;
        p->prev[2] = oz;
        p->pos[0] = nx;
        p->pos[1] = ny;
        p->pos[2] = nz;
    }

    if (w->constraint_count == 0 || w->iterations == 0) return;

    for (it = 0; it < w->iterations; it++) {
        for (j = 0; j < w->constraint_count; j++) {
            w->order[j] = j;
        }
        k = w->constraint_count - 1;
        while (k >= 1) {
            u32 r = (u32)xoshiro_bounded(&w->rng, (u64)k + 1ULL);
            u32 tmp = w->order[k];
            w->order[k] = w->order[r];
            w->order[r] = tmp;
            k--;
        }
        for (cidx = 0; cidx < w->constraint_count; cidx++) {
            DistanceConstraint *c = &w->constraints[w->order[cidx]];
            Particle *pa = &w->particles[c->a];
            Particle *pb = &w->particles[c->b];
            float dx, dy, dz, len, wa, wb, wsum, corr;
            float cax, cay, caz, cbx, cby, cbz;
            dx = pb->pos[0] - pa->pos[0];
            dy = pb->pos[1] - pa->pos[1];
            dz = pb->pos[2] - pa->pos[2];
            len = pbd_len(dx, dy, dz);
            if (len == zero) continue;
            wa = pa->inv_mass;
            wb = pb->inv_mass;
            wsum = wa + wb;
            if (wsum == zero) continue;
            corr = (float)((float)(len - c->rest) / len) * c->stiffness;
            cax = (float)((float)(dx * corr) * wa) / wsum;
            cay = (float)((float)(dy * corr) * wa) / wsum;
            caz = (float)((float)(dz * corr) * wa) / wsum;
            cbx = (float)((float)(dx * corr) * wb) / wsum;
            cby = (float)((float)(dy * corr) * wb) / wsum;
            cbz = (float)((float)(dz * corr) * wb) / wsum;
            pa->pos[0] += cax;
            pa->pos[1] += cay;
            pa->pos[2] += caz;
            pb->pos[0] -= cbx;
            pb->pos[1] -= cby;
            pb->pos[2] -= cbz;
        }
    }
}

static int read_line(char *buf, int n)
{
    if (fgets(buf, n, stdin) == NULL) return 0;
    while (*buf == ' ' || *buf == '\t' || *buf == '\r' || *buf == '\n') buf++;
    return 1;
}

int main(void)
{
    char line[1024];
    for (;;) {
        u64 seed;
        u32 gx, gy, gz, damping_bits, dt_bits;
        unsigned int iterations, steps;
        u32 np, nc;
        PbdWorld w;
        u32 i;
        unsigned int s;

        if (!read_line(line, (int)sizeof(line))) break;
        if (sscanf(line, "%llu", &seed) != 1) break;

        if (!read_line(line, (int)sizeof(line))) break;
        if (sscanf(line, "%x %x %x", &gx, &gy, &gz) != 3) break;

        if (!read_line(line, (int)sizeof(line))) break;
        if (sscanf(line, "%x", &damping_bits) != 1) break;

        if (!read_line(line, (int)sizeof(line))) break;
        if (sscanf(line, "%u", &iterations) != 1) break;

        if (!read_line(line, (int)sizeof(line))) break;
        if (sscanf(line, "%u", &steps) != 1) break;

        if (!read_line(line, (int)sizeof(line))) break;
        if (sscanf(line, "%x", &dt_bits) != 1) break;

        if (!read_line(line, (int)sizeof(line))) break;
        if (sscanf(line, "%u %u", &np, &nc) != 2) break;

        if (!pbd_init(&w, np, nc, seed)) break;
        w.gravity[0] = bits_f32(gx);
        w.gravity[1] = bits_f32(gy);
        w.gravity[2] = bits_f32(gz);
        w.damping = bits_f32(damping_bits);
        w.iterations = (unsigned char)iterations;

        for (i = 0; i < np; i++) {
            u32 x, y, z, m;
            if (!read_line(line, (int)sizeof(line))) break;
            if (sscanf(line, "%x %x %x %x", &x, &y, &z, &m) != 4) break;
            pbd_add_particle(&w, bits_f32(x), bits_f32(y), bits_f32(z), bits_f32(m));
        }
        for (i = 0; i < nc; i++) {
            unsigned int a, b;
            u32 k;
            if (!read_line(line, (int)sizeof(line))) break;
            if (sscanf(line, "%u %u %x", &a, &b, &k) != 3) break;
            pbd_add_distance(&w, (u32)a, (u32)b, bits_f32(k));
        }

        for (s = 0; s < steps; s++) {
            pbd_step(&w, bits_f32(dt_bits));
        }
        for (i = 0; i < w.particle_count; i++) {
            printf("%08x %08x %08x\n",
                   f32_bits(w.particles[i].pos[0]),
                   f32_bits(w.particles[i].pos[1]),
                   f32_bits(w.particles[i].pos[2]));
        }
        pbd_free(&w);
    }
    return 0;
}
