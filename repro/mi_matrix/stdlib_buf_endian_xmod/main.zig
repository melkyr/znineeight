// stdlib_buf_endian_xmod — STDLIB std_buf (L2) endian-aware append GREEN fixture.
//
// Contract (blueprint §3 L2): the append*BE/append*LE families write big- and
// little-endian encodings of u16/u32/u64. This fixture pins the exact byte
// order for all six functions and verifies each BE/LE pair of the same value
// is a byte-reverse (the round-trip property).
//
// GREEN (contract): deterministic byte-exact stdout `buf endian ok\n` (RUNRC=0).
const std = @import("std");
const buf = @import("std_buf.zig");

var g_backing: [128]u8 = undefined;
var g_arena = std.arena.init(g_backing[0..]);
var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    var b = std.buf.init(&g_arena);

    std.buf.appendU16BE(&b, @intCast(u16, 0x1234)) catch {
        g_fail += 1;
    };
    std.buf.appendU16LE(&b, @intCast(u16, 0x1234)) catch {
        g_fail += 1;
    };
    std.buf.appendU32BE(&b, @intCast(u32, 0x12345678)) catch {
        g_fail += 1;
    };
    std.buf.appendU32LE(&b, @intCast(u32, 0x12345678)) catch {
        g_fail += 1;
    };
    std.buf.appendU64BE(&b, @intCast(u64, 0x0102030405060708)) catch {
        g_fail += 1;
    };
    std.buf.appendU64LE(&b, @intCast(u64, 0x0102030405060708)) catch {
        g_fail += 1;
    };

    var want: [28]u8 = [_]u8{
        0x12, 0x34, // u16 BE
        0x34, 0x12, // u16 LE
        0x12, 0x34, 0x56, 0x78, // u32 BE
        0x78, 0x56, 0x34, 0x12, // u32 LE
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, // u64 BE
        0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01, // u64 LE
    };

    var s = std.buf.slice(&b);
    ck(s.len == 28, "endian total length");
    var i: usize = 0;
    while (i < want.len) : (i += 1) {
        ck(s[i] == want[i], "endian byte order");
    }

    // Round-trip: BE and LE encodings of the same value are byte-reverses.
    ck(s[0] == s[3] and s[1] == s[2], "u16 BE/LE reverse");
    ck(s[4] == s[11] and s[5] == s[10] and s[6] == s[9] and s[7] == s[8], "u32 BE/LE reverse");
    ck(s[12] == s[27] and s[13] == s[26] and s[14] == s[25] and s[15] == s[24], "u64 BE/LE reverse low");
    ck(s[16] == s[23] and s[17] == s[22] and s[18] == s[21] and s[19] == s[20], "u64 BE/LE reverse high");

    // std.buf re-export smoke check.
    std.buf.appendByte(&b, 0xAA) catch {
        g_fail += 1;
    };
    ck(std.buf.slice(&b).len == 29, "std.buf re-export appendByte");

    if (g_fail == 0) {
        std.io.write("buf endian ok\n");
    } else {
        std.io.write("buf endian FAIL\n");
    }
}
