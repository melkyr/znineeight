// stdlib_parse_parseint64_xmod — STDLIB std_parse (L5) parseInt64 GREEN fixture.
//
// Contract (blueprint §3 L5): parseInt64(s) ?i64. Parsing rejects whitespace,
// '+' and underscores; null on overflow or malformed.
//
// GREEN: deterministic stdout `parse int64 ok\n` (RUNRC=0).
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

fn wantI64(s: []const u8, want: i64, what: []const u8) void {
    var got = parse.parseInt64(s);
    if (got) |v| {
        ck(v == want, what);
    } else {
        ck(false, what);
    }
}

fn wantNull(s: []const u8, what: []const u8) void {
    var got = parse.parseInt64(s);
    if (got == null) {
        ck(true, what);
    } else {
        ck(false, what);
    }
}

pub fn main() void {
    wantI64("0", 0, "zero");
    wantI64("42", 42, "42");
    wantI64("-42", -42, "neg 42");
    wantI64("007", 7, "leading zeros");
    wantI64("-0", 0, "neg zero");
    wantI64("9223372036854775807", @intCast(i64, 0x7FFFFFFFFFFFFFFF), "i64 max");
    wantI64("-9223372036854775808", I64_MIN, "i64 min");

    wantNull("", "empty");
    wantNull("+1", "plus");
    wantNull(" 1", "leading space");
    wantNull("1 ", "trailing space");
    wantNull("1_0", "underscore");
    wantNull("x", "alpha");
    wantNull("9223372036854775808", "overflow max");
    wantNull("-9223372036854775809", "overflow min");

    if (g_fail == 0) {
        std.io.write("parse int64 ok\n");
    } else {
        std.io.write("parse int64 FAIL\n");
    }
}
