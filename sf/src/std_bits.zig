// std_bits.zig — Z98 std lib L0: pure bit manipulation on u32/u64.
//
// Contract (blueprint §3 L0): alloc no | errors no | coroutine no. No imports
// (L0 is pure computation). Z98 has no bit builtins (only @bitCast), so every
// function is a hand-written loop/arithmetic total function — with one
// exception: extract/insert trap on out-of-range offsets via `unreachable`.
//
// Bounds for extract/insert (out of range => trap):
//   off < 32, len <= 32, and off + len <= 32.
// Every other function is total for all inputs (clz/ctz of 0 return the width;
// nextPow2(0) == 1; mask(bits) is defined for bits in [0,32]).

pub fn popcount32(x: u32) u32 {
    var v: u32 = x;
    var c: u32 = 0;
    while (v != 0) {
        c += v & 1;
        v = v >> 1;
    }
    return c;
}

pub fn popcount64(x: u64) u32 {
    var v: u64 = x;
    var c: u32 = 0;
    while (v != 0) {
        c += @intCast(u32, v & 1);
        v = v >> 1;
    }
    return c;
}

pub fn clz32(x: u32) u32 {
    if (x == 0) return 32;
    var n: u32 = 0;
    var bit: u32 = @intCast(u32, 0x80000000);
    while ((x & bit) == 0) {
        n += 1;
        bit = bit >> 1;
    }
    return n;
}

pub fn clz64(x: u64) u32 {
    if (x == 0) return 64;
    var n: u32 = 0;
    var bit: u64 = @intCast(u64, 0x8000000000000000);
    while ((x & bit) == 0) {
        n += 1;
        bit = bit >> 1;
    }
    return n;
}

pub fn ctz32(x: u32) u32 {
    if (x == 0) return 32;
    var n: u32 = 0;
    var v: u32 = x;
    while ((v & 1) == 0) {
        n += 1;
        v = v >> 1;
    }
    return n;
}

pub fn ctz64(x: u64) u32 {
    if (x == 0) return 64;
    var n: u32 = 0;
    var v: u64 = x;
    while ((v & 1) == 0) {
        n += 1;
        v = v >> 1;
    }
    return n;
}

// Rotations mask the left-shifted half first: -fsafe traps on any left shift
// that discards high bits, and a raw `x << s` would discard exactly the bits
// the paired right shift re-inserts. Masking keeps the shift lossless.
pub fn rotl32(x: u32, n: u32) u32 {
    var s: u32 = n % 32;
    if (s == 0) return x;
    var keep: u32 = x & mask(32 - s);
    return (keep << s) | (x >> (32 - s));
}

pub fn rotr32(x: u32, n: u32) u32 {
    var s: u32 = n % 32;
    if (s == 0) return x;
    var keep: u32 = x & mask(s);
    return (x >> s) | (keep << (32 - s));
}

pub fn bitrev32(x: u32) u32 {
    var v: u32 = x;
    var r: u32 = 0;
    var i: u32 = 0;
    while (i < 32) : (i += 1) {
        r = (r << 1) | (v & 1);
        v = v >> 1;
    }
    return r;
}

pub fn mask(bits: u32) u32 {
    if (bits == 0) return 0;
    if (bits >= 32) return ~@intCast(u32, 0);
    var one: u32 = 1;
    return (one << bits) - 1;
}

pub fn extract(x: u32, off: u32, len: u32) u32 {
    if (off >= 32) {
        unreachable;
    }
    if (len > 32) {
        unreachable;
    }
    if (off + len > 32) {
        unreachable;
    }
    return (x >> off) & mask(len);
}

pub fn insert(x: u32, val: u32, off: u32, len: u32) u32 {
    if (off >= 32) {
        unreachable;
    }
    if (len > 32) {
        unreachable;
    }
    if (off + len > 32) {
        unreachable;
    }
    if (len == 0) return x;
    var m: u32 = mask(len);
    var field: u32 = m << off;
    var cleared: u32 = x & ~field;
    var placed: u32 = (val & m) << off;
    return cleared | placed;
}

pub fn isPow2(x: u32) bool {
    if (x == 0) return false;
    var m: u32 = x - 1;
    return (x & m) == 0;
}

pub fn nextPow2(x: u32) u32 {
    if (x <= 1) return 1;
    var v: u32 = x - 1;
    v = v | (v >> 1);
    v = v | (v >> 2);
    v = v | (v >> 4);
    v = v | (v >> 8);
    v = v | (v >> 16);
    // x > 0x80000000 has no representable next power of two in u32; return 0
    // rather than trapping (total-function contract).
    if (v == ~@intCast(u32, 0)) return 0;
    return v + 1;
}
