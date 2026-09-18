// stdlib_bits_stress_xmod — STDLIB std_bits (L0) hand-written stress table.
//
// No PRNG: every input is an explicit table. Stresses the two round-trip
// contracts of std_bits:
//   - extract(insert(base, v, off, len), off, len) == v, for a written table of
//     (off, len, val) field layouts spanning the width boundaries (len 0/1/32,
//     off 0/31, off+len == 32), and for three bases (0, all-ones, patterned);
//     the bits OUTSIDE the field must be preserved exactly.
//   - rotr32(rotl32(x, n), n) == x and rotl32(rotr32(x, n), n) == x for n in a
//     written set including 0/31/32/33 (and the wrap cases 64/65).
//   - mask(bits) for every width 0..32 against an incrementally built pattern.
//
// GREEN (contract): deterministic byte-exact stdout `bits stress ok\n` (RUNRC=0).
// A mismatch increments g_fail and calls @panic; the final line is
// `bits stress ok` only when g_fail == 0.
const std = @import("std");
const bits = @import("std_bits.zig");

const ALL32: u32 = ~@intCast(u32, 0);
const PAT: u32 = @intCast(u32, 0xDEADBEEF);
var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

const FieldCase = struct { off: u32, len: u32, val: u32 };
const RotCase = struct { x: u32, n: u32 };

