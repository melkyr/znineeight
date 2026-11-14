// stdlib_utf8_codepointlen_xmod — STDLIB std_utf8 (L5) codepointLen GREEN fixture.
//
// std_utf8.zig is a pure L5 module: no imports, no allocation, no error set
// (contract: alloc none | errors none | coroutine no; R1). This fixture imports
// it by module basename (the compiler's lib search path binds
// <exe>/lib/std_utf8.zig).
//
// codepointLen(first_byte) returns the length (1..4) of the UTF-8 sequence
// whose lead byte is `first_byte`, or 0 when the byte can never begin a valid
// sequence. Pinned policy (RFC 3629 lead-byte ranges):
//   0x00..0x7F -> 1
//   0xC2..0xDF -> 2   (0xC0/0xC1 are overlong -> 0)
//   0xE0..0xEF -> 3
//   0xF0..0xF4 -> 4   (0xF5..0xFF exceed U+10FFFF -> 0)
//   0x80..0xBF (continuation), 0xC0, 0xC1, 0xF5..0xFF -> 0
// The function is total and consults only the lead byte; the decode-time
// constraints on the SECOND byte (overlong E0/F0, surrogate ED, >U+10FFFF F4)
// are enforced by `decode`, not here.
//
// Cases: every one of the 256 byte values against an in-fixture reference
// (exhaustive), plus explicit boundary bytes.
//
// GREEN (contract): deterministic byte-exact stdout `utf8 codepointLen ok\n`
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

// Independent reference for the lead-byte length policy.
fn refLen(b: u8) u8 {
    if (b < 0x80) return 1;
    if (b >= 0xC2 and b <= 0xDF) return 2;
    if (b >= 0xE0 and b <= 0xEF) return 3;
    if (b >= 0xF0 and b <= 0xF4) return 4;
    return 0;
}

pub fn main() void {
    // Exhaustive: all 256 lead bytes.
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        var b: u8 = @intCast(u8, i);
        ck(utf8.codepointLen(b) == refLen(b), "codepointLen all256");
    }

    ck(utf8.codepointLen(0x00) == 1, "nul len 1");
    ck(utf8.codepointLen(0x41) == 1, "A len 1");
    ck(utf8.codepointLen(0x7F) == 1, "0x7F len 1");
    ck(utf8.codepointLen(0x80) == 0, "continuation 0x80 len 0");
    ck(utf8.codepointLen(0xBF) == 0, "continuation 0xBF len 0");
    ck(utf8.codepointLen(0xC0) == 0, "overlong C0 len 0");
    ck(utf8.codepointLen(0xC1) == 0, "overlong C1 len 0");
    ck(utf8.codepointLen(0xC2) == 2, "C2 len 2");
    ck(utf8.codepointLen(0xDF) == 2, "DF len 2");
    ck(utf8.codepointLen(0xE0) == 3, "E0 len 3");
    ck(utf8.codepointLen(0xEF) == 3, "EF len 3");
    ck(utf8.codepointLen(0xF0) == 4, "F0 len 4");
    ck(utf8.codepointLen(0xF4) == 4, "F4 len 4");
    ck(utf8.codepointLen(0xF5) == 0, "F5 len 0");
    ck(utf8.codepointLen(0xFE) == 0, "FE len 0");
    ck(utf8.codepointLen(0xFF) == 0, "FF len 0");

    if (g_fail == 0) {
        std.io.write("utf8 codepointLen ok\n");
    } else {
        std.io.write("utf8 codepointLen FAIL\n");
    }
}
