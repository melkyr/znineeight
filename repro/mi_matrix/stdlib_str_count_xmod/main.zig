// stdlib_str_count_xmod — std_str.count (L2) GREEN fixture.
//
// Contract (blueprint §3 L2): `count(s, needle) usize` counts the occurrences
// of the byte `needle` in `s`.
//
// Cases pinned:
//   ("hello",  'l') -> 2
//   ("hello",  'z') -> 0
//   ("",       'a') -> 0
//   ("aaa",    'a') -> 3
//   ("banana", 'a') -> 3
//
// GREEN (contract): deterministic byte-exact stdout `str count ok\n`.
const std = @import("std");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    var s1: []const u8 = "hello";
    ck(std.str.count(s1, 'l') == 2, "hello l");
    ck(std.str.count(s1, 'z') == 0, "hello z");

    var s2: []const u8 = "";
    ck(std.str.count(s2, 'a') == 0, "empty");

    var s3: []const u8 = "aaa";
    ck(std.str.count(s3, 'a') == 3, "aaa");

    var s4: []const u8 = "banana";
    ck(std.str.count(s4, 'a') == 3, "banana");

    std.io.write("str count ok\n");
}
