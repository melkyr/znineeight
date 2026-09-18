// stdlib_parse_parseint_xmod — STDLIB std_parse (L5) parseInt GREEN fixture.
//
// std_parse.zig is a PURE (no imports, no allocation) Z98 module; this fixture
// imports it by module basename (the compiler's lib search path binds the
// canonical <exe>/lib std_parse.zig).
//
// Contract (blueprint §3 L5): parseInt(s) ?i32. Parsing rejects whitespace, '+'
// and underscores; null on overflow or malformed.
//
// GREEN: deterministic stdout `parse int ok\n` (RUNRC=0).
const std = @import("std");
const parse = @import("std_parse.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn wantI32(s: []const u8, want: i32, what: []const u8) void {
    var got = parse.parseInt(s);
    if (got) |v| {
        ck(v == want, what);
    } else {
        ck(false, what);
    }
}

fn wantNull(s: []const u8, what: []const u8) void {
    var got = parse.parseInt(s);
    if (got == null) {
        ck(true, what);
    } else {
        ck(false, what);
    }
}

pub fn main() void {
    wantI32("0", 0, "zero");
    wantI32("42", 42, "42");
    wantI32("-42", -42, "neg 42");
    wantI32("007", 7, "leading zeros");
    wantI32("-0", 0, "neg zero");
    wantI32("2147483647", 2147483647, "i32 max");
    wantI32("-2147483648", -2147483647 - 1, "i32 min");

    wantNull("", "empty");
    wantNull("+5", "plus");
    wantNull(" 5", "leading space");
    wantNull("5 ", "trailing space");
    wantNull("1_0", "underscore");
    wantNull("abc", "alpha");
    wantNull("1a", "trailing alpha");
    wantNull("-", "bare minus");
    wantNull("--1", "double minus");
    wantNull("2147483648", "overflow max");
    wantNull("-2147483649", "overflow min");
    wantNull("00x", "trailing junk");

    if (g_fail == 0) {
        std.io.write("parse int ok\n");
    } else {
        std.io.write("parse int FAIL\n");
    }
}
