// std_noise.zig — Z98 std lib L5: OpenSimplex noise (Kurt Spencer, 2014).
//
// Contract (blueprint §3 L5): alloc none | errors none | coroutine no. Imports
// only the M1 `std_rand` module (xoshiro256** Fisher-Yates permutation). State
// is fixed at 512 bytes (`perm` + `perm_grad`); no heap, clock, env, PID or
// address input.
//
// Algorithm: Kurt Spencer's 2014 OpenSimplex Noise v1.1 (October 5, 2014),
// github.com/KdotJPG/OpenSimplexNoise (preserved as the original
// implementation in github.com/KdotJPG/OpenSimplexNoise-for-Processing,
// src/algorithms/noise/OpenSimplexNoiseKS.java). This is the 2014 OpenSimplex
// algorithm, NOT OpenSimplex2. The 2014 reference is authoritative for the
// lattice values: at seed 0, (0,0) is zero but (1,0), (0,1), (1,1) are nonzero.
//
// f64 throughout. The 2D skew/squish constants are precomputed literals;
// 2D uses the eight compass gradients and 3D the 24 rhombicuboctahedron
// gradients (`perm_grad[i] = (perm[i] % 24) * 3`). Do not substitute Perlin
// gradients or f32 intermediates.
//
//   opensimplexInit(seed)          -> OpenSimplex (512 B)
//   noise2d(n, x, y)               -> [-1, 1]
//   noise3d(n, x, y, z)            -> [-1, 1]
//   noiseFbm2d(n, x, y, octaves, lacunarity, gain)
//
// `octaves == 0` returns exactly 0.0.

const rand = @import("std_rand.zig");

pub const OpenSimplex = struct {
    perm: [256]u8,
    perm_grad: [256]u8,
};

const STRETCH_CONSTANT_2D: f64 = -0.211324865405187;
// Decimal literals are chosen to survive the Z98 lexer's fractional-digit
// accumulation unchanged; 0.3660254037844389 and -0.16666666666666664 parse
// to the same IEEE-754 doubles that gcc assigns to the 2014 reference's
// 0.366025403784439 and -1.0/6.0 constants.
const SQUISH_CONSTANT_2D: f64 = 0.3660254037844389;
const STRETCH_CONSTANT_3D: f64 = -0.16666666666666664;
const SQUISH_CONSTANT_3D: f64 = 0.3333333333333333;
const NORM_CONSTANT_2D: f64 = 47.0;
const NORM_CONSTANT_3D: f64 = 103.0;

fn fastFloor(x: f64) i32 {
    var xi: i32 = @intCast(i32, x);
    if (x < @intToFloat(f64, xi)) return xi - 1;
    return xi;
}

fn pixelIndex(x: i32) usize {
    return @intCast(usize, x & 0xFF);
}

fn extrapolate2(n: *const OpenSimplex, xsb: i32, ysb: i32, dx: f64, dy: f64) f64 {
    const gradients2D: [16]i32 = .{
        5, 2, 2, 5,
        -5, 2, -2, 5,
        5, -2, 2, -5,
        -5, -2, -2, -5,
    };
    var inner: i32 = @intCast(i32, n.perm[pixelIndex(xsb)]) + ysb;
    var index: usize = @intCast(usize, n.perm[pixelIndex(inner)] & 0x0E);
    return @intToFloat(f64, gradients2D[index]) * dx +
        @intToFloat(f64, gradients2D[index + 1]) * dy;
}

