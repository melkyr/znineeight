// stdlib_bits_table_xmod — STDLIB std_bits (L0) table-driven GREEN fixture.
//
// std_bits.zig is a PURE, import-free (L0) Z98 module; this fixture imports it
// directly by module basename (the compiler's lib search path binds the
// canonical <exe>/lib std_bits.zig) AND exercises the std.zig re-export
// (`std.bits`) with one smoke check.
//
// Contract (blueprint §3 L0): bit manipulation on u32/u64, pure, no imports.
// Boundary cases pinned here:
//   clz32(0) == 32, ctz32(0) == 32, clz64(0) == 64, ctz64(0) == 64
//   nextPow2(0) == 1, rotl32(x, 32) == x, mask(0) == 0, mask(32) == 0xFFFFFFFF
// extract/insert trap on out-of-range offsets via `unreachable` (not exercised:
// a trap is not a GREEN run); every other function is total.
//
// GREEN (contract): deterministic byte-exact stdout `bits ok\n` (RUNRC=0).
// A mismatch increments g_fail and calls @panic; the final line is `bits ok`
// only when g_fail == 0, so a silent/soft-panic target still fails visibly.
const std = @import("std");
const bits = @import("std_bits.zig");

const ALL32: u32 = ~@intCast(u32, 0);
const ALL64: u64 = ~@intCast(u64, 0);
const HI32: u32 = @intCast(u32, 0x80000000);
const HI64: u64 = @intCast(u64, 0x8000000000000000);
const LO64: u64 = @intCast(u64, 0xFFFFFFFF);

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

const Case = struct { x: u32, want: u32 };
const Case64 = struct { x: u64, want: u32 };
const BoolCase = struct { x: u32, want: bool };

