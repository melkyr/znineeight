// stdlib_crypto_sha256_xmod — STDLIB std_crypto (L5) SHA-256 GREEN fixture.
//
// std_crypto.zig is a PURE (no imports, no allocation) Z98 module; this
// fixture imports it by module basename (the compiler's lib search path binds
// the canonical <exe>/lib std_crypto.zig). It exercises the full SHA-256 API:
// sha256Init / sha256Update / sha256Final.
//
// Contract (blueprint §3 L5): streaming SHA-256, alloc none, errors none.
// Pinned here:
//   - FIPS 180-4 KAT SHA-256("abc")
//   - KAT SHA-256("") (empty input)
//   - FIPS 180-4 KAT SHA-256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
//     (56-byte input: forces a second padded block)
//   - streaming (1-byte and 3-byte chunks) == one-shot, byte-for-byte
//
// GREEN (contract): deterministic byte-exact stdout `crypto sha256 ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic; the final line is
// `crypto sha256 ok` only when g_fail == 0.
const std = @import("std");
const crypto = @import("std_crypto.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn ckBytes(got: []const u8, want: []const u8, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

pub fn main() void {
    var abc: []const u8 = "abc";
    var empty: []const u8 = "";
    var long: []const u8 = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";

    var want_abc = [_]u8{
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad,
    };
    var want_empty = [_]u8{
        0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
        0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
        0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
        0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
    };
    var want_long = [_]u8{
        0x24, 0x8d, 0x6a, 0x61, 0xd2, 0x06, 0x38, 0xb8,
        0xe5, 0xc0, 0x26, 0x93, 0x0c, 0x3e, 0x60, 0x39,
        0xa3, 0x3c, 0xe4, 0x59, 0x64, 0xff, 0x21, 0x67,
        0xf6, 0xec, 0xed, 0xd4, 0x19, 0xdb, 0x06, 0xc1,
    };

    var d: [32]u8 = undefined;

    var s1 = crypto.sha256Init();
    crypto.sha256Update(&s1, abc);
    crypto.sha256Final(&s1, &d);
    ckBytes(d[0..], want_abc[0..], "sha256 abc");

    var s2 = crypto.sha256Init();
    crypto.sha256Update(&s2, empty);
    crypto.sha256Final(&s2, &d);
    ckBytes(d[0..], want_empty[0..], "sha256 empty");

    var s3 = crypto.sha256Init();
    crypto.sha256Update(&s3, long);
    crypto.sha256Final(&s3, &d);
    ckBytes(d[0..], want_long[0..], "sha256 long");

    var s4 = crypto.sha256Init();
    var i: usize = 0;
    while (i < long.len) : (i += 1) {
        crypto.sha256Update(&s4, long[i .. i + 1]);
    }
    var d1: [32]u8 = undefined;
    crypto.sha256Final(&s4, &d1);
    ckBytes(d1[0..], want_long[0..], "sha256 1-byte streaming");

    var s5 = crypto.sha256Init();
    i = 0;
    while (i < long.len) {
        var end: usize = i + 3;
        if (end > long.len) end = long.len;
        crypto.sha256Update(&s5, long[i..end]);
        i = end;
    }
    var d3: [32]u8 = undefined;
    crypto.sha256Final(&s5, &d3);
    ckBytes(d3[0..], want_long[0..], "sha256 3-byte streaming");

    var msg: [200]u8 = undefined;
    var mi: usize = 0;
    while (mi < 200) : (mi += 1) {
        msg[mi] = @intCast(u8, mi % 256);
    }
    var want_mb = [_]u8{
        0x19, 0x01, 0xda, 0x1c, 0x9f, 0x69, 0x9b, 0x48,
        0xf6, 0xb2, 0x63, 0x6e, 0x65, 0xcb, 0xf7, 0x3a,
        0xbf, 0x99, 0xd0, 0x44, 0x1e, 0xf6, 0x7f, 0x5c,
        0x54, 0x0a, 0x42, 0xf7, 0x05, 0x1d, 0xec, 0x6f,
    };
    var s6 = crypto.sha256Init();
    crypto.sha256Update(&s6, msg[0..]);
    crypto.sha256Final(&s6, &d);
    ckBytes(d[0..], want_mb[0..], "sha256 multiblock");

    var s7 = crypto.sha256Init();
    i = 0;
    while (i < 200) {
        var end: usize = i + 7;
        if (end > 200) end = 200;
        crypto.sha256Update(&s7, msg[i..end]);
        i = end;
    }
    var d4: [32]u8 = undefined;
    crypto.sha256Final(&s7, &d4);
    ckBytes(d4[0..], want_mb[0..], "sha256 multiblock streaming");

    if (g_fail == 0) {
        std.io.write("crypto sha256 ok\n");
    } else {
        std.io.write("crypto sha256 FAIL\n");
    }
}
