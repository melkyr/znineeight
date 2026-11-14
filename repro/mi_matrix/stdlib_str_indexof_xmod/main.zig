// stdlib_str_indexof_xmod — std_str.indexOf (L2) GREEN fixture.
//
// Contract (blueprint §3 L2): `indexOf(s, needle) ?usize` returns the first
// index of `needle` in `s`, or null. An empty needle matches at index 0; a
// needle longer than `s` never matches. Overlap is not considered (first match
// wins at its leftmost start).
//
// Cases pinned (orelse 999 is the null sentinel):
//   ("hello world", "world") -> 6
//   ("hello",       "z")     -> null -> 999
//   ("hello",       "")      -> 0
//   ("aaa",         "aa")    -> 0
//   ("abc",         "abcd")  -> null -> 999
//   ("abcabc",      "bc")    -> 1
//   ("abcabc",      "c")     -> 2
//   ("",            "")      -> 0
//   ("",            "a")     -> null -> 999
//
// GREEN (contract): deterministic byte-exact stdout `str indexof ok\n`.
const std = @import("std");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn at(s: []const u8, needle: []const u8) usize {
    return std.str.indexOf(s, needle) orelse 999;
}

pub fn main() void {
    var s1: []const u8 = "hello world";
    ck(at(s1, "world") == 6, "world");

    var s2: []const u8 = "hello";
    ck(at(s2, "z") == 999, "missing");

    ck(at(s2, "") == 0, "empty needle");

    var s3: []const u8 = "aaa";
    ck(at(s3, "aa") == 0, "overlap");

    var s4: []const u8 = "abc";
    ck(at(s4, "abcd") == 999, "needle longer");

    var s5: []const u8 = "abcabc";
    ck(at(s5, "bc") == 1, "bc first");
    ck(at(s5, "c") == 2, "c first");

    var s6: []const u8 = "";
    ck(at(s6, "") == 0, "empty empty");
    ck(at(s6, "a") == 999, "empty missing");

    std.io.write("str indexof ok\n");
}
