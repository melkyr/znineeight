// rng.zig — UNDERSANDED xorshift32 (spec §25.5).
//
// Shifts, XOR, and pre-shift masks only: no multiply, so no u32 overflow trap
// (R7). A zero state is reseeded to ZERO_SEED. rngSeed applies the 3× warm-up
// that kills seed correlation across fights.

pub const ZERO_SEED: u32 = 0x9E3779B9;
pub const WARMUP_DRAWS: i32 = 3;

// Pre-shift masks keep the u32 wrap explicit under -fsafe (the same idiom as
// std_crypto's rotate steps); the result is bit-identical to `x << n`.
const SHL13_MASK: u32 = 0x0007FFFF;
const SHL5_MASK: u32 = 0x07FFFFFF;

pub fn rngNext(s: *u32) u32 {
    if (s.* == 0) s.* = ZERO_SEED;

    var x = s.*;
    x = x ^ ((x & SHL13_MASK) << 13);
    x = x ^ (x >> 17);
    x = x ^ ((x & SHL5_MASK) << 5);
    s.* = x;
    return x;
}

pub fn rngRange(s: *u32, lo: i32, hi: i32) i32 {
    if (hi < lo) @panic("rngRange: hi < lo");
    const span: u32 = @intCast(u32, hi - lo + 1);
    const r: u32 = rngNext(s) % span;
    return lo + @intCast(i32, r);
}

pub fn rngSeed(s: *u32, seed: u32) void {
    s.* = seed;
    var i: i32 = 0;
    while (i < WARMUP_DRAWS) : (i += 1) {
        _ = rngNext(s);
    }
}
