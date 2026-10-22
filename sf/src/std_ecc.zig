// std_ecc.zig — Z98 std lib L5: X25519, P-256 ECDH/ECDSA verify,
// P-384 ECDSA verify.
//
// Contract: alloc no | errors only for invalid inputs/weak X25519 output |
// coroutine no. Pure except for the caller-supplied xoshiro256** state in
// p256Generate. Constant-time scalar multiplication: no secret-dependent
// branches or table indices; no heap, libm, C99 or compiler builtins; integer
// arithmetic only (no f64 intermediates).
//
// X25519 is the ref10 10-limb (26/25-bit alternating) Montgomery ladder from
// SUPERCOP crypto_scalarmult/curve25519/ref10 (public domain / CC0, D. J.
// Bernstein et al.), with the RFC 7748 clamp and all-zero output rejection.
//
// P-256/P-384 use one shared generic prime-curve engine ported from BearSSL
// `src/ec/ec_prime_i31.c` and the `src/int/i31_*.c` primitives, Copyright (c)
// 2016 Thomas Pornin, MIT licence (see /tmp/bearssl-src/LICENSE.txt in the
// phase-1 workspace; the same notice is reproduced here):
//
//   Permission is hereby granted, free of charge, to any person obtaining a
//   copy of this software and associated documentation files (the
//   "Software"), to deal in the Software without restriction, including
//   without limitation the rights to use, copy, modify, merge, publish,
//   distribute, sublicense, and/or sell copies of the Software, and to permit
//   persons to whom the Software is furnished to do so, subject to the
//   following conditions:
//
//   The above copyright notice and this permission notice shall be included
//   in all copies or substantial portions of the Software.
//
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
//   THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//   DEALINGS IN THE SOFTWARE.
//
// The BearSSL interpreter/curve code is preserved; the only arithmetic change
// is that modular exponentiation stays in Montgomery form throughout (the
// exponents are public curve constants), which removes the need for the
// division/to-Montgomery helpers without changing the result.

const rand = @import("std_rand.zig");

// ---------------------------------------------------------------------------
// X25519 — ref10 10-limb field arithmetic modulo 2^255-19
// ---------------------------------------------------------------------------

const Fe = [10]i64;

fn fe0(h: *Fe) void {
    var i: usize = 0;
    while (i < 10) : (i += 1) h[i] = 0;
}

fn fe1(h: *Fe) void {
    h[0] = 1;
    var i: usize = 1;
    while (i < 10) : (i += 1) h[i] = 0;
}

fn feCopy(h: *Fe, f: *const Fe) void {
    var i: usize = 0;
    while (i < 10) : (i += 1) h[i] = f[i];
}

fn feAdd(h: *Fe, f: *const Fe, g: *const Fe) void {
    var i: usize = 0;
    while (i < 10) : (i += 1) h[i] = f[i] + g[i];
}

fn feSub(h: *Fe, f: *const Fe, g: *const Fe) void {
    var i: usize = 0;
    while (i < 10) : (i += 1) h[i] = f[i] - g[i];
}

fn feCswap(f: *Fe, g: *Fe, b: u32) void {
    var m: i64 = 0 -% @intCast(i64, b);
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var x: i64 = (f[i] ^ g[i]) & m;
        f[i] = f[i] ^ x;
        g[i] = g[i] ^ x;
    }
}

fn feCarry(h: *[10]i64) void {
    var c: i64 = 0;
    c = (h[0] + 33554432) >> 26;
    h[1] += c;
    h[0] -= c * 67108864;
    c = (h[4] + 33554432) >> 26;
    h[5] += c;
    h[4] -= c * 67108864;
    c = (h[1] + 16777216) >> 25;
    h[2] += c;
    h[1] -= c * 33554432;
    c = (h[5] + 16777216) >> 25;
    h[6] += c;
    h[5] -= c * 33554432;
    c = (h[2] + 33554432) >> 26;
    h[3] += c;
    h[2] -= c * 67108864;
    c = (h[6] + 33554432) >> 26;
    h[7] += c;
    h[6] -= c * 67108864;
    c = (h[3] + 16777216) >> 25;
    h[4] += c;
    h[3] -= c * 33554432;
    c = (h[7] + 16777216) >> 25;
    h[8] += c;
    h[7] -= c * 33554432;
    c = (h[4] + 33554432) >> 26;
    h[5] += c;
    h[4] -= c * 67108864;
    c = (h[8] + 33554432) >> 26;
    h[9] += c;
    h[8] -= c * 67108864;
    c = (h[9] + 16777216) >> 25;
    h[0] += c * 19;
    h[9] -= c * 33554432;
    c = (h[0] + 33554432) >> 26;
    h[1] += c;
    h[0] -= c * 67108864;
}

