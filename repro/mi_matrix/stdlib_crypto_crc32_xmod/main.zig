// stdlib_crypto_crc32_xmod — STDLIB std_crypto (L5) CRC-32 GREEN fixture.
//
// std_crypto.zig is a PURE (no imports, no allocation) Z98 module; this
// fixture imports it by module basename (the compiler's lib search path binds
// the canonical <exe>/lib std_crypto.zig). It exercises the full CRC-32 API:
// crc32Init / crc32Update / crc32Final.
//
// Contract (blueprint §3 L5): streaming CRC-32 (IEEE 802.3 reflected
// polynomial, init 0xFFFFFFFF, final XOR 0xFFFFFFFF), alloc none, errors none.
// Pinned here:
//   - IEEE 802.3 KAT CRC-32("123456789") == 0xCBF43926
//   - CRC-32("") == 0x00000000 (empty input)
//   - streaming (1-byte and 3-byte chunks) == one-shot, byte-for-byte
//
// GREEN (contract): deterministic byte-exact stdout `crypto crc32 ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic; the final line is
// `crypto crc32 ok` only when g_fail == 0.
const std = @import("std");
const crypto = @import("std_crypto.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    var check: []const u8 = "123456789";
    var empty: []const u8 = "";

    var want_check: u32 = 0xCBF43926;
    var want_empty: u32 = 0x00000000;

    var c1 = crypto.crc32Init();
    c1 = crypto.crc32Update(c1, check);
    c1 = crypto.crc32Final(c1);
    ck(c1 == want_check, "crc32 123456789");

    var c2 = crypto.crc32Init();
    c2 = crypto.crc32Update(c2, empty);
    c2 = crypto.crc32Final(c2);
    ck(c2 == want_empty, "crc32 empty");

    var c3 = crypto.crc32Init();
    var i: usize = 0;
    while (i < check.len) : (i += 1) {
        c3 = crypto.crc32Update(c3, check[i .. i + 1]);
    }
    c3 = crypto.crc32Final(c3);
    ck(c3 == want_check, "crc32 1-byte streaming");

    var c4 = crypto.crc32Init();
    i = 0;
    while (i < check.len) {
        var end: usize = i + 3;
        if (end > check.len) end = check.len;
        c4 = crypto.crc32Update(c4, check[i..end]);
        i = end;
    }
    c4 = crypto.crc32Final(c4);
    ck(c4 == want_check, "crc32 3-byte streaming");

    var msg: [200]u8 = undefined;
    var mi: usize = 0;
    while (mi < 200) : (mi += 1) {
        msg[mi] = @intCast(u8, mi % 256);
    }
    var want_mb: u32 = 0xED086180;
    var c5 = crypto.crc32Init();
    c5 = crypto.crc32Update(c5, msg[0..]);
    c5 = crypto.crc32Final(c5);
    ck(c5 == want_mb, "crc32 multiblock");

    var c6 = crypto.crc32Init();
    i = 0;
    while (i < 200) {
        var end: usize = i + 7;
        if (end > 200) end = 200;
        c6 = crypto.crc32Update(c6, msg[i..end]);
        i = end;
    }
    c6 = crypto.crc32Final(c6);
    ck(c6 == want_mb, "crc32 multiblock streaming");

    if (g_fail == 0) {
        std.io.write("crypto crc32 ok\n");
    } else {
        std.io.write("crypto crc32 FAIL\n");
    }
}
