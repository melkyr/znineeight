// stdlib_utf8_countcodepoints_xmod — STDLIB std_utf8 (L5) countCodepoints
// GREEN fixture.
//
// std_utf8.zig is a pure L5 module: no imports, no allocation, no error set
// (contract: alloc none | errors none | coroutine no; R1). This fixture imports
// it by module basename (the compiler's lib search path binds
// <exe>/lib/std_utf8.zig).
//
// countCodepoints(s) is total: it walks `s` and counts code points. For each
// position it decodes one code point with `decode`; a valid code point
// contributes 1 and advances by its byte length, while a byte that begins an
// invalid sequence contributes 1 and advances by exactly one byte (so the walk
// always terminates and no byte is skipped). Consequently a string that is not
// valid UTF-8 still yields a deterministic count; an empty string yields 0.
//
// Cases: empty; ASCII; 1/2/3/4-byte code points; mixed scripts; every one of
// the 256 byte values (each counts 1); invalid leads/continuations; truncated;
// overlong; surrogate; >U+10FFFF; a repeated multi-byte string.
//
// GREEN (contract): deterministic byte-exact stdout `utf8 countCodepoints ok\n`
// (RUNRC=0).
const std = @import("std");
const utf8 = @import("std_utf8.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn cntIs(s: []const u8, want: usize, what: []const u8) void {
    ck(utf8.countCodepoints(s) == want, what);
}

pub fn main() void {
    // Empty and ASCII.
    var empty: []const u8 = "";
    cntIs(empty, 0, "empty");
    cntIs("A", 1, "A");
    cntIs("AB", 2, "AB");
    cntIs("abc", 3, "abc");
    cntIs("hello", 5, "hello");

    // Single multi-byte code points.
    var b_e9: [2]u8 = [_]u8{ 0xC3, 0xA9 };
    cntIs(b_e9[0..], 1, "e-acute");
    var b_20ac: [3]u8 = [_]u8{ 0xE2, 0x82, 0xAC };
    cntIs(b_20ac[0..], 1, "euro");
    var b_1f600: [4]u8 = [_]u8{ 0xF0, 0x9F, 0x98, 0x80 };
    cntIs(b_1f600[0..], 1, "emoji");
    var b_10ffff: [4]u8 = [_]u8{ 0xF4, 0x8F, 0xBF, 0xBF };
    cntIs(b_10ffff[0..], 1, "U+10FFFF");

    // Mixed 1/2/3/4-byte: a, euro, emoji, e-acute -> 4 code points.
    var mixed: [10]u8 = [_]u8{ 0x61, 0xE2, 0x82, 0xAC, 0xF0, 0x9F, 0x98, 0x80, 0xC3, 0xA9 };
    cntIs(mixed[0..], 4, "mixed 4");

    // e-acute + A -> 2 code points.
    var e9a: [3]u8 = [_]u8{ 0xC3, 0xA9, 0x41 };
    cntIs(e9a[0..], 2, "e-acute A");

    // a + e-acute -> 2 code points.
    var ae9: [3]u8 = [_]u8{ 0x61, 0xC3, 0xA9 };
    cntIs(ae9[0..], 2, "a e-acute");

    // All 256 byte values: each byte counts exactly 1 (ASCII valid, 0x80..0xFF
    // invalid and advanced one at a time).
    var all: [256]u8 = undefined;
    var i: usize = 0;
    while (i < all.len) : (i += 1) {
        all[i] = @intCast(u8, i);
    }
    cntIs(all[0..], 256, "all256");

    // Invalid inputs: one unit per starting byte.
    var ff1: [1]u8 = [_]u8{0xFF};
    cntIs(ff1[0..], 1, "single FF");
    var bad2: [2]u8 = [_]u8{ 0xC3, 0x41 };
    cntIs(bad2[0..], 2, "bad continuation");
    var a_ff_b: [3]u8 = [_]u8{ 0x61, 0xFF, 0x62 };
    cntIs(a_ff_b[0..], 3, "a FF b");
    var ol2: [2]u8 = [_]u8{ 0xC0, 0x80 };
    cntIs(ol2[0..], 2, "overlong 2-byte");
    var sur: [3]u8 = [_]u8{ 0xED, 0xA0, 0x80 };
    cntIs(sur[0..], 3, "surrogate");
    var big: [4]u8 = [_]u8{ 0xF4, 0x90, 0x80, 0x80 };
    cntIs(big[0..], 4, "U+110000");
    var trunc: [1]u8 = [_]u8{0xC3};
    cntIs(trunc[0..], 1, "truncated");

    // Repeated 2-byte code point: 4 x e-acute = 8 bytes -> 4 code points.
    var rep: [8]u8 = [_]u8{ 0xC3, 0xA9, 0xC3, 0xA9, 0xC3, 0xA9, 0xC3, 0xA9 };
    cntIs(rep[0..], 4, "four e-acute");

    if (g_fail == 0) {
        std.io.write("utf8 countCodepoints ok\n");
    } else {
        std.io.write("utf8 countCodepoints FAIL\n");
    }
}