fn feMul(h: *Fe, f: *const Fe, g: *const Fe) void {
    var f0: i64 = f[0];
    var f1: i64 = f[1];
    var f2: i64 = f[2];
    var f3: i64 = f[3];
    var f4: i64 = f[4];
    var f5: i64 = f[5];
    var f6: i64 = f[6];
    var f7: i64 = f[7];
    var f8: i64 = f[8];
    var f9: i64 = f[9];
    var g0: i64 = g[0];
    var g1: i64 = g[1];
    var g2: i64 = g[2];
    var g3: i64 = g[3];
    var g4: i64 = g[4];
    var g5: i64 = g[5];
    var g6: i64 = g[6];
    var g7: i64 = g[7];
    var g8: i64 = g[8];
    var g9: i64 = g[9];


    var h0: i64 = f0 * g0 + 38 * f1 * g9 + 19 * f2 * g8 + 38 * f3 * g7 + 19 * f4 * g6 + 38 * f5 * g5 + 19 * f6 * g4 + 38 * f7 * g3 + 19 * f8 * g2 + 38 * f9 * g1;
    var h1: i64 = f0 * g1 + f1 * g0 + 19 * f2 * g9 + 19 * f3 * g8 + 19 * f4 * g7 + 19 * f5 * g6 + 19 * f6 * g5 + 19 * f7 * g4 + 19 * f8 * g3 + 19 * f9 * g2;
    var h2: i64 = f0 * g2 + 2 * f1 * g1 + f2 * g0 + 38 * f3 * g9 + 19 * f4 * g8 + 38 * f5 * g7 + 19 * f6 * g6 + 38 * f7 * g5 + 19 * f8 * g4 + 38 * f9 * g3;
    var h3: i64 = f0 * g3 + f1 * g2 + f2 * g1 + f3 * g0 + 19 * f4 * g9 + 19 * f5 * g8 + 19 * f6 * g7 + 19 * f7 * g6 + 19 * f8 * g5 + 19 * f9 * g4;
    var h4: i64 = f0 * g4 + 2 * f1 * g3 + f2 * g2 + 2 * f3 * g1 + f4 * g0 + 38 * f5 * g9 + 19 * f6 * g8 + 38 * f7 * g7 + 19 * f8 * g6 + 38 * f9 * g5;
    var h5: i64 = f0 * g5 + f1 * g4 + f2 * g3 + f3 * g2 + f4 * g1 + f5 * g0 + 19 * f6 * g9 + 19 * f7 * g8 + 19 * f8 * g7 + 19 * f9 * g6;
    var h6: i64 = f0 * g6 + 2 * f1 * g5 + f2 * g4 + 2 * f3 * g3 + f4 * g2 + 2 * f5 * g1 + f6 * g0 + 38 * f7 * g9 + 19 * f8 * g8 + 38 * f9 * g7;
    var h7: i64 = f0 * g7 + f1 * g6 + f2 * g5 + f3 * g4 + f4 * g3 + f5 * g2 + f6 * g1 + f7 * g0 + 19 * f8 * g9 + 19 * f9 * g8;
    var h8: i64 = f0 * g8 + 2 * f1 * g7 + f2 * g6 + 2 * f3 * g5 + f4 * g4 + 2 * f5 * g3 + f6 * g2 + 2 * f7 * g1 + f8 * g0 + 38 * f9 * g9;
    var h9: i64 = f0 * g9 + f1 * g8 + f2 * g7 + f3 * g6 + f4 * g5 + f5 * g4 + f6 * g3 + f7 * g2 + f8 * g1 + f9 * g0;


    var c: i64 = 0;
    c = (h0 + 33554432) >> 26;
    h1 += c;
    h0 -= c * 67108864;
    c = (h4 + 33554432) >> 26;
    h5 += c;
    h4 -= c * 67108864;
    c = (h1 + 16777216) >> 25;
    h2 += c;
    h1 -= c * 33554432;
    c = (h5 + 16777216) >> 25;
    h6 += c;
    h5 -= c * 33554432;
    c = (h2 + 33554432) >> 26;
    h3 += c;
    h2 -= c * 67108864;
    c = (h6 + 33554432) >> 26;
    h7 += c;
    h6 -= c * 67108864;
    c = (h3 + 16777216) >> 25;
    h4 += c;
    h3 -= c * 33554432;
    c = (h7 + 16777216) >> 25;
    h8 += c;
    h7 -= c * 33554432;
    c = (h4 + 33554432) >> 26;
    h5 += c;
    h4 -= c * 67108864;
    c = (h8 + 33554432) >> 26;
    h9 += c;
    h8 -= c * 67108864;
    c = (h9 + 16777216) >> 25;
    h0 += c * 19;
    h9 -= c * 33554432;
    c = (h0 + 33554432) >> 26;
    h1 += c;
    h0 -= c * 67108864;

    h[0] = h0;
    h[1] = h1;
    h[2] = h2;
    h[3] = h3;
    h[4] = h4;
    h[5] = h5;
    h[6] = h6;
    h[7] = h7;
    h[8] = h8;
    h[9] = h9;
}


fn feSq(h: *Fe, f: *const Fe) void {
    feMul(h, f, f);
}

fn feMul121666(h: *Fe, f: *const Fe) void {
    var u: [10]i64 = undefined;
    var i: usize = 0;
    while (i < 10) : (i += 1) u[i] = f[i] * 121666;
    feCarry(&u);
    i = 0;
    while (i < 10) : (i += 1) h[i] = u[i];
}

fn load3(p: []const u8, off: usize) i64 {
    var r: i64 = @intCast(i64, p[off]);
    r |= @intCast(i64, p[off + 1]) << 8;
    r |= @intCast(i64, p[off + 2]) << 16;
    return r;
}

fn load4(p: []const u8, off: usize) i64 {
    var r: i64 = @intCast(i64, p[off]);
    r |= @intCast(i64, p[off + 1]) << 8;
    r |= @intCast(i64, p[off + 2]) << 16;
    r |= @intCast(i64, p[off + 3]) << 24;
    return r;
}

fn feFromBytes(h: *Fe, s: []const u8) void {
    var h0: i64 = load4(s, 0);
    var h1: i64 = load3(s, 4) << 6;
    var h2: i64 = load3(s, 7) << 5;
    var h3: i64 = load3(s, 10) << 3;
    var h4: i64 = load3(s, 13) << 2;
    var h5: i64 = load4(s, 16);
    var h6: i64 = load3(s, 20) << 7;
    var h7: i64 = load3(s, 23) << 5;
    var h8: i64 = load3(s, 26) << 4;
    var h9: i64 = (load3(s, 29) & 8388607) << 2;

    var c: i64 = 0;
    c = (h9 + 16777216) >> 25;
    h0 += c * 19;
    h9 -= c * 33554432;
    c = (h1 + 16777216) >> 25;
    h2 += c;
    h1 -= c * 33554432;
    c = (h3 + 16777216) >> 25;
    h4 += c;
    h3 -= c * 33554432;
    c = (h5 + 16777216) >> 25;
    h6 += c;
    h5 -= c * 33554432;
    c = (h7 + 16777216) >> 25;
    h8 += c;
    h7 -= c * 33554432;
    c = (h0 + 33554432) >> 26;
    h1 += c;
    h0 -= c * 67108864;
    c = (h2 + 33554432) >> 26;
    h3 += c;
    h2 -= c * 67108864;
    c = (h4 + 33554432) >> 26;
    h5 += c;
    h4 -= c * 67108864;
    c = (h6 + 33554432) >> 26;
    h7 += c;
    h6 -= c * 67108864;
    c = (h8 + 33554432) >> 26;
    h9 += c;
    h8 -= c * 67108864;

    h[0] = h0;
    h[1] = h1;
    h[2] = h2;
    h[3] = h3;
    h[4] = h4;
    h[5] = h5;
    h[6] = h6;
    h[7] = h7;
    h[8] = h8;
    h[9] = h9;
}