pub fn main() void {
    // --- extract(insert(...)) identity over a field-layout table ------------
    var fields = [_]FieldCase{
        FieldCase{ .off = 0, .len = 1, .val = 1 },
        FieldCase{ .off = 0, .len = 32, .val = ALL32 },
        FieldCase{ .off = 0, .len = 32, .val = 0 },
        FieldCase{ .off = 31, .len = 1, .val = 1 },
        FieldCase{ .off = 0, .len = 0, .val = 0 },
        FieldCase{ .off = 31, .len = 0, .val = 0 },
        FieldCase{ .off = 0, .len = 8, .val = @intCast(u32, 0xFF) },
        FieldCase{ .off = 8, .len = 8, .val = @intCast(u32, 0xAB) },
        FieldCase{ .off = 24, .len = 8, .val = @intCast(u32, 0x5A) },
        FieldCase{ .off = 4, .len = 4, .val = @intCast(u32, 0xA) },
        FieldCase{ .off = 16, .len = 16, .val = @intCast(u32, 0xBEEF) },
        FieldCase{ .off = 1, .len = 31, .val = @intCast(u32, 0x7FFFFFFF) },
        FieldCase{ .off = 28, .len = 4, .val = @intCast(u32, 0xF) },
        FieldCase{ .off = 8, .len = 6, .val = @intCast(u32, 0x2B) },
        FieldCase{ .off = 0, .len = 16, .val = @intCast(u32, 0x1234) },
        FieldCase{ .off = 16, .len = 16, .val = @intCast(u32, 0xABCD) },
        FieldCase{ .off = 13, .len = 19, .val = @intCast(u32, 0x7FFFF) },
        FieldCase{ .off = 7, .len = 25, .val = @intCast(u32, 0x1FFFFFF) },
        FieldCase{ .off = 0, .len = 24, .val = @intCast(u32, 0xABCDEF) },
        FieldCase{ .off = 8, .len = 24, .val = @intCast(u32, 0xFFFFFF) },
        FieldCase{ .off = 30, .len = 2, .val = @intCast(u32, 0x3) },
        FieldCase{ .off = 1, .len = 1, .val = 1 },
        FieldCase{ .off = 2, .len = 2, .val = @intCast(u32, 0x2) },
        FieldCase{ .off = 5, .len = 27, .val = @intCast(u32, 0x7FFFFFF) },
    };
    var fi: usize = 0;
    while (fi < fields.len) : (fi += 1) {
        var c = fields[fi];
        var fm: u32 = bits.mask(c.len) << c.off;
        var g0 = bits.insert(0, c.val, c.off, c.len);
        ck(bits.extract(g0, c.off, c.len) == c.val, "insert/extract base 0");
        var g1 = bits.insert(ALL32, c.val, c.off, c.len);
        ck(bits.extract(g1, c.off, c.len) == c.val, "insert/extract base all");
        ck((g1 & ~fm) == (ALL32 & ~fm), "preserve outside all-ones base");
        var g2 = bits.insert(PAT, c.val, c.off, c.len);
        ck(bits.extract(g2, c.off, c.len) == c.val, "insert/extract base patterned");
        ck((g2 & ~fm) == (PAT & ~fm), "preserve outside patterned base");
    }

    // --- mask(width) for every width 0..32 ----------------------------------
    var b: u32 = 0;
    var m: u32 = 0;
    while (b < 32) : (b += 1) {
        ck(bits.mask(b) == m, "mask width sweep");
        m = (m << 1) | 1;
    }
    ck(bits.mask(32) == ALL32, "mask width 32");

    // --- rotate inverses over a written (x, n) table ------------------------
    var rots = [_]RotCase{
        RotCase{ .x = @intCast(u32, 0x12345678), .n = 0 },
        RotCase{ .x = @intCast(u32, 0x12345678), .n = 1 },
        RotCase{ .x = @intCast(u32, 0x12345678), .n = 30 },
        RotCase{ .x = @intCast(u32, 0x12345678), .n = 31 },
        RotCase{ .x = @intCast(u32, 0x12345678), .n = 32 },
        RotCase{ .x = @intCast(u32, 0x12345678), .n = 33 },
        RotCase{ .x = ALL32, .n = 7 },
        RotCase{ .x = 0, .n = 17 },
        RotCase{ .x = @intCast(u32, 0x80000001), .n = 1 },
        RotCase{ .x = PAT, .n = 13 },
        RotCase{ .x = 1, .n = 31 },
        RotCase{ .x = @intCast(u32, 0x0000FFFF), .n = 16 },
        RotCase{ .x = @intCast(u32, 0xABCDEF01), .n = 64 },
        RotCase{ .x = @intCast(u32, 0xABCDEF01), .n = 65 },
    };
    var ri: usize = 0;
    while (ri < rots.len) : (ri += 1) {
        var r = rots[ri];
        ck(bits.rotr32(bits.rotl32(r.x, r.n), r.n) == r.x, "rotl/rotr inverse");
        ck(bits.rotl32(bits.rotr32(r.x, r.n), r.n) == r.x, "rotr/rotl inverse");
    }

    // --- explicit width-boundary pins ---------------------------------------
    ck(bits.rotl32(@intCast(u32, 0x12345678), 0) == @intCast(u32, 0x12345678), "rotl n=0");
    ck(bits.rotl32(@intCast(u32, 0x12345678), 31) == bits.rotr32(@intCast(u32, 0x12345678), 1), "rotl n=31");
    ck(bits.rotl32(@intCast(u32, 0x12345678), 32) == @intCast(u32, 0x12345678), "rotl n=32");
    ck(bits.rotl32(@intCast(u32, 0x12345678), 33) == bits.rotl32(@intCast(u32, 0x12345678), 1), "rotl n=33");
    ck(bits.rotr32(@intCast(u32, 0x12345678), 0) == @intCast(u32, 0x12345678), "rotr n=0");
    ck(bits.rotr32(@intCast(u32, 0x12345678), 32) == @intCast(u32, 0x12345678), "rotr n=32");
    ck(bits.rotr32(@intCast(u32, 0x12345678), 33) == bits.rotr32(@intCast(u32, 0x12345678), 1), "rotr n=33");

    ck(std.bits.popcount32(ALL32) == 32, "std.bits re-export");

    if (g_fail == 0) {
        std.io.write("bits stress ok\n");
    } else {
        std.io.write("bits stress FAIL\n");
    }
}
