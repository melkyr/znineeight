// stdlib_parse_parseuint_xmod — STDLIB std_parse (L5) parseUint GREEN fixture.
//
// Contract (blueprint §3 L5): parseUint(s) ?u32. Parsing rejects whitespace, '+'
// and underscores; a leading '-' is malformed; null on overflow or malformed.
//
// GREEN: deterministic stdout `parse uint ok\n` (RUNRC=0).
const std = @import("std");
const parse = @import("std_parse.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn wantU32(s: []const u8, want: u32, what: []const u8) void {
    var got = parse.parseUint(s);
    if (got) |v| {
        ck(v == want, what);
    } else {
        ck(false, what);
    }
}

fn wantNull(s: []const u8, what: []const u8) void {
    var got = parse.parseUint(s);
    if (got == null) {
        ck(true, what);
    } else {
        ck(false, what);
    }
}

pub fn main() void {
    wantU32("0", 0, "zero");
    wantU32("42", 42, "42");
    wantU32("007", 7, "leading zeros");
    wantU32("4294967295", 4294967295, "u32 max");

    wantNull("", "empty");
    wantNull("-1", "neg");
    wantNull("-0", "neg zero");
    wantNull("+1", "plus");
    wantNull(" 1", "leading space");
    wantNull("1 ", "trailing space");
    wantNull("1_0", "underscore");
    wantNull("abc", "alpha");
    wantNull("1a", "trailing alpha");
    wantNull("4294967296", "overflow");

    if (g_fail == 0) {
        std.io.write("parse uint ok\n");
    } else {
        std.io.write("parse uint FAIL\n");
    }
}