fn feToBytes(s: []u8, h: *const Fe) void {
    var h0: i64 = h[0];
    var h1: i64 = h[1];
    var h2: i64 = h[2];
    var h3: i64 = h[3];
    var h4: i64 = h[4];
    var h5: i64 = h[5];
    var h6: i64 = h[6];
    var h7: i64 = h[7];
    var h8: i64 = h[8];
    var h9: i64 = h[9];

    var q: i64 = (19 * h9 + 16777216) >> 25;
    q = (h0 + q) >> 26;
    q = (h1 + q) >> 25;
    q = (h2 + q) >> 26;
    q = (h3 + q) >> 25;
    q = (h4 + q) >> 26;
    q = (h5 + q) >> 25;
    q = (h6 + q) >> 26;
    q = (h7 + q) >> 25;
    q = (h8 + q) >> 26;
    q = (h9 + q) >> 25;

    h0 += 19 * q;
    var c: i64 = 0;
    c = h0 >> 26;
    h1 += c;
    h0 -= c * 67108864;
    c = h1 >> 25;
    h2 += c;
    h1 -= c * 33554432;
    c = h2 >> 26;
    h3 += c;
    h2 -= c * 67108864;
    c = h3 >> 25;
    h4 += c;
    h3 -= c * 33554432;
    c = h4 >> 26;
    h5 += c;
    h4 -= c * 67108864;
    c = h5 >> 25;
    h6 += c;
    h5 -= c * 33554432;
    c = h6 >> 26;
    h7 += c;
    h6 -= c * 67108864;
    c = h7 >> 25;
    h8 += c;
    h7 -= c * 33554432;
    c = h8 >> 26;
    h9 += c;
    h8 -= c * 67108864;
    c = h9 >> 25;
    h9 -= c * 33554432;

    s[0] = @intCast(u8, h0 & 255);
    s[1] = @intCast(u8, (h0 >> 8) & 255);
    s[2] = @intCast(u8, (h0 >> 16) & 255);
    s[3] = @intCast(u8, ((h0 >> 24) | (h1 << 2)) & 255);
    s[4] = @intCast(u8, (h1 >> 6) & 255);
    s[5] = @intCast(u8, (h1 >> 14) & 255);
    s[6] = @intCast(u8, ((h1 >> 22) | (h2 << 3)) & 255);
    s[7] = @intCast(u8, (h2 >> 5) & 255);
    s[8] = @intCast(u8, (h2 >> 13) & 255);
    s[9] = @intCast(u8, ((h2 >> 21) | (h3 << 5)) & 255);
    s[10] = @intCast(u8, (h3 >> 3) & 255);
    s[11] = @intCast(u8, (h3 >> 11) & 255);
    s[12] = @intCast(u8, ((h3 >> 19) | (h4 << 6)) & 255);
    s[13] = @intCast(u8, (h4 >> 2) & 255);
    s[14] = @intCast(u8, (h4 >> 10) & 255);
    s[15] = @intCast(u8, (h4 >> 18) & 255);
    s[16] = @intCast(u8, h5 & 255);
    s[17] = @intCast(u8, (h5 >> 8) & 255);
    s[18] = @intCast(u8, (h5 >> 16) & 255);
    s[19] = @intCast(u8, ((h5 >> 24) | (h6 << 1)) & 255);
    s[20] = @intCast(u8, (h6 >> 7) & 255);
    s[21] = @intCast(u8, (h6 >> 15) & 255);
    s[22] = @intCast(u8, ((h6 >> 23) | (h7 << 3)) & 255);
    s[23] = @intCast(u8, (h7 >> 5) & 255);
    s[24] = @intCast(u8, (h7 >> 13) & 255);
    s[25] = @intCast(u8, ((h7 >> 21) | (h8 << 4)) & 255);
    s[26] = @intCast(u8, (h8 >> 4) & 255);
    s[27] = @intCast(u8, (h8 >> 12) & 255);
    s[28] = @intCast(u8, ((h8 >> 20) | (h9 << 6)) & 255);
    s[29] = @intCast(u8, (h9 >> 2) & 255);
    s[30] = @intCast(u8, (h9 >> 10) & 255);
    s[31] = @intCast(u8, (h9 >> 18) & 255);
}

fn feSqN(out: *Fe, in: *const Fe, n: u32) void {
    feSq(out, in);
    var i: u32 = 1;
    while (i < n) : (i += 1) feSq(out, out);
}

fn feInvert(out: *Fe, z: *const Fe) void {
    var t0: Fe = undefined;
    var t1: Fe = undefined;
    var t2: Fe = undefined;
    var t3: Fe = undefined;

    feSqN(&t0, z, 1);
    feSqN(&t1, &t0, 2);
    feMul(&t1, z, &t1);
    feMul(&t0, &t0, &t1);
    feSqN(&t2, &t0, 1);
    feMul(&t1, &t1, &t2);
    feSqN(&t2, &t1, 5);
    feMul(&t1, &t2, &t1);
    feSqN(&t2, &t1, 10);
    feMul(&t2, &t2, &t1);
    feSqN(&t3, &t2, 20);
    feMul(&t2, &t3, &t2);
    feSqN(&t2, &t2, 10);
    feMul(&t1, &t2, &t1);
    feSqN(&t2, &t1, 50);
    feMul(&t2, &t2, &t1);
    feSqN(&t3, &t2, 100);
    feMul(&t2, &t3, &t2);
    feSqN(&t2, &t2, 50);
    feMul(&t1, &t2, &t1);
    feSqN(&t1, &t1, 5);
    feMul(out, &t1, &t0);
}

fn x25519Ladder(scalar: []const u8, u: []const u8, out: []u8) void {
    var e: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) e[i] = scalar[i];
    e[0] &= 248;
    e[31] &= 127;
    e[31] |= 64;

    var x1: Fe = undefined;
    var x2: Fe = undefined;
    var z2: Fe = undefined;
    var x3: Fe = undefined;
    var z3: Fe = undefined;
    var tmp0: Fe = undefined;
    var tmp1: Fe = undefined;

    feFromBytes(&x1, u);
    fe1(&x2);
    fe0(&z2);
    feCopy(&x3, &x1);
    fe1(&z3);

    var swap: u32 = 0;
    var p: usize = 255;
    while (p > 0) : (p -= 1) {
        var pos: usize = p - 1;
        var b: u32 = @intCast(u32, e[pos / 8]);
        b = (b >> @intCast(u32, pos & 7)) & 1;

        swap ^= b;
        feCswap(&x2, &x3, swap);
        feCswap(&z2, &z3, swap);
        swap = b;

        feSub(&tmp0, &x3, &z3);
        feSub(&tmp1, &x2, &z2);
        feAdd(&x2, &x2, &z2);
        feAdd(&z2, &x3, &z3);
        feMul(&z3, &tmp0, &x2);
        feMul(&z2, &z2, &tmp1);
        feSq(&tmp0, &tmp1);
        feSq(&tmp1, &x2);
        feAdd(&x3, &z3, &z2);
        feSub(&z2, &z3, &z2);
        feMul(&x2, &tmp1, &tmp0);
        feSub(&tmp1, &tmp1, &tmp0);
        feSq(&z2, &z2);
        feMul121666(&z3, &tmp1);
        feSq(&x3, &x3);
        feAdd(&tmp0, &tmp0, &z3);
        feMul(&z3, &x1, &z2);
        feMul(&z2, &tmp1, &tmp0);
    }
    feCswap(&x2, &x3, swap);
    feCswap(&z2, &z3, swap);

    feInvert(&z2, &z2);
    feMul(&x2, &x2, &z2);
    feToBytes(out, &x2);
}

fn allZero(p: []const u8) bool {
    var z: u8 = 0;
    var i: usize = 0;
    while (i < p.len) : (i += 1) z |= p[i];
    return z == 0;
}

