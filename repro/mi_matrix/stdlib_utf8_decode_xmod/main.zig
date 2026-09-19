// stdlib_utf8_decode_xmod — STDLIB std_utf8 (L5) decode GREEN fixture.
//
// std_utf8.zig is a pure L5 module: no imports, no allocation, no error set
// (contract: alloc none | errors none | coroutine no; R1). This fixture imports
// it by module basename (the compiler's lib search path binds
// <exe>/lib/std_utf8.zig).
//
// decode(s) decodes the FIRST code point of `s` and returns
//   Codepoint{ .cp = <scalar value>, .len = <bytes consumed 1..4> }
// or null when `s` is empty or does not begin with a valid UTF-8 sequence.
//
// VALIDATION POLICY (pinned here; RFC 3629):
//   * a truncated sequence (fewer bytes than the lead promises) -> null;
//   * any continuation byte outside 0x80..0xBF -> null;
//   * an overlong encoding (cp below the lead's minimum: <0x80 for 2-byte,
//     <0x800 for 3-byte, <0x10000 for 4-byte) -> null;
//   * a UTF-16 surrogate U+D800..U+DFFF -> null;
//   * a scalar above U+10FFFF -> null;
//   * lead bytes 0x80..0xBF, 0xC0, 0xC1, 0xF5..0xFF -> null.
// Only the first code point is examined; trailing bytes are ignored.
//
// Cases: every 1/2/3/4-byte boundary (U+0000, U+007F, U+0080, U+07FF,
// U+0800, U+D7FF, U+E000, U+FFFF, U+10000, U+10FFFF, U+1F600, U+20AC);
// first-of-many; empty; truncated; bad continuation; overlong (2/3/4);
// surrogate hi/lo; >U+10FFFF; invalid lead bytes.
//
// GREEN (contract): deterministic byte-exact stdout `utf8 decode ok\n`
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

fn decIs(s: []const u8, want_cp: u32, want_len: u8, what: []const u8) void {
    var got = utf8.decode(s);
    if (got) |c| {
        ck(c.cp == want_cp, what);
        ck(c.len == want_len, what);
    } else {
        ck(false, what);
    }
}

fn decNull(s: []const u8, what: []const u8) void {
    var got = utf8.decode(s);
    ck(got == null, what);
}

