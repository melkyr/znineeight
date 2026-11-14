/*
 * ref.c — C89 reference for std_rand (PCG32 + xoshiro256**).
 *
 * Crosscheck protocol: one input line `seed stream count` (decimal u64, u64,
 * u32); two output lines per input:
 *   line 1: `count` lowercase hex u32 PCG32 outputs, single-space separated
 *   line 2: `count` lowercase hex u64 xoshiro256** outputs, 16 digits each
 * A `bounded seed stream bound count` line (decimal u64, u64, u32, u32) prints
 * one line of `count` lowercase hex u32 `pcg32Bounded` outputs (same rejection
 * sampling as the Z98 module).
 * With `--kat`, prints the KAT fixture's golden: 100 PCG32 outputs (8 hex
 * digits, one per line), 100 xoshiro256** outputs (16 hex digits, one per
 * line), then `rand kat ok`.
 *
 * PCG32 seeding is O'Neill's pcg32_srandom_r: state 0, odd increment
 * (stream << 1) | 1, one advance, add seed, one advance.
 */

#include <stdio.h>

typedef unsigned long long u64;
typedef unsigned int u32;

typedef struct {
    u64 state;
    u64 inc;
} Pcg32;

typedef struct {
    u64 s[4];
} Xoshiro256;

static u64 rotl64(u64 x, unsigned n)
{
    n &= 63u;
    if (n == 0u) return x;
    return (x << n) | (x >> (64u - n));
}

static u32 pcg32_next(Pcg32 *r);

static Pcg32 pcg32_init(u64 seed, u64 stream)
{
    Pcg32 r;
    r.state = 0ULL;
    r.inc = (stream << 1) | 1ULL;
    (void)pcg32_next(&r);
    r.state += seed;
    (void)pcg32_next(&r);
    return r;
}

static u32 pcg32_next(Pcg32 *r)
{
    u64 old = r->state;
    u32 xorshifted;
    u32 rot;
    r->state = old * 6364136223846793005ULL + r->inc;
    xorshifted = (u32)(((old >> 18) ^ old) >> 27);
    rot = (u32)(old >> 59);
    return (xorshifted >> rot) | (xorshifted << ((32u - rot) & 31u));
}

static u32 pcg32_bounded(Pcg32 *r, u32 bound)
{
    u64 b64 = (u64)bound;
    u32 threshold = (u32)(((1ULL << 32) - b64) % b64);
    for (;;) {
        u32 v = pcg32_next(r);
        if ((u64)v >= (u64)threshold) return v % bound;
    }
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

static int parse_u64(const char *s, int *pi, u64 *out)
{
    int i = *pi;
    int any = 0;
    u64 v = 0ULL;
    while (s[i] == ' ' || s[i] == '\t') i++;
    while (s[i] >= '0' && s[i] <= '9') {
        v = v * 10ULL + (u64)(s[i] - '0');
        i++;
        any = 1;
    }
    if (!any) return 0;
    *pi = i;
    *out = v;
    return 1;
}

static void kat(void)
{
    Pcg32 p = pcg32_init(0xDEADBEEFULL, 1ULL);
    Xoshiro256 x = xoshiro_init(0xDEADBEEFULL);
    int i;
    for (i = 0; i < 100; i++) {
        printf("%08x\n", pcg32_next(&p));
    }
    for (i = 0; i < 100; i++) {
        printf("%016llx\n", xoshiro_next(&x));
    }
    printf("rand kat ok\n");
}

int main(int argc, char **argv)
{
    char line[512];
    if (argc > 1 && argv[1][0] == '-' && argv[1][1] == '-' && argv[1][2] == 'k') {
        kat();
        return 0;
    }
    while (fgets(line, (int)sizeof(line), stdin) != NULL) {
        int pos = 0;
        u64 seed;
        u64 stream;
        u64 count64;
        u32 count;
        u32 i;
        Pcg32 p;
        Xoshiro256 x;
        while (line[pos] == ' ' || line[pos] == '\t') pos++;
        if (line[pos] == 'b') {
            u64 bound64;
            u32 bound;
            pos += 7; /* "bounded" */
            if (!parse_u64(line, &pos, &seed)) continue;
            if (!parse_u64(line, &pos, &stream)) continue;
            if (!parse_u64(line, &pos, &bound64)) continue;
            if (!parse_u64(line, &pos, &count64)) continue;
            count = (u32)count64;
            bound = (u32)bound64;
            p = pcg32_init(seed, stream);
            for (i = 0; i < count; i++) {
                if (i != 0) putchar(' ');
                printf("%x", pcg32_bounded(&p, bound));
            }
            putchar('\n');
            continue;
        }
        if (!parse_u64(line, &pos, &seed)) continue;
        if (!parse_u64(line, &pos, &stream)) continue;
        if (!parse_u64(line, &pos, &count64)) continue;
        count = (u32)count64;
        p = pcg32_init(seed, stream);
        x = xoshiro_init(seed);
        for (i = 0; i < count; i++) {
            if (i != 0) putchar(' ');
            printf("%x", pcg32_next(&p));
        }
        putchar('\n');
        for (i = 0; i < count; i++) {
            if (i != 0) putchar(' ');
            printf("%016llx", xoshiro_next(&x));
        }
        putchar('\n');
    }
    return 0;
}
