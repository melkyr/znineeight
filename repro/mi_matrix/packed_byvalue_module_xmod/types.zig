pub const Pair = packed struct { lo: u4, hi: u4 };

pub fn build(lo: u4, hi: u4) Pair {
    return Pair{ .lo = lo, .hi = hi };
}

pub fn sum(p: Pair) i32 {
    return @intCast(i32, p.lo) + @intCast(i32, p.hi);
}
