// stdlib_base64_decodedlen_xmod — STDLIB std_base64 (L5) decodedLen GREEN fixture.
//
// std_base64.zig is an L5 module; decodedLen is a pure size helper that
// allocates nothing (R1). This fixture imports it by module basename.
//
// Contract pinned: decodedLen(n) is the MAXIMUM number of decoded bytes for an
// n-character base64 string, i.e. (n / 4) * 3. It is an upper bound because the
// exact decoded length depends on trailing '=' padding, which a length alone
// cannot reveal (a canonical 4-char quad may decode to 3, 2, or 1 bytes). The
// bound is exact whenever the input carries no padding and is always >= the
// true decoded length. This matches the Zig standard library's decoder sizing
// convention (calcSizeForSlice). For canonical padded input the exact length is
// (n / 4) * 3 - pad, where pad is 0, 1, or 2.
//
// GREEN (contract): deterministic byte-exact stdout `base64 decodedLen ok\n`
// (RUNRC=0).
const std = @import("std");
const b64 = @import("std_base64.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    ck(b64.decodedLen(0) == 0, "n0");
    ck(b64.decodedLen(1) == 0, "n1");
    ck(b64.decodedLen(2) == 0, "n2");
    ck(b64.decodedLen(3) == 0, "n3");
    ck(b64.decodedLen(4) == 3, "n4");
    ck(b64.decodedLen(5) == 3, "n5");
    ck(b64.decodedLen(6) == 3, "n6");
    ck(b64.decodedLen(7) == 3, "n7");
    ck(b64.decodedLen(8) == 6, "n8");
    ck(b64.decodedLen(9) == 6, "n9");
    ck(b64.decodedLen(12) == 9, "n12");
    ck(b64.decodedLen(100) == 75, "n100");
    ck(b64.decodedLen(344) == 258, "n344");

    var n: usize = 0;
    while (n <= 512) : (n += 1) {
        ck(b64.decodedLen(b64.encodedLen(n)) >= n, "bound holds");
    }

    if (g_fail == 0) {
        std.io.write("base64 decodedLen ok\n");
    } else {
        std.io.write("base64 decodedLen FAIL\n");
    }
}