pub fn main() void {
    // Empty input.
    var empty: []const u8 = "";
    decNull(empty, "empty");

    // 1-byte boundaries.
    var b_nul: [1]u8 = [_]u8{0x00};
    decIs(b_nul[0..], 0x00, 1, "U+0000");
    decIs("A", 0x41, 1, "U+0041");
    var b_7f: [1]u8 = [_]u8{0x7F};
    decIs(b_7f[0..], 0x7F, 1, "U+007F");

    // 2-byte boundaries.
    var b_80: [2]u8 = [_]u8{ 0xC2, 0x80 };
    decIs(b_80[0..], 0x80, 2, "U+0080");
    var b_e9: [2]u8 = [_]u8{ 0xC3, 0xA9 };
    decIs(b_e9[0..], 0xE9, 2, "U+00E9");
    var b_7ff: [2]u8 = [_]u8{ 0xDF, 0xBF };
    decIs(b_7ff[0..], 0x7FF, 2, "U+07FF");

    // 3-byte boundaries.
    var b_800: [3]u8 = [_]u8{ 0xE0, 0xA0, 0x80 };
    decIs(b_800[0..], 0x800, 3, "U+0800");
    var b_20ac: [3]u8 = [_]u8{ 0xE2, 0x82, 0xAC };
    decIs(b_20ac[0..], 0x20AC, 3, "U+20AC");
    var b_d7ff: [3]u8 = [_]u8{ 0xED, 0x9F, 0xBF };
    decIs(b_d7ff[0..], 0xD7FF, 3, "U+D7FF");
    var b_e000: [3]u8 = [_]u8{ 0xEE, 0x80, 0x80 };
    decIs(b_e000[0..], 0xE000, 3, "U+E000");
    var b_fffd: [3]u8 = [_]u8{ 0xEF, 0xBF, 0xBD };
    decIs(b_fffd[0..], 0xFFFD, 3, "U+FFFD");
    var b_ffff: [3]u8 = [_]u8{ 0xEF, 0xBF, 0xBF };
    decIs(b_ffff[0..], 0xFFFF, 3, "U+FFFF");

    // 4-byte boundaries.
    var b_10000: [4]u8 = [_]u8{ 0xF0, 0x90, 0x80, 0x80 };
    decIs(b_10000[0..], 0x10000, 4, "U+10000");
    var b_1f600: [4]u8 = [_]u8{ 0xF0, 0x9F, 0x98, 0x80 };
    decIs(b_1f600[0..], 0x1F600, 4, "U+1F600");
    var b_10ffff: [4]u8 = [_]u8{ 0xF4, 0x8F, 0xBF, 0xBF };
    decIs(b_10ffff[0..], 0x10FFFF, 4, "U+10FFFF");

    // Only the first code point is decoded; trailing bytes are ignored.
    decIs("AB", 0x41, 1, "first of AB");
    var b_e9_trail: [3]u8 = [_]u8{ 0xC3, 0xA9, 0x41 };
    decIs(b_e9_trail[0..], 0xE9, 2, "first of e-acute A");

    // Truncated sequences.
    decNull(b_e9[0..1], "truncated 2-byte");
    decNull(b_800[0..2], "truncated 3-byte");
    decNull(b_10000[0..3], "truncated 4-byte");

    // Bad continuation bytes.
    var bad2: [2]u8 = [_]u8{ 0xC3, 0x41 };
    decNull(bad2[0..], "bad continuation 2-byte");
    var bad3: [3]u8 = [_]u8{ 0xE2, 0x82, 0x41 };
    decNull(bad3[0..], "bad continuation 3-byte");
    var bad4: [4]u8 = [_]u8{ 0xF0, 0x9F, 0x98, 0x41 };
    decNull(bad4[0..], "bad continuation 4-byte");

    // Overlong encodings.
    var ol2a: [2]u8 = [_]u8{ 0xC0, 0x80 };
    decNull(ol2a[0..], "overlong 2-byte C0 80");
    var ol2b: [2]u8 = [_]u8{ 0xC1, 0xBF };
    decNull(ol2b[0..], "overlong 2-byte C1 BF");
    var ol3a: [3]u8 = [_]u8{ 0xE0, 0x80, 0x80 };
    decNull(ol3a[0..], "overlong 3-byte E0 80 80");
    var ol3b: [3]u8 = [_]u8{ 0xE0, 0x9F, 0xBF };
    decNull(ol3b[0..], "overlong 3-byte E0 9F BF");
    var ol4a: [4]u8 = [_]u8{ 0xF0, 0x80, 0x80, 0x80 };
    decNull(ol4a[0..], "overlong 4-byte F0 80 80 80");
    var ol4b: [4]u8 = [_]u8{ 0xF0, 0x8F, 0xBF, 0xBF };
    decNull(ol4b[0..], "overlong 4-byte F0 8F BF BF");

    // Surrogates.
    var sur_hi: [3]u8 = [_]u8{ 0xED, 0xA0, 0x80 };
    decNull(sur_hi[0..], "surrogate U+D800");
    var sur_lo: [3]u8 = [_]u8{ 0xED, 0xBF, 0xBF };
    decNull(sur_lo[0..], "surrogate U+DFFF");

    // Above U+10FFFF.
    var big_a: [4]u8 = [_]u8{ 0xF4, 0x90, 0x80, 0x80 };
    decNull(big_a[0..], "U+110000");
    var big_b: [4]u8 = [_]u8{ 0xF5, 0x80, 0x80, 0x80 };
    decNull(big_b[0..], "lead F5");

    // Invalid lead bytes.
    var cont_first: [2]u8 = [_]u8{ 0x80, 0x80 };
    decNull(cont_first[0..], "continuation lead");
    var lead_fe: [1]u8 = [_]u8{0xFE};
    decNull(lead_fe[0..], "lead FE");
    var lead_ff: [1]u8 = [_]u8{0xFF};
    decNull(lead_ff[0..], "lead FF");

    if (g_fail == 0) {
        std.io.write("utf8 decode ok\n");
    } else {
        std.io.write("utf8 decode FAIL\n");
    }
}
