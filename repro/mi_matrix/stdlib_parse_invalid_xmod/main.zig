// stdlib_parse_invalid_xmod — STDLIB std_parse (L5) malformed-input
// expected-failure probe (Plan C hardening Task 3).
//
// Contract (sf/src/std_parse.zig:1-6 + each parser): the numeric parsers are
// total and never trap. A malformed input — empty, whitespace, '+', an
// underscore, a stray alpha, a bare/double sign, trailing junk, or an
// out-of-range magnitude — returns `null` (not an error, not a trap).
// `parseFloat` additionally rejects a value that overflows to +/-inf.
//
// This probe drives every parser's documented malformed-input path. Each call
// is expected to yield `null`; a parser that instead returns a value, traps, or
// hangs FAILS the probe. Because the failure is reported in-process (not by a
// signal) the process exits cleanly (rc 0) on the expected path.
//
// GREEN (contract): deterministic byte-exact stdout `parse invalid ok\n` (rc 0).
const std = @import("std");
const parse = @import("std_parse.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn i32Null(s: []const u8, what: []const u8) void {
    ck(parse.parseInt(s) == null, what);
}

fn u32Null(s: []const u8, what: []const u8) void {
    ck(parse.parseUint(s) == null, what);
}

fn i64Null(s: []const u8, what: []const u8) void {
    ck(parse.parseInt64(s) == null, what);
}

fn u64Null(s: []const u8, what: []const u8) void {
    ck(parse.parseUint64(s) == null, what);
}

fn f64Null(s: []const u8, what: []const u8) void {
    ck(parse.parseFloat(s) == null, what);
}

pub fn main() void {
    var empty: []const u8 = "";

    // parseInt: malformed / overflow -> null.
    i32Null(empty, "i32 empty");
    i32Null("+5", "i32 plus");
    i32Null(" 5", "i32 leading space");
    i32Null("5 ", "i32 trailing space");
    i32Null("1_0", "i32 underscore");
    i32Null("abc", "i32 alpha");
    i32Null("1a", "i32 trailing alpha");
    i32Null("-", "i32 bare minus");
    i32Null("--1", "i32 double minus");
    i32Null("2147483648", "i32 overflow max");
    i32Null("-2147483649", "i32 overflow min");
    i32Null("00x", "i32 trailing junk");

    // parseUint: malformed / overflow / sign -> null.
    u32Null(empty, "u32 empty");
    u32Null("-1", "u32 minus");
    u32Null("+1", "u32 plus");
    u32Null("1 2", "u32 embedded space");
    u32Null("12_3", "u32 underscore");
    u32Null("xyz", "u32 alpha");
    u32Null("4294967296", "u32 overflow");

    // parseInt64: malformed / overflow -> null.
    i64Null(empty, "i64 empty");
    i64Null("-", "i64 bare minus");
    i64Null("9223372036854775808", "i64 overflow max");
    i64Null("-9223372036854775809", "i64 overflow min");
    i64Null("1e3", "i64 exponent");

    // parseUint64: malformed / overflow -> null.
    u64Null(empty, "u64 empty");
    u64Null("-5", "u64 minus");
    u64Null("18446744073709551616", "u64 overflow");
    u64Null("0x10", "u64 hex");

    // parseFloat: malformed / overflow -> null.
    f64Null(empty, "f64 empty");
    f64Null("-", "f64 bare minus");
    f64Null("abc", "f64 alpha");
    f64Null("1.2.3", "f64 double dot");
    f64Null("1e", "f64 bare exponent");
    f64Null(" 1.0", "f64 leading space");
    f64Null("1.0 ", "f64 trailing space");
    f64Null("1_000", "f64 underscore");

    if (g_fail == 0) {
        std.io.write("parse invalid ok\n");
    } else {
        std.io.write("parse invalid FAIL\n");
    }
}
