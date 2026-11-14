// stdlib_str_splitonce_xmod — std_str.splitOnce GREEN fixture.
//
// Contract: `splitOnce(s, sep, out)` splits `s` on the FIRST `sep` byte into
// slices INTO `s` (views; nothing is allocated or copied). It returns true and
// fills `out.first` / `out.second` when a separator is present, and returns
// false (leaving `out` untouched) when there is none.
//
// Shape note: the planned `?[2][]const u8` return shape dumps but its emitted
// C assigns an array value (`zT = ...value`), which gcc rejects with
// "assignment to expression with array type". The brief's approved fallback is
// used: the 2-field out-param struct `SplitOnce { first, second }` plus a bool
// found result.
//
// Cases pinned (first separator only):
//   "a=b"    '=' -> true  "a" / "b"
//   "a=b=c"  '=' -> true  "a" / "b=c"
//   "=b"     '=' -> true  ""  / "b"    (leading separator)
//   "a="     '=' -> true  "a" / ""     (trailing separator)
//   "="      '=' -> true  ""  / ""
//   "abc"    '=' -> false (no separator)
//   ""       '=' -> false (empty input)
//
// GREEN (contract): deterministic byte-exact stdout `str splitonce ok\n`
// (RUNRC=0).
const std = @import("std");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.str.eql(a, b);
}

pub fn main() void {
    var out: std.str.SplitOnce = undefined;

    var s1: []const u8 = "a=b";
    ck(std.str.splitOnce(s1, '=', &out), "a=b found");
    ck(eq(out.first, "a"), "a=b first");
    ck(eq(out.second, "b"), "a=b second");

    var s2: []const u8 = "a=b=c";
    ck(std.str.splitOnce(s2, '=', &out), "a=b=c found");
    ck(eq(out.first, "a"), "a=b=c first");
    ck(eq(out.second, "b=c"), "a=b=c second keeps rest");

    var s3: []const u8 = "=b";
    ck(std.str.splitOnce(s3, '=', &out), "=b found");
    ck(eq(out.first, ""), "=b first empty");
    ck(eq(out.second, "b"), "=b second");

    var s4: []const u8 = "a=";
    ck(std.str.splitOnce(s4, '=', &out), "a= found");
    ck(eq(out.first, "a"), "a= first");
    ck(eq(out.second, ""), "a= second empty");

    var s5: []const u8 = "=";
    ck(std.str.splitOnce(s5, '=', &out), "= found");
    ck(eq(out.first, ""), "= first empty");
    ck(eq(out.second, ""), "= second empty");

    var s6: []const u8 = "abc";
    ck(!std.str.splitOnce(s6, '=', &out), "abc no separator");

    var s7: []const u8 = "";
    ck(!std.str.splitOnce(s7, '=', &out), "empty no separator");

    std.io.write("str splitonce ok\n");
}