fn extrapolate3(n: *const OpenSimplex, xsb: i32, ysb: i32, zsb: i32, dx: f64, dy: f64, dz: f64) f64 {
    const gradients3D: [72]i32 = .{
        -11, 4, 4, -4, 11, 4, -4, 4, 11,
        11, 4, 4, 4, 11, 4, 4, 4, 11,
        -11, -4, 4, -4, -11, 4, -4, -4, 11,
        11, -4, 4, 4, -11, 4, 4, -4, 11,
        -11, 4, -4, -4, 11, -4, -4, 4, -11,
        11, 4, -4, 4, 11, -4, 4, 4, -11,
        -11, -4, -4, -4, -11, -4, -4, -4, -11,
        11, -4, -4, 4, -11, -4, 4, -4, -11,
    };
    var inner1: i32 = @intCast(i32, n.perm[pixelIndex(xsb)]) + ysb;
    var inner2: i32 = @intCast(i32, n.perm[pixelIndex(inner1)]) + zsb;
    var index: usize = @intCast(usize, n.perm_grad[pixelIndex(inner2)]);
    return @intToFloat(f64, gradients3D[index]) * dx +
        @intToFloat(f64, gradients3D[index + 1]) * dy +
        @intToFloat(f64, gradients3D[index + 2]) * dz;
}

pub fn opensimplexInit(seed: u64) OpenSimplex {
    var n: OpenSimplex = undefined;
    var source: [256]u8 = undefined;
    var i: i32 = 0;
    while (i < 256) : (i += 1) {
        source[@intCast(usize, i)] = @intCast(u8, i);
    }
    var r = rand.xoshiroInit(seed);
    i = 255;
    while (i >= 0) : (i -= 1) {
        var bound: u64 = @intCast(u64, i + 1);
        var j: u64 = rand.xoshiroBounded(&r, bound);
        var ju: usize = @intCast(usize, j);
        var iu: usize = @intCast(usize, i);
        n.perm[iu] = source[ju];
        source[ju] = source[iu];
    }
    i = 0;
    while (i < 256) : (i += 1) {
        var iu: usize = @intCast(usize, i);
        n.perm_grad[iu] = @intCast(u8, (@intCast(u32, n.perm[iu]) % 24) * 3);
    }
    return n;
}

