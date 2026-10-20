/*
 * ref.c — C89 reference for std_noise (OpenSimplex 2D/3D).
 *
 * Algorithm: Kurt Spencer's 2014 OpenSimplex Noise, v1.1 (October 5, 2014),
 * github.com/KdotJPG/OpenSimplexNoise (now preserved as the original
 * implementation in github.com/KdotJPG/OpenSimplexNoise-for-Processing,
 * src/algorithms/noise/OpenSimplexNoiseKS.java).  This is the 2014
 * OpenSimplex algorithm, NOT OpenSimplex2.
 *
 * Copyright: Kurt Spencer released the original OpenSimplex Noise
 * implementation into the public domain (UNLICENSE).  This C89 port keeps
 * the same public-domain terms; no warranty is provided.
 *
 * Port notes:
 *   - The Z98 module binds the permutation to the M1 xoshiro256** generator
 *     (Fisher-Yates over 0..255) instead of the Java class's internal LCG.
 *     The same xoshiro init is used here so the crosscheck pins the exact
 *     module state.  Gradients, skew/unskew constants, attenuation and
 *     normalization are unchanged from the 2014 reference.
 *   - The 2014 v1.1 reference has 24 3D gradients (rhombicuboctahedron);
 *     the pre-computed gradient index table stores multiples of 3.
 *
 * Crosscheck protocol: one input line
 *     `2 <seed> <x> <y>` or `3 <seed> <x> <y> <z>`
 * (decimal).  Re-initialize from <seed> for each line and print exactly one
 * line: the 16 lowercase hex digits of the IEEE-754 f64 bit pattern returned
 * by noise2d/noise3d.  Always exits 0.
 *
 * `--lattice` prints the Step-1 lattice pre-check for seed 0 as
 * `x y bits decimal` lines.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned long long u64;
typedef unsigned int u32;

typedef struct {
    u64 s[4];
} Xoshiro256;

typedef struct {
    unsigned char perm[256];
    unsigned char perm_grad[256];
} OpenSimplex;

static const double STRETCH_CONSTANT_2D = -0.211324865405187;
static const double SQUISH_CONSTANT_2D = 0.366025403784439;
static const double STRETCH_CONSTANT_3D = -1.0 / 6.0;
static const double SQUISH_CONSTANT_3D = 1.0 / 3.0;
static const double NORM_CONSTANT_2D = 47.0;
static const double NORM_CONSTANT_3D = 103.0;

static const signed char gradients2D[16] = {
     5,  2,    2,  5,
    -5,  2,   -2,  5,
     5, -2,    2, -5,
    -5, -2,   -2, -5
};

static const signed char gradients3D[72] = {
    -11,  4,  4,     -4,  11,  4,    -4,  4,  11,
     11,  4,  4,      4,  11,  4,     4,  4,  11,
    -11, -4,  4,     -4, -11,  4,    -4, -4,  11,
     11, -4,  4,      4, -11,  4,     4, -4,  11,
    -11,  4, -4,     -4,  11, -4,    -4,  4, -11,
     11,  4, -4,      4,  11, -4,     4,  4, -11,
    -11, -4, -4,     -4, -11, -4,    -4, -4, -11,
     11, -4, -4,      4, -11, -4,     4, -4, -11
};

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
    u64 t = (r->s[1] & 0x7FFFFFFFFFFFULL) << 17;
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

static OpenSimplex opensimplex_init(u64 seed)
{
    OpenSimplex n;
    Xoshiro256 r = xoshiro_init(seed);
    unsigned char source[256];
    int i;
    for (i = 0; i < 256; i++) source[i] = (unsigned char)i;
    for (i = 255; i >= 0; i--) {
        u32 j = (u32)xoshiro_bounded(&r, (u64)(i + 1));
        n.perm[i] = source[j];
        source[j] = source[i];
    }
    for (i = 0; i < 256; i++) {
        n.perm_grad[i] = (unsigned char)((n.perm[i] % 24u) * 3u);
    }
    return n;
}

static int fast_floor(double x)
{
    int xi = (int)x;
    return x < (double)xi ? xi - 1 : xi;
}

static double extrapolate2(const OpenSimplex *n, int xsb, int ysb, double dx, double dy)
{
    int index = n->perm[(n->perm[xsb & 0xFF] + ysb) & 0xFF] & 0x0E;
    return (double)gradients2D[index] * dx + (double)gradients2D[index + 1] * dy;
}

static double extrapolate3(const OpenSimplex *n, int xsb, int ysb, int zsb,
                           double dx, double dy, double dz)
{
    int index = n->perm_grad[(n->perm[(n->perm[xsb & 0xFF] + ysb) & 0xFF] + zsb) & 0xFF];
    return (double)gradients3D[index] * dx
         + (double)gradients3D[index + 1] * dy
         + (double)gradients3D[index + 2] * dz;
}

static double noise2d(const OpenSimplex *n, double x, double y)
{
    double stretchOffset = (x + y) * STRETCH_CONSTANT_2D;
    double xs = x + stretchOffset;
    double ys = y + stretchOffset;
    int xsb = fast_floor(xs);
    int ysb = fast_floor(ys);
    double squishOffset = (double)(xsb + ysb) * SQUISH_CONSTANT_2D;
    double xb = (double)xsb + squishOffset;
    double yb = (double)ysb + squishOffset;
    double xins = xs - (double)xsb;
    double yins = ys - (double)ysb;
    double inSum = xins + yins;
    double dx0 = x - xb;
    double dy0 = y - yb;
    double dx_ext = 0.0;
    double dy_ext = 0.0;
    int xsv_ext = 0;
    int ysv_ext = 0;
    double value = 0.0;
    double dx1;
    double dy1;
    double attn1;
    double dx2;
    double dy2;
    double attn2;
    double attn0;
    double attn_ext;

    dx1 = dx0 - 1.0 - SQUISH_CONSTANT_2D;
    dy1 = dy0 - 0.0 - SQUISH_CONSTANT_2D;
    attn1 = 2.0 - dx1 * dx1 - dy1 * dy1;
    if (attn1 > 0.0) {
        attn1 *= attn1;
        value += attn1 * attn1 * extrapolate2(n, xsb + 1, ysb + 0, dx1, dy1);
    }

    dx2 = dx0 - 0.0 - SQUISH_CONSTANT_2D;
    dy2 = dy0 - 1.0 - SQUISH_CONSTANT_2D;
    attn2 = 2.0 - dx2 * dx2 - dy2 * dy2;
    if (attn2 > 0.0) {
        attn2 *= attn2;
        value += attn2 * attn2 * extrapolate2(n, xsb + 0, ysb + 1, dx2, dy2);
    }

    if (inSum <= 1.0) {
        double zins = 1.0 - inSum;
        if (zins > xins || zins > yins) {
            if (xins > yins) {
                xsv_ext = xsb + 1;
                ysv_ext = ysb - 1;
                dx_ext = dx0 - 1.0;
                dy_ext = dy0 + 1.0;
            } else {
                xsv_ext = xsb - 1;
                ysv_ext = ysb + 1;
                dx_ext = dx0 + 1.0;
                dy_ext = dy0 - 1.0;
            }
        } else {
            xsv_ext = xsb + 1;
            ysv_ext = ysb + 1;
            dx_ext = dx0 - 1.0 - 2.0 * SQUISH_CONSTANT_2D;
            dy_ext = dy0 - 1.0 - 2.0 * SQUISH_CONSTANT_2D;
        }
    } else {
        double zins = 2.0 - inSum;
        if (zins < xins || zins < yins) {
            if (xins > yins) {
                xsv_ext = xsb + 2;
                ysv_ext = ysb + 0;
                dx_ext = dx0 - 2.0 - 2.0 * SQUISH_CONSTANT_2D;
                dy_ext = dy0 + 0.0 - 2.0 * SQUISH_CONSTANT_2D;
            } else {
                xsv_ext = xsb + 0;
                ysv_ext = ysb + 2;
                dx_ext = dx0 + 0.0 - 2.0 * SQUISH_CONSTANT_2D;
                dy_ext = dy0 - 2.0 - 2.0 * SQUISH_CONSTANT_2D;
            }
        } else {
            dx_ext = dx0;
            dy_ext = dy0;
            xsv_ext = xsb;
            ysv_ext = ysb;
        }
        xsb += 1;
        ysb += 1;
        dx0 = dx0 - 1.0 - 2.0 * SQUISH_CONSTANT_2D;
        dy0 = dy0 - 1.0 - 2.0 * SQUISH_CONSTANT_2D;
    }

    attn0 = 2.0 - dx0 * dx0 - dy0 * dy0;
    if (attn0 > 0.0) {
        attn0 *= attn0;
        value += attn0 * attn0 * extrapolate2(n, xsb, ysb, dx0, dy0);
    }

    attn_ext = 2.0 - dx_ext * dx_ext - dy_ext * dy_ext;
    if (attn_ext > 0.0) {
        attn_ext *= attn_ext;
        value += attn_ext * attn_ext * extrapolate2(n, xsv_ext, ysv_ext, dx_ext, dy_ext);
    }

    return value / NORM_CONSTANT_2D;
}

static double noise3d(const OpenSimplex *n, double x, double y, double z)
{
    double stretchOffset = (x + y + z) * STRETCH_CONSTANT_3D;
    double xs = x + stretchOffset;
    double ys = y + stretchOffset;
    double zs = z + stretchOffset;
    int xsb = fast_floor(xs);
    int ysb = fast_floor(ys);
    int zsb = fast_floor(zs);
    double squishOffset = (double)(xsb + ysb + zsb) * SQUISH_CONSTANT_3D;
    double xb = (double)xsb + squishOffset;
    double yb = (double)ysb + squishOffset;
    double zb = (double)zsb + squishOffset;
    double xins = xs - (double)xsb;
    double yins = ys - (double)ysb;
    double zins = zs - (double)zsb;
    double inSum = xins + yins + zins;
    double dx0 = x - xb;
    double dy0 = y - yb;
    double dz0 = z - zb;
    double dx_ext0 = 0.0;
    double dy_ext0 = 0.0;
    double dz_ext0 = 0.0;
    double dx_ext1 = 0.0;
    double dy_ext1 = 0.0;
    double dz_ext1 = 0.0;
    int xsv_ext0 = 0;
    int ysv_ext0 = 0;
    int zsv_ext0 = 0;
    int xsv_ext1 = 0;
    int ysv_ext1 = 0;
    int zsv_ext1 = 0;
    double value = 0.0;

    if (inSum <= 1.0) {
        int aPoint = 0x01;
        double aScore = xins;
        int bPoint = 0x02;
        double bScore = yins;
        double wins;
        int c;

        if (aScore >= bScore && zins > bScore) {
            bScore = zins;
            bPoint = 0x04;
        } else if (aScore < bScore && zins > aScore) {
            aScore = zins;
            aPoint = 0x04;
        }

        wins = 1.0 - inSum;
        if (wins > aScore || wins > bScore) {
            c = (bScore > aScore ? bPoint : aPoint);
            if ((c & 0x01) == 0) {
                xsv_ext0 = xsb - 1;
                xsv_ext1 = xsb;
                dx_ext0 = dx0 + 1.0;
                dx_ext1 = dx0;
            } else {
                xsv_ext0 = xsb + 1;
                xsv_ext1 = xsb + 1;
                dx_ext0 = dx0 - 1.0;
                dx_ext1 = dx0 - 1.0;
            }
            if ((c & 0x02) == 0) {
                ysv_ext0 = ysb;
                ysv_ext1 = ysb;
                dy_ext0 = dy0;
                dy_ext1 = dy0;
                if ((c & 0x01) == 0) {
                    ysv_ext1 -= 1;
                    dy_ext1 += 1.0;
                } else {
                    ysv_ext0 -= 1;
                    dy_ext0 += 1.0;
                }
            } else {
                ysv_ext0 = ysb + 1;
                ysv_ext1 = ysb + 1;
                dy_ext0 = dy0 - 1.0;
                dy_ext1 = dy0 - 1.0;
            }
            if ((c & 0x04) == 0) {
                zsv_ext0 = zsb;
                zsv_ext1 = zsb - 1;
                dz_ext0 = dz0;
                dz_ext1 = dz0 + 1.0;
            } else {
                zsv_ext0 = zsb + 1;
                zsv_ext1 = zsb + 1;
                dz_ext0 = dz0 - 1.0;
                dz_ext1 = dz0 - 1.0;
            }
        } else {
            c = aPoint | bPoint;
            if ((c & 0x01) == 0) {
                xsv_ext0 = xsb;
                xsv_ext1 = xsb - 1;
                dx_ext0 = dx0 - 2.0 * SQUISH_CONSTANT_3D;
                dx_ext1 = dx0 + 1.0 - SQUISH_CONSTANT_3D;
            } else {
                xsv_ext0 = xsb + 1;
                xsv_ext1 = xsb + 1;
                dx_ext0 = dx0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
                dx_ext1 = dx0 - 1.0 - SQUISH_CONSTANT_3D;
            }
            if ((c & 0x02) == 0) {
                ysv_ext0 = ysb;
                ysv_ext1 = ysb - 1;
                dy_ext0 = dy0 - 2.0 * SQUISH_CONSTANT_3D;
                dy_ext1 = dy0 + 1.0 - SQUISH_CONSTANT_3D;
            } else {
                ysv_ext0 = ysb + 1;
                ysv_ext1 = ysb + 1;
                dy_ext0 = dy0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
                dy_ext1 = dy0 - 1.0 - SQUISH_CONSTANT_3D;
            }
            if ((c & 0x04) == 0) {
                zsv_ext0 = zsb;
                zsv_ext1 = zsb - 1;
                dz_ext0 = dz0 - 2.0 * SQUISH_CONSTANT_3D;
                dz_ext1 = dz0 + 1.0 - SQUISH_CONSTANT_3D;
            } else {
                zsv_ext0 = zsb + 1;
                zsv_ext1 = zsb + 1;
                dz_ext0 = dz0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
                dz_ext1 = dz0 - 1.0 - SQUISH_CONSTANT_3D;
            }
        }

        {
            double dx1 = dx0 - 1.0 - SQUISH_CONSTANT_3D;
            double dy1 = dy0 - 0.0 - SQUISH_CONSTANT_3D;
            double dz1 = dz0 - 0.0 - SQUISH_CONSTANT_3D;
            double dx2;
            double dy2;
            double dz2;
            double dx3;
            double dy3;
            double dz3;
            double attn0 = 2.0 - dx0 * dx0 - dy0 * dy0 - dz0 * dz0;
            double attn1 = 2.0 - dx1 * dx1 - dy1 * dy1 - dz1 * dz1;
            double attn2;
            double attn3;
            if (attn0 > 0.0) {
                attn0 *= attn0;
                value += attn0 * attn0 * extrapolate3(n, xsb + 0, ysb + 0, zsb + 0, dx0, dy0, dz0);
            }
            if (attn1 > 0.0) {
                attn1 *= attn1;
                value += attn1 * attn1 * extrapolate3(n, xsb + 1, ysb + 0, zsb + 0, dx1, dy1, dz1);
            }
            dx2 = dx0 - 0.0 - SQUISH_CONSTANT_3D;
            dy2 = dy0 - 1.0 - SQUISH_CONSTANT_3D;
            dz2 = dz1;
            attn2 = 2.0 - dx2 * dx2 - dy2 * dy2 - dz2 * dz2;
            if (attn2 > 0.0) {
                attn2 *= attn2;
                value += attn2 * attn2 * extrapolate3(n, xsb + 0, ysb + 1, zsb + 0, dx2, dy2, dz2);
            }
            dx3 = dx2;
            dy3 = dy1;
            dz3 = dz0 - 1.0 - SQUISH_CONSTANT_3D;
            attn3 = 2.0 - dx3 * dx3 - dy3 * dy3 - dz3 * dz3;
            if (attn3 > 0.0) {
                attn3 *= attn3;
                value += attn3 * attn3 * extrapolate3(n, xsb + 0, ysb + 0, zsb + 1, dx3, dy3, dz3);
            }
        }
    } else if (inSum >= 2.0) {
        int aPoint = 0x06;
        double aScore = xins;
        int bPoint = 0x05;
        double bScore = yins;
        double wins;
        int c;

        if (aScore <= bScore && zins < bScore) {
            bScore = zins;
            bPoint = 0x03;
        } else if (aScore > bScore && zins < aScore) {
            aScore = zins;
            aPoint = 0x03;
        }

        wins = 3.0 - inSum;
        if (wins < aScore || wins < bScore) {
            c = (bScore < aScore ? bPoint : aPoint);
            if ((c & 0x01) != 0) {
                xsv_ext0 = xsb + 2;
                xsv_ext1 = xsb + 1;
                dx_ext0 = dx0 - 2.0 - 3.0 * SQUISH_CONSTANT_3D;
                dx_ext1 = dx0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
            } else {
                xsv_ext0 = xsb;
                xsv_ext1 = xsb;
                dx_ext0 = dx0 - 3.0 * SQUISH_CONSTANT_3D;
                dx_ext1 = dx0 - 3.0 * SQUISH_CONSTANT_3D;
            }
            if ((c & 0x02) != 0) {
                ysv_ext0 = ysb + 1;
                ysv_ext1 = ysb + 1;
                dy_ext0 = dy0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
                dy_ext1 = dy0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
                if ((c & 0x01) != 0) {
                    ysv_ext1 += 1;
                    dy_ext1 -= 1.0;
                } else {
                    ysv_ext0 += 1;
                    dy_ext0 -= 1.0;
                }
            } else {
                ysv_ext0 = ysb;
                ysv_ext1 = ysb;
                dy_ext0 = dy0 - 3.0 * SQUISH_CONSTANT_3D;
                dy_ext1 = dy0 - 3.0 * SQUISH_CONSTANT_3D;
            }
            if ((c & 0x04) != 0) {
                zsv_ext0 = zsb + 1;
                zsv_ext1 = zsb + 2;
                dz_ext0 = dz0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
                dz_ext1 = dz0 - 2.0 - 3.0 * SQUISH_CONSTANT_3D;
            } else {
                zsv_ext0 = zsb;
                zsv_ext1 = zsb;
                dz_ext0 = dz0 - 3.0 * SQUISH_CONSTANT_3D;
                dz_ext1 = dz0 - 3.0 * SQUISH_CONSTANT_3D;
            }
        } else {
            c = aPoint & bPoint;
            if ((c & 0x01) != 0) {
                xsv_ext0 = xsb + 1;
                xsv_ext1 = xsb + 2;
                dx_ext0 = dx0 - 1.0 - SQUISH_CONSTANT_3D;
                dx_ext1 = dx0 - 2.0 - 2.0 * SQUISH_CONSTANT_3D;
            } else {
                xsv_ext0 = xsb;
                xsv_ext1 = xsb;
                dx_ext0 = dx0 - SQUISH_CONSTANT_3D;
                dx_ext1 = dx0 - 2.0 * SQUISH_CONSTANT_3D;
            }
            if ((c & 0x02) != 0) {
                ysv_ext0 = ysb + 1;
                ysv_ext1 = ysb + 2;
                dy_ext0 = dy0 - 1.0 - SQUISH_CONSTANT_3D;
                dy_ext1 = dy0 - 2.0 - 2.0 * SQUISH_CONSTANT_3D;
            } else {
                ysv_ext0 = ysb;
                ysv_ext1 = ysb;
                dy_ext0 = dy0 - SQUISH_CONSTANT_3D;
                dy_ext1 = dy0 - 2.0 * SQUISH_CONSTANT_3D;
            }
            if ((c & 0x04) != 0) {
                zsv_ext0 = zsb + 1;
                zsv_ext1 = zsb + 2;
                dz_ext0 = dz0 - 1.0 - SQUISH_CONSTANT_3D;
                dz_ext1 = dz0 - 2.0 - 2.0 * SQUISH_CONSTANT_3D;
            } else {
                zsv_ext0 = zsb;
                zsv_ext1 = zsb;
                dz_ext0 = dz0 - SQUISH_CONSTANT_3D;
                dz_ext1 = dz0 - 2.0 * SQUISH_CONSTANT_3D;
            }
        }

        {
            double dx3 = dx0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
            double dy3 = dy0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
            double dz3 = dz0 - 0.0 - 2.0 * SQUISH_CONSTANT_3D;
            double dx2;
            double dy2;
            double dz2;
            double dx1;
            double dy1;
            double dz1;
            double attn3 = 2.0 - dx3 * dx3 - dy3 * dy3 - dz3 * dz3;
            double attn2;
            double attn1;
            double attn0;
            if (attn3 > 0.0) {
                attn3 *= attn3;
                value += attn3 * attn3 * extrapolate3(n, xsb + 1, ysb + 1, zsb + 0, dx3, dy3, dz3);
            }
            dx2 = dx3;
            dy2 = dy0 - 0.0 - 2.0 * SQUISH_CONSTANT_3D;
            dz2 = dz0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
            attn2 = 2.0 - dx2 * dx2 - dy2 * dy2 - dz2 * dz2;
            if (attn2 > 0.0) {
                attn2 *= attn2;
                value += attn2 * attn2 * extrapolate3(n, xsb + 1, ysb + 0, zsb + 1, dx2, dy2, dz2);
            }
            dx1 = dx0 - 0.0 - 2.0 * SQUISH_CONSTANT_3D;
            dy1 = dy3;
            dz1 = dz2;
            attn1 = 2.0 - dx1 * dx1 - dy1 * dy1 - dz1 * dz1;
            if (attn1 > 0.0) {
                attn1 *= attn1;
                value += attn1 * attn1 * extrapolate3(n, xsb + 0, ysb + 1, zsb + 1, dx1, dy1, dz1);
            }
            dx0 = dx0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
            dy0 = dy0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
            dz0 = dz0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
            attn0 = 2.0 - dx0 * dx0 - dy0 * dy0 - dz0 * dz0;
            if (attn0 > 0.0) {
                attn0 *= attn0;
                value += attn0 * attn0 * extrapolate3(n, xsb + 1, ysb + 1, zsb + 1, dx0, dy0, dz0);
            }
        }
    } else {
        double aScore;
        int aPoint;
        int aIsFurtherSide;
        double bScore;
        int bPoint;
        int bIsFurtherSide;
        double p1;
        double p2;
        double p3;
        int c1;
        int c2;

        p1 = xins + yins;
        if (p1 > 1.0) {
            aScore = p1 - 1.0;
            aPoint = 0x03;
            aIsFurtherSide = 1;
        } else {
            aScore = 1.0 - p1;
            aPoint = 0x04;
            aIsFurtherSide = 0;
        }

        p2 = xins + zins;
        if (p2 > 1.0) {
            bScore = p2 - 1.0;
            bPoint = 0x05;
            bIsFurtherSide = 1;
        } else {
            bScore = 1.0 - p2;
            bPoint = 0x02;
            bIsFurtherSide = 0;
        }

        p3 = yins + zins;
        if (p3 > 1.0) {
            double score = p3 - 1.0;
            if (aScore <= bScore && aScore < score) {
                aScore = score;
                aPoint = 0x06;
                aIsFurtherSide = 1;
            } else if (aScore > bScore && bScore < score) {
                bScore = score;
                bPoint = 0x06;
                bIsFurtherSide = 1;
            }
        } else {
            double score = 1.0 - p3;
            if (aScore <= bScore && aScore < score) {
                aScore = score;
                aPoint = 0x01;
                aIsFurtherSide = 0;
            } else if (aScore > bScore && bScore < score) {
                bScore = score;
                bPoint = 0x01;
                bIsFurtherSide = 0;
            }
        }

        if (aIsFurtherSide == bIsFurtherSide) {
            if (aIsFurtherSide) {
                int c;
                dx_ext0 = dx0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
                dy_ext0 = dy0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
                dz_ext0 = dz0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
                xsv_ext0 = xsb + 1;
                ysv_ext0 = ysb + 1;
                zsv_ext0 = zsb + 1;
                c = aPoint & bPoint;
                if ((c & 0x01) != 0) {
                    dx_ext1 = dx0 - 2.0 - 2.0 * SQUISH_CONSTANT_3D;
                    dy_ext1 = dy0 - 2.0 * SQUISH_CONSTANT_3D;
                    dz_ext1 = dz0 - 2.0 * SQUISH_CONSTANT_3D;
                    xsv_ext1 = xsb + 2;
                    ysv_ext1 = ysb;
                    zsv_ext1 = zsb;
                } else if ((c & 0x02) != 0) {
                    dx_ext1 = dx0 - 2.0 * SQUISH_CONSTANT_3D;
                    dy_ext1 = dy0 - 2.0 - 2.0 * SQUISH_CONSTANT_3D;
                    dz_ext1 = dz0 - 2.0 * SQUISH_CONSTANT_3D;
                    xsv_ext1 = xsb;
                    ysv_ext1 = ysb + 2;
                    zsv_ext1 = zsb;
                } else {
                    dx_ext1 = dx0 - 2.0 * SQUISH_CONSTANT_3D;
                    dy_ext1 = dy0 - 2.0 * SQUISH_CONSTANT_3D;
                    dz_ext1 = dz0 - 2.0 - 2.0 * SQUISH_CONSTANT_3D;
                    xsv_ext1 = xsb;
                    ysv_ext1 = ysb;
                    zsv_ext1 = zsb + 2;
                }
            } else {
                int c;
                dx_ext0 = dx0;
                dy_ext0 = dy0;
                dz_ext0 = dz0;
                xsv_ext0 = xsb;
                ysv_ext0 = ysb;
                zsv_ext0 = zsb;
                c = aPoint | bPoint;
                if ((c & 0x01) == 0) {
                    dx_ext1 = dx0 + 1.0 - SQUISH_CONSTANT_3D;
                    dy_ext1 = dy0 - 1.0 - SQUISH_CONSTANT_3D;
                    dz_ext1 = dz0 - 1.0 - SQUISH_CONSTANT_3D;
                    xsv_ext1 = xsb - 1;
                    ysv_ext1 = ysb + 1;
                    zsv_ext1 = zsb + 1;
                } else if ((c & 0x02) == 0) {
                    dx_ext1 = dx0 - 1.0 - SQUISH_CONSTANT_3D;
                    dy_ext1 = dy0 + 1.0 - SQUISH_CONSTANT_3D;
                    dz_ext1 = dz0 - 1.0 - SQUISH_CONSTANT_3D;
                    xsv_ext1 = xsb + 1;
                    ysv_ext1 = ysb - 1;
                    zsv_ext1 = zsb + 1;
                } else {
                    dx_ext1 = dx0 - 1.0 - SQUISH_CONSTANT_3D;
                    dy_ext1 = dy0 - 1.0 - SQUISH_CONSTANT_3D;
                    dz_ext1 = dz0 + 1.0 - SQUISH_CONSTANT_3D;
                    xsv_ext1 = xsb + 1;
                    ysv_ext1 = ysb + 1;
                    zsv_ext1 = zsb - 1;
                }
            }
        } else {
            if (aIsFurtherSide) {
                c1 = aPoint;
                c2 = bPoint;
            } else {
                c1 = bPoint;
                c2 = aPoint;
            }

            if ((c1 & 0x01) == 0) {
                dx_ext0 = dx0 + 1.0 - SQUISH_CONSTANT_3D;
                dy_ext0 = dy0 - 1.0 - SQUISH_CONSTANT_3D;
                dz_ext0 = dz0 - 1.0 - SQUISH_CONSTANT_3D;
                xsv_ext0 = xsb - 1;
                ysv_ext0 = ysb + 1;
                zsv_ext0 = zsb + 1;
            } else if ((c1 & 0x02) == 0) {
                dx_ext0 = dx0 - 1.0 - SQUISH_CONSTANT_3D;
                dy_ext0 = dy0 + 1.0 - SQUISH_CONSTANT_3D;
                dz_ext0 = dz0 - 1.0 - SQUISH_CONSTANT_3D;
                xsv_ext0 = xsb + 1;
                ysv_ext0 = ysb - 1;
                zsv_ext0 = zsb + 1;
            } else {
                dx_ext0 = dx0 - 1.0 - SQUISH_CONSTANT_3D;
                dy_ext0 = dy0 - 1.0 - SQUISH_CONSTANT_3D;
                dz_ext0 = dz0 + 1.0 - SQUISH_CONSTANT_3D;
                xsv_ext0 = xsb + 1;
                ysv_ext0 = ysb + 1;
                zsv_ext0 = zsb - 1;
            }

            dx_ext1 = dx0 - 2.0 * SQUISH_CONSTANT_3D;
            dy_ext1 = dy0 - 2.0 * SQUISH_CONSTANT_3D;
            dz_ext1 = dz0 - 2.0 * SQUISH_CONSTANT_3D;
            xsv_ext1 = xsb;
            ysv_ext1 = ysb;
            zsv_ext1 = zsb;
            if ((c2 & 0x01) != 0) {
                dx_ext1 -= 2.0;
                xsv_ext1 += 2;
            } else if ((c2 & 0x02) != 0) {
                dy_ext1 -= 2.0;
                ysv_ext1 += 2;
            } else {
                dz_ext1 -= 2.0;
                zsv_ext1 += 2;
            }
        }

        {
            double dx1 = dx0 - 1.0 - SQUISH_CONSTANT_3D;
            double dy1 = dy0 - 0.0 - SQUISH_CONSTANT_3D;
            double dz1 = dz0 - 0.0 - SQUISH_CONSTANT_3D;
            double dx2;
            double dy2;
            double dz2;
            double dx3;
            double dy3;
            double dz3;
            double dx4;
            double dy4;
            double dz4;
            double dx5;
            double dy5;
            double dz5;
            double dx6;
            double dy6;
            double dz6;
            double attn1 = 2.0 - dx1 * dx1 - dy1 * dy1 - dz1 * dz1;
            double attn2;
            double attn3;
            double attn4;
            double attn5;
            double attn6;
            if (attn1 > 0.0) {
                attn1 *= attn1;
                value += attn1 * attn1 * extrapolate3(n, xsb + 1, ysb + 0, zsb + 0, dx1, dy1, dz1);
            }
            dx2 = dx0 - 0.0 - SQUISH_CONSTANT_3D;
            dy2 = dy0 - 1.0 - SQUISH_CONSTANT_3D;
            dz2 = dz1;
            attn2 = 2.0 - dx2 * dx2 - dy2 * dy2 - dz2 * dz2;
            if (attn2 > 0.0) {
                attn2 *= attn2;
                value += attn2 * attn2 * extrapolate3(n, xsb + 0, ysb + 1, zsb + 0, dx2, dy2, dz2);
            }
            dx3 = dx2;
            dy3 = dy1;
            dz3 = dz0 - 1.0 - SQUISH_CONSTANT_3D;
            attn3 = 2.0 - dx3 * dx3 - dy3 * dy3 - dz3 * dz3;
            if (attn3 > 0.0) {
                attn3 *= attn3;
                value += attn3 * attn3 * extrapolate3(n, xsb + 0, ysb + 0, zsb + 1, dx3, dy3, dz3);
            }
            dx4 = dx0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
            dy4 = dy0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
            dz4 = dz0 - 0.0 - 2.0 * SQUISH_CONSTANT_3D;
            attn4 = 2.0 - dx4 * dx4 - dy4 * dy4 - dz4 * dz4;
            if (attn4 > 0.0) {
                attn4 *= attn4;
                value += attn4 * attn4 * extrapolate3(n, xsb + 1, ysb + 1, zsb + 0, dx4, dy4, dz4);
            }
            dx5 = dx4;
            dy5 = dy0 - 0.0 - 2.0 * SQUISH_CONSTANT_3D;
            dz5 = dz0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
            attn5 = 2.0 - dx5 * dx5 - dy5 * dy5 - dz5 * dz5;
            if (attn5 > 0.0) {
                attn5 *= attn5;
                value += attn5 * attn5 * extrapolate3(n, xsb + 1, ysb + 0, zsb + 1, dx5, dy5, dz5);
            }
            dx6 = dx0 - 0.0 - 2.0 * SQUISH_CONSTANT_3D;
            dy6 = dy4;
            dz6 = dz5;
            attn6 = 2.0 - dx6 * dx6 - dy6 * dy6 - dz6 * dz6;
            if (attn6 > 0.0) {
                attn6 *= attn6;
                value += attn6 * attn6 * extrapolate3(n, xsb + 0, ysb + 1, zsb + 1, dx6, dy6, dz6);
            }
        }
    }

    {
        double attn_ext0 = 2.0 - dx_ext0 * dx_ext0 - dy_ext0 * dy_ext0 - dz_ext0 * dz_ext0;
        double attn_ext1 = 2.0 - dx_ext1 * dx_ext1 - dy_ext1 * dy_ext1 - dz_ext1 * dz_ext1;
        if (attn_ext0 > 0.0) {
            attn_ext0 *= attn_ext0;
            value += attn_ext0 * attn_ext0 * extrapolate3(n, xsv_ext0, ysv_ext0, zsv_ext0,
                                                          dx_ext0, dy_ext0, dz_ext0);
        }
        if (attn_ext1 > 0.0) {
            attn_ext1 *= attn_ext1;
            value += attn_ext1 * attn_ext1 * extrapolate3(n, xsv_ext1, ysv_ext1, zsv_ext1,
                                                          dx_ext1, dy_ext1, dz_ext1);
        }
    }

    return value / NORM_CONSTANT_3D;
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

static int parse_double(const char *s, int *pi, double *out)
{
    int i = *pi;
    int start;
    char *end;
    while (s[i] == ' ' || s[i] == '\t') i++;
    start = i;
    *out = strtod(s + start, &end);
    if (end == s + start) return 0;
    *pi = (int)(end - s);
    return 1;
}

static u64 double_bits(double v)
{
    u64 bits;
    memcpy(&bits, &v, sizeof(bits));
    return bits;
}

/* Force IEEE-754 double precision on the x87 FPU (53-bit significand).
 * Without this, gcc -m32 -O0 can carry excess 80-bit intermediates and the
 * last bits of the reference disagree with the f64-only Z98 module.  This is
 * a host-evaluation guard, not an algorithm change. */
