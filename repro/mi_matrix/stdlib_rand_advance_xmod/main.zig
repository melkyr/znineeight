// stdlib_rand_advance_xmod — std_rand (L5) advance/equivalence fixture.
//
// pcg32Advance(1000) must leave state == 1000 calls of pcg32Next; the fixture
// prints both states and five subsequent equal output pairs. Two xoshiro
// instances with the same seed must agree over 1000 next calls; the fixture
// prints the 1000th outputs and five subsequent pairs.
//
// GREEN (contract): byte-exact stdout `expected.txt` and RUNRC=0.
const std = @import("std");
const rand = @import("std_rand.zig");

const SEED: u64 = 0xDEADBEEF;

fn hexChar(v: u64) u8 {
    if (v < 10) return @intCast(u8, @intCast(u32, '0') + @intCast(u32, v));
    return @intCast(u8, @intCast(u32, 'a') + @intCast(u32, v - 10));
}

fn writeHexPadded(v: u64, digits: usize) void {
    var buf: [16]u8 = undefined;
    var i: usize = 0;
    while (i < digits) : (i += 1) {
        var sh: u64 = @intCast(u64, (digits - 1 - i) * 4);
        buf[i] = hexChar((v >> sh) & 15);
    }
    std.io.write(buf[0..digits]);
}

fn ck(cond: bool) void {
    if (!cond) @panic("rand advance mismatch");
}

pub fn main() void {
    var advanced = rand.pcg32Init(SEED, 1);
    var stepped = rand.pcg32Init(SEED, 1);
    rand.pcg32Advance(&advanced, 1000);
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        _ = rand.pcg32Next(&stepped);
    }
    ck(advanced.state == stepped.state);
    ck(advanced.inc == stepped.inc);

    std.io.write("pcg state ");
    writeHexPadded(advanced.state, 16);
    std.io.write(" ");
    writeHexPadded(stepped.state, 16);
    std.io.write("\n");

    i = 0;
    while (i < 5) : (i += 1) {
        var a: u32 = rand.pcg32Next(&advanced);
        var b: u32 = rand.pcg32Next(&stepped);
        ck(a == b);
        std.io.write("pcg ");
        writeHexPadded(@intCast(u64, a), 8);
        std.io.write(" ");
        writeHexPadded(@intCast(u64, b), 8);
        std.io.write("\n");
    }

    var x1 = rand.xoshiroInit(SEED);
    var x2 = rand.xoshiroInit(SEED);
    var last1: u64 = 0;
    var last2: u64 = 0;
    i = 0;
    while (i < 1000) : (i += 1) {
        last1 = rand.xoshiroNext(&x1);
        last2 = rand.xoshiroNext(&x2);
        ck(last1 == last2);
    }
    std.io.write("xoshiro step ");
    writeHexPadded(last1, 16);
    std.io.write(" ");
    writeHexPadded(last2, 16);
    std.io.write("\n");

    i = 0;
    while (i < 5) : (i += 1) {
        var a: u64 = rand.xoshiroNext(&x1);
        var b: u64 = rand.xoshiroNext(&x2);
        ck(a == b);
        std.io.write("xoshiro ");
        writeHexPadded(a, 16);
        std.io.write(" ");
        writeHexPadded(b, 16);
        std.io.write("\n");
    }

    std.io.write("rand advance ok\n");
}
