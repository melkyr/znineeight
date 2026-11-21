// stdlib_str_trimright_xmod — std_str.trimRight (L2) GREEN fixture.
//
// Contract (blueprint §3 L2): `trimRight(s, chars)` strips any trailing byte
// that is present in the `chars` set and returns a view into `s`. An empty
// `chars` set strips nothing.
//
// Cases pinned:
//   ("xxabcxx", "x")   -> "xxabc"
//   ("abc",     "x")   -> "abc"   (no trailing match)
//   ("baaa",    "a")   -> "b"
//   ("",        "x")   -> ""
//   ("abcxyz",  "xyz") -> "abc"   (chars is a SET)
//   ("a  ",     " ")   -> "a"
//   ("abc",     "")    -> "abc"   (empty set strips nothing)
//
// GREEN (contract): deterministic byte-exact stdout `str trimright ok\n`.
const std = @import("std");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.str.eql(a, b);
}

pub fn main() void {
    var x: []const u8 = "x";
    var xyz: []const u8 = "xyz";
    var sp: []const u8 = " ";
    var none: []const u8 = "";

    var s1: []const u8 = "xxabcxx";
    ck(eq(std.str.trimRight(s1, x), "xxabc"), "xxabcxx");

    var s2: []const u8 = "abc";
    ck(eq(std.str.trimRight(s2, x), "abc"), "no match");

    var s3: []const u8 = "baaa";
    ck(eq(std.str.trimRight(s3, "a"), "b"), "baaa");

    var s4: []const u8 = "";
    ck(eq(std.str.trimRight(s4, x), ""), "empty input");

    var s5: []const u8 = "abcxyz";
    ck(eq(std.str.trimRight(s5, xyz), "abc"), "set semantics");

    var s6: []const u8 = "a  ";
    ck(eq(std.str.trimRight(s6, sp), "a"), "space");

    var s7: []const u8 = "abc";
    ck(eq(std.str.trimRight(s7, none), "abc"), "empty set");

    std.io.write("str trimright ok\n");
}
