pub fn min(a: i32, b: i32) i32 {
    if (a < b) return a;
    return b;
}

pub fn max(a: i32, b: i32) i32 {
    if (a > b) return a;
    return b;
}

pub fn minU(a: u32, b: u32) u32 {
    if (a < b) return a;
    return b;
}

pub fn maxU(a: u32, b: u32) u32 {
    if (a > b) return a;
    return b;
}

pub fn abs(n: i32) i32 {
    if (n < 0) return 0 - n;
    return n;
}

pub fn clamp(v: i32, lo: i32, hi: i32) i32 {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

pub fn clampU(v: u32, lo: u32, hi: u32) u32 {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

pub fn isPowerOfTwoU32(n: u32) bool {
    if (n == 0) return false;
    var m: u32 = n - @intCast(u32, 1);
    return (n & m) == 0;
}

pub fn alignUp(n: u32, alignment: u32) u32 {
    var one: u32 = 1;
    var a: u32 = alignment - one;
    return (n + a) & ~a;
}

pub fn alignDown(n: u32, alignment: u32) u32 {
    var one: u32 = 1;
    var a: u32 = alignment - one;
    return n & ~a;
}

// f64 square root, correctly rounded, pure Z98 (no libm, no @sqrt, no @bitCast).
//
// A plain bit-seed + Newton loop is not correctly rounded (it is 1 ulp off on
// ~25% of inputs, e.g. sqrt(2)), so the result is computed exactly:
//   1. decompose the (normalized) input as x = M * 2^E with M a 53/54-bit
//      integer and E even (subnormals are pre-scaled by 2^54 and E adjusted);
//   2. form the 128-bit integer N = M * 2^60 and take its exact integer square
//      root r = floor(sqrt(N)) by a bit-by-bit restoring algorithm, retaining
//      the remainder N - r^2;
//   3. N has 112..114 bits, so r has exactly 57 bits; round r (with a nonzero
//      remainder as the sticky bit) to a 53-bit significand round-to-nearest-
//      even and rebuild the f64.
// Z98 has no u128 and no f64 @bitCast, hence the two-u64 limbs and the pointer
// reinterpretation helpers below.

const SqrtU128 = struct { hi: u64, lo: u64 };

fn sqrtB2D(b: u64) f64 {
    var p: *f64 = @ptrCast(*f64, &b);
    return p.*;
}

fn sqrtD2B(d: f64) u64 {
    var p: *u64 = @ptrCast(*u64, &d);
    return p.*;
}

fn sqrtU128Add(a: SqrtU128, b: SqrtU128) SqrtU128 {
    var lo: u64 = a.lo +% b.lo;
    var carry: u64 = 0;
    if (lo < a.lo) { carry = 1; }
    var hi: u64 = a.hi +% b.hi;
    hi = hi +% carry;
    return SqrtU128{ .hi = hi, .lo = lo };
}

fn sqrtU128Sub(a: SqrtU128, b: SqrtU128) SqrtU128 {
    var lo: u64 = a.lo -% b.lo;
    var borrow: u64 = 0;
    if (a.lo < b.lo) { borrow = 1; }
    var hi: u64 = a.hi -% b.hi;
    hi = hi -% borrow;
    return SqrtU128{ .hi = hi, .lo = lo };
}

fn sqrtU128Cmp(a: SqrtU128, b: SqrtU128) i32 {
    if (a.hi > b.hi) { return 1; }
    if (a.hi < b.hi) { return -1; }
    if (a.lo > b.lo) { return 1; }
    if (a.lo < b.lo) { return -1; }
    return 0;
}

fn sqrtU128Shr1(a: SqrtU128) SqrtU128 {
    var hi: u64 = a.hi >> 1;
    var lo: u64 = (a.lo >> 1) | ((a.hi & 1) << 63);
    return SqrtU128{ .hi = hi, .lo = lo };
}

fn sqrtU128Shr2(a: SqrtU128) SqrtU128 {
    var hi: u64 = a.hi >> 2;
    var lo: u64 = (a.lo >> 2) | ((a.hi & 3) << 62);
    return SqrtU128{ .hi = hi, .lo = lo };
}

pub fn sqrt(x: f64) f64 {
    var xv: f64 = x;
    if (xv != xv) { return xv; }
    if (xv < 0.0) {
        var one_n: u64 = 1;
        var nb: u64 = 0x7ff;
        nb = nb << 52;
        nb = nb | (one_n << 51);
        return sqrtB2D(nb);
    }
    if (xv == 0.0) { return xv; }
    if (xv + xv == xv) { return xv; }

    var bx: u64 = sqrtD2B(xv);
    var expf: u64 = (bx >> 52) & 0x7ff;
    var subnormal: bool = false;
    if (expf == 0) {
        var one_s: u64 = 1;
        var scale: f64 = @intToFloat(f64, one_s << 54);
        xv = xv * scale;
        bx = sqrtD2B(xv);
        expf = (bx >> 52) & 0x7ff;
        subnormal = true;
    }
    var one_m: u64 = 1;
    var m: u64 = (bx & 0xfffffffffffff) | (one_m << 52);
    var e: i64 = @intCast(i64, expf) - 1023 - 52;
    if (subnormal) { e = e - 54; }
    if ((e & 1) != 0) {
        m = m << 1;
        e = e - 1;
    }

    var n: SqrtU128 = SqrtU128{ .hi = m >> 4, .lo = (m & 0xf) << 60 };
    var r: SqrtU128 = SqrtU128{ .hi = 0, .lo = 0 };
    var one_b: u64 = 1;
    var bit: SqrtU128 = SqrtU128{ .hi = one_b << 48, .lo = 0 };
    while (!(bit.hi == 0 and bit.lo == 0)) {
        var t: SqrtU128 = sqrtU128Add(r, bit);
        if (sqrtU128Cmp(n, t) >= 0) {
            n = sqrtU128Sub(n, t);
            r = sqrtU128Add(sqrtU128Shr1(r), bit);
        } else {
            r = sqrtU128Shr1(r);
        }
        bit = sqrtU128Shr2(bit);
    }

    var one: u64 = 1;
    var kept: u64 = r.lo >> 4;
    var roundbit: u64 = (r.lo >> 3) & one;
    var sticky: bool = ((r.lo & 7) != 0) or (n.lo != 0);
    if (roundbit != 0 and (sticky or (kept & one) != 0)) {
        kept = kept + one;
    }
    var biased: i64 = e / 2 + 1049;
    if (kept >= (one << 53)) {
        kept = kept >> 1;
        biased = biased + 1;
    }
    var ob: u64 = (@intCast(u64, biased) << 52) | (kept & ((one << 52) - 1));
    return sqrtB2D(ob);
}