static void set_f64_precision(void)
{
#if defined(__i386__) || defined(__i686__)
    unsigned short cw;
    __asm__ __volatile__("fstcw %0" : "=m"(cw));
    cw = (unsigned short)((cw & ~0x0300u) | 0x0200u);
    __asm__ __volatile__("fldcw %0" : : "m"(cw));
#endif
}

static void lattice_check(void)
{
    OpenSimplex n = opensimplex_init(0ULL);
    static const double pts[4][2] = {
        { 0.0, 0.0 },
        { 1.0, 0.0 },
        { 0.0, 1.0 },
        { 1.0, 1.0 }
    };
    int i;
    for (i = 0; i < 4; i++) {
        double v = noise2d(&n, pts[i][0], pts[i][1]);
        printf("%.0f %.0f %016llx %.17g\n",
               pts[i][0], pts[i][1], double_bits(v), v);
    }
}

int main(int argc, char **argv)
{
    char line[1024];
    set_f64_precision();
    if (argc > 1 && strcmp(argv[1], "--lattice") == 0) {
        lattice_check();
        return 0;
    }
    while (fgets(line, (int)sizeof(line), stdin) != NULL) {
        int pos = 0;
        u64 dim64;
        u64 seed;
        int dim;
        double x;
        double y;
        double z;
        OpenSimplex n;
        while (line[pos] == ' ' || line[pos] == '\t') pos++;
        if (line[pos] == '\0' || line[pos] == '\n') continue;
        if (!parse_u64(line, &pos, &dim64)) continue;
        dim = (int)dim64;
        if (!parse_u64(line, &pos, &seed)) continue;
        if (!parse_double(line, &pos, &x)) continue;
        if (!parse_double(line, &pos, &y)) continue;
        n = opensimplex_init(seed);
        if (dim == 2) {
            printf("%016llx\n", double_bits(noise2d(&n, x, y)));
        } else if (dim == 3) {
            if (!parse_double(line, &pos, &z)) continue;
            printf("%016llx\n", double_bits(noise3d(&n, x, y, z)));
        } else {
            continue;
        }
    }
    return 0;
}
