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

// f64 sine/cosine, pure Z98 (no libm externs, no @sin/@cos builtins).
//
// Ported from fdlibm's __ieee754_rem_pio2 (medium range), __kernel_sin and
// __kernel_cos. Argument reduction is Cody-Waite with a split 2/pi:
//     x = n*(pi/2) + r,   |r| <= pi/4
// pio2_1 holds the top 33 significant bits of pi/2, so n*pio2_1 is EXACT for
// |n| < 2^20; two further split constants recover pi/2 - pio2_1 - pio2_2 to
// ~150 bits, and y1 keeps the low part for the kernel's correction term. The
// quadrant n mod 4 selects sin/cos and a sign.
//
// Accuracy is <= 1 ULP vs a correctly-rounded oracle (python3/glibc) over
// |x| <= 2^20*(pi/2) ~ 1.65e6 (fdlibm's medium-reduction limit; covers the
// Vorbis IMDCT/window argument range, max ~ pi*8192, with >60x headroom).
// Outside that domain sin/cos return NaN; sinTruncToI32 additionally saturates
// rather than trapping, so no `-fsafe` integer overflow can occur anywhere.
//
// Every arithmetic step is written as its own statement. The C89 emitter
// stores a double per statement, which forces round-to-f64 at each step so
// x87 80-bit excess precision cannot leak into the result: the output is
// bit-for-bit reproducible under the fixture's `gcc -m32 -O0` build.
//
// f64 bits are moved with the same @ptrCast helpers `sqrt` uses (Z98 has no
// f64 @bitCast), and the constants are built from exact IEEE-754 bit patterns
// (the lexer's decimal-float parser is not correctly rounded).

const SinReduce = struct { n: i32, y0: f64, y1: f64 };

// floor(v) for 0 <= v < 2^31 (fewer than 31 significant bits by construction);
// returns a saturating value for v outside that range so @intCast never traps.
fn sinTruncToI32(v: f64) i32 {
    var b: u64 = sqrtD2B(v);
    var e: i64 = @intCast(i64, (b >> 52) & 0x7ff) - 1023;
    if (e < 0) return 0;
    if (e > 30) return 0x7fffffff;
    var m: u64 = (b & 0xfffffffffffff) | 0x10000000000000;
    var t: u64 = m >> @intCast(u64, @intCast(u32, 52 - e));
    return @intCast(i32, t);
}

// x = n*(pi/2) + (y0 + y1) for the non-negative magnitude v. The three-stage
// Cody-Waite refinement runs unconditionally (equivalent to fdlibm taking its
// 2nd/3rd cancellation branches); the extra stages are a no-op when unused.
fn sinReduce(v: f64) SinReduce {
    var invpio2: f64 = sqrtB2D(0x3fe45f306dc9c883);
    var pio2_1: f64 = sqrtB2D(0x3ff921fb54400000);
    var pio2_2: f64 = sqrtB2D(0x3dd0b4611a600000);
    var pio2_2t: f64 = sqrtB2D(0x3ba3198a2e037073);
    var pio2_3: f64 = sqrtB2D(0x3ba3198a2e000000);
    var pio2_3t: f64 = sqrtB2D(0x397b839a252049c1);
    var w: f64 = v * invpio2;
    w = w + 0.5;
    var n: i32 = sinTruncToI32(w);
    var fn_: f64 = @intToFloat(f64, n);
    var r: f64 = fn_ * pio2_1;
    r = v - r;
    var t: f64 = r;
    var ww: f64 = fn_ * pio2_2;
    r = t - ww;
    var a: f64 = t - r;
    var z: f64 = a - ww;
    ww = fn_ * pio2_2t;
    ww = ww - z;
    var y0: f64 = r - ww;
    t = r;
    ww = fn_ * pio2_3;
    r = t - ww;
    a = t - r;
    z = a - ww;
    ww = fn_ * pio2_3t;
    ww = ww - z;
    y0 = r - ww;
    var y1: f64 = r - y0;
    y1 = y1 - ww;
    return SinReduce{ .n = n, .y0 = y0, .y1 = y1 };
}

