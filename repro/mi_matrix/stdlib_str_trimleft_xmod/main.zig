// stdlib_str_trimleft_xmod — std_str.trimLeft (L2) GREEN fixture.
//
// Contract (blueprint §3 L2): `trimLeft(s, chars)` strips any leading byte that
// is present in the `chars` set and returns a view into `s`. An empty `chars`
// set strips nothing.
//
// Cases pinned:
//   ("xxabcxx", "x")  -> "abcxx"
//   ("abc",     "x")  -> "abc"    (no leading match)
//   ("aaab",    "a")  -> "b"
//   ("",        "x")  -> ""
//   ("xyx",     "xy") -> ""       (chars is a SET)
//   ("  a",     " ")  -> "a"
//   ("abc",     "")   -> "abc"    (empty set strips nothing)
//
// GREEN (contract): deterministic byte-exact stdout `str trimleft ok\n`.
const std = @import("std");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.str.eql(a, b);
}

pub fn main() void {
    var x: []const u8 = "x";
    var xy: []const u8 = "xy";
    var sp: []const u8 = " ";
    var none: []const u8 = "";

    var s1: []const u8 = "xxabcxx";
    ck(eq(std.str.trimLeft(s1, x), "abcxx"), "xxabcxx");

    var s2: []const u8 = "abc";
    ck(eq(std.str.trimLeft(s2, x), "abc"), "no match");

    var s3: []const u8 = "aaab";
    ck(eq(std.str.trimLeft(s3, "a"), "b"), "aaab");

    var s4: []const u8 = "";
    ck(eq(std.str.trimLeft(s4, x), ""), "empty input");

    var s5: []const u8 = "xyx";
    ck(eq(std.str.trimLeft(s5, xy), ""), "set semantics");

    var s6: []const u8 = "  a";
    ck(eq(std.str.trimLeft(s6, sp), "a"), "space");

    var s7: []const u8 = "abc";
    ck(eq(std.str.trimLeft(s7, none), "abc"), "empty set");

    std.io.write("str trimleft ok\n");
}
