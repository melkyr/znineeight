// stdlib_parse_parseuint64_xmod — STDLIB std_parse (L5) parseUint64 fixture.
//
// Contract (blueprint §3 L5): parseUint64(s) ?u64. Parsing rejects whitespace,
// '+' and underscores; a leading '-' is malformed; null on overflow or malformed.
//
// GREEN: deterministic stdout `parse uint64 ok\n` (RUNRC=0).
const std = @import("std");
const parse = @import("std_parse.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn wantU64(s: []const u8, want: u64, what: []const u8) void {
    var got = parse.parseUint64(s);
    if (got) |v| {
        ck(v == want, what);
    } else {
        ck(false, what);
    }
}

fn wantNull(s: []const u8, what: []const u8) void {
    var got = parse.parseUint64(s);
    if (got == null) {
        ck(true, what);
    } else {
        ck(false, what);
    }
}

pub fn main() void {
    wantU64("0", 0, "zero");
    wantU64("42", 42, "42");
    wantU64("007", 7, "leading zeros");
    wantU64("18446744073709551615", @intCast(u64, 0xFFFFFFFFFFFFFFFF), "u64 max");

    wantNull("", "empty");
    wantNull("-1", "neg");
    wantNull("-0", "neg zero");
    wantNull("+1", "plus");
    wantNull(" 1", "leading space");
    wantNull("1 ", "trailing space");
    wantNull("1_0", "underscore");
    wantNull("x", "alpha");
    wantNull("18446744073709551616", "overflow");

    if (g_fail == 0) {
        std.io.write("parse uint64 ok\n");
    } else {
        std.io.write("parse uint64 FAIL\n");
    }
}
