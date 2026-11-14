// stdlib_parse_utoa_xmod — STDLIB std_parse (L5) utoa GREEN fixture.
//
// Contract (blueprint §3 L5): utoa(buf, v) []u8. Writes backwards from buf's
// end; the returned slice points into buf. No allocation, no errors.
//
// GREEN: deterministic stdout `utoa ok\n` (RUNRC=0).
const std = @import("std");
const parse = @import("std_parse.zig");

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
    var buf: [32]u8 = undefined;
    var r: []u8 = undefined;

    r = parse.utoa(buf[0..], 0);
    ckBytes(r, "0", "utoa 0");

    r = parse.utoa(buf[0..], 42);
    ckBytes(r, "42", "utoa 42");
    ck(buf[31] == '2', "utoa writes from end");

    r = parse.utoa(buf[0..], 1000);
    ckBytes(r, "1000", "utoa 1000");

    r = parse.utoa(buf[0..], 4294967295);
    ckBytes(r, "4294967295", "utoa u32 max");

    if (g_fail == 0) {
        std.io.write("utoa ok\n");
    } else {
        std.io.write("utoa FAIL\n");
    }
}