pub fn noise2d(n: *const OpenSimplex, x: f64, y: f64) f64 {
    var stretch_offset: f64 = (x + y) * STRETCH_CONSTANT_2D;
    var xs: f64 = x + stretch_offset;
    var ys: f64 = y + stretch_offset;
    var xsb: i32 = fastFloor(xs);
    var ysb: i32 = fastFloor(ys);
    var squish_offset: f64 = @intToFloat(f64, xsb + ysb) * SQUISH_CONSTANT_2D;
    var xb: f64 = @intToFloat(f64, xsb) + squish_offset;
    var yb: f64 = @intToFloat(f64, ysb) + squish_offset;
    var xins: f64 = xs - @intToFloat(f64, xsb);
    var yins: f64 = ys - @intToFloat(f64, ysb);
    var in_sum: f64 = xins + yins;
    var dx0: f64 = x - xb;
    var dy0: f64 = y - yb;
    var dx_ext: f64 = 0.0;
    var dy_ext: f64 = 0.0;
    var xsv_ext: i32 = 0;
    var ysv_ext: i32 = 0;
    var value: f64 = 0.0;

    var dx1: f64 = dx0 - 1.0 - SQUISH_CONSTANT_2D;
    var dy1: f64 = dy0 - 0.0 - SQUISH_CONSTANT_2D;
    var attn1: f64 = 2.0 - dx1 * dx1 - dy1 * dy1;
    if (attn1 > 0.0) {
        attn1 *= attn1;
        value += attn1 * attn1 * extrapolate2(n, xsb + 1, ysb + 0, dx1, dy1);
    }

    var dx2: f64 = dx0 - 0.0 - SQUISH_CONSTANT_2D;
    var dy2: f64 = dy0 - 1.0 - SQUISH_CONSTANT_2D;
    var attn2: f64 = 2.0 - dx2 * dx2 - dy2 * dy2;
    if (attn2 > 0.0) {
        attn2 *= attn2;
        value += attn2 * attn2 * extrapolate2(n, xsb + 0, ysb + 1, dx2, dy2);
    }

    if (in_sum <= 1.0) {
        var zins: f64 = 1.0 - in_sum;
        if (zins > xins or zins > yins) {
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
        var zins2: f64 = 2.0 - in_sum;
        if (zins2 < xins or zins2 < yins) {
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

    var attn0: f64 = 2.0 - dx0 * dx0 - dy0 * dy0;
    if (attn0 > 0.0) {
        attn0 *= attn0;
        value += attn0 * attn0 * extrapolate2(n, xsb, ysb, dx0, dy0);
    }

    var attn_ext: f64 = 2.0 - dx_ext * dx_ext - dy_ext * dy_ext;
    if (attn_ext > 0.0) {
        attn_ext *= attn_ext;
        value += attn_ext * attn_ext * extrapolate2(n, xsv_ext, ysv_ext, dx_ext, dy_ext);
    }

    return value / NORM_CONSTANT_2D;
}

pub fn noise3d(n: *const OpenSimplex, x: f64, y: f64, z: f64) f64 {
    var stretch_offset: f64 = (x + y + z) * STRETCH_CONSTANT_3D;
    var xs: f64 = x + stretch_offset;
    var ys: f64 = y + stretch_offset;
    var zs: f64 = z + stretch_offset;
    var xsb: i32 = fastFloor(xs);
    var ysb: i32 = fastFloor(ys);
    var zsb: i32 = fastFloor(zs);
    var squish_offset: f64 = @intToFloat(f64, xsb + ysb + zsb) * SQUISH_CONSTANT_3D;
    var xb: f64 = @intToFloat(f64, xsb) + squish_offset;
    var yb: f64 = @intToFloat(f64, ysb) + squish_offset;
    var zb: f64 = @intToFloat(f64, zsb) + squish_offset;
    var xins: f64 = xs - @intToFloat(f64, xsb);
    var yins: f64 = ys - @intToFloat(f64, ysb);
    var zins: f64 = zs - @intToFloat(f64, zsb);
    var in_sum: f64 = xins + yins + zins;
    var dx0: f64 = x - xb;
    var dy0: f64 = y - yb;
    var dz0: f64 = z - zb;
    var dx_ext0: f64 = 0.0;
    var dy_ext0: f64 = 0.0;
    var dz_ext0: f64 = 0.0;
    var dx_ext1: f64 = 0.0;
    var dy_ext1: f64 = 0.0;
    var dz_ext1: f64 = 0.0;
    var xsv_ext0: i32 = 0;
    var ysv_ext0: i32 = 0;
    var zsv_ext0: i32 = 0;
    var xsv_ext1: i32 = 0;
    var ysv_ext1: i32 = 0;
    var zsv_ext1: i32 = 0;
    var value: f64 = 0.0;

    if (in_sum <= 1.0) {
        var a_point: i32 = 0x01;
        var a_score: f64 = xins;
        var b_point: i32 = 0x02;
        var b_score: f64 = yins;
        if (a_score >= b_score and zins > b_score) {
            b_score = zins;
            b_point = 0x04;
        } else if (a_score < b_score and zins > a_score) {
            a_score = zins;
            a_point = 0x04;
        }

        var wins: f64 = 1.0 - in_sum;
        if (wins > a_score or wins > b_score) {
            var c: i32 = 0;
            if (b_score > a_score) {
                c = b_point;
            } else {
                c = a_point;
            }
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
            var c2: i32 = a_point | b_point;
            if ((c2 & 0x01) == 0) {
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
            if ((c2 & 0x02) == 0) {
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
            if ((c2 & 0x04) == 0) {
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
            var dx1: f64 = dx0 - 1.0 - SQUISH_CONSTANT_3D;
            var dy1: f64 = dy0 - 0.0 - SQUISH_CONSTANT_3D;
            var dz1: f64 = dz0 - 0.0 - SQUISH_CONSTANT_3D;
            var attn0: f64 = 2.0 - dx0 * dx0 - dy0 * dy0 - dz0 * dz0;
            var attn1: f64 = 2.0 - dx1 * dx1 - dy1 * dy1 - dz1 * dz1;
            if (attn0 > 0.0) {
                attn0 *= attn0;
                value += attn0 * attn0 * extrapolate3(n, xsb + 0, ysb + 0, zsb + 0, dx0, dy0, dz0);
            }
            if (attn1 > 0.0) {
                attn1 *= attn1;
                value += attn1 * attn1 * extrapolate3(n, xsb + 1, ysb + 0, zsb + 0, dx1, dy1, dz1);
            }
            var dx2: f64 = dx0 - 0.0 - SQUISH_CONSTANT_3D;
            var dy2: f64 = dy0 - 1.0 - SQUISH_CONSTANT_3D;
            var dz2: f64 = dz1;
            var attn2: f64 = 2.0 - dx2 * dx2 - dy2 * dy2 - dz2 * dz2;
            if (attn2 > 0.0) {
                attn2 *= attn2;
                value += attn2 * attn2 * extrapolate3(n, xsb + 0, ysb + 1, zsb + 0, dx2, dy2, dz2);
            }
            var dx3: f64 = dx2;
            var dy3: f64 = dy1;
            var dz3: f64 = dz0 - 1.0 - SQUISH_CONSTANT_3D;
            var attn3: f64 = 2.0 - dx3 * dx3 - dy3 * dy3 - dz3 * dz3;
            if (attn3 > 0.0) {
                attn3 *= attn3;
                value += attn3 * attn3 * extrapolate3(n, xsb + 0, ysb + 0, zsb + 1, dx3, dy3, dz3);
            }
        }
    } else if (in_sum >= 2.0) {
        var a_point: i32 = 0x06;
        var a_score: f64 = xins;
        var b_point: i32 = 0x05;
        var b_score: f64 = yins;
        if (a_score <= b_score and zins < b_score) {
            b_score = zins;
            b_point = 0x03;
        } else if (a_score > b_score and zins < a_score) {
            a_score = zins;
            a_point = 0x03;
        }

        var wins: f64 = 3.0 - in_sum;
        if (wins < a_score or wins < b_score) {
            var c: i32 = 0;
            if (b_score < a_score) {
                c = b_point;
            } else {
                c = a_point;
            }
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
            var c2: i32 = a_point & b_point;
            if ((c2 & 0x01) != 0) {
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
            if ((c2 & 0x02) != 0) {
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
            if ((c2 & 0x04) != 0) {
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
            var dx3: f64 = dx0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
            var dy3: f64 = dy0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
            var dz3: f64 = dz0 - 0.0 - 2.0 * SQUISH_CONSTANT_3D;
            var attn3: f64 = 2.0 - dx3 * dx3 - dy3 * dy3 - dz3 * dz3;
            if (attn3 > 0.0) {
                attn3 *= attn3;
                value += attn3 * attn3 * extrapolate3(n, xsb + 1, ysb + 1, zsb + 0, dx3, dy3, dz3);
            }
            var dx2: f64 = dx3;
            var dy2: f64 = dy0 - 0.0 - 2.0 * SQUISH_CONSTANT_3D;
            var dz2: f64 = dz0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
            var attn2: f64 = 2.0 - dx2 * dx2 - dy2 * dy2 - dz2 * dz2;
            if (attn2 > 0.0) {
                attn2 *= attn2;
                value += attn2 * attn2 * extrapolate3(n, xsb + 1, ysb + 0, zsb + 1, dx2, dy2, dz2);
            }
            var dx1: f64 = dx0 - 0.0 - 2.0 * SQUISH_CONSTANT_3D;
            var dy1: f64 = dy3;
            var dz1: f64 = dz2;
            var attn1: f64 = 2.0 - dx1 * dx1 - dy1 * dy1 - dz1 * dz1;
            if (attn1 > 0.0) {
                attn1 *= attn1;
                value += attn1 * attn1 * extrapolate3(n, xsb + 0, ysb + 1, zsb + 1, dx1, dy1, dz1);
            }
            dx0 = dx0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
            dy0 = dy0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
            dz0 = dz0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
            var attn0: f64 = 2.0 - dx0 * dx0 - dy0 * dy0 - dz0 * dz0;
            if (attn0 > 0.0) {
                attn0 *= attn0;
                value += attn0 * attn0 * extrapolate3(n, xsb + 1, ysb + 1, zsb + 1, dx0, dy0, dz0);
            }
        }
    } else {
        var a_score: f64 = 0.0;
        var a_point: i32 = 0;
        var a_further: bool = false;
        var b_score: f64 = 0.0;
        var b_point: i32 = 0;
        var b_further: bool = false;

        var p1: f64 = xins + yins;
        if (p1 > 1.0) {
            a_score = p1 - 1.0;
            a_point = 0x03;
            a_further = true;
        } else {
            a_score = 1.0 - p1;
            a_point = 0x04;
            a_further = false;
        }

        var p2: f64 = xins + zins;
        if (p2 > 1.0) {
            b_score = p2 - 1.0;
            b_point = 0x05;
            b_further = true;
        } else {
            b_score = 1.0 - p2;
            b_point = 0x02;
            b_further = false;
        }

        var p3: f64 = yins + zins;
        if (p3 > 1.0) {
            var score: f64 = p3 - 1.0;
            if (a_score <= b_score and a_score < score) {
                a_score = score;
                a_point = 0x06;
                a_further = true;
            } else if (a_score > b_score and b_score < score) {
                b_score = score;
                b_point = 0x06;
                b_further = true;
            }
        } else {
            var score2: f64 = 1.0 - p3;
            if (a_score <= b_score and a_score < score2) {
                a_score = score2;
                a_point = 0x01;
                a_further = false;
            } else if (a_score > b_score and b_score < score2) {
                b_score = score2;
                b_point = 0x01;
                b_further = false;
            }
        }

        if (a_further == b_further) {
            if (a_further) {
                dx_ext0 = dx0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
                dy_ext0 = dy0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
                dz_ext0 = dz0 - 1.0 - 3.0 * SQUISH_CONSTANT_3D;
                xsv_ext0 = xsb + 1;
                ysv_ext0 = ysb + 1;
                zsv_ext0 = zsb + 1;

                var c: i32 = a_point & b_point;
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
                dx_ext0 = dx0;
                dy_ext0 = dy0;
                dz_ext0 = dz0;
                xsv_ext0 = xsb;
                ysv_ext0 = ysb;
                zsv_ext0 = zsb;

                var c2: i32 = a_point | b_point;
                if ((c2 & 0x01) == 0) {
                    dx_ext1 = dx0 + 1.0 - SQUISH_CONSTANT_3D;
                    dy_ext1 = dy0 - 1.0 - SQUISH_CONSTANT_3D;
                    dz_ext1 = dz0 - 1.0 - SQUISH_CONSTANT_3D;
                    xsv_ext1 = xsb - 1;
                    ysv_ext1 = ysb + 1;
                    zsv_ext1 = zsb + 1;
                } else if ((c2 & 0x02) == 0) {
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
            var c1: i32 = 0;
            var c2: i32 = 0;
            if (a_further) {
                c1 = a_point;
                c2 = b_point;
            } else {
                c1 = b_point;
                c2 = a_point;
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
            var dx1: f64 = dx0 - 1.0 - SQUISH_CONSTANT_3D;
            var dy1: f64 = dy0 - 0.0 - SQUISH_CONSTANT_3D;
            var dz1: f64 = dz0 - 0.0 - SQUISH_CONSTANT_3D;
            var attn1: f64 = 2.0 - dx1 * dx1 - dy1 * dy1 - dz1 * dz1;
            if (attn1 > 0.0) {
                attn1 *= attn1;
                value += attn1 * attn1 * extrapolate3(n, xsb + 1, ysb + 0, zsb + 0, dx1, dy1, dz1);
            }
            var dx2: f64 = dx0 - 0.0 - SQUISH_CONSTANT_3D;
            var dy2: f64 = dy0 - 1.0 - SQUISH_CONSTANT_3D;
            var dz2: f64 = dz1;
            var attn2: f64 = 2.0 - dx2 * dx2 - dy2 * dy2 - dz2 * dz2;
            if (attn2 > 0.0) {
                attn2 *= attn2;
                value += attn2 * attn2 * extrapolate3(n, xsb + 0, ysb + 1, zsb + 0, dx2, dy2, dz2);
            }
            var dx3: f64 = dx2;
            var dy3: f64 = dy1;
            var dz3: f64 = dz0 - 1.0 - SQUISH_CONSTANT_3D;
            var attn3: f64 = 2.0 - dx3 * dx3 - dy3 * dy3 - dz3 * dz3;
            if (attn3 > 0.0) {
                attn3 *= attn3;
                value += attn3 * attn3 * extrapolate3(n, xsb + 0, ysb + 0, zsb + 1, dx3, dy3, dz3);
            }
            var dx4: f64 = dx0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
            var dy4: f64 = dy0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
            var dz4: f64 = dz0 - 0.0 - 2.0 * SQUISH_CONSTANT_3D;
            var attn4: f64 = 2.0 - dx4 * dx4 - dy4 * dy4 - dz4 * dz4;
            if (attn4 > 0.0) {
                attn4 *= attn4;
                value += attn4 * attn4 * extrapolate3(n, xsb + 1, ysb + 1, zsb + 0, dx4, dy4, dz4);
            }
            var dx5: f64 = dx4;
            var dy5: f64 = dy0 - 0.0 - 2.0 * SQUISH_CONSTANT_3D;
            var dz5: f64 = dz0 - 1.0 - 2.0 * SQUISH_CONSTANT_3D;
            var attn5: f64 = 2.0 - dx5 * dx5 - dy5 * dy5 - dz5 * dz5;
            if (attn5 > 0.0) {
                attn5 *= attn5;
                value += attn5 * attn5 * extrapolate3(n, xsb + 1, ysb + 0, zsb + 1, dx5, dy5, dz5);
            }
            var dx6: f64 = dx0 - 0.0 - 2.0 * SQUISH_CONSTANT_3D;
            var dy6: f64 = dy4;
            var dz6: f64 = dz5;
            var attn6: f64 = 2.0 - dx6 * dx6 - dy6 * dy6 - dz6 * dz6;
            if (attn6 > 0.0) {
                attn6 *= attn6;
                value += attn6 * attn6 * extrapolate3(n, xsb + 0, ysb + 1, zsb + 1, dx6, dy6, dz6);
            }
        }
    }

    {
        var attn_ext0: f64 = 2.0 - dx_ext0 * dx_ext0 - dy_ext0 * dy_ext0 - dz_ext0 * dz_ext0;
        var attn_ext1: f64 = 2.0 - dx_ext1 * dx_ext1 - dy_ext1 * dy_ext1 - dz_ext1 * dz_ext1;
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

pub fn noiseFbm2d(n: *const OpenSimplex, x: f64, y: f64, octaves: u8, lacunarity: f64, gain: f64) f64 {
    if (octaves == 0) return 0.0;
    var total: f64 = 0.0;
    var amplitude: f64 = 1.0;
    var frequency: f64 = 1.0;
    var i: u8 = 0;
    while (i < octaves) : (i += 1) {
        total += amplitude * noise2d(n, x * frequency, y * frequency);
        frequency *= lacunarity;
        amplitude *= gain;
    }
    return total;
}