// fdlibm __kernel_sin: sin(x + y) for |x| <= pi/4. `iy` is 1 when `y` carries
// the reduction tail (general case) and 0 for the direct small-|x| path.
fn sinKernel(x: f64, y: f64, iy: i32) f64 {
    var s1: f64 = sqrtB2D(0xbfc5555555555549);
    var s2: f64 = sqrtB2D(0x3f8111111110f8a6);
    var s3: f64 = sqrtB2D(0xbf2a01a019c161d5);
    var s4: f64 = sqrtB2D(0x3ec71de357b1fe7d);
    var s5: f64 = sqrtB2D(0xbe5ae5e68a2b9ceb);
    var s6: f64 = sqrtB2D(0x3de5d93a5acfd57c);
    var z: f64 = x * x;
    var v: f64 = z * x;
    var p: f64 = z * s6;
    p = p + s5;
    p = z * p;
    p = p + s4;
    p = z * p;
    p = p + s3;
    p = z * p;
    var r: f64 = p + s2;
    if (iy == 0) {
        var q: f64 = z * r;
        q = q + s1;
        q = v * q;
        return x + q;
    }
    var t1: f64 = 0.5 * y;
    var t2: f64 = v * r;
    t1 = t1 - t2;
    var t3: f64 = z * t1;
    t3 = t3 - y;
    var t4: f64 = v * s1;
    t3 = t3 - t4;
    return x - t3;
}

// fdlibm __kernel_cos: cos(x + y) for |x| <= pi/4.
fn cosKernel(x: f64, y: f64) f64 {
    var c1: f64 = sqrtB2D(0x3fa555555555554c);
    var c2: f64 = sqrtB2D(0xbf56c16c16c15177);
    var c3: f64 = sqrtB2D(0x3efa01a019cb1590);
    var c4: f64 = sqrtB2D(0xbe927e4f809c52ad);
    var c5: f64 = sqrtB2D(0x3e21ee9ebdb4b1c4);
    var c6: f64 = sqrtB2D(0xbda8fae9be8838d4);
    var zb: u64 = sqrtD2B(x);
    var ix: u32 = @intCast(u32, (zb >> 32) & 0x7fffffff);
    var z: f64 = x * x;
    var p: f64 = z * c6;
    p = p + c5;
    p = z * p;
    p = p + c4;
    p = z * p;
    p = p + c3;
    p = z * p;
    p = p + c2;
    p = z * p;
    p = p + c1;
    var r: f64 = z * p;
    var t1: f64 = 0.5 * z;
    var t2: f64 = z * r;
    var t3: f64 = x * y;
    t2 = t2 - t3;
    if (ix < 0x3fd33333) {
        t1 = t1 - t2;
        return 1.0 - t1;
    }
    var qx: f64 = 0.0;
    if (ix > 0x3fe90000) {
        qx = sqrtB2D(0x3fd2000000000000);
    } else {
        var qhi: u64 = @intCast(u64, ix - 0x00200000);
        qx = sqrtB2D(qhi << 32);
    }
    var hz: f64 = t1 - qx;
    var aa: f64 = 1.0 - qx;
    t3 = hz - t2;
    return aa - t3;
}

pub fn sin(x: f64) f64 {
    var xb: u64 = sqrtD2B(x);
    var ix: u32 = @intCast(u32, (xb >> 32) & 0x7fffffff);
    if (ix >= 0x7ff00000) {
        if (x != x) { return x; }
        return sqrtB2D(0x7ff8000000000000);
    }
    if (ix <= 0x3fe921fb) {
        return sinKernel(x, 0.0, 0);
    }
    if (ix > 0x413921fb) {
        return sqrtB2D(0x7ff8000000000000);
    }
    var neg: bool = x < 0.0;
    var v: f64 = x;
    if (neg) { v = -v; }
    var red: SinReduce = sinReduce(v);
    var n: i32 = red.n;
    var y0: f64 = red.y0;
    var y1: f64 = red.y1;
    if (neg) {
        y0 = -y0;
        y1 = -y1;
        n = -n;
    }
    var q: i32 = n & 3;
    if (q == 0) { return sinKernel(y0, y1, 1); }
    if (q == 1) { return cosKernel(y0, y1); }
    if (q == 2) { return -sinKernel(y0, y1, 1); }
    return -cosKernel(y0, y1);
}

pub fn cos(x: f64) f64 {
    var xb: u64 = sqrtD2B(x);
    var ix: u32 = @intCast(u32, (xb >> 32) & 0x7fffffff);
    if (ix >= 0x7ff00000) {
        if (x != x) { return x; }
        return sqrtB2D(0x7ff8000000000000);
    }
    if (ix <= 0x3fe921fb) {
        return cosKernel(x, 0.0);
    }
    if (ix > 0x413921fb) {
        return sqrtB2D(0x7ff8000000000000);
    }
    var neg: bool = x < 0.0;
    var v: f64 = x;
    if (neg) { v = -v; }
    var red: SinReduce = sinReduce(v);
    var n: i32 = red.n;
    var y0: f64 = red.y0;
    var y1: f64 = red.y1;
    if (neg) {
        y0 = -y0;
        y1 = -y1;
        n = -n;
    }
    var q: i32 = n & 3;
    if (q == 0) { return cosKernel(y0, y1); }
    if (q == 1) { return -sinKernel(y0, y1, 1); }
    if (q == 2) { return -cosKernel(y0, y1); }
    return sinKernel(y0, y1, 1);
}