pub fn x25519(scalar: *const [32]u8, u: *const [32]u8, out: *[32]u8) !void {
    x25519Ladder(scalar[0..], u[0..], out[0..]);
    if (allZero(out[0..])) return error.WeakPublicKey;
}

pub fn x25519Base(scalar: *const [32]u8, out: *[32]u8) !void {
    var base: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) base[i] = 0;
    base[0] = 9;
    try x25519(scalar, &base, out);
}

// ---------------------------------------------------------------------------
// Shared prime-curve engine (BearSSL i31 port), P-256 and P-384
// ---------------------------------------------------------------------------

const I31_LEN: usize = 19;

const P256_P = [19]u32{
    0x00000108,
    0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x00000007,
    0x00000000, 0x00000000, 0x00000040, 0x7FFFFF80,
    0x000000FF, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

const P256_R2 = [19]u32{
    0x00000108,
    0x00014000, 0x00018000, 0x00000000, 0x7FF40000,
    0x7FEFFFFF, 0x7FF7FFFF, 0x7FAFFFFF, 0x005FFFFF,
    0x00000000, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

const P256_B = [19]u32{
    0x00000108,
    0x6FEE1803, 0x6229C4BD, 0x21B139BE, 0x327150AA,
    0x3567802E, 0x3F7212ED, 0x012E4355, 0x782DD38D,
    0x0000000E, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

const P384_P = [19]u32{
    0x0000018C,
    0x7FFFFFFF, 0x00000001, 0x00000000, 0x7FFFFFF8,
    0x7FFFFFEF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF,
    0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF,
    0x00000FFF, 0, 0, 0, 0, 0,
};

const P384_R2 = [19]u32{
    0x0000018C,
    0x00000000, 0x00000080, 0x7FFFFE00, 0x000001FF,
    0x00000800, 0x00000000, 0x7FFFE000, 0x00001FFF,
    0x00008000, 0x00008000, 0x00000000, 0x00000000,
    0x00000000, 0, 0, 0, 0, 0,
};

const P384_B = [19]u32{
    0x0000018C,
    0x6E666840, 0x070D0392, 0x5D810231, 0x7651D50C,
    0x17E218D6, 0x1B192002, 0x44EFE441, 0x3A524E2B,
    0x2719BA5F, 0x41F02209, 0x36C5643E, 0x5813EFFE,
    0x000008A5, 0, 0, 0, 0, 0,
};

const P256_N = [32]u8{
    0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xBC, 0xE6, 0xFA, 0xAD, 0xA7, 0x17, 0x9E, 0x84,
    0xF3, 0xB9, 0xCA, 0xC2, 0xFC, 0x63, 0x25, 0x51,
};

const P256_G = [65]u8{
    0x04,
    0x6B, 0x17, 0xD1, 0xF2, 0xE1, 0x2C, 0x42,
    0x47, 0xF8, 0xBC, 0xE6, 0xE5, 0x63, 0xA4, 0x40,
    0xF2, 0x77, 0x03, 0x7D, 0x81, 0x2D, 0xEB, 0x33,
    0xA0, 0xF4, 0xA1, 0x39, 0x45, 0xD8, 0x98, 0xC2,
    0x96, 0x4F, 0xE3, 0x42, 0xE2, 0xFE, 0x1A, 0x7F,
    0x9B, 0x8E, 0xE7, 0xEB, 0x4A, 0x7C, 0x0F, 0x9E,
    0x16, 0x2B, 0xCE, 0x33, 0x57, 0x6B, 0x31, 0x5E,
    0xCE, 0xCB, 0xB6, 0x40, 0x68, 0x37, 0xBF, 0x51,
    0xF5,
};

const P384_N = [48]u8{
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xC7, 0x63, 0x4D, 0x81, 0xF4, 0x37, 0x2D, 0xDF,
    0x58, 0x1A, 0x0D, 0xB2, 0x48, 0xB0, 0xA7, 0x7A,
    0xEC, 0xEC, 0x19, 0x6A, 0xCC, 0xC5, 0x29, 0x73,
};

const P384_G = [97]u8{
    0x04,
    0xAA, 0x87, 0xCA, 0x22, 0xBE, 0x8B, 0x05,
    0x37, 0x8E, 0xB1, 0xC7, 0x1E, 0xF3, 0x20, 0xAD,
    0x74, 0x6E, 0x1D, 0x3B, 0x62, 0x8B, 0xA7, 0x9B,
    0x98, 0x59, 0xF7, 0x41, 0xE0, 0x82, 0x54, 0x2A,
    0x38, 0x55, 0x02, 0xF2, 0x5D, 0xBF, 0x55, 0x29,
    0x6C, 0x3A, 0x54, 0x5E, 0x38, 0x72, 0x76, 0x0A,
    0xB7, 0x36, 0x17, 0xDE, 0x4A, 0x96, 0x26, 0x2C,
    0x6F, 0x5D, 0x9E, 0x98, 0xBF, 0x92, 0x92, 0xDC,
    0x29, 0xF8, 0xF4, 0x1D, 0xBD, 0x28, 0x9A, 0x14,
    0x7C, 0xE9, 0xDA, 0x31, 0x13, 0xB5, 0xF0, 0xB8,
    0xC0, 0x0A, 0x60, 0xB1, 0xCE, 0x1D, 0x7E, 0x81,
    0x9D, 0x7A, 0x43, 0x1D, 0x7C, 0x90, 0xEA, 0x0E,
    0x5F,
};

const CURVE_P256: u32 = 23;
const CURVE_P384: u32 = 24;

fn curveP(c: u32) []const u32 {
    if (c == CURVE_P256) return P256_P[0..];
    return P384_P[0..];
}

fn curveR2(c: u32) []const u32 {
    if (c == CURVE_P256) return P256_R2[0..];
    return P384_R2[0..];
}

fn curveB(c: u32) []const u32 {
    if (c == CURVE_P256) return P256_B[0..];
    return P384_B[0..];
}

fn curveOrder(c: u32) []const u8 {
    if (c == CURVE_P256) return P256_N[0..];
    return P384_N[0..];
}

fn curveGenerator(c: u32) []const u8 {
    if (c == CURVE_P256) return P256_G[0..];
    return P384_G[0..];
}

fn curvePointLen(c: u32) usize {
    if (c == CURVE_P256) return 65;
    return 97;
}

fn mux32(ctl: u32, x: u32, y: u32) u32 {
    return y ^ ((0 -% ctl) & (x ^ y));
}

fn not32(c: u32) u32 {
    return c ^ 1;
}

fn eq32(x: u32, y: u32) u32 {
    var q: u32 = x ^ y;
    return not32((q | (0 -% q)) >> 31);
}

fn neq32(x: u32, y: u32) u32 {
    var q: u32 = x ^ y;
    return (q | (0 -% q)) >> 31;
}

fn gt32(x: u32, y: u32) u32 {
    var z: u32 = y -% x;
    return (z ^ ((x ^ y) & (x ^ z))) >> 31;
}

fn i31Zero(x: []u32, bit_len: u32) void {
    x[0] = bit_len;
    var m: usize = @intCast(usize, (bit_len + 31) >> 5);
    var i: usize = 1;
    while (i <= m) : (i += 1) x[i] = 0;
}

fn i31Add(a: []u32, b: []const u32, ctl: u32) u32 {
    var cc: u32 = 0;
    var m: usize = @intCast(usize, (a[0] + 63) >> 5);
    var u: usize = 1;
    while (u < m) : (u += 1) {
        var aw: u32 = a[u];
        var bw: u32 = b[u];
        var naw: u32 = aw +% bw +% cc;
        cc = naw >> 31;
        a[u] = mux32(ctl, naw & 0x7FFFFFFF, aw);
    }
    return cc;
}

fn i31Sub(a: []u32, b: []const u32, ctl: u32) u32 {
    var cc: u32 = 0;
    var m: usize = @intCast(usize, (a[0] + 63) >> 5);
    var u: usize = 1;
    while (u < m) : (u += 1) {
        var aw: u32 = a[u];
        var bw: u32 = b[u];
        var naw: u32 = aw -% bw -% cc;
        cc = naw >> 31;
        a[u] = mux32(ctl, naw & 0x7FFFFFFF, aw);
    }
    return cc;
}

fn i31Montymul(d: []u32, x: []const u32, y: []const u32, m: []const u32, m0i: u32) void {
    var len: usize = @intCast(usize, (m[0] + 31) >> 5);
    i31Zero(d, m[0]);
    var dh: u32 = 0;
    var u: usize = 0;
    while (u < len) : (u += 1) {
        var xu: u32 = x[u + 1];
        var f: u32 = ((d[1] +% (xu *% y[1] & 0x7FFFFFFF)) *% m0i) & 0x7FFFFFFF;
        var r: u64 = 0;
        var v: usize = 0;
        while (v < len) : (v += 1) {
            var z: u64 = @intCast(u64, d[v + 1]) +
                @intCast(u64, xu) * @intCast(u64, y[v + 1]) +
                @intCast(u64, f) * @intCast(u64, m[v + 1]) + r;
            r = z >> 31;
            d[v] = @intCast(u32, z & 0x7FFFFFFF);
        }
        dh += @intCast(u32, r);
        d[len] = dh & 0x7FFFFFFF;
        dh >>= 31;
    }
    d[0] = m[0];
    i31Sub(d, m, neq32(dh, 0) | not32(i31Sub(d, m, 0)));
}

fn i31Ninv31(x: u32) u32 {
    var y: u32 = 2 -% x;
    y *%= 2 -% y *% x;
    y *%= 2 -% y *% x;
    y *%= 2 -% y *% x;
    y *%= 2 -% y *% x;
    return mux32(x & 1, 0 -% y, 0) & 0x7FFFFFFF;
}

fn i31Iszero(x: []const u32) u32 {
    var z: u32 = 0;
    var u: usize = @intCast(usize, (x[0] + 31) >> 5);
    while (u > 0) {
        z |= x[u];
        u -= 1;
    }
    return not32((z | (0 -% z)) >> 31);
}

fn bitLength32(x: u32) u32 {
    var v: u32 = x;
    var k: u32 = 0;
    if (v != 0) {
        k = 1;
        var c: u32 = gt32(v, 0xFFFF);
        v = mux32(c, v >> 16, v);
        k += c << 4;
        c = gt32(v, 0xFF);
        v = mux32(c, v >> 8, v);
        k += c << 3;
        c = gt32(v, 0xF);
        v = mux32(c, v >> 4, v);
        k += c << 2;
        c = gt32(v, 0x3);
        v = mux32(c, v >> 2, v);
        k += c << 1;
        k += gt32(v, 0x1);
    }
    return k;
}

fn i31BitLength(x: []const u32, start: usize, count: usize) u32 {
    var tw: u32 = 0;
    var twk: u32 = 0;
    var i: usize = count;
    while (i > 0) {
        i -= 1;
        var c: u32 = eq32(tw, 0);
        var w: u32 = x[start + i];
        tw = mux32(c, w, tw);
        twk = mux32(c, @intCast(u32, i), twk);
    }
    return (twk << 5) + bitLength32(tw);
}

fn i31Decode(x: []u32, src: []const u8) void {
    var u: usize = src.len;
    var v: usize = 1;
    var acc: u32 = 0;
    var acc_len: u32 = 0;
    while (u > 0) {
        u -= 1;
        var b: u32 = @intCast(u32, src[u]);
        acc |= b << acc_len;
        acc_len += 8;
        if (acc_len >= 31) {
            x[v] = acc & 0x7FFFFFFF;
            v += 1;
            acc_len -= 31;
            acc = b >> (8 - acc_len);
        }
    }
    if (acc_len != 0) {
        x[v] = acc;
        v += 1;
    }
    x[0] = i31BitLength(x, 1, v - 1);
}

fn i31DecodeMod(x: []u32, src: []const u8, m: []const u32) u32 {
    var mlen: usize = @intCast(usize, (m[0] + 31) >> 5);
    var tlen: usize = mlen << 2;
    if (tlen < src.len) tlen = src.len;
    tlen += 4;
    var r: u32 = 0;
    var pass: usize = 0;
    while (pass < 2) : (pass += 1) {
        var v: usize = 1;
        var acc: u32 = 0;
        var acc_len: u32 = 0;
        var u: usize = 0;
        while (u < tlen) : (u += 1) {
            var b: u32 = 0;
            if (u < src.len) b = @intCast(u32, src[src.len - 1 - u]);
            acc |= b << acc_len;
            acc_len += 8;
            if (acc_len >= 31) {
                var xw: u32 = acc & 0x7FFFFFFF;
                acc_len -= 31;
                acc = b >> (8 - acc_len);
                if (v <= mlen) {
                    if (pass != 0) {
                        x[v] = r & xw;
                    } else {
                        if (xw > m[v]) {
                            r = 1;
                        } else if (xw < m[v]) {
                            r = 0xFFFFFFFF;
                        }
                    }
                } else {
                    if (pass == 0 and xw != 0) r = 1;
                }
                v += 1;
            }
        }
        r >>= 1;
        r |= r << 1;
    }
    x[0] = m[0];
    return r & 1;
}

fn i31Encode(dst: []u8, x: []const u32) void {
    var len: usize = dst.len;
    var i: usize = 0;
    while (i < len) : (i += 1) dst[i] = 0;
    var xlen: usize = @intCast(usize, (x[0] + 31) >> 5);
    if (xlen == 0) return;
    var pos: usize = len;
    var k: usize = 1;
    var acc: u32 = 0;
    var acc_len: u32 = 0;
    while (len != 0) {
        var w: u32 = 0;
        if (k <= xlen) w = x[k];
        k += 1;
        if (acc_len == 0) {
            acc = w;
            acc_len = 31;
        } else {
            var z: u32 = acc | (w << acc_len);
            acc_len -= 1;
            acc = w >> (31 - acc_len);
            if (len >= 4) {
                pos -= 4;
                len -= 4;
                dst[pos] = @intCast(u8, z >> 24);
                dst[pos + 1] = @intCast(u8, (z >> 16) & 0xFF);
                dst[pos + 2] = @intCast(u8, (z >> 8) & 0xFF);
                dst[pos + 3] = @intCast(u8, z & 0xFF);
            } else {
                if (len >= 3) dst[pos - 3] = @intCast(u8, (z >> 16) & 0xFF);
                if (len >= 2) dst[pos - 2] = @intCast(u8, (z >> 8) & 0xFF);
                dst[pos - 1] = @intCast(u8, z & 0xFF);
                return;
            }
        }
    }
}

fn i31Rshift(x: []u32, count: u32) void {
    var len: usize = @intCast(usize, (x[0] + 31) >> 5);
    if (len == 0) return;
    var r: u32 = x[1] >> count;
    var u: usize = 2;
    while (u <= len) : (u += 1) {
        var w: u32 = x[u];
        x[u - 1] = ((w << (31 - count)) | r) & 0x7FFFFFFF;
        r = w >> count;
    }
    x[len] = r;
}

fn ccopyWords(ctl: u32, dst: []u32, src: []const u32) void {
    var mask: u32 = 0 -% ctl;
    var i: usize = 0;
    while (i < dst.len) : (i += 1) {
        dst[i] = dst[i] ^ ((dst[i] ^ src[i]) & mask);
    }
}

fn modPowPlain(dst: []u32, x: []const u32, e: []const u8, m: []const u32, m0i: u32, r2: []const u32) void {
    var one: [I31_LEN]u32 = undefined;
    i31Zero(one[0..], m[0]);
    one[1] = 1;
    var acc: [I31_LEN]u32 = undefined;
    var i: usize = 0;
    while (i < I31_LEN) : (i += 1) acc[i] = one[i];
    var base: [I31_LEN]u32 = undefined;
    i31Montymul(base[0..], x, r2, m, m0i);
    var tmp: [I31_LEN]u32 = undefined;
    var k: usize = 0;
    while (k < e.len * 8) : (k += 1) {
        var ctl: u32 = (@intCast(u32, e[e.len - 1 - (k >> 3)]) >> (@intCast(u32, k) & 7)) & 1;
        i31Montymul(tmp[0..], acc[0..], base[0..], m, m0i);
        ccopyWords(ctl, acc[0..], tmp[0..]);
        i31Montymul(tmp[0..], base[0..], base[0..], m, m0i);
        i = 0;
        while (i < I31_LEN) : (i += 1) base[i] = tmp[i];
    }
    i = 0;
    while (i < dst.len) : (i += 1) dst[i] = acc[i];
}


fn modDouble(x: []u32, m: []const u32) void {
    var carry: u32 = i31Add(x, x, 1);
    var ctl: u32 = carry | not32(i31Sub(x, m, 0));
    i31Sub(x, m, ctl);
}

fn r2Mod(out: []u32, m: []const u32) void {
    i31Zero(out, m[0]);
    out[1] = 1;
    var len: usize = @intCast(usize, (m[0] + 31) >> 5);
    var n: usize = 0;
    while (n < 2 * 31 * len) : (n += 1) modDouble(out, m);
}

const JAC_LEN: usize = 3 * I31_LEN;

const Jacobian = struct {
    c: [JAC_LEN]u32,
};

fn copyJacobian(dst: *Jacobian, src: *const Jacobian) void {
    var i: usize = 0;
    while (i < JAC_LEN) : (i += 1) dst.c[i] = src.c[i];
}

fn ccopyJacobian(ctl: u32, dst: *Jacobian, src: *const Jacobian) void {
    ccopyWords(ctl, dst.c[0..], src.c[0..]);
}

fn setOne(x: []u32, p: []const u32) void {
    var plen: usize = @intCast(usize, (p[0] + 63) >> 5);
    var i: usize = 0;
    while (i < plen) : (i += 1) x[i] = 0;
    x[0] = p[0];
    x[1] = 1;
}

fn pointZero(P: *Jacobian, c: u32) void {
    var i: usize = 0;
    while (i < JAC_LEN) : (i += 1) P.c[i] = 0;
    P.c[0] = curveP(c)[0];
    P.c[I31_LEN] = curveP(c)[0];
    P.c[2 * I31_LEN] = curveP(c)[0];
}


const codeDouble = [24]u16{
    0x3622, 0x0700, 0x2760, 0x1600, 0x3867, 0x0680, 0x1680, 0x1680,
    0x3811, 0x1880, 0x3708, 0x1770, 0x3066, 0x2070, 0x2070, 0x3912,
    0x0290, 0x1290, 0x2700, 0x3167, 0x3988, 0x2190, 0x2190, 0,
};

const codeAdd = [25]u16{
    0x3855, 0x3608, 0x3958, 0x3819, 0x3922, 0x3739, 0x3A29, 0x394A,
    0x2760, 0x2980, 0x5900, 0x3C77, 0x3B6C, 0x3AC7, 0x3099, 0x20A0,
    0x20B0, 0x20B0, 0x2B00, 0x319B, 0x36A8, 0x2160, 0x3625, 0x3267,
    0,
};

const codeCheck = [15]u16{
    0x3603, 0x3713, 0x0060, 0x0170, 0x3700, 0x3607, 0x2600, 0x2600,
    0x2600, 0x1640, 0x3711, 0x2670, 0x5600, 0x3235, 0,
};

const codeAffine = [11]u16{
    0x0620, 0x3722, 0x3827, 0x3785, 0x4789, 0x0810, 0x3178, 0x3876,
    0x0700, 0x3078, 0,
};


fn runCode(P1: *Jacobian, P2: *const Jacobian, c: u32, code: []const u16) u32 {
    var t: [13 * I31_LEN]u32 = undefined;
    var r: u32 = 1;
    var k: usize = 0;
    while (k < 3) : (k += 1) {
        var i: usize = 0;
        while (i < I31_LEN) : (i += 1) {
            t[k * I31_LEN + i] = P1.c[k * I31_LEN + i];
            t[(3 + k) * I31_LEN + i] = P2.c[k * I31_LEN + i];
        }
    }
    var ui: usize = 0;
    while (true) : (ui += 1) {
        var op: u32 = @intCast(u32, code[ui]);
        if (op == 0) break;
        var d: usize = @intCast(usize, (op >> 8) & 0x0F);
        var a: usize = @intCast(usize, (op >> 4) & 0x0F);
        var b: usize = @intCast(usize, op & 0x0F);
        op >>= 12;
        var db: usize = d * I31_LEN;
        var ab: usize = a * I31_LEN;
        var bb: usize = b * I31_LEN;
        if (op == 0) {
            var i: usize = 0;
            while (i < I31_LEN) : (i += 1) t[db + i] = t[ab + i];
        } else if (op == 1) {
            var ctl: u32 = i31Add(t[db..db + I31_LEN], t[ab..ab + I31_LEN], 1);
            ctl |= not32(i31Sub(t[db..db + I31_LEN], curveP(c), 0));
            i31Sub(t[db..db + I31_LEN], curveP(c), ctl);
        } else if (op == 2) {
            i31Add(t[db..db + I31_LEN], curveP(c), i31Sub(t[db..db + I31_LEN], t[ab..ab + I31_LEN], 1));
        } else if (op == 3) {
            i31Montymul(t[db..db + I31_LEN], t[ab..ab + I31_LEN], t[bb..bb + I31_LEN], curveP(c), 1);
        } else if (op == 4) {
            var plen: usize = @intCast(usize, (curveP(c)[0] - (curveP(c)[0] >> 5) + 7) >> 3);
            var tp: [66]u8 = undefined;
            i31Encode(tp[0..plen], curveP(c));
            tp[plen - 1] -= 2;
            modPowPlain(t[db..db + I31_LEN], t[db..db + I31_LEN], tp[0..plen], curveP(c), 1, curveR2(c));
        } else {
            r &= ~i31Iszero(t[db..db + I31_LEN]);
        }
    }
    k = 0;
    while (k < 3) : (k += 1) {
        var i: usize = 0;
        while (i < I31_LEN) : (i += 1) P1.c[k * I31_LEN + i] = t[k * I31_LEN + i];
    }
    return r;
}


fn pointDouble(P: *Jacobian, c: u32) void {
    runCode(P, P, c, codeDouble[0..]);
}

fn pointAdd(P1: *Jacobian, P2: *const Jacobian, c: u32) u32 {
    return runCode(P1, P2, c, codeAdd[0..]);
}

fn pointMul(P: *Jacobian, x: []const u8, c: u32) void {
    var P2: Jacobian = undefined;
    var P3: Jacobian = undefined;
    var Q: Jacobian = undefined;
    var T: Jacobian = undefined;
    var U: Jacobian = undefined;

    copyJacobian(&P2, P);
    pointDouble(&P2, c);
    copyJacobian(&P3, P);
    _ = pointAdd(&P3, &P2, c);

    pointZero(&Q, c);
    var qz: u32 = 1;
    var xi: usize = 0;
    while (xi < x.len) : (xi += 1) {
        var k: i32 = 6;
        while (k >= 0) : (k -= 2) {
            pointDouble(&Q, c);
            pointDouble(&Q, c);
            copyJacobian(&T, P);
            copyJacobian(&U, &Q);
            var bits: u32 = (@intCast(u32, x[xi]) >> @intCast(u32, k)) & 3;
            var bnz: u32 = neq32(bits, 0);
            ccopyJacobian(eq32(bits, 2), &T, &P2);
            ccopyJacobian(eq32(bits, 3), &T, &P3);
            _ = pointAdd(&U, &T, c);
            ccopyJacobian(bnz & qz, &Q, &T);
            ccopyJacobian(bnz & ~qz, &Q, &U);
            qz &= ~bnz;
        }
    }
    copyJacobian(P, &Q);
}

fn pointDecode(P: *Jacobian, src: []const u8, c: u32) u32 {
    var Q: Jacobian = undefined;
    pointZero(P, c);
    var plen: usize = @intCast(usize, (curveP(c)[0] - (curveP(c)[0] >> 5) + 7) >> 3);
    if (src.len != 1 + (plen << 1)) return 0;
    var r: u32 = i31DecodeMod(P.c[0..I31_LEN], src[1..1 + plen], curveP(c));
    r &= i31DecodeMod(P.c[I31_LEN..2 * I31_LEN], src[1 + plen..1 + 2 * plen], curveP(c));
    r &= eq32(@intCast(u32, src[0]), 0x04);

    var zlen: usize = @intCast(usize, (curveP(c)[0] + 63) >> 5);
    var i: usize = 0;
    while (i < zlen) : (i += 1) {
        Q.c[i] = curveR2(c)[i];
        Q.c[I31_LEN + i] = curveB(c)[i];
    }
    setOne(Q.c[2 * I31_LEN..3 * I31_LEN], curveP(c));
    r &= ~runCode(P, &Q, c, codeCheck[0..]);
    return r;
}

fn pointEncode(dst: []u8, P: *const Jacobian, c: u32) void {
    var Q: Jacobian = undefined;
    var T: Jacobian = undefined;
    copyJacobian(&Q, P);
    var i: usize = 0;
    while (i < JAC_LEN) : (i += 1) T.c[i] = 0;
    setOne(T.c[2 * I31_LEN..3 * I31_LEN], curveP(c));
    _ = runCode(&Q, &T, c, codeAffine[0..]);
    var plen: usize = @intCast(usize, (curveP(c)[0] - (curveP(c)[0] >> 5) + 7) >> 3);
    dst[0] = 0x04;
    i31Encode(dst[1..1 + plen], Q.c[0..I31_LEN]);
    i31Encode(dst[1 + plen..1 + 2 * plen], Q.c[I31_LEN..2 * I31_LEN]);
}



fn apiMul(G: []u8, x: []const u8, c: u32) u32 {
    if (G.len != curvePointLen(c)) return 0;
    var P: Jacobian = undefined;
    var r: u32 = pointDecode(&P, G, c);
    pointMul(&P, x, c);
    pointEncode(G, &P, c);
    return r;
}

fn apiMulGen(dst: []u8, x: []const u8, c: u32) void {
    var g: []const u8 = curveGenerator(c);
    var i: usize = 0;
    while (i < g.len) : (i += 1) dst[i] = g[i];
    _ = apiMul(dst, x, c);
}

fn apiMulAdd(A: []u8, x: []const u8, y: []const u8, c: u32) u32 {
    if (A.len != curvePointLen(c)) return 0;
    var P: Jacobian = undefined;
    var Q: Jacobian = undefined;
    var r: u32 = pointDecode(&P, A, c);
    r &= pointDecode(&Q, curveGenerator(c), c);
    pointMul(&P, x, c);
    pointMul(&Q, y, c);

    var t: u32 = pointAdd(&P, &Q, c);
    pointDouble(&Q, c);
    var z: u32 = i31Iszero(P.c[2 * I31_LEN..3 * I31_LEN]);
    ccopyJacobian(z & ~t, &P, &Q);
    pointEncode(A, &P, c);
    r &= ~(z & t);
    return r;
}

fn scalarValid(s: []const u8, c: u32) bool {
    var order: []const u8 = curveOrder(c);
    if (s.len != order.len) return false;
    var z: u8 = 0;
    var borrow: u32 = 0;
    var i: usize = order.len;
    while (i > 0) {
        i -= 1;
        var a: u32 = @intCast(u32, s[i]);
        var b: u32 = @intCast(u32, order[i]) + borrow;
        var d: u32 = a -% b;
        borrow = (d >> 31) & 1;
        z |= s[i];
    }
    return borrow == 1 and z != 0;
}


pub fn p256Generate(rng: *rand.Xoshiro256, priv: *[32]u8, pub_out: *[65]u8) void {
    var pv: []u8 = priv[0..];
    var cand: [32]u8 = undefined;
    while (true) {
        var i: usize = 0;
        while (i < 32) : (i += 8) {
            var v: u64 = rand.xoshiroNext(rng);
            cand[i] = @intCast(u8, (v >> 56) & 0xFF);
            cand[i + 1] = @intCast(u8, (v >> 48) & 0xFF);
            cand[i + 2] = @intCast(u8, (v >> 40) & 0xFF);
            cand[i + 3] = @intCast(u8, (v >> 32) & 0xFF);
            cand[i + 4] = @intCast(u8, (v >> 24) & 0xFF);
            cand[i + 5] = @intCast(u8, (v >> 16) & 0xFF);
            cand[i + 6] = @intCast(u8, (v >> 8) & 0xFF);
            cand[i + 7] = @intCast(u8, v & 0xFF);
        }
        if (scalarValid(cand[0..], CURVE_P256)) {
            var i2: usize = 0;
            while (i2 < 32) : (i2 += 1) pv[i2] = cand[i2];
            apiMulGen(pub_out[0..], cand[0..], CURVE_P256);
            return;
        }
    }
}

pub fn p256Ecdh(priv: *const [32]u8, peer_pub: *const [65]u8, out: *[32]u8) !void {
    if (!scalarValid(priv[0..], CURVE_P256)) return error.InvalidPrivateKey;
    var pp: []const u8 = peer_pub[0..];
    var oo: []u8 = out[0..];
    var g: [65]u8 = undefined;
    var i: usize = 0;
    while (i < 65) : (i += 1) g[i] = pp[i];
    var r: u32 = apiMul(g[0..], priv[0..], CURVE_P256);
    if (r == 0) return error.InvalidPublicKey;
    i = 0;
    while (i < 32) : (i += 1) oo[i] = g[1 + i];
}


fn ecdsaVerify(c: u32, pub_uncompressed: []const u8, hash: []const u8, r_sig: []const u8, s_sig: []const u8) bool {
    var order: []const u8 = curveOrder(c);
    var nlen: usize = order.len;
    if (pub_uncompressed.len != curvePointLen(c)) return false;
    if (r_sig.len != nlen or s_sig.len != nlen) return false;

    var n: [I31_LEN]u32 = undefined;
    i31Decode(n[0..], order);
    var n0i: u32 = i31Ninv31(n[1]);

    var r: [I31_LEN]u32 = undefined;
    var s: [I31_LEN]u32 = undefined;
    if (i31DecodeMod(r[0..], r_sig, n[0..]) == 0) return false;
    if (i31DecodeMod(s[0..], s_sig, n[0..]) == 0) return false;
    if (i31Iszero(s[0..]) != 0) return false;

    var nR2: [I31_LEN]u32 = undefined;
    r2Mod(nR2[0..], n[0..]);
    var oneN: [I31_LEN]u32 = undefined;
    i31Zero(oneN[0..], n[0]);
    oneN[1] = 1;
    var sMont: [I31_LEN]u32 = undefined;
    i31Montymul(sMont[0..], s[0..], oneN[0..], n[0..], n0i);

    var nExp: [48]u8 = undefined;
    i31Encode(nExp[0..nlen], n[0..]);
    nExp[nlen - 1] -= 2;
    var sInv: [I31_LEN]u32 = undefined;
    modPowPlain(sInv[0..], sMont[0..], nExp[0..nlen], n[0..], n0i, nR2[0..]);


    var t1: [I31_LEN]u32 = undefined;
    var t2: [I31_LEN]u32 = undefined;
    bits2int(t1[0..], hash, n[0]);
    i31Sub(t1[0..], n[0..], i31Sub(t1[0..], n[0..], 0) ^ 1);

    i31Montymul(t2[0..], t1[0..], sInv[0..], n[0..], n0i);
    var ty: [48]u8 = undefined;
    i31Encode(ty[0..nlen], t2[0..]);
    i31Montymul(t1[0..], r[0..], sInv[0..], n[0..], n0i);
    var tx: [48]u8 = undefined;
    i31Encode(tx[0..nlen], t1[0..]);

    var eU: [97]u8 = undefined;
    var i: usize = 0;
    while (i < pub_uncompressed.len) : (i += 1) eU[i] = pub_uncompressed[i];
    var res: u32 = apiMulAdd(eU[0..pub_uncompressed.len], tx[0..nlen], ty[0..nlen], c);

    i31Zero(t1[0..], n[0]);
    var plen: usize = pub_uncompressed.len >> 1;
    i31Decode(t1[0..], eU[1..1 + plen]);
    t1[0] = n[0];
    i31Sub(t1[0..], n[0..], i31Sub(t1[0..], n[0..], 0) ^ 1);
    res &= ~i31Sub(t1[0..], r[0..], 1);
    res &= i31Iszero(t1[0..]);
    return res == 1;
}

fn bits2int(x: []u32, src: []const u8, ebitlen: u32) void {
    var bitlen: u32 = ebitlen - (ebitlen >> 5);
    var hbitlen: u32 = @intCast(u32, src.len) << 3;
    var len: usize = src.len;
    var sc: u32 = 0;
    if (hbitlen > bitlen) {
        len = @intCast(usize, (bitlen + 7) >> 3);
        sc = (hbitlen - bitlen) & 7;
    }
    i31Zero(x, ebitlen);
    i31Decode(x, src[0..len]);
    i31Rshift(x, sc);
    x[0] = ebitlen;
}

pub fn p256EcdsaVerify(pub_uncompressed: *const [65]u8, hash32: *const [32]u8, r: *const [32]u8, s: *const [32]u8) bool {
    return ecdsaVerify(CURVE_P256, pub_uncompressed[0..], hash32[0..], r[0..], s[0..]);
}

pub fn p384EcdsaVerify(pub_uncompressed: *const [97]u8, hash48: *const [48]u8, r: *const [48]u8, s: *const [48]u8) bool {
    return ecdsaVerify(CURVE_P384, pub_uncompressed[0..], hash48[0..], r[0..], s[0..]);
}
