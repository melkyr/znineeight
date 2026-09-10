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
