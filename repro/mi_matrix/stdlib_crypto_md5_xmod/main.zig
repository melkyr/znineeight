// stdlib_crypto_md5_xmod — STDLIB std_crypto (L5) MD5 GREEN fixture.
//
// std_crypto.zig is a PURE (no imports, no allocation) Z98 module; this
// fixture imports it by module basename (the compiler's lib search path binds
// the canonical <exe>/lib std_crypto.zig). It exercises the full MD5 API:
// md5Init / md5Update / md5Final.
//
// Contract (blueprint §3 L5): streaming MD5, alloc none, errors none.
// Pinned here:
//   - RFC 1321 KAT MD5("abc")
//   - KAT MD5("") (empty input)
//   - RFC 1321 KAT MD5("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
//     (56-byte input: forces a second padded block)
//   - streaming (1-byte and 3-byte chunks) == one-shot, byte-for-byte
//
// GREEN (contract): deterministic byte-exact stdout `crypto md5 ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic; the final line is
// `crypto md5 ok` only when g_fail == 0.
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
        0x90, 0x01, 0x50, 0x98, 0x3c, 0xd2, 0x4f, 0xb0,
        0xd6, 0x96, 0x3f, 0x7d, 0x28, 0xe1, 0x7f, 0x72,
    };
    var want_empty = [_]u8{
        0xd4, 0x1d, 0x8c, 0xd9, 0x8f, 0x00, 0xb2, 0x04,
        0xe9, 0x80, 0x09, 0x98, 0xec, 0xf8, 0x42, 0x7e,
    };
    var want_long = [_]u8{
        0x82, 0x15, 0xef, 0x07, 0x96, 0xa2, 0x0b, 0xca,
        0xaa, 0xe1, 0x16, 0xd3, 0x87, 0x6c, 0x66, 0x4a,
    };

    var d: [16]u8 = undefined;

    var s1 = crypto.md5Init();
    crypto.md5Update(&s1, abc);
    crypto.md5Final(&s1, &d);
    ckBytes(d[0..], want_abc[0..], "md5 abc");

    var s2 = crypto.md5Init();
    crypto.md5Update(&s2, empty);
    crypto.md5Final(&s2, &d);
    ckBytes(d[0..], want_empty[0..], "md5 empty");

    var s3 = crypto.md5Init();
    crypto.md5Update(&s3, long);
    crypto.md5Final(&s3, &d);
    ckBytes(d[0..], want_long[0..], "md5 long");

    var s4 = crypto.md5Init();
    var i: usize = 0;
    while (i < long.len) : (i += 1) {
        crypto.md5Update(&s4, long[i .. i + 1]);
    }
    var d1: [16]u8 = undefined;
    crypto.md5Final(&s4, &d1);
    ckBytes(d1[0..], want_long[0..], "md5 1-byte streaming");

    var s5 = crypto.md5Init();
    i = 0;
    while (i < long.len) {
        var end: usize = i + 3;
        if (end > long.len) end = long.len;
        crypto.md5Update(&s5, long[i..end]);
        i = end;
    }
    var d3: [16]u8 = undefined;
    crypto.md5Final(&s5, &d3);
    ckBytes(d3[0..], want_long[0..], "md5 3-byte streaming");

    var msg: [200]u8 = undefined;
    var mi: usize = 0;
    while (mi < 200) : (mi += 1) {
        msg[mi] = @intCast(u8, mi % 256);
    }
    var want_mb = [_]u8{
        0xfb, 0x70, 0x01, 0xd3, 0x4b, 0x8e, 0x82, 0xc9,
        0xb5, 0x79, 0xbe, 0x50, 0x05, 0xd5, 0xb0, 0xa5,
    };
    var s6 = crypto.md5Init();
    crypto.md5Update(&s6, msg[0..]);
    crypto.md5Final(&s6, &d);
    ckBytes(d[0..], want_mb[0..], "md5 multiblock");

    var s7 = crypto.md5Init();
    i = 0;
    while (i < 200) {
        var end: usize = i + 7;
        if (end > 200) end = 200;
        crypto.md5Update(&s7, msg[i..end]);
        i = end;
    }
    var d4: [16]u8 = undefined;
    crypto.md5Final(&s7, &d4);
    ckBytes(d4[0..], want_mb[0..], "md5 multiblock streaming");

    if (g_fail == 0) {
        std.io.write("crypto md5 ok\n");
    } else {
        std.io.write("crypto md5 FAIL\n");
    }
}
