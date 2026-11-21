// stdlib_str_lastindexof_xmod — std_str.lastIndexOf (L2) GREEN fixture.
//
// Contract (blueprint §3 L2): `lastIndexOf(s, needle) ?usize` returns the last
// index of `needle` in `s`, or null. An empty needle matches at `s.len` (the
// position just past the end); a needle longer than `s` never matches.
//
// Cases pinned (orelse 999 is the null sentinel):
//   ("abcabc", "bc")   -> 4
//   ("hello",  "z")    -> null -> 999
//   ("hello",  "")     -> 5        (s.len)
//   ("aaa",    "aa")   -> 1        (overlap at the last start)
//   ("abc",    "abcd") -> null -> 999
//   ("abcabc", "c")    -> 5
//   ("",       "")     -> 0
//   ("",       "a")    -> null -> 999
//   ("hello",  "h")    -> 0
//
// GREEN (contract): deterministic byte-exact stdout `str lastindexof ok\n`.
const std = @import("std");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn at(s: []const u8, needle: []const u8) usize {
    return std.str.lastIndexOf(s, needle) orelse 999;
}

pub fn main() void {
    var s1: []const u8 = "abcabc";
    ck(at(s1, "bc") == 4, "bc last");
    ck(at(s1, "c") == 5, "c last");

    var s2: []const u8 = "hello";
    ck(at(s2, "z") == 999, "missing");
    ck(at(s2, "") == 5, "empty needle");
    ck(at(s2, "h") == 0, "first char");

    var s3: []const u8 = "aaa";
    ck(at(s3, "aa") == 1, "overlap last");

    var s4: []const u8 = "abc";
    ck(at(s4, "abcd") == 999, "needle longer");

    var s5: []const u8 = "";
    ck(at(s5, "") == 0, "empty empty");
    ck(at(s5, "a") == 999, "empty missing");

    std.io.write("str lastindexof ok\n");
}
