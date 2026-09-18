// stdlib_parse_itoa64_xmod — STDLIB std_parse (L5) itoa64 GREEN fixture.
//
// Contract (blueprint §3 L5): itoa64(buf, v) []u8. Writes backwards from buf's
// end; the returned slice points into buf. No allocation, no errors.
//
// GREEN: deterministic stdout `itoa64 ok\n` (RUNRC=0).
const std = @import("std");
const parse = @import("std_parse.zig");

const I64_MIN: i64 = @bitCast(i64, @intCast(u64, 0x8000000000000000));

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

    r = parse.itoa64(buf[0..], 0);
    ckBytes(r, "0", "itoa64 0");

    r = parse.itoa64(buf[0..], 42);
    ckBytes(r, "42", "itoa64 42");
    ck(buf[31] == '2', "itoa64 writes from end");

    r = parse.itoa64(buf[0..], -42);
    ckBytes(r, "-42", "itoa64 -42");

    r = parse.itoa64(buf[0..], @intCast(i64, 0x7FFFFFFFFFFFFFFF));
    ckBytes(r, "9223372036854775807", "itoa64 i64 max");

    r = parse.itoa64(buf[0..], I64_MIN);
    ckBytes(r, "-9223372036854775808", "itoa64 i64 min");

    if (g_fail == 0) {
        std.io.write("itoa64 ok\n");
    } else {
        std.io.write("itoa64 FAIL\n");
    }
}
