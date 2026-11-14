// stdlib_utf8_invalid_xmod — STDLIB std_utf8 (L5) invalid-sequence
// expected-failure probe (Plan C hardening Task 3).
//
// Contract (sf/src/std_utf8.zig:14-35,45-90): `decode` returns the first code
// point only if `s` begins with valid RFC 3629 UTF-8; otherwise it returns
// `null`. A sequence is invalid when a continuation byte is outside
// 0x80..0xBF, when it is overlong (2-byte < 0x80, 3-byte < 0x800, 4-byte
// < 0x10000), when it is a UTF-16 surrogate (U+D800..U+DFFF), when it exceeds
// U+10FFFF, or when the lead byte can never begin a sequence (0x80..0xBF, 0xC0,
// 0xC1, 0xF5..0xFF). `codepointLen` returns 0 for exactly those impossible
// leads.
//
// This probe drives the documented rejection paths: each invalid input MUST
// yield `null` and each impossible lead MUST yield `codepointLen == 0`. A
// decode that yields a value (or `codepointLen` a nonzero length) FAILS the
// probe. The failure is reported in-process, so the process exits cleanly
// (rc 0) on the expected path.
//
// GREEN (contract): deterministic byte-exact stdout `utf8 invalid ok\n` (rc 0).
const std = @import("std");
const utf8 = @import("std_utf8.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn decNull(s: []const u8, what: []const u8) void {
    ck(utf8.decode(s) == null, what);
}

fn lenZero(b: u8, what: []const u8) void {
    ck(utf8.codepointLen(b) == 0, what);
}

pub fn main() void {
    var empty: []const u8 = "";
    decNull(empty, "empty");

    // Invalid continuation bytes (all three widths).
    var bad2: [2]u8 = [_]u8{ 0xC3, 0x41 };
    decNull(bad2[0..], "bad continuation 2-byte");
    var bad2c: [2]u8 = [_]u8{ 0xC2, 0x7F };
    decNull(bad2c[0..], "continuation below 0x80");
    var bad3: [3]u8 = [_]u8{ 0xE2, 0x82, 0x41 };
    decNull(bad3[0..], "bad continuation 3-byte");
    var bad4: [4]u8 = [_]u8{ 0xF0, 0x9F, 0x98, 0x41 };
    decNull(bad4[0..], "bad continuation 4-byte");

    // Overlong encodings (2/3/4-byte).
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

    // Surrogates and above U+10FFFF.
    var sur_hi: [3]u8 = [_]u8{ 0xED, 0xA0, 0x80 };
    decNull(sur_hi[0..], "surrogate U+D800");
    var sur_lo: [3]u8 = [_]u8{ 0xED, 0xBF, 0xBF };
    decNull(sur_lo[0..], "surrogate U+DFFF");
    var big: [4]u8 = [_]u8{ 0xF4, 0x90, 0x80, 0x80 };
    decNull(big[0..], "U+110000");

    // Truncated sequences.
    var trunc2: [1]u8 = [_]u8{0xC3};
    decNull(trunc2[0..], "truncated 2-byte");
    var trunc3: [2]u8 = [_]u8{ 0xE2, 0x82 };
    decNull(trunc3[0..], "truncated 3-byte");
    var trunc4: [3]u8 = [_]u8{ 0xF0, 0x9F, 0x98 };
    decNull(trunc4[0..], "truncated 4-byte");

    // Impossible lead bytes: codepointLen == 0 and decode == null.
    lenZero(0x80, "lead 80 len0");
    lenZero(0xBF, "lead BF len0");
    lenZero(0xC0, "lead C0 len0");
    lenZero(0xC1, "lead C1 len0");
    lenZero(0xF5, "lead F5 len0");
    lenZero(0xFE, "lead FE len0");
    lenZero(0xFF, "lead FF len0");

    var lead80: [2]u8 = [_]u8{ 0x80, 0x80 };
    decNull(lead80[0..], "continuation lead");
    var leadc0: [2]u8 = [_]u8{ 0xC0, 0x80 };
    decNull(leadc0[0..], "lead C0 decode");
    var leadf5: [4]u8 = [_]u8{ 0xF5, 0x80, 0x80, 0x80 };
    decNull(leadf5[0..], "lead F5 decode");
    var leadfe: [1]u8 = [_]u8{0xFE};
    decNull(leadfe[0..], "lead FE decode");
    var leadff: [1]u8 = [_]u8{0xFF};
    decNull(leadff[0..], "lead FF decode");

    if (g_fail == 0) {
        std.io.write("utf8 invalid ok\n");
    } else {
        std.io.write("utf8 invalid FAIL\n");
    }
}