pub fn main() void {
    var pc32 = [_]Case{
        Case{ .x = 0, .want = 0 },
        Case{ .x = 1, .want = 1 },
        Case{ .x = HI32, .want = 1 },
        Case{ .x = ALL32, .want = 32 },
        Case{ .x = @intCast(u32, 0xF0F0F0F0), .want = 16 },
        Case{ .x = @intCast(u32, 0x80000001), .want = 2 },
    };
    var i: usize = 0;
    while (i < pc32.len) : (i += 1) {
        ck(bits.popcount32(pc32[i].x) == pc32[i].want, "popcount32");
    }

    var pc64 = [_]Case64{
        Case64{ .x = 0, .want = 0 },
        Case64{ .x = 1, .want = 1 },
        Case64{ .x = HI64, .want = 1 },
        Case64{ .x = ALL64, .want = 64 },
        Case64{ .x = LO64, .want = 32 },
        Case64{ .x = @intCast(u64, 0x8000000000000001), .want = 2 },
    };
    i = 0;
    while (i < pc64.len) : (i += 1) {
        ck(bits.popcount64(pc64[i].x) == pc64[i].want, "popcount64");
    }

    var cz32 = [_]Case{
        Case{ .x = 0, .want = 32 },
        Case{ .x = 1, .want = 31 },
        Case{ .x = HI32, .want = 0 },
        Case{ .x = @intCast(u32, 0x00010000), .want = 15 },
        Case{ .x = ALL32, .want = 0 },
    };
    i = 0;
    while (i < cz32.len) : (i += 1) {
        ck(bits.clz32(cz32[i].x) == cz32[i].want, "clz32");
    }

    var cz64 = [_]Case64{
        Case64{ .x = 0, .want = 64 },
        Case64{ .x = 1, .want = 63 },
        Case64{ .x = HI64, .want = 0 },
        Case64{ .x = @intCast(u64, 0x0000000100000000), .want = 31 },
    };
    i = 0;
    while (i < cz64.len) : (i += 1) {
        ck(bits.clz64(cz64[i].x) == cz64[i].want, "clz64");
    }

    var tz32 = [_]Case{
        Case{ .x = 0, .want = 32 },
        Case{ .x = 1, .want = 0 },
        Case{ .x = HI32, .want = 31 },
        Case{ .x = @intCast(u32, 0x00010000), .want = 16 },
    };
    i = 0;
    while (i < tz32.len) : (i += 1) {
        ck(bits.ctz32(tz32[i].x) == tz32[i].want, "ctz32");
    }

    var tz64 = [_]Case64{
        Case64{ .x = 0, .want = 64 },
        Case64{ .x = 1, .want = 0 },
        Case64{ .x = HI64, .want = 63 },
        Case64{ .x = @intCast(u64, 0x0000000100000000), .want = 32 },
    };
    i = 0;
    while (i < tz64.len) : (i += 1) {
        ck(bits.ctz64(tz64[i].x) == tz64[i].want, "ctz64");
    }

    var rv = [_]Case{
        Case{ .x = 0, .want = 0 },
        Case{ .x = 1, .want = HI32 },
        Case{ .x = HI32, .want = 1 },
        Case{ .x = ALL32, .want = ALL32 },
        Case{ .x = @intCast(u32, 0x12345678), .want = @intCast(u32, 0x1E6A2C48) },
        Case{ .x = @intCast(u32, 0x0000FFFF), .want = @intCast(u32, 0xFFFF0000) },
    };
    i = 0;
    while (i < rv.len) : (i += 1) {
        ck(bits.bitrev32(rv[i].x) == rv[i].want, "bitrev32");
    }

    var mk = [_]Case{
        Case{ .x = 0, .want = 0 },
        Case{ .x = 1, .want = 1 },
        Case{ .x = 8, .want = @intCast(u32, 0xFF) },
        Case{ .x = 31, .want = @intCast(u32, 0x7FFFFFFF) },
        Case{ .x = 32, .want = ALL32 },
    };
    i = 0;
    while (i < mk.len) : (i += 1) {
        ck(bits.mask(mk[i].x) == mk[i].want, "mask");
    }

    var np = [_]Case{
        Case{ .x = 0, .want = 1 },
        Case{ .x = 1, .want = 1 },
        Case{ .x = 2, .want = 2 },
        Case{ .x = 3, .want = 4 },
        Case{ .x = 4, .want = 4 },
        Case{ .x = 5, .want = 8 },
        Case{ .x = @intCast(u32, 0x10000000), .want = @intCast(u32, 0x10000000) },
        Case{ .x = @intCast(u32, 0x10000001), .want = @intCast(u32, 0x20000000) },
    };
    i = 0;
    while (i < np.len) : (i += 1) {
        ck(bits.nextPow2(np[i].x) == np[i].want, "nextPow2");
    }
    ck(bits.nextPow2(ALL32) == 0, "nextPow2 overflow -> 0");

    var pw = [_]BoolCase{
        BoolCase{ .x = 0, .want = false },
        BoolCase{ .x = 1, .want = true },
        BoolCase{ .x = 2, .want = true },
        BoolCase{ .x = 3, .want = false },
        BoolCase{ .x = HI32, .want = true },
        BoolCase{ .x = ALL32, .want = false },
    };
    i = 0;
    while (i < pw.len) : (i += 1) {
        ck(bits.isPow2(pw[i].x) == pw[i].want, "isPow2");
    }

    ck(bits.rotl32(@intCast(u32, 0x80000001), 1) == @intCast(u32, 0x00000003), "rotl32 carry");
    ck(bits.rotl32(@intCast(u32, 0x12345678), 32) == @intCast(u32, 0x12345678), "rotl32 n=32 identity");
    ck(bits.rotl32(@intCast(u32, 0x12345678), 0) == @intCast(u32, 0x12345678), "rotl32 n=0 identity");
    ck(bits.rotl32(@intCast(u32, 0x12345678), 33) == bits.rotl32(@intCast(u32, 0x12345678), 1), "rotl32 wraps mod 32");

    ck(bits.rotr32(@intCast(u32, 0x00000003), 1) == @intCast(u32, 0x80000001), "rotr32 carry");
    ck(bits.rotr32(@intCast(u32, 0x12345678), 32) == @intCast(u32, 0x12345678), "rotr32 n=32 identity");
    ck(bits.rotr32(@intCast(u32, 0x12345678), 0) == @intCast(u32, 0x12345678), "rotr32 n=0 identity");
    ck(bits.rotr32(bits.rotl32(@intCast(u32, 0xDEADBEEF), 7), 7) == @intCast(u32, 0xDEADBEEF), "rotl/rotr roundtrip");

    ck(bits.extract(@intCast(u32, 0x12345678), 0, 8) == @intCast(u32, 0x78), "extract low byte");
    ck(bits.extract(@intCast(u32, 0x12345678), 8, 8) == @intCast(u32, 0x56), "extract byte 1");
    ck(bits.extract(@intCast(u32, 0x12345678), 16, 16) == @intCast(u32, 0x1234), "extract high half");
    ck(bits.extract(ALL32, 0, 32) == ALL32, "extract full width");
    ck(bits.extract(@intCast(u32, 0x12345678), 0, 0) == 0, "extract zero len");
    ck(bits.extract(@intCast(u32, 0x12345678), 28, 4) == 1, "extract top nibble");

    ck(bits.insert(0, @intCast(u32, 0xFF), 0, 8) == @intCast(u32, 0xFF), "insert low byte");
    ck(bits.insert(ALL32, 0, 0, 8) == @intCast(u32, 0xFFFFFF00), "insert clears field");
    ck(bits.insert(0, 1, 31, 1) == HI32, "insert top bit");
    ck(bits.insert(0, @intCast(u32, 0xFFFF), 16, 16) == @intCast(u32, 0xFFFF0000), "insert high half");
    ck(bits.insert(ALL32, 0, 0, 32) == 0, "insert zero full width");
    ck(bits.insert(0, ALL32, 0, 32) == ALL32, "insert ones full width");
    ck(bits.insert(@intCast(u32, 0x12345678), @intCast(u32, 0xAA), 8, 8) == @intCast(u32, 0x1234AA78), "insert byte 1");
    ck(bits.insert(bits.extract(@intCast(u32, 0x12345678), 8, 8), @intCast(u32, 0xAA), 0, 8) == @intCast(u32, 0xAA), "extract/insert compose");

    var via_std: u32 = std.bits.popcount32(@intCast(u32, 0xF0F0F0F0));
    ck(via_std == 16, "std.bits re-export");

    if (g_fail == 0) {
        std.io.write("bits ok\n");
    } else {
        std.io.write("bits FAIL\n");
    }
}
