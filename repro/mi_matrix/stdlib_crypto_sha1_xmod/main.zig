// stdlib_crypto_sha1_xmod — STDLIB std_crypto (L5) SHA-1 GREEN fixture.
//
// std_crypto.zig is a PURE (no imports, no allocation) Z98 module; this
// fixture imports it by module basename (the compiler's lib search path binds
// the canonical <exe>/lib std_crypto.zig). It exercises the full SHA-1 API:
// sha1Init / sha1Update / sha1Final.
//
// Contract (blueprint §3 L5): streaming SHA-1, alloc none, errors none.
// Pinned here:
//   - RFC 3174 KAT SHA-1("abc")
//   - KAT SHA-1("") (empty input)
//   - RFC 3174 KAT SHA-1("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
//     (56-byte input: forces a second padded block)
//   - streaming (1-byte and 3-byte chunks) == one-shot, byte-for-byte
//
// GREEN (contract): deterministic byte-exact stdout `crypto sha1 ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic; the final line is
// `crypto sha1 ok` only when g_fail == 0.
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
        0xa9, 0x99, 0x3e, 0x36, 0x47, 0x06, 0x81, 0x6a, 0xba, 0x3e,
        0x25, 0x71, 0x78, 0x50, 0xc2, 0x6c, 0x9c, 0xd0, 0xd8, 0x9d,
    };
    var want_empty = [_]u8{
        0xda, 0x39, 0xa3, 0xee, 0x5e, 0x6b, 0x4b, 0x0d, 0x32, 0x55,
        0xbf, 0xef, 0x95, 0x60, 0x18, 0x90, 0xaf, 0xd8, 0x07, 0x09,
    };
    var want_long = [_]u8{
        0x84, 0x98, 0x3e, 0x44, 0x1c, 0x3b, 0xd2, 0x6e, 0xba, 0xae,
        0x4a, 0xa1, 0xf9, 0x51, 0x29, 0xe5, 0xe5, 0x46, 0x70, 0xf1,
    };

    var d: [20]u8 = undefined;

    var s1 = crypto.sha1Init();
    crypto.sha1Update(&s1, abc);
    crypto.sha1Final(&s1, &d);
    ckBytes(d[0..], want_abc[0..], "sha1 abc");

    var s2 = crypto.sha1Init();
    crypto.sha1Update(&s2, empty);
    crypto.sha1Final(&s2, &d);
    ckBytes(d[0..], want_empty[0..], "sha1 empty");

    var s3 = crypto.sha1Init();
    crypto.sha1Update(&s3, long);
    crypto.sha1Final(&s3, &d);
    ckBytes(d[0..], want_long[0..], "sha1 long");

    var s4 = crypto.sha1Init();
    var i: usize = 0;
    while (i < long.len) : (i += 1) {
        crypto.sha1Update(&s4, long[i .. i + 1]);
    }
    var d1: [20]u8 = undefined;
    crypto.sha1Final(&s4, &d1);
    ckBytes(d1[0..], want_long[0..], "sha1 1-byte streaming");

    var s5 = crypto.sha1Init();
    i = 0;
    while (i < long.len) {
        var end: usize = i + 3;
        if (end > long.len) end = long.len;
        crypto.sha1Update(&s5, long[i..end]);
        i = end;
    }
    var d3: [20]u8 = undefined;
    crypto.sha1Final(&s5, &d3);
    ckBytes(d3[0..], want_long[0..], "sha1 3-byte streaming");

    var msg: [200]u8 = undefined;
    var mi: usize = 0;
    while (mi < 200) : (mi += 1) {
        msg[mi] = @intCast(u8, mi % 256);
    }
    var want_mb = [_]u8{
        0x54, 0xd1, 0x1e, 0x99, 0x12, 0x7d, 0x15, 0x97, 0x99, 0xdb,
        0xce, 0x10, 0xf5, 0x1a, 0x75, 0xe6, 0x97, 0x78, 0x04, 0x78,
    };
    var s6 = crypto.sha1Init();
    crypto.sha1Update(&s6, msg[0..]);
    crypto.sha1Final(&s6, &d);
    ckBytes(d[0..], want_mb[0..], "sha1 multiblock");

    var s7 = crypto.sha1Init();
    i = 0;
    while (i < 200) {
        var end: usize = i + 7;
        if (end > 200) end = 200;
        crypto.sha1Update(&s7, msg[i..end]);
        i = end;
    }
    var d4: [20]u8 = undefined;
    crypto.sha1Final(&s7, &d4);
    ckBytes(d4[0..], want_mb[0..], "sha1 multiblock streaming");

    if (g_fail == 0) {
        std.io.write("crypto sha1 ok\n");
    } else {
        std.io.write("crypto sha1 FAIL\n");
    }
}
