// stdlib_parse_itoa_xmod — STDLIB std_parse (L5) itoa GREEN fixture.
//
// Contract (blueprint §3 L5): itoa(buf, v) []u8. Writes backwards from buf's
// end; the returned slice points into buf. No allocation, no errors.
//
// GREEN: deterministic stdout `itoa ok\n` (RUNRC=0).
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

    r = parse.itoa(buf[0..], 0);
    ckBytes(r, "0", "itoa 0");

    r = parse.itoa(buf[0..], 42);
    ckBytes(r, "42", "itoa 42");
    ck(buf[31] == '2', "itoa writes from end");

    r = parse.itoa(buf[0..], -42);
    ckBytes(r, "-42", "itoa -42");

    r = parse.itoa(buf[0..], 1000);
    ckBytes(r, "1000", "itoa 1000");

    r = parse.itoa(buf[0..], 2147483647);
    ckBytes(r, "2147483647", "itoa i32 max");

    r = parse.itoa(buf[0..], -2147483647 - 1);
    ckBytes(r, "-2147483648", "itoa i32 min");

    if (g_fail == 0) {
        std.io.write("itoa ok\n");
    } else {
        std.io.write("itoa FAIL\n");
    }
}
