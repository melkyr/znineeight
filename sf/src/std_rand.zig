// std_rand.zig — Z98 std lib L5: PCG32 and xoshiro256**.
//
// Contract (blueprint §3 L5): alloc none | errors none | coroutine no. Pure
// (no imports). Two concrete state types, free functions, explicit seeds.
// All modular arithmetic uses the explicit wrap operators (`+%`, `*%`) so the
// default -fsafe build does not trap on the expected mod-2^64 arithmetic.
// Rotations and intentional truncating left shifts mask the high half first:
// -fsafe traps on a left shift that discards bits.

pub const Pcg32 = struct {
    state: u64,
    inc: u64,
};

pub const Xoshiro256 = struct {
    s: [4]u64,
};

const PCG_MULT: u64 = 6364136223846793005;
const SPLITMIX_INC: u64 = 0x9E3779B97F4A7C15;
const SPLITMIX_MUL1: u64 = 0xBF58476D1CE4E5B9;
const SPLITMIX_MUL2: u64 = 0x94D049BB133111EB;

fn mask64(bits: u64) u64 {
    if (bits == 0) return 0;
    if (bits >= 64) return ~@intCast(u64, 0);
    return (@intCast(u64, 1) << bits) - 1;
}

fn mask32(bits: u32) u32 {
    if (bits == 0) return 0;
    if (bits >= 32) return ~@intCast(u32, 0);
    var one: u32 = 1;
    return (one << bits) - 1;
}

fn rotl64(x: u64, n: u64) u64 {
    var s: u64 = n % 64;
    if (s == 0) return x;
    var keep: u64 = x & mask64(64 - s);
    return (keep << s) | (x >> (64 - s));
}

fn rotl32(x: u32, n: u32) u32 {
    var s: u32 = n % 32;
    if (s == 0) return x;
    var keep: u32 = x & mask32(32 - s);
    return (keep << s) | (x >> (32 - s));
}

// O'Neill's pcg32_srandom_r: seed the LCG (stream is the odd increment), then
// advance once, add the seed state, and advance again.
pub fn pcg32Init(seed: u64, stream: u64) Pcg32 {
    var r = Pcg32{ .state = 0, .inc = (stream *% 2) | 1 };
    _ = pcg32Next(&r);
    r.state = r.state +% seed;
    _ = pcg32Next(&r);
    return r;
}

pub fn pcg32Next(r: *Pcg32) u32 {
    var old: u64 = r.state;
    r.state = old *% PCG_MULT +% r.inc;
    var xorshifted: u32 = @intCast(u32, (((old >> 18) ^ old) >> 27) & @intCast(u64, 0xFFFFFFFF));
    var rot: u32 = @intCast(u32, old >> 59);
    if (rot == 0) return xorshifted;
    return rotl32(xorshifted, 32 - rot);
}

pub fn pcg32Bounded(r: *Pcg32, bound: u32) u32 {
    if (bound == 0) {
        @panic("pcg32Bounded: bound must be nonzero");
        return 0;
    }
    var b64: u64 = @intCast(u64, bound);
    var threshold: u32 = @intCast(u32, ((@intCast(u64, 1) << 32) - b64) % b64);
    while (true) {
        var v: u32 = pcg32Next(r);
        if (@intCast(u64, v) >= @intCast(u64, threshold)) return v % bound;
    }
    return 0;
}

pub fn pcg32Advance(r: *Pcg32, delta: u64) void {
    var acc_mult: u64 = 1;
    var acc_plus: u64 = 0;
    var cur_mult: u64 = PCG_MULT;
    var cur_plus: u64 = r.inc;
    var d: u64 = delta;
    while (d > 0) {
        if ((d & 1) != 0) {
            acc_mult = acc_mult *% cur_mult;
            acc_plus = acc_plus *% cur_mult +% cur_plus;
        }
        cur_plus = (cur_mult +% 1) *% cur_plus;
        cur_mult = cur_mult *% cur_mult;
        d >>= 1;
    }
    r.state = acc_mult *% r.state +% acc_plus;
}

pub fn xoshiroInit(seed: u64) Xoshiro256 {
    var r: Xoshiro256 = undefined;
    var x: u64 = seed;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        x = x +% SPLITMIX_INC;
        var z: u64 = x;
        z = (z ^ (z >> 30)) *% SPLITMIX_MUL1;
        z = (z ^ (z >> 27)) *% SPLITMIX_MUL2;
        r.s[i] = z ^ (z >> 31);
    }
    return r;
}

pub fn xoshiroNext(r: *Xoshiro256) u64 {
    var result: u64 = rotl64(r.s[1] *% 5, 7) *% 9;
    var t: u64 = (r.s[1] & mask64(47)) << 17;
    r.s[2] = r.s[2] ^ r.s[0];
    r.s[3] = r.s[3] ^ r.s[1];
    r.s[1] = r.s[1] ^ r.s[2];
    r.s[0] = r.s[0] ^ r.s[3];
    r.s[2] = r.s[2] ^ t;
    r.s[3] = rotl64(r.s[3], 45);
    return result;
}

pub fn xoshiroBounded(r: *Xoshiro256, bound: u64) u64 {
    if (bound == 0) {
        @panic("xoshiroBounded: bound must be nonzero");
        return 0;
    }
    var threshold: u64 = ((~bound) +% 1) % bound;
    while (true) {
        var v: u64 = xoshiroNext(r);
        if (v >= threshold) return v % bound;
    }
    return 0;
}
