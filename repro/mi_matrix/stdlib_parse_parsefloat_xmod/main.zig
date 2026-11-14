// stdlib_parse_parsefloat_xmod — STDLIB std_parse (L5) parseFloat GREEN fixture.
//
// Contract (blueprint §3 L5): parseFloat(s) ?f64. Parsing rejects whitespace,
// '+' and underscores; null on overflow or malformed. This module accepts a
// plain decimal (optional '-', digits, at most one '.', digits); exponent
// notation is malformed.
//
// GREEN: deterministic stdout `parse float ok\n` (RUNRC=0).
const std = @import("std");
const parse = @import("std_parse.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn wantF64(s: []const u8, want: f64, what: []const u8) void {
    var got = parse.parseFloat(s);
    if (got) |v| {
        var d = v - want;
        if (d < 0.0) d = -d;
        ck(d < 0.0000001, what);
    } else {
        ck(false, what);
    }
}

fn wantNull(s: []const u8, what: []const u8) void {
    var got = parse.parseFloat(s);
    if (got == null) {
        ck(true, what);
    } else {
        ck(false, what);
    }
}

pub fn main() void {
    wantF64("0", 0.0, "zero");
    wantF64("0.0", 0.0, "zero point zero");
    wantF64("2", 2.0, "int");
    wantF64("-2", -2.0, "neg int");
    wantF64("3.5", 3.5, "3.5");
    wantF64("-3.5", -3.5, "-3.5");
    wantF64(".5", 0.5, "leading dot");
    wantF64("-.5", -0.5, "neg leading dot");
    wantF64("0.25", 0.25, "0.25");
    wantF64("123.456", 123.456, "123.456");
    wantF64("1.", 1.0, "trailing dot");

    wantNull("", "empty");
    wantNull("+1", "plus");
    wantNull(" 1", "leading space");
    wantNull("1 ", "trailing space");
    wantNull("1_0", "underscore");
    wantNull("abc", "alpha");
    wantNull("1.2.3", "two dots");
    wantNull("1e3", "exponent");
    wantNull(".", "bare dot");
    wantNull("-", "bare minus");

    if (g_fail == 0) {
        std.io.write("parse float ok\n");
    } else {
        std.io.write("parse float FAIL\n");
    }
}
